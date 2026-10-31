# Testing

## Automated checks

Run `./scripts/check.sh` on macOS. The standalone runner avoids a dependency on
XCTest and uses fresh temporary directories and private pasteboards. It never reads
or replaces the user's normal clipboard.

Coverage includes:

- Persistence, Unicode, embedded NUL characters, and file permissions.
- Rich and multi-item pasteboard round trips.
- Confidential and transient markers, including mixed sensitive copies.
- Stable fingerprints and duplicate recency without losing pins.
- Count and byte-budget eviction, including fully pinned history.
- Clear, delete, pin, and unpin semantics.
- Oversized rejection, the exact supported size boundary, and unsupported content.
- Invalid-write protection and file-reference retention.

GitHub Actions runs the checks and packages the app on Apple Silicon and Intel
macOS runners. Successful automation does not establish compatibility with every
destination app, OS release, or window configuration.

## UI preview

```sh
./scripts/build.sh
open -n dist/Clippy.app --args --preview
```

Preview mode uses sample entries, a temporary database, and a private pasteboard.
It does not start capture, register the global shortcut, or request permissions.
It can also render the picker:

```sh
dist/Clippy.app/Contents/MacOS/Clippy --preview --render-preview /tmp/clippy-preview.png
```

Check search, no-result states, keyboard selection, Command-A editing, Command-P
pinning, Return selection, scrolling, and row buttons.

## Manual release matrix

Use non-sensitive test content and record the environment and result. Do not claim
a check passed until it has been exercised on the relevant platform.

| Area | Checks |
| --- | --- |
| First launch | Menu-bar item, empty state, initial picker, no import of existing clipboard |
| Global shortcut | Open/close with Option-V, conflict handling, menu-bar fallback |
| Permission lifecycle | Denial, grant while running, revocation, restart, rebuilt app identity |
| Direct paste | TextEdit, Safari, Terminal, editor; click and keyboard selection |
| Cancellation | Escape, outside click, app switch, clipboard change, held modifiers |
| Content | Plain text, HTML/RTF, image, single and multiple file references |
| Privacy | Concealed/transient markers, password-manager copy, Secure Input, pause/resume |
| History | Duplicate copy, eviction, persistence, pin/unpin, clear, delete all |
| Windows | Multiple screens, screen edges, Spaces, full-screen apps |
| System | Launch at login from Applications, logout/login, sleep/wake |

The deployment target is macOS 13. Run-testing older OS releases and Intel hardware
is separate from compiling a compatible binary. Direct paste acceptance cannot be
inferred solely from successfully posting a keyboard event.
