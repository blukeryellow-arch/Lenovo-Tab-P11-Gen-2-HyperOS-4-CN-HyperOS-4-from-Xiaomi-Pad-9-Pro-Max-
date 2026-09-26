#!/usr/bin/env python3
"""Extract selected logical partitions directly from an Android sparse super image.

This avoids materializing a full raw ``super.img``.  That is important for CI
runners: a sparse super image plus its full raw expansion can exceed the
available working disk even though the selected system partitions fit.

The Android logical-partition metadata parser is intentionally supplied at run
time (``--lpunpack``).  This wrapper only supplies sparse-image random access;
it never modifies the source image.
"""

from __future__ import annotations

import argparse
import bisect
import importlib.util
import io
import struct
import sys
from pathlib import Path
from typing import BinaryIO

SPARSE_MAGIC = 0xED26FF3A
CHUNK_RAW = 0xCAC1
CHUNK_FILL = 0xCAC2
CHUNK_DONT_CARE = 0xCAC3


class SparseVirtualFile:
    """Read-only random-access view of the expanded Android sparse stream."""

    def __init__(self, source: BinaryIO) -> None:
        self._source = source
        self._position = 0
        header = source.read(28)
        if len(header) != 28:
            raise ValueError("truncated sparse header")
        (
            magic,
            _major,
            _minor,
            file_header_size,
            chunk_header_size,
            block_size,
            _total_blocks,
            total_chunks,
            _checksum,
        ) = struct.unpack("<I4H4I", header)
        if magic != SPARSE_MAGIC:
            raise ValueError("not an Android sparse image")
        if file_header_size < 28 or chunk_header_size < 12:
            raise ValueError("invalid sparse header sizes")

        source.seek(file_header_size)
        self._chunks: list[tuple[int, int, int, int]] = []
        raw_offset = 0
        for _ in range(total_chunks):
            chunk_at = source.tell()
            chunk_header = source.read(chunk_header_size)
            if len(chunk_header) != chunk_header_size:
                raise ValueError("truncated sparse chunk header")
            chunk_type, _reserved, chunk_blocks, chunk_total_size = struct.unpack(
                "<2H2I", chunk_header[:12]
            )
            output_size = chunk_blocks * block_size
            if chunk_total_size < chunk_header_size:
                raise ValueError("invalid sparse chunk size")
            self._chunks.append((raw_offset, raw_offset + output_size, chunk_type, chunk_at + chunk_header_size))
            raw_offset += output_size
            source.seek(chunk_at + chunk_total_size)
        self._starts = [chunk[0] for chunk in self._chunks]
        self.size = raw_offset
        self.name = getattr(source, "name", "sparse-super.img")

    def seek(self, offset: int, whence: int = io.SEEK_SET) -> int:
        if whence == io.SEEK_SET:
            self._position = offset
        elif whence == io.SEEK_CUR:
            self._position += offset
        elif whence == io.SEEK_END:
            self._position = self.size + offset
        else:
            raise ValueError("invalid seek origin")
        if self._position < 0:
            raise ValueError("negative seek")
        return self._position

    def read(self, count: int = -1) -> bytes:
        if count < 0:
            count = self.size - self._position
        count = min(count, self.size - self._position)
        output = bytearray()
        while count:
            index = bisect.bisect_right(self._starts, self._position) - 1
            if index < 0:
                raise ValueError("sparse read before the first chunk")
            start, end, chunk_type, data_offset = self._chunks[index]
            if self._position >= end:
                raise ValueError("sparse chunk map has a gap")
            take = min(count, end - self._position)
            in_chunk = self._position - start
            if chunk_type == CHUNK_RAW:
                self._source.seek(data_offset + in_chunk)
                data = self._source.read(take)
                if len(data) != take:
                    raise ValueError("truncated sparse raw chunk")
            elif chunk_type == CHUNK_FILL:
                self._source.seek(data_offset)
                pattern = self._source.read(4)
                if len(pattern) != 4:
                    raise ValueError("truncated sparse fill chunk")
                data = (pattern * ((in_chunk % 4 + take + 3) // 4))[in_chunk % 4 : in_chunk % 4 + take]
            elif chunk_type == CHUNK_DONT_CARE:
                data = b"\0" * take
            else:
                # CRC chunks do not normally carry output blocks. If a vendor
                # emits an output-bearing unknown chunk, presenting zeroes is
                # safer than reading unrelated compressed data.
                data = b"\0" * take
            output.extend(data)
            self._position += take
            count -= take
        return bytes(output)

    def close(self) -> None:
        self._source.close()


def load_lpunpack(path: Path):
    spec = importlib.util.spec_from_file_location("audit_lpunpack", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load lpunpack implementation: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lpunpack", type=Path, required=True, help="downloaded lpunpack.py metadata parser")
    parser.add_argument("--list", action="store_true", help="print logical partition names and exit")
    parser.add_argument("--partition", action="append", help="logical partition name (repeatable)")
    parser.add_argument("super_image", type=Path)
    parser.add_argument("output_dir", type=Path, nargs="?")
    args = parser.parse_args()
    if not args.list and (not args.partition or args.output_dir is None):
        parser.error("--partition and OUTPUT_DIR are required unless --list is used")

    lpmod = load_lpunpack(args.lpunpack)
    requested = set(args.partition or [])
    with args.super_image.open("rb") as sparse_source:
        virtual_super = SparseVirtualFile(sparse_source)
        unpacker = lpmod.LpUnpack(SUPER_IMAGE=str(args.super_image), OUTPUT_DIR=args.output_dir)
        unpacker._fd.close()
        unpacker._fd = virtual_super
        metadata = unpacker._read_metadata()
        if args.list:
            for partition in metadata.partitions:
                print(partition.name)
            return 0
        selected = [partition for partition in metadata.partitions if partition.name in requested]
        missing = sorted(requested - {partition.name for partition in selected})
        if missing:
            available = ", ".join(partition.name for partition in metadata.partitions)
            raise RuntimeError(f"requested partitions not present: {', '.join(missing)}; available: {available}")
        args.output_dir.mkdir(parents=True, exist_ok=True)
        metadata.partitions = selected
        for partition in selected:
            unpacker._extract(partition, metadata)
        virtual_super.close()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"sparse super extraction failed: {error}", file=sys.stderr)
        raise SystemExit(1)
