#!/usr/bin/env python3
"""
Factory spacing from the factories' own yardmaps (owner: Cortex bot labs can be chained, Armada T2/T3 labs have
several ways out). No hand-picked yards.

For every factory unit file: read its footprint (footprintx/z, squares of 8 elmos) and yardmap ('o' blocked,
anything else passable). A side is an exit when passable yard cells touch that border. The lane on an exit side is
as deep as the largest unit the factory builds (its footprint, from the build options' unit files); closed sides get
no lane, so labs can stand against each other there (a Cortex bot lab, open front and back, chains in a line).

Writes Anarva/stable/config/anarva/block_map_factories.json: block classes per factory and their instance entries;
merge into block_map.json with --merge.

usage: python tools/gen_factory_blocks.py [--units ref/game/units] [--merge Anarva/stable/config/anarva/block_map.json]
"""
import argparse, glob, json, os, re

def parse_unit(path):
    t = open(path, encoding="utf-8", errors="ignore").read()
    g = lambda k: (re.search(r"\b" + k + r"\s*=\s*([-\d.]+)", t) or [None, None])[1]
    ym = re.search(r'\byardmap\s*=\s*"([^"]*)"', t)
    bo = re.search(r"buildoptions\s*=\s*\{(.*?)\}", t, re.S)
    return {
        "fx": int(float(g("footprintx") or 0)), "fz": int(float(g("footprintz") or 0)),
        "yardmap": re.sub(r"\s+", "", ym.group(1)) if ym else "",
        "builds": re.findall(r'"(\w+)"', bo.group(1)) if bo else [],
        "canmove": float(g("speed") or 0) > 0,  # mobile = has a speed (BAR flags factories canmove)
    }

def exits(u):
    fx, fz, ym = u["fx"], u["fz"], u["yardmap"]
    if fx <= 0 or fz <= 0 or len(ym) < fx * fz:
        return None
    open_ = lambda x, z: ym[z * fx + x] != "o"
    back = any(open_(x, 0) for x in range(fx))           # first row = back (yardmaps are written north = back)
    front = any(open_(x, fz - 1) for x in range(fx))
    left = any(open_(0, z) for z in range(fz))
    right = any(open_(fx - 1, z) for z in range(fz))
    return {"front": front, "back": back, "left": left, "right": right}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--units", default="ref/game/units")
    ap.add_argument("--merge")
    a = ap.parse_args()
    units = {os.path.splitext(os.path.basename(f))[0]: f for f in glob.glob(os.path.join(a.units, "**", "*.lua"), recursive=True)}
    parsed = {}
    classes, instance = {}, {}
    for name, path in units.items():
        u = parse_unit(path)
        if not u["builds"] or u["canmove"]:
            continue  # factories: static units that build others
        mobile = [parse_unit(units[b]) for b in u["builds"] if b in units]
        mobile = [m for m in mobile if m["canmove"]]
        if not mobile:
            continue  # builds structures only (not a factory)
        e = exits(u)
        if e is None:
            continue
        lane = max(max(m["fx"], m["fz"]) for m in mobile)  # squares (8 elmos) of the largest unit it makes
        lane16 = (lane + 1) // 2                           # block units are 16 elmos
        yx = lane16 * (int(e["left"]) + int(e["right"]))
        yz = lane16 * (int(e["front"]) + int(e["back"]))
        # offset shifts the yard toward the open side when only one side of a pair is open ([left/right, front/back])
        ox = (lane16 // 2) * (int(e["right"]) - int(e["left"]))
        oz = (lane16 // 2) * (int(e["front"]) - int(e["back"]))
        cls = "fac_" + name
        classes[cls] = {"type": ["rectangle", "factory"], "yard": [yx, yz], "offset": [ox, oz], "ignore": ["none"],
                        "_from": f"yardmap exits {''.join(k[0] for k, v in e.items() if v) or 'none'}, largest unit {lane} squares"}
        instance[cls] = [name]
    out = {"class_land": classes, "instance": instance}
    path = "Anarva/stable/config/anarva/block_map_factories.json"
    json.dump(out, open(path, "w"), indent=1)
    print(f"{len(classes)} factories -> {path}")
    for n in ("corlab", "coralab", "armlab", "armalab", "armshltx", "corgant", "armvp", "corvp"):
        c = classes.get("fac_" + n)
        if c: print(n, c["_from"], "yard", c["yard"], "offset", c["offset"])
    if a.merge:
        s = open(a.merge, encoding="utf-8").read()
        # remove these factories from existing instance lists, then add our classes and instances
        for cls, names in instance.items():
            for n in names:
                s = re.sub(r'"' + n + r'"\s*,\s*', "", s)
                s = re.sub(r',\s*"' + n + r'"', "", s)
        cls_txt = "".join('\t\t"%s": {"type": ["rectangle", "factory"], "yard": %s, "offset": %s, "ignore": ["none"]},  // %s\n'
                          % (k, json.dumps(v["yard"]), json.dumps(v["offset"]), v["_from"]) for k, v in classes.items())
        s = s.replace('\t"class_land": {\n', '\t"class_land": {\n' + cls_txt, 1)
        inst_txt = "".join('\t\t"%s": ["%s"],\n' % (k, v[0]) for k, v in instance.items())
        s = s.replace('\t"instance": {\n', '\t"instance": {\n' + inst_txt, 1)
        open(a.merge, "w", encoding="utf-8").write(s)
        print("merged into", a.merge)

if __name__ == "__main__":
    main()
