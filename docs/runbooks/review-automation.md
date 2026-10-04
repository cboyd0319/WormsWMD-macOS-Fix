# Automatic pull request reviews

Ready pull requests targeting `main` receive Balanced Copilot review and a
workflow-requested Codex Code Review. Maintainers own configuration, credential
rotation, and failed requests. These reviews supplement required checks and
human review; provider access, quotas, and service availability still apply.

## Configuration

| Control | Recorded configuration |
| --- | --- |
| GitHub ruleset | Active main-only ruleset [24433209](https://github.com/cboyd0319/WormsWMD-macOS-Fix/settings/rules/24433209); request Copilot on ready PRs, exclude drafts, no push re-review |
| Copilot effort | **Balanced**, verified in repository Copilot settings and review output |
| Codex native auto-review | **Follow personal preference**; owner's personal auto-review disabled |
| Codex workflow | [`codex-review.yml`](../../.github/workflows/codex-review.yml), installed on the default branch |
| Credential | Actions repository secret `CODEX_REVIEW_TOKEN`, belonging to a Codex-connected GitHub user |

Repository-wide native Codex auto-review has no target-branch filter in the
observed settings. Leave it disabled to preserve the requested `main` scope.
Native Security Review is separate: its completion does not prove that Codex
Code Review ran.

## Trigger behavior

| Event | Codex behavior |
| --- | --- |
| Open or reopen a ready PR into `main` | Request the current head |
| Mark a PR into `main` ready | Request the current head |
| Change the base to `main` while ready | Request the current head |
| Draft, closed PR, another target, or title/body edit | No request |
| Later push to an ordinary PR | No automatic request; comment `@codex review` manually |
| Dependabot PR CI completes | Request only its matching current revision; CI success is not required |

The Dependabot fallback exists because its own PR events cannot access the
Actions secret. It accepts only a completed `CI` PR run initiated by Dependabot
from this repository, associated with exactly one eligible Dependabot PR.
The immutable run `head_sha` must equal the current PR head; mutable associated
PR metadata cannot authorize a newer revision.

Both paths re-fetch PR eligibility after listing comments. A fixed request
contains `@codex review` and an HTML marker identifying PR number and full head
SHA. Deduplication trusts the authenticated user's numeric ID, not matching
text posted by another account. Per-PR concurrency serializes requests;
`queue: max` preserves pending runs, and ignored metadata edits use a separate
lane. A successful request job proves posting or deduplication, not completion
of an AI review.

## CI after merging

PRs keep the required `ShellCheck`, `Validate Scripts`, and `Zizmor` checks.
For a merge commit pushed to `main`, the Ubuntu CI job can reuse macOS validation
from the latest same-repository PR run completed successfully within 24 hours.
It requires the same workflow, successful Ubuntu and macOS jobs, and identical
Git trees for the PR head, recorded test commit, and final merge. The test commit
must have the same two parents as the final merge. Both runners check out the
immutable `github.sha` recorded in their checkout step names. Job completion
timestamps also bound reuse, including partial re-runs.

On a match, `Validate Scripts` is skipped and the Ubuntu log identifies its
source run ID and tree. Cheap checks and GitHub Security still execute. Direct
commits, squash/rebase merges, fork PRs, changed trees or parents, old workflows
without the recorded SHA, stale or unsuccessful runs, missing jobs, and API
errors take the normal path. Existing documentation-only path selection still
applies. Only `actions: read` is added; there are no artifacts, caches, write
tokens, or new credentials. PR validation and Codex's CI-completion trigger remain
active. Re-running only a failed job cannot turn skipped macOS work into proof.

To force a fresh macOS run, re-run the original PR workflow; PR events never reuse
validation. To disable reuse, remove the reuse step/output and the
`macos-reused` condition in `ci.yml`, retaining its existing path classifier.

## Credentials and trust boundary

Use a fine-grained user token scoped only to this repository, with **Pull
requests: Read and write** and required **Metadata: Read**. No account
permissions or Dependabot-secret copy are needed. Choose an expiration and
record a rotation reminder privately; this repository contains no token value
or exact expiry claim.

The workflow runs the SHA-pinned GitHub-owned `actions/github-script` from
trusted workflow source. Its `GITHUB_TOKEN` has no permissions. It performs no
checkout, artifact download, cache restore, or execution of PR-controlled text.
The user token is the narrowly scoped exception documented in
[Security](../../SECURITY.md#github-and-ci-controls).

## Rotate or recover

1. In the connected user's GitHub account, create a replacement fine-grained
   token with the scope above; keep its value out of issues, logs, and commits.
2. In repository **Settings > Secrets and variables > Actions**, replace
   `CODEX_REVIEW_TOKEN`.
3. Re-run a failed eligible request job, or use a ready PR whose current head
   has no existing marker from that user.
4. Confirm the workflow succeeds, the user-authored request appears, and the
   Codex summary shows **Code Review** completed for that exact head.
5. After verification, revoke the superseded credential.

| Symptom | Check and recovery |
| --- | --- |
| Job skipped | Check draft/open/base state, event type, and Dependabot run/head eligibility |
| Missing or rejected token | Restore the Actions secret, repository scope, permissions, expiry, and Codex-connected identity |
| Green job without a new comment | Check whether that user's marker already exists for the current SHA |
| Comment exists but no Code Review | Check Codex access/quota and summary; an eyes reaction or Security Review alone is insufficient |
| Review failed after posting | Re-running the workflow deduplicates; request a retry manually with `@codex review` |
| Summary says “Manual request” | Expected for the comment-based trigger, including comments posted automatically |

For containment, disable **Request Codex review** in Actions; if credentials
may be compromised, revoke the token. Copilot configuration is independent.
Before re-enabling, inspect the trusted workflow, credential scope, and an
eligible request.

The [October 2026 validation record](../release-records/2026-10-03-issues-30-31.md)
contains the live identity experiment, draft/ready checks, Dependabot proof,
review outcomes, and release evidence.
