# Release Incident Runbook

Use this runbook when a signing key, tag, workflow, attestation, or published
asset may be wrong or compromised. Preserve evidence first. Do not reuse a tag,
silently replace an asset, weaken verification, or bypass the protected release
environment merely to complete publication.

## Owners And Preconditions

- Incident owner: repository maintainer.
- Review owner: the configured `release` environment reviewer; use a second
  trusted CODEOWNER when one is available.
- Security reports containing exploit or credential details stay in a private
  GitHub security advisory.
- The `release` environment must have a required reviewer before the next tag.
  PR4 adds the workflow reference but does not change this credentialed setting.
  The sole maintainer may self-review until a second trusted maintainer exists;
  enable prevention after that. Publication fails unless the reviewer rule is
  present and nonempty.

## Signed Tag Preflight

Use an SSH-signed annotated tag from a clean, synchronized protected `main`:

```bash
git status --short --branch
git fetch origin main --tags
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
git config gpg.format ssh
git tag -s -a vX.Y.Z -m "WormsWMD macOS Fix vX.Y.Z"
git verify-tag vX.Y.Z
git merge-base --is-ancestor "vX.Y.Z^{commit}" origin/main
```

Before pushing, confirm required CI is green, the changelog section exists, the
tag and release do not already exist, and packaging/standalone/embedded Qt
provenance are byte-identical. The workflow independently repeats ancestry,
checksum, manifest, provenance, and SBOM verification.

## Suspected Signing-Key Loss Or Compromise

1. Do not create or push another tag with the affected key.
2. Record the last known-good signed tag and the key fingerprint without
   copying private key material.
3. Revoke or remove the compromised public-key authorization through the
   approved GitHub and signing-key process.
4. Configure and independently verify a replacement SSH signing key.
5. Publish a new higher patch version after normal review. Never delete and
   reuse the compromised version tag.

## Ruleset Or Environment Break-Glass

Use bypass only to contain an active incident, never to accelerate a release.
Require two-person approval when a second trusted maintainer exists. Otherwise,
name the exact rule/environment, reason, and duration, record the GitHub audit
event, and restore the protection immediately after the bounded action. Re-run
all required checks after protection is restored.

## Disable A Suspect Workflow

If release automation itself may be unsafe, disable it before investigating:

```bash
gh workflow disable release.yml
```

Preserve the workflow SHA and run evidence first when safe. Re-enable only
after a reviewed corrective PR reaches protected `main` and the environment,
permissions, and ancestry gates are revalidated.

## Preserve Evidence

Create an access-controlled incident directory outside the repository and save:

- tag object, tag commit, signer fingerprint, and `git verify-tag` output;
- workflow/run/job identifiers and downloaded logs;
- release asset names, sizes, SHA-256 values, SBOM, and attestations;
- packaging lock plus standalone and embedded provenance;
- timeline, approvals, observed impact, and every containment action.

Do not commit raw logs, credentials, private paths, or player data. Hash evidence
before moving it and retain the originals read-only according to the incident
owner's retention decision.

## Withdraw Or Correct A Release

Stop bootstrap/default-version promotion first. Preserve all evidence before any
withdrawal. If repository immutability prevents safe asset removal, leave the
historical evidence intact, mark the release as affected through the approved
GitHub process, and publish a higher corrective version. Never overwrite assets
under the same tag.

The public notice should state affected versions/assets, observable impact,
containment, verification commands, and the corrected release. Keep exploit,
credential, and private reporter details out of the notice. Link the corrective
release and its checksum, SBOM, and attestation evidence.

## Recovery Verification

- Release workflow source matches reviewed protected `main`.
- `release` environment approval and repository rules are restored.
- New annotated tag verifies and is an ancestor of `origin/main`.
- Downloaded assets pass checksum, manifest, provenance, SBOM, and attestation
  checks.
- Incident actions, residual risk, and follow-up owner are recorded.
