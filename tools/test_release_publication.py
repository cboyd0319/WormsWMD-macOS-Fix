#!/usr/bin/env python3
"""Exercise the workflow's publication shell without a checkout or network."""

import json
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parent.parent
REPO = "owner/release-repo"
TAG = "v9.8.7"
ASSETS = [f"WormsWMD-macOS-Fix-{TAG}{suffix}"
          for suffix in (".zip", ".zip.sha256", ".cdx.json")]
MOCK_GH = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
state_file = pathlib.Path('state.json')
state = json.loads(state_file.read_text())
args = sys.argv[1:]
if os.environ.get('GH_REPO') != 'owner/release-repo':
    sys.exit('gh requires repository context outside a Git checkout')
state['calls'].append(args)
state_file.write_text(json.dumps(state))
if args[:2] == ['release', 'view']:
    if not state['exists']:
        sys.exit(1)
    if '--json' in args:
        field = args[args.index('--json') + 1]
        if field == 'isDraft':
            print(str(state['draft']).lower())
        elif field == 'assets':
            print('\n'.join(state['assets']))
        else:
            sys.exit('Unexpected release field')
elif args[:2] == ['release', 'create']:
    assert '--draft' in args and '--verify-tag' in args
    state.update(exists=True, draft=True)
elif args[:2] == ['release', 'upload']:
    state['assets'] = sorted(set(state['assets']) | {
        pathlib.Path(arg).name for arg in args[3:] if not arg.startswith('--')})
elif args[:2] == ['release', 'edit']:
    if '--draft=false' in args:
        state['draft'] = False
elif args[:1] == ['api']:
    assert args[1] == 'repos/owner/release-repo/git/ref/tags/v9.8.7'
    print(state['tag_object'])
else:
    sys.exit('Unexpected gh invocation: ' + repr(args))
state_file.write_text(json.dumps(state))
'''


class ReleasePublicationTests(unittest.TestCase):
    def run_publication(self, *, exists=False, draft=True, assets=(), moved=False):
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        step = workflow.split("      - name: Publish GitHub release assets\n", 1)[1]
        settings, shell = step.split("        run: |\n", 1)
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            (work / "build/release").mkdir(parents=True)
            for name in ASSETS + ["RELEASE_NOTES.md"]:
                (work / "build/release" / name).write_text("fixture\n")
            (work / "gh").write_text(MOCK_GH)
            (work / "gh").chmod(0o755)
            state_file = work / "state.json"
            state_file.write_text(json.dumps({
                "exists": exists, "draft": draft, "assets": list(assets),
                "tag_object": "moved" if moved else "verified-tag", "calls": [],
            }))
            # Explicit environment: no developer credentials or ambient GH_REPO.
            env = {"PATH": f"{work}:/usr/bin:/bin", "HOME": directory,
                   "RUNNER_TEMP": directory, "GITHUB_REPOSITORY": REPO,
                   "GITHUB_REF_NAME": TAG, "EXPECTED_TAG_OBJECT": "verified-tag"}
            if "          GH_REPO: ${{ github.repository }}\n" in settings:
                env["GH_REPO"] = REPO
            result = subprocess.run(
                ["/bin/bash", "-e", "-c", textwrap.dedent(shell)], cwd=work,
                env=env, capture_output=True, text=True, timeout=15,
            )
            self.assertFalse((work / ".git").exists())
            return result, json.loads(state_file.read_text())

    def test_create_and_resume_without_checkout(self):
        for exists in (False, True):
            with self.subTest(existing_draft=exists):
                result, state = self.run_publication(exists=exists)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(state["draft"])
                self.assertEqual(sorted(state["assets"]), sorted(ASSETS))

    def test_published_release_is_untouched(self):
        result, state = self.run_publication(exists=True, draft=False, assets=ASSETS)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Refusing to overwrite", result.stdout)
        self.assertTrue(all(call[:2] == ["release", "view"] for call in state["calls"]))

    def test_unexpected_asset_and_moved_tag_block_publication(self):
        for options, error in (({"assets": ["unexpected.txt"]}, "Unexpected release asset"),
                               ({"moved": True}, "Tag moved")):
            with self.subTest(options=options):
                result, state = self.run_publication(exists=True, **options)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(error, result.stdout)
                self.assertTrue(state["draft"])


if __name__ == "__main__":
    unittest.main()
