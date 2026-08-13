## Features

- Menu bar icon: SF Symbols `powercord`
- Lists TCP and UDP ports from `lsof`
- Shows process, PID, user, endpoint, protocol, and state details
- Opens inferred local URLs in the browser
- Sends `SIGTERM` to a selected process with the `Kill` action
- Sparkle auto-updates from GitHub Releases (distribution builds only)

## Build, Install, Restart

From the `app` directory:

```sh
./build-install-restart.sh
```

The script builds a development-signed app, installs it to `~/Applications/Ports on Mac.app`, and relaunches it. It prefers a valid Apple Development certificate and otherwise creates a persistent `Ports on Mac Local Development` identity so macOS keeps treating rebuilds as the same app.

Use `--assemble-only` to build and sign without installing:

```sh
./build-install-restart.sh --assemble-only
```

## Uninstall

Quit the app from the menu, then remove:

```sh
rm -rf "$HOME/Applications/Ports on Mac.app"
```

## Release

Releases are signed with Developer ID, notarized, packaged as `PortsOnMac.dmg`, and published to GitHub with a signed Sparkle `appcast.xml`.

### One-time setup

1. In Xcode Settings → Accounts → Manage Certificates, create **Apple Development** and **Developer ID Application** certificates.
2. Install tools and authenticate GitHub CLI:

   ```sh
   brew install gh uv
   gh auth login
   ```

3. Store notarization credentials in Keychain. Create an app-specific password at [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords. The Team ID is the 10-character id under [developer.apple.com](https://developer.apple.com) → Membership:

   ```sh
   xcrun notarytool store-credentials "ports-on-mac-notary" \
     --apple-id "APPLE-ID" \
     --team-id "TEAM-ID" \
     --password "APP-SPECIFIC-PASSWORD"
   ```

   The profile name must be `ports-on-mac-notary`. Scripts never read the password; `notarytool` keeps it in Keychain.

4. Generate Ports on Mac's Sparkle Ed25519 key (do **not** reuse Current's key). From the repo:

   ```sh
   cd app/Packaging/SparkleTools
   swift package --disable-sandbox resolve
   .build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.emilianscheel.ports-on-mac
   ```

   Keep an encrypted backup with `generate_keys --account com.emilianscheel.ports-on-mac -x <secure-path>`.

5. Verify the environment and write `Packaging/SparklePublicKey.txt` (commit that file):

   ```sh
   ./app/release.sh --setup
   ```

   If Keychain asks, choose **Always Allow** for Sparkle's `sign_update` tool.

### Publish a release

Work on a clean `main` that matches `origin/main`, then:

```sh
./app/release.sh vX.Y.Z
```

The script builds, notarizes, creates an annotated git tag, and publishes a GitHub Release with `PortsOnMac.dmg` and `appcast.xml`.
