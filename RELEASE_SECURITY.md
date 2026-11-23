# CHEXX Windows updates – release security

This repository is the public **CHEXX-only** release feed used by the installed Windows application. It is separate from Charli FPS.

A release becomes eligible for one-click updates only after verification. An eligible stable release must contain exactly:

- `CHEXX Setup X.Y.Z.exe` (Windows x64 NSIS installer)
- `CHEXX Setup X.Y.Z.exe.sha256` (matching 64-character SHA-256 digest)
- Release notes, a source-code and license compliance archive, and QA information.

CHEXX checks owner, repository, release version, expected installer name, file size and SHA-256 before starting any installer. The UI displays a large **red mandatory backup warning**, requires a locally verified user-data backup, and requires explicit user acknowledgement before any installation. The Electron main process enforces this independently of the UI.

Private user profiles, PocketBase keys and original non-redistributable audio must never be uploaded. No release should be marked complete unless the binary and its metadata are actually available on GitHub.

The original CHEXX project remains in a separate private repository.