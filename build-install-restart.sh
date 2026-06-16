#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Ports on Mac"
PROJECT="PortsOnMac.xcodeproj"
SCHEME="Ports on Mac"
CONFIGURATION="Release"
CERT_NAME="Ports on Mac Local Code Signing"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
ARCHIVE_ROOT="${PWD}/build"
INSTALL_PATH="/Applications/${APP_NAME}.app"
P12_PASSWORD="ports-on-mac-local-signing"

create_certificate() {
  if security find-certificate -c "${CERT_NAME}" "${KEYCHAIN}" >/dev/null 2>&1; then
    return
  fi

  echo "Creating reusable local code-signing certificate: ${CERT_NAME}"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' RETURN

  cat > "${tmpdir}/openssl.cnf" <<EOF_CERT
[ req ]
distinguished_name = dn
x509_extensions = extensions
prompt = no

[ dn ]
CN = ${CERT_NAME}

[ extensions ]
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, keyCertSign
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF_CERT

  openssl req \
    -new \
    -newkey rsa:2048 \
    -nodes \
    -x509 \
    -days 3650 \
    -config "${tmpdir}/openssl.cnf" \
    -keyout "${tmpdir}/cert.key" \
    -out "${tmpdir}/cert.pem"

  openssl pkcs12 \
    -export \
    -legacy \
    -keypbe PBE-SHA1-3DES \
    -certpbe PBE-SHA1-3DES \
    -macalg sha1 \
    -inkey "${tmpdir}/cert.key" \
    -in "${tmpdir}/cert.pem" \
    -name "${CERT_NAME}" \
    -passout "pass:${P12_PASSWORD}" \
    -out "${tmpdir}/cert.p12"

  if ! security import "${tmpdir}/cert.p12" \
    -k "${KEYCHAIN}" \
    -P "${P12_PASSWORD}" \
    -A \
    -T /usr/bin/codesign \
    -T /usr/bin/security; then
    echo "Could not import the generated PKCS#12 signing identity into the login keychain." >&2
    echo "If macOS prompts for your keychain password, approve it and rerun this script." >&2
    exit 1
  fi

  if ! security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "${KEYCHAIN}" \
    "${tmpdir}/cert.pem" >/dev/null 2>&1; then
    echo "Could not trust the local signing certificate for code signing." >&2
    echo "Open Keychain Access, trust '${CERT_NAME}' for code signing, then run this script again." >&2
    exit 1
  fi

  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "" \
    "${KEYCHAIN}" >/dev/null 2>&1 || true
}

find_identity() {
  local identity
  identity="$(security find-identity -v -p codesigning "${KEYCHAIN}" | awk -v name="${CERT_NAME}" '$0 ~ name {print $2; exit}')"

  if [[ -z "${identity}" ]]; then
    echo "No valid code-signing identity found for '${CERT_NAME}'." >&2
    echo "Open Keychain Access, trust the certificate for code signing, then run this script again." >&2
    exit 1
  fi

  printf "%s" "${identity}"
}

create_certificate
IDENTITY="$(find_identity)"

echo "Building ${APP_NAME} with xcodebuild..."
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${ARCHIVE_ROOT}/DerivedData" \
  CODE_SIGN_IDENTITY="${IDENTITY}" \
  CODE_SIGN_STYLE=Manual \
  build

BUILT_APP="${ARCHIVE_ROOT}/DerivedData/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
if [[ ! -d "${BUILT_APP}" ]]; then
  echo "Build succeeded, but app bundle was not found at ${BUILT_APP}" >&2
  exit 1
fi

echo "Stopping any running copy..."
/usr/bin/pkill -x "${APP_NAME}" >/dev/null 2>&1 || true

echo "Installing to ${INSTALL_PATH}..."
/bin/rm -rf "${INSTALL_PATH}"
/bin/cp -R "${BUILT_APP}" "${INSTALL_PATH}"

echo "Signing installed app with reusable identity..."
/usr/bin/codesign --force --deep --options runtime --sign "${IDENTITY}" "${INSTALL_PATH}"

echo "Starting ${APP_NAME}..."
/usr/bin/open "${INSTALL_PATH}"

echo "Done."
