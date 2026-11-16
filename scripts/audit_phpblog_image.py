#!/usr/bin/env python3
"""Read-only inspection and selective extraction for the phpblog lab image."""

from __future__ import annotations

import argparse
import os
from pathlib import Path

import pytsk3


PARTITION_OFFSET = 2048 * 512


class ImageAuditor:
    def __init__(self, image_path: str) -> None:
        self.image = pytsk3.Img_Info(image_path)
        self.fs = pytsk3.FS_Info(self.image, offset=PARTITION_OFFSET)

    @staticmethod
    def _name(entry: pytsk3.Directory) -> str:
        return entry.info.name.name.decode("utf-8", errors="replace")

    def walk(self, root: str):
        try:
            directory = self.fs.open_dir(path=root)
        except OSError:
            return

        for entry in directory:
            name = self._name(entry)
            if name in {".", ".."}:
                continue
            path = os.path.join(root, name).replace("\\", "/")
            yield entry, path
            if entry.info.meta and entry.info.meta.type == pytsk3.TSK_FS_META_TYPE_DIR:
                yield from self.walk(path)

    def read(self, path: str) -> bytes:
        entry = self.fs.open(path)
        return entry.read_random(0, entry.info.meta.size)

    def extract_tree(self, source_root: str, destination_root: Path) -> int:
        count = 0
        for entry, source_path in self.walk(source_root):
            if not entry.info.meta or entry.info.meta.type != pytsk3.TSK_FS_META_TYPE_REG:
                continue
            relative = source_path.removeprefix("/")
            destination = destination_root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(self.read(source_path))
            count += 1
        return count

    def find(self, root: str, needles: tuple[str, ...], max_results: int = 500):
        results = []
        for entry, path in self.walk(root):
            lowered = path.lower()
            if any(needle in lowered for needle in needles):
                results.append((entry, path))
                if len(results) >= max_results:
                    break
        return results


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("image")
    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list")
    list_parser.add_argument("root")

    find_parser = subparsers.add_parser("find")
    find_parser.add_argument("root")
    find_parser.add_argument("needles", nargs="+")

    extract_parser = subparsers.add_parser("extract")
    extract_parser.add_argument("source_root")
    extract_parser.add_argument("destination_root")

    extract_file_parser = subparsers.add_parser("extract-file")
    extract_file_parser.add_argument("source_file")
    extract_file_parser.add_argument("destination_file")

    args = parser.parse_args()
    auditor = ImageAuditor(args.image)

    if args.command == "list":
        for entry, path in auditor.walk(args.root):
            kind = "dir" if entry.info.meta.type == pytsk3.TSK_FS_META_TYPE_DIR else "file"
            print(f"{kind:4} {entry.info.meta.size:10} {path}")
    elif args.command == "find":
        needles = tuple(item.lower() for item in args.needles)
        for entry, path in auditor.find(args.root, needles):
            meta = entry.info.meta
            kind = "dir" if meta and meta.type == pytsk3.TSK_FS_META_TYPE_DIR else "file"
            size = meta.size if meta else 0
            print(f"{kind:4} {size:10} {path}")
    elif args.command == "extract":
        destination = Path(args.destination_root)
        count = auditor.extract_tree(args.source_root, destination)
        print(f"Extracted {count} files to {destination}")
    elif args.command == "extract-file":
        destination = Path(args.destination_file)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(auditor.read(args.source_file))
        print(f"Extracted {args.source_file} to {destination}")


if __name__ == "__main__":
    main()
