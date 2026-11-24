#!/usr/bin/env python3
"""
Fetch the official BAR leaderboard (https://bar-rts.com/leaderboards, the page embedded on
beyondallreason.info/leaderboards) and save it as ref/leaderboard.json.

The page is server-rendered by Nuxt: the data sits in `window.__NUXT__=(function(a,b,...){return {...}}(v1,v2,...))`.
This parses that expression as data (parameter names, argument literals, the returned object literal with
the parameters substituted); nothing from the page is executed.

usage: python tools/fetch_leaderboard.py [--out ref/leaderboard.json]
"""
import argparse, datetime, json, re, urllib.request

URL = "https://bar-rts.com/leaderboards"


class P:
    def __init__(self, s, env=None):
        self.s, self.i, self.env = s, 0, env or {}

    def ws(self):
        while self.i < len(self.s) and self.s[self.i] in " \t\r\n":
            self.i += 1

    def peek(self):
        self.ws()
        return self.s[self.i]

    def eat(self, c):
        self.ws()
        if self.s[self.i] != c:
            raise ValueError(f"expected {c!r} at {self.i}: {self.s[self.i:self.i + 40]!r}")
        self.i += 1

    def string(self):
        q = self.s[self.i]; self.i += 1; out = []
        while self.s[self.i] != q:
            c = self.s[self.i]
            if c == "\\":
                n = self.s[self.i + 1]
                if n == "u":
                    out.append(chr(int(self.s[self.i + 2:self.i + 6], 16))); self.i += 6; continue
                out.append({"n": "\n", "t": "\t", "r": "\r"}.get(n, n)); self.i += 2; continue
            out.append(c); self.i += 1
        self.i += 1
        return "".join(out)

    def ident(self):
        m = re.compile(r"[A-Za-z_$][\w$]*").match(self.s, self.i)
        if not m:
            raise ValueError(f"bad token at {self.i}: {self.s[self.i:self.i + 40]!r}")
        self.i = m.end()
        return m.group(0)

    def value(self):
        c = self.peek()
        if c in "\"'":
            return self.string()
        if c == "{":
            self.i += 1; obj = {}
            while self.peek() != "}":
                k = self.string() if self.peek() in "\"'" else self.ident()
                self.eat(":"); obj[k] = self.value()
                if self.peek() == ",":
                    self.i += 1
            self.i += 1
            return obj
        if c == "[":
            self.i += 1; arr = []
            while self.peek() != "]":
                arr.append(self.value())
                if self.peek() == ",":
                    self.i += 1
            self.i += 1
            return arr
        m = re.compile(r"-?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?").match(self.s, self.i)
        if m and (c.isdigit() or c in "-."):
            self.i = m.end(); t = m.group(0)
            return float(t) if any(x in t for x in ".eE") else int(t)
        name = self.ident()
        if name == "void":
            self.value(); return None
        lit = {"true": True, "false": False, "null": None, "undefined": None}
        if name in lit:
            return lit[name]
        if name in self.env:
            return self.env[name]
        if self.peek() == "(":  # a call such as Array(...): not data we need
            depth = 0
            while True:
                ch = self.s[self.i]; self.i += 1
                depth += ch == "("; depth -= ch == ")"
                if depth == 0:
                    return None
        return None


def parse_nuxt(html):
    start = html.index("window.__NUXT__=(function(") + len("window.__NUXT__=(function(")
    end_params = html.index(")", start)
    params = [p.strip() for p in html[start:end_params].split(",")]
    body_start = html.index("return", end_params) + len("return")
    p = P(html[body_start:])
    p.ws()
    # skip the body once to find where the arguments begin
    p.value()
    rest = html[body_start + p.i:]
    args_at = rest.index("}(") + 2
    ap = P(rest[args_at:])
    args = []
    while ap.peek() != ")":
        args.append(ap.value())
        if ap.peek() == ",":
            ap.i += 1
    env = dict(zip(params, args))
    return P(html[body_start:], env).value()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="ref/leaderboard.json")
    a = ap.parse_args()
    req = urllib.request.Request(URL, headers={"User-Agent": "replay-research-script/1.0"})
    html = urllib.request.urlopen(req, timeout=60).read().decode("utf-8")
    data = parse_nuxt(html)["data"][0]
    boards = [{"name": b["name"], "players": [{"id": p["id"], "name": p["name"], "rating": p["rating"]} for p in b["players"]]}
              for b in data["currentLeaderboard"]]
    season = max(s["season"] for s in data.get("seasonInfo", [{"season": 0}]))
    json.dump({"season": season, "source": URL, "fetched": datetime.datetime.now(datetime.timezone.utc).isoformat(), "boards": boards},
              open(a.out, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    for b in boards:
        r = [p["rating"] for p in b["players"]]
        print(f"{b['name']}: {len(r)} players, rating {max(r):.1f}..{min(r):.1f}; top: {', '.join(p['name'] for p in b['players'][:5])}")


if __name__ == "__main__":
    main()
