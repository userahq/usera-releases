# usera releases

The usera agent: `usera` (the CLI) and `userad` (the on-device agent), one tarball per platform and architecture with `SHA256SUMS`, published from the private [usera-app](https://github.com/userahq/usera-app) repository.

- **macOS** (Apple silicon and Intel): `usera`, `userad` and `Usera.app`, the menu bar item. Network visibility through the filter extension.
- **Linux** (x64 and arm64, from v0.1.3): `usera` and `userad`. Hooks only — the agent sees Claude Code, Codex and Cursor through their hooks, with findings and policy decisions, and not the network. Installs as a systemd user unit; on a machine nobody logs into, `loginctl enable-linger` keeps it running.
- **Windows**: planned.

Install or update:

```sh
curl -fsSL https://raw.githubusercontent.com/userahq/usera-releases/main/install.sh | sh
```

Already installed: `usera update` (`--check` only reports).

Verify a download by hand: `sha256sum -c SHA256SUMS --ignore-missing` (macOS: `shasum -a 256 -c SHA256SUMS --ignore-missing`).
