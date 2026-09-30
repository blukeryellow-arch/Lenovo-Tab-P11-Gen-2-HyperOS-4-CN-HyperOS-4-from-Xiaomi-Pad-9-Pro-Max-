#!/usr/bin/env python3
"""Parse AOSP lpdump text and emit deterministic lpmake arguments.

The generated shell script is a review artifact, not executed automatically.
Supports the standard single-block-device super layout used by most phones/tablets.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass, asdict
import json
from pathlib import Path
import re
import shlex
import sys


@dataclass
class Partition:
    name: str
    group: str
    attributes: str
    sectors: int = 0

    @property
    def size(self) -> int:
        return self.sectors * 512


@dataclass
class Metadata:
    metadata_max_size: int
    metadata_slot_count: int
    block_device_name: str
    block_device_size: int
    block_device_flags: str
    header_flags: str
    super_name: str
    groups: dict[str, int]
    partitions: list[Partition]


def _integer(pattern: str, text: str, label: str) -> int:
    match = re.search(pattern, text, re.MULTILINE | re.IGNORECASE)
    if not match:
        raise ValueError(f"cannot find {label} in lpdump output")
    return int(match.group(1))


def parse_lpdump(text: str) -> Metadata:
    max_size = _integer(r"^Metadata max size:\s*(\d+)", text, "metadata max size")
    slot_count = _integer(r"^Metadata slot count:\s*(\d+)", text, "metadata slot count")

    block_section = re.search(
        r"^Block device table:\s*\n(?P<body>.*?)(?:^Group table:|\Z)",
        text, re.MULTILINE | re.DOTALL | re.IGNORECASE,
    )
    if not block_section:
        raise ValueError("cannot find block device table")
    block_body = block_section.group("body")
    block_names = re.findall(r"^\s*Partition name:\s*(\S+)", block_body, re.MULTILINE)
    block_sizes = re.findall(r"^\s*Size:\s*(\d+)", block_body, re.MULTILINE)
    block_flags = re.findall(r"^\s*Flags:\s*(.*?)\s*$", block_body, re.MULTILINE)
    if len(block_names) != 1 or len(block_sizes) != 1:
        raise ValueError("only a single LP block device is supported; refusing ambiguous geometry")
    block_flag = block_flags[0] if block_flags else "none"

    group_section = re.search(
        r"^Group table:\s*\n(?P<body>.*?)(?:^Partition table:|\Z)",
        text, re.MULTILINE | re.DOTALL | re.IGNORECASE,
    )
    if not group_section:
        raise ValueError("cannot find group table")
    groups: dict[str, int] = {}
    for chunk in re.split(r"^-{3,}\s*$", group_section.group("body"), flags=re.MULTILINE):
        name = re.search(r"^\s*Name:\s*(\S+)", chunk, re.MULTILINE)
        maximum = re.search(r"^\s*Maximum size:\s*(\d+)", chunk, re.MULTILINE)
        if name and maximum:
            groups[name.group(1)] = int(maximum.group(1))
    if not groups:
        raise ValueError("no LP groups parsed")

    partition_section = re.search(
        r"^Partition table:\s*\n(?P<body>.*?)(?:^Block device table:|\Z)",
        text, re.MULTILINE | re.DOTALL | re.IGNORECASE,
    )
    if not partition_section:
        raise ValueError("cannot find partition table")
    partitions: list[Partition] = []
    for chunk in re.split(r"^-{3,}\s*$", partition_section.group("body"), flags=re.MULTILINE):
        name = re.search(r"^\s*Name:\s*(\S+)", chunk, re.MULTILINE)
        group = re.search(r"^\s*Group:\s*(\S+)", chunk, re.MULTILINE)
        attrs = re.search(r"^\s*Attributes:\s*(.*?)\s*$", chunk, re.MULTILINE)
        if not (name and group):
            continue
        sectors = 0
        # Typical form: "0 .. 2047 linear super 2048". Count zero extents too;
        # both forms occupy logical sectors and therefore affect image size.
        for start, end in re.findall(r"^\s*(\d+)\s*\.\.\s*(\d+)\s+(?:linear|zero)\b", chunk, re.MULTILINE):
            first, last = int(start), int(end)
            if last < first:
                raise ValueError(f"invalid extent in {name.group(1)}")
            sectors += last - first + 1
        if sectors == 0:
            # Alternate lpdump releases print "Extent 0: ... length N".
            sectors = sum(int(n) for n in re.findall(r"\b(?:num_sectors|length):\s*(\d+)", chunk))
        partitions.append(Partition(name.group(1), group.group(1), (attrs.group(1) if attrs else "readonly") or "none", sectors))
    if not partitions or any(p.sectors == 0 for p in partitions):
        raise ValueError("one or more partition extents could not be parsed")

    super_name_match = re.search(r"^Super partition name:\s*(\S+)", text, re.MULTILINE | re.IGNORECASE)
    super_name = super_name_match.group(1) if super_name_match else block_names[0]
    header_match = re.search(r"^Header flags:\s*(.*?)\s*$", text, re.MULTILINE | re.IGNORECASE)
    header_flags = header_match.group(1) if header_match else "none"
    return Metadata(max_size, slot_count, block_names[0], int(block_sizes[0]), block_flag,
                    header_flags, super_name, groups, partitions)


def make_command(metadata: Metadata, images: Path, output: Path) -> list[str]:
    command = [
        "lpmake", "--metadata-size", str(metadata.metadata_max_size),
        "--metadata-slots", str(metadata.metadata_slot_count),
        "--super-name", metadata.super_name,
        "--device", f"{metadata.block_device_name}:{metadata.block_device_size}",
    ]
    if "virtual_ab" in metadata.header_flags:
        command.append("--virtual-ab")
    if "slot" in metadata.block_device_flags.lower():
        command.append("--auto-slot-suffixing")
    for name in sorted(metadata.groups):
        command += ["--group", f"{name}:{metadata.groups[name]}"]
    for part in sorted(metadata.partitions, key=lambda p: p.name):
        image = images / f"{part.name}.img"
        attributes = "readonly" if "readonly" in part.attributes else "none"
        command += ["--partition", f"{part.name}:{attributes}:{part.size}:{part.group}"]
        command += ["--image", f"{part.name}={image}"]
    command += ["--sparse", "--output", str(output)]
    return command


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("lpdump")
    parser.add_argument("--images", default="work/partitions")
    parser.add_argument("--output", default="out/super-v16.img")
    parser.add_argument("--json")
    parser.add_argument("--shell")
    args = parser.parse_args()
    try:
        metadata = parse_lpdump(Path(args.lpdump).read_text())
        command = make_command(metadata, Path(args.images), Path(args.output))
    except (OSError, ValueError) as exc:
        print(f"lp_metadata: {exc}", file=sys.stderr)
        return 2
    payload = asdict(metadata)
    payload["lpmake_argv"] = command
    rendered_json = json.dumps(payload, indent=2) + "\n"
    rendered_shell = "#!/bin/sh\nset -eu\n" + shlex.join(command) + "\n"
    if args.json:
        Path(args.json).write_text(rendered_json)
    else:
        print(rendered_json, end="")
    if args.shell:
        path = Path(args.shell)
        path.write_text(rendered_shell)
        path.chmod(0o755)
    return 0


if __name__ == "__main__":
    sys.exit(main())
