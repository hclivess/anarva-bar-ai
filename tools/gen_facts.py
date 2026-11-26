"""Generate Anarva's unit facts (things the script API can't see) from the game's unit files.

usage: python gen_facts.py <units_dir> <out facts.as>
  units_dir: extracted game units/ folder (tools/rapid_extract.py ... units/)
Emits an AngelScript file with: factory build options, paralyzer (EMP) units, crawling bombs,
resurrect bots, extractor extraction/upkeep, constructor workertime. Re-run after a balance patch.
"""
import os
import re
import sys


def _lua_table(v):
    """lupa table -> Python (dict for keyed tables, list for 1..n arrays)."""
    try:
        items = list(v.items())
    except AttributeError:
        return v
    d = {(k.lower() if isinstance(k, str) else k): _lua_table(x) for k, x in items}
    if d and all(isinstance(k, int) for k in d):
        return [d[k] for k in sorted(d)]
    return d


def _find(t, key):
    """Every value of `key` anywhere in the evaluated unit table (keys are case-insensitive in the engine)."""
    out = []
    if isinstance(t, dict):
        for k, v in t.items():
            if k == key:
                out.append(v)
            out.extend(_find(v, key))
    elif isinstance(t, list):
        for v in t:
            out.extend(_find(v, key))
    return out


def _num(v):
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str):  # customparams hold numbers as strings, sometimes "a / b"
        m = re.fullmatch(r"\s*(-?[\d.]+)\s*(?:/\s*([\d.]+))?\s*", v)
        if m:
            return float(m.group(1)) / (float(m.group(2)) if m.group(2) else 1.0)
    return None


def scan(units_dir):
    """Evaluate every unit file as the engine does (a Lua program returning its def table), in the sandboxed
    LuaJIT of analyze_maps.py, and read the facts from the table. (A regex over the text read literals only.)"""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from analyze_maps import eval_mapinfo
    defs = {}
    for root, _, files in os.walk(units_dir):
        for fn in files:
            if not fn.endswith(".lua"):
                continue
            name = fn[:-4]
            text = open(os.path.join(root, fn), encoding="utf-8", errors="replace").read()
            try:
                top = _lua_table(eval_mapinfo(text))
            except Exception:
                continue
            if not isinstance(top, dict) or name not in top or not isinstance(top[name], dict):
                continue  # only the unit table named like the file
            u = top[name]
            d = {"name": name}
            for key in ("metalcost", "energycost", "workertime", "extractsmetal", "energyupkeep", "buildtime", "metalmake", "energymake", "speed", "radardistance", "sightdistance", "cloakcost", "cloakcostmoving", "mincloakdistance"):
                x = _num(u.get(key))
                if x is not None:
                    d[key] = x
            cp = u.get("customparams") if isinstance(u.get("customparams"), dict) else {}
            d["commander"] = cp.get("iscommander") in (True, "true", "1", 1)
            d["canresurrect"] = u.get("canresurrect") is True
            d["paralyzer"] = any(v is True for v in _find(u, "paralyzer"))
            boom = [str(u.get("explodeas", "")).lower(), str(u.get("selfdestructas", "")).lower()]
            d["crawl"] = any(b.startswith("crawl") for b in boom)
            cap = [_num(v) for v in _find(u, "energyconv_capacity")]
            eff = [_num(v) for v in _find(u, "energyconv_efficiency")]
            if cap and eff and cap[0] is not None and eff[0] is not None:
                d["conv"] = (cap[0], eff[0])
            st = [x for x in (_num(v) for v in _find(u, "stockpiletime")) if x is not None]
            if st:
                d["stockpiletime"] = max(st)
            mps = [x for x in (_num(v) for v in _find(u, "metalpershot")) if x is not None]
            if mps and max(mps) > 0:
                d["metalpershot"] = max(mps)
            sr = [x for x in (_num(v) for v in _find(u, "shield_radius")) if x is not None]
            if sr:
                d["shieldradius"] = max(sr)
            # a 'g' cell in the yardmap = must stand on a geothermal vent (engine yardmap code; a leading 'h' marks
            # the high-resolution format)
            ym = u.get("yardmap")
            if isinstance(ym, str):
                cells = ym.replace(" ", "").lower()
                if cells.startswith("h"):
                    cells = cells[1:]
                if "g" in cells:
                    d["needgeo"] = 1.0
            # weapons that turn independently of the hull ("turret" in the weapon def) fire while the unit moves in any
            # direction: the share of its weapon defs that do (owner #116: a unit fights from its own reach - kiting
            # pays only for units that fire while moving away)
            wd = u.get("weapondefs") if isinstance(u.get("weapondefs"), dict) else {}
            if wd:
                tur = [w.get("turret") is True for w in wd.values() if isinstance(w, dict)]
                if tur:
                    d["turret"] = sum(tur) / len(tur)
            bo = u.get("buildoptions")
            d["buildoptions"] = [x for x in bo if isinstance(x, str)] if isinstance(bo, list) else []
            defs[name] = d
    return defs


def as_list(names):
    return "{" + ", ".join('"%s"' % n for n in names) + "}"


