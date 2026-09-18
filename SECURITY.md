# Security and privacy

The launcher manages local profile metadata and launches the installed application. It does not read authentication file contents, collect passwords, send analytics, or provide a remote service.

Credentials written by Codex may be plaintext files inside a private profile directory. Never attach that directory, `auth.json`, full login logs, browser storage, or token values to an issue.

The launcher provides state separation within one macOS user. It is not a security boundary against other software running as that user. Organization policy and system-level integrations can still apply across profiles.

For a vulnerability, use the repository’s private **Report a vulnerability** feature when enabled. If it is unavailable, open a minimal issue asking for a private contact without including exploit details or secrets. Maintainers should enable private vulnerability reporting before public release.
