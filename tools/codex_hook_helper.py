#!/usr/bin/env python3

import json
import os
import socket
import sys
from pathlib import Path


SOCKET_PATH = os.environ.get(
    "CODEX_ISLAND_SOCKET",
    str(Path.home() / ".codex" / "codex-island-helper.sock"),
)


def decode_relay_response(payload: bytes):
    try:
        decoded = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None

    if not isinstance(decoded, dict):
        return None

    decision = decoded.get("decision")
    if decision == "approve":
        return b""

    if decision == "deny":
        hook_response = decoded.get("hookResponse")
        if hook_response is None:
            return b""
        return json.dumps(hook_response, separators=(",", ":")).encode("utf-8")

    return None


def forward_payload(payload: bytes) -> int:
    if not payload:
        return 0

    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(1.0)
            client.connect(SOCKET_PATH)
            client.settimeout(None)
            client.sendall(payload)
            client.shutdown(socket.SHUT_WR)

            response = bytearray()
            while True:
                chunk = client.recv(65536)
                if not chunk:
                    break
                response.extend(chunk)

                relay_output = decode_relay_response(bytes(response))
                if relay_output is not None:
                    if relay_output:
                        sys.stdout.buffer.write(relay_output)
                    return 0

            if response:
                sys.stdout.buffer.write(bytes(response))

        return 0
    except OSError:
        return 0


def main() -> int:
    return forward_payload(sys.stdin.buffer.read())


if __name__ == "__main__":
    raise SystemExit(main())
