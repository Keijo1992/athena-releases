# athena-releases

Build downloads for Athena, the shop's macOS diagnostics tool.

This repository holds **release attachments only** — no source code. Athena
checks it for new builds and updates itself on the USB stick it runs from,
including from Setup Assistant.

Each release contains:

- `Athena-<build>.zip` — the universal, ad-hoc signed app bundle
- `manifest.json` — version, download URL and SHA-256 checksum

Athena polls the permanent URL
`https://github.com/biofuze/athena-releases/releases/latest/download/manifest.json`,
which GitHub repoints at each new release. The checksum is what establishes a
build is intact: these bundles are ad-hoc signed, so Gatekeeper cannot tell a
good build from a tampered one.
