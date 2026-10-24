#!/bin/bash
# Stable local code-signing identity so Accessibility TCC survives rebuilds.
set -euo pipefail

CERT_CN="T650Gestures Local"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
[[ -f "$KEYCHAIN" ]] || KEYCHAIN="${HOME}/Library/Keychains/login.keychain"

valid_hash() {
  security find-identity -v -p codesigning 2>/dev/null \
    | awk '/T650Gestures Local/{print $2; exit}'
}

if HASH="$(valid_hash)"; [[ -n "${HASH:-}" ]]; then
  echo "$HASH"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

openssl genrsa -out "$TMP/key.pem" 2048 2>/dev/null
cat > "$TMP/openssl.cnf" <<EOF
[req]
distinguished_name = req_dn
x509_extensions = v3_code
prompt = no
[req_dn]
CN = ${CERT_CN}
[v3_code]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -new -x509 -days 3650 -key "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf" 2>/dev/null

openssl pkcs12 -export -legacy \
  -out "$TMP/cert.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -passout pass:t650local -name "$CERT_CN" 2>/dev/null

security import "$TMP/cert.p12" -k "$KEYCHAIN" -P t650local -A \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null 2>&1 || true

security add-trusted-cert -d -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem" >/dev/null 2>&1 || true
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

HASH="$(valid_hash)"
if [[ -z "${HASH:-}" ]]; then
  echo "ERROR: could not create trusted identity '$CERT_CN'" >&2
  exit 1
fi
echo "$HASH"
