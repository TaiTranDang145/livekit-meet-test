#!/usr/bin/env python3
"""Render a LAN-specific LiveKit config without editing the product config."""

from __future__ import annotations

import ipaddress
import os
import re
import sys
import tempfile
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parent.parent
SOURCE_FILE = PROJECT_DIR / "livekit.yml"
OUTPUT_FILE = PROJECT_DIR / ".local" / "livekit-lan.yml"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {Path(sys.argv[0]).name} <LAN_IPV4>", file=sys.stderr)
        return 2

    try:
        lan_ip = ipaddress.IPv4Address(sys.argv[1])
    except ipaddress.AddressValueError:
        print("Expected a private LAN IPv4 address.", file=sys.stderr)
        return 2

    if not lan_ip.is_private or lan_ip.is_loopback or lan_ip.is_link_local:
        print("Expected a private LAN IPv4 address, not loopback or link-local.", file=sys.stderr)
        return 2

    config = SOURCE_FILE.read_text(encoding="utf-8")
    config = re.sub(r"(?m)^  node_ip:\s*.*(?:\n|$)", "", config)
    pattern = re.compile(r"(?m)^  use_external_ip:\s*(?:true|false)\s*$")
    if len(pattern.findall(config)) != 1:
        print(
            f"Expected exactly one rtc.use_external_ip setting in {SOURCE_FILE.name}.",
            file=sys.stderr,
        )
        return 1

    rendered = pattern.sub(
        f"  use_external_ip: false\n  node_ip: {lan_ip}", config, count=1
    )
    OUTPUT_FILE.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=".livekit-lan.", dir=OUTPUT_FILE.parent
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary_file:
            temporary_file.write(rendered)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.chmod(temporary_name, 0o644)
        os.replace(temporary_name, OUTPUT_FILE)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)

    print(f"Generated {OUTPUT_FILE.relative_to(PROJECT_DIR)} for {lan_ip}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
