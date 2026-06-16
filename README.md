# Ports on Mac

Minimal macOS menu bar app for inspecting used ports and freeing them quickly.

## Features

- Menu bar icon: SF Symbols `powercord`
- Lists TCP and UDP ports from `lsof`
- Shows process, PID, user, endpoint, protocol, and state details
- Opens inferred local URLs in the browser
- Sends `SIGTERM` to a selected process with the `Kill` action

## Build, Install, Restart

```sh
./build-install-restart.sh
```

The script builds with `xcodebuild`, creates or reuses a local self-signed code-signing certificate, installs the app to `/Applications`, and restarts it.

Reusing the same certificate helps macOS recognize rebuilds as the same app identity, so permissions are less likely to be requested again after every restart.

## Uninstall

Quit the app from the menu, then remove:

```sh
rm -rf "/Applications/Ports on Mac.app"
```
