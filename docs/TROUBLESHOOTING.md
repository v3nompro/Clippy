# Troubleshooting

## Permission is on but Clippy still asks

macOS records a code-signing identity alongside Accessibility approval. An ad-hoc
build's identity changes when the executable changes. An older entry can therefore
look enabled while macOS rejects the currently installed build.

1. Quit Clippy and keep only the intended installed copy in Applications.
2. In **System Settings → Privacy & Security → Accessibility** (or **Device Control
   and Data Access**), remove the stale Clippy entry if the Remove control is available.
3. Add **`/Applications/Clippy.app`** and enable it.
4. Relaunch Clippy. Check that the permission banner disappears.

If the stale entry cannot be removed through Settings, you can reset **only Clippy's**
Accessibility approval with the following command. This revokes its existing grant;
you must add and approve the installed app again afterward. It does not delete
clipboard history or affect other apps' permissions.

```sh
tccutil reset Accessibility app.clippy.clipboard
```

Do not reset all system permissions. A stable Developer ID signature is needed for
permission continuity across distributed app updates; see [releasing](RELEASING.md).

## Selecting a clip only copies it

Enable Accessibility access for direct paste. Without it, press Command-V after
selecting the item. Some applications and secure fields reject simulated paste
events even with access enabled.

## Option-V does not open the picker

Make sure Clippy is running and check its menu-bar icon. Another app may already
own the shortcut. In that case, use the menu-bar item or change the conflicting
shortcut in the other app.

## A copied item does not appear

Check that capture is not paused. Confidential/transient types, excluded password
managers, Secure Input, unsupported content, copies above 4 MiB, and a full set of
pins can prevent a new item from being saved. Copies replaced within the 250 ms
polling interval may also be missed.

## Launch at login is unavailable

Move the app to Applications before enabling **Launch at login**. Review macOS's
Login Items settings if approval is pending or the item is disabled.

## Build or check failure

Confirm the selected developer tools provide Swift 5.9 or later. The tests require
a macOS desktop session with its pasteboard service available. In an environment
that prevents nested build sandboxing, pass `--disable-sandbox` to the build or
check script. Report the toolchain version and relevant error text without secrets.
