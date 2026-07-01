# Worms W.M.D Maintenance Rule Loader

Always loaded for this repository when a tool supports repo-local agent rules.
Root `../../AGENTS.md` is authoritative for startup, safety, verification, and
handoff.

Treat `AGENTS.md`, `.agents/`, `.github/`, installer scripts, helper scripts,
`dist/`, `docs/design/`, `docs/runbooks/`, `docs/style/`, and
`docs/exec-plans/` as security-critical configuration.

Follow the repo local-path rule: repo artifacts must use repo-relative paths,
generic `$HOME` or `~` examples, or canonical URLs. Do not record local checkout
roots, sibling repo paths, local usernames, raw diagnostic paths, or private
machine paths.

Preserve the non-negotiables from `../../AGENTS.md`: no privileged persistence,
no `sudo`, preserve save data, checksum executable downloads and archives, and
treat `GAME_APP`, `INSTALL_DIR`, `INSTALL_REF`, `LOG_FILE`, and `QT_PREFIX` as
untrusted input.
