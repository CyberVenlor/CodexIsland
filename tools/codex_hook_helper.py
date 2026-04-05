#!/usr/bin/env python3

import os
import socket
import sys
from pathlib import Path


SOCKET_PATH = os.environ.get(
    "CODEX_ISLAND_SOCKET",
    str(Path.home() / ".codex" / "codex-island-helper.sock"),
)


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

            while True:
                chunk = client.recv(65536)
                if not chunk:
                    break
                sys.stdout.buffer.write(chunk)

        return 0
    except OSError:
        return 0


def main() -> int:
    return forward_payload(sys.stdin.buffer.read())


if __name__ == "__main__":
    raise SystemExit(main())
