#!/usr/bin/env python3
"""Generate LiveKit API credentials and write them to an environment file."""

from __future__ import annotations

import ipaddress
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parent.parent
ENV_FILE = PROJECT_DIR / "meet" / ".env.production"
LIVEKIT_IMAGE = "livekit/livekit-server:v1.13.11"


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print(
            f"Usage: {Path(sys.argv[0]).name} <SERVER_IPV4> [ENV_FILE]",
            file=sys.stderr,
        )
        return 2

    try:
        server_ip = str(ipaddress.IPv4Address(sys.argv[1]))
    except ipaddress.AddressValueError:
        print("Expected the IPv4 address used to generate the TLS certificate.", file=sys.stderr)
        return 2

    env_file = Path(sys.argv[2]) if len(sys.argv) == 3 else ENV_FILE
    if not env_file.is_absolute():
        env_file = PROJECT_DIR / env_file

    if not env_file.is_file():
        print(
            f"Missing {env_file}. "
            "Copy meet/.env.production.example first.",
            file=sys.stderr,
        )
        return 1
    if env_file.is_symlink():
        print("Refusing to write credentials through a symlinked env file.", file=sys.stderr)
        return 1

    try:
        result = subprocess.run(
            ["docker", "run", "--rm", LIVEKIT_IMAGE, "generate-keys"],
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        print("Docker CLI is not installed or is not on PATH.", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as exc:
        if exc.stderr:
            print(exc.stderr.rstrip(), file=sys.stderr)
        print("LiveKit key generation failed.", file=sys.stderr)
        return 1

    key_match = re.search(r"^API Key:\s*(\S+)\s*$", result.stdout, re.MULTILINE)
    secret_match = re.search(r"^API Secret:\s*(\S+)\s*$", result.stdout, re.MULTILINE)
    if not key_match or not secret_match:
        print("Could not parse the generated API key/secret output.", file=sys.stderr)
        return 1

    values = {
        "LIVEKIT_URL": f"wss://{server_ip}:8443",
        "LIVEKIT_API_KEY": key_match.group(1),
        "LIVEKIT_API_SECRET": secret_match.group(1),
    }
    lines = env_file.read_text(encoding="utf-8").splitlines()
    updated_lines: list[str] = []
    written: set[str] = set()
    for line in lines:
        name, separator, _ = line.partition("=")
        if separator and name in values:
            if name not in written:
                updated_lines.append(f"{name}={values[name]}")
                written.add(name)
            continue
        updated_lines.append(line)

    for name, value in values.items():
        if name not in written:
            updated_lines.append(f"{name}={value}")

    content = "\n".join(updated_lines) + "\n"
    fd, temp_name = tempfile.mkstemp(prefix=f".{env_file.name}.", dir=env_file.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as temp_file:
            temp_file.write(content)
            temp_file.flush()
            os.fsync(temp_file.fileno())
        os.chmod(temp_name, 0o600)
        os.replace(temp_name, env_file)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)

    print(f"Saved LIVEKIT_URL and generated credentials to {env_file} (mode 0600).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
