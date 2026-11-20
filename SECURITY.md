# Security Policy

## Supported version

Security fixes are applied to the latest commit on `main`. Older source builds
are not maintained separately.

## Reporting a vulnerability

Please use GitHub's **Security → Report a vulnerability** flow when it is
available. Do not include credentials, tokens, private paths, transcripts or
other sensitive data in a public issue. If private reporting is unavailable,
contact the maintainer through the GitHub profile before sharing technical
details.

## Local trust boundary

QuotaBar is a local menu-bar application with no hosted backend. It launches
the locally installed Codex and Claude Code CLIs under the current macOS user.
It does not request elevated privileges and does not read provider credential
files directly.

Connecting Claude Code updates `~/.claude/settings.json` so Claude's status
line invokes QuotaBar's bridge. An existing status-line object is backed up and
restored on disconnect. The bridge forwards the original status-line JSON to
the user's pre-existing command because that command already received the same
input before QuotaBar was installed.

QuotaBar persists only the general five-hour and seven-day percentages, reset
timestamps and optional model display name. It deliberately discards working
directories, transcript paths, account data and unrecognized fields. Its local
support directory is owner-only (`0700`); persisted files are owner-only
(`0600`).

## Distribution

The included installer creates an ad-hoc signed app for local use. It is not an
Apple-notarized distribution. Build only from a trusted checkout and review
changes before running the installer.
