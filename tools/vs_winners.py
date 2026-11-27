"""Compare a batch of Anarva games with the 1v1 winners in replays.db, minute by minute, and rank the gaps.

Usage: python tools/vs_winners.py runs/swe151 runs/swe152 ...   (each a run dir with g00/infolog.txt)

Per minute 1-5: metal income, energy income, army metal, extractors, builders (commander + constructors), metal bank;
plus the opener: extractors and energy plants before the lab, lab time, first armed unit. Winners: every winning team of
a 1v1 replay in runs/replays.db (the yardstick, not an input to the AI). Gaps are ranked by how far our median is from
the winners' median relative to the winners' spread (q3-q1), so the first line is what to work on next.
"""
import re, sqlite3, statistics as st, sys, os

MIN = [1, 2, 3, 4, 5]
DB = os.path.join(os.path.dirname(__file__), '..', 'runs', 'replays.db')


def q(a):
    a = sorted(x for x in a if x is not None)
    if not a:
        return None
    return a[len(a) // 4], st.median(a), a[(3 * len(a)) // 4]


def winners():
    c = sqlite3.connect(DB); cur = c.cursor()
    rows = cur.execute("select r.id, t.team from replays r join teams t on t.replay_id=r.id "
                       "where r.file like '1v1/%' and t.won=1").fetchall()
    per = {}
    op = {'mex_before_lab': [], 'energy_before_lab': [], 'lab_s': [], 'first_armed_s': []}
    for rid, team in rows:
        for m, mi, ei, army, mex, b, mc in cur.execute(
                "select minute, m_inc, e_inc, army, mex, builders, m_cur from stats where replay_id=? and team=? and minute<=5",
                (rid, team)):
            d = per.setdefault(m, {k: [] for k in ('m_inc', 'e_inc', 'army', 'mex', 'builders', 'm_bank')})
            d['m_inc'].append(mi); d['e_inc'].append(ei); d['army'].append(army); d['mex'].append(mex)
            d['builders'].append(b); d['m_bank'].append(mc)
        b = cur.execute("select frame, unit, fac, static, builder, armed from built where replay_id=? and team=? order by frame",
                        (rid, team)).fetchall()
        lab = next((x for x in b if x[2] == 1), None)
        if lab:
            pre = [x for x in b if x[0] < lab[0] and x[3] == 1]
            op['mex_before_lab'].append(sum(1 for x in pre if 'mex' in x[1]))
            op['energy_before_lab'].append(sum(1 for x in pre if any(k in x[1] for k in ('solar', 'win'))))
            op['lab_s'].append(lab[0] / 30.0)
        fa = next((x for x in b if x[5] == 1 and x[4] == 0 and x[3] == 0 and 'com' not in x[1]), None)
        if fa:
            op['first_armed_s'].append(fa[0] / 30.0)
    return per, op


def ours(run):
    f = os.path.join(run, 'g00', 'infolog.txt')
    if not os.path.exists(f):
        return None, None
    txt = open(f, encoding='utf-8', errors='replace').read()
    per = {}
    for m in MIN:
        fr = m * 1800
        s = re.search(r'\[HARNESS\] stats f=%d [^\n]*team=0[^\n]*' % fr, txt)
        t = re.search(r'\[HARNESS\] tech f=%d team=0[^\n]*' % fr, txt)
        if not s:
            continue
        g = lambda k, line: (float(re.search(k + r'([0-9.]+)', line).group(1)) if re.search(k + r'([0-9.]+)', line) else None)
        line = s.group(0)
        per[m] = {'m_inc': g('m_inc=', line), 'e_inc': g('e_inc=', line), 'army': g('army_m=', line),
                  'm_bank': g(r' m=', line), 'mex': g('mex=', t.group(0)) if t else None, 'builders': g('con=', t.group(0)) if t else None}
    built = re.findall(r'\[ANV\] built ([a-z]+) t=([0-9]+)s', txt)
    op = {}
    lab = next(((u, int(tt)) for u, tt in built if u in ('armlab', 'armvp', 'armhp', 'armap', 'armsy')), None)
    if lab:
        pre = [(u, int(tt)) for u, tt in built if int(tt) < lab[1]]
        op['mex_before_lab'] = sum(1 for u, _ in pre if 'mex' in u)
        op['energy_before_lab'] = sum(1 for u, _ in pre if any(k in u for k in ('solar', 'win')))
        op['lab_s'] = lab[1]
    fe = re.search(r'\[ANV-FAC\] f=([0-9]+) execute (arm(?!cv|ck|ch)[a-z]+)', txt)
    if fe:
        op['first_armed_s'] = int(fe.group(1)) / 30.0  # ordered; built a build time later
    return per, op


def main(runs):
    wp, wo = winners()
    games = [ours(r) for r in runs]
    games = [g for g in games if g[0] is not None]
    if not games:
        print('no games'); return
    gaps = []
    print('%-22s %-22s %-22s' % ('measure', 'ours q1/med/q3', 'winners q1/med/q3'))
    for k in ('mex_before_lab', 'energy_before_lab', 'lab_s', 'first_armed_s'):
        oq = q([g[1].get(k) for g in games]); wq = q(wo[k])
        if oq and wq:
            print('%-22s %-22s %-22s' % (k, '%g/%g/%g' % oq, '%.0f/%.0f/%.0f' % wq))
            gaps.append((abs(oq[1] - wq[1]) / max(1e-6, wq[2] - wq[0]), k, oq[1], wq[1]))
    for m in MIN:
        for k in ('m_inc', 'e_inc', 'army', 'mex', 'builders', 'm_bank'):
            oq = q([g[0].get(m, {}).get(k) for g in games]); wq = q(wp.get(m, {}).get(k, []))
            if oq and wq:
                print('%-22s %-22s %-22s' % ('%d:00 %s' % (m, k), '%g/%g/%g' % oq, '%.1f/%.1f/%.1f' % wq))
                gaps.append((abs(oq[1] - wq[1]) / max(1e-6, wq[2] - wq[0]), '%d:00 %s' % (m, k), oq[1], wq[1]))
    print('\nlargest gaps (|ours - winners| / winners spread):')
    for gscore, k, o, w in sorted(gaps, reverse=True)[:8]:
        print('  %-18s ours %-8g winners %-8.1f gap %.2f' % (k, o, w, gscore))


if __name__ == '__main__':
    main(sys.argv[1:])
