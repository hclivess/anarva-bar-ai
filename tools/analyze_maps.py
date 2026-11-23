"""Pre-match map analysis, like a player studying the map: reads BAR map archives (.sd7) and
computes, per map: size, start positions, extractor spots (from the metal map), base-to-base path
distance and the narrowest corridor on it (chokes), water share and geo vents.
Writes a JSON report and an AngelScript facts file the AI loads at game start.

usage: python analyze_maps.py <maps_dir> <out.json> <out.as> [map file names...]
Requires py7zr (dev only).
"""
import heapq
import io
import json
import math
import os
import re
import struct
import sys

import py7zr

SQUARE = 8           # elmos per heightmap square
CELL = 4             # analysis cell = 4 heightmap squares = 32 elmos
MAX_SLOPE = 0.41     # bot movedef max slope (vbot/kbot), a game fact


def read_archive(path):
    import tempfile
    with py7zr.SevenZipFile(path, "r") as z:
        names = z.getnames()
    smf = next((n for n in names if n.lower().endswith(".smf")), None)
    info = next((n for n in names if n.lower() == "mapinfo.lua"), None) or next((n for n in names if n.lower().endswith("/mapinfo.lua")), None)
    want = [n for n in (smf, info) if n]
    out = {}
    with tempfile.TemporaryDirectory() as tmp:
        with py7zr.SevenZipFile(path, "r") as z:
            z.extract(path=tmp, targets=want)
        for n in want:
            with open(os.path.join(tmp, *n.split("/")), "rb") as f:
                out[n] = f.read()
    return out, smf, info


def parse_smf(raw, override=None):
    (magic, ver, mapid, mapx, mapy, sq, tex, tile, minh, maxh, hptr, typeptr, tilesptr, minimapptr,
     metalptr, featptr) = struct.unpack_from("<16siiiiiiiffiiiiii", raw, 0)
    w, h = mapx + 1, mapy + 1
    heights = struct.unpack_from("<%dH" % (w * h), raw, hptr)
    if override:  # mapinfo.lua smf = { minheight, maxheight } replaces the header values
        minh, maxh = override.get("min", minh), override.get("max", maxh)
    scale = (maxh - minh) / 65536.0
    hm = [minh + v * scale for v in heights]
    mw, mh = mapx // 2, mapy // 2
    metal = raw[metalptr:metalptr + mw * mh]
    return {"mapx": mapx, "mapy": mapy, "hm": hm, "hw": w, "hh": h, "metal": metal, "mw": mw, "mh": mh}


def parse_starts(info_text):
    starts = []
    for m in re.finditer(r"startpos\s*=\s*\{\s*x\s*=\s*([\d.]+)\s*,\s*z\s*=\s*([\d.]+)", info_text, re.I):
        starts.append((float(m.group(1)), float(m.group(2))))
    return starts


