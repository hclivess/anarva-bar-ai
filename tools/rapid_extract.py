"""Extract files from a Rapid (.sdp) package in the BAR data folder.

Usage: python rapid_extract.py <data_dir> <sdp_hash> <out_dir> [path_prefix ...]
  With no prefixes, lists all paths instead of extracting.
"""
import gzip
import os
import struct
import sys


def read_sdp(path):
    raw = gzip.open(path, "rb").read()
    i, entries = 0, []
    while i < len(raw):
        n = raw[i]
        i += 1
        name = raw[i:i + n].decode("utf-8", "replace")
        i += n
        md5 = raw[i:i + 16].hex()
        i += 16
        _crc, size = struct.unpack(">II", raw[i:i + 8])
        i += 8
        entries.append((name, md5, size))
    return entries


def main():
    data_dir, sdp_hash, out_dir = sys.argv[1:4]
    prefixes = [p.lower() for p in sys.argv[4:]]
    entries = read_sdp(os.path.join(data_dir, "packages", sdp_hash + ".sdp"))
    if not prefixes:
        for name, _, size in entries:
            print(size, name)
        return
    count = 0
    for name, md5, _ in entries:
        if not any(name.lower().startswith(p) for p in prefixes):
            continue
        src = os.path.join(data_dir, "pool", md5[:2], md5[2:] + ".gz")
        dst = os.path.join(out_dir, *name.split("/"))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with gzip.open(src, "rb") as f, open(dst, "wb") as o:
            o.write(f.read())
        count += 1
    print("extracted", count, "files")


if __name__ == "__main__":
    main()
