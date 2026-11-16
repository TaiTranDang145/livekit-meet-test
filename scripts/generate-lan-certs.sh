#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

LAN_IP="${1:?Usage: scripts/generate-lan-certs.sh <LAN_IP>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CERT_DIR="${2:-$PROJECT_ROOT/.local/lan-certs}"
mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"

if [[ ! -e "$CERT_DIR/ca.crt" && ! -e "$CERT_DIR/ca.key" ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$CERT_DIR/ca.key" \
    -out "$CERT_DIR/ca.crt" \
    -days 3650 \
    -subj '/CN=LiveKit Meet LAN Test CA'
elif [[ ! -s "$CERT_DIR/ca.crt" || ! -s "$CERT_DIR/ca.key" ]]; then
  echo "CA files are incomplete in $CERT_DIR; refusing to replace the existing CA." >&2
  exit 1
fi

openssl req -newkey rsa:2048 -nodes \
  -keyout "$CERT_DIR/server.key" \
  -out "$CERT_DIR/server.csr" \
  -subj "/CN=$LAN_IP"

cat > "$CERT_DIR/server.ext" <<EOF
subjectAltName = IP:$LAN_IP
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
EOF

openssl x509 -req \
  -in "$CERT_DIR/server.csr" \
  -CA "$CERT_DIR/ca.crt" \
  -CAkey "$CERT_DIR/ca.key" \
  -CAcreateserial \
  -out "$CERT_DIR/server.crt" \
  -days 397 \
  -sha256 \
  -extfile "$CERT_DIR/server.ext"

chmod 600 "$CERT_DIR/ca.key" "$CERT_DIR/server.key"
chmod 644 "$CERT_DIR/ca.crt" "$CERT_DIR/server.crt"
echo "LAN TLS files generated in $CERT_DIR for IP $LAN_IP"
openssl x509 -in "$CERT_DIR/ca.crt" -noout -fingerprint -sha256
