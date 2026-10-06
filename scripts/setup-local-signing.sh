#!/bin/bash
set -euo pipefail

IDENTITY="VoiceInputLocalSigning"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep "\"$IDENTITY\"" | grep -vq "Invalid"; then
  echo "✅ 已存在代码签名身份: $IDENTITY"
  exit 0
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "❌ 找不到 openssl，无法创建本地签名证书。"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CERT_PATH="$TMP_DIR/$IDENTITY.crt"
KEY_PATH="$TMP_DIR/$IDENTITY.key"
P12_PATH="$TMP_DIR/$IDENTITY.p12"
P12_PASSWORD="voiceinput"

echo "🔐 创建本机代码签名证书: $IDENTITY"

openssl req \
  -newkey rsa:2048 \
  -nodes \
  -keyout "$KEY_PATH" \
  -x509 \
  -days 3650 \
  -out "$CERT_PATH" \
  -subj "/CN=$IDENTITY/" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

openssl pkcs12 \
  -export \
  -des3 \
  -descert \
  -macalg sha1 \
  -inkey "$KEY_PATH" \
  -in "$CERT_PATH" \
  -out "$P12_PATH" \
  -name "$IDENTITY" \
  -passout "pass:$P12_PASSWORD" >/dev/null 2>&1

security import "$P12_PATH" \
  -f pkcs12 \
  -k "$KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign

security add-trusted-cert \
  -d \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$CERT_PATH"

echo "✅ 完成。之后运行 ./scripts/build.sh 会自动使用 ${IDENTITY}。"
