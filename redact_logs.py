#!/usr/bin/env python3
"""Redact personal identifiers from Inspect .eval logs and text evidence.

Generic rules (always applied):
  * /home/<user>            -> /home/REDACTED        (except /home/ubuntu/shared)
  * <anything>@gmail.com    -> redacted@example.invalid

Personal terms (usernames, hostnames, names) are NOT stored in this repo.
Supply them one per line in a file via --terms FILE or $REDACT_TERMS_FILE.
Each term is matched as a literal substring, longest first, and replaced with REDACTED.

.eval members are rewritten at the byte level: zip member order and names are kept,
each JSON member is re-compressed with zstd, and only matched substrings change.
Scores, sample counts, and model names are not touched.

Usage:
    python redact_logs.py --terms TERMS --logs IN_DIR OUT_DIR
    python redact_logs.py --terms TERMS --text FILE [FILE ...]      # in-place
    python redact_logs.py --terms TERMS --verify ORIG_DIR OUT_DIR

Requires: zstandard.
"""

import argparse
import glob
import json
import os
import re
import struct
import sys
import zipfile

import zstandard

ZSTD_METHOD = 93
PLACEHOLDER = b"REDACTED"

GENERIC = [
    (re.compile(rb"/home/(?!ubuntu/shared\b)[A-Za-z0-9_.-]+"), b"/home/REDACTED"),
    (re.compile(rb"[A-Za-z0-9._%+-]+@gmail\.com"), b"redacted@example.invalid"),
]


def load_terms(path: str | None) -> list[bytes]:
    path = path or os.environ.get("REDACT_TERMS_FILE")
    if not path:
        return []
    with open(path, "rb") as f:
        terms = [t.strip() for t in f.read().splitlines() if t.strip()]
    return sorted(set(terms), key=len, reverse=True)  # longest first


def build_subs(terms: list[bytes]):
    subs = list(GENERIC)
    for t in terms:
        subs.append((re.compile(re.escape(t)), PLACEHOLDER))
    return subs


def redact_bytes(data: bytes, subs) -> bytes:
    for pat, repl in subs:
        data = pat.sub(repl, data)
    return data


def leak_regex(terms: list[bytes]):
    parts = [re.escape(t) for t in terms] + [rb"@gmail\.com", rb"/home/(?!ubuntu/shared\b|REDACTED\b)[A-Za-z0-9_.-]+"]
    return re.compile(b"|".join(parts), re.IGNORECASE)


def read_members(path: str):
    """Yield (ZipInfo, decompressed bytes). zipfile cannot decode zstd, so read raw."""
    dctx = zstandard.ZstdDecompressor()
    with zipfile.ZipFile(path) as z:
        for info in z.infolist():
            fp = z.fp
            fp.seek(info.header_offset)
            hdr = fp.read(30)
            n_name = int.from_bytes(hdr[26:28], "little")
            n_extra = int.from_bytes(hdr[28:30], "little")
            fp.seek(info.header_offset + 30 + n_name + n_extra)
            blob = fp.read(info.compress_size)
            if info.file_size == 0:
                raw = b""
            elif info.compress_type == ZSTD_METHOD:
                raw = dctx.decompress(blob, max_output_size=info.file_size * 4 + 1024)
            elif info.compress_type == 0:
                raw = blob
            else:
                raise RuntimeError(f"{path}:{info.filename}: unsupported method {info.compress_type}")
            yield info, raw


def patch_methods_to_zstd(path: str) -> None:
    """Set the compression-method field to zstd (93) in each local and central header."""
    with open(path, "r+b") as f:
        data = f.read()
        eocd = data.rfind(b"PK\x05\x06")
        cd_count = struct.unpack_from("<H", data, eocd + 10)[0]
        cd_off = struct.unpack_from("<I", data, eocd + 16)[0]
        method = struct.pack("<H", ZSTD_METHOD)
        pos = cd_off
        for _ in range(cd_count):
            assert data[pos:pos + 4] == b"PK\x01\x02", "bad central directory record"
            n, e, c = struct.unpack_from("<HHH", data, pos + 28)
            local_off = struct.unpack_from("<I", data, pos + 42)[0]
            f.seek(pos + 10)
            f.write(method)
            f.seek(local_off + 8)
            f.write(method)
            pos += 46 + n + e + c


def redact_eval(src: str, dst: str, subs) -> dict:
    cctx = zstandard.ZstdCompressor(level=3)
    stats = {"members": 0, "length_delta": 0}
    tmp = dst + ".tmp"
    with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_STORED) as out:
        for info, raw in read_members(src):
            red = redact_bytes(raw, subs)
            stats["members"] += 1
            stats["length_delta"] += len(red) - len(raw)
            zi = zipfile.ZipInfo(info.filename, date_time=info.date_time)
            zi.compress_type = zipfile.ZIP_STORED  # patched to zstd below
            out.writestr(zi, cctx.compress(red) if red else b"")
    patch_methods_to_zstd(tmp)
    os.replace(tmp, dst)
    return stats


def verify_eval(orig: str, red: str, leak) -> list[str]:
    problems = []
    names_orig = [i.filename for i in zipfile.ZipFile(orig).infolist()]
    names_red = [i.filename for i in zipfile.ZipFile(red).infolist()]
    if names_orig != names_red:
        problems.append("member list/order differs")
    for info, raw in read_members(red):
        if leak.search(raw):
            problems.append(f"residual identifier in {info.filename}")
        if info.filename.endswith(".json") and raw:
            try:
                json.loads(raw)
            except json.JSONDecodeError as e:
                problems.append(f"invalid JSON in {info.filename}: {e}")
    return problems


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--terms", help="file with one personal term per line (kept outside the repo)")
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--logs", nargs=2, metavar=("IN_DIR", "OUT_DIR"))
    mode.add_argument("--text", nargs="+", metavar="FILE", help="redact text files in place")
    mode.add_argument("--verify", nargs=2, metavar=("ORIG_DIR", "RED_DIR"))
    a = ap.parse_args()
    terms = load_terms(a.terms)
    subs = build_subs(terms)
    if a.logs:
        in_dir, out_dir = a.logs
        os.makedirs(out_dir, exist_ok=True)
        files = sorted(glob.glob(os.path.join(in_dir, "*.eval")))
        for src in files:
            st = redact_eval(src, os.path.join(out_dir, os.path.basename(src)), subs)
            print(f"{os.path.basename(src)}: members={st['members']} length_delta={st['length_delta']}")
        print(f"redacted {len(files)} logs -> {out_dir} (terms={len(terms)})")
        return 0
    if a.text:
        changed = []
        for p in a.text:
            data = open(p, "rb").read()
            new = redact_bytes(data, subs)
            if new != data:
                open(p, "wb").write(new)
                changed.append(p)
        print("text files changed:", changed)
        return 0
    orig_dir, red_dir = a.verify
    leak = leak_regex(terms)
    reds = sorted(glob.glob(os.path.join(red_dir, "*.eval")))
    failures = 0
    for red in reds:
        probs = verify_eval(os.path.join(orig_dir, os.path.basename(red)), red, leak)
        if probs:
            failures += 1
            print(f"FAIL {os.path.basename(red)}: {probs}")
    print(f"verified {len(reds)} logs, failures={failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
