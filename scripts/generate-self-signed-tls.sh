#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s <SERVER_IPV4>\n' "$0" >&2
  exit 2
fi

SERVER_IP="$1"
IPV4_RE='^(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$'
if [[ ! "$SERVER_IP" =~ $IPV4_RE ]]; then
  printf 'Error: expected an IPv4 address; received: %s\n' "$SERVER_IP" >&2
  exit 2
fi

IFS='.' read -r -a octets <<< "$SERVER_IP"
for octet in "${octets[@]}"; do
  if (( octet > 255 )); then
    printf 'Error: invalid IPv4 address: %s\n' "$SERVER_IP" >&2
    exit 2
  fi
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
CA_DIR="$PROJECT_DIR/.local/tls-ca"
GENERATED_CERT_DIR="$PROJECT_DIR/.local/generated-tls"
CA_KEY="$CA_DIR/rootCA.key"
CA_CERT="$CA_DIR/rootCA.crt"

umask 077
mkdir -p "$CA_DIR" "$GENERATED_CERT_DIR"
chmod 700 "$CA_DIR" "$GENERATED_CERT_DIR"

if [[ -e "$CA_KEY" || -e "$CA_CERT" ]]; then
  if [[ ! -f "$CA_KEY" || ! -f "$CA_CERT" ]]; then
    printf 'Error: found an incomplete CA in %s; restore both CA files before continuing.\n' "$CA_DIR" >&2
    exit 1
  fi
  printf 'Reusing the existing local CA.\n'
else
  printf 'Creating a local root CA valid for approximately 50 years.\n'
  openssl req -x509 -newkey rsa:4096 -sha256 -nodes -days 18250 \
    -keyout "$CA_KEY" \
    -out "$CA_CERT" \
    -subj "/CN=LiveKit Meet Local Test CA" \
    -addext 'basicConstraints=critical,CA:TRUE' \
    -addext 'keyUsage=critical,keyCertSign,cRLSign' \
    -addext 'subjectKeyIdentifier=hash'
fi

chmod 600 "$CA_KEY"
chmod 644 "$CA_CERT"

CA_END_DATE="$(openssl x509 -in "$CA_CERT" -noout -enddate | cut -d= -f2-)"
CA_END_EPOCH="$(date -u -d "$CA_END_DATE" +%s)"
NOW_EPOCH="$(date -u +%s)"
CA_DAYS_LEFT="$(( (CA_END_EPOCH - NOW_EPOCH) / 86400 ))"
if (( CA_DAYS_LEFT < 2 )); then
  printf 'Error: the local CA has expired or is about to expire.\n' >&2
  exit 1
fi
SERVER_DAYS=18250
if (( CA_DAYS_LEFT < SERVER_DAYS )); then
  SERVER_DAYS="$((CA_DAYS_LEFT - 1))"
fi

WORK_DIR="$(mktemp -d "$CA_DIR/issue.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

openssl req -new -newkey rsa:2048 -nodes -sha256 \
  -keyout "$WORK_DIR/privkey.pem" \
  -out "$WORK_DIR/server.csr" \
  -subj "/CN=$SERVER_IP"

cat > "$WORK_DIR/server.ext" <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=IP:$SERVER_IP
authorityKeyIdentifier=keyid,issuer
subjectKeyIdentifier=hash
EOF

openssl x509 -req \
  -in "$WORK_DIR/server.csr" \
  -CA "$CA_CERT" \
  -CAkey "$CA_KEY" \
  -CAcreateserial \
  -out "$WORK_DIR/server.crt" \
  -days "$SERVER_DAYS" -sha256 \
  -extfile "$WORK_DIR/server.ext"

openssl verify -CAfile "$CA_CERT" -verify_ip "$SERVER_IP" "$WORK_DIR/server.crt"

cat "$WORK_DIR/server.crt" "$CA_CERT" > "$WORK_DIR/fullchain.pem"
install -m 0644 "$WORK_DIR/fullchain.pem" "$GENERATED_CERT_DIR/fullchain.pem"
install -m 0600 "$WORK_DIR/privkey.pem" "$GENERATED_CERT_DIR/privkey.pem"

printf '\nGenerated certificate files are ready:\n  %s/fullchain.pem\n  %s/privkey.pem\n' \
  "$GENERATED_CERT_DIR" "$GENERATED_CERT_DIR"
printf 'Copy the generated files to the certificate directory mounted by the selected Compose profile.\n'
printf 'Product: .local/nginx-certs/ ; LAN: .local/nginx-certs-lan/\n'
printf 'Install this public root CA on each test client:\n  %s\n' "$CA_CERT"
printf 'Keep the CA private key secret; it is stored at:\n  %s\n' "$CA_KEY"
printf 'The root CA is valid for approximately 50 years; the server certificate is valid for up to %s days.\n' "$SERVER_DAYS"
