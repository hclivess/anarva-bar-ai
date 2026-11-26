#!/usr/bin/env python3
"""List the core's CCircuitDef getters that the script can't call (see SCRIPT_SIGHT.md)."""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "ref", "circuitai", "src", "circuit")
h = open(os.path.join(SRC, "unit", "CircuitDef.h"), encoding="latin-1").read()
getters = sorted(set(re.findall(r"\b(?:float|int|bool|unsigned|[A-Za-z:<>]+\*?)\s+((?:Get|Is|Has|Can)[A-Za-z0-9]+)\s*\(", h)))
reg = "\n".join(l for l in open(os.path.join(SRC, "script", "InitScript.cpp"), encoding="latin-1").read().splitlines()
                if '"CCircuitDef"' in l)
exposed = set(re.findall(r'"[^"(]*?\b([A-Za-z0-9_]+)\(', reg))
props = set(re.findall(r'"(?:const )?[A-Za-z0-9_@ ]+? ([A-Za-z0-9_]+)"\s*,\s*asOFFSET\(CCircuitDef', reg))
missing = [g for g in getters if g not in exposed]
print(f"{len(exposed)} methods and {len(props)} properties exposed; {len(missing)} getters not exposed:")
for g in missing:
    print("  " + g)