def mex_spots(smf):
    """Connected components of metal-map pixels -> spot centres (elmos) and richness."""
    mw, mh, metal = smf["mw"], smf["mh"], smf["metal"]
    seen = bytearray(mw * mh)
    spots = []
    for i in range(mw * mh):
        if metal[i] == 0 or seen[i]:
            continue
        stack, pix, tot = [i], [], 0
        seen[i] = 1
        while stack:
            j = stack.pop()
            pix.append(j)
            tot += metal[j]
            x, z = j % mw, j // mw
            for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, nz = x + dx, z + dz
                if 0 <= nx < mw and 0 <= nz < mh:
                    k = nz * mw + nx
                    if metal[k] and not seen[k]:
                        seen[k] = 1
                        stack.append(k)
        if len(pix) >= 3:
            cx = sum(p % mw for p in pix) / len(pix) * 16 + 8   # metal map pixel = 16 elmos
            cz = sum(p // mw for p in pix) / len(pix) * 16 + 8
            spots.append((cx, cz, tot))
    return spots


def passability(smf):
    """Cell grid: passable for bots (slope <= MAX_SLOPE and above water)."""
    hw, hh, hm = smf["hw"], smf["hh"], smf["hm"]
    gw, gh = (hw - 1) // CELL, (hh - 1) // CELL
    grid = bytearray(gw * gh)
    water = 0
    for gz in range(gh):
        for gx in range(gw):
            x0, z0 = gx * CELL, gz * CELL
            hs = [hm[(z0 + dz) * hw + (x0 + dx)] for dz in (0, CELL) for dx in (0, CELL)]
            # steepest step between adjacent height samples inside the cell (closer to the engine's slope)
            slope = 0.0
            for dz in range(CELL):
                for dx in range(CELL):
                    a = hm[(z0 + dz) * hw + (x0 + dx)]
                    slope = max(slope, abs(hm[(z0 + dz) * hw + (x0 + dx + 1)] - a), abs(hm[(z0 + dz + 1) * hw + (x0 + dx)] - a))
            slope /= SQUARE
            under = sum(1 for v in hs if v < 0) >= 3
            water += under
            grid[gz * gw + gx] = 1 if (slope <= MAX_SLOPE and not under) else 0
    return grid, gw, gh, water / float(gw * gh)


def path_and_choke(grid, gw, gh, a, b):
    """Shortest passable path a->b (cells) and the narrowest perpendicular width along it."""
    def cell(p):
        return (min(gw - 1, max(0, int(p[0] / (CELL * SQUARE)))), min(gh - 1, max(0, int(p[1] / (CELL * SQUARE)))))
    s, t = cell(a), cell(b)
    dist = {s: 0.0}
    prev = {}
    pq = [(0.0, s)]
    while pq:
        d, u = heapq.heappop(pq)
        if u == t:
            break
        if d > dist.get(u, 1e18):
            continue
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                if dx == dz == 0:
                    continue
                v = (u[0] + dx, u[1] + dz)
                if not (0 <= v[0] < gw and 0 <= v[1] < gh) or not grid[v[1] * gw + v[0]]:
                    continue
                nd = d + math.hypot(dx, dz)
                if nd < dist.get(v, 1e18):
                    dist[v] = nd
                    prev[v] = u
                    heapq.heappush(pq, (nd, v))
    if t not in dist:
        return None, None
    path, u = [], t
    while u != s:
        path.append(u)
        u = prev[u]
    path.reverse()
    # width across the path direction, sampled every few cells, ignoring the base areas themselves
    widths = []
    for i in range(4, len(path) - 4, 2):
        (x0, z0), (x1, z1) = path[i - 2], path[i + 2]
        dx, dz = x1 - x0, z1 - z0
        n = math.hypot(dx, dz) or 1.0
        px, pz = -dz / n, dx / n
        w = 1
        for sgn in (1, -1):
            k = 1
            while True:
                cx, cz = int(round(path[i][0] + sgn * px * k)), int(round(path[i][1] + sgn * pz * k))
                if not (0 <= cx < gw and 0 <= cz < gh) or not grid[cz * gw + cx] or k > 200:
                    break
                k += 1
                w += 1
        widths.append(w)
    # a choke is a narrow stretch, not a single bump: narrowest 5-sample moving median along the path
    if len(widths) >= 5:
        smooth = [sorted(widths[i - 2:i + 3])[2] for i in range(2, len(widths) - 2)]
    else:
        smooth = widths
    return dist[t] * CELL * SQUARE, (min(smooth) * CELL * SQUARE if smooth else None)


def analyze(path):
    files, smf_name, info_name = read_archive(path)
    info = files.get(info_name, b"").decode("utf-8", "replace") if info_name else ""
    ov = {}
    smfblock = re.search(r"\bsmf\s*=\s*\{(.*?)\}", info, re.S | re.I)
    if smfblock:
        for k, key in (("minheight", "min"), ("maxheight", "max")):
            m = re.search(r"\b%s\s*=\s*(-?[\d.]+)" % k, smfblock.group(1), re.I)
            if m:
                ov[key] = float(m.group(1))
    smf = parse_smf(files[smf_name], ov)
    name = re.search(r'\bname\s*=\s*"([^"]+)"', info)
    version = re.search(r'\bversion\s*=\s*"([^"]*)"', info)
    mapname = (name.group(1) + ((" " + version.group(1)) if version and version.group(1) and version.group(1) not in name.group(1) else "")) if name else os.path.basename(path)
    starts = parse_starts(info)
    spots = mex_spots(smf)
    grid, gw, gh, water = passability(smf)
    size = (smf["mapx"] * SQUARE, smf["mapy"] * SQUARE)
    rep = {"file": os.path.basename(path), "name": mapname, "size": size, "starts": starts[:16],
           "mex": len(spots), "water": round(water, 3)}
    if len(starts) >= 2:
        d, choke = path_and_choke(grid, gw, gh, starts[0], starts[1])
        rep["base_path"] = round(d) if d else None
        rep["base_straight"] = round(math.dist(starts[0], starts[1]))
        rep["choke_width"] = round(choke) if choke else None
        # extractors closer to start 0 than to start 1: what each side can claim
        near = sum(1 for s in spots if math.dist(s[:2], starts[0]) < math.dist(s[:2], starts[1]))
        rep["mex_per_side"] = [near, len(spots) - near]
    return rep


def main():
    maps_dir, out_json, out_as = sys.argv[1:4]
    wanted = sys.argv[4:]
    files = [os.path.join(maps_dir, f) for f in (wanted or sorted(os.listdir(maps_dir))) if f.endswith(".sd7")]
    reports = []
    for f in files:
        try:
            r = analyze(f)
            reports.append(r)
            print(f"{r['name'][:30]:30s} size={r['size']} mex={r['mex']} water={r['water']} "
                  f"path={r.get('base_path')} straight={r.get('base_straight')} choke={r.get('choke_width')} per_side={r.get('mex_per_side')}")
        except Exception as e:
            print("FAIL", os.path.basename(f), e)
    json.dump(reports, open(out_json, "w"), indent=1)
    lines = ["// GENERATED by tools/analyze_maps.py: pre-match map analysis. Do not edit.",
             "namespace MapFacts {", "",
             "class SMap { float basePath; float straight; float choke; int mex; float water; }", "",
             "dictionary maps;", "", "void Init()", "{"]
    for r in reports:
        lines.append('\t{ SMap m; m.basePath = %s; m.straight = %s; m.choke = %s; m.mex = %d; m.water = %s; maps.set("%s", @m); }'
                     % (float(r.get("base_path") or -1), float(r.get("base_straight") or -1), float(r.get("choke_width") or -1),
                        r["mex"], r["water"], r["name"].replace('"', "")))
    lines += ["}", "", "SMap@ Get(const string& in name)", "{", "\tSMap@ m;", "\tif (maps.get(name, @m))", "\t\treturn m;",
              "\treturn null;", "}", "", "}  // namespace MapFacts"]
    open(out_as, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
    print(f"{len(reports)} maps -> {out_json}, {out_as}")


if __name__ == "__main__":
    main()
