#!/usr/bin/env python3
"""Convert Android sparse data transfer images (*.transfer.list + *.new.dat) to raw .img."""

import sys

BLOCK_SIZE = 4096


def parse_ranges(range_str: str) -> list[tuple[int, int]]:
    vals = [int(x) for x in range_str.split(",") if x]
    if not vals:
        return []
    count = vals[0]
    coords = vals[1:]
    if len(coords) != count:
        raise ValueError(f"Range count mismatch: expected {count}, got {len(coords)}")
    return [(coords[i], coords[i + 1]) for i in range(0, len(coords), 2)]


def sdat2img(transfer_list_path: str, new_dat_path: str, output_img_path: str) -> None:
    with open(transfer_list_path, "r", encoding="utf-8") as tl:
        version_line = tl.readline().strip()
        if not version_line:
            raise ValueError("Empty transfer.list")
        version = int(version_line)
        _new_blocks = int(tl.readline().strip())
        if version >= 2:
            tl.readline()  # stash entries
            if version >= 3:
                tl.readline()  # max stash blocks

        max_end_block = 0
        commands: list[tuple[str, list[tuple[int, int]]]] = []
        for raw_line in tl:
            line = raw_line.strip()
            if not line:
                continue
            parts = line.split(" ", 1)
            cmd = parts[0]
            if cmd in ("new", "zero", "erase") and len(parts) == 2:
                ranges = parse_ranges(parts[1])
                for _start, end in ranges:
                    if end > max_end_block:
                        max_end_block = end
                if cmd == "new":
                    commands.append((cmd, ranges))

    with open(output_img_path, "wb") as out_f, open(new_dat_path, "rb") as dat_f:
        for _cmd, ranges in commands:
            for start, end in ranges:
                out_f.seek(start * BLOCK_SIZE)
                remaining = (end - start) * BLOCK_SIZE
                while remaining > 0:
                    chunk = dat_f.read(min(remaining, 4 * 1024 * 1024))
                    if not chunk:
                        raise EOFError("Unexpected EOF in .new.dat")
                    out_f.write(chunk)
                    remaining -= len(chunk)
        if max_end_block > 0:
            out_f.truncate(max_end_block * BLOCK_SIZE)


def main() -> int:
    if len(sys.argv) != 4:
        print("Usage: sdat2img.py <transfer.list> <new.dat> <output.img>", file=sys.stderr)
        return 2
    sdat2img(sys.argv[1], sys.argv[2], sys.argv[3])
    print(f"sdat2img: wrote {sys.argv[3]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
