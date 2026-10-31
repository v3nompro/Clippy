# Privacy

Clippy stores clipboard history locally. It has no account system, network client,
telemetry, advertising, crash-reporting service, cloud synchronization, or updater.

## Stored data

- Supported clipboard representations: plain text, HTML, RTF, PNG/TIFF images,
  URLs, and file references.
- A display title, a searchable text excerpt, source-app name, copy time, pin state,
  and an optional small image thumbnail.
- The database lives at `~/Library/Application Support/Clippy/History.sqlite`.
  The directory uses mode `0700`, and the database uses mode `0600`.
- Launch and other app preferences use macOS preferences and Service Management.

History is not separately encrypted. Software running as your user, administrators,
and backups may be able to access it. FileVault protects your disk according to
your Mac's settings.

## Sensitive copies

Clippy ignores confidential, transient, and automatically generated pasteboard
markers. It also excludes several common password-manager applications and skips
capture while Secure Input is enabled. These safeguards depend on information
supplied by macOS and the app you copied from. An unmarked password or secret can
still be recorded.

Use **Pause clipboard history** before copying information you do not want stored.
Copies made while paused are not imported when capture resumes. Clippy also does
not import the existing clipboard when it starts.

## Permissions

Accessibility access is used to send a paste command to the destination app and
query the caret's location. It is optional for storing and manually copying history.
Clippy never enables or resets this access itself. Launch at login is opt-in.

## Deletion

Delete individual entries, clear unpinned history, or use **Delete all history** to
include pins. SQLite `secure_delete` is enabled. Deleted entries are removed from
the active database; filesystem snapshots and backups are outside Clippy's control.
Clearing history does not clear the system clipboard.

To remove all local history, quit Clippy, then remove
`~/Library/Application Support/Clippy`. Remove the app and disable its login item
if you no longer want it to run.

## Independent services

macOS Universal Clipboard, iCloud, Time Machine, the operating system, and other
applications have their own data behavior. Clippy does not configure those services.

Tests and preview mode use temporary private pasteboards. Preview screenshots
contain sample entries rather than a user's history.
