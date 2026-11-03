#!/usr/bin/env python3
"""Create shared AWG 3 settings; append the same block to both Interface sections."""

import argparse
import base64
import os
from pathlib import Path
import secrets


def build_settings() -> str:
    s1 = 16 + secrets.randbelow(80)
    s2 = 16 + secrets.randbelow(80)
    while s1 + 148 == s2 + 92:
        s2 = 16 + secrets.randbelow(80)
    headers = secrets.SystemRandom().sample(range(10000, 4294967200, 100), 4)
    values = {
        "Jc": 4 + secrets.randbelow(5),
        "Jmin": 40 + secrets.randbelow(40),
        "Jmax": 500 + secrets.randbelow(700),
        "S1": s1,
        "S2": s2,
        "S3": 16 + secrets.randbelow(32),
        "S4": 16 + secrets.randbelow(32),
        **{f"H{i + 1}": f"{value}-{value + 9}" for i, value in enumerate(headers)},
        "HeaderProtectionKey": base64.b64encode(secrets.token_bytes(32)).decode("ascii"),
        "ContentPaddingAddition": "16-32",
    }
    return "".join(f"{key} = {value}\n" for key, value in values.items())


def write_settings(destination: Path) -> None:
    # Exclusive creation avoids overwriting deployed settings or following a symlink.
    fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="ascii") as output:
        output.write(build_settings())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="new private file in an existing directory")
    args = parser.parse_args()
    try:
        write_settings(args.output)
    except OSError as error:
        parser.exit(1, f"Cannot create settings file: {error.strerror}\n")
    print("Created private AWG 3 settings. Use MTU 1280 and the same block on server and clients.")
    print("Keep HeaderProtectionKey private; these settings do not replace each device's own keys.")


if __name__ == "__main__":
    main()
