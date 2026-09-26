#!/usr/bin/env python3
"""Apply source-level Lenovo-runtime compatibility patches.

This tool deliberately patches a source checkout, not a built system image. It
fails closed when the expected Lenovo hook is not present, so it cannot silently
patch an unrelated BatteryService implementation or the stock Xiaomi donor.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path

BATTERY_RELATIVE_PATH = Path("services/core/java/com/android/server/BatteryService.java")
HOOK = "mBatteryServiceManager.updateHealthInfo(healthInfo)"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def patch_battery_service(path: Path) -> bool:
    """Add an NPE/RuntimeException guard around the Lenovo battery callback."""
    if not path.is_file():
        raise RuntimeError(f"BatteryService source not found: {path}")

    original = path.read_text(encoding="utf-8")
    if "Lenovo IBatteryServiceManager reference is null" in original:
        print(f"Battery hook guard already present: {path}")
        return False
    if "mBatteryServiceManager" not in original:
        raise RuntimeError(
            f"{path} does not contain mBatteryServiceManager. "
            "This is not the Lenovo-modified BatteryService from the failing image."
        )
    if "TAG" not in original:
        raise RuntimeError(f"{path} has no TAG constant; refusing to insert an invalid Slog call.")

    # Keep the expression intentionally strict.  An exact, single invocation is
    # required before a framework class is changed.
    invocation = re.compile(
        r"(?m)^(?P<indent>[ \t]*)mBatteryServiceManager\s*\.\s*"
        r"updateHealthInfo\s*\(\s*healthInfo\s*\)\s*;\s*$"
    )
    matches = list(invocation.finditer(original))
    if len(matches) != 1:
        raise RuntimeError(
            f"Expected exactly one standalone '{HOOK}' invocation in {path}; found {len(matches)}. "
            "Inspect the decompiled/custom wrapper and apply the guard at its actual call site."
        )

    indent = matches[0].group("indent")
    guarded_call = "\n".join(
        [
            f"{indent}if (mBatteryServiceManager != null) {{",
            f"{indent}    try {{",
            f"{indent}        mBatteryServiceManager.updateHealthInfo(healthInfo);",
            f"{indent}    }} catch (Exception e) {{",
            f"{indent}        Slog.e(TAG, \"Failed to update Lenovo custom battery info; bypassing.\", e);",
            f"{indent}    }}",
            f"{indent}}} else {{",
            f"{indent}    Slog.w(TAG, \"Lenovo IBatteryServiceManager reference is null; "
            "gracefully bypassing proprietary hooks.\");",
            f"{indent}}}",
        ]
    )
    patched = original[: matches[0].start()] + guarded_call + original[matches[0].end() :]

    if not re.search(r"^import\s+android\.util\.Slog\s*;", patched, re.MULTILINE):
        imports = list(re.finditer(r"^import\s+[^;]+;\s*$", patched, re.MULTILINE))
        if not imports:
            raise RuntimeError(f"No Java import block found in {path}; refusing to add Slog import.")
        insertion = imports[-1].end()
        patched = patched[:insertion] + "\nimport android.util.Slog;" + patched[insertion:]

    path.write_text(patched, encoding="utf-8")
    print(f"Patched Lenovo battery hook: {path}")
    return True


def patch_board_config(path: Path) -> bool:
    """Append the boot argument used by init to request test-only permissive SELinux."""
    if not path.is_file():
        raise RuntimeError(f"BoardConfig.mk not found: {path}")
    original = path.read_text(encoding="utf-8")
    if re.search(r"(?:^|\s)androidboot\.selinux=permissive(?:\s|$)", original):
        print(f"SELinux boot argument already present: {path}")
        return False

    addition = (
        "\n# TEMPORARY DSU compatibility diagnostic: vendor Android 14 sepolicy versus "
        "system Android 17.\n"
        "# Remove after replacing this with the minimum required vendor/system allow rules.\n"
        "BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive\n"
    )
    path.write_text(original.rstrip() + "\n" + addition, encoding="utf-8")
    print(f"Patched SELinux boot argument: {path}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Apply the Lenovo BatteryService guard and the temporary permissive boot argument."
    )
    parser.add_argument("--android-root", type=Path, required=True, help="Android/HyperOS source-tree root")
    parser.add_argument(
        "--boardconfig",
        type=Path,
        required=True,
        help="BoardConfig.mk used to build the boot or vendor_boot image for the DSU test",
    )
    parser.add_argument(
        "--allow-insecure-permissive",
        action="store_true",
        help="Required acknowledgement before adding androidboot.selinux=permissive",
    )
    args = parser.parse_args()

    if not args.allow_insecure_permissive:
        parser.error(
            "Refusing to weaken SELinux without --allow-insecure-permissive. "
            "Use it only for an isolated DSU diagnostic build."
        )

    root = args.android_root.resolve()
    battery = root / BATTERY_RELATIVE_PATH
    boardconfig = args.boardconfig.resolve()
    try:
        battery_changed = patch_battery_service(battery)
        board_changed = patch_board_config(boardconfig)
    except RuntimeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    print("\nPatch summary")
    print(f"  BatteryService: {'changed' if battery_changed else 'unchanged'}")
    print(f"  BoardConfig:    {'changed' if board_changed else 'unchanged'}")
    print(f"  BatteryService SHA-256: {sha256(battery)}")
    print(f"  BoardConfig SHA-256:    {sha256(boardconfig)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