def main():
    units_dir, out = sys.argv[1:3]
    defs = scan(units_dir)
    # every unit with build options (factories and constructors alike: the script needs both). A factory is one
    # that builds and cannot move (unit facts, not name endings).
    factories = {n: d["buildoptions"] for n, d in defs.items() if d["buildoptions"] and d.get("workertime", 0) > 0}
    # Factory tier by build depth from the commanders (facts, no name lists): a commander's labs are tier 1; a
    # constructor has its lab's tier; a lab built by a constructor of tier t is tier t + 1.
    tier = {}
    frontier = [(c, 0) for c, d in defs.items() if d.get("commander") and d.get("buildoptions")]
    seen = set()
    while frontier:
        b, t = frontier.pop(0)
        if b in seen:
            continue
        seen.add(b)
        for o in defs.get(b, {}).get("buildoptions", []):
            if o in factories and defs[o].get("speed", 0) <= 0:  # a factory: builds, cannot move
                if o not in tier or tier[o] > t + 1:
                    tier[o] = t + 1
                for u in factories[o]:
                    if defs.get(u, {}).get("buildoptions"):
                        frontier.append((u, tier[o]))
    defs_tier = {n: {"factorytier": float(t)} for n, t in tier.items()}
    for n, v in defs_tier.items():
        defs[n]["factorytier"] = v["factorytier"]
    emp = sorted(n for n, d in defs.items() if d["paralyzer"] and "metalcost" in d)
    crawl = sorted(n for n, d in defs.items() if d["crawl"] and "metalcost" in d)
    rez = sorted(n for n, d in defs.items() if d["canresurrect"])
    lines = [
        "// GENERATED by tools/gen_facts.py from the game's unit files. Do not edit; re-run after a patch.",
        "// Facts the script API cannot see: build options, weapon kinds, extraction, upkeep.",
        "namespace Facts {",
        "",
        "array<string> empUnits = " + as_list(emp) + ";",
        "array<string> crawlUnits = " + as_list(crawl) + ";",
        "array<string> rezUnits = " + as_list(rez) + ";",
        "",
        "// factory -> what it can build",
        "dictionary buildOptions = {",
    ]
    for i, (fac, opts) in enumerate(sorted(factories.items())):
        sep = "," if i < len(factories) - 1 else ""
        lines.append('\t{"%s", array<string> = %s}%s' % (fac, as_list(opts), sep))
    lines.append("};")
    lines.append("")
    lines.append("// extractor facts: extractsmetal relative to T1, energy upkeep (E/s)")
    for n in ("armmex", "cormex", "legmex", "armmoho", "cormoho", "legmoho", "cormexp"):
        d = defs.get(n, {})
        lines.append("// %s extracts=%s upkeepE=%s" % (n, d.get("extractsmetal"), d.get("energyupkeep")))
    lines.append("")
    lines.append("// energy converters: E/s consumed, metal per energy, cost, build time (customparams)")
    lines.append("class SConv { float capE; float eff; float costM; float costE; float buildTime; }")
    lines.append("dictionary converters;")
    lines.append("void InitConverters()")
    lines.append("{")
    for n, d in sorted(defs.items()):
        if "conv" in d and "metalcost" in d:
            lines.append('	{ SConv c; c.capE = %g; c.eff = %g; c.costM = %g; c.costE = %g; c.buildTime = %g; converters.set("%s", @c); }'
                         % (d["conv"][0], d["conv"][1], d["metalcost"], d.get("energycost", 0), d.get("buildtime", 0), n))
    lines.append("}")
    lines.append("SConv@ Converter(const string& in name)")
    lines.append("{")
    lines.append("	SConv@ c;")
    lines.append("	if (converters.get(name, @c))")
    lines.append("		return c;")
    lines.append("	return null;")
    lines.append("}")
    lines.append("")
    for key, fn in (("stockpiletime", "StockpileTime"), ("metalpershot", "ShotMetal"), ("shieldradius", "ShieldRadius"),
                    ("extractsmetal", "ExtractsMetal"), ("energyupkeep", "EnergyUpkeep"), ("factorytier", "FactoryTier"),
                    ("needgeo", "NeedsGeo"), ("metalmake", "MetalMake"), ("energymake", "EnergyMake"),
                    ("radardistance", "RadarRange"), ("cloakcost", "CloakCost"), ("cloakcostmoving", "CloakCostMoving"), ("mincloakdistance", "DecloakDistance"),
                    ("turret", "FiresMoving")):
        items = sorted((n, d[key]) for n, d in defs.items() if key in d)
        lines.append("dictionary %s_ = {" % key)
        lines.append(",\n".join('\t{"%s", %g}' % (n, v) for n, v in items))
        lines.append("};")
        # a missing key leaves the out value undefined in this AngelScript build: only a found key counts (sc2)
        lines.append("float %s(const string& in name) { double v = 0; if (!%s_.get(name, v)) v = 0; return float(v); }" % (fn, key))
        lines.append("")
    lines.append("array<string> BuildOptions(const string& in fac)")
    lines.append("{")
    lines.append("\tarray<string>@ o;")
    lines.append("\tif (buildOptions.get(fac, @o))")
    lines.append("\t\treturn o;")
    lines.append("\treturn array<string>();")
    lines.append("}")
    lines.append("")
    lines.append("}  // namespace Facts")
    open(out, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
    print(f"{len(defs)} unit defs, {len(factories)} factories, emp={len(emp)}, crawl={len(crawl)}, rez={len(rez)} -> {out}")
    print("emp:", emp)
    print("crawl:", crawl)
    print("rez:", rez)


if __name__ == "__main__":
    main()
