#!/usr/bin/env python3
"""
cut_paste.py — move or copy a line range from one file to another.

Usage:
    ./cut_paste.py copy <src> <start> <end> <dst> <dst_line>
    ./cut_paste.py cut  <src> <start> <end> <dst> <dst_line>

Arguments:
    src       source file path
    start     first line to extract (1-indexed, inclusive)
    end       last line to extract (1-indexed, inclusive)
    dst       destination file path (created if it doesn't exist)
    dst_line  line number in dst to insert BEFORE; 0 = append

Modes:
    copy  — copy lines to dst, leave src unchanged
    cut   — move lines to dst, remove them from src

Prints a diff-style preview and asks for confirmation before writing.
Pass --yes to skip confirmation.
"""

import argparse
import sys
from pathlib import Path


def read_lines(path: Path) -> list[str]:
    return path.read_text().splitlines(keepends=True) if path.exists() else []


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mode", choices=["copy", "cut"])
    parser.add_argument("src")
    parser.add_argument("start", type=int)
    parser.add_argument("end", type=int)
    parser.add_argument("dst")
    parser.add_argument("dst_line", type=int)
    parser.add_argument("--yes", action="store_true", help="skip confirmation")
    args = parser.parse_args()

    src = Path(args.src)
    dst = Path(args.dst)
    same_file = src.resolve() == dst.resolve() if dst.exists() else src.resolve() == dst.absolute()

    if not src.exists():
        sys.exit(f"error: source file not found: {src}")

    src_lines = read_lines(src)
    total = len(src_lines)

    if args.start < 1 or args.end > total or args.start > args.end:
        sys.exit(f"error: line range {args.start}–{args.end} invalid for file with {total} lines")

    # Extract (0-indexed slice)
    extracted = src_lines[args.start - 1 : args.end]

    if same_file:
        # Single self-consistent transform: remove the range (if cut),
        # then insert at dst_line -- expressed in the ORIGINAL src's line
        # numbers, so the insertion point is remapped below if it fell
        # at or after the removed range.
        base = src_lines[: args.start - 1] + src_lines[args.end :] if args.mode == "cut" else src_lines
        if args.dst_line == 0:
            new_dst = base + extracted
            insert_desc = "appended"
        else:
            if args.mode == "cut" and args.dst_line > args.end:
                pos = args.dst_line - 1 - len(extracted)
            elif args.mode == "cut" and args.dst_line > args.start:
                pos = args.start - 1
            else:
                pos = args.dst_line - 1
            if pos > len(base):
                sys.exit(f"error: dst_line {args.dst_line} exceeds destination length after edit")
            new_dst = base[:pos] + extracted + base[pos:]
            insert_desc = f"inserted before line {args.dst_line}"
        new_src = new_dst
    else:
        # Build new src (cut only)
        new_src = src_lines[: args.start - 1] + src_lines[args.end :] if args.mode == "cut" else src_lines

        # Build new dst
        dst_lines = read_lines(dst)
        if args.dst_line == 0:
            new_dst = dst_lines + extracted
            insert_desc = "appended"
        else:
            if args.dst_line > len(dst_lines) + 1:
                sys.exit(f"error: dst_line {args.dst_line} exceeds destination length {len(dst_lines)}")
            pos = args.dst_line - 1
            new_dst = dst_lines[:pos] + extracted + dst_lines[pos:]
            insert_desc = f"inserted before line {args.dst_line}"

    print(f"{'CUT' if args.mode == 'cut' else 'COPY'} lines {args.start}-{args.end} from {src} -> {dst} "
          f"({insert_desc}, {len(extracted)} lines)")

    if not args.yes:
        answer = input("Proceed? [y/N] ").strip().lower()
        if answer != "y":
            sys.exit("aborted")

    dst.parent.mkdir(parents=True, exist_ok=True)
    if same_file:
        dst.write_text("".join(new_dst))
    else:
        dst.write_text("".join(new_dst))
        if args.mode == "cut":
            src.write_text("".join(new_src))

    print(f"done - wrote {dst}" + (f", updated {src}" if args.mode == "cut" and not same_file else ""))


if __name__ == "__main__":
    main()
