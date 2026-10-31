# Security

Clipboard history may contain sensitive information. Please do not attach a real
history database, clipboard dump, password, token, or private screenshot to an issue.

For a vulnerability, use the repository's **Security → Report a vulnerability**
option when available. If private reporting is unavailable, open an issue asking
for a private reporting channel without including exploit details or sensitive data.

Only the latest source version is maintained. There is no guaranteed response time.

## Security boundaries

- History is local and protected by account-level file permissions, not separate
  application encryption.
- Password filtering depends on source-app markers and Secure Input; it cannot
  identify every secret.
- Accessibility permission is optional and granted explicitly by the user.
- Local and CI development builds are ad-hoc signed. Public distribution binaries
  should be Developer ID signed and notarized.
- Build and test workflows do not require production secrets or write access to
  the repository.

See [privacy](PRIVACY.md) and [release signing](docs/RELEASING.md).
