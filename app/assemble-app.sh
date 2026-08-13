#!/bin/zsh
set -euo pipefail

SCRIPT_PATH="$0"
PROJECT_DIR="${0:A:h}"
cd "$PROJECT_DIR"

SIGNING_MODE=""
SIGNING_IDENTITY=""
KEYCHAIN_PATH=""
APP_VERSION=""
BUILD_VERSION="$(date -u +%Y%m%d%H%M%S)"

APP_NAME="Ports on Mac"
BUNDLE_ID="com.emilianscheel.ports-on-mac"
GITHUB_REPO="emilianscheel/ports-on-mac"

usage() {
  print -u2 "Usage: $SCRIPT_PATH --signing-mode adhoc|development|distribution --signing-identity ID [--keychain PATH] [--version X.Y.Z] [--build-version N]"
}

die() {
  print -u2 -- "$1"
  exit "${2:-1}"
}

while (( $# > 0 )); do
  case "$1" in
    --signing-mode)
      (( $# >= 2 )) || die "Missing value for --signing-mode." 64
      SIGNING_MODE="$2"
      shift 2
      ;;
    --signing-identity)
      (( $# >= 2 )) || die "Missing value for --signing-identity." 64
      SIGNING_IDENTITY="$2"
      shift 2
      ;;
    --keychain)
      (( $# >= 2 )) || die "Missing value for --keychain." 64
      KEYCHAIN_PATH="$2"
      shift 2
      ;;
    --version)
      (( $# >= 2 )) || die "Missing value for --version." 64
      APP_VERSION="$2"
      shift 2
      ;;
    --build-version)
      (( $# >= 2 )) || die "Missing value for --build-version." 64
      BUILD_VERSION="$2"
      shift 2
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

[[ "$SIGNING_MODE" == "adhoc" || "$SIGNING_MODE" == "development" || "$SIGNING_MODE" == "distribution" ]] || {
  usage
  exit 64
}
[[ -n "$SIGNING_IDENTITY" ]] || die "A signing identity is required." 64
[[ -z "$APP_VERSION" || "$APP_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || die "Version must use X.Y.Z numeric format." 64
[[ "$BUILD_VERSION" =~ '^[0-9]+$' ]] || die "Build version must be a positive integer." 64
(( BUILD_VERSION > 0 )) || die "Build version must be a positive integer." 64
[[ -z "$KEYCHAIN_PATH" || "$KEYCHAIN_PATH" == /* ]] || die "Keychain path must be absolute." 64

[[ "$(uname -m)" == "arm64" ]] || die "Ports on Mac requires Apple silicon (arm64)."
OS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
(( OS_MAJOR >= 26 )) || die "Ports on Mac requires macOS 26 or newer."

for required_command in swift codesign xcrun xcodebuild plutil file ditto otool; do
  command -v "$required_command" >/dev/null || die "$required_command is required."
done

STAGE_APP="$PROJECT_DIR/.build/${APP_NAME}.app-staging"
ICON_BUILD_DIR="$PROJECT_DIR/.build/AppIcon-assets"
ICON_PARTIAL_INFO_PLIST="$ICON_BUILD_DIR/partial-info.plist"
XCODE_DERIVED_DATA="$PROJECT_DIR/.build/xcode-derived"
SPARKLE_TOOLS_DIR="$PROJECT_DIR/Packaging/SparkleTools"
SPARKLE_DISTRIBUTION="$SPARKLE_TOOLS_DIR/.build/artifacts/sparkle/Sparkle"
SPARKLE_SOURCE_FRAMEWORK="$SPARKLE_DISTRIBUTION/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
SPARKLE_PUBLIC_KEY_FILE="$PROJECT_DIR/Packaging/SparklePublicKey.txt"
SPARKLE_FEED_URL="https://github.com/${GITHUB_REPO}/releases/latest/download/appcast.xml"
ENTITLEMENTS="$PROJECT_DIR/PortsOnMac/PortsOnMac.entitlements"
typeset -a CODESIGN_KEYCHAIN_ARGS CODESIGN_TIMESTAMP_ARGS CODESIGN_RUNTIME_ARGS
CODESIGN_KEYCHAIN_ARGS=()
CODESIGN_RUNTIME_ARGS=()
[[ -z "$KEYCHAIN_PATH" ]] || CODESIGN_KEYCHAIN_ARGS=(--keychain "$KEYCHAIN_PATH")
if [[ "$SIGNING_MODE" == "distribution" ]]; then
  [[ "$SIGNING_IDENTITY" != "-" ]] || die "Distribution builds cannot use ad-hoc signing."
  CODESIGN_TIMESTAMP_ARGS=(--timestamp)
  CODESIGN_RUNTIME_ARGS=(--options runtime)
elif [[ "$SIGNING_MODE" == "development" ]]; then
  CODESIGN_TIMESTAMP_ARGS=(--timestamp=none)
  CODESIGN_RUNTIME_ARGS=(--options runtime)
else
  CODESIGN_TIMESTAMP_ARGS=(--timestamp=none)
fi

SPARKLE_PUBLIC_KEY=""
if [[ "$SIGNING_MODE" == "distribution" ]]; then
  [[ -f "$SPARKLE_PUBLIC_KEY_FILE" ]] || die "Packaging/SparklePublicKey.txt is required for distribution builds. Run ./app/release.sh --setup."
  SPARKLE_PUBLIC_KEY="$(tr -d '\r\n' < "$SPARKLE_PUBLIC_KEY_FILE")"
  [[ "$SPARKLE_PUBLIC_KEY" =~ '^[A-Za-z0-9+/]{43}=$' ]] \
    || die "Packaging/SparklePublicKey.txt does not contain one base64 Ed25519 public key."
fi

sign_code() {
  codesign --force "${CODESIGN_RUNTIME_ARGS[@]}" "${CODESIGN_TIMESTAMP_ARGS[@]}" "${CODESIGN_KEYCHAIN_ARGS[@]}" --sign "$SIGNING_IDENTITY" "$1"
}

print "Signing mode: $SIGNING_MODE"
print "Signing with identity: $SIGNING_IDENTITY"

print "Resolving Sparkle tools…"
(cd "$SPARKLE_TOOLS_DIR" && swift package --disable-sandbox resolve)
[[ -d "$SPARKLE_SOURCE_FRAMEWORK" ]] || die "The resolved Sparkle.framework artifact is missing."

print "Building release app…"
xcodebuild \
  -quiet \
  -project "$PROJECT_DIR/PortsOnMac.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$XCODE_DERIVED_DATA" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  build

BUILT_APP="$XCODE_DERIVED_DATA/Build/Products/Release/${APP_NAME}.app"
[[ -d "$BUILT_APP" ]] || die "xcodebuild did not produce ${APP_NAME}.app."
[[ -f "$BUILT_APP/Contents/MacOS/$APP_NAME" ]] || die "Built app is missing its executable."

print "Compiling the adaptive app icon…"
rm -rf "$ICON_BUILD_DIR"
mkdir -p "$ICON_BUILD_DIR"
xcrun actool \
  --compile "$ICON_BUILD_DIR" \
  --output-format human-readable-text \
  --warnings \
  --errors \
  --notices \
  --output-partial-info-plist "$ICON_PARTIAL_INFO_PLIST" \
  --app-icon icon \
  --platform macosx \
  --minimum-deployment-target 26.0 \
  --target-device mac \
  --standalone-icon-behavior all \
  "$PROJECT_DIR/icon.icon"
[[ -f "$ICON_BUILD_DIR/Assets.car" ]] || die "App icon compilation did not produce Assets.car."
[[ -f "$ICON_BUILD_DIR/icon.icns" ]] || die "App icon compilation did not produce icon.icns."
[[ -f "$ICON_PARTIAL_INFO_PLIST" ]] || die "App icon compilation did not produce bundle metadata."

rm -rf "$STAGE_APP"
ditto "$BUILT_APP" "$STAGE_APP"
SPARKLE_FRAMEWORK="$STAGE_APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$STAGE_APP/Contents/Frameworks"
rm -rf "$SPARKLE_FRAMEWORK"
ditto "$SPARKLE_SOURCE_FRAMEWORK" "$SPARKLE_FRAMEWORK"
# Ports on Mac is not App-Sandboxed. Sparkle's sandbox-only XPC services are
# unused, so remove both their real directory and public symlink.
rm -rf \
  "$SPARKLE_FRAMEWORK/Versions/B/XPCServices" \
  "$SPARKLE_FRAMEWORK/XPCServices"
[[ ! -e "$SPARKLE_FRAMEWORK/Versions/B/XPCServices" ]] \
  || die "Sparkle's sandbox-only XPC services were not removed."

mkdir -p "$STAGE_APP/Contents/Resources"
cp "$ICON_BUILD_DIR/icon.icns" "$ICON_BUILD_DIR/Assets.car" "$STAGE_APP/Contents/Resources/"
MAIN_INFO_PLIST="$STAGE_APP/Contents/Info.plist"
for ICON_KEY in CFBundleIconFile CFBundleIconName; do
  ICON_VALUE="$(plutil -extract "$ICON_KEY" raw "$ICON_PARTIAL_INFO_PLIST")"
  if plutil -extract "$ICON_KEY" raw "$MAIN_INFO_PLIST" >/dev/null 2>&1; then
    plutil -replace "$ICON_KEY" -string "$ICON_VALUE" "$MAIN_INFO_PLIST"
  else
    plutil -insert "$ICON_KEY" -string "$ICON_VALUE" "$MAIN_INFO_PLIST"
  fi
done

typeset -a SPARKLE_CONFIGURATION_KEYS
SPARKLE_CONFIGURATION_KEYS=(
  SUFeedURL
  SUPublicEDKey
  SUEnableAutomaticChecks
  SUAutomaticallyUpdate
  SUAllowsAutomaticUpdates
  SUScheduledCheckInterval
  SUSendProfileInfo
  SUEnableSystemProfiling
  SURequireSignedFeed
  SUVerifyUpdateBeforeExtraction
)
for key in "${SPARKLE_CONFIGURATION_KEYS[@]}"; do
  plutil -remove "$key" "$MAIN_INFO_PLIST" >/dev/null 2>&1 || true
done
plutil -remove PortsOnMacUpdateMode "$MAIN_INFO_PLIST" >/dev/null 2>&1 || true
if [[ "$SIGNING_MODE" == "distribution" ]]; then
  plutil -insert PortsOnMacUpdateMode -string production "$MAIN_INFO_PLIST"
  plutil -insert SUFeedURL -string "$SPARKLE_FEED_URL" "$MAIN_INFO_PLIST"
  plutil -insert SUPublicEDKey -string "$SPARKLE_PUBLIC_KEY" "$MAIN_INFO_PLIST"
  plutil -insert SUEnableAutomaticChecks -bool YES "$MAIN_INFO_PLIST"
  plutil -insert SUAutomaticallyUpdate -bool YES "$MAIN_INFO_PLIST"
  plutil -insert SUAllowsAutomaticUpdates -bool YES "$MAIN_INFO_PLIST"
  plutil -insert SUScheduledCheckInterval -integer 86400 "$MAIN_INFO_PLIST"
  plutil -insert SUSendProfileInfo -bool NO "$MAIN_INFO_PLIST"
  plutil -insert SUEnableSystemProfiling -bool NO "$MAIN_INFO_PLIST"
  plutil -insert SURequireSignedFeed -bool YES "$MAIN_INFO_PLIST"
  plutil -insert SUVerifyUpdateBeforeExtraction -bool YES "$MAIN_INFO_PLIST"
else
  plutil -insert PortsOnMacUpdateMode -string disabled "$MAIN_INFO_PLIST"
fi
if [[ -n "$APP_VERSION" ]]; then
  plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$MAIN_INFO_PLIST"
fi
plutil -replace CFBundleVersion -string "$BUILD_VERSION" "$MAIN_INFO_PLIST"

[[ "$(plutil -extract CFBundleIdentifier raw "$MAIN_INFO_PLIST")" == "$BUNDLE_ID" ]] \
  || die "The staged app has an unexpected bundle identifier."
[[ -L "$SPARKLE_FRAMEWORK/Versions/Current" ]] \
  || die "Sparkle.framework's version symlink was not preserved."
otool -L "$STAGE_APP/Contents/MacOS/$APP_NAME" \
  | grep -Fq '@rpath/Sparkle.framework' \
  || die "Ports on Mac is not linked to the embedded Sparkle framework through @rpath."
otool -l "$STAGE_APP/Contents/MacOS/$APP_NAME" \
  | grep -Fq '@executable_path/../Frameworks' \
  || die "Ports on Mac does not search its embedded Frameworks directory at runtime."

plutil -lint "$ENTITLEMENTS" >/dev/null || die "PortsOnMac.entitlements is not a valid property list."

# Sign every Mach-O payload first, followed by Sparkle and finally the app
# bundle. Keep --deep for verification only.
while IFS= read -r -d '' candidate; do
  if file -b "$candidate" | grep -q 'Mach-O'; then
    sign_code "$candidate"
  fi
done < <(find "$STAGE_APP/Contents" -type f -perm -111 -print0)
sign_code "$SPARKLE_FRAMEWORK/Versions/B/Updater.app"
sign_code "$SPARKLE_FRAMEWORK"
codesign --force "${CODESIGN_RUNTIME_ARGS[@]}" "${CODESIGN_TIMESTAMP_ARGS[@]}" "${CODESIGN_KEYCHAIN_ARGS[@]}" \
  --entitlements "$ENTITLEMENTS" --sign "$SIGNING_IDENTITY" "$STAGE_APP"
codesign --verify --deep --strict --verbose=2 "$STAGE_APP"

if [[ "$SIGNING_MODE" == "distribution" ]]; then
  for signed_item in \
    "$STAGE_APP/Contents/MacOS/$APP_NAME" \
    "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate" \
    "$SPARKLE_FRAMEWORK/Versions/B/Updater.app" \
    "$SPARKLE_FRAMEWORK" \
    "$STAGE_APP"; do
    SIGNATURE_DETAILS="$(codesign -dvvv "$signed_item" 2>&1)"
    [[ "$SIGNATURE_DETAILS" == *"Authority=Developer ID Application:"* ]] || die "$signed_item is not signed with a Developer ID Application identity."
    [[ "$SIGNATURE_DETAILS" == *"Timestamp="* ]] || die "$signed_item has no secure timestamp."
    [[ "$SIGNATURE_DETAILS" == *"runtime"* ]] || die "$signed_item does not enable Hardened Runtime."
  done

  EMBEDDED_ENTITLEMENTS="$PROJECT_DIR/.build/PortsOnMac.release-entitlements.plist"
  codesign -d --entitlements :- "$STAGE_APP" > "$EMBEDDED_ENTITLEMENTS" 2>/dev/null
  plutil -lint "$EMBEDDED_ENTITLEMENTS" >/dev/null || die "The assembled app has malformed embedded entitlements."
  GET_TASK_ALLOW="$(plutil -extract 'com\.apple\.security\.get-task-allow' raw -o - "$EMBEDDED_ENTITLEMENTS" 2>/dev/null || true)"
  [[ "$GET_TASK_ALLOW" != "true" ]] || die "Distribution builds must not include com.apple.security.get-task-allow."
fi

UPDATE_MODE="$(plutil -extract PortsOnMacUpdateMode raw "$MAIN_INFO_PLIST")"
if [[ "$SIGNING_MODE" == "distribution" ]]; then
  [[ "$UPDATE_MODE" == "production" ]] || die "Distribution build did not enable production updates."
  [[ "$(plutil -extract SUFeedURL raw "$MAIN_INFO_PLIST")" == "$SPARKLE_FEED_URL" ]] \
    || die "Distribution build has an unexpected Sparkle feed URL."
  [[ "$(plutil -extract SUPublicEDKey raw "$MAIN_INFO_PLIST")" == "$SPARKLE_PUBLIC_KEY" ]] \
    || die "Distribution build has an unexpected Sparkle public key."
else
  [[ "$UPDATE_MODE" == "disabled" ]] || die "Local build unexpectedly enabled production updates."
  for key in "${SPARKLE_CONFIGURATION_KEYS[@]}"; do
    ! plutil -extract "$key" raw "$MAIN_INFO_PLIST" >/dev/null 2>&1 \
      || die "Local build unexpectedly contains $key."
  done
fi

print "Running --debug-scan smoke test…"
"$STAGE_APP/Contents/MacOS/$APP_NAME" --debug-scan >/dev/null

print "Assembly verified at $STAGE_APP."
