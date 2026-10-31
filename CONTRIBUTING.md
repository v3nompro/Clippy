# Contributing

Keep Clippy small, native, and focused on retrieving clipboard history. Changes
should preserve offline operation and avoid unnecessary dependencies.

## Local setup

Use macOS 13+ and Swift 5.9+ from Command Line Tools or Xcode.

```sh
./scripts/check.sh
./scripts/build.sh
open -n dist/Clippy.app --args --preview
```

The check runner uses SQLite and temporary private pasteboards. Never add tests,
screenshots, or logs containing a real clipboard, account data, or credentials.

If your development environment blocks SwiftPM's nested build sandbox, the scripts
accept additional SwiftPM arguments, including `--disable-sandbox`. This changes
the build process, not the app's permissions.

## Pull requests

- Describe the problem, the resulting behavior, and how it was verified.
- Add regression coverage for changed storage, filtering, and paste behavior.
- Run the core checks and release build before opening the pull request.
- Check UI changes with sample content in preview mode.
- Preserve destination-app checks, modifier-release handling, and cancellation.
- Keep credentials, clipboard databases, build products, and signing certificates
  outside version control.

The CI workflow checks Apple Silicon and Intel builds. See [testing](docs/TESTING.md)
for the manual matrix and [releasing](docs/RELEASING.md) for signing requirements.
