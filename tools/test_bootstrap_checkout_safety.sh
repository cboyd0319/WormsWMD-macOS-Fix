#!/bin/bash
# Exercise real bootstrap entrypoints against disposable local Git repositories.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
work=$(mktemp -d "${TMPDIR:-/tmp}/wormswmd-bootstrap-checkout.XXXXXX")
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

fail() { printf 'Bootstrap checkout safety failed: %s\n' "$*" >&2; exit 1; }
upstream="$work/upstream.git"
mkdir -p "$upstream" "$work/bin"
git -C "$upstream" -c core.hooksPath=/dev/null init -q
printf '#!/bin/bash\nprintf trusted > "$RUN_MARKER"\n' > "$upstream/fix_worms_wmd.sh"
chmod +x "$upstream/fix_worms_wmd.sh"
git -C "$upstream" add .
git -C "$upstream" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm fixture
release_ref=$(sed -nE 's/^DEFAULT_INSTALL_REF="([^"]*)"$/\1/p' "$ROOT_DIR/install.sh")
git -C "$upstream" tag "$release_ref"
pin=$(git -C "$upstream" rev-parse HEAD)
printf '#!/bin/bash\nexit 0\n' > "$work/bin/clear"
printf '#!/bin/bash\nprintf "Darwin\\n"\n' > "$work/bin/uname"
chmod +x "$work/bin/clear" "$work/bin/uname"

for entrypoint in install.sh "Install Fix.command"; do
    for scenario in fresh tampered wrong-pin wrong-remote clone-failure symlink locked publish-failure; do
        case_dir="$work/${entrypoint// /-}-$scenario"
        case_home="$case_dir/home with spaces"
        target="$case_home/.wormswmd-fix"
        mkdir -p "$case_home"
        expected_pin="$pin"
        [[ "$scenario" != wrong-pin ]] || expected_pin=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
        sed -E \
            -e "s|https://github.com/cboyd0319/WormsWMD-macOS-Fix|file://$work/upstream|g" \
            -e "s/^(DEFAULT_INSTALL_COMMIT|INSTALL_COMMIT)=.*/\1=\"$expected_pin\"/" \
            "$ROOT_DIR/$entrypoint" > "$case_dir/bootstrap.sh"

        if [[ "$scenario" != fresh ]]; then
            git -c core.hooksPath=/dev/null clone -q "file://$upstream" "$target"
            printf '#!/bin/bash\nprintf modified > "$DIRTY_MARKER"\n' > "$target/fix_worms_wmd.sh"
            printf 'keep user data\n' > "$target/untracked.txt"
            printf '#!/bin/bash\nprintf hook > "$HOOK_MARKER"\n' > "$target/.git/hooks/post-checkout"
            chmod +x "$target/.git/hooks/post-checkout"
            git -C "$target" config core.fsmonitor "$target/.git/hooks/post-checkout"
            if [[ "$scenario" == wrong-remote ]]; then
                git -C "$target" config remote.origin.url https://example.invalid/unrelated.git
            elif [[ "$scenario" == symlink ]]; then
                mv "$target" "$case_dir/original"
                ln -s "$case_dir/original" "$target"
            elif [[ "$scenario" == locked ]]; then
                mkdir "$target.bootstrap-lock"
            elif [[ "$scenario" == publish-failure ]]; then
                cat > "$work/bin/mv" <<'STUB'
#!/bin/bash
case "$1" in */checkout) exit 1 ;; esac
exec /bin/mv "$@"
STUB
                chmod +x "$work/bin/mv"
            elif [[ "$scenario" == clone-failure ]]; then
                mv "$upstream" "$work/unavailable.git"
            fi
        fi

        # The double-click entrypoint's final /dev/tty pause may fail in CI.
        # Assertions below inspect effects rather than masking script failures.
        result=0
        HOME="$case_home" INSTALL_DIR="$target" PATH="$work/bin:$PATH" \
            RUN_MARKER="$case_dir/ran" DIRTY_MARKER="$case_dir/dirty-ran" \
            HOOK_MARKER="$case_dir/hook-ran" \
            /bin/bash "$case_dir/bootstrap.sh" --dry-run > "$case_dir/output" 2>&1 || result=$?
        if [[ "$scenario" == clone-failure ]]; then
            mv "$work/unavailable.git" "$upstream"
        fi
        rm -f "$work/bin/mv"
        [[ ! -e "$case_dir/hook-ran" ]] || fail "$entrypoint/$scenario executed an existing hook or fsmonitor"
        [[ ! -e "$case_dir/dirty-ran" ]] || fail "$entrypoint/$scenario executed modified source"
        case "$scenario" in
            fresh|tampered)
                [[ -f "$case_dir/ran" ]] || fail "$entrypoint/$scenario did not run verified source (exit $result)"
                [[ "$(git -C "$target" rev-parse HEAD)" == "$pin" ]] || fail "wrong installed commit"
                [[ ! -e "$target/untracked.txt" ]] || fail "untracked content entered the new installation"
                if [[ "$scenario" == tampered ]]; then
                    preserved=$(find "$case_home" -path '*/previous/untracked.txt' -type f -print)
                    [[ -n "$preserved" ]] || fail "previous user files were not preserved"
                    [[ "$(cat "$preserved")" == 'keep user data' ]] || fail "previous user file changed"
                fi
                ;;
            *)
                [[ ! -e "$case_dir/ran" ]] || fail "$entrypoint/$scenario executed despite invalid input"
                [[ -f "$target/untracked.txt" ]] || fail "$entrypoint/$scenario lost existing user data"
                [[ "$(cat "$target/untracked.txt")" == 'keep user data' ]] || fail "existing data changed on failure"
                ;;
        esac
    done
done
printf 'Bootstrap checkout safety passed for both entrypoints.\n'
