"""Append the enemy-classification role "jammer" to every jammer UnitDef in commented-JSON behaviour files.

usage: python patch_jammer_roles.py <behaviour.json> [...]
Idempotent. Prints what it changed / could not find.
"""
import re
import sys

JAMMERS = [
    "armjamt", "corjamt", "armveil", "corshroud", "armjam", "coreter", "armsjam", "corsjam",
    "armaser", "corspec", "cormando", "armmlv", "cormlv",
    "legjam", "legajam", "legajamk", "legavjam", "leganavyradjamship", "legmlv",
]


def patch(text, name):
    m = re.search(r'"%s"\s*:\s*\{' % re.escape(name), text)
    if not m:
        return text, "missing"
    # role array within this unit's block (first "role" after the key)
    r = re.compile(r'"role"\s*:\s*\[([^\]]*)\]')
    rm = r.search(text, m.end())
    nxt = re.search(r'\n\s*"[a-z0-9_]+"\s*:\s*\{', text[m.end():])
    if not rm or (nxt and rm.start() > m.end() + nxt.start()):
        return text, "no role"
    roles = rm.group(1)
    if '"jammer"' in roles:
        return text, "ok"
    new = '"role": [%s, "jammer"]' % roles.strip()
    return text[:rm.start()] + new + text[rm.end():], "patched"


def main():
    for path in sys.argv[1:]:
        text = open(path, encoding="utf-8").read()
        for name in JAMMERS:
            text, status = patch(text, name)
            if status != "missing":
                print(f"{path}: {name}: {status}")
        open(path, "w", encoding="utf-8", newline="").write(text)


if __name__ == "__main__":
    main()
