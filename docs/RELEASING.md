# Releasing

## Source releases and development builds

The repository can be built with Command Line Tools or Xcode. The default signing
identity is ad-hoc, suitable for local development. CI ZIPs are **development builds**,
not notarized end-user installers.

```sh
./scripts/check.sh
./scripts/package.sh
```

Packaging produces `dist/Clippy-<version>-<architecture>.zip` and a `.sha256` checksum.
The script uses the built binary's actual architecture in the filename. It does
not install the app or replace a copy in Applications.

## Distribution signing

For a public binary release, use a valid **Developer ID Application** certificate
in your own keychain. Never commit or upload its private key or signing credentials.

```sh
CLIPPY_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./scripts/build.sh
```

This enables the hardened runtime and timestamped signing. Then:

1. Run the automated checks and the manual matrix in [testing](TESTING.md).
2. Create a temporary ZIP for notarization using `ditto`.
3. Submit it with `xcrun notarytool submit` using your configured keychain profile.
4. Wait for acceptance, then run `xcrun stapler staple dist/Clippy.app`.
5. Validate with `xcrun stapler validate` and `spctl --assess --type execute`.
6. Recreate the final ZIP **after stapling**, and generate its SHA-256 checksum.
7. Test the downloaded ZIP on another Mac before attaching it to a GitHub release.

Keep the same bundle identifier and signing team across updates. Rebuilding with
ad-hoc signing or changing identity can require a new Accessibility approval.
Do not hide that limitation or disable macOS security protections to ship a release.

## Repository checklist

- Update the version and build number in `scripts/Info.plist` and the changelog.
- Ensure CI passes on both supported architectures.
- Review `git diff --cached` for secrets, local paths, clipboard data, and build products.
- Keep source documentation, license, privacy information, and setup instructions current.
- Use sample data for screenshots and tests.
- Tag the verified source commit. Label source/development releases clearly until
  distribution signing, notarization, and the manual matrix are complete.
