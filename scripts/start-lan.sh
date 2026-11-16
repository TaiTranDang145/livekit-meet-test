#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

if [[ $# -gt 1 ]]; then
  printf 'Usage: %s [LAN_IPV4]\n' "$0" >&2
  exit 2
fi

LAN_IP="${1:-}"
if [[ -z "$LAN_IP" ]]; then
  if ! command -v ip >/dev/null 2>&1; then
    printf 'Install iproute2 or pass the LAN IPv4 address explicitly.\n' >&2
    exit 1
  fi
  LAN_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }')"
fi
if [[ -z "$LAN_IP" ]]; then
  printf 'Could not detect the LAN IPv4 address; pass it explicitly: %s 192.168.1.25\n' "$0" >&2
  exit 1
fi

LAN_IP="$(python3 - "$LAN_IP" <<'PY'
import ipaddress
import sys

try:
    address = ipaddress.IPv4Address(sys.argv[1])
except ipaddress.AddressValueError:
    print("Expected a private LAN IPv4 address.", file=sys.stderr)
    raise SystemExit(2)

if not address.is_private or address.is_loopback or address.is_link_local:
    print("Expected a private LAN IPv4 address, not loopback or link-local.", file=sys.stderr)
    raise SystemExit(2)

print(address)
PY
)"

ENV_FILE=".local/.env.lan"
mkdir -p .local
chmod 700 .local
if [[ ! -e "$ENV_FILE" ]]; then
  install -m 0600 meet/.env.production.example "$ENV_FILE"
fi
if [[ -L "$ENV_FILE" ]]; then
  printf 'Refusing to update a symlinked LAN env file: %s\n' "$ENV_FILE" >&2
  exit 1
fi

if ! python3 - "$ENV_FILE" <<'PY'
import sys
from pathlib import Path

values = {}
for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    name, separator, value = line.partition("=")
    if separator:
        values[name] = value.strip().strip("\"'")

raise SystemExit(0 if values.get("LIVEKIT_API_KEY") and values.get("LIVEKIT_API_SECRET") else 1)
PY
then
  python3 scripts/generate-livekit-keys.py "$LAN_IP" "$ENV_FILE"
else
  python3 - "$ENV_FILE" "$LAN_IP" <<'PY'
import os
import sys
import tempfile
from pathlib import Path

env_file = Path(sys.argv[1])
if env_file.is_symlink():
    print("Refusing to update a symlinked LAN env file.", file=sys.stderr)
    raise SystemExit(1)

url = f"LIVEKIT_URL=wss://{sys.argv[2]}:8443"
lines = env_file.read_text(encoding="utf-8").splitlines()
updated = []
written = False
for line in lines:
    if line.startswith("LIVEKIT_URL="):
        if not written:
            updated.append(url)
            written = True
    else:
        updated.append(line)
if not written:
    updated.append(url)

descriptor, temporary_name = tempfile.mkstemp(prefix=".env.lan.", dir=env_file.parent)
try:
    with os.fdopen(descriptor, "w", encoding="utf-8") as temporary_file:
        temporary_file.write("\n".join(updated) + "\n")
        temporary_file.flush()
        os.fsync(temporary_file.fileno())
    os.chmod(temporary_name, 0o600)
    os.replace(temporary_name, env_file)
finally:
    if os.path.exists(temporary_name):
        os.unlink(temporary_name)
PY
fi

bash scripts/generate-self-signed-tls.sh "$LAN_IP"
mkdir -p .local/nginx-certs-lan
install -m 0644 .local/generated-tls/fullchain.pem .local/nginx-certs-lan/fullchain.pem
install -m 0600 .local/generated-tls/privkey.pem .local/nginx-certs-lan/privkey.pem
python3 scripts/render-livekit-lan-config.py "$LAN_IP"

COMPOSE=(docker compose -f docker-compose.yml -f docker-compose.lan.yml --env-file "$ENV_FILE")
"${COMPOSE[@]}" config --quiet
"${COMPOSE[@]}" up -d --build --force-recreate
"${COMPOSE[@]}" ps

printf '\nLAN Meet is available at: https://%s:8443\n' "$LAN_IP"
printf 'Install and trust this CA on each test device: %s/.local/tls-ca/rootCA.crt\n' "$PROJECT_DIR"
printf 'Allow 8443/TCP and 8443/UDP from the Wi-Fi subnet in the host firewall.\n'
