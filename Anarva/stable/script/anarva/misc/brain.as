// Anarva brain: script-side logic layered over the CircuitAI (BARb) core.
//
//  Army     - scales attack/raid gather quotas with our real army size, so squads launch as blobs
//             instead of trickling in one by one.
//  Recycler - once fusion-tier energy carries the base, reclaims solars / winds / tidals (and T1
//             metal makers once T2 makers exist) for metal, and stops the core from rebuilding them.
//  Intel    - jammer awareness: seen enemy jammers project a guessed "hidden army" influence,
//             a decaying heatmap of our losses marks places where something we can't see is
//             killing us, and we answer with vision (Dragon's Eyes, air scouts) and bigger groups.

#include "../../define.as"
#include "../../unit.as"
#include "../../task.as"

namespace Brain {

/*
 * Travel time with the unit's real motion: turn to face the target, accelerate, cruise. Vehicles turn slowly
 * and on an arc (no turn in place); distance/top speed makes them look as agile as bots, which overstates how
 * fast they reach a raid, retreat or kite. Heading unknown: the expected turn of a random heading is 90 deg.
 */
// math: PI, and the expected turn when the heading is unknown (the mean of a uniform turn of 0..PI is PI/2, i.e.
// acos(0)), converted to the degrees turnRate uses
float Pi() { return acos(-1.f); }
float ExpectedTurnDeg() { return acos(0.f) * 180.f / Pi(); }
float MoveTime(const CCircuitDef@ d, float dist)
{
	const float v = AiMax(1.f, d.speed);
	const float tTurn = d.turnRate > 0.f ? ExpectedTurnDeg() / d.turnRate : 0.f;
	float tMove;
	if (d.accel > 0.f) {
		const float tAcc = v / d.accel, dAcc = 0.5f * v * tAcc;
		tMove = dist <= dAcc ? sqrt(2.f * dist / d.accel) : tAcc + (dist - dAcc) / v;
	} else tMove = dist / v;
	// turn in place (bots) or on an arc of radius v/omega (most vehicles): either way the heading takes angle/omega
	return tTurn + tMove;
}


// Systematic choices (no dice): assisting adds the same build power to any factory, so the difference is the walk.
CCircuitUnit@ FactoryReachedSoonest(const AIFloat3& in from, const CCircuitDef@ mover)
{
	return FactoryReachedSoonestIn(Brain::Intel::allFactories, from, mover);
}
CCircuitUnit@ FactoryReachedSoonestIn(const array<CCircuitUnit@>@ facs, const AIFloat3& in from, const CCircuitDef@ mover)
{
	CCircuitUnit@ best = null; float bt = 1e30f;
	for (uint i = 0; i < facs.length(); ++i) {
		CCircuitUnit@ f = facs[i];
		const float t = (mover is null) ? f.GetPos(ai.frame).distance2D(from) : MoveTime(mover, f.GetPos(ai.frame).distance2D(from));
		if (t < bt) { bt = t; @best = f; }
	}
	return best;
}


// A turret alone at the front dies without trading (owner: "absolutely not covered, gets destroyed"). Build it only
// where it is more likely to survive than not: (1-P) x cost > P x cost, P from the same fight-and-escape estimate,
// at the turret's health, against everything that can reach it while it is being built.
bool TurretSurvives(const CCircuitDef@ tur, const AIFloat3& in pos)
{
	CCircuitUnit@ ref = commander;
	if (ref is null) { const array<CCircuitUnit@>@ all = AiGetTeamUnits(); if (all.length() > 0) @ref = all[0]; }
	if (ref is null) return true;
	const float bpPer = aiBuilderMgr.GetBuildPower() / AiMax(1.f, float(aiBuilderMgr.GetWorkerCount()));
	const float tBuild = tur.buildTime / AiMax(1.f, bpPer);
	const float P = JobPDeath(ref, tur, pos, tBuild);
	if ((1.f - P) <= P) AiLog("[ANV] DefRisk: not building " + tur.GetName() + " at (" + int(pos.x) + "," + int(pos.z) + "): P(lost) " + F1(P));
	return (1.f - P) > P;
}

CCircuitDef@ Def(const string& in name)
{
	return ai.GetCircuitDef(name);
}

array<CCircuitDef@> Defs(const array<string>& in names)
{
	array<CCircuitDef@> res;
	for (uint i = 0; i < names.length(); ++i) {
		CCircuitDef@ d = Def(names[i]);
		if (d !is null)
			res.insertLast(d);
	}
	return res;
}

bool InList(const array<CCircuitDef@>& in list, const CCircuitDef@ d)
{
	for (uint i = 0; i < list.length(); ++i) {
		if (list[i].id == d.id)
			return true;
	}
	return false;
}

int Minute() { return ai.frame / MINUTE; }

string F1(float v) { return formatFloat(v, "", 0, 1); }
string F2(float v) { return formatFloat(v, "", 0, 2); }

AIFloat3 basePos = AIFloat3(-1.f, 0.f, -1.f);
bool HasBase() { return basePos.x >= 0.f; }
const int NEVER = -1;  // "no order yet" marker for frame stamps


// How long an order may wait before it is forgotten: the time to finish it - the walk from base plus its build time at
// our mean constructor's build power (frames). Replaces fixed 2/3/5-minute lifetimes.
int OrderLife(const CCircuitDef@ d, const AIFloat3& in pos)
{
	const float workers = float(AiMax(1, int(aiBuilderMgr.GetWorkerCount())));
	const float bp = AiMax(1e-3f, aiBuilderMgr.GetBuildPower() / workers);
	const float speed = AiMax(1.f, (commander !is null) ? commander.circuitDef.speed : Brain::Director::allSpeed);
	const float walk = HasBase() ? basePos.distance2D(pos) / speed : 0.f;
	return int((walk + ((d is null) ? 0.f : d.buildTime) / bp) * SECOND) + 1;
}
// The same for a reclaim of this much metal (reclaim runs at build power)
int ReclaimLife(float metal, const AIFloat3& in pos)
{
	const float workers = float(AiMax(1, int(aiBuilderMgr.GetWorkerCount())));
	const float bp = AiMax(1e-3f, aiBuilderMgr.GetBuildPower() / workers);
	const float speed = AiMax(1.f, (commander !is null) ? commander.circuitDef.speed : Brain::Director::allSpeed);
	const float walk = HasBase() ? basePos.distance2D(pos) / speed : 0.f;
	return int((walk + metal / bp) * SECOND) + 1;
}

void RemoveUnit(array<CCircuitUnit@>@ list, CCircuitUnit@ unit)
{
	int idx = list.findByRef(unit);
	if (idx >= 0)
		list.removeAt(idx);
}

/* ======================================================================== */
namespace Army {

array<CCircuitUnit@> ground;   // units that end up in defend->attack squads
array<CCircuitUnit@> scouts;

uint excludeMask = 0;

void Init()
{
	excludeMask = Unit::Role::SCOUT.mask | Unit::Role::RAIDER.mask | Unit::Role::AA.mask
		| Unit::Role::ARTY.mask | Unit::Role::SUPPORT.mask | Unit::Role::BUILDER.mask
		| Unit::Role::COMM.mask | Unit::Role::MINE.mask | Unit::Role::TRANS.mask
		| Unit::Role::BOMBER.mask | Unit::Role::AS.mask;

}

bool IsGround(const CCircuitDef@ d)
{
	return d.IsMobile() && !d.IsAbleToFly() && !d.IsRoleAny(excludeMask);
}

bool IsRaider(const CCircuitDef@ d)
{
	return d.IsMobile() && !d.IsAbleToFly() && ai.GetBindedRole(d.GetMainRole()) == RT::RAIDER;
}

array<CCircuitUnit@> raiders;

void OnAdded(CCircuitUnit@ unit)
{
	const CCircuitDef@ d = unit.circuitDef;
	if (d.IsRoleAny(Unit::Role::SCOUT.mask)) {
		scouts.insertLast(unit);
	}
	if (IsGround(d)) {
		ground.insertLast(unit);
	} else if (IsRaider(d)) {
		raiders.insertLast(unit);
	}
}

void OnRemoved(CCircuitUnit@ unit)
{
	RemoveUnit(ground, unit);
	RemoveUnit(raiders, unit);
	RemoveUnit(scouts, unit);
}

// (BARb squad tracking and broken-squad recall removed with BARb's army handling; Command pulls back itself.)

}  // namespace Army



/* ======================================================================== */
/*
 * Metal storage (owner: storage is needed for midgame transitions that eat T2 labs etc.; replays: of 228 players
 * 37% built metal storage, the first one a median 1.1 min before their first T2 lab, n=28, runs/comm_study +
 * runs/lib_play 2026-11-24). Metal reclaimed into full storage is thrown away. A reclaim starts only when what
 * it returns, on top of what is already coming back, fits; reclaims held back for room make a storage worth
 * building when the metal they'd save beats its cost.
 */
namespace Storage {

CCircuitDef@ storeDef = null;
float blockedMax = 0.f;
int ordered = 0, orderFrame = NEVER, countAtOrder = -1;

float Incoming()
{
	float m = 0.f;
	for (uint i = 0; i < Recycler::pending.length(); ++i)
		if (Recycler::pending[i] !is null) m += Recycler::pending[i].circuitDef.costM;
	return m;
}
float Free() { return AiMax(0.f, aiEconomyMgr.metal.storage - aiEconomyMgr.metal.current); }
bool Fits(float m) { return Incoming() + m <= Free(); }
void Block(float m) { blockedMax = AiMax(blockedMax, Incoming() + m - Free()); }

void Update()
{
	if (storeDef is null) @storeDef = Strategic::Side("armmstor", "cormstor", "legmstor");
	const float want = blockedMax;
	blockedMax = 0.f;
	if (storeDef is null || !storeDef.IsAvailable(ai.frame) || want <= 0.f || !HasBase()) return;
	// one order at a time: outstanding until one more storage exists or the task would have timed out
	if (countAtOrder >= 0 && storeDef.count <= countAtOrder && orderFrame != NEVER && ai.frame - orderFrame < OrderLife(storeDef, basePos)) return;
	const float saved = AiMin(want, storeDef.storageM);
	if (saved <= Economist::MetalValue(storeDef)) return;
	aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::STORE, Task::Priority::NORMAL, storeDef, basePos, 0.f, true, OrderLife(storeDef, basePos)));
	countAtOrder = storeDef.count; orderFrame = ai.frame; ++ordered;
	AiLog("[ANV] Storage: ordering " + storeDef.GetName() + " (reclaims held back: " + int(want) + " metal over free storage, it holds " + int(storeDef.storageM) + ")");
}

/*
 * Energy storage: it keeps energy that would otherwise overflow. Over the planning horizon it saves
 * min(its capacity, (income - pull) x H) of energy, worth that / energy-per-metal; build it when that beats its cost
 * (metal + energy / energy-per-metal). Only while storage is full: below full nothing overflows.
 */
CCircuitDef@ eStoreDef = null;
int eOrderFrame = NEVER, eCountAtOrder = -1;
void UpdateEnergy()
{
	if (eStoreDef is null) @eStoreDef = Strategic::Side("armestor", "corestor", "legestor");
	if (eStoreDef is null || !eStoreDef.IsAvailable(ai.frame) || !HasBase()) return;
	const SResourceInfo@ e = aiEconomyMgr.energy;
	if (e.current < e.storage) return;  // nothing overflows below full
	if (eCountAtOrder >= 0 && eStoreDef.count <= eCountAtOrder && eOrderFrame != NEVER && ai.frame - eOrderFrame < OrderLife(eStoreDef, basePos)) return;
	const float epm = AiMax(1e-3f, Economist::energyPerMetal);
	const float over = AiMax(0.f, e.income - Economist::RealPull());  // converted surplus is still surplus
	const float kept = AiMin(eStoreDef.storageE, over * Economist::Horizon());
	if (kept / epm <= Economist::MetalValue(eStoreDef)) return;
	aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::STORE, Task::Priority::NORMAL, eStoreDef, basePos, 0.f, true, OrderLife(eStoreDef, basePos)));
	eCountAtOrder = eStoreDef.count; eOrderFrame = ai.frame; ++ordered;
	AiLog("[ANV] Storage: ordering " + eStoreDef.GetName() + " (keeps " + int(kept) + " E over the horizon = " + int(kept / epm) + " M > its cost " + int(Economist::MetalValue(eStoreDef)) + ")");
}

string Status() { return "storage orders=" + ordered; }

}  // namespace Storage


/*
 * Economic position (Vritrasura108, #41): "I try to reduce army only when I am economically behind. Otherwise when I
 * am in surplus I accumulate army for attack. Defensive army can also become offensive army if accumulated for long
 * enough. Having no army at all ruins the possibility to exploit fast once a critical weakness is discovered."
 * Enemy income is estimated from the extractors of theirs we have seen, at what our own extractors yield. Behind:
 * income goes to constructors and economy. Ahead: no new constructors; income becomes army (option value).
 */

/*
 * Rez lab (owner: rez bots ignored the whole game after a vehicle opening). Rez bots come from bot labs (and
 * shipyards); a vehicle opening has none, so no factory of ours could ever make one. When none of our factories can,
 * a bot lab is worth building once the wreck metal on the map beats the lab plus one rez bot: the lab pays through
 * the rez bots it enables (same test as the rez fleet, one level up). One order outstanding at a time.
 */
namespace RezLab {
int ordered = 0, orderFrame = NEVER;
void Update()
{
	if (!HasBase()) return;
	const array<CCircuitUnit@>@ facs = Intel::allFactories;
	for (uint i = 0; i < facs.length(); ++i) {
		const array<string> opts = Facts::BuildOptions(facs[i].circuitDef.GetName());
		for (uint k = 0; k < opts.length(); ++k)
			if (Production::rezDefs.findByRef(ai.GetCircuitDef(opts[k])) >= 0) return;  // we can already make rez bots
	}
	CCircuitDef@ lab = Strategic::Side("armlab", "corlab", "leglab");
	CCircuitDef@ rez = Strategic::Side("armrectr", "cornecro", "legrezbot");
	if (lab is null || rez is null || !lab.IsAvailable(ai.frame) || (orderFrame != NEVER && ai.frame - orderFrame < OrderLife(lab, basePos))) return;  // one order at a time, for its lifetime
	array<AIFloat3> wp; array<float> wm; array<bool> wr;
	const uint w = AiGetWrecks(wp, wm, wr);
	float pool = 0.f;
	for (uint i = 0; i < w; ++i) pool += wm[i];
	if (pool <= Economist::MetalValue(lab) + Economist::MetalValue(rez)) return;
	orderFrame = ai.frame;
	++ordered;
	aiBuilderMgr.Enqueue(TaskB::Factory(Task::Priority::HIGH, lab, basePos, lab, 0.f, false, true, OrderLife(lab, basePos)));
	AiLog("[ANV] RezLab: ordering " + lab.GetName() + " (wreck metal " + int(pool) + " > lab + rez bot)");
}
}  // namespace RezLab

namespace EcoPos {
bool wantConstructor = false;  // (kept for the status line)
float constructorValue = 0.f; int conLogFrame = -100000;  // metal-eq one more constructor saves (Production compares it with every other unit)
array<AIFloat3> raidPos; array<float> raidVal;  // expected enemy economy (Command objectives)
// the cheapest mobile constructor any factory we own can build (unit facts via Facts::BuildOptions)
CCircuitDef@ CheapestConstructor()
{
	CCircuitDef@ best = null;
	const array<CCircuitUnit@>@ facs = Intel::allFactories;
	for (uint i = 0; i < facs.length(); ++i) {
		const array<string> opts = Facts::BuildOptions(facs[i].circuitDef.GetName());
		for (uint k = 0; k < opts.length(); ++k) {
			CCircuitDef@ d = ai.GetCircuitDef(opts[k]);
			if (d is null || !d.IsMobile() || !d.IsRoleAny(Unit::Role::BUILDER.mask) || d.buildSpeed <= 0.f) continue;
			if (Economist::mexT1 is null || !d.CanBuild(Economist::mexT1)) continue;  // it must be able to claim a spot
			if (best is null || d.costM < best.costM) @best = d;
		}
	}
	return best;
}
// a spot is ours when one of our extractors stands within an extractor's radius of it
bool OwnSpot(const AIFloat3& in p)
{
	for (uint i = 0; i < Economist::mexes.length(); ++i) {
		CCircuitUnit@ m = Economist::mexes[i];
		if (m !is null && m.GetPos(ai.frame).distance2D(p) <= m.circuitDef.GetRadius() * 2.f) return true;
	}
	return false;
}
float ours = 0.f, theirs = 0.f;
bool behind = true;
void Update()
{
	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
	const uint n = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	uint enemyMex = 0;
	for (uint i = 0; i < n; ++i) {
		if (ed[i] is null || ed[i].IsMobile()) continue;
		const string nm = ed[i].GetName();
		if (nm.findFirst("mex") >= 0 || nm.findFirst("moho") >= 0) ++enemyMex;
	}
	ours = aiEconomyMgr.metal.income;
	const float perMex = ours / float(AiMax(1, int(Economist::mexes.length())));
	// Unseen spots on their side count as theirs with the chance they've been taken since we last looked there
	// (dark time against the time they need to cross the map), the same model the scouts use; seen-open ones don't.
	float unseen = 0.f;
	{
		array<AIFloat3> msp; array<float> msi; array<bool> mso;
		const uint ns = AiGetMetalSpots(msp, msi, mso);
		float sp = 0.f; uint nm = 0;
		for (uint i = 0; i < n; ++i) if (ed[i] !is null && ed[i].IsMobile()) { sp += ed[i].speed; ++nm; }
		const float speed = nm > 0 ? sp / float(nm) : AiMax(1.f, Director::allSpeed);
		const float cross = AiTerrainDiagonal() / AiMax(1.f, speed);
		const bool scouted = Scout::lastSeen.length() == uint(Intel::gw * Intel::gh);
		for (uint i = 0; i < ns; ++i) {
			if (!mso[i] || Assess::OnOurSide(msp[i]) || AiIsInLOS(msp[i])) continue;
			const float age = scouted ? float(ai.frame - Scout::lastSeen[Intel::CellOf(msp[i])]) / SECOND : float(ai.frame) / SECOND;
			unseen += AiMin(1.f, age / AiMax(1.f, cross));
		}
	}
	theirs = (float(enemyMex) + unseen) * perMex;
	// Raid targets (#89, owner: "an early raid of a few blitz easily wins against barb"): every spot we don't hold,
	// worth an extractor's metal times the chance the enemy holds it (seen enemy extractor: 1; unseen spot on their
	// side: dark time / their crossing time, as above). The core sends a raid with nothing in sight to the best of
	// these per second of travel that its power beats on the threat map (turrets included).
	{
		array<AIFloat3> rp; array<float> rv, rTakenRaw; array<bool> rSeen;
		array<AIFloat3> msp; array<float> msi; array<bool> mso;
		const uint ns = AiGetMetalSpots(msp, msi, mso);
		float sp2 = 0.f; uint nm2 = 0;
		for (uint i = 0; i < n; ++i) if (ed[i] !is null && ed[i].IsMobile()) { sp2 += ed[i].speed; ++nm2; }
		const float cross2 = AiTerrainDiagonal() / AiMax(1.f, nm2 > 0 ? sp2 / float(nm2) : Director::allSpeed);
		const bool scouted2 = Scout::lastSeen.length() == uint(Intel::gw * Intel::gh);
		const float mexV = (Economist::mexT1 is null) ? 0.f : Economist::MetalValue(Economist::mexT1);
		for (uint i = 0; i < ns; ++i) {
			if (OwnSpot(msp[i])) continue;
			float pTaken = 0.f;
			for (uint k = 0; k < n && pTaken < 1.f; ++k)
				if (ed[k] !is null && !ed[k].IsMobile() && (ed[k].GetName().findFirst("mex") >= 0 || ed[k].GetName().findFirst("moho") >= 0)
					&& ep[k].distance2D(msp[i]) <= ed[k].GetRadius() * 2.f) pTaken = 1.f;
			const bool seenMex = pTaken >= 1.f;  // an extractor of theirs seen there
			if (pTaken < 1.f && !Assess::OnOurSide(msp[i]) && !AiIsInLOS(msp[i])) {
				const float age = scouted2 ? float(ai.frame - Scout::lastSeen[Intel::CellOf(msp[i])]) / SECOND : float(ai.frame) / SECOND;
				pTaken = AiMin(1.f, age / AiMax(1.f, cross2));
			}
			if (pTaken <= 0.f) continue;
			rp.insertLast(msp[i]); rTakenRaw.insertLast(pTaken); rSeen.insertLast(seenMex);
			// what killing their extractor there is worth: its cost + what it would extract over our horizon
			// its yield until they could stand it again (their constructor's walk from their base + build), as a seen
			// enemy extractor is valued (EnemyValue, #107) - over the whole horizon (~10700 s early) every far corner
			// outweighed defending home and the first fighters left one by one for them (swe13: ops at 6800,752 and
			// 6960,5888 at 2:30-4:00, pickets 0)
			float rebuild = Economist::Horizon();
			{
				const CCircuitDef@ con = CheapestConstructor();
				if (con !is null && Economist::mexT1 !is null)
					rebuild = AiMin(rebuild, AiEnemyBasePos().distance2D(msp[i]) / AiMax(1.f, con.speed) + Economist::mexT1.buildTime / AiMax(1.f, con.buildSpeed));
			}
			const float yieldH = (Economist::mexT1 is null) ? 0.f : msi[i] * Economist::Extract(Economist::mexT1.GetName()) * rebuild;
			rv.insertLast(mexV + yieldH);
		}
		// They can't hold more spots than their economy allows - as many extractors as we have (they earn as we do): the
		// unseen spots' chances sum to at most our extractor count less the extractors of theirs we see. Never seen, every
		// far spot read as certainly theirs by 2:00; the first Pawns and Ticks left one each for their corners while 3-4
		// Grunts killed our extractors at 3:05-3:40 with nothing home (spectator, swe1-12)
		{
			float seenM = 0.f, unseenSum = 0.f;
			for (uint k = 0; k < rp.length(); ++k) { if (rSeen[k]) seenM += 1.f; else unseenSum += rTakenRaw[k]; }
			const float room = AiMax(0.f, float(Economist::mexes.length()) - seenM);
			const float scaleU = (unseenSum > room && unseenSum > 0.f) ? room / unseenSum : 1.f;
			for (uint k = 0; k < rp.length(); ++k) rv[k] *= rSeen[k] ? 1.f : rTakenRaw[k] * scaleU;
		}
		raidPos = rp; raidVal = rv;
	}
	behind = ours < theirs;
	// the core's constructor rule (decide): builds constructors while build power < income x ratio. A constructor
	// pays only through work the ones we have can't do: open extractor spots on our side to claim. Behind without, more constructors only spend (smoke 2026-11-25: 22 constructors,
	// 4 extractors, army 403 vs 3170).
	// Unclaimed income = spots nobody holds (all, minus ours, minus enemy extractors we know of). Top 1v1 winners keep
	// about one constructor per extractor and expand hard (replays.db, 11 games: 8 extractors / 8 constructors at
	// minute 4, 22 / 26 at minute 8); "behind and on our side" held Anarva at 5 extractors.
	array<AIFloat3> msp2; array<float> msi2; array<bool> mso2;
	const int ns2 = int(AiGetMetalSpots(msp2, msi2, mso2));
	const int unclaimed = ns2 - int(Economist::mexes.length()) - int(enemyMex);
	// (Overflowing metal is not constructor work: it is missing spending capacity, i.e. factories. As a reason for
	// constructors it made 49 of them on Throne while one lab sat on 4600 metal, 1v1 2026-11-25.)
	// Claiming is limited by walking: a constructor takes one spot per (walk + build) seconds, so claiming the
	// unclaimed spots within the planning horizon needs  sum over them of (walk from base + build) / H  constructors.
	// Neither unlimited (1e9: the lab made only constructors, army 344 vs 1560 at minute 7, Throne) nor income-bound
	// (build power x income: the commander alone covered it, 2 constructors and 5 extractors in 10 minutes, Avalanche).
	// One more constructor is worth the yield it saves by claiming the free spots sooner. With N constructors the
	// remaining claim work takes work/N seconds, each spot waits half of that on average and yields nothing meanwhile,
	// so the (N+1)th saves  yield x work/2 x (1/N - 1/(N+1)). Build one while that beats its cost (and while we are not
	// weaker than the known enemy army). "Enough to claim within the horizon" asked for 1-2 constructors early (the
	// horizon is long while we own the commander's 2700 metal) while the winners run 7 by minute 4.
	float claimWork = 0.f, claimYield = 0.f;  // constructor-seconds; metal/s the free spots would yield us
	array<float> spWork, spYield;  // per free spot: walk + build seconds, metal/s kept
	CCircuitDef@ conDef = CheapestConstructor();
	if (conDef !is null && Economist::mexT1 !is null && HasBase()) {
		const float conSpeed = AiMax(1.f, conDef.speed);
		const float conBuild = Economist::mexT1.buildTime / AiMax(1.f, conDef.buildSpeed);
		const float ext = Economist::Extract(Economist::mexT1.GetName());
		// Players expand behind their army: a spot on their side of the map is ours only as far as our army controls
		// it, our strength / (ours + theirs) (20 constructors and an army of 54-420 against the winners' 15 and
		// 648-3395: spots nobody could hold drove constructor production, Gasbag Grabens 2026-11-25)
		const float control = Production::ArmyControl();
		// our side is held too, by the army, the commander and our armed buildings: the raids come there first (a
		// spot at home counted in full while the enemy's 1387 strength faced our 24 - the lab built 14 constructors
		// and army 0 at minute 4 against the winners' 656, Gasbag 2026-11-25)
		const float homeControl = Production::ArmyControl(true);
		for (int i = 0; i < ns2; ++i)
			if (mso2[i] && !OwnSpot(msp2[i])) {
				// weighted by the share we keep: how much sooner we reach the spot than they do
				const float dUs = basePos.distance2D(msp2[i]), dThem = AiEnemyBasePos().distance2D(msp2[i]);
				float keep = (dUs + dThem > 0.f) ? dThem / (dUs + dThem) : 1.f;
				keep *= (dThem < dUs) ? control : homeControl;
				claimWork += keep * (dUs / conSpeed + conBuild);
				claimYield += keep * msi2[i] * ext;
				spWork.insertLast(dUs / conSpeed + conBuild); spYield.insertLast(keep * msi2[i] * ext);
			}
	}
	const float N = float(AiMax(1, int(aiBuilderMgr.GetWorkerCount())));
	// the yield claimed is metal: worth the share of our metal we actually spend (with 500-1000 banked a constructor
	// scored 2x a Pawn and the lab made ~9 units by 4:00, half constructors, vs the winners' 17.6 - 3.9 constructors,
	// 13.7 Pawns and Fleas: replays.db, 24 Armada bot-lab 1v1 winners)
	// The claim schedule within the horizon: N constructors take the spots least work first, spot j done at
	// T_j = (work up to j) / N, yielding until the horizon: V(N) = sum y_j (H - T_j)+. One more is worth V(N+1) - V(N).
	// (yield x work/2 x (1/N - 1/(N+1)) summed every free spot on the map with no horizon - quadratic in the spot count:
	// a constructor read 22597 against a Pawn's 183 at 2:00 and the lab made 6 constructors by 4:14 while raiders
	// killed the extractors - metal 6.6 vs BARb 18.1 and army 270 vs 637 at 4:00, swing.py sw5)
	for (uint a = 0; a < spWork.length(); ++a)
		for (uint b = a + 1; b < spWork.length(); ++b)
			if (spWork[b] < spWork[a]) { const float tw = spWork[a]; spWork[a] = spWork[b]; spWork[b] = tw; const float ty = spYield[a]; spYield[a] = spYield[b]; spYield[b] = ty; }
	const float Hc = AiMax(1.f, Economist::Horizon());
	// feedback (owner: "ignores losses? is there no feedback loop?"): a claimed extractor yields until the horizon or
	// until it dies, whichever comes first - its measured life once producers have been lost (no horizon floor)
	const float Lm = (Economist::producerLosses > 0) ? Economist::MeasuredLife() : 1e30f;
	float vN = 0.f, vN1 = 0.f, cum = 0.f;
	for (uint j = 0; j < spWork.length(); ++j) {
		cum += spWork[j];
		vN += spYield[j] * AiMin(Lm, AiMax(0.f, Hc - cum / N));
		vN1 += spYield[j] * AiMin(Lm, AiMax(0.f, Hc - cum / (N + 1.f)));
	}
	const float saved = (vN1 - vN) * Economist::MetalShare();
	// A constructor without a building job proves the work we can claim now is covered: one more saves nothing (25
	// constructors, 12 idle and 3 extractors at minute 8 while the raiders made every free spot unsafe: Eye of Horus
	// 1v1, 2026-11-25). The lab builds the army that makes spots claimable instead.
	int unemployed = 0;
	{
		const array<CCircuitUnit@>@ mine = AiGetTeamUnits();
		for (uint i = 0; i < mine.length(); ++i) {
			CCircuitUnit@ u = mine[i];
			if (u is commander || !u.circuitDef.IsMobile() || !u.circuitDef.IsRoleAny(Unit::Role::BUILDER.mask) || u.task is null) continue;
			// only builders that can claim a spot: a minelayer (builder role, mines only) guarding the lab zeroed the
			// constructor's value and Throne kept 3 extractors all game (2026-11-25)
			if (Economist::mexT1 is null || !u.circuitDef.CanBuild(Economist::mexT1)) continue;
			if (u.task.GetType() == Task::Type::NIL) continue;  // still in the factory
			IBuilderTask@ bt = cast<IBuilderTask>(u.task);
			// (Counting constructors on non-extractor jobs as spare froze our builders at 5-7 all game while BARb grew to 36:
			// extractors 8-10 vs 46, metal 20 vs 151 at 20:00, army 11k vs 3.7k - the owner's game 2026-11-26, replay view.)
			if (bt is null || bt.buildDef is null) ++unemployed;
		}
	}
	const bool work = unclaimed > 0 && unemployed == 0 && conDef !is null && saved > Economist::MetalValue(conDef) && Director::ratio >= 1.f;
	// the value Production weighs against every other unit: the yield saved, while every constructor has a job
	constructorValue = (unclaimed > 0 && unemployed == 0) ? saved : 0.f;
	if (ai.frame - conLogFrame >= SECOND * 30) {
		conLogFrame = ai.frame;
		AiLog("[ANV-CONVAL] spots " + spWork.length() + " unclaimed " + unclaimed + " unemployed " + unemployed + " N " + int(N) + " H " + int(Hc)
			+ " Lm " + (Lm > 1e20f ? "-" : ("" + int(Lm))) + " vN " + int(vN) + " vN1 " + int(vN1) + " share " + F2(Economist::MetalShare())
			+ " first work " + (spWork.length() > 0 ? int(spWork[0]) : -1) + " yield " + (spYield.length() > 0 ? F2(spYield[0]) : "-") + " -> " + int(constructorValue));
	}
	wantConstructor = work;
	aiFactoryMgr.buildpowerRatio = 0.f;  // the core never asks for constructors itself: Production weighs constructorValue (#96)
}
string Status() { return "ecoPos " + (behind ? "behind" : "ahead") + " ours=" + int(ours) + " theirs~" + int(theirs); }
}  // namespace EcoPos

/*
 * Outer extractor defence (Vritrasura108, #43: "invest early into LLTs or pawns ... however LLTs can be killed by a
 * single rocket bot so they should not be overinvested"). An extractor gets a turret when the metal lost around it
 * recently (raid evidence, Intel heat) exceeds the turret's cost and the turret would survive there (TurretSurvives).
 */
namespace MexPorc {
int orders = 0;
IUnitTask@ pending = null;  // the tower ordered last, until its job ends: one at a time, like a player (26 towers in
                            // 10 minutes when every update ordered another before the last one stood, Gasbag)
int pendingFrame = 0;
float pendingValue = 0.f;
void OnTaskRemoved(IUnitTask@ t)
{
	if (t !is pending) return;
	// why tower orders end (a log for each: 8 orders gave 1 tower and nothing said why)
	IBuilderTask@ bt = cast<IBuilderTask>(t);
	AiLog("[ANV-TOWEREND] f=" + ai.frame + " tower job ended after " + ((ai.frame - pendingFrame) / SECOND) + " s, builders "
		+ t.GetUnits().length() + ", built " + ((bt !is null && bt.target !is null) ? "started" : "not started"));
	@pending = null;
}
bool IsFactory(const CCircuitDef@ d) { return !d.IsMobile() && d.buildSpeed > 0.f && Facts::BuildOptions(d.GetName()).length() > 0; }
// The metal of the spot under an extractor at p: the nearest metal spot within the extractor's radius x 2 (its
// footprint), else the map's average. Spots differ in richness (owner: "different metal spots have different values");
// valued at the average, a rich spot and a poor one counted the same (#107).
float SpotMetalAt(const AIFloat3& in p, const CCircuitDef@ d)
{
	array<AIFloat3> sp; array<float> si; array<bool> so;
	const uint ns = AiGetMetalSpots(sp, si, so);
	float avg = 0.f, best = -1.f, bd = 1e9f;
	for (uint i = 0; i < ns; ++i) {
		avg += si[i];
		const float dd = sp[i].distance2D(p);
		if (dd < bd) { bd = dd; best = si[i]; }
	}
	avg = (ns > 0) ? avg / float(ns) : 0.f;
	return (best >= 0.f && bd <= 2.f * AiMax(1.f, d.GetRadius())) ? best : avg;
}
float RaidLoss(CCircuitUnit@ u, const CCircuitDef@ con)
{
	const CCircuitDef@ d = u.circuitDef;
	const string nm = d.GetName();
	const float upkeep = Facts::EnergyUpkeep(nm);
	const float eYield = Facts::EnergyMake(nm) + ((upkeep < 0.f) ? -upkeep : 0.f);
	float yield = Economist::Extract(nm) * SpotMetalAt(u.GetPos(ai.frame), d) + Facts::MetalMake(nm) + eYield / AiMax(1e-3f, Economist::energyPerMetal);
	// A factory's output is the army: while it is down, everything it would make isn't made. Its yield is its build
	// power x the metal per build-second of what it makes (unit facts). Counted at its cost alone, one Incisor killed our
	// lab at 3.7 min while the army raided far spots (Canis 2026-11-26).
	if (!d.IsMobile() && d.buildSpeed > 0.f) {
		const array<string>@ opts = Facts::BuildOptions(nm);
		float sm = 0.f, sbt = 0.f;
		for (uint k = 0; k < opts.length(); ++k) {
			CCircuitDef@ o = ai.GetCircuitDef(opts[k]);
			if (o is null || !o.IsMobile()) continue;
			sm += o.costM; sbt += o.buildTime;
		}
		if (sbt > 0.f) yield += d.buildSpeed * sm / sbt;
		// the last factory is all of our production: without it no unit at all is made (the constructor to rebuild it
		// included), so its loss is the game's (owner: "losing a lab mainly means no unit production at all?!")
		uint facs = 0;
		const array<CCircuitUnit@>@ all = AiGetTeamUnits();
		for (uint k = 0; k < all.length(); ++k) if (IsFactory(all[k].circuitDef)) ++facs;
		if (facs <= 1) return Economist::MetalValue(d) + GameValue();
	}
	float rebuild = 0.f;
	if (con !is null) rebuild = (HasBase() ? basePos.distance2D(u.GetPos(ai.frame)) : 0.f) / AiMax(1.f, con.speed) + d.buildTime / AiMax(1.f, con.buildSpeed);
	return Economist::MetalValue(d) + yield * rebuild;
}
dictionary guarded;  // mex id -> frame ordered
void Update()
{
	if (!HasBase()) return;
	// the last tower first - unless nobody has taken it and a better site appears: a barely-worth order (103 vs a 94
	// turret) sat untaken all game and blocked every better tower (1 tower by minute 8 against Cortex)
	if (pending !is null && pending.GetUnits().length() > 0) return;
	CCircuitDef@ tur = Strategic::BestTurret();
	if (tur is null || !tur.IsAvailable(ai.frame)) return;
	const float cost = Economist::MetalValue(tur);
	// sites: extractors. (Factories here made every tower near the lab look worth ~1000 and builders spent the opening
	// on towers - 0 extractors at minute 4; winners build 0.2 towers by 3:00 and defend the lab with the army. The
	// lab's value goes to the army's defence decision, Command::OursThreatened.)
	const array<CCircuitUnit@>@ mx = Economist::mexes;
	CCircuitUnit@ best = null; float bestHeat = cost;
	for (uint i = 0; i < mx.length(); ++i) {
		if (guarded.exists("" + mx[i].id)) continue;
		const float h = Intel::heat[Intel::CellOf(mx[i].GetPos(ai.frame))];
		if (h > bestHeat) { bestHeat = h; @best = mx[i]; }
	}
	/*
	 * Before the raid, not after it (95 of 106 winners build turrets early: median 4 armed buildings by minute 6, the
	 * first at ~217 s - when the first raids arrive; replays.db): from when the earliest enemy raid can arrive
	 * (less the tower's build time), a raid goes where our value is, so the loss expected at an unguarded spot is its
	 * value in the tower's reach x its share of all our exposed producer value. A tower pays when that beats it.
	 */
	const bool seen = best !is null;  // a raid that has already hit there: urgent
	const float now = float(ai.frame) / SECOND;
	const float tBuild = tur.buildTime / AiMax(1.f, aiBuilderMgr.GetBuildPower());
	if (best is null && now + tBuild >= Opening::raidArrive) {
		const array<CCircuitUnit@>@ mine = AiGetTeamUnits();
		float total = 0.f;
		array<float> val(mx.length(), 0.f);
		// what a raid takes from a producer: its cost and its yield until it stands again (a constructor's walk from
		// base + build), not its whole future - we rebuild (with the horizon's worth every extractor earned a tower:
		// 11 constructors on towers at minute 12, Gasbag Grabens)
		CCircuitDef@ con = EcoPos::CheapestConstructor();
		for (uint i = 0; i < mine.length(); ++i)
			if (Economist::IsProducer(mine[i].circuitDef)) total += RaidLoss(mine[i], con);
		const float r = tur.GetMaxRange();
		for (uint i = 0; i < mx.length(); ++i) {
			if (guarded.exists("" + mx[i].id)) continue;
			const AIFloat3 q = mx[i].GetPos(ai.frame);
			bool covered = false;
			for (uint k = 0; k < mine.length() && !covered; ++k)
				covered = !mine[k].circuitDef.IsMobile() && mine[k].circuitDef.surfThrDmg > 0.f && mine[k].GetPos(ai.frame).distance2D(q) <= mine[k].circuitDef.GetMaxRange();
			if (covered) continue;
			for (uint k = 0; k < mine.length(); ++k)
				if (Economist::IsProducer(mine[k].circuitDef) && mine[k].GetPos(ai.frame).distance2D(q) <= r) val[i] += RaidLoss(mine[k], con);
			// raids come back: about once per raider round trip from their base to the spot, so over the horizon the
			// tower saves the per-raid loss that many times (valued at one raid, no tower was built by minute 8 against
			// Cortex, where Armada winners build 6.2 light lasers - replays.db, 28 games)
			const float cycle = 2.f * AiEnemyBasePos().distance2D(q) / AiMax(1.f, Opening::raidSpeed);
			const float raids = AiMax(1.f, Economist::Horizon() / AiMax(1.f, cycle));
			// A raid doesn't stop at one site: unanswered, it keeps killing until our nearest armed unit gets there. Sites it
			// clears per raid = answer time / (time to kill a site + walk to the next). With one site per raid (share
			// alone) a tower scored 5-10x worse than an extractor per builder-second and 9 orders gave 1 tower by
			// minute 8 vs Cortex (players 6.2, replays.db 28 games).
			float answer = Economist::Horizon(), hp = 0.f, gap = 0.f;
			for (uint k = 0; k < mine.length(); ++k) {
				const CCircuitDef@ kd = mine[k].circuitDef;
				const float dk = mine[k].GetPos(ai.frame).distance2D(q);
				if (kd.IsMobile() && kd.surfThrDmg > 0.f && kd.buildSpeed <= 0.f) answer = AiMin(answer, dk / AiMax(1.f, kd.speed));
				if (Economist::IsProducer(kd) && dk <= r) hp += kd.health;
			}
			for (uint k = 0; k < mx.length(); ++k) {
				const float dk = mx[k].GetPos(ai.frame).distance2D(q);
				if (k != i && (gap == 0.f || dk < gap)) gap = dk;
			}
			const float perSite = hp / AiMax(1.f, Opening::raidDps) + gap / AiMax(1.f, Opening::raidSpeed);
			const float cleared = AiMax(1.f, answer / AiMax(1.f, perSite));
			const float pHit = AiMin(1.f, cleared * val[i] / AiMax(1.f, total));
			float expected = val[i] * pHit * raids;
			// ...and it kills raiders: a raid that reaches it spends about 2 x its range / the raider's speed under its
			// fire, taking its dps that long; the kills (a share of one raider at least) are worth the raider's cost each
			// (unit facts). Counted as loss prevented alone, a second tower never beat an extractor (1 tower by minute 8
			// vs Cortex, players 6.2).
			if (Opening::raidHp > 0.f && Opening::raidSpeed > 0.f) {
				const float exposure = 2.f * tur.GetMaxRange() / Opening::raidSpeed;
				// limited by how many come: the armed enemy mobiles we know of (at least one). Capped at one raider, a light
				// laser that can kill ~4 Grunts per pass counted one while 7 raided (cmd_m13)
				array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
				const uint en = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
				float raiders = 0.f;
				for (uint e = 0; e < en; ++e) if (ed[e] !is null && ed[e].IsMobile() && ed[e].surfThrDmg > 0.f && ed[e].buildSpeed <= 0.f) raiders += 1.f;
				const float kills = AiMin(AiMax(1.f, raiders), tur.GetSustainedDps() * exposure / Opening::raidHp);
				expected += raids * kills * Opening::raidCostM * pHit;
			}
			// measured, once uncovered producers have died: over the tower's life (the covered life) each producer in
			// its reach is lost Lc/Lu - 1 fewer times, each loss its RaidLoss
			if (Economist::uncoveredLosses > 0) {
				const float Lc = Economist::CoveredLife(), Lu = AiMax(1.f, Economist::UncoveredLife());
				const float avoided = val[i] * AiMax(0.f, Lc / Lu - 1.f);
				expected = AiMax(expected, avoided + (expected - val[i] * pHit * raids));  // measured loss term, kills kept
			}
			if (expected > bestHeat) { bestHeat = expected; @best = mx[i]; }
		}
	}
	if (best is null) return;
	if (pending !is null) {
		if (bestHeat <= pendingValue) return;  // the pending order is still the best site
		// a builder on its way has taken it: a tower that gets built beats a better one that never does (replaced under
		// the walking builder, ~20 orders between 4:03 and 13:14 built none while one extractor died 7 times; df5)
		if (pending.GetUnits().length() > 0) return;
		AiLog("[ANV] MexPorc: untaken tower order (worth " + int(pendingValue) + ") replaced by a better site (" + int(bestHeat) + ")");
		pending.Abort();
		@pending = null;
	}
	const AIFloat3 p = best.GetPos(ai.frame);
	if (!TurretSurvives(tur, p)) return;
	guarded.set("" + best.id, ai.frame);
	++orders;
	// An explicit decision while metal is being lost here (the losses beat the turret): NOW, the one band the builders'
// ranking keeps. Only turrets against a raid and the opener are NOW: with cameras, storage, shields NOW too, six
// constructors built cameras at minute 9 while extractors stood at 4 (Canis River, 2026-11-25) - as a
	// plain job it counted at its cost only and was never built (3 orders, 0 towers on Canis River, 2026-11-25)
	// next to the extractor, not on it: the build site is searched within the two footprints side by side (at the
	// extractor's own position with radius 0 the job could never be placed: 8 orders, 1 tower, Gasbag Grabens)
	const float around = tur.GetRadius() * 2.f + best.circuitDef.GetRadius() * 2.f;
	// Urgent only against a raid that has hit (seen loss beats the tower). Before that the tower is worth the loss it
	// is expected to prevent and competes on that value with every other job: as NOW it skipped the comparison and
	// took the commander off extractors and wind twice before minute 2.5 (Theta, round 29), while winners build 0.2
	// towers by 3:00 against 8.4 turbines and 5 extractors (replays.db, 107 wins).
	// a pre-emptive tower answers a danger that lasts the horizon: its claim lives that long (with the minimum walk +
	// build as its life, 10 orders gave 1 tower by minute 8 - each expired untaken while builders were busy)
	const int life = seen ? OrderLife(tur, p) : int(Economist::Horizon() * SECOND) + 1;
	@pending = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE, seen ? Task::Priority::NOW : Task::Priority::NORMAL,
		tur, p, around, true, life));
	pendingFrame = ai.frame;
	pendingValue = bestHeat;
	IBuilderTask@ pbt = cast<IBuilderTask>(pending);
	if (pbt !is null) {
		pbt.value = bestHeat;
		// a tower goes where raids come: the core's "abort when the path isn't safe" dropped exactly these (8 orders,
		// 1 tower by minute 8 against Cortex); the builder's own evacuation still weighs its life
		pbt.canAutoAbort = false;
	}
	AiLog("[ANV] MexPorc: " + tur.GetName() + (seen ? " NOW" : " valued") + " at extractor (loss there, seen or expected from the raid, " + int(bestHeat) + " > turret " + int(cost) + ")");
}
}  // namespace MexPorc

/*
 * Radar (#48 vision, script blindness): 96 of 107 1v1 winners build radar, the first at a median 3.3 min and 5 by
 * 12:00 (replays.db); we built none, and the commander died to enemies nobody saw coming (an unseen attacker 2651
 * out, a Reaper at 823 - cs1-3). A radar turns unseen enemies into seen ones within its range (unit facts:
 * radardistance, gen_facts.py). It is worth what it covers, not yet under radar - everything of ours there, the
 * commander at the game's value - times the share of the enemy we can't see now: their strength unseen is at least
 * ours less what we see (they earn as we do), over all of it. Seeing everything, a radar adds nothing. Built at the
 * site of ours (a building, or the commander) where that is largest, from the radar our constructors can build with
 * the most value per metal; one order at a time, its value competing with every other job.
 */
namespace Radar {
IUnitTask@ pending = null;
int lastLog = -1000000;
void OnTaskRemoved(IUnitTask@ task) { if (task is pending) @pending = null; }
void Update()
{
	if (pending !is null || !HasBase() || Brain::Intel::allFactories.length() == 0) return;
	const array<CCircuitUnit@>@ mine = AiGetTeamUnits();
	// the radars our constructors can build, and the ground our radars already cover
	array<CCircuitDef@> defs;
	array<AIFloat3> rp; array<float> rr;
	for (uint i = 0; i < mine.length(); ++i) {
		const CCircuitDef@ d = mine[i].circuitDef;
		const float rd = Facts::RadarRange(d.GetName());
		if (!d.IsMobile() && rd > 0.f) { rp.insertLast(mine[i].GetPos(ai.frame)); rr.insertLast(rd); }
		if (!d.IsMobile() || d.buildSpeed <= 0.f) continue;
		const array<string> opts = Facts::BuildOptions(d.GetName());
		for (uint k = 0; k < opts.length(); ++k) {
			CCircuitDef@ o = ai.GetCircuitDef(opts[k]);
			if (o is null || o.IsMobile() || !o.IsAvailable(ai.frame) || defs.findByRef(o) >= 0) continue;
			if (Facts::RadarRange(o.GetName()) <= 0.f || o.GetSustainedDps() > 0.f || Facts::BuildOptions(o.GetName()).length() > 0) continue;
			if (o.IsAbleToFly()) continue;
			defs.insertLast(o);
		}
	}
	if (defs.length() == 0) return;
	// nothing hidden can be near before the earliest enemy raid can arrive (as the commander's fog): a radar is worth
	// something only from then, so it is ordered when it would stand by then (its build time at our build power). At
	// "unseen share 1.00" from the first second it took the first constructor's time at 80-136 s while extractors waited
	// (winners' first radar: median 3.3 min, replays.db)
	const float tBuildR = defs[0].buildTime / AiMax(1.f, aiBuilderMgr.GetBuildPower());
	if (float(ai.frame) / SECOND + tBuildR < Opening::raidArrive) return;
	// the share of their strength we don't see
	const float seen = Economist::KnownEnemyThreat();
	const float ours = Director::OurPower();
	const float hidden = AiMax(0.f, ours - seen);
	const float share = hidden / AiMax(1e-3f, hidden + seen);
	if (share <= 0.f) return;
	const float V = GameValue();
	int bestU = -1; CCircuitDef@ bestD = null; float bestV = 0.f, bestRatio = 0.f;
	for (uint s = 0; s < mine.length(); ++s) {
		const bool comm = mine[s] is commander;
		if (mine[s].circuitDef.IsMobile() && !comm) continue;
		const AIFloat3 site = mine[s].GetPos(ai.frame);
		for (uint di = 0; di < defs.length(); ++di) {
			const float R = Facts::RadarRange(defs[di].GetName());
			float v = 0.f;
			for (uint i = 0; i < mine.length(); ++i) {
				const AIFloat3 q = mine[i].GetPos(ai.frame);
				if (q.distance2D(site) > R) continue;
				bool covered = false;
				for (uint k = 0; k < rp.length() && !covered; ++k) covered = q.distance2D(rp[k]) <= rr[k];
				if (covered) continue;
				v += (mine[i] is commander) ? V : mine[i].circuitDef.costM;
			}
			v *= share;
			// ...and the warning it gives (#111, owner: "you cant see the enemy with that single radar"): for each producer
			// of ours, the stretch of the enemy's approach (the line from their base) inside this radar's range and not yet
			// watched (sight or another radar), over the enemy's speed, is the extra warning; it saves that producer's value
			// x warning / horizon. Counted only on our own ground, one radar over the base looked like enough and the second
			// (valued 158-428) was never taken; a winner put one 1396 out among the far extractors (replays.db d346036b).
			{
				const AIFloat3 eb = AiEnemyBasePos();
				const float eSpeed = AiMax(1.f, Director::allSpeed);
				const float Hw = AiMax(1.f, Economist::Horizon());
				const float step = AiMax(1.f, R / 4.f);
				for (uint i = 0; i < mine.length(); ++i) {
					if (!Economist::IsProducer(mine[i].circuitDef)) continue;
					const AIFloat3 q = mine[i].GetPos(ai.frame);
					const float L = eb.distance2D(q);
					if (L <= 0.f) continue;
					float inside = 0.f;
					for (float t = 0.f; t <= L; t += step) {
						const AIFloat3 pt = eb + (q - eb) * (t / L);
						if (pt.distance2D(site) > R || AiIsInLOS(pt)) continue;
						bool cov = false;
						for (uint k = 0; k < rp.length() && !cov; ++k) cov = pt.distance2D(rp[k]) <= rr[k];
						if (!cov) inside += step;
					}
					v += Economist::MetalValue(mine[i].circuitDef) * (inside / eSpeed) / Hw;
				}
			}
			const float ratio = v / AiMax(1.f, Economist::MetalValue(defs[di]));
			if (ratio > bestRatio) { bestRatio = ratio; bestV = v; bestU = int(s); @bestD = defs[di]; }
		}
	}
	if (bestD is null || bestV <= Economist::MetalValue(bestD)) return;  // it must be worth more than it costs
	const AIFloat3 p = mine[bestU].GetPos(ai.frame);
	@pending = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::RADAR, Task::Priority::NORMAL, bestD, p, bestD.GetRadius() * 4.f, true, OrderLife(bestD, p)));
	IBuilderTask@ bt = cast<IBuilderTask>(pending);
	if (bt !is null) bt.value = bestV;
	AiLog("[ANV] Radar: " + bestD.GetName() + " at (" + int(p.x) + "," + int(p.z) + ") by " + mine[bestU].circuitDef.GetName() + ": covers "
		+ int(bestV / share) + " unwatched x unseen share " + F2(share) + " (seen " + F1(seen) + ", ours " + F1(ours) + ") = " + int(bestV) + " > cost " + int(Economist::MetalValue(bestD)));
}
}  // namespace Radar

/* ======================================================================== */
/*
 * Scouting by the value of vision (issue #48, Vritrasura108). Each cell keeps the time since we last had
 * sight of it. What we don't see there could have reached anything of ours within (age x the enemy's
 * mean speed), so the value of looking = our metal inside that reach. Unidentified radar dots in the
 * cell add their likely value (new reinforcements). A cell in sight is worth nothing; a cell long dark
 * next to our extractors or the front is worth a lot. Scouts take the best targets (core switch
 * scoutMap); we keep one more scout while there is a dark cell worth more than a scout.
 */
namespace Scout {

array<int> lastSeen;
array<float> value;
int sent = 0;
float topValue = 0.f;
uint worthy = 0;
CCircuitDef@ cheapest = null;

void Init()
{
	const int n = Intel::gw * Intel::gh;
	lastSeen.resize(n); value.resize(n);
	for (int c = 0; c < n; ++c) { lastSeen[c] = 0; value[c] = 0.f; }
	array<CCircuitDef@> sc = Defs({"armflea", "armfav", "corfav", "legscout", "armpeep", "corfink", "legfig"});
	for (uint i = 0; i < sc.length(); ++i)
		if (cheapest is null || sc[i].costM < cheapest.costM) @cheapest = sc[i];
}

// What scouting finds, measured: enemy metal first seen within a scout's sight, per scout-second (#116: valued on
// a model alone, Ticks as scouts at 1.57 per metal crowded out Centurions - the only unit trading above 1, fe4)
dictionary seenIds;
float foundMetal = 0.f, scoutSeconds = 0.f; int foundFrame = -1;
void TrackFinds()
{
	if (foundFrame >= 0) scoutSeconds += float(scouts.length()) * float(ai.frame - foundFrame) / SECOND;
	foundFrame = ai.frame;
	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef, ids;
	const uint ne = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	AiGetEnemyIds(ids);
	for (uint i = 0; i < ne && i < ids.length(); ++i) {
		const string key = "" + ids[i];
		if (seenIds.exists(key) || (ef[i] & 2) == 0) continue;  // known, or only a radar blip
		seenIds.set(key, true);
		for (uint k = 0; k < scouts.length(); ++k)
			if (scouts[k].GetPos(ai.frame).distance2D(ep[i]) <= scouts[k].circuitDef.losRadius) { foundMetal += ec[i]; break; }
	}
}
// A scout parked on the enemy's approach warns like a radar (#111's term): for each producer of ours, the stretch of the
// line from their base to it within the scout's sight and not yet watched (sight or radar), over their speed, saves its
// value x warning / horizon - at the best point along the approach, over the scout's measured life share of the horizon.
// Valued only for metal it finds (pOcc 0.02 early), our first Tick came at 190 s against the winners' 84 s, and Grunts
// reached our extractors unseen from 3:17 (swe2, blind at 2:00 and 3:00; replays.db, 20 winners)
float WarningValue(const CCircuitDef@ d)
{
	const AIFloat3 eb = AiEnemyBasePos();
	if (!HasBase() || d is null) return 0.f;
	const float R = AiMax(1.f, d.losRadius);
	const float eSpeed = AiMax(1.f, Director::allSpeed);
	const float Hw = AiMax(1.f, Economist::Horizon());
	const array<CCircuitUnit@>@ mine = AiGetTeamUnits();
	array<AIFloat3> rp; array<float> rr;
	for (uint i = 0; i < mine.length(); ++i) {
		const float rd = Facts::RadarRange(mine[i].circuitDef.GetName());
		if (!mine[i].circuitDef.IsMobile() && rd > 0.f) { rp.insertLast(mine[i].GetPos(ai.frame)); rr.insertLast(rd); }
	}
	const float L0 = eb.distance2D(basePos);
	float best = 0.f;
	for (float f = R; f < L0; f += R) {  // candidate posts along the approach to our base, a sight radius apart
		const AIFloat3 site = eb + (basePos - eb) * (f / L0);
		float v = 0.f;
		for (uint i = 0; i < mine.length(); ++i) {
			if (!Economist::IsProducer(mine[i].circuitDef)) continue;
			const AIFloat3 q = mine[i].GetPos(ai.frame);
			const float L = eb.distance2D(q);
			if (L <= 0.f) continue;
			float inside = 0.f;
			for (float t = 0.f; t <= L; t += R / 4.f) {
				const AIFloat3 pt = eb + (q - eb) * (t / L);
				if (pt.distance2D(site) > R || AiIsInLOS(pt)) continue;
				bool cov = false;
				for (uint k = 0; k < rp.length() && !cov; ++k) cov = pt.distance2D(rp[k]) <= rr[k];
				if (!cov) inside += R / 4.f;
			}
			v += Economist::MetalValue(mine[i].circuitDef) * (inside / eSpeed) / Hw;
		}
		best = AiMax(best, v);
	}
	return best * AiMin(1.f, Life() / Hw);
}
// measured worth of one more scout: metal found per scout-second x the scouts' life; -1 until scouts have served
float MeasuredWorth() { return (scoutSeconds > 0.f) ? foundMetal / scoutSeconds * Life() : -1.f; }
void Update()
{
	TrackFinds();
	const int n = Intel::gw * Intel::gh;
	if (int(lastSeen.length()) != n) Init();
	for (int c = 0; c < n; ++c)
		if (AiIsInLOS(Intel::CellCenter(c))) lastSeen[c] = ai.frame;
	// our metal per cell
	array<float> ours(n, 0.f);
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	for (uint i = 0; i < all.length(); ++i) ours[Intel::CellOf(all[i].GetPos(ai.frame))] += all[i].circuitDef.costM;
	// the enemy's mean speed and mean cost (what we have seen of them)
	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
	const uint ne = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	float sp = 0.f, cost = 0.f; uint ns = 0;
	array<float> dots(n, 0.f);
	for (uint i = 0; i < ne; ++i) {
		if (ed[i] !is null && ed[i].IsMobile()) { sp += ed[i].speed; cost += ed[i].costM; ++ns; }
		if ((ef[i] & 2) != 0 && (ef[i] & 1) == 0) dots[Intel::CellOf(ep[i])] += 1.f;
	}
	Director::MeasuredPower();
	const float speed = ns > 0 ? sp / ns : AiMax(1.f, Director::allSpeed);
	const float meanCost = ns > 0 ? cost / ns : 0.f;
	/*
	 * Value of seeing cell c, per asset a of ours (cells holding our metal):
	 *   warning   = min(d(c,a)/speed, Tr(a)) / Tr(a): seeing c warns a by the enemy's travel time from c, but only up
	 *               to a's response time Tr(a) (our army's travel time to a) is useful
	 *   staleness = min(1, age(c)*speed / d(c,a)): something can only be at c, on its way to a, if c has been dark long enough
	 *   direction = for later picks, the angle between c and the picks already watching a (0 same way .. 1 opposite)
	 * A pick is kept while its value beats what a scout costs.
	 */
	array<int> assets;
	for (int c = 0; c < n; ++c) if (ours[c] > 0.f) assets.insertLast(c);
	// cells inside a known enemy turret's reach (19 Fleas died to light laser towers on Canis River, 2026-11-25)
	array<bool> covered(n, false);
	for (uint i = 0; i < ne; ++i) {
		if (ed[i] is null || ed[i].IsMobile() || ed[i].GetSustainedDps() <= 0.f) continue;
		const float r = ed[i].GetMaxRange();
		for (int c = 0; c < n; ++c)
			if (!covered[c] && Intel::CellCenter(c).distance2D(ep[i]) <= r) covered[c] = true;
	}
	/*
	 * Offence (Vritrasura108 #74: scouts in several directions find unprotected extractors and constructors to raid).
	 * An open metal spot on the enemy's side may have been taken since we last looked: the chance grows with how
	 * long the cell has been dark against the time the enemy needs to cross the map (diagonal / their speed). Its
	 * value is what a raid there kills: an extractor.
	 */
	array<float> raidable(n, 0.f);
	{
		array<AIFloat3> msp; array<float> msi; array<bool> mso;
		const uint ns2 = AiGetMetalSpots(msp, msi, mso);
		CCircuitDef@ mexDef = Strategic::Side("armmex", "cormex", "legmex");
		const float mexCost = mexDef is null ? 0.f : Economist::MetalValue(mexDef);
		const float cross = AiTerrainDiagonal() / AiMax(1.f, speed);
		for (uint i = 0; i < ns2; ++i) {
			if (!mso[i] || Assess::OnOurSide(msp[i])) continue;
			const int c = Intel::CellOf(msp[i]);
			const float age = float(ai.frame - lastSeen[c]) / SECOND;
			raidable[c] += mexCost * AiMin(1.f, age / AiMax(1.f, cross));
		}
	}
	// our army's centre: where the response comes from
	float axs = 0.f, azs = 0.f, aw = 0.f;
	for (uint i = 0; i < all.length(); ++i) {
		const CCircuitDef@ d = all[i].circuitDef;
		if (!d.IsMobile() || d.power <= 0.f || d.IsRoleAny(Unit::Role::BUILDER.mask)) continue;
		const AIFloat3 q = all[i].GetPos(ai.frame); axs += q.x * d.power; azs += q.z * d.power; aw += d.power;
	}
	const AIFloat3 armyAt = aw > 0.f ? AIFloat3(axs / aw, 0.f, azs / aw) : (HasBase() ? basePos : Intel::CellCenter(0));
	const float ourSpeed = AiMax(1.f, Director::allSpeed);
	array<float> tr(assets.length());
	for (uint k = 0; k < assets.length(); ++k)
		tr[k] = AiMax(1.f, armyAt.distance2D(Intel::CellCenter(assets[k])) / ourSpeed);
	array<array<float>> watched(assets.length());  // per asset: angles of the picks watching it
	array<AIFloat3> tp; array<float> tv;
	topValue = 0.f; worthy = 0;
	const float scoutCost = cheapest is null ? 1e9f : Economist::MetalValue(cheapest);
	array<bool> picked(n, false);
	for (uint pick = 0; pick < uint(n); ++pick) {
		int best = -1; float bestV = 0.f;
		for (int c = 0; c < n; ++c) {
			if (picked[c]) continue;
			const AIFloat3 cc = Intel::CellCenter(c);
			const float age = float(ai.frame - lastSeen[c]) / SECOND;
			if (age <= 0.f && dots[c] <= 0.f) continue;
			if (covered[c]) continue;  // a known turret holds it: a scout dies there before it learns anything new
			float v = dots[c] * meanCost + raidable[c];
			for (uint k = 0; k < assets.length(); ++k) {
				const AIFloat3 ac = Intel::CellCenter(assets[k]);
				const float d = AiMax(1.f, cc.distance2D(ac));
				const float warn = AiMin(d / speed, tr[k]) / tr[k];
				const float stale = AiMin(1.f, age * speed / d);
				float dir = 1.f;
				const float ang = atan2(cc.z - ac.z, cc.x - ac.x);
				for (uint w = 0; w < watched[k].length(); ++w) {
					float da = AiMax(ang - watched[k][w], watched[k][w] - ang);
					if (da > Pi()) da = 2.f * Pi() - da;
					dir = AiMin(dir, da / Pi());
				}
				v += ours[assets[k]] * warn * stale * dir;
			}
			if (v > bestV) { bestV = v; best = c; }
		}
		if (best < 0 || bestV <= scoutCost) break;
		picked[best] = true;
		value[best] = bestV;
		if (bestV > topValue) topValue = bestV;
		++worthy;
		const AIFloat3 bc = Intel::CellCenter(best);
		tp.insertLast(bc); tv.insertLast(bestV);
		for (uint k = 0; k < assets.length(); ++k) {
			const AIFloat3 ac = Intel::CellCenter(assets[k]);
			watched[k].insertLast(atan2(bc.z - ac.z, bc.x - ac.x));
		}
	}
	aiMilitaryMgr.SetScoutTargets(tp, tv);
	picks = tp; pickVals = tv;  // in value order (each pick was the best left)
	// the chance a dark cell holds an enemy: their mobile units out of our sight (at least their commander) spread
	// over the cells we can't see
	{
		uint hidden = 0, dark = 0;
		for (uint i = 0; i < ne; ++i)
			if (ed[i] !is null && ed[i].IsMobile() && (ef[i] & 1) == 0) ++hidden;
		for (int c = 0; c < n; ++c) if (lastSeen[c] != ai.frame) ++dark;
		pOccupied = AiMin(1.f, float(AiMax(1, int(hidden))) / float(AiMax(1, int(dark))));
	}
	Send();
}
// The scouts Production bought for their information (not for a fight): each goes to the most valuable cell no
// other scout is on, the nearest scout first. Command leaves them alone.
array<AIFloat3> picks; array<float> pickVals;
float pOccupied = 0.f;
array<CCircuitUnit@> scouts;
array<int> pendingDefs;  // def ids ordered as scouts, not yet finished
dictionary sentTo;       // scout id -> the cell it was sent to
bool IsScout(CCircuitUnit@ u) { return scouts.findByRef(u) >= 0; }
// what one more scout is worth: the next cell no scout covers, for the share of it its sight covers
float NextValue(const CCircuitDef@ d)
{
	const uint k = scouts.length() + pendingDefs.length();
	if (k >= pickVals.length()) return 0.f;
	// worth only as much as there is something to find: the chance an enemy is in the cell (66 Fleas were bought on
	// the value of what could be there, Eye of Horus 2026-11-25)
	// ...and only if it lives to get there: the measured life of our scouts against its walk to the cell
	const float walk = (HasBase() ? basePos.distance2D(picks[k]) : 0.f) / AiMax(1.f, d.speed);
	const float alive = AiMax(0.f, 1.f - walk / AiMax(1.f, Life()));
	return pickVals[k] * pOccupied * alive * CellSurvival(picks[k]) * AiMin(1.f, 2.f * d.losRadius / AiMax(1.f, Intel::CELL));
}
void OnFinished(CCircuitUnit@ u)
{
	const int at = pendingDefs.find(u.circuitDef.id);
	if (at < 0) return;
	pendingDefs.removeAt(at);
	scouts.insertLast(u);
}
// per cell: scouts sent there and scouts killed on the way (before it was in their sight) - 16 of 39 Fleas died to
// light lasers around the same enemy cells, each new one valued at the global life (Canis vs Cortex, cmd_m26)
dictionary cellSent, cellDied;
void OnDestroyed(CCircuitUnit@ u)
{
	const int at = scouts.findByRef(u);
	if (at < 0) return;
	string key;
	if (sentTo.get("" + u.id, key)) {
		const array<string>@ xz = key.split(",");
		const AIFloat3 c(parseFloat(xz[0]), 0.f, parseFloat(xz[1]));
		if (u.GetPos(ai.frame).distance2D(c) > u.circuitDef.losRadius) {
			int n = 0; if (!cellDied.get(key, n)) n = 0; cellDied.set(key, n + 1);
		}
	}
	scouts.removeAt(at); ++lost;
}
float CellSurvival(const AIFloat3& in c)
{
	const string key = int(c.x) + "," + int(c.z);
	// a missing key leaves the out value undefined (it read the cell's z: sent = died = 2800, survival 0, no scout ever
	// built - sc2): only a found key counts
	int sent = 0, died = 0;
	if (!cellSent.get(key, sent)) sent = 0;
	if (!cellDied.get(key, died)) died = 0;
	return (sent > 0) ? AiMax(0.f, float(sent - died) / float(sent)) : 1.f;
}
// how long our scouts live: scout-seconds survived / scouts lost (none lost yet: the horizon)
float exposure = 0.f; int lost = 0; int lifeFrame = -1;
float Life()
{
	if (lifeFrame >= 0) exposure += float(scouts.length()) * float(ai.frame - lifeFrame) / SECOND;
	lifeFrame = ai.frame;
	return (lost > 0) ? exposure / float(lost) : Economist::Horizon();
}
void Send()
{
	array<bool> used(scouts.length(), false);
	for (uint p = 0; p < picks.length(); ++p) {
		int best = -1; float bd = 1e30f;
		for (uint i = 0; i < scouts.length(); ++i) {
			if (used[i]) continue;
			const float d = scouts[i].GetPos(ai.frame).distance2D(picks[p]);
			if (d < bd) { bd = d; best = int(i); }
		}
		if (best < 0) break;
		used[best] = true;
		const string key = int(picks[p].x) + "," + int(picks[p].z);
		string prev;
		if (sentTo.get("" + scouts[best].id, prev) && prev == key) continue;  // already on its way there
		sentTo.set("" + scouts[best].id, key);
		{ int n = 0; if (!cellSent.get(key, n)) n = 0; cellSent.set(key, n + 1); }
		scouts[best].CmdMoveTo(picks[p]);
	}
}

string Status()
{
	string f = "";
	const uint k = scouts.length() + pendingDefs.length();
	CCircuitDef@ d = ai.GetCircuitDef("armflea");
	if (d is null) @d = ai.GetCircuitDef("corfav");
	if (d !is null && k < pickVals.length()) {
		const float walk = (HasBase() ? basePos.distance2D(picks[k]) : 0.f) / AiMax(1.f, d.speed);
		f = " next: val " + int(pickVals[k]) + " pOcc " + F2(pOccupied) + " alive " + F2(AiMax(0.f, 1.f - walk / AiMax(1.f, Life())))
			+ " (walk " + int(walk) + " s, life " + int(Life()) + " s) cellSurv " + F2(CellSurvival(picks[k]))
			+ " los " + F2(AiMin(1.f, 2.f * d.losRadius / AiMax(1.f, Intel::CELL)));
	}
	return "scout: worthy=" + worthy + " top=" + int(topValue) + " scouts=" + scouts.length() + f;
}

}  // namespace Scout

/* ======================================================================== */
// (Hold, the just-in-time extractor defence built on BARb defend tasks, was removed with BARb's army handling: Command
// defends what enemies threaten through OursThreatened.)


namespace Recycler {

array<CCircuitDef@> lowEnergyDefs;   // solar / wind / tidal
array<CCircuitDef@> midEnergyDefs;   // advanced solar
array<CCircuitDef@> bigEnergyDefs;   // fusion-tier + geo
array<CCircuitDef@> afusDefs;
array<CCircuitDef@> lowMakerDefs;
array<CCircuitDef@> highMakerDefs;

array<CCircuitUnit@> lowEnergy;
array<CCircuitUnit@> midEnergy;
array<CCircuitUnit@> bigEnergy;
array<CCircuitUnit@> lowMakers;
array<CCircuitUnit@> highMakers;

array<CCircuitUnit@> pending;
array<int> pendingFrame;
array<int> origMax;  // per def id; -1 = not retired
int reclaimedCount = 0;


void Init()
{
	lowEnergyDefs = Defs({"armsolar", "corsolar", "legsolar", "armwin", "corwin", "legwin",
		"armtide", "cortide", "legtide"});
	midEnergyDefs = Defs({"armadvsol", "coradvsol", "legadvsol"});
	bigEnergyDefs = Defs({"armfus", "corfus", "legfus", "armckfus", "armuwfus", "coruwfus",
		"armafus", "corafus", "legafus", "armgeo", "corgeo", "leggeo", "armageo", "corageo", "legageo",
		"armgmm"});
	afusDefs = Defs({"armafus", "corafus", "legafus"});
	lowMakerDefs = Defs({"armmakr", "cormakr", "legeconv", "armfmkr", "corfmkr", "legfeconv"});
	highMakerDefs = Defs({"armmmkr", "cormmkr", "legadveconv", "armuwmmm", "coruwmmm"});
	origMax.resize(ai.GetDefCount() + 1);
	for (uint i = 0; i < origMax.length(); ++i)
		origMax[i] = -1;
}

void OnFinished(CCircuitUnit@ unit)
{
	const CCircuitDef@ d = unit.circuitDef;
	if (InList(lowEnergyDefs, d))       lowEnergy.insertLast(unit);
	else if (InList(midEnergyDefs, d))  midEnergy.insertLast(unit);
	else if (InList(bigEnergyDefs, d))  bigEnergy.insertLast(unit);
	else if (InList(lowMakerDefs, d))   lowMakers.insertLast(unit);
	else if (InList(highMakerDefs, d))  highMakers.insertLast(unit);
}

// Returns true if the unit was one we were reclaiming (so it doesn't count as a combat loss).
bool OnDestroyed(CCircuitUnit@ unit)
{
	RemoveUnit(lowEnergy, unit);
	RemoveUnit(midEnergy, unit);
	RemoveUnit(bigEnergy, unit);
	RemoveUnit(lowMakers, unit);
	RemoveUnit(highMakers, unit);
	int s = salvagePending.findByRef(unit);
	if (s >= 0) {
		salvagePending.removeAt(s);
		++salvaged;
	}
	int idx = pending.findByRef(unit);
	if (idx >= 0) {
		pending.removeAt(idx);
		pendingFrame.removeAt(idx);
		++reclaimedCount;
		return true;
	}
	return false;
}

float EnergyMake(const CCircuitDef@ d)
{
	// what it really makes on this map: fixed make, tidal at the map's tidal strength, wind at the map's average wind
	return AiEnergyMake(ai.GetCircuitDef(d.id));  // the bridge takes a non-const def handle
}

float BigMake()
{
	float sum = 0.f;
	for (uint i = 0; i < bigEnergy.length(); ++i)
		sum += EnergyMake(bigEnergy[i].circuitDef);
	return sum;
}

int AfusCount()
{
	int n = 0;
	for (uint i = 0; i < bigEnergy.length(); ++i) {
		if (InList(afusDefs, bigEnergy[i].circuitDef))
			++n;
	}
	return n;
}

/*
 * Obsolete T1 units. Late in the game cheap T1 units idling at home are worth more as metal for
 * T2/T3 production. We take the unit out of the core's control (so it stands still), reclaim it,
 * and hand it back if the reclaim times out.
 */
int advFactories = 0;
int lastSalvageFrame = 0;
int salvaged = 0;
array<CCircuitUnit@> salvagePending;

// Obsolete: a combat unit at home, out of fire, that fights worse per metal than the best unit our factories can build
// now. Reclaiming returns its metal for a better unit (no hand-written T1 list, no 1200-elmo ring).
float bestBuildablePerMetal = 0.f;
/*
 * Obsolete = outclassed by a higher tech: a factory of a higher tier we own builds something with more power per
 * metal. (Against the single best unit on the field everything else counted as obsolete, and the Recycler
 * reclaimed Thuds fresh off the line: smoke 2026-11-25.) A unit's tier is the lowest tier of the factories that
 * build it (Facts, build depth from the commanders).
 */
array<float> bestPerMetalByTier;
dictionary unitTierCache;
int UnitTier(const string& in name)
{
	double c = 0;
	if (unitTierCache.get(name, c)) return int(c);
	int t = 0;
	const array<string>@ keys = Facts::buildOptions.getKeys();
	for (uint i = 0; i < keys.length(); ++i) {
		const int tf = int(Facts::FactoryTier(keys[i]));
		if (tf <= 0 || (t > 0 && tf >= t)) continue;
		if (Facts::BuildOptions(keys[i]).find(name) >= 0) t = tf;
	}
	unitTierCache.set(name, double(t));
	return t;
}
void MeasureBestBuildable()
{
	bestPerMetalByTier.resize(0);
	const array<CCircuitUnit@>@ facs = Brain::Intel::allFactories;
	for (uint i = 0; i < facs.length(); ++i) {
		const int tf = int(Facts::FactoryTier(facs[i].circuitDef.GetName()));
		if (tf <= 0) continue;
		if (int(bestPerMetalByTier.length()) <= tf) {
			const uint old = bestPerMetalByTier.length();
			bestPerMetalByTier.resize(tf + 1);
			for (uint k = old; k < bestPerMetalByTier.length(); ++k) bestPerMetalByTier[k] = 0.f;
		}
		const array<string> opts = Facts::BuildOptions(facs[i].circuitDef.GetName());
		for (uint k = 0; k < opts.length(); ++k) {
			CCircuitDef@ d = ai.GetCircuitDef(opts[k]);
			if (d is null || !d.IsMobile() || d.costM <= 0.f || !d.IsAvailable(ai.frame)) continue;
			bestPerMetalByTier[tf] = AiMax(bestPerMetalByTier[tf], d.power / d.costM);
		}
	}
}
bool IsObsoleteT1(CCircuitUnit@ u)
{
	const CCircuitDef@ d = u.circuitDef;
	if (!d.IsMobile() || d.power <= 0.f || d.costM <= 0.f || d.IsRoleAny(Unit::Role::BUILDER.mask) || u is commander)
		return false;
	const AIFloat3 p = u.GetPos(ai.frame);
	if (!Brain::Assess::OnOurSide(p) || aiThreat.GetThreatAt(u, p) > 0.f)
		return false;
	const int tu = AiMax(1, UnitTier(d.GetName()));
	for (uint t = uint(tu) + 1; t < bestPerMetalByTier.length(); ++t)
		if (bestPerMetalByTier[t] > d.power / d.costM)
			return true;
	return false;
}

/*
 * The best energy per metal a plant we can build right now makes: any of our constructors (or the commander) can
 * build it. A standing plant is only worth reclaiming when it is worse than that: its metal rebuilds more energy.
 */
float BestPlantPerMetal()
{
	array<CCircuitDef@> plants;
	for (uint i = 0; i < lowEnergyDefs.length(); ++i) plants.insertLast(lowEnergyDefs[i]);
	for (uint i = 0; i < midEnergyDefs.length(); ++i) plants.insertLast(midEnergyDefs[i]);
	for (uint i = 0; i < bigEnergyDefs.length(); ++i) plants.insertLast(bigEnergyDefs[i]);
	array<const CCircuitDef@> builders;
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	for (uint i = 0; i < all.length(); ++i) {
		const CCircuitDef@ d = all[i].circuitDef;
		if (!d.IsMobile() || !d.IsRoleAny(Unit::Role::BUILDER.mask | Unit::Role::COMM.mask)) continue;
		if (builders.findByRef(d) < 0) builders.insertLast(d);
	}
	float best = 0.f;
	for (uint i = 0; i < plants.length(); ++i) {
		CCircuitDef@ pd = plants[i];
		if (pd is null || pd.costM <= 0.f || !pd.IsAvailable(ai.frame)) continue;
		if (Facts::NeedsGeo(pd.GetName()) > 0.f) continue;  // bound to a vent: it can't stand where it would replace one
		bool can = false;
		for (uint b = 0; b < builders.length() && !can; ++b) can = builders[b].CanBuild(pd);
		if (!can) continue;
		best = AiMax(best, AiEnergyMake(pd) / pd.costM);
	}
	return best;
}

void Salvage()
{
	// obsolete once we have advanced labs; the metal must fit (Reclaim checks), no clock or income bar
	// one salvage at a time (its reclaim must finish first); no clock, no tier gate
	if (salvagePending.length() > 0)
		return;
	MeasureBestBuildable();
	array<CCircuitUnit@>@ pools = Brain::Army::raiders;
	CCircuitUnit@ cand = null;
	for (uint i = 0; i < pools.length() && cand is null; ++i) {
		if (IsObsoleteT1(pools[i]) && pending.findByRef(pools[i]) < 0)
			@cand = pools[i];
	}
	for (uint i = 0; i < Brain::Army::ground.length() && cand is null; ++i) {
		if (IsObsoleteT1(Brain::Army::ground[i]) && pending.findByRef(Brain::Army::ground[i]) < 0)
			@cand = Brain::Army::ground[i];
	}
	for (uint i = 0; i < Brain::Army::scouts.length() && cand is null; ++i) {
		CCircuitUnit@ u = Brain::Army::scouts[i];
		if (IsObsoleteT1(u) && pending.findByRef(u) < 0 && Brain::Army::scouts.length() > aiMilitaryMgr.quota.scout)
			@cand = u;
	}
	if (cand is null)
		return;
	lastSalvageFrame = ai.frame;
	ai.UnitControl(cand, false);
	salvagePending.insertLast(cand);
	Reclaim(cand);
	AiLog("[ANV] Recycler: salvaging obsolete " + cand.circuitDef.GetName());
}

void Retire(const CCircuitDef@ cd)
{
	CCircuitDef@ d = ai.GetCircuitDef(cd.id);
	if (origMax[d.id] < 0) {
		origMax[d.id] = d.maxThisUnit;
		d.maxThisUnit = 0;  // core economy must not rebuild what we're recycling
		AiLog("[ANV] Recycler: retiring " + d.GetName());
	}
}

void RestoreAll()
{
	for (uint i = 0; i < origMax.length(); ++i) {
		if (origMax[i] >= 0) {
			CCircuitDef@ d = ai.GetCircuitDef(Id(i));
			if (d !is null) {
				d.maxThisUnit = origMax[i];
				AiLog("[ANV] Recycler: un-retiring " + d.GetName() + " (energy stall)");
			}
			origMax[i] = -1;
		}
	}
}

void PrunePending()
{
	for (int i = int(pending.length()) - 1; i >= 0; --i) {
		if (ai.frame - pendingFrame[i] > ReclaimLife(pending[i].circuitDef.costM, pending[i].GetPos(ai.frame))) {
			int s = salvagePending.findByRef(pending[i]);
			if (s >= 0) {
				ai.UnitControl(pending[i], true);  // give the unit back
				salvagePending.removeAt(s);
			}
			pending.removeAt(i);  // task timed out; unit may be retried later
			pendingFrame.removeAt(i);
		}
	}
}

// Pick the candidate farthest from base: outlying fields are the most exposed and the least useful.
CCircuitUnit@ PickCandidate(const array<CCircuitUnit@>& in list)
{
	CCircuitUnit@ best = null;
	float bestDist = -1.f;
	for (uint i = 0; i < list.length(); ++i) {
		CCircuitUnit@ u = list[i];
		if (pending.findByRef(u) >= 0)
			continue;
		float dist = HasBase() ? basePos.distance2D(u.GetPos(ai.frame)) : float(i);
		if (dist > bestDist) {
			bestDist = dist;
			@best = u;
		}
	}
	return best;
}

void Reclaim(CCircuitUnit@ u)
{
	// Metal that comes back into full storage is thrown away: only start when it fits (else ask for storage)
	if (!Brain::Storage::Fits(u.circuitDef.costM)) {
		Brain::Storage::Block(u.circuitDef.costM);
		return;
	}
	aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::HIGH, u, ReclaimLife(u.circuitDef.costM, u.GetPos(ai.frame))));
	pending.insertLast(u);
	pendingFrame.insertLast(ai.frame);
}


/*
 * Energy plants by value (owner: never consumed a fusion to fund the AFUS, never reclaimed advanced solars; the
 * Recycler's fixed gates - big plants >= 60% of income, storage > 50%, surplus > max(8% income, 40) - never held
 * while converters pulled the energy). Keeping a plant is worth its energy until the horizon at the converter price
 * (make x horizon / energy-per-metal); reclaiming it is worth its metal now, which funds what we are building. The
 * plant with the largest positive difference is reclaimed, if its loss doesn't run energy dry before a new plant
 * could be built and the metal fits in storage.
 */
int ecoReclaims = 0;
void EcoReclaimUpdate()
{
	const SResourceInfo@ e = aiEconomyMgr.energy;
	const float epm = AiMax(1e-3f, Brain::Economist::energyPerMetal);
	const float H = Brain::Economist::Horizon();
	const float bestPlant = BestPlantPerMetal();
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	CCircuitUnit@ best = null; float bestGain = 0.f, bestMake = 0.f;
	for (uint i = 0; i < all.length(); ++i) {
		CCircuitUnit@ u = all[i];
		const CCircuitDef@ d = u.circuitDef;
		if (d.IsMobile() || pending.findByRef(u) >= 0) continue;
		const float make = AiEnergyMake(ai.GetCircuitDef(d.id));
		if (make <= 0.f || make / AiMax(1e-3f, d.costM) >= bestPlant) continue;  // not outclassed: keep it
		// the metal back is worth the share of our metal we actually spend (as the builders price it): counted in full
		// with 580 banked, new turbines were reclaimed at 2:29 and rebuilt and reclaimed again (Canis, cmd_m20)
		const float gain = d.costM * Brain::Economist::MetalShare() - make * H / epm;
		if (gain > bestGain) { bestGain = gain; @best = u; bestMake = make; }
	}
	if (best is null) return;
	// The converter price is what SURPLUS energy is worth. Without the plant, energy must still be in surplus (income
	// covers the pull); otherwise its energy is what lets our metal be spent at all, worth far more than a converter
	// pays, and reclaiming it starves the build (smoke 2026-11-25: wind built, reclaimed, stalled, rebuilt).
	const float net = e.income - bestMake - Brain::Economist::RealPull();  // converters' draw is surplus, not need
	if (net < 0.f) return;
	if (!Brain::Storage::Fits(best.circuitDef.costM)) { Brain::Storage::Block(best.circuitDef.costM); return; }
	++ecoReclaims;
	AiLog("[ANV] EcoReclaim: " + best.circuitDef.GetName() + " (metal " + int(best.circuitDef.costM) + " now vs its energy "
		+ int(bestMake * H / epm) + " metal-eq over " + int(H) + " s)");
	Reclaim(best);
}


/*
 * Idle caretakers (owner: old nano turrets left unused in the middle of the base). A caretaker is worth the build
 * power it actually applies: its share of our build power x our income x the horizon x its utilisation. Utilisation
 * is a moving average of busy (on a builder task) vs idle, averaged over the planning horizon itself. Reclaiming it
 * returns its metal now; that wins once the nano stands where nothing is being built any more.
 */
dictionary nanoUse;   // unit id -> utilisation 0..1
int nanoLastFrame = 0, nanoReclaims = 0;
void NanoUpdate()
{
	const float dt = float(ai.frame - nanoLastFrame) / SECOND;
	nanoLastFrame = ai.frame;
	const float H = AiMax(1.f, Brain::Economist::Horizon());
	const float a = AiMin(1.f, dt / H);  // moving average over the horizon
	const float income = aiEconomyMgr.metal.income;
	const float bp = AiMax(1.f, aiBuilderMgr.GetBuildPower());
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	CCircuitUnit@ best = null; float bestGain = 0.f;
	for (uint i = 0; i < all.length(); ++i) {
		CCircuitUnit@ u = all[i];
		const CCircuitDef@ d = u.circuitDef;
		if (d.IsMobile() || d.buildSpeed <= 0.f || Brain::Intel::allFactories.findByRef(u) >= 0 || pending.findByRef(u) >= 0) continue;
		const string key = "" + u.id;
		const bool busy = (u.task !is null && u.task.GetType() == Task::Type::BUILDER);
		float use = 1.f;  // a new nano is presumed useful until measured
		if (!nanoUse.get(key, use)) use = 1.f;
		use = use + a * ((busy ? 1.f : 0.f) - use);
		nanoUse.set(key, use);
		const float keep = d.buildSpeed / bp * income * H * use;
		const float gain = d.costM - keep;
		if (gain > bestGain) { bestGain = gain; @best = u; }
	}
	if (best is null || !Brain::Storage::Fits(best.circuitDef.costM)) return;
	++nanoReclaims;
	AiLog("[ANV] Nanos: reclaiming idle " + best.circuitDef.GetName() + " (metal " + int(best.circuitDef.costM) + " > its use " + int(best.circuitDef.costM - bestGain) + ")");
	Reclaim(best);
}

void Update()
{
	PrunePending();

	const SResourceInfo@ e = aiEconomyMgr.energy;
	const float bigMake = BigMake();
	const float income = e.income;
	const float fill = (e.storage > 0.f) ? e.current / e.storage : 0.f;

	// Safety valve: energy stalls and the big plants no longer cover what we consume -> allow cheap energy again
	// (no 10% fill, 15 ticks or half-income lines)
	if (aiEconomyMgr.isEnergyStalling && bigMake < Brain::Economist::RealPull()) {
		RestoreAll();
		return;
	}

	if (pending.length() >= aiBuilderMgr.GetWorkerCount())  // one reclaim per constructor
		return;

	Salvage();

	// --- T1 metal makers once T2 makers carry conversion ---
	if (highMakers.length() > 0 && aiEconomyMgr.isEnergyFull) {  // T2 makers exist and energy still overflows: T1 makers add nothing
		CCircuitUnit@ cand = PickCandidate(lowMakers);
		if (cand !is null) {
			Retire(cand.circuitDef);
			Reclaim(cand);
		}
	}
}

string Status()
{
	return "lowE=" + lowEnergy.length() + " midE=" + midEnergy.length() + " bigE=" + bigEnergy.length()
		+ " bigMake=" + F1(BigMake()) + " lowMk=" + lowMakers.length() + " hiMk=" + highMakers.length()
		+ " pending=" + pending.length() + " reclaimed=" + reclaimedCount + " salvaged=" + salvaged + " afus=" + AfusCount();
}

}  // namespace Recycler

/* ======================================================================== */
namespace Intel {

float CELL = 1.f;  // set in Init: a camera's sight diameter (what the grid is for)
int gw = 1, gh = 1;
array<float> heat;
array<int> lastEyesFrame;   // per cell: when we last ordered vision there

array<CCircuitDef@> jammerDefs;
array<CCircuitDef@> eyesDefs;
CCircuitDef@ eyesDef = null;
array<CCircuitUnit@> eyes;
array<CCircuitUnit@> airFactories;
array<CCircuitUnit@> allFactories;

float jammerCost = 0.f;
bool jamAlert = false;
int eyesOrdered = 0;

void Init()
{
	{
		const string side0 = ai.GetSideName();
		CCircuitDef@ cam = (side0 == "cortex") ? Def("coreyes") : ((side0 == "legion") ? Def("legeyes") : Def("armeyes"));
		CCircuitDef@ com = (side0 == "cortex") ? Def("corcom") : ((side0 == "legion") ? Def("legcom") : Def("armcom"));
		if (cam !is null && cam.losRadius > 0.f) CELL = 2.f * cam.losRadius;
		else if (com !is null && com.losRadius > 0.f) CELL = 2.f * com.losRadius;  // no camera: our own sight
		else CELL = AiTerrainDiagonal();  // nothing sees: the map is one cell
	}
	gw = AiMax(1, int(AiTerrainWidth() / CELL) + 1);
	gh = AiMax(1, int(AiTerrainHeight() / CELL) + 1);
	heat.resize(gw * gh);
	lastEyesFrame.resize(gw * gh);
	for (uint i = 0; i < heat.length(); ++i) {
		heat[i] = 0.f;
		lastEyesFrame[i] = NEVER;
	}

	jammerDefs = Defs({"armjamt", "corjamt", "armveil", "corshroud", "armjam", "coreter", "armsjam", "corsjam",
		"armaser", "corspec", "armmlv", "cormlv", "legjam", "legajam", "legajamk", "legavjam",
		"leganavyradjamship", "legmlv"});
	eyesDefs = Defs({"armeyes", "coreyes", "legeyes"});
	const string side = ai.GetSideName();
	if (side == "cortex")       @eyesDef = Def("coreyes");
	else if (side == "legion")  @eyesDef = Def("legeyes");
	else                        @eyesDef = Def("armeyes");

}

/*
 * A jammer is only worth building if it hides something. When we see an enemy jammer, give it
 * the influence of a squad of same-tier units, so the core's attack logic treats its cluster as
 * defended: weak squads skip it, strong squads go in. Weaponless jammers only; own jammers have
 * "power": 0.01 in behaviour.json so this doesn't inflate our own squads.
 */
float RefInfluence(const array<string>& in names)
{
	array<CCircuitDef@> refs = Defs(names);
	float sum = 0.f;
	for (uint i = 0; i < refs.length(); ++i)
		sum += refs[i].defDmg * sqrt(refs[i].health);
	return (refs.length() > 0) ? sum / refs.length() : 0.f;
}

// A seen enemy jammer stands for hidden strength: its metal share of the enemy army we can see (live, no squad sizes)
void UpdatePhantomThreat()
{
	// nothing visible yet: assume they kept pace with us (the Director's blind prior)
	const float visible = (Brain::Economist::KnownEnemyThreat() > 0.f) ? Brain::Economist::KnownEnemyThreat() : Brain::Director::OurPower();
	for (uint i = 0; i < jammerDefs.length(); ++i) {
		CCircuitDef@ d = jammerDefs[i];
		if (d.defDmg > 0.f)
			continue;  // armed (e.g. commando): keep its real threat
		d.SetThreatKernel(visible * d.costM / AiMax(d.costM, jammerCost));
	}
}

int CellOf(const AIFloat3& in p)
{
	int x = AiMax(0, AiMin(gw - 1, int(p.x / CELL)));
	int z = AiMax(0, AiMin(gh - 1, int(p.z / CELL)));
	return z * gw + x;
}

AIFloat3 CellCenter(int c)
{
	return AIFloat3((c % gw + 0.5f) * CELL, 0.f, (c / gw + 0.5f) * CELL);
}

void OnLoss(CCircuitUnit@ unit)
{
	const CCircuitDef@ d = unit.circuitDef;
	// Unarmed structures also "die" when the core recycles them, so only count fighters,
	// builders and defences.
	if (!d.IsMobile() && d.defDmg <= 0.f)
		return;
	heat[CellOf(unit.GetPos(ai.frame))] += d.costM;
}

void OnFinished(CCircuitUnit@ unit)
{
	if (InList(eyesDefs, unit.circuitDef))
		eyes.insertLast(unit);
}


// Smoke test of the C++ bridge (enemy list, groups, terrain, threat, height-aware range).
void BridgeLog()
{
	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
	const uint n = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	float known = 0.f; uint los = 0;
	for (uint i = 0; i < n; ++i) { known += ec[i]; if ((ef[i] & 1) != 0) ++los; }
	array<AIFloat3> gp; array<float> gc, gt;
	const uint g = AiGetEnemyGroups(gp, gc, gt);
	float big = 0.f; AIFloat3 bigPos;
	for (uint i = 0; i < g; ++i) if (gc[i] > big) { big = gc[i]; bigPos = gp[i]; }
	string s = "[ANV] bridge enemies=" + n + " los=" + los + " knownM=" + int(known) + " groups=" + g
		+ " biggest=" + int(big) + "@(" + int(bigPos.x) + "," + int(bigPos.z) + ") own=" + AiGetTeamUnits().length()
		+ " elev[min,max]=" + int(AiMinElevation()) + "," + int(AiMaxElevation());
	if (HasBase()) s += " baseElev=" + int(AiGetElevation(basePos.x, basePos.z)) + " baseLOS=" + AiIsInLOS(basePos);
	array<AIFloat3> wp; array<float> wm; array<bool> wr;
	const uint w = AiGetWrecks(wp, wm, wr);
	float wreckM = 0.f; for (uint i = 0; i < w; ++i) wreckM += wm[i];
	float hurt = 0.f; uint building = 0; for (uint i = 0; i < n; ++i) { hurt += 1.f - eh[i]; if (eb[i] < 1.f) ++building; }
	s += " wrecks=" + w + " wreckM=" + int(wreckM) + " enemyHurt=" + F1(hurt) + " enemyBuilding=" + building;
	CCircuitDef@ arty = ai.GetCircuitDef("armmart");
	if (arty !is null) s += " mart range flat/+100/-100=" + int(arty.GetRangeAt(0)) + "/" + int(arty.GetRangeAt(-100)) + "/" + int(arty.GetRangeAt(100));
	if (commander !is null) s += " commThreat=" + F1(aiThreat.GetThreatAt(commander, commander.GetPos(ai.frame)));
	AiLog(s);
}

void OnDestroyed(CCircuitUnit@ unit)
{
	RemoveUnit(eyes, unit);
	RemoveUnit(airFactories, unit);
	RemoveUnit(allFactories, unit);
}

void OnFactory(CCircuitUnit@ unit)
{
	allFactories.insertLast(unit);
	CCircuitDef@ scout = aiFactoryMgr.GetRoleDef(unit.circuitDef, RT::SCOUT);
	if (scout !is null && scout.IsAbleToFly())
		airFactories.insertLast(unit);
}

bool EyesNear(const AIFloat3& in p, float radius)
{
	for (uint i = 0; i < eyes.length(); ++i) {
		if (eyes[i].GetPos(ai.frame).distance2D(p) < radius)
			return true;
	}
	return false;
}

void Update()
{
	// memory of losses on the planning horizon (as the trade estimate), no 0.995
	const float hDecay = pow(2.71828183f, -1.f / AiMax(1.f, Brain::Economist::Horizon()));
	for (uint i = 0; i < heat.length(); ++i)
		heat[i] *= hDecay;

	jammerCost = aiEnemyMgr.GetEnemyCost(RT::JAMMER);
	const bool wasAlert = jamAlert;
	jamAlert = jammerCost > 0.f;
	if (jamAlert != wasAlert)
		AiLog("[ANV] Intel: jammer alert " + (jamAlert ? "ON" : "OFF") + " (known jammer metal=" + F1(jammerCost) + ")");

	if (jamAlert)
		UpdatePhantomThreat();
	if (!HasBase())
		return;

	OrderVision();

	// scouting of jammed or dark areas is decided by vision value (Scout)
}

// Put a cheap long-sight camera where we keep dying. Under a jammer, sight is the only way to see.
// Cameras by value, no caps or clocks: the hottest cell we can't see, if the metal recently lost there beats a camera.
// Placed back toward our base by the camera's own sight radius, so it watches the cell from as far as it can see.
void OrderVision()
{
	if (eyesDef is null || !eyesDef.IsAvailable(ai.frame))
		return;
	const float cost = Brain::Economist::MetalValue(eyesDef);
	const float sight = AiMax(1.f, eyesDef.losRadius);
	int best = -1;
	float bestHeat = cost;
	for (uint c = 0; c < heat.length(); ++c) {
		// a cell whose camera order is still within its lifetime is already being served
		if (heat[c] > bestHeat && !AiIsInLOS(CellCenter(int(c))) && (lastEyesFrame[c] == NEVER || ai.frame - lastEyesFrame[c] >= OrderLife(eyesDef, CellCenter(int(c))))) {
			bestHeat = heat[c];
			best = int(c);
		}
	}
	if (best < 0)
		return;
	AIFloat3 hot = CellCenter(best);
	AIFloat3 dir = basePos - hot;
	dir.y = 0.f;
	const float len = dir.Length2D();
	if (len > 1.f)
		hot = hot + dir * (AiMin(sight, len) / len);
	if (EyesNear(hot, sight))
		return;
	lastEyesFrame[best] = ai.frame;
	aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE, Task::Priority::NORMAL, eyesDef, hot,
		0.f, true, OrderLife(eyesDef, hot)));
	++eyesOrdered;
	AiLog("[ANV] Intel: vision ordered at (" + int(hot.x) + "," + int(hot.z) + ") heat=" + F1(bestHeat) + " > camera " + int(cost));
}

float MaxHeat()
{
	float m = 0.f;
	for (uint i = 0; i < heat.length(); ++i)
		m = AiMax(m, heat[i]);
	return m;
}

}  // namespace Intel

/* ======================================================================== */
/*
 * Strategic structures the core never builds on its own (they sit past the end of its defence
 * order or are commented out of its superweapon list): Juno, anti-nuke, tactical/EMP launcher,
 * nuke silo, and shields placed over our most valuable infrastructure.
 * Firing is handled by the core's super-weapon tasks ("super" role in behaviour.json).
 */
namespace Strategic {

CCircuitDef@ junoDef, amdDef, tacDef, siloDef, shieldDef;
array<CCircuitDef@> junoDefs, amdDefs, tacDefs, siloDefs, shieldDefs;
array<CCircuitUnit@> junos, amds, tacs, silos, shields, infra;
enum OrderKind { ORDER_JUNO, ORDER_AMD, ORDER_TAC, ORDER_SILO, ORDER_SHIELD, ORDER_KINDS }
array<int> lastOrder(uint(ORDER_KINDS), NEVER);
array<int> lastLife(uint(ORDER_KINDS), 0);  // each kind's last order lifetime (OrderLife)  // juno, amd, tac, silo, shield
int orders = 0;

float ShieldRadius() { return shieldDef is null ? 0.f : Facts::ShieldRadius(shieldDef.GetName()); }  // unit facts

CCircuitDef@ Side(const string& in arm, const string& in cor, const string& in leg)
{
	const string side = ai.GetSideName();
	return Def(side == "cortex" ? cor : (side == "legion" ? leg : arm));
}

void Init()
{
	@junoDef   = Side("armjuno", "corjuno", "legjuno");
	@amdDef    = Side("armamd", "corfmd", "legabm");
	@tacDef    = Side("armemp", "cortron", "legperdition");
	@siloDef   = Side("armsilo", "corsilo", "legsilo");
	@shieldDef = Side("armgate", "corgate", "legdeflector");
	junoDefs   = Defs({"armjuno", "corjuno", "legjuno"});
	amdDefs    = Defs({"armamd", "corfmd", "legabm"});
	tacDefs    = Defs({"armemp", "cortron", "legperdition"});
	siloDefs   = Defs({"armsilo", "corsilo", "legsilo"});
	shieldDefs = Defs({"armgate", "corgate", "legdeflector"});
	InitFortify();
}

/*
 * Nuke risk, as an expected loss. A launch from an unseen silo leaves seconds, so the only defence that
 * works is an anti-nuke already standing with an interceptor stockpiled. Readiness takes
 *   L = anti-nuke build time at the build power we can put on it + its interceptor stockpile time.
 * By now + L, could an enemy have a missile? The metal they could have put into silo + missile since
 * they could reach T2 (parity: when we did; we can't see theirs), over what silo + missile cost, capped
 * at 1; a seen silo makes it 1. Worth it when that feasibility x the metal at risk in our base (what a
 * nuke would erase) >= the anti-nuke's cost. Returns feasibility x risk / cost (>= 1: build).
 * Game facts (unit files): anti-nuke 60000 build time, 90 s stockpile; silo ~8000 M + missile, 120-180 s.
 */
int ourT2Frame = -1;
float InfraValue()
{
	float v = 0.f;
	for (uint i = 0; i < infra.length(); ++i)
		v += infra[i].circuitDef.costM;
	return v;
}
float NukeRisk()
{
	if (amdDef is null || siloDef is null)
		return 0.f;
	// time to have an anti-nuke up: its build time at our measured build power + its stockpile time (unit facts)
	const float L = amdDef.buildTime / AiMax(1.f, aiBuilderMgr.GetBuildPower()) + Facts::StockpileTime(amdDef.GetName());
	float feasible = 1.f;
	if (aiEnemyMgr.GetEnemyCost(RT::NUKE) <= 0.f) {
		if (ourT2Frame < 0)
			return 0.f;  // nobody near T2 yet (parity): a silo is out of reach
		// A silo takes long and stands in their base: seen without one, the earliest missile is that sighting + the silo's
		// build (at our build power, parity) + its stockpile. Our anti-nuke waits while it would still stand before then.
		// (On affordability alone the T2 constructors took anti-nuke jobs at 13 min against no nuke, t2g; #100.)
		const int cell = Intel::CellOf(AiEnemyBasePos());
		if (cell >= 0 && cell < int(Scout::lastSeen.length()) && Scout::lastSeen[cell] > 0) {
			const float tSilo = float(Scout::lastSeen[cell]) / SECOND + siloDef.buildTime / AiMax(1.f, aiBuilderMgr.GetBuildPower())
				+ Facts::StockpileTime(siloDef.GetName());
			if (float(ai.frame) / SECOND + L < tSilo) return 0.f;
		}
		const float since = float(ai.frame - ourT2Frame) / SECOND + L;
		// each enemy earns about what we do (parity prior; scouted BARbs out-earn us, so it's a floor)
		const float enemyMetal = float(AiMax(1, ai.GetEnemyTeamSize())) * aiEconomyMgr.metal.income * since;
		feasible = AiMin(1.f, enemyMetal / (siloDef.costM + Facts::ShotMetal(siloDef.GetName())) - Facts::StockpileTime(siloDef.GetName()) / AiMax(1.f, since));
		if (feasible <= 0.f)
			return 0.f;
	}
	return feasible * InfraValue() / AiMax(1.f, Brain::Economist::MetalValue(amdDef));
}

void OnFinished(CCircuitUnit@ u)
{
	const CCircuitDef@ d = u.circuitDef;
	if (InList(junoDefs, d))        junos.insertLast(u);
	else if (InList(amdDefs, d))    amds.insertLast(u);
	else if (InList(tacDefs, d))    tacs.insertLast(u);
	else if (InList(siloDefs, d))   silos.insertLast(u);
	else if (InList(shieldDefs, d)) shields.insertLast(u);
	if (!d.IsMobile() && !InList(shieldDefs, d))  // every structure at its metal value; the protection value sums decide
		infra.insertLast(u);
}

void OnDestroyed(CCircuitUnit@ u)
{
	RemoveUnit(junos, u); RemoveUnit(amds, u); RemoveUnit(tacs, u);
	RemoveUnit(silos, u); RemoveUnit(shields, u); RemoveUnit(infra, u);
}

// No cooldown clock: a kind is ready when no order of it is still outstanding (one more exists, or the build task
// we queued has expired at its own lifetime, ORDER_LIFE, set where it is enqueued).

array<int> countAtOrder(uint(ORDER_KINDS), -1);
bool Ready(int kind, CCircuitDef@ d)
{
	if (d is null || !d.IsAvailable(ai.frame)) return false;
	return countAtOrder[kind] < 0 || d.count > countAtOrder[kind] || ai.frame - lastOrder[kind] > lastLife[kind];
}

void Order(int kind, CCircuitDef@ d, const AIFloat3& in pos, Task::Priority pri, float shake)
{
	lastOrder[kind] = ai.frame;
	countAtOrder[kind] = d.count;
	++orders;
	lastLife[kind] = OrderLife(d, pos);
	aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::BIG_GUN, pri, d, pos, shake, true, lastLife[kind]));
	AiLog("[ANV] Strategic: ordering " + d.GetName() + " at (" + int(pos.x) + "," + int(pos.z) + ")");
}

// Toward the map centre: tactical launchers have 2250-3650 range and must sit forward.

// Where a launcher of this reach covers the enemy's structures (their centre, or the mirror of our base when none are
// known) while staying on our half of the way
AIFloat3 ReachPos(const CCircuitDef@ d)
{
	AIFloat3 target = AiTerrainCenter() * 2.f - basePos;
	const array<AIFloat3>@ es = Brain::Assess::enemyStatics;
	if (es.length() > 0) {
		target = AIFloat3(0.f, 0.f, 0.f);
		for (uint i = 0; i < es.length(); ++i) target = target + es[i];
		target = target / float(es.length());
	}
	AIFloat3 dir = target - basePos;
	dir.y = 0.f;
	const float len = dir.Length2D();
	if (len < 1.f)
		return basePos;
	const float along = AiMin(AiMax(0.f, len - d.GetMaxRange()), len * 0.5f);
	return basePos + dir * (along / len);
}

// Most valuable spot not yet under a shield: sum of infra cost within the shield radius.
bool BestShieldSpot(AIFloat3& out pos, float& out value)
{
	value = 0.f;
	for (uint i = 0; i < infra.length(); ++i) {
		const AIFloat3 p = infra[i].GetPos(ai.frame);
		bool covered = false;
		for (uint s = 0; s < shields.length() && !covered; ++s)
			covered = shields[s].GetPos(ai.frame).distance2D(p) < ShieldRadius();  // inside the shield = covered
		if (covered)
			continue;
		float v = 0.f;
		for (uint j = 0; j < infra.length(); ++j) {
			if (infra[j].GetPos(ai.frame).distance2D(p) < ShieldRadius())
				v += infra[j].circuitDef.costM;
		}
		if (v > value) {
			value = v;
			pos = p;
		}
	}
	return value > 0.f;
}

void Update(bool jamAlert)
{
	if (!HasBase())
		return;
	Fortify();
	const float m = aiEconomyMgr.metal.income;
	const float e = aiEconomyMgr.energy.income;
	const int minute = Minute();
	const bool enemyNuke = aiEnemyMgr.GetEnemyCost(RT::NUKE) > 0.f;

	// Anti-nuke: ready BEFORE the first missile could exist, because after a launch there is no time
	// to react (the missile lands in seconds). See NukeRisk().
	const uint wantAmd = (amds.length() == 0 && NukeRisk() >= 1.f) ? 1
		: ((enemyNuke && InfraValue() > 2.f * Brain::Economist::MetalValue(amdDef) * float(amds.length() + 1)) ? amds.length() + 1 : amds.length());
	if (amds.length() < wantAmd && Ready(ORDER_AMD, amdDef)) {
		Order(ORDER_AMD, amdDef, basePos, enemyNuke ? Task::Priority::NORMAL : Task::Priority::HIGH, 0.f);  // no scatter: the block map spaces by blast radius
		return;
	}
	// Juno: EMP missile that wipes radar, jammers and mines in its blast. Worth it when the enemy jammers it can wipe
	// are worth more than it (no game clock).
	if (jamAlert && junos.length() < 1 && Ready(ORDER_JUNO, junoDef)
		&& aiEnemyMgr.GetEnemyCost(RT::JAMMER) > Brain::Economist::MetalValue(junoDef)) {
		Order(ORDER_JUNO, junoDef, basePos, Task::Priority::HIGH, 0.f);  // no scatter: the block map spaces by blast radius
		return;
	}
	// Everything below is an investment that doesn't fight today: only when our army covers what we need.
	if (Brain::Director::ratio < 1.f)
		return;
	// Shields over the most valuable uncovered infrastructure: one more while what it would cover is worth more than
	// the shield (no clock, no energy level, no count formula, no fixed value floor).
	if (Ready(ORDER_SHIELD, shieldDef)) {
		AIFloat3 pos;
		float value;
		if (BestShieldSpot(pos, value) && value > Brain::Economist::MetalValue(shieldDef)) {
			Order(ORDER_SHIELD, shieldDef, pos, Task::Priority::NORMAL, 0.f);  // no scatter: the block map spaces by blast radius
			return;
		}
	}
	// Tactical / EMP launcher, forward of base: one more while the enemy's static metal exceeds what our launchers cost.
	const float enemyStatic = aiEnemyMgr.GetEnemyCost(RT::STATIC);
	if (tacDef !is null && Ready(ORDER_TAC, tacDef) && enemyStatic > Brain::Economist::MetalValue(tacDef) * float(tacs.length() + 1)) {
		Order(ORDER_TAC, tacDef, ReachPos(tacDef), Task::Priority::NORMAL, 0.f);  // no scatter: the block map spaces by blast radius
		return;
	}
	// Nuke: only under our own anti-nuke umbrella, while the enemy's static metal exceeds the silo.
	if (amds.length() >= 1 && silos.length() < 1 && siloDef !is null && Ready(ORDER_SILO, siloDef)
		&& enemyStatic > Brain::Economist::MetalValue(siloDef)) {
		Order(ORDER_SILO, siloDef, basePos, Task::Priority::NORMAL, 0.f);  // no scatter: the block map spaces by blast radius
		return;
	}
}

/*
 * Fortify: fight where the enemy has to come to us. The choke from the map analysis first (TerrainFortify);
 * otherwise the loss heatmap shows where fights happen and a turret covers the hottest cell (Fortify).
 */
CCircuitDef@ turT1, turT2, turT3, wallDef;
int lastFortify = 0, forts = 0;
IUnitTask@ fortPending = null;
void OnTaskRemoved(IUnitTask@ t) { if (t is fortPending) @fortPending = null; }
// terrain defence bookkeeping: build the next turret only once the last one stands AND something has
// come at us since (event-driven, no timer flood: one order per real attack)
int terrainBuilt = 0;
float terrainHit = 0.f, hitAtLastOrder = -1.f;
CCircuitDef@ terrainDef = null;
float armyMetal = 0.f;               // our armed mobile units (not builders), metal
float ownedMetal = 0.f;              // everything we own, metal
CCircuitDef@ mlvDef, mineDef;        // minelayer vehicle and its light land mine
int minelayers = 0, mlvOrderedAt = NEVER;
void OnTerrainLoss(const AIFloat3& in pos, float costM)
{
	MapFacts::SMap@ m = Brain::Production::mapInfo;
	if (myStart < 0 || m is null)
		return;
	const AIFloat3 high(m.hx[myStart], 0.f, m.hz[myStart]);
	const AIFloat3 choke(m.cx[myStart], 0.f, m.cz[myStart]);
	// a loss counts against the terrain spots when it falls within what a turret there would reach (no 900-elmo ring)
	CCircuitDef@ tur = BestTurret();
	const float reach = (tur is null) ? 0.f : tur.GetMaxRange();
	if (pos.distance2D(high) < reach || pos.distance2D(choke) < reach)
		terrainHit += costM;
}

void InitFortify()
{
	@turT1 = Side("armllt", "corllt", "leglht");
	@turT2 = Side("armhlt", "corhlt", "legmg");
	@turT3 = Side("armpb", "corvipe", "legbastion");
	@wallDef = Side("armdrag", "cordrag", "legdrag");
	@mlvDef = Side("armmlv", "cormlv", "legmlv");
	@mineDef = Side("armmine1", "cormine1", "legmine1");
}

/*
 * Terrain fortification: the choke on our side of the path to the enemy, and the highest ground
 * overlooking it (offline map analysis). Turrets on the high ground (reach, fire from above), teeth
 * across the choke mouth (attackers stall under fire). Done while we can't win an open fight
 * (power < needed) or whenever we're outnumbered (1vN), as long as the deficit lasts.
 */
int myStart = -2;
CCircuitDef@ BestTurret()
{
	array<CCircuitDef@> c = {turT1, turT2, turT3};
	CCircuitDef@ best = null;
	float bestV = 0.f;
	for (uint i = 0; i < c.length(); ++i) {
		if (c[i] is null || !c[i].IsAvailable(ai.frame))
			continue;
		const float v = c[i].power / AiMax(1.f, Brain::Economist::MetalValue(c[i]));
		if (best is null || v > bestV) { bestV = v; @best = c[i]; }
	}
	return best;
}
// Turret, camera and wall jobs go in the NORMAL band, below income (extractors, plants: HIGH). A defence only
// protects income, so it comes after the income it protects (smoke 2026-11-25: in one band the builders took 20 LLTs
// over 4 extractors).
bool TerrainFortify()
{
	MapFacts::SMap@ m = Brain::Production::mapInfo;
	if (m is null || m.hx.length() == 0 || !HasBase())
		return false;
	if (myStart == -2) {
		myStart = -1;
		float best = 1e9f;
		for (uint i = 0; i < m.sx.length(); ++i) {
			const float d = basePos.distance2D(AIFloat3(m.sx[i], 0.f, m.sz[i]));
			if (d < best) {  // the nearest analysed start is ours
				best = d;
				myStart = int(i);
			}
		}
		AiLog("[ANV] Terrain: " + (myStart < 0 ? "our start isn't an analysed one" : ("choke at (" + int(m.cx[myStart]) + "," + int(m.cz[myStart])
			+ "), high ground (" + int(m.hx[myStart]) + "," + int(m.hz[myStart]) + ") +" + int(m.gain[myStart]) + " elmos")));
	}
	if (myStart < 0)
		return false;
	const bool outnumbered = ai.GetEnemyTeamSize() > 1;
	if (Brain::Director::ratio >= 1.f && !outnumbered)
		return true;  // handled (nothing to do now)
	/*
	 * How much defence: one turret at the first order, then one more whenever something came at us since
	 * the last order (the measured pressure). Humans vs several BARbs put ~20 light turrets and ~30 mines
	 * on the lanes in the first 8 minutes (Edict, Comet Catcher 1v2).
	 */
	const float hit = terrainHit + Brain::Assess::lostNearTotal;
	if (forts > 0 && hit <= hitAtLastOrder)
		return true;
	// the turret that holds the most ground per metal we can build now (live, from the defs)
	CCircuitDef@ tur = BestTurret();
	if (tur is null || !tur.IsAvailable(ai.frame))
		return true;
	// orders still unbuilt (tasks live 3 min) count against the one wanted; expired ones are forgotten
	if (ai.frame - lastFortify >= OrderLife(terrainDef, basePos))
		terrainBuilt = forts;
	const int pending = forts - terrainBuilt;
	const int n = AiMin(1 - pending, AiMax(1, aiBuilderMgr.GetWorkerCount()));
	if (n < 1)
		return true;
	lastFortify = ai.frame;
	forts += n;
	hitAtLastOrder = hit;
	@terrainDef = tur;
	const AIFloat3 high(m.hx[myStart], 0.f, m.hz[myStart]);
	const AIFloat3 choke(m.cx[myStart], 0.f, m.cz[myStart]);
	if (!TurretSurvives(tur, high)) { forts -= n; return true; }
	// A choke tower holds the choke only if its fire reaches across the whole mouth: else raiders walk past along the
	// edges (owner, 2026-11-25, watching: "chokepoint tower placement - but can be avoided, doesnt reach to corners").
	// Reach from the high ground to the far edge = its distance to the choke centre + half the measured choke width.
	const float reachNeeded = high.distance2D(choke) + 0.5f * AiMax(0.f, m.choke);
	if (reachNeeded > tur.GetMaxRange()) {
		forts -= n;
		AiLog("[ANV] Terrain: no choke tower - " + tur.GetName() + " reaches " + int(tur.GetMaxRange()) + ", the choke's far edge is " + int(reachNeeded) + " away");
		return true;
	}
	// worth what a raid through the choke would take behind it (our producers, as raid towers value them), competing
	// with every other job - not urgent (as NOW it skipped the comparison and came before extractors)
	float behind = 0.f;
	{
		const array<CCircuitUnit@>@ mine = AiGetTeamUnits();
		CCircuitDef@ con = EcoPos::CheapestConstructor();
		for (uint i = 0; i < mine.length(); ++i)
			if (Economist::IsProducer(mine[i].circuitDef)) behind += MexPorc::RaidLoss(mine[i], con);
	}
	for (int k = 0; k < n; ++k) {
		IUnitTask@ t = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE, Task::Priority::NORMAL, tur, high, tur.GetRadius() * 2.f * float(k), true, OrderLife(tur, high)));  // side by side, a turret width apart
		IBuilderTask@ bt = cast<IBuilderTask>(t);
		if (bt !is null) bt.value = behind;
	}
	if (wallDef !is null && wallDef.IsAvailable(ai.frame) && forts % 2 == 1) {
		AIFloat3 dir = choke - AIFloat3(m.sx[myStart], 0.f, m.sz[myStart]);
		const float len = AiMax(1.f, dir.Length2D());
		dir = dir / len;
		const AIFloat3 side(-dir.z, 0.f, dir.x);
		// across the measured choke width, walls touching (no fixed 7)
		const int half = int(AiMax(0.f, m.choke) / (4.f * AiMax(1.f, wallDef.GetRadius())));
		for (int k = -half; k <= half; ++k)
			aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE, Task::Priority::NORMAL, wallDef, choke + side * (2.f * wallDef.GetRadius() * float(k)), 0.f, true, OrderLife(wallDef, choke)));  // touching
	}
	// mines in the choke mouth, on the enemy's side of the teeth: BARb walks its lanes and never sweeps
	if (minelayers > 0 && mineDef !is null && mineDef.IsAvailable(ai.frame)) {
		AIFloat3 dir = choke - AIFloat3(m.sx[myStart], 0.f, m.sz[myStart]);
		dir = dir / AiMax(1.f, dir.Length2D());
		const AIFloat3 side(-dir.z, 0.f, dir.x);
		// one row just beyond the walls, across the choke width (no fixed 5 mines or 3 cycling rows)
		const int mhalf = int(AiMax(0.f, m.choke) / (4.f * AiMax(1.f, mineDef.GetRadius())));
		for (int k = -mhalf; k <= mhalf; ++k)
			aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE, Task::Priority::NORMAL, mineDef,
				choke + dir * (2.f * ((wallDef !is null) ? wallDef.GetRadius() : mineDef.GetRadius())) + side * (2.f * mineDef.GetRadius() * float(k)), 0.f, true, OrderLife(mineDef, choke)));
	}
	AiLog("[ANV] Terrain: " + n + "x " + tur.GetName() + " on high ground (+" + int(m.gain[myStart]) + ")" + (forts % 2 == 1 ? " + teeth across the choke" : "")
		+ (minelayers > 0 ? " + mines" : ""));
	return true;
}

void Fortify()
{
	if (TerrainFortify())
		return;
	// Audit S1: no fallback constants. The cell where we lost the most metal gets a turret when that loss beats the
	// turret and it would survive; it stands on our side of the cell by its own range, so it covers the cell. One
	// order at a time, for the order's lifetime (3 min, below).
	if (ai.frame - lastFortify < OrderLife(terrainDef, basePos)) return;
	if (fortPending !is null) return;  // the last tower first (252 orders in 12 minutes, Gasbag 2026-11-25)
	CCircuitDef@ tur = BestTurret();
	if (tur is null || !tur.IsAvailable(ai.frame) || !HasBase()) return;
	// a cell a tower of ours already covers is answered: its heat is the loss before the tower stood
	const array<CCircuitUnit@>@ mine = AiGetTeamUnits();
	int best = -1;
	float bestHeat = Economist::MetalValue(tur);
	for (uint c = 0; c < Brain::Intel::heat.length(); ++c) {
		if (Brain::Intel::heat[c] <= bestHeat) continue;
		const AIFloat3 cc = Brain::Intel::CellCenter(c);
		bool covered = false;
		for (uint k = 0; k < mine.length() && !covered; ++k) {
			const CCircuitDef@ d = mine[k].circuitDef;
			covered = !d.IsMobile() && d.GetMaxRange() > 0.f && mine[k].GetPos(ai.frame).distance2D(cc) <= d.GetMaxRange();
		}
		if (covered) continue;
		bestHeat = Brain::Intel::heat[c]; best = int(c);
	}
	if (best < 0) return;
	const AIFloat3 hot = Brain::Intel::CellCenter(best);
	AIFloat3 dir = hot - basePos;
	dir.y = 0.f;
	const float len = AiMax(1.f, dir.Length2D());
	const AIFloat3 tpos = basePos + dir / len * AiMax(0.f, len - tur.GetMaxRange());
	if (!TurretSurvives(tur, tpos)) return;
	lastFortify = ai.frame;
	++forts;
	@fortPending = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE, Task::Priority::NOW, tur, tpos, tur.GetRadius() * 2.f, true, OrderLife(tur, tpos)));  // a site within its own footprint
	AiLog("[ANV] Fortify: " + tur.GetName() + " covering the cell where we lost " + int(bestHeat) + " metal");
}

string Status()
{
	return "forts=" + forts + " juno=" + junos.length() + " amd=" + amds.length() + " tac=" + tacs.length() + " silo=" + silos.length()
		+ " shield=" + shields.length() + " infra=" + infra.length() + " orders=" + orders;
}

}  // namespace Strategic

/* ======================================================================== */
/*
 * Production chooser: what should this factory make next? Decided from unit abilities read at
 * runtime (damage vs air / surface / underwater, health, range, speed, cost), never from unit names,
 * so balance patches change the choice automatically. Candidates are what the factory offers for
 * each combat role; each is scored against the scouted enemy mix.
 */
namespace Production {

array<Type> roles;
array<CCircuitDef@> rezDefs;       // resurrect/reclaim bots (facts: canresurrect)
array<CCircuitUnit@> rezBots;
int rezOrders = 0;
array<int> built(1, 0);  // per def id: how many we've ordered (diminishing returns)
int choices = 0, builders = 0;
string last = "";

void Init()
{
	roles = {RT::RAIDER, RT::ASSAULT, RT::SKIRM, RT::RIOT, RT::HEAVY, RT::ARTY, RT::AA, RT::AH, RT::AS,
		RT::SUB, RT::AHA, RT::SUPER, RT::BOMBER};
	rezDefs = Defs({"armrectr", "cornecro", "legrezbot", "armrecl", "correcl"});
	built.resize(ai.GetDefCount() + 1);
	for (uint i = 0; i < built.length(); ++i)
		built[i] = 0;
}

MapFacts::SMap@ mapInfo = null;
void LookAtMap()  // pre-match map study (tools/analyze_maps.py)
{
	MapFacts::Init();
	@mapInfo = MapFacts::Get(ai.GetMapName());
	AiLog("[ANV] Map: " + ai.GetMapName() + (mapInfo is null ? " (not analysed)" : (" mex=" + mapInfo.mex + " path=" + int(mapInfo.basePath) + " straight=" + int(mapInfo.straight) + " choke=" + int(mapInfo.choke) + " water=" + F1(mapInfo.water))));
}
// Our current army, as the candidates would join it (Lanchester: strength ~ total damage x total health).
float armyH = 0.f, armyD = 0.f, armyCost = 0.f, armyRange = 0.f, armyLos = 0.f, armySpeed = 0.f, wArty = 0.f, wStaticCost = 0.f;
// how much less the enemy can shoot aircraft than ground units: (their surface damage + 1) / (their air damage + 1)
float airExposure = 1.f;
void MeasureEnemyAA()
{
	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
	const uint n = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	float surf = 0.f, air = 0.f;
	for (uint i = 0; i < n; ++i) { if (ed[i] is null) continue; surf += ed[i].surfThrDmg; air += ed[i].airThrDmg; }
	airExposure = (surf + 1.f) / (air + 1.f);
}

void MeasureArmy(float wAir, float wSurf, float wSub)
{
	armyH = 0.f; armyD = 0.f; armyCost = 0.f; armyRange = 0.f; armyLos = 0.f; armySpeed = 0.f;
	int n = 0;
	array<CCircuitUnit@>@ pools = Brain::Army::ground;
	for (int pass = 0; pass < 2; ++pass) {
		if (pass == 1)
			@pools = Brain::Army::raiders;
		for (uint i = 0; i < pools.length(); ++i) {
			const CCircuitDef@ u = pools[i].circuitDef;
			const float dmg = wAir * u.airThrDmg + wSurf * u.surfThrDmg + wSub * u.waterThrDmg;
			armyH += u.health;
			armyD += dmg;
			armyCost += u.costM;
			armyRange += u.GetMaxRange() * dmg;   // damage-weighted reach
			armyLos = AiMax(armyLos, u.losRadius);
			armySpeed += u.speed;
			++n;
		}
	}
	armyRange = (armyD > 0.f) ? armyRange / armyD : 0.f;
	armySpeed = (n > 0) ? armySpeed / n : 0.f;
}

float Score(CCircuitDef@ d, float wAir, float wSurf, float wSub, float wStatic, float wHeavy)
{
	if (d is null || !d.IsAvailable(ai.frame) || d.costM <= 0.f)
		return 0.f;
	// damage that can actually land on what the enemy fields
	const float dmg = wAir * d.airThrDmg + wSurf * d.surfThrDmg + wSub * d.waterThrDmg;
	if (dmg <= 0.f)
		return 0.f;
	const float hp = AiMax(1.f, d.health);
	// Lanchester square law: strength ~ D*H. The relative gain from adding (dmg, hp) is
	// d(DH)/DH = dmg/D + hp/H: scale-free (threat-damage and health use different units), and it buys
	// what the army lacks: damage for a tanky army, bodies for a glass cannon.
	const float D = AiMax(armyD, dmg), Hh = AiMax(armyH, hp);
	float s = dmg / D + hp / Hh;
	const float range = d.GetMaxRange();
	// Reach: a unit that extends our army's reach fights on our terms; against defences even more.
	if (armyRange > 0.f)
		s *= 1.f + (1.f + wStatic) * AiMax(0.f, range - armyRange) / armyRange;
	// Sight: if our army outranges its own sight it shoots at nothing; long-sight units close that gap.
	if (armyRange > armyLos && armyRange > 0.f)
		s *= 1.f + (armyRange - armyLos) / armyRange * AiMin(1.f, d.losRadius / armyRange);
	// Slow shells miss moving targets: against an artillery-heavy enemy, speed is survival.
	if (armySpeed > 0.f)
		s *= 1.f + wArty * d.speed / armySpeed;
	// Screens: vs heavies/artillery, hp per metal soaks expensive shots (relative to our army's).
	if (armyCost > 0.f && armyH > 0.f)
		s *= 1.f + wHeavy * (hp / d.costM) / (armyH / armyCost);
	// Counter: aircraft are worth as much more as the enemy can't shoot them (owner: T2 gunships beat Behemoth, no AA)
	if (d.IsAbleToFly())
		s *= airExposure;
	// Time is a resource: a unit is worth the share of the planning horizon it actually spends fighting.
	const float H = Brain::Economist::Horizon();
	const float dist = Brain::Assess::frontDist > 0.f ? Brain::Assess::frontDist : AiTerrainDiagonal() * 0.5f;
	const float travel = dist / AiMax(1.f, d.speed);
	s *= AiMax(0.f, 1.f - travel / AiMax(1.f, H));
	// Tactical kinds (facts from unit files; the API can't see weapon flags). Same units as above:
	// relative gain in fighting strength. A stun/blast that removes a fraction f of the enemy's
	// effective strength is worth ~f; f ~ (share of targets it suits) x (this unit's share of our army).
	const float share = d.costM / AiMax(1.f, armyCost + d.costM);
	if (Facts::empUnits.find(d.GetName()) >= 0)
		s += wHeavy * share;      // EMP: disables heavy, expensive targets while our army hits freely
	if (Facts::crawlUnits.find(d.GetName()) >= 0)
		s += (wStaticCost + wHeavy) * share;  // crawling bombs: area damage on what can't dodge
	return s / Brain::Economist::MetalValue(d);  // per metal, energy priced at the converter rate
}
void OnFinished(CCircuitUnit@ u) { if (InList(rezDefs, u.circuitDef)) rezBots.insertLast(u); }
void OnDestroyed(CCircuitUnit@ u) { RemoveUnit(rezBots, u); }

// Wrecks are the fastest metal on the map: about half the metal of what died recently lies there
// (Assess windows decay as it gets harvested or goes stale). Keep adding rez bots while that pool is
// worth more than the rez fleet we already have: a bot pays for itself if there's more than its cost to take.
// who ends up holding the ground where fights happened: our share of the exchange, trade / (1 + trade)
float HoldShare() { const float tr = Brain::Assess::trade; return tr / (1.f + tr); }
CCircuitDef@ RezToBuild(const CCircuitDef@ fdef)
{
	/*
	 * Scale: the fleet is worth having while the wreck metal on the map repays it. Wrecks don't decay, so
	 * the pool is everything that died (ours and theirs) at the wreck share of its metal. Fights far away
	 * leave wrecks the enemy can take too, so those count half. One more bot while pool > fleet cost + bot
	 * (each bot must have at least its own cost to bring back). Debt: subtract what was already harvested.
	 */
	// the wreck metal actually on the map (bridge), not an estimate from what died
	float pool = 0.f;
	{
		array<AIFloat3> wp; array<float> wm; array<bool> wr;
		const uint w = AiGetWrecks(wp, wm, wr);
		// wrecks of units only (resurrectable): rocks and trees counted too ordered rez bots without end on a rock-rich
		// map (owner, 2026-11-25: "building nothing but rezbots?!"); winners build 0.56 by minute 5, 1.83 by 10, once
		// fights have left wrecks (replays.db, 107 1v1 wins) - constructors reclaim rocks themselves
		// ...and only what we will hold: wrecks on our side, at our share of the exchange (HoldShare, as the comment above
		// intends - unapplied, every wreck counted and 33 rez bots came in minutes 12-19 while the trade ran 0.45 and
		// the army lost its fights, cmd_m116)
		for (uint i = 0; i < w; ++i) if (wr[i] && Assess::OnOurSide(wp[i])) pool += wm[i];
		pool *= HoldShare();
	}
	float fleet = 0.f;
	for (uint i = 0; i < rezBots.length(); ++i)
		fleet += rezBots[i].circuitDef.costM;
	// which lab builds which rez bot (unit facts: buildoptions); the API can't list buildoptions
	const string fn = fdef.GetName();
	CCircuitDef@ d = (fn == "armlab") ? Def("armrectr") : ((fn == "corlab") ? Def("cornecro")
		: ((fn == "leglab") ? Def("legrezbot") : ((fn == "armsy") ? Def("armrecl") : ((fn == "corsy") ? Def("correcl") : null))));
	if (d !is null && d.IsAvailable(ai.frame) && pool > fleet + d.costM)
		return d;
	return null;
}

IUnitTask@ MineLayerTask(CCircuitUnit@ fac)
{
	if (Strategic::myStart < 0 || Strategic::minelayers > 0 || Strategic::mlvDef is null
		|| (Strategic::mlvOrderedAt != NEVER && ai.frame - Strategic::mlvOrderedAt < OrderLife(Strategic::mlvDef, fac.GetPos(ai.frame))) || !Strategic::mlvDef.IsAvailable(ai.frame)
		|| Facts::BuildOptions(fac.circuitDef.GetName()).find(Strategic::mlvDef.GetName()) < 0)
		return null;
	Strategic::mlvOrderedAt = ai.frame;
	AiLog("[ANV] Terrain: recruiting a minelayer");
	return aiFactoryMgr.Enqueue(TaskS::Recruit(Task::RecruitType::BUILDPOWER, Task::Priority::HIGH, Strategic::mlvDef,
		fac.GetPos(ai.frame), fac.circuitDef.GetRadius()));
}


/*
 * Extractor upgrades (1v2 curve: we match each bot until minute 15, then lose outer extractors and stall at
 * ~55 m/s while each bot compounds to 150 on mohos). If we can't hold as many spots as two enemies, the
 * spots we can hold must give 4x. Upgrades are queued on T2 constructors: with U safe T1 extractors and C
 * constructors, the k-th upgrade waits ~k*tau/C, so one more constructor saves ~extra*tau*U^2/(2C(C+1))
 * of metal (extra = income an upgrade adds, tau = one upgrade's build time). Build it while that beats its cost.
 */
// an upgrade constructor is one that can build the T2 extractor (unit facts, no name list)
bool IsUpgradeCon(const CCircuitDef@ d) { return d !is null && Brain::Economist::mexT2 !is null && d.CanBuild(Brain::Economist::mexT2); }
int mohoCons = 0;
string mohoWhy = "";
// What a lab whose constructors upgrade extractors adds: each safe T1 extractor's extra yield (net of the upgrade's
// extra upkeep) from when the k-th upgrade is done to the horizon, less each upgrade's cost. BARb's income ran 87-239/s
// on upgraded extractors vs our 20-40 (cmd_m89-m135).
float UpgradeValue(const CCircuitDef@ lab, float labBusy)
{
	CCircuitDef@ t1 = Brain::Economist::mexT1; CCircuitDef@ t2 = Brain::Economist::mexT2;
	if (t1 is null || t2 is null || lab is null) return 0.f;
	const array<string> opts = Facts::BuildOptions(lab.GetName());
	CCircuitDef@ con = null;
	for (uint k = 0; k < opts.length() && con is null; ++k) { CCircuitDef@ o = ai.GetCircuitDef(opts[k]); if (o !is null && IsUpgradeCon(o)) @con = o; }
	if (con is null) return 0.f;
	uint U = 0;
	const array<CCircuitUnit@>@ mx = Brain::Economist::mexes;
	for (uint m = 0; m < mx.length(); ++m) if (mx[m].circuitDef is t1 && aiThreat.GetThreatAt(con, mx[m].GetPos(ai.frame)) <= 0.f) ++U;
	const float perMex = aiEconomyMgr.metal.income / float(AiMax(1, int(mx.length())));
	const float extra = perMex * (Brain::Economist::MexExtract(t2) / AiMax(1e-9f, Brain::Economist::MexExtract(t1)) - 1.f)
		- (Brain::Economist::MexUpkeep(t2) - Brain::Economist::MexUpkeep(t1)) / AiMax(1e-3f, Brain::Economist::energyPerMetal);
	const float tau = t2.buildTime / AiMax(1.f, con.buildSpeed);
	const float H = AiMax(1.f, Brain::Economist::ProducerLife());
	float up = 0.f;
	for (uint k = 1; k <= U; ++k) up += AiMax(0.f, extra * AiMax(0.f, H - labBusy - float(k) * tau) - Brain::Economist::MetalValue(t2));
	return up;
}
IUnitTask@ MohoConTask(CCircuitUnit@ fac)
{
	CCircuitDef@ t2 = Brain::Economist::mexT2;
	if (t2 is null || !t2.IsAvailable(ai.frame)) return null;
	const array<string>@ opts = Facts::BuildOptions(fac.circuitDef.GetName());
	CCircuitDef@ con = null;
	for (uint i = 0; i < opts.length() && con is null; ++i)
		{ CCircuitDef@ d = ai.GetCircuitDef(opts[i]); if (d !is null && d.IsAvailable(ai.frame) && IsUpgradeCon(d)) @con = d; }
	if (con is null) return null;
	// safe T1 extractors left to upgrade
	uint U = 0;
	const array<CCircuitUnit@>@ mx = Brain::Economist::mexes;
	for (uint m = 0; m < mx.length(); ++m)
		if (mx[m].circuitDef is Brain::Economist::mexT1 && aiThreat.GetThreatAt(con, mx[m].GetPos(ai.frame)) <= 0.f) ++U;
	if (U == 0) { mohoWhy = "nothing safe to upgrade"; return null; }
	uint C = 0;
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	for (uint i = 0; i < all.length(); ++i) if (IsUpgradeCon(all[i].circuitDef)) ++C;
	const float perMex = aiEconomyMgr.metal.income / float(AiMax(1, int(mx.length())));
	const float extra = perMex * (Brain::Economist::MexExtract(Brain::Economist::mexT2) / AiMax(1e-9f, Brain::Economist::MexExtract(Brain::Economist::mexT1)) - 1.f)
		- (Brain::Economist::MexUpkeep(Brain::Economist::mexT2) - Brain::Economist::MexUpkeep(Brain::Economist::mexT1)) / AiMax(1e-3f, Brain::Economist::energyPerMetal);
	if (extra <= 0.f) { mohoWhy = "upgrade doesn't pay its upkeep"; return null; }
	const float tau = t2.buildTime / AiMax(1.f, con.buildSpeed);
	// What one more constructor saves, within the extractors' life: with C constructors the k-th upgrade stands at
	// ceil(k/C) x tau and earns extra until the life is out. (Counting every upgrade forever - U^2 / 2C(C+1) - bought 7-11
	// constructors per game and the advanced lab made no fighters; the first upgrade came at 13:15 and the game was
	// lost at 15:00, t2g; #100.)
	const float L = AiMax(1.f, Brain::Economist::ProducerLife());
	float vC = 0.f, vC1 = 0.f;
	for (uint k = 1; k <= U; ++k) {
		if (C > 0) vC += extra * AiMax(0.f, L - ceil(float(k) / float(C)) * tau);
		vC1 += extra * AiMax(0.f, L - ceil(float(k) / float(C + 1)) * tau);
	}
	const float saving = vC1 - vC;
	// Metal has a shadow price: while we are short of the army we need, a metal not spent on army costs
	// needed/ours of it (the Director's ratio). Upgrades must beat army at that price.
	const float shadow = AiMax(1.f, 1.f / AiMax(1e-2f, Brain::Director::ratio));
	const float price = Brain::Economist::MetalValue(con) * shadow;
	mohoWhy = "U=" + U + " C=" + C + " saving=" + int(AiMin(saving, 1e6f)) + " vs " + int(price);
	if (saving <= price) return null;
	++mohoCons;
	return aiFactoryMgr.Enqueue(TaskS::Recruit(Task::RecruitType::BUILDPOWER, Task::Priority::HIGH, con, fac.GetPos(ai.frame), fac.circuitDef.GetRadius()));
}

IUnitTask@ MakeTask(CCircuitUnit@ fac)
{
	if (!fac.circuitDef.IsMobile()) {
		CCircuitDef@ rez = RezToBuild(fac.circuitDef);
		if (rez !is null) {
			++rezOrders;
			AiLog("[ANV] Rez: +" + rez.GetName() + " fleet=" + rezBots.length());
			return aiFactoryMgr.Enqueue(TaskS::Recruit(Task::RecruitType::BUILDPOWER, Task::Priority::HIGH, rez, fac.GetPos(ai.frame), fac.circuitDef.GetRadius()));
		}
	}
	IUnitTask@ ml = MineLayerTask(fac);
	if (ml !is null)
		return ml;
	IUnitTask@ mc = MohoConTask(fac);
	if (mc !is null)
		return mc;
	const CCircuitDef@ fdef = fac.circuitDef;
	if (fdef.IsMobile())
		return null;
	/*
	 * What this factory builds is one comparison (#96): every unit it can make is worth what it adds, in metal, per
	 * metal it costs; the best is built. No roles, quotas, target mix or BARb default.
	 *  - a fighter: the square law, per damage domain (air; surface = everything else). Our strength S = sum of
	 *    sqrt(damage vs that domain x health); theirs E, as seen (unseen: at least as strong as ours, they earn as we
	 *    do). The chance we win there is p = S^2/(S^2+E^2); the unit is worth what is at stake there (what we own and
	 *    what they own, split by where their strength is) x how much it raises p - nothing where no enemy is, less
	 *    and less where we already dominate. Discounted by the share of the horizon it spends walking to the front.
	 *  - a constructor: the yield it saves by claiming free spots sooner (EcoPos), while every constructor has a job.
	 *  - a scout (any unit, for its sight): the next most valuable cell no scout covers (Scout: what of ours an enemy
	 *    there could reach before we answer, raidable spots gone dark), for the share of the cell its sight covers.
	 * A unit can do one job: its value is the larger of the three.
	 */
	const array<string>@ opts = Facts::BuildOptions(fdef.GetName());
	const AIFloat3 fpos = fac.GetPos(ai.frame), them = AiEnemyBasePos();
	// our strength per domain
	float sAir = 0.f, sSurf = 0.f;
	{
		const array<CCircuitUnit@>@ mine = AiGetTeamUnits();
		for (uint i = 0; i < mine.length(); ++i) {
			const CCircuitDef@ d = mine[i].circuitDef;
			if ((!IsArmy(d) && mine[i] !is commander) || Scout::IsScout(mine[i])) continue;  // the commander fights too
			sAir += sqrt(AiMax(0.f, d.airThrDmg) * AiMax(1.f, d.health));
			sSurf += sqrt(AiMax(0.f, d.surfThrDmg) * AiMax(1.f, d.health));
		}
	}
	// theirs, as seen
	float eAir = 0.f, eSurf = 0.f;
	{
		array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
		const uint ne = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
		for (uint i = 0; i < ne; ++i) {
			const CCircuitDef@ d = ed[i];
			if (d is null || d.GetSustainedDps() <= 0.f) continue;
			const float st = sqrt(d.GetSustainedDps() * AiMax(1.f, eh[i] * d.health));
			if (d.IsAbleToFly()) eAir += st; else eSurf += st;
		}
	}
	eSurf = AiMax(eSurf, sSurf + sAir);  // unseen: at least as strong as we are (they earn as we do)
	// Their growth as seen: the strongest surface strength we have seen, and when. A unit ordered now fights the army
	// that is there when it is ready, so it is valued against that: now + measured growth x (its build + walk) (sight,
	// not a prior: no growth before two sightings). Valued against the army of the moment, fighters lost to
	// constructors both before BARb's first raid (seen 39-50) and once it was seen (277 vs our 35): army 162 vs 386 at
	// 3:00, the swing (swing.py it2).
	{
		float seenE = 0.f;
		array<AIFloat3> ep2, ev2; array<CCircuitDef@> ed2; array<float> ec2, eh2, eb2; array<int> ef2;
		const uint ne2 = AiGetEnemies(ep2, ev2, ed2, ec2, ef2, eh2, eb2);
		for (uint i = 0; i < ne2; ++i)
			if (ed2[i] !is null && ed2[i].IsMobile() && !ed2[i].IsAbleToFly() && ed2[i].GetSustainedDps() > 0.f)
				seenE += sqrt(ed2[i].GetSustainedDps() * AiMax(1.f, eh2[i] * ed2[i].health));
		if (seenE > peakE) {
			if (peakE > 0.f && peakFrame >= 0 && ai.frame > peakFrame) growthE = (seenE - peakE) / (float(ai.frame - peakFrame) / SECOND);
			peakE = seenE; peakFrame = ai.frame;
		}
	}
	// The ground units a fighter of ours will meet: the enemy's as seen (weighted by strength); none seen yet, the
	// units this factory offers (they build the same class of units). A unit outranged by them takes their fire while
	// it closes the gap: its health in the fight is less that damage (range, speed and dps from the unit defs). Without
	// it, sqrt(dps x health) per metal made the Flea - a scout with a needle gun - our best fighter: 14-16 per game
	// and the extractors raided away (short test s32, 2026-11-25).
	Mix mix; FillMix(mix, opts);
	// An army holds the flow, not only the stock: our income over the horizon is what a raid takes and what holding
	// the map keeps (the constructor's value counts the yield it claims over the horizon; against a stake of owned
	// metal alone the lab made 19 constructors and 86 army by minute 8 vs the winners' 10.8 and 2036, Feast 2026-11-25)
	const float H0 = AiMax(1.f, Economist::Horizon());
	const float flow = (aiEconomyMgr.metal.income + aiEconomyMgr.energy.income / AiMax(1e-3f, Economist::energyPerMetal)) * H0;
	// feedback: what raids have been taking, at the measured rate over the horizon, is what an army stops
	const float stake = Strategic::ownedMetal + Assess::EnemyValue() + flow + Economist::LossRate() * H0;
	const float eAll = AiMax(1e-3f, eAir + eSurf);
	const float stakeAir = stake * eAir / eAll, stakeSurf = stake * eSurf / eAll;
	const float H = AiMax(1.f, Economist::Horizon());
	const float dist = Brain::Assess::frontDist > 0.f ? Brain::Assess::frontDist : fpos.distance2D(them) * 0.5f;
	array<AIFloat3> theirSpots;
	{
		array<AIFloat3> msp; array<float> msi; array<bool> mso;
		AiGetMetalSpots(msp, msi, mso);
		for (uint k = 0; k < msp.length(); ++k) if (!Assess::OnOurSide(msp[k])) theirSpots.insertLast(msp[k]);
		if (theirSpots.length() == 0) theirSpots.insertLast(them);
	}
	// One fight per enemy type seen (owner: "do you build anything else than fucking ticks?" - 91 Pawns and 12
	// constructors, sp0; 89 and 235 Fleas, cmd_lab2/3): scored against the whole mix at once the same unit won every
	// pick, and nothing made its next copy worth less. Per type k: their strength E_k as seen (scaled so the total stays
	// at least ours - unseen), ours S_k = our army's power against k (Production::SurfPower: range gap, splash, hit
	// chance), the stake shared by E_k. A unit is worth what it adds over all k; WinShare saturates where a matchup is
	// won, so more Pawns add nothing against Gators they already beat and a unit that outranges the Levelers we lose to
	// adds most (square law).
	array<string> kName; array<float> kE, kS; array<Mix@> kMix;
	float mE = 0.f, nOurs = 0.f;  // armed units on each side (granularity, #101)
	{
		array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
		const uint ne = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
		for (uint i = 0; i < ne; ++i) {
			const CCircuitDef@ d = ed[i];
			if (d is null || !d.IsMobile() || d.IsAbleToFly() || d.GetSustainedDps() <= 0.f) continue;
			int k = kName.find(d.GetName());
			if (k < 0) {
				k = int(kName.length()); kName.insertLast(d.GetName()); kE.insertLast(0.f); kS.insertLast(0.f);
				Mix mk; mk.dps.insertLast(d.GetSustainedDps()); mk.range.insertLast(d.GetMaxRange()); mk.aoe.insertLast(d.GetAoe());
				mk.shot.insertLast(d.GetShotSpeed()); mk.speed.insertLast(d.speed); mk.rad.insertLast(d.GetRadius()); mk.w.insertLast(1.f);
				mk.cnt.insertLast(0.f);
				kMix.insertLast(mk);
			}
			kMix[k].cnt[0] += 1.f;
			kE[k] += sqrt(d.GetSustainedDps() * AiMax(1.f, eh[i] * d.health));
			mE += 1.f;
		}
		// Memory of what scouting has shown (owner: "you should resolve that through scouting", "no prior"): per enemy
		// type the most seen at once and when; a type seen and now out of sight still counts, by the share of the
		// horizon since it was seen (sightings, not assumptions). Counting only what is in sight now, Storms and Thuds
		// seen at 12:00 left the mix as they left sight and the lab kept making Pawns into their push (tk3).
		{
			dictionary nowCnt;
			for (uint i = 0; i < ne; ++i) {
				const CCircuitDef@ d = ed[i];
				if (d is null || !d.IsMobile() || d.IsAbleToFly() || d.GetSustainedDps() <= 0.f) continue;
				int c = 0; if (!nowCnt.get(d.GetName(), c)) c = 0; nowCnt.set(d.GetName(), c + 1);
			}
			const array<string>@ ks = nowCnt.getKeys();
			for (uint q = 0; q < ks.length(); ++q) {
				int c = 0; if (!nowCnt.get(ks[q], c)) c = 0;
				int m = 0; if (!memMax.get(ks[q], m)) m = 0;
				if (c >= m) { memMax.set(ks[q], c); memFrame.set(ks[q], ai.frame); }
			}
			const array<string>@ mk = memMax.getKeys();
			const float Hm = AiMax(1.f, Economist::Horizon());
			for (uint q = 0; q < mk.length(); ++q) {
				int m = 0; if (!memMax.get(mk[q], m)) m = 0;
				int fr = 0; if (!memFrame.get(mk[q], fr)) fr = ai.frame;
				int c = 0; if (!nowCnt.get(mk[q], c)) c = 0;
				const float age = float(ai.frame - fr) / SECOND;
				const float extra = float(m - c) * AiMax(0.f, 1.f - age / Hm);  // remembered, out of sight, fading over the horizon
				if (extra <= 0.f) continue;
				CCircuitDef@ d = ai.GetCircuitDef(mk[q]);
				if (d is null) continue;
				int k = kName.find(d.GetName());
				if (k < 0) {
					k = int(kName.length()); kName.insertLast(d.GetName()); kE.insertLast(0.f); kS.insertLast(0.f);
					Mix mk2; mk2.dps.insertLast(d.GetSustainedDps()); mk2.range.insertLast(d.GetMaxRange()); mk2.aoe.insertLast(d.GetAoe());
					mk2.shot.insertLast(d.GetShotSpeed()); mk2.speed.insertLast(d.speed); mk2.rad.insertLast(d.GetRadius()); mk2.w.insertLast(1.f);
					mk2.cnt.insertLast(0.f);
					kMix.insertLast(mk2);
				}
				kMix[k].cnt[0] += extra;
				kE[k] += extra * sqrt(d.GetSustainedDps() * AiMax(1.f, d.health));
				mE += extra;
			}
		}
		float seen = 0.f;
		for (uint k = 0; k < kE.length(); ++k) seen += kE[k];
		const float scale = (seen > 0.f) ? AiMax(1.f, eSurf / seen) : 1.f;
		for (uint k = 0; k < kE.length(); ++k) kE[k] *= Gran(mE * scale) * scale;  // their unseen units count too
		// ours against each: per our type, its power x how many (one SurfPower per type pair)
		const array<CCircuitUnit@>@ mine = AiGetTeamUnits();
		dictionary cnt; array<string> ours;
		for (uint i = 0; i < mine.length(); ++i) {
			const CCircuitDef@ d = mine[i].circuitDef;
			if ((!IsArmy(d) && mine[i] !is commander) || Scout::IsScout(mine[i]) || d.IsAbleToFly() || d.GetSustainedDps() <= 0.f) continue;
			int c = 0; if (!cnt.get(d.GetName(), c)) c = 0; cnt.set(d.GetName(), c + 1);
			if (c == 0) ours.insertLast(d.GetName());
			nOurs += 1.f;
		}
		for (uint j = 0; j < ours.length(); ++j) {
			int c = 0; if (!cnt.get(ours[j], c)) c = 0;
			CCircuitDef@ od = ai.GetCircuitDef(ours[j]);
			for (uint k = 0; k < kE.length(); ++k) { string tm; kS[k] += float(c) * SurfPower(od, kMix[k], tm); }
		}
	}
	// The fights a fighter takes are with the enemy's groups, not its whole army at once: raiders come one or two at a
	// time and kill producers until something beats them there. Each seen group (linked when within the longer of their
	// weapon ranges, as the replay analyzer groups squads) is one fight; its stake is what it can destroy over the
	// horizon (its dps x H at our producers' metal per health, at most the stake); a fighter is worth what it adds to
	// our win share in each. As one global battle, behind 12 vs 236 a Pawn added ~0.04 of the stake and the lab made
	// constructors while 1-2 Grunts killed the extractors (metal 6.6-8.9 vs 18.1 at 4:00, swing.py sw5-6).
	array<float> gE, gD;  // per group: strength, dps
	{
		array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
		const uint ne = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
		array<int> gi; array<AIFloat3> gp; array<float> gr, gs, gd;
		for (uint i = 0; i < ne; ++i) {
			const CCircuitDef@ d = ed[i];
			if (d is null || !d.IsMobile() || d.IsAbleToFly() || d.GetSustainedDps() <= 0.f) continue;
			gp.insertLast(ep[i]); gr.insertLast(d.GetMaxRange()); gd.insertLast(d.GetSustainedDps());
			gs.insertLast(sqrt(d.GetSustainedDps() * AiMax(1.f, eh[i] * d.health)));
			gi.insertLast(int(gi.length()));
		}
		// single linkage: union by relabelling
		for (uint a = 0; a < gp.length(); ++a)
			for (uint b = a + 1; b < gp.length(); ++b)
				if (gi[a] != gi[b] && gp[a].distance2D(gp[b]) <= AiMax(gr[a], gr[b])) {
					const int from = gi[b], to = gi[a];
					for (uint c = 0; c < gi.length(); ++c) if (gi[c] == from) gi[c] = to;
				}
		array<int> lab;
		for (uint a = 0; a < gi.length(); ++a) {
			int g = lab.find(gi[a]);
			if (g < 0) { g = int(lab.length()); lab.insertLast(gi[a]); gE.insertLast(0.f); gD.insertLast(0.f); }
			gE[g] += gs[a]; gD[g] += gd[a];
		}
	}
	float mPerHp = 0.f;
	{
		float pc = 0.f, ph = 0.f;
		const array<CCircuitUnit@>@ mine = AiGetTeamUnits();
		for (uint i = 0; i < mine.length(); ++i)
			if (Economist::IsProducer(mine[i].circuitDef)) { pc += Economist::MetalValue(mine[i].circuitDef); ph += AiMax(1.f, mine[i].circuitDef.health); }
		mPerHp = (ph > 0.f) ? pc / ph : 0.f;
	}
	float kESum = 0.f;
	for (uint k = 0; k < kE.length(); ++k) kESum += kE[k];
	string kLog = "";
	for (uint k = 0; k < kE.length(); ++k) kLog += " " + kName[k] + " " + int(kS[k]) + "/" + int(kE[k]);
	CCircuitDef@ bestDef = null; float bestRatio = 0.f, bestV = 0.f; int bestJob = -1;  // 0 fight, 1 build, 2 scout
	float conRatioNow = 0.f;  // the constructor's value per metal this pick
	string why = "";
	for (uint i = 0; i < opts.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(opts[i]);
		if (d is null || !d.IsMobile() || !d.IsAvailable(ai.frame) || d.costM <= 0.f || InList(rezDefs, d)) continue;
		if (!d.IsAbleToFly()) {  // it must reach somewhere that matters: an extractor spot on their side
			bool reach = false;
			for (uint k = 0; k < theirSpots.length() && !reach; ++k) reach = AiDefCanReach(d, fpos, theirSpots[k]);
			if (!reach) continue;
		}
		float vFight = 0.f, vBuild = 0.f, vScout = 0.f;
		string terms = "";  // the fight terms, logged with each candidate
		if (d.IsRoleAny(Unit::Role::BUILDER.mask) && d.buildSpeed > 0.f) {
			// the value is claiming free spots: only for a builder that can build an extractor
			if (Economist::mexT1 !is null && d.CanBuild(Economist::mexT1)) vBuild = EcoPos::constructorValue;
		} else if (d.GetSustainedDps() > 0.f) {
			const float hp = AiMax(1.f, d.health);
			const float us = SurfPower(d, mix, terms);
			const float ua = sqrt(AiMax(0.f, d.airThrDmg) * hp);
			const float tReady = d.buildTime / AiMax(1.f, fdef.buildSpeed) + dist / AiMax(1.f, d.speed);
			const float grow = (eSurf > 0.f) ? 1.f + growthE * tReady / eSurf : 1.f;  // the enemy when it is ready, as a factor
			float vSurf = stakeSurf * (WinShare(sSurf + us, eSurf * grow) - WinShare(sSurf, eSurf * grow));
			if (kESum > 0.f) {
				vSurf = 0.f;
				for (uint k = 0; k < kE.length(); ++k) {
					string tm;
					const float uk = SurfPower(d, kMix[k], tm);
					// with one unit more our force is split one way further (#101): Gran(n+1) on the new total
					vSurf += stakeSurf * kE[k] / kESum * (WinShare((kS[k] + uk) * Gran(nOurs + 1.f), kE[k] * grow) - WinShare(kS[k] * Gran(nOurs), kE[k] * grow));
				}
				terms += " per-type " + int(vSurf) + " grow " + F2(grow);
			}
			// the first raids, valued by the loss a fighter prevents (#41/#103, "army by the first raid"): the opener's raid
			// model (unit facts, setup) says how many raiders their lab has by the time this unit is ready; while they
			// outnumber our fighters, each fighter that beats one in a duel stops its kill rate on our producers (its dps
			// x our producers' metal per health) over the horizon. As a share of a bigger enemy's fight the same raid
			// made fighters worth less (Pawn 0.71 vs constructor 2.08, army 54 vs 215 at 3:00, swe4).
			if (Opening::raidRate > 0.f && mPerHp > 0.f) {
				const float tUp = float(ai.frame) / SECOND + d.buildTime / AiMax(1.f, fdef.buildSpeed);
				// their raider rate is the lab's build speed AND what their income pays for (they earn as we do: our income over
				// a raider's metal) - on build speed alone it read 6.3 raiders at ~2:00 against BARb's real 86 metal of army,
				// and the lab made Ticks and no constructors (swe6: army 504 vs 215 but metal 8.9 vs 11.2 at 3:00)
				const float rate = AiMin(Opening::raidRate, aiEconomyMgr.metal.income / AiMax(1.f, Opening::raidCostM));
				float nR = AiMax(0.f, tUp - Opening::raidLabAt) * rate;
				// once raiders have been seen, how many there are is what scouting showed (Production's memory of enemy
				// types, most seen at once), not the model - the model has them spend every metal on raiders and read dozens
				// by 4:00: 12 Pawns in a row after two constructors, metal 6.6 vs 20.4 (swe10)
				{
					float seenArmed = 0.f;
					const array<string>@ mk = memMax.getKeys();
					for (uint q = 0; q < mk.length(); ++q) {
						CCircuitDef@ md = ai.GetCircuitDef(mk[q]);
						if (md is null || md.GetSustainedDps() <= 0.f) continue;
						int c = 0; if (!memMax.get(mk[q], c)) c = 0;
						seenArmed += float(c);
					}
					if (seenArmed > 0.f) nR = seenArmed;
				}
				if (nR > nOurs) {
					// in the raider's own measure, sqrt(dps x health) both sides (SurfPower is on the core's threat scale: the
					// duel read 0.01-0.02, swe5)
					// the square law, as every fight is judged (FightGain): at least as strong it stops the raider; weaker, it
					// kills (s/R)^2 of it and dies. As a share s/(s+R) a Tick read half a Grunt's worth per far less metal and
					// four Ticks died to Grunts at 3:33-3:53 beside the extractors they were meant to keep (swe9)
					const float sR = Opening::Strength(d), R = AiMax(1e-3f, Opening::raidStrength);
					const float duel = (sR >= R) ? 1.f : (sR / R) * (sR / R);
					// a fighter now instead of later answers the raid one lab slot sooner (its build time): that is the loss it
					// prevents, not the raid's damage over the whole horizon (10711 s early: 85492, the whole stake - the lab made
					// no constructor in its first 12 units and the base fell behind, buildings 665 vs 850 at 3:00, swe7)
					// ...and as long as the raid will have gone unanswered when it is ready: before the raid arrives a fighter one
					// slot later is as good (one slot); after, each slot without one lets it go on. Over the whole horizon the
					// lab made no constructor (swe7); over one slot alone it made only constructors, army 0 vs 146 at 2:00 (swe8).
					const float slot = d.buildTime / AiMax(1.f, fdef.buildSpeed);
					const float unanswered = AiMax(slot, tUp - Opening::raidArrive);
					const float vRaid = AiMin(stakeSurf, Opening::raidDps * mPerHp * unanswered * duel);
					if (vRaid > vSurf) { vSurf = vRaid; terms += " firstRaid " + int(vRaid) + " (" + F1(nR) + " raiders, duel " + F2(duel) + ")"; }
				}
			}
			if (gE.length() > 0) {
				float vG = 0.f;
				for (uint g = 0; g < gE.length(); ++g) {
					const float stakeG = AiMin(stakeSurf, gD[g] * H * mPerHp);
					vG += stakeG * (WinShare((sSurf + us) * Gran(nOurs + 1.f), gE[g] * grow) - WinShare(sSurf * Gran(nOurs), gE[g] * grow));
				}
				terms += " groups " + gE.length() + ":" + int(vG);
				vSurf = AiMax(vSurf, vG);  // the global fight and the group fights are the same army: the larger stands
			}
			vFight = stakeAir * (WinShare(sAir + ua, eAir) - WinShare(sAir, eAir)) + vSurf;
			// a raider is also worth what our raids actually kill per raider over its measured life (Command::RaiderWorth;
			// 0 until a raid has killed) - winners' labs make mostly Ticks early (replays.db, 24 wins)
			{
				const float vR = Command::RaiderWorth(d);
				if (vR > vFight) { vFight = vR; terms += " raid " + int(vR); }
			}
			vFight *= AiMax(0.f, 1.f - dist / AiMax(1.f, d.speed) / H);
		}
		// information is worth what we can do with it: the share of a fight our forces could contest (a warning saves
		// nothing when the army can't answer - 29 Fleas and 3 fighters at our 25 strength against 3789, round 20)
		{
			// measured once scouts have served (what they found per second over their life), the model before
			const float mw = Scout::MeasuredWorth();
			vScout = ((mw >= 0.f) ? AiMin(mw, Scout::NextValue(d)) : Scout::NextValue(d)) * WinShare(sSurf + sAir, eSurf + eAir);
			if (Scout::scouts.length() == 0) vScout = AiMax(vScout, Scout::WarningValue(d));  // a first scout warns of raids
		}
		const float v = AiMax(vFight, AiMax(vBuild, vScout));
		const float ratio = v / AiMax(1.f, Economist::CostNow(d));  // energy at its price now (binding or not)
		if (v == vBuild && vBuild > 0.f) conRatioNow = ratio;
		why += " " + d.GetName() + "=" + F2(ratio) + terms;
		if (ratio > bestRatio) {
			bestRatio = ratio; @bestDef = d; bestV = v;
			bestJob = (v == vScout) ? 2 : ((v == vBuild) ? 1 : 0);
		}
	}
	if (bestDef is null) {
		AiLog("[ANV-PROD] " + fdef.GetName() + ": no unit adds value now:" + why);
		return null;
	}
	if (bestJob == 2) Scout::pendingDefs.insertLast(bestDef.id);
	if (bestJob == 1) ++builders; else ++choices;
	++built[bestDef.id];
	last = bestDef.GetName();
	if (bestJob == 0) lastBestRatio = bestRatio;
	if (conRatioNow > 0.f || lastBestRatio > 0.f) aiMilitaryMgr.SetValuePerMetal(lastBestRatio, conRatioNow);  // lab build power (core)
	AiLog("[ANV-PROD] " + fdef.GetName() + " -> " + bestDef.GetName() + " as " + (bestJob == 2 ? "scout" : (bestJob == 1 ? "constructor" : "fighter"))
		+ " (value " + int(bestV) + " per metal " + F2(bestRatio) + "; S air/surf " + int(sAir) + "/" + int(sSurf) + " E " + int(eAir) + "/" + int(eSurf) + "; per type ours/theirs" + kLog + ")" + " |" + why);
	return aiFactoryMgr.Enqueue(TaskS::Recruit(bestJob == 1 ? Task::RecruitType::BUILDPOWER : Task::RecruitType::FIREPOWER,
		Task::Priority::NORMAL, bestDef, fpos, fac.circuitDef.GetRadius()));
}
// our army's share of control: our strength (armed units and commander) against theirs, as seen (unseen: at least
// ours), on the linear share below
float ArmyControl(bool home = false)
{
	float S = 0.f, E = 0.f;
	const array<CCircuitUnit@>@ mine = AiGetTeamUnits();
	for (uint i = 0; i < mine.length(); ++i) {
		const CCircuitDef@ d = mine[i].circuitDef;
		const bool tower = home && !d.IsMobile() && d.GetSustainedDps() > 0.f;
		if (!IsArmy(d) && mine[i] !is commander && !tower) continue;
		S += sqrt(AiMax(0.f, d.GetSustainedDps()) * AiMax(1.f, d.health));
	}
	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
	const uint ne = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	for (uint i = 0; i < ne; ++i)
		if (ed[i] !is null && ed[i].IsMobile() && ed[i].GetSustainedDps() > 0.f) E += sqrt(ed[i].GetSustainedDps() * AiMax(1.f, eh[i] * ed[i].health));
	return WinShare(S, AiMax(E, S));
}
// The share of what is contested that strength S holds against E. Fights come piecemeal (raids, local fights),
// where each unit adds in proportion (Lanchester's linear law); the square law over one big battle made a small army
// worth nothing at the margin exactly when it was behind (S 56 vs E 364: 39 Fleas instead of fighters, Eye of Horus
// 2026-11-25). The square law still decides whether a fight is taken (Command).
// Chance a shot lands on a moving target: instant weapons (shot speed 0) always; else the target's radius over how far it
// moves while the shot flies the weapon's range (unit facts: shot speed, range, target speed and size).
// The enemy ground units a fighter of ours will meet, weighted by strength: as seen; none seen yet, the units the
// given factory options field (they build the same class of units). Shared by Production and the factory choice.
class Mix { array<float> dps, range, w, aoe, shot, speed, rad, cnt; }  // cnt: enemy units an entry stands for (0: hypothetical)
void FillMix(Mix@ m, const array<string>@ opts)
{
	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
	const uint ne = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	for (uint i = 0; i < ne; ++i) {
		const CCircuitDef@ d = ed[i];
		if (d is null || !d.IsMobile() || d.IsAbleToFly() || d.GetSustainedDps() <= 0.f) continue;
		m.dps.insertLast(d.GetSustainedDps()); m.range.insertLast(d.GetMaxRange()); m.aoe.insertLast(d.GetAoe());
		m.shot.insertLast(d.GetShotSpeed()); m.speed.insertLast(d.speed); m.rad.insertLast(d.GetRadius());
		m.w.insertLast(sqrt(d.GetSustainedDps() * AiMax(1.f, d.health)));
		m.cnt.insertLast(1.f);
	}
	if (m.w.length() == 0 && opts !is null) {
		for (uint i = 0; i < opts.length(); ++i) {
			CCircuitDef@ d = ai.GetCircuitDef(opts[i]);
			if (d is null || !d.IsMobile() || d.IsAbleToFly() || d.GetSustainedDps() <= 0.f || d.IsRoleAny(Unit::Role::BUILDER.mask)) continue;
			m.dps.insertLast(d.GetSustainedDps()); m.range.insertLast(d.GetMaxRange()); m.aoe.insertLast(d.GetAoe());
			m.shot.insertLast(d.GetShotSpeed()); m.speed.insertLast(d.speed); m.rad.insertLast(d.GetRadius()); m.w.insertLast(1.f);
			m.cnt.insertLast(0.f);
		}
	}
}
// A unit's ground fighting power against the mix, sqrt(dps landed x health in the fight), from unit facts:
//  - range gap: a unit outranged takes their fire while it closes: its health is less that damage;
//  - splash: one shot hits ~(aoe / two of our radii)^2 of a squad, at least one (44 Pawns lost to Pounders in a
//    minute, Canis 2026-11-26); its health is divided by the hits a shot makes;
//  - dodging: a shell fired at range R with speed v lands R/v later; a target of radius r moving at u has moved u*R/v,
//    so it is hit with chance ~ r / max(r, u*R/v) (instant weapons always hit) - for our shots and theirs.
// (Without these, sqrt(dps x health) per metal made the Flea our best fighter: 14-16 per game, short test s32.)
// metal fielded per our army type (all built), for the live efficiency: damage dealt per metal invested in the type
dictionary builtMetal;
void OnBuilt(CCircuitUnit@ u)
{
	if (!IsArmy(u.circuitDef) || u.circuitDef.GetSustainedDps() <= 0.f) return;
	double m = 0; if (!builtMetal.get(u.circuitDef.GetName(), m)) m = 0;
	builtMetal.set(u.circuitDef.GetName(), m + double(u.circuitDef.costM));
}
// A type's measured efficiency against the mean of our fielded types: (its damage dealt per metal fielded) / (all
// types' dealt per metal). The trade ratio (dealt / received) missed that a cheap unit dies cheaply and a heavy one keeps
// shooting: rc2, 6 Centurions ~10.6 damage per metal, 62 Pawns ~2.3 - 4.5x - while the sqrt-of-trade correction gave
// the Centurion x1.28 and the lab kept making Pawns (#116). 1 until the type has fought (taken a unit's health).
float LiveEfficiency(const CCircuitDef@ d)
{
	double mine = 0; if (!builtMetal.get(d.GetName(), mine)) mine = 0;
	if (mine <= 0.0 || AiDamageReceived(d.GetName()) < d.health) return 1.f;
	float dealtAll = 0.f, metalAll = 0.f;
	const array<string>@ ks = builtMetal.getKeys();
	for (uint q = 0; q < ks.length(); ++q) {
		double mm = 0; if (!builtMetal.get(ks[q], mm)) mm = 0;
		CCircuitDef@ kd = ai.GetCircuitDef(ks[q]);
		if (kd is null || AiDamageReceived(ks[q]) < kd.health) continue;  // only types that have fought
		dealtAll += AiDamageDealt(ks[q]); metalAll += float(mm);
	}
	if (dealtAll <= 0.f || metalAll <= 0.f) return 1.f;
	return (AiDamageDealt(d.GetName()) / float(mine)) / (dealtAll / metalAll);
}
int armyCountFrame = -1; float armyCount = 0.f;
float OurArmyCount()
{
	if (armyCountFrame == ai.frame) return armyCount;
	armyCountFrame = ai.frame; armyCount = 0.f;
	const array<CCircuitUnit@>@ mine = AiGetTeamUnits();
	for (uint i = 0; i < mine.length(); ++i) if (IsArmy(mine[i].circuitDef) && mine[i].circuitDef.GetSustainedDps() > 0.f) armyCount += 1.f;
	return armyCount;
}
float SurfPower(const CCircuitDef@ d, Mix@ m, string& out terms)
{
	// #116 design (1): against an enemy that outranges us and is at least as fast, we never close - it backs off and
	// fires; our power against it is nothing, not "a little less" (gapDmg). The share of the mix (by weight) we can
	// reach scales our power. Pawns (180, speed 87) against Mists (700) and Wolverines (710) traded 0.31-0.65 (REPLAYS.md)
	float reachW = 0.f, allW = 0.f;
	for (uint k = 0; k < m.w.length(); ++k) {
		allW += m.w[k];
		if (!(m.range[k] > d.GetMaxRange() && m.speed[k] >= d.speed)) reachW += m.w[k];
	}
	const float reachShare = (allW > 0.f) ? reachW / allW : 1.f;
	if (reachShare <= 0.f) { terms = "(unreachable: outranged and outrun)"; return 0.f; }
	const float hp = AiMax(1.f, d.health);
	float gapDmg = 0.f, wSum = 0.f, landW = 0.f, dpsW = 0.f, hitsW = 0.f, inW = 0.f;
	const float spacing = AiMax(1.f, 2.f * d.GetRadius());
	for (uint k = 0; k < m.w.length(); ++k) {
		gapDmg += m.w[k] * m.dps[k] * AiMax(0.f, m.range[k] - d.GetMaxRange()) / AiMax(1.f, d.speed);
		const float hk = AiMax(1.f, (m.aoe[k] / spacing) * (m.aoe[k] / spacing));
		const float tk = HitChance(m.shot[k], m.range[k], d.speed, d.GetRadius());
		landW += m.w[k] * HitChance(d.GetShotSpeed(), d.GetMaxRange(), m.speed[k], m.rad[k]);
		// what reaches us is each enemy's damage x the units its blast hits x its hit chance, so splash and dodging are
		// weighted by the damage each enemy deals, not by its share of the mix: averaged by share, the Leveler's 144-elmo
		// blast (unit facts) read 1.0 among Gators while Levelers dealt 39% of all damage we took (op3-6)
		dpsW += m.w[k] * m.dps[k];
		hitsW += m.w[k] * m.dps[k] * hk;
		inW += m.w[k] * m.dps[k] * hk * tk;
		wSum += m.w[k];
	}
	if (wSum > 0.f) gapDmg /= wSum;
	// #116: every enemy in range fires on the squad while it closes, shared among our units - the sum over the enemy
	// units the mix stands for (cnt) over our army's count; as a strength-weighted average one Pawn closing on a line of
	// artillery read like facing one gun (Pawns traded 0.40-0.69 walking in, cb1-2). Hypothetical mixes keep the average.
	{
		float cntSum = 0.f, fire = 0.f;
		for (uint k = 0; k < m.cnt.length() && k < m.dps.length(); ++k) {
			cntSum += m.cnt[k];
			fire += m.cnt[k] * m.dps[k] * AiMax(0.f, m.range[k] - d.GetMaxRange()) / AiMax(1.f, d.speed);
		}
		if (cntSum > 0.f) gapDmg = fire / AiMax(1.f, OurArmyCount());
	}
	const float hits = (dpsW > 0.f) ? hitsW / dpsW : 1.f;  // (logged) splash hits per shot, damage-weighted
	const float land = (wSum > 0.f) ? landW / wSum : 1.f;
	const float taken = (dpsW > 0.f) ? AiMax(1e-3f, inW / AiMax(1e-3f, hitsW)) : 1.f;  // hit chance, damage x splash weighted
	const float hpSurf = AiMax(1.f, (hp - gapDmg) / hits / taken);
	float mixDps = 0.f;
	for (uint k = 0; k < m.w.length(); ++k) mixDps += m.w[k] * m.dps[k];
	mixDps = (wSum > 0.f) ? mixDps / wSum : 0.f;
	float power = sqrt(AiMax(0.f, d.surfThrDmg) * land * hpSurf);
	// Live trade, once this type has taken a unit's worth of damage (enough to mean something): damage dealt over taken
	// in this game, against the model's own (our dps x our hit chance) / (their dps x splash hits x their hit chance).
	// Modelled, Pawns dodged half the shells; live, Levelers dealt them 14709 by minute 11 (cmd_m86) and killed 130 in a
	// game (cmd_m75). Fighting value goes with sqrt of the trade (square law), so the correction is sqrt(live / model).
	const float rec = AiDamageReceived(d.GetName()), dealt = AiDamageDealt(d.GetName());
	string live = "";
	if (rec >= hp && mixDps > 0.f) {
		// in damage per second on both sides (surfThrDmg is the core's threat-weighted figure: with it the model read
		// ~0.004, the correction multiplied the Pawn ~10x and 93 Pawns died to Levelers, cmd_m88)
		const float model = AiMax(0.f, d.GetSustainedDps()) * land / AiMax(1e-3f, mixDps * hits * taken);
		const float meas = dealt / rec;
		const float eff = LiveEfficiency(d);
		power *= eff;
		live = " live " + F2(meas) + "/" + F2(model) + " eff x" + F2(eff);
	}
	terms = "(hits " + F2(land) + " taken " + F2(taken) + " splash " + F2(hits) + " gapDmg " + int(gapDmg) + live + (reachShare < 1.f ? " reach " + F2(reachShare) : "") + ")";
	return power * reachShare;
}
float HitChance(float shotSpeed, float range, float targetSpeed, float targetRadius)
{
	if (shotSpeed <= 0.f) return 1.f;
	const float drift = targetSpeed * range / shotSpeed;
	return AiMin(1.f, AiMax(1.f, targetRadius) / AiMax(AiMax(1.f, targetRadius), drift));
}
float WinShare(float S, float E) { return (S + E > 0.f) ? S / (S + E) : 0.f; }
// Granularity (#101, owner: "2 units that each have 500 hp are worse than one unit with 1000 hp because the latter's
// damage output doesn't drop"): under focus fire n equal units die one after another and deliver dps x time
// (n+1)/(2n) of one undivided unit with their total dps and health; strength (sqrt of dps x health delivered) scales by
// the square root of that. n = 1: 1; 2: 0.87; many: 0.71.
float Gran(float n) { const float m = AiMax(1.f, n); return sqrt((m + 1.f) / (2.f * m)); }

float lastBestRatio = 0.f;  // production's best value per metal at its last fighter pick (what army metal buys now)
float peakE = 0.f, growthE = 0.f; int peakFrame = -1;
dictionary memMax, memFrame;  // enemy type -> most seen at once; frame of that sighting  // strongest enemy surface strength seen, its measured growth /s
string Status() { return "moho=" + mohoCons + "(" + mohoWhy + ") prod=" + choices + "/b" + builders + " rez=" + rezBots.length() + "/" + rezOrders + " last=" + last; }

}  // namespace Production

/* ======================================================================== */
/*
 * Economist: the shared valuation every decision uses. No hand-picked cutoffs: investments are judged
 * by payback time against a planning horizon derived from the live situation, and energy is priced in
 * metal at the exchange rate of the converters we can build (read from their defs).
 */
namespace Economist {

array<CCircuitDef@> mexDefs;
array<CCircuitUnit@> mexes;
CCircuitDef@ mexT1, mexT2, makerDef;
float energyPerMetal = 0.f;   // converter exchange rate, from defs
/*
 * Metal per second an extractor makes per unit of a spot's income: extractsMetal x the scale the engine actually
 * applies, measured from our own extractors (their output now / spot income x extractsMetal). The spot "income" is
 * BAR's metal value, not metal per second: taken as such, every extractor was valued at ~1/9 of its output (0.2
 * against 1.9 measured in our game and 1.80 median in 848 player-minutes of 1v1 replays). Until our first extractor
 * reports, the scale that makes an average spot give that replay median.
 */
float extractorScale = 0.f;
float Extract(const string& in name) { return Facts::ExtractsMetal(name) * AiMax(1e-6f, extractorScale); }
void MeasureExtraction()
{
	array<AIFloat3> sp; array<float> si; array<bool> so;
	const uint n = AiGetMetalSpots(sp, si, so);
	if (extractorScale <= 0.f && mexT1 !is null && n > 0) {
		float sum = 0.f;
		for (uint i = 0; i < n; ++i) sum += si[i];
		const float avg = sum / float(n);
		const float replayMedian = 1.80f;  // metal/s per extractor, 1v1 replays.db (measured, minutes 3-6, n=848)
		extractorScale = replayMedian / AiMax(1e-6f, avg * Facts::ExtractsMetal(mexT1.GetName()));
	}
	float actual = 0.f, predicted = 0.f;
	for (uint k = 0; k < mexes.length(); ++k) {
		const float a = mexes[k].GetMetalMake();
		if (a <= 0.f) continue;  // not extracting yet (just built, or stalled)
		const AIFloat3 p = mexes[k].GetPos(ai.frame);
		int best = -1; float bd = 1e30f;
		for (uint i = 0; i < n; ++i) { const float d = sp[i].distance2D(p); if (d < bd) { bd = d; best = int(i); } }
		if (best < 0) continue;
		actual += a;
		predicted += si[best] * Facts::ExtractsMetal(mexes[k].circuitDef.GetName());
	}
	if (predicted > 0.f) extractorScale = actual / predicted;
	aiEconomyMgr.SetExtractorScale(extractorScale);
}
// Game facts the script API doesn't expose (from unitdefs: extractsmetal / energyupkeep). Not tunables.
// extractor facts from the unit files (extractsmetal relative to T1, energy upkeep E/s)
float MexExtract(const CCircuitDef@ d) { return (d is null) ? 0.f : Facts::ExtractsMetal(d.GetName()); }
float MexUpkeep(const CCircuitDef@ d) { return (d is null) ? 0.f : Facts::EnergyUpkeep(d.GetName()); }
float lastEnemySeen = 0.f;    // for when we're blind

void Init()
{
	mexDefs = Defs({"armmex", "cormex", "legmex", "armamex", "armmoho", "cormoho", "legmoho", "cormexp", "armuwmex",
		"coruwmex", "armuwmme", "coruwmme"});
	@mexT1 = Brain::Strategic::Side("armmex", "cormex", "legmex");
	@mexT2 = Brain::Strategic::Side("armmoho", "cormoho", "legmoho");
	Facts::InitConverters();  // ConverterUse needs the table even when the defs give the rate
	@makerDef = Brain::Strategic::Side("armmakr", "cormakr", "legeconv");
	if (makerDef !is null) {
		const float mm = aiEconomyMgr.GetMetalMake(makerDef);
		const float em = aiEconomyMgr.GetEnergyMake(makerDef);
		if (mm > 0.f && em < 0.f)
			energyPerMetal = -em / mm;
	}
	if (energyPerMetal <= 0.f && makerDef !is null) {
		// the defs don't expose it: the maker's unit file (energyconv_efficiency = metal per energy)
		Facts::InitConverters();
		Facts::SConv@ c = Facts::Converter(makerDef.GetName());
		if (c !is null && c.eff > 0.f)
			energyPerMetal = 1.f / c.eff;
	}
	MeasureExtraction();
	AiLog("[ANV] Economist: converter rate " + F1(energyPerMetal) + " E per M, extractor scale " + F2(extractorScale));
}

void OnFinished(CCircuitUnit@ u) { if (InList(mexDefs, u.circuitDef)) mexes.insertLast(u); }
void OnDestroyed(CCircuitUnit@ u) { RemoveUnit(mexes, u); }

float MetalValue(const CCircuitDef@ d) { return d.costM + d.costE / energyPerMetal; }
// What a unit costs us now (owner: unit types differ hugely in energy draw): energy at the converter rate while it is
// in surplus, at the metal we can match it with (metal income / energy income) while it binds (stall, or pulled
// faster than it comes in) - an energy-heavy unit then costs the production it takes away.
float EnergyPrice()
{
	const float conv = 1.f / AiMax(1e-3f, energyPerMetal);
	const bool binds = aiEconomyMgr.isEnergyStalling || aiEconomyMgr.energy.pull > aiEconomyMgr.energy.income;
	if (!binds) return conv;
	return AiMax(conv, aiEconomyMgr.metal.income / AiMax(1e-3f, aiEconomyMgr.energy.income));
}
float CostNow(const CCircuitDef@ d) { return d.costM + d.costE * EnergyPrice(); }
// what a building is worth to whoever owns it: its cost plus what it yields over the horizon (extraction at the map's
// mean spot, metal make, energy make or negative upkeep at the converter rate) - one valuation for ours and theirs
float AssetValue(const CCircuitDef@ d)
{
	if (d is null) return 0.f;
	const string nm = d.GetName();
	float spotM = 0.f;
	{
		array<AIFloat3> sp; array<float> si; array<bool> so;
		const uint ns = AiGetMetalSpots(sp, si, so);
		float sum = 0.f;
		for (uint i = 0; i < ns; ++i) sum += si[i];
		spotM = (ns > 0) ? sum / float(ns) : 0.f;
	}
	const float upkeep = Facts::EnergyUpkeep(nm);
	const float eYield = Facts::EnergyMake(nm) + ((upkeep < 0.f) ? -upkeep : 0.f);
	const float yield = Economist::Extract(nm) * spotM + Facts::MetalMake(nm) + eYield / AiMax(1e-3f, energyPerMetal);
	return MetalValue(d) + ((yield > 0.f) ? yield * Horizon() : 0.f);
}

// Planning horizon (s): how long what we own keeps paying (see below).
float Horizon()
{
	// How long what we own keeps paying before the enemy can take it: the time they need to build a force worth all
	// we own (our metal / their income; unseen, each enemy earns as fast as we do), plus the time to cross the map.
	// (The old "as long as the game has run" was 0 s at start, so every future value read 0 and the AI reclaimed its
	// own wind turbines.)
	float V = Brain::Strategic::ownedMetal;
	if (Brain::commander !is null)
		V = AiMax(V, Brain::commander.circuitDef.costM);
	// at least what a commander makes (unit fact): before the first economy tick the income read 0 and the horizon
	// came out at 2.7 million s, which made every opening plan and start candidate look alike
	float ourInc = aiEconomyMgr.metal.income;
	const CCircuitDef@ com = (Brain::commander !is null) ? Brain::commander.circuitDef : aiSetupMgr.commChoice;
	if (com !is null) ourInc = AiMax(ourInc, Facts::MetalMake(com.GetName()));
	const float theirInc = AiMax(Brain::EcoPos::theirs, ourInc * float(AiMax(1, ai.GetEnemyTeamSize())));
	const float cross = AiTerrainDiagonal() / AiMax(1.f, Brain::Director::allSpeed);
	return V / AiMax(1e-3f, theirInc) + cross;
}

// How long a producing building (extractor, energy plant) of ours actually lives in this game: building-seconds
// survived / buildings lost (the exponential-lifetime estimate). The threat horizon above is the earliest the enemy
// could take everything, a floor; valuing extractors over it alone (~160 s by minute 8) made resurrecting a wreck
// worth more than a new extractor while the winners hold 17-19 extractors at minutes 8-10 (Eye of Horus 1v1).
float producerExposure = 0.f;  // building-seconds
int producerLosses = 0;
int producerFrame = -1;
bool IsProducer(const CCircuitDef@ d)
{
	if (d is null || d.IsMobile()) return false;
	const string nm = d.GetName();
	return Facts::ExtractsMetal(nm) > 0.f || Facts::EnergyMake(nm) > 0.f || Facts::EnergyUpkeep(nm) < 0.f;
}
// ...split by cover: a producer one of our armed buildings has in range, or not. What a tower adds is the difference
// (measured in this game, not assumed): with one life for all, raids made every extractor look break-even and towers
// never paid (1-4 by 8:00 vs the winners' 6.2; cmd_m42).
float coveredExposure = 0.f, uncoveredExposure = 0.f;
int coveredLosses = 0, uncoveredLosses = 0;
bool Covered(const AIFloat3& in p, const array<CCircuitUnit@>@ mine)
{
	for (uint k = 0; k < mine.length(); ++k) {
		const CCircuitDef@ d = mine[k].circuitDef;
		if (!d.IsMobile() && d.surfThrDmg > 0.f && mine[k].GetPos(ai.frame).distance2D(p) <= d.GetMaxRange()) return true;
	}
	return false;
}
void UpdateProducerLife()
{
	const int f = ai.frame;
	if (producerFrame >= 0) {
		int n = 0, nc = 0;
		const array<CCircuitUnit@>@ mine = AiGetTeamUnits();
		for (uint i = 0; i < mine.length(); ++i) {
			if (!IsProducer(mine[i].circuitDef)) continue;
			++n;
			if (Covered(mine[i].GetPos(f), mine)) ++nc;
		}
		const float dt = float(f - producerFrame) / SECOND;
		producerExposure += float(n) * dt;
		coveredExposure += float(nc) * dt;
		uncoveredExposure += float(n - nc) * dt;
	}
	producerFrame = f;
}
float producerLostMetal = 0.f;  // metal of producers the enemy killed (feedback: what raids take, measured)
float LossRate() { return producerLostMetal / AiMax(1.f, float(ai.frame) / SECOND); }
// where producers die: position, metal, and the raiders there (strength sqrt(dps x hp) and dps of the enemies in reach)
array<AIFloat3> lossPos; array<float> lossM, lossE, lossD;
void OnProducerLost(CCircuitUnit@ u)
{
	++producerLosses;
	producerLostMetal += MetalValue(u.circuitDef);
	{
		const AIFloat3 p = u.GetPos(ai.frame);
		float E = 0.f, D = 0.f;
		array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
		const uint ne = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
		for (uint i = 0; i < ne; ++i) {
			const CCircuitDef@ d = ed[i];
			if (d is null || !d.IsMobile() || d.GetSustainedDps() <= 0.f || ep[i].distance2D(p) > d.GetMaxRange() + d.GetRadius() + u.circuitDef.GetRadius()) continue;
			E += sqrt(d.GetSustainedDps() * AiMax(1.f, eh[i] * d.health)); D += d.GetSustainedDps();
		}
		// what the loss cost: its metal and its yield until it stands again (MexPorc::RaidLoss), not its price alone -
		// at 50 a lost extractor, pickets rarely beat a unit's place in the army: 0-2 pickets while 15 of 22 extractors
		// built from 4 to 12 min died (kt1)
		lossPos.insertLast(p); lossM.insertLast(AiMax(MetalValue(u.circuitDef), MexPorc::RaidLoss(u, EcoPos::CheapestConstructor()))); lossE.insertLast(E); lossD.insertLast(D);
	}
	if (Covered(u.GetPos(ai.frame), AiGetTeamUnits())) ++coveredLosses; else ++uncoveredLosses;
}
float CoveredLife() { return (coveredLosses > 0) ? coveredExposure / float(coveredLosses) : AiMax(coveredExposure, ProducerLife()); }
float UncoveredLife() { return (uncoveredLosses > 0) ? uncoveredExposure / float(uncoveredLosses) : AiMax(uncoveredExposure, ProducerLife()); }
// The share of the metal we have to spend (income, plus the bank over the value horizon once a factory has produced)
// that we actually spend (smoothed pull) - the builders' metal price (core pM). More metal is worth only that share.
float MetalShare()
{
	bool producing = false;
	const array<CCircuitUnit@>@ mine = AiGetTeamUnits();
	for (uint i = 0; i < mine.length() && !producing; ++i)
		producing = mine[i].circuitDef.IsMobile() && mine[i] !is Brain::commander;
	const float bank = producing ? aiEconomyMgr.metal.current / AiMax(1.f, ProducerLife()) : 0.f;
	const float avail = aiEconomyMgr.metal.income + bank;
	return (avail > 0.f) ? AiMin(1.f, AiSmoothMetalPull() / avail) : 1.f;
}
// The life we have measured, without the horizon floor: exposure / losses, or before any loss the mean age so far.
// For a decision that pays only if producers live long (tier 2): floored by Horizon() - huge early, when the enemy has
// no army yet - the upgrades read 36x at 1:48 and the lab took the army's metal (as4).
float MeasuredLife()
{
	if (producerLosses > 0) return producerExposure / float(producerLosses);
	int n = 0;
	const array<CCircuitUnit@>@ mine = AiGetTeamUnits();
	for (uint i = 0; i < mine.length(); ++i) if (IsProducer(mine[i].circuitDef)) ++n;
	return producerExposure / float(AiMax(1, n));
}
float ProducerLife()
{
	const float floorH = Horizon();
	if (producerLosses > 0) return AiMax(floorH, producerExposure / float(producerLosses));
	// none lost yet: what we know is that a producer lives at least its mean age so far - the exposure is the sum over
	// all of them (as a life it read 10575 s at 2:00 and opened tier 2 at 36x; the lab took the army's metal until 8:52,
	// t2a)
	int n = 0;
	const array<CCircuitUnit@>@ mine = AiGetTeamUnits();
	for (uint i = 0; i < mine.length(); ++i) if (IsProducer(mine[i].circuitDef)) ++n;
	return AiMax(floorH, producerExposure / float(AiMax(1, n)));
}

// Enemy mobile threat; when we see nothing, assume they grew at least as fast as we did.
int knownThreatFrame = -1; float knownThreat = 0.f;
float KnownEnemyThreat()
{
	if (knownThreatFrame == ai.frame) return knownThreat;
	knownThreatFrame = ai.frame;
	knownThreat = 0.f;
	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
	const uint n = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	for (uint i = 0; i < n; ++i)
		if (ed[i] !is null && ed[i].IsMobile() && ed[i].surfThrDmg > 0.f) knownThreat += ed[i].threat;
	return knownThreat;
}
float EnemyThreat()
{
	// Each known enemy once, same measure as ours (CCircuitDef threat). The core's running mobileThreat grew with
	// re-identifications and unseen deaths: 173 for 11 known units while our ~60 read 47 (Throne 2026-11-25), so a
	// bigger army read r=0.3 and never attacked or expanded.
	const float seen = KnownEnemyThreat();
	if (seen > 1.f)
		lastEnemySeen = seen;
	return Brain::Director::blind ? AiMax(lastEnemySeen, Brain::Director::OurPower()) : seen;
}

// Energy our converters draw now (unit files: energyconv_capacity per converter). Converters eat exactly the surplus,
// so income - pull hides it; every surplus/deficit test uses RealPull() = pull without them (owner, #83).
float ConverterUse()
{
	float use = 0.f;
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	for (uint i = 0; i < all.length(); ++i) {
		if (all[i].circuitDef.IsMobile()) continue;
		Facts::SConv@ c = Facts::Converter(all[i].circuitDef.GetName());
		if (c !is null) use += c.capE;
	}
	return AiMin(use, aiEconomyMgr.energy.pull);
}
float RealPull() { return AiMax(0.f, aiEconomyMgr.energy.pull - ConverterUse()); }

// Payback of the next T1 extractor we could still claim on our side (cost / its spot's income); none left: never
float NextMexPayback()
{
	if (mexT1 is null) return 1e9f;
	array<AIFloat3> sp; array<float> si; array<bool> so;
	const uint n = AiGetMetalSpots(sp, si, so);
	float best = 0.f;
	for (uint i = 0; i < n; ++i)
		if (so[i] && Brain::Assess::OnOurSide(sp[i]))
			best = AiMax(best, si[i]);
	const float inc = best * MexExtract(mexT1);
	if (inc <= 0.f) return 1e9f;
	return MetalValue(mexT1) / inc;
}

// Payback of upgrading every extractor we own: (lab + mohos) / (extra metal - upkeep priced in metal)
float MohoPayback(const CCircuitDef@ lab)
{
	if (mexT1 is null || mexT2 is null || mexes.length() == 0)
		return 1e9f;
	const float n = float(mexes.length());
	// extractor income only: what the commander makes on its own isn't upgraded (with 2 extractors it was ~40% of
	// income and made a T2 lab look paid back at minute 3, smoke 2026-11-25)
	float own = 0.f;
	if (Brain::commander !is null)
		own = Facts::MetalMake(Brain::commander.circuitDef.GetName());  // unit-file metalmake
	const float perMex = AiMax(0.f, aiEconomyMgr.metal.income - own) / n;  // still an upper bound: includes reclaim
	const float extraM = perMex * (MexExtract(mexT2) / AiMax(1e-9f, MexExtract(mexT1)) - 1.f);
	const float upkeepM = (MexUpkeep(mexT2) - MexUpkeep(mexT1)) / AiMax(1e-3f, energyPerMetal);
	const float gain = n * (extraM - upkeepM);
	if (gain <= 0.f)
		return 1e9f;
	// the upgrades need the lab's constructor too, and nothing is earned until lab, constructor and upgrades stand:
	// the lab at our build power now, the constructor at the lab's, the n upgrades at the constructor's (unit facts).
	// (Cost alone read 220 s at 2:00 with 5 extractors; the lab then took the army's metal until 8:54, t2a/t2c.)
	float conCost = 0.f, conTime = 0.f, mohoTime = 0.f;
	const array<string> lo = Facts::BuildOptions(lab.GetName());
	for (uint i = 0; i < lo.length(); ++i) {
		CCircuitDef@ c = ai.GetCircuitDef(lo[i]);
		if (c is null || !c.IsMobile() || c.buildSpeed <= 0.f || !c.CanBuild(mexT2)) continue;
		if (conCost == 0.f || MetalValue(c) < conCost) {
			conCost = MetalValue(c);
			conTime = c.buildTime / AiMax(1.f, lab.buildSpeed);
			// each upgrade earns from when it stands: the k-th at k x tau, on average (n+1)/2 x tau; and every builder joins
			// them (#102, owner: "assisted by every t1 con and tower"), so tau is its build time at all our build power.
			// (All n done by one constructor before any earned read 1251-1820 s and returns 0.00x all game, as2/as3.)
			const float tau = mexT2.buildTime / AiMax(c.buildSpeed, aiBuilderMgr.GetBuildPower());
			mohoTime = 0.5f * (n + 1.f) * tau;
		}
	}
	mohoReady = lab.buildTime / AiMax(1.f, aiBuilderMgr.GetBuildPower()) + conTime + mohoTime;
	return (MetalValue(lab) + conCost + n * MetalValue(mexT2)) / gain;
}
float mohoReady = 0.f;  // seconds until the upgrade path earns (set by MohoPayback)

}  // namespace Economist

/* ======================================================================== */
/*
 * Tech gate: T2/T3 is an investment that pays later and costs army now. Weighed against the
 * situation and the clock: income able to carry the tier, not being pushed back, holding parity,
 * game time, and whether the enemy has teched already (then we must follow).
 */
namespace Tech {

int lastLog = 0;

// Tier from unit facts: a factory's build depth from the commander (gen_facts.py: the commander's labs are 1, a lab
// built by a tier-t constructor is t + 1). No name lists. A unit that is no factory counts as tier 1.
int Tier(const CCircuitDef@ d)
{
	if (d is null) return 0;
	const int t = int(Facts::FactoryTier(d.GetName()));
	return (t > 0) ? t : 1;
}
float lastT2Return = 0.f;  // the tier-2 gate's measured return per metal (the lab job carries it: AiTaskAdded)
int TierWeHave()
{
	int t = 0;
	for (uint i = 0; i < Brain::Intel::allFactories.length(); ++i) t = AiMax(t, Tier(Brain::Intel::allFactories[i].circuitDef));
	return t;
}

// Tech decision, always live (no flag, no clock): a lower or equal tier is always allowed; a higher tier when it pays.
bool Allowed(const CCircuitDef@ facDef)
{
	const int tier = Tier(facDef);
	const bool t3 = tier >= 3;
	const bool t2 = tier == 2;
	if (!t2 && !t3)
		return true;
	const float H = Brain::Economist::Horizon();
	string why;
	bool ok;
	if (t2) {
		// T2 pays through moho upgrades on the extractors we actually own; if the enemy has teched,
		// our T1 army is losing value and teching becomes a necessity, not an investment.
		const float payback = Brain::Economist::MohoPayback(facDef);
		const bool forced = aiEnemyMgr.GetEnemyCost(RT::HEAVY) > 0.f && Brain::Director::ratio < 1.f;
		// Investments go in order of return rate: the upgrade must also beat the next T1 extractor we could still
		// claim on our side (its income / its cost). (Payback inside the horizon alone bought a T2 lab at 2:20 with
		// 3 extractors, ~13x worse per metal than expanding: smoke 2026-11-25.)
		const float mexBack = Brain::Economist::NextMexPayback();
		// The extractor is only the alternative when both compete for the same metal: with the lab's cost already
		// banked, buying it takes nothing from the extractors (one lab sat on 4600 metal for 20 min, Throne 2026-11-25).
		// paid while it is built: what we hold plus the income we don't spend during its build (the bank alone could
		// never hold it - the advanced lab costs more than our whole storage, cmd_m125)
		const float tBuild = facDef.buildTime / AiMax(1.f, aiBuilderMgr.GetBuildPower());
		const float surplus = AiMax(0.f, aiEconomyMgr.metal.income - AiSmoothMetalPull());
		const bool banked = aiEconomyMgr.metal.current + surplus * tBuild >= Brain::Economist::MetalValue(facDef);
		// The metal the upgrade path takes would otherwise go where production spends it: the army, at production's best
		// value per metal now. (Against "banked or faster than the next extractor", tier 2 never came - production spends
		// all income, so nothing banks, and a 50-metal extractor always pays back faster though spots, not metal, limit
		// extractors: "payback 176s vs horizon 226s, next extractor 28s", 64 M/s at 12:00, sp2.) The upgrade returns its
		// producers' life over its payback per metal; it goes when that beats the army's value per metal and returns
		// more than it costs.
		const float life = Brain::Economist::MeasuredLife();
		const float ret = AiMax(0.f, life - Brain::Economist::mohoReady) / AiMax(1.f, payback);  // earns only once it stands
		lastT2Return = ret;
		const float armyRet = Brain::Production::lastBestRatio;
		// (no fighter priced yet: the army's worth is unknown, so it can't be beaten - it read 0 and tier 2 began at 2:00)
		ok = (armyRet > 0.f && ret > 1.f && ret > armyRet) || banked || forced;
		why = "payback " + int(payback) + "s after " + int(Brain::Economist::mohoReady) + "s to build, producer life " + int(life) + "s: returns " + F2(ret) + "x per metal vs the army's " + F2(armyRet)
			+ (banked ? ", banked" : "") + ", next extractor " + (mexBack >= 1e9f ? "none" : (int(mexBack) + "s")) + (forced ? ", enemy teched" : "");
	} else {
		// T3: when the enemy fields super units while we're not ahead and must answer in kind.
		const bool enemySuper = aiEnemyMgr.GetEnemyCost(RT::SUPER) > 0.f && Brain::Director::ratio < 1.f;
		ok = enemySuper;
		why = enemySuper ? "enemy fields super units" : "no super units to answer";
	}
	if (ai.frame - lastLog > MINUTE || ok) {
		lastLog = ai.frame;
		AiLog("[ANV] Tech: " + (ok ? "building " : "not yet ") + facDef.GetName() + " (" + why + ")");
	}
	return ok;
}
}  // namespace Tech

/* ======================================================================== */
/*
 * Assessment: how are we doing? Pushing or being pushed back, trading efficiently or not,
 * investing well or stalling. Feeds the Director.
 *  - front: where our losses happen (near base = pushed back, far = pushing), EMA of loss distance
 *  - trade: metal we lose vs the drop in the enemy's known value over the same window (kill proxy;
 *           the script API has no enemy-death event)
 *  - investing: metal income growth over the last 3 minutes
 */
namespace Assess {

float lostNear = 0.f, lostFar = 0.f, killed = 0.f, frontDist = 0.f;
float frontW = 0.f, frontWD = 0.f;  // metal lost (mobile) and metal x distance from base, decayed on the horizon
float lostNearTotal = 0.f;  // never decays: has anything come at us since X?
float lostFarTotal = 0.f, killedTotal = 0.f;  // never decay: wrecks stay on the map
float enemyPrev = -1.f;
bool pushedBack = false, pushing = false;
float trade = 1.f;
// Where exchanges happen (C++ bridge): our side of the map = closer to our base than to any known enemy
// building, the live midpoint of the territory (no distance constant). Kills are located: an enemy that
// leaves the core's list died, at its last known spot.
float killedHome = 0.f, killedAway = 0.f;
dictionary seen;  // enemy id -> last spot and cost
class SSeen { AIFloat3 pos; float cost; }
array<AIFloat3> enemyStatics;

bool OnOurSide(const AIFloat3& in p)
{
	if (!HasBase()) return true;
	const float dU = basePos.distance2D(p);
	if (enemyStatics.length() == 0) return dU < basePos.distance2D(AiEnemyBasePos());
	for (uint j = 0; j < enemyStatics.length(); ++j)
		if (enemyStatics[j].distance2D(p) < dU) return false;
	return true;
}

void TrackKills()
{
	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef, ids;
	const uint n = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	AiGetEnemyIds(ids);
	enemyStatics.resize(0);
	for (uint i = 0; i < n; ++i)
		if (ed[i] !is null && !ed[i].IsMobile()) enemyStatics.insertLast(ep[i]);
	// real kills only: the engine's enemy-destroyed events (an id vanishing from the known list also meant a ghost
	// pruned or an enemy out of sight: 17646 "killed" at minute 8 while BARb's buildings grew, Eye of Horus 1v1)
	array<AIFloat3> kp; array<float> km;
	const uint nk = AiDrainKills(kp, km);
	for (uint k = 0; k < nk; ++k) {
		if (OnOurSide(kp[k])) killedHome += km[k]; else killedAway += km[k];
		Command::CreditRaid(kp[k], km[k]);
	}
}

float EnemyValue()
{
	float v = aiEnemyMgr.GetEnemyCost(RT::STATIC);
	array<Type> rs = {RT::RAIDER, RT::ASSAULT, RT::SKIRM, RT::RIOT, RT::HEAVY, RT::ARTY, RT::AA, RT::SUPER, RT::AIR, RT::BUILDER};
	for (uint i = 0; i < rs.length(); ++i)
		v += aiEnemyMgr.GetEnemyCost(rs[i]);
	return v;
}

void OnLoss(CCircuitUnit@ unit)
{
	const CCircuitDef@ d = unit.circuitDef;
	// generators/makers the core recycles "die" too; never count them
	if (!d.IsMobile() && d.defDmg <= 0.f && aiEconomyMgr.GetEnergyMake(d) > 0.f)
		return;
	const float dist = HasBase() ? basePos.distance2D(unit.GetPos(ai.frame)) : 0.f;
	Brain::Strategic::OnTerrainLoss(unit.GetPos(ai.frame), d.costM);
	const bool home = OnOurSide(unit.GetPos(ai.frame));  // our side: closer to our assets than to theirs (no 1500-elmo ring)
	if (home) {
		lostNear += d.costM;
		lostNearTotal += d.costM;
	} else {
		lostFar += d.costM;
		lostFarTotal += d.costM;
	}
	if (d.IsMobile()) {
		frontW += d.costM;
		frontWD += d.costM * dist;
		frontDist = frontWD / AiMax(1e-3f, frontW);  // where our units die, by the metal lost there
	}
}

void Update()  // every second
{
	// Memory on the planning horizon itself (no hand-picked half-life): per second, evidence decays by e^(-1/H).
	const float H = AiMax(1.f, Brain::Economist::Horizon());
	const float decay = pow(2.71828183f, -1.f / H);  // e^(-1/H); the script math has pow, not exp
	lostNear *= decay;
	frontW *= decay;
	frontWD *= decay;
	lostFar *= decay;
	killedHome *= decay;
	killedAway *= decay;
	// Kills located through the bridge (enemy ids that vanish), no value-drop proxy with a cap.
	const float kh = killedHome, ka = killedAway;
	TrackKills();
	killedTotal += (killedHome - kh) + (killedAway - ka);
	killed = killedHome + killedAway;
	const float lost = lostNear + lostFar;
	// Evidence weighted by the army at stake: exchanges small next to what we'd risk can't swing the estimate.
	// The stake is all we own (commander, eco and army): before the first army unit it was 1, and a lost 40-metal
	// scout put the trade at 0.02 and the power we "need" x50 (smoke 2026-11-25).
	const float stake = AiMax(1.f, Brain::Strategic::ownedMetal);
	trade = (killed + stake) / (lost + stake);
	// Pushed back = home losses
	// over that window exceed what our income replaces in it; pushing = our losses happen mostly away from home.
	const float window = H;  // the evidence window is the horizon (see decay above)
	pushedBack = lostNear > aiEconomyMgr.metal.income * window;
	pushing = lostFar > lostNear && lostFar > aiEconomyMgr.metal.income * window;

}

string Status()
{
	return (pushedBack ? "PUSHED-BACK" : (pushing ? "PUSHING" : "holding")) + " trade=" + F1(trade)
		+ " kill(h/a)=" + int(killedHome) + "/" + int(killedAway)
		+ " lost(n/f)=" + int(lostNear) + "/" + int(lostFar) + " front=" + int(frontDist);
}

}  // namespace Assess

/* ======================================================================== */
/*
 * Director: every second it weighs our army against the enemy's known mobile threat at our trade rate.
 * The other modules read the ratio (ours / needed) and the needed power.
 */
namespace Director {

float ratio = 1.f;
bool blind = false;

// Everything of ours that fights on the surface. The gather pool alone drops every unit with a support,
// artillery or AA secondary role, which is most of a mixed army: measured 48 vs ~11k metal fielded.
float allPower = 0.f, allSpeed = 0.f;
int allPowerFrame = -1;
float MeasuredPower()
{
	if (allPowerFrame == ai.frame) return allPower;
	allPowerFrame = ai.frame;
	allPower = 0.f; allSpeed = 0.f; uint cnt = 0;
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	for (uint i = 0; i < all.length(); ++i) {
		const CCircuitDef@ d = all[i].circuitDef;
		// our commander counts like theirs does (aiEnemyMgr.mobileThreat includes the enemy commander, ~4 Pawns of threat)
		if (!d.IsMobile() || d.power <= 0.f || d.surfThrDmg <= 0.f) continue;
		if (d.IsRoleAny(Unit::Role::BUILDER.mask)) continue;
		// the same measure the enemy side is summed in (defThreat, aiEnemyMgr.mobileThreat): power carried another
		// config modifier, so a bigger army read r=0.3 and never attacked (1v1 Avalanche 2026-11-25: 1426 vs 1114 metal)
		allPower += d.threat;
		allSpeed += d.speed; ++cnt;
	}
	if (cnt > 0) allSpeed /= float(cnt);
	return allPower;
}
float OurPower() { return MeasuredPower(); }

float needPower = 0.f;   // army power needed to win against what we know (and guess) is out there

void Update()
{
	const float ours = OurPower();
	const float enemyStatic = aiEnemyMgr.GetEnemyCost(RT::STATIC);
	blind = Brain::Economist::KnownEnemyThreat() <= 0.f && enemyStatic <= 0.f;

	// What we must be able to beat: the known (or, when blind, assumed) enemy army plus the army we
	// guess is hidden under seen jammers, divided by how efficiently we are actually trading.
	const float theirs = Brain::Economist::EnemyThreat() + aiEnemyMgr.GetEnemyThreat(RT::JAMMER);
	needPower = theirs / AiMax(1e-3f, Brain::Assess::trade);  // numeric guard only
	// nothing to beat: we are at least even (0/1 read "weaker" and fortified a 1v1 at minute 0)
	ratio = (needPower <= 0.f) ? 1.f : ours / needPower;
}
string Status() { return "r=" + F1(ratio) + " need=" + int(needPower) + (blind ? " blind" : ""); }

}  // namespace Director

/* ======================================================================== */

bool inited = false;
const bool DUMP_DEFS = false;  // dev: log every UnitDef as the core sees it

void DumpDefs()
{
	for (Id id = 1, n = ai.GetDefCount(); id <= n; ++id) {
		CCircuitDef@ d = ai.GetCircuitDef(id);
		if (d is null)
			continue;
		AiLog("[ANV] DEF " + d.GetName() + " m=" + F1(d.costM) + " e=" + F1(d.costE) + " hp=" + F1(d.health)
			+ " spd=" + F1(d.speed) + " rng=" + F1(d.GetMaxRange()) + " pow=" + F1(d.power) + " thr=" + F1(d.threat)
			+ " dmg=" + F1(d.defDmg) + " main=" + d.GetMainRole() + " mob=" + d.IsMobile() + " fly=" + d.IsAbleToFly()
			+ " emake=" + F1(aiEconomyMgr.GetEnergyMake(d)) + " mmake=" + F1(aiEconomyMgr.GetMetalMake(d)));
	}
}

void Init()
{
	if (inited)
		return;
	inited = true;
	if (DUMP_DEFS)
		DumpDefs();
	Army::Init();
	Recycler::Init();
	Intel::Init();
	Strategic::Init();
	Production::Init();
	Production::LookAtMap();
	Economist::Init();
	initSide = ai.GetSideName();
}

/*
 * With a random side the core only learns our faction when the commander spawns (SetupManager::SetCommander),
 * after Init ran on its fallback side: a Cortex Anarva then ordered Armada extractors and turrets it can't build.
 * When the side changes, redo everything that picked defs by side.
 */
string initSide = "";
void CheckSide()
{
	const string side = ai.GetSideName();
	if (side == initSide)
		return;
	AiLog("[ANV] side resolved: " + initSide + " -> " + side + ", re-initialising side defs");
	initSide = side;
	Intel::Init();
	Scout::Init();
	Strategic::Init();
	Economist::Init();
}

void OnFactoryAdded(CCircuitUnit@ unit)
{
	if ((Factory::userData[unit.circuitDef.id].attr & (Factory::Attr::T2 | Factory::Attr::T3)) != 0)
	{
		++Recycler::advFactories;
		if (Strategic::ourT2Frame < 0)
			Strategic::ourT2Frame = ai.frame;
	}
	if (!HasBase())
		basePos = unit.GetPos(ai.frame);
	Intel::OnFactory(unit);
}

bool IsArmy(const CCircuitDef@ d)
{
	return d.IsMobile() && d.defDmg > 0.f && !d.IsRoleAny(Unit::Role::BUILDER.mask) && !d.IsRoleAny(Unit::Role::COMM.mask);
}

void OnUnitFinished(CCircuitUnit@ unit)
{
	if (commander is null && unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
		@commander = unit;
	if (!HasBase() && !unit.circuitDef.IsMobile())
		basePos = unit.GetPos(ai.frame);
	Recycler::OnFinished(unit);
	Intel::OnFinished(unit);
	Strategic::OnFinished(unit);
	if (Strategic::terrainDef !is null && unit.circuitDef is Strategic::terrainDef)
		++Strategic::terrainBuilt;
	Strategic::ownedMetal += unit.circuitDef.costM;
	if (!unit.circuitDef.IsMobile() || unit.circuitDef.IsRoleAny(Unit::Role::BUILDER.mask))
		AiLog("[ANV] built " + unit.circuitDef.GetName() + " t=" + int(ai.frame / SECOND) + "s");
	if (IsArmy(unit.circuitDef))
		Strategic::armyMetal += unit.circuitDef.costM;
	if (Strategic::mlvDef !is null && unit.circuitDef is Strategic::mlvDef)
		++Strategic::minelayers;
	Economist::OnFinished(unit);
	Production::OnFinished(unit);
	Scout::OnFinished(unit);
	Production::OnBuilt(unit);
}

/*
 * Opening (owner, 2026-11-25: "openings must be based on map characteristics and must be procedurally adjusted";
 * #95: "deadline?! also no decision is made on WHICH lab to build"). No build list, no deadline, no default lab.
 * The commander's next jobs are planned from this map and re-planned after every job:
 *  - options: every free extractor spot (its income at the share we keep), every energy plant the commander can
 *    build that makes energy here and can stand near home, and every lab it can build that can stand at home and
 *    makes armed units able to move from our base to theirs;
 *  - each option's real time: walking, build time at the commander's build power, waiting for missing resources;
 *  - value over the planning horizon: income counts only as it can be spent (what energy lets production use, up to
 *    the build power of the commander and the lab) from the moment each producer is finished; minus what the
 *    earliest enemy raid strips before our lab can field an equal strength;
 *  - the earliest raid: over every T1 lab any commander can build, the one whose fastest raider can reach us first
 *    (lab build + raider build + path / speed; moved up when an armed enemy is seen closer); it grows at that lab's
 *    rate on an income like ours;
 *  - choice: every first option followed by the best next step while a step adds value; the commander takes the
 *    first job of the best plan.
 * The opening's own decision is the lab (which and when): once a lab stands, the builders' job valuation, which
 * prices the same options the same way, takes over. Every plan is logged ([ANV-OPEN]).
 */
namespace Opening {
bool done = false;
bool ready = false;
IUnitTask@ planned = null;
int plans = 0;

class Opt {
	int kind = 0;        // 0 extractor, 1 energy, 2 lab
	CCircuitDef@ def;
	AIFloat3 pos;
	int spot = -1;
	int lab = -1;        // index into labs
	float yieldM = 0.f;  // metal/s it adds
	float yieldE = 0.f;  // energy/s it adds
}
class Sim {
	float t, M, E, mInc, eInc, labAt;
	int lab = -1;
	AIFloat3 pos;
	array<bool> usedSpot;
	float realized = 0.f;                // metal-eq spent productively from now to t
	float nProd = 0.f, prodYield = 0.f;  // producers the plan built and their metal-eq/s: what a raid can take
	float prodHp = 0.f, prodCost = 0.f;
	float nFar = 0.f, farYield = 0.f, farHp = 0.f, farCost = 0.f;  // producers beyond the commander's defence reach (#103)
}

// a lab we can build: what it fields against a raid and how fast it spends
class Lab {
	CCircuitDef@ def;
	AIFloat3 pos;
	CCircuitDef@ answer;   // its armed unit with the most strength per second it can field
	float strength;        // sqrt(dps x health) of one answer unit
	float unitTime;        // build time of one at the lab's build power
	float spend;           // metal/s the lab spends building it
	float eRatio;          // its energy per metal
	CCircuitDef@ con;      // its cheapest constructor that can build an extractor
	float conTime = 0.f;   // build time of one at the lab's build power
}
array<Lab@> labs;
array<CCircuitDef@> plants;
array<AIFloat3> plantPos;
// the earliest enemy raid
float raidArrive = 1e9f;      // game seconds
float raidLabAt = 0.f;        // the enemy lab time that estimate assumed
float raidRate = 0.f;         // raiders per second it adds (lab rate; capped by income in Value)
float raidStrength = 0.f;     // sqrt(dps x health) of one raider
float raidDps = 0.f;
float raidSpeed = 0.f;  // the earliest raider's speed (elmos/s), for how often raids come back
float raidHp = 0.f;     // its health (a tower's kills per raid)
float raidCostM = 1.f;
float raidUnitTime = 1.f;

// Planning a start before the game (no commander yet): the commander type, the candidate home and the enemy's box
bool planning = false;
const CCircuitDef@ planDef = null;
AIFloat3 planHome, planThem;
const CCircuitDef@ ComDef() { return planning ? planDef : commander.circuitDef; }
// the T1 lab worth most for this map: strength per metal of the units it fields (as the opener chooses)
CCircuitDef@ BestLab()
{
	if (!ready && commander !is null) Init();
	CCircuitDef@ best = null; float bv = -1e30f;
	for (uint k = 0; k < labs.length(); ++k) {
		const float v = labs[k].strength / AiMax(1.f, Economist::MetalValue(labs[k].answer));
		if (v > bv) { bv = v; @best = labs[k].def; }
	}
	return best;
}
// Once the game has shown us the enemy: the T1 lab whose best fighter does most per metal against it - strength per
// metal x the share of the enemy it can catch (its speed over their mobiles' mean speed now, at most 1). Second
// factories were always another bot lab (BestLab ignores the enemy) at 14:45; winners add one at a median 7:29, a
// vehicle or air plant in 78 of 94 games (replays.db 1v1 winners) - Pawns chased Grunts as fast as themselves.
float lastNewLabReturn = 0.f;  // the best new kind of lab's return per metal of its cost (last LabVsEnemy)
CCircuitDef@ BestLabVsEnemy()
{
	if (!ready && commander !is null) Init();
	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
	const uint n = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	float sumS = 0.f; int cnt = 0;
	for (uint i = 0; i < n; ++i) if (ed[i] !is null && ed[i].IsMobile() && ed[i].GetSustainedDps() > 0.f) { sumS += ed[i].speed; ++cnt; }
	// nothing in sight: the first lab is the opener's; a later one is still chosen among the kinds we don't have (the
	// early return gave the opener's bot lab every time no enemy was in view - every second factory a bot lab, vp1-4)
	if (cnt == 0 && Intel::allFactories.length() == 0) return BestLab();
	const float eSpeed = (cnt > 0) ? sumS / float(cnt) : 0.f;  // 0: no enemy speed seen - no closing-speed factor
	// the same fighting power Production uses against what we've seen (range gap, splash, hit chance): strength per
	// metal alone picked the cheapest unit (Pawns) while BARb's Raiders and Levelers killed 37 Pawns in 90 s (cmd_m24)
	Brain::Production::Mix mix; Brain::Production::FillMix(mix, null);
	CCircuitDef@ best = null; float bv = -1e30f;
	string why = "";
	// a lab we already have brings no new units, only build power - which caretakers give more cheaply: a second
	// factory is worth the options it opens (owner: "1 unit type bulked in one ball"; winners' second factories: 78 of
	// 94 a T1 vehicle or air plant, median 7:29, replays.db; ours were all bot labs - dr1-2, bp1-2, fg2 - and our Pawns
	// met BARb's 700-range Mists and Wolverines with nothing that reaches them)
	array<string> owned;
	{
		const array<CCircuitUnit@>@ mine = AiGetTeamUnits();
		for (uint i = 0; i < mine.length(); ++i)
			if (!mine[i].circuitDef.IsMobile() && mine[i].circuitDef.buildSpeed > 0.f && Facts::BuildOptions(mine[i].circuitDef.GetName()).length() > 0)
				owned.insertLast(mine[i].circuitDef.GetName());
	}
	array<float> labV(labs.length(), 0.f);
	float ownedBest = 0.f;
	for (uint k = 0; k < labs.length(); ++k) {
		const array<string> opts = Facts::BuildOptions(labs[k].def.GetName());
		float lv = 0.f; string lu = "-";
		for (uint o = 0; o < opts.length(); ++o) {
			CCircuitDef@ u = ai.GetCircuitDef(opts[o]);
			if (u is null || !u.IsMobile() || u.surfThrDmg <= 0.f || u.IsRoleAny(Unit::Role::BUILDER.mask) || !u.IsAvailable(ai.frame)) continue;  // it must hit what it meets on the ground
			string tm;
			const float v = Brain::Production::SurfPower(u, mix, tm) / AiMax(1.f, Economist::MetalValue(u)) * ((eSpeed > 0.f) ? AiMin(1.f, u.speed / eSpeed) : 1.f);
			if (v > lv) { lv = v; lu = u.GetName(); }
		}
		why += " " + labs[k].def.GetName() + "(" + lu + ")=" + F2(lv);
		labV[k] = lv;
		if (owned.find(labs[k].def.GetName()) >= 0) { ownedBest = AiMax(ownedBest, lv); continue; }  // a duplicate brings no new units
		if (lv > bv) { bv = lv; @best = labs[k].def; }
	}
	// each kind we don't have: the share by which its best unit beats the best we can build now - the core values the
	// factory by the metal it turns into those units (#116; tr1: the vehicle plant valued as build power only)
	for (uint k = 0; k < labs.length(); ++k)
		if (owned.find(labs[k].def.GetName()) < 0)
			aiMilitaryMgr.SetFactoryEdge(labs[k].def, (labV[k] > 0.f) ? AiMax(0.f, labV[k] - ownedBest) / labV[k] : 0.f);
	if (best is null) { for (uint k = 0; k < labs.length(); ++k) if (labV[k] > bv) { bv = labV[k]; @best = labs[k].def; } }  // we have every kind
	// the chosen new kind's return per metal of its cost: the metal it turns into better units over the horizon (edge x
	// its build power x metal per build-second of its options) / its cost - compared with tier 2's return (factory.as)
	lastNewLabReturn = 0.f;
	if (best !is null && owned.find(best.GetName()) < 0) {
		int bk = -1;
		for (uint k = 0; k < labs.length(); ++k) if (labs[k].def is best) bk = int(k);
		const float edge = (bk >= 0 && labV[bk] > 0.f) ? AiMax(0.f, labV[bk] - ownedBest) / labV[bk] : 0.f;
		const array<string> bo = Facts::BuildOptions(best.GetName());
		float sm = 0.f, st = 0.f;
		for (uint q = 0; q < bo.length(); ++q) { CCircuitDef@ o = ai.GetCircuitDef(bo[q]); if (o !is null && o.IsMobile()) { sm += o.costM; st += o.buildTime; } }
		const float rate = (st > 0.f) ? best.buildSpeed * sm / st : 0.f;
		lastNewLabReturn = edge * rate * Economist::Horizon() / AiMax(1.f, Economist::MetalValue(best));
	}
	AiLog("[ANV] LabVsEnemy: enemy speed " + F1(eSpeed) + " |" + why);
	return (best !is null) ? best : BestLab();
}
AIFloat3 Home() { if (planning) return planHome; return HasBase() ? basePos : commander.GetPos(ai.frame); }
AIFloat3 Them() { return planning ? planThem : AiEnemyBasePos(); }
float Strength(const CCircuitDef@ d) { return sqrt(AiMax(0.f, d.GetSustainedDps()) * AiMax(1.f, d.health)); }

// a spot near home where it can stand: home, else the first point of a ring at the commander's build distance
// a site touching the builder's footprint, never on it (owner, 2026-11-26: "why walk over to build, do not place the
// building on yourself"): builder radius + building radius from where it stands, inside its build distance, so it builds
// without a step. Of the directions around it, the buildable one nearest home (keeps the base together, away from them).
bool PlaceNextTo(CCircuitDef@ d, const AIFloat3& in at, AIFloat3& out p)
{
	const float r = ComDef().GetRadius() + d.GetRadius();
	const AIFloat3 h = Home();
	float best = 1e30f;
	bool ok = false;
	for (int k = 0; k < 16; ++k) {  // the 16 directions a footprint's neighbours take around it (a square grid's compass)
		const float ang = 2.f * Pi() * float(k) / 16.f;
		AIFloat3 q(at.x + r * cos(ang), 0.f, at.z + r * sin(ang));
		q.y = AiGetElevation(q.x, q.z);
		if (!AiCanBeBuiltAt(d, q)) continue;
		// never on the lab's planned site: a solar there left the lab unplaceable - 17 failed starts from 53 s to 110 s,
		// the lab at 128 s against the winners' 58 (rs1). Clear of its footprint and the plant's own.
		bool onLab = false;
		for (uint L = 0; L < labs.length() && !onLab; ++L)
			if (labs[L].def !is null && q.distance2D(labs[L].pos) < labs[L].def.GetRadius() + d.GetRadius()) onLab = true;
		if (onLab) continue;
		const float dh = q.distance2D(h);
		if (dh < best) { best = dh; p = q; ok = true; }
	}
	return ok;
}
bool PlaceNearHome(CCircuitDef@ d, AIFloat3& out p)
{
	const AIFloat3 h = Home();
	if (AiCanBeBuiltAt(d, h)) { p = h; return true; }
	const float r = ComDef().GetBuildDistance() + d.GetRadius();
	for (int k = 0; k < 16; ++k) {
		const float ang = 2.f * Pi() * float(k) / 16.f;
		AIFloat3 q(h.x + r * cos(ang), 0.f, h.z + r * sin(ang));
		q.y = AiGetElevation(q.x, q.z);
		if (AiCanBeBuiltAt(d, q)) { p = q; return true; }
	}
	return false;
}

void Init()
{
	const CCircuitDef@ com = ComDef();
	const float comBp = AiMax(1.f, com.buildSpeed);
	const AIFloat3 home = Home(), them = Them();
	const array<string> opts = Facts::BuildOptions(com.GetName());
	plants.resize(0); plantPos.resize(0); labs.resize(0);
	array<AIFloat3> theirSpots;
	{
		array<AIFloat3> msp; array<float> msi; array<bool> mso;
		AiGetMetalSpots(msp, msi, mso);
		for (uint q = 0; q < msp.length(); ++q) if (msp[q].distance2D(them) < msp[q].distance2D(home)) theirSpots.insertLast(msp[q]);
		if (theirSpots.length() == 0) theirSpots.insertLast(them);
	}
	for (uint k = 0; k < opts.length(); ++k) {
		CCircuitDef@ d = ai.GetCircuitDef(opts[k]);
		if (d is null || d.IsMobile()) continue;
		AIFloat3 p;
		if (aiEconomyMgr.GetEnergyMake(d) > 0.f && Facts::NeedsGeo(d.GetName()) <= 0.f) {
			if (PlaceNearHome(d, p)) { plants.insertLast(d); plantPos.insertLast(p); }
			continue;
		}
		const array<string> prod = Facts::BuildOptions(d.GetName());
		if (prod.length() == 0 || !PlaceNearHome(d, p)) continue;
		// its answer to a raid: the armed unit that can cross to their base with the most strength fielded per second
		Lab L; @L.def = d; L.pos = p; @L.answer = null; L.strength = 0.f;
		float bestRate = 0.f;
		for (uint u = 0; u < prod.length(); ++u) {
			CCircuitDef@ ud = ai.GetCircuitDef(prod[u]);
			if (ud is null || !ud.IsMobile() || ud.GetSustainedDps() <= 0.f || ud.IsAbleToFly()) continue;
			// it must reach somewhere that matters: an extractor spot on their side (the centre of their start box can be
			// unpathable: Theta Crystals listed no lab at all and the commander built extractors forever)
			bool reach = false;
			for (uint q = 0; q < theirSpots.length() && !reach; ++q) reach = AiDefCanReach(ud, home, theirSpots[q]);
			if (!reach) continue;
			const float ut = ud.buildTime / AiMax(1.f, d.buildSpeed);
			// strength per metal it costs: early production is limited by income, not build time (per second of
			// build time chose a hover plant on Feast of Hades - strong hovers no early income can feed)
			const float rate = Strength(ud) / AiMax(1.f, Economist::MetalValue(ud));
			if (rate > bestRate) { bestRate = rate; @L.answer = ud; L.strength = Strength(ud); L.unitTime = ut;
				L.spend = ud.costM / AiMax(1e-3f, ut); L.eRatio = ud.costE / AiMax(1.f, ud.costM); }
		}
		@L.con = null;
		for (uint u = 0; u < prod.length(); ++u) {
			CCircuitDef@ cd = ai.GetCircuitDef(prod[u]);
			if (cd is null || !cd.IsMobile() || cd.buildSpeed <= 0.f || Economist::mexT1 is null || !cd.CanBuild(Economist::mexT1)) continue;
			if (L.con is null || cd.costM < L.con.costM) { @L.con = cd; L.conTime = cd.buildTime / AiMax(1.f, d.buildSpeed); }
		}
		if (L.answer !is null) labs.insertLast(L);
	}
	// the earliest raid: every T1 lab any commander can build, its fastest raider that can reach us from their base
	// the raid's path from their side to this home: the straight distance times the map's detour (path / straight
	// between the bases, map analysis) - a forward start invites an earlier raid (it was the same for every start)
	float path = them.distance2D(home);
	if (Production::mapInfo !is null && Production::mapInfo.basePath > 0.f && Production::mapInfo.straight > 0.f)
		path *= Production::mapInfo.basePath / Production::mapInfo.straight;
	const array<string>@ facs = Facts::buildOptions.getKeys();
	for (uint f = 0; f < facs.length(); ++f) {
		if (int(Facts::FactoryTier(facs[f])) != 1) continue;
		CCircuitDef@ F = ai.GetCircuitDef(facs[f]);
		if (F is null || F.IsMobile()) continue;
		const array<string> prod = Facts::BuildOptions(facs[f]);
		for (uint u = 0; u < prod.length(); ++u) {
			CCircuitDef@ r = ai.GetCircuitDef(prod[u]);
			if (r is null || !r.IsMobile() || r.GetSustainedDps() <= 0.f || r.IsAbleToFly() || !Army::IsRaider(r)) continue;
			bool comes = false;  // from any spot on their side (their box centre can be unpathable)
			for (uint q = 0; q < theirSpots.length() && !comes; ++q) comes = AiDefCanReach(r, theirSpots[q], home);
			if (!comes) continue;
			// the enemy obeys the same economy: each of lab and raider takes the longer of its build time and the time
			// to afford it from the starting stock plus a commander's income (a raid "at 54 s" rushed our lab ahead
			// of the extractors every player builds first; winners' first armed unit comes at ~78 s, replays.db)
			const float m0 = AiSetupNumber("startmetal", 1000.f), e0 = AiSetupNumber("startenergy", 1000.f);
			const float mI = AiMax(1e-3f, Facts::MetalMake(com.GetName())), eI = AiMax(1e-3f, AiMax(Facts::EnergyMake(com.GetName()), aiEconomyMgr.GetEnergyMake(com)));
			const float tLab = AiMax(F.buildTime / comBp, AiMax((F.costM - m0) / mI, (F.costE - e0) / eI));
			const float ut = r.buildTime / AiMax(1.f, F.buildSpeed);
			const float mLeft = m0 + mI * tLab - F.costM, eLeft = e0 + eI * tLab - F.costE;
			const float tUnit = AiMax(ut, AiMax((r.costM - mLeft) / mI, (r.costE - eLeft) / eI));
			const float arrive = tLab + tUnit + path / AiMax(1.f, r.speed);
			if (arrive < raidArrive) {
				raidArrive = arrive; raidLabAt = tLab; raidRate = 1.f / AiMax(1e-3f, ut); raidStrength = Strength(r); raidDps = r.GetSustainedDps(); raidSpeed = r.speed; raidHp = r.health;
				raidCostM = AiMax(1.f, r.costM); raidUnitTime = ut;
				AiLog("[ANV-OPEN] earliest raid: " + r.GetName() + " from " + F.GetName() + " at " + int(arrive) + " s");
			}
		}
	}
	string ls = "";
	for (uint i = 0; i < labs.length(); ++i) ls += " " + labs[i].def.GetName() + "(" + labs[i].answer.GetName() + ")";
	AiLog("[ANV-OPEN] map: " + plants.length() + " energy options, wind " + F1(AiMinWind()) + "-" + F1(AiMaxWind()) + " tidal " + F1(AiTidal())
		+ ", labs:" + ls + ", path " + int(path));
	ready = true;
}

// metal-eq per second we can turn into something now. Everything we spend on needs energy at its own ratio: the
// commander's builds (an extractor's energy per metal) and the lab's units. Income flows to the commander's build
// power first, then the lab's; only energy left after both counts at the converter rate. (Metal counted as fully
// usable without a lab but energy-limited with one made adding a lab look like a loss: the extractor-first plan
// never added one, Feast of Hades 2026-11-25.)
float SpendRate(const Sim@ s)
{
	// What a player counts: resources gathered, usable as far as metal and energy match for what we spend on -
	// extractors and plants before the lab, the lab's units after it - plus surplus energy at the converter rate.
	// Build power is no value in itself; it only limits growth (TailGrowth). At the start (2 M, 30 E) metal binds:
	// extractors first; after three, energy binds: energy; then the lab, whose constructors grow the economy - the
	// order the winners follow (first extractor 4 s, 3 by 60 s, solar 24 s, lab 43 s; 106 winners, replays.db).
	const float epm = AiMax(1e-3f, Economist::energyPerMetal);
	if (Economist::mexT1 is null) return 0.f;
	float eR = Economist::mexT1.costE / AiMax(1.f, Economist::mexT1.costM);
	if (s.lab >= 0 && s.t >= s.labAt) eR = labs[s.lab].eRatio;
	const float m = s.mInc, e = s.eInc;
	const float usable = (eR > 0.f) ? AiMin(m, e / eR) : m;
	return usable + AiMax(0.f, e - usable * eR) / epm;
}

// the free extractor spots, nearest home first: what constructors claim after the lab (set per planning call)
array<int> tailOrder; array<float> tailYield, tailDist;
void PrepareTail(const array<AIFloat3>@ sp, const array<float>@ si, const array<bool>@ so)
{
	tailOrder.resize(0); tailYield.resize(0); tailDist.resize(0);
	if (Economist::mexT1 is null) return;
	const float ext = Economist::Extract(Economist::mexT1.GetName());
	const AIFloat3 h = Home(), t = Them();
	array<float> d; array<int> idx;
	for (uint i = 0; i < sp.length(); ++i) {
		if (!so[i] || EcoPos::OwnSpot(sp[i])) continue;
		d.insertLast(h.distance2D(sp[i])); idx.insertLast(int(i));
	}
	while (idx.length() > 0) {  // selection by distance (no sort helper for parallel arrays)
		uint m = 0;
		for (uint k = 1; k < idx.length(); ++k) if (d[k] < d[m]) m = k;
		const int i = idx[m];
		const float dUs = d[m], dThem = t.distance2D(sp[i]);
		tailOrder.insertLast(i); tailDist.insertLast(dUs);
		tailYield.insertLast(si[i] * ext * ((dUs + dThem > 0.f) ? dThem / (dUs + dThem) : 1.f));
		idx.removeAt(m); d.removeAt(m);
	}
}
// After the lab stands, income keeps growing: the lab makes constructors (one per conTime) and each claims spots at
// one per (walk + extractor build); the k-th spot comes at labAt + sqrt(2 k conTime / rate). Each yields its kept
// income to the end of the horizon, less the constructors' cost. (Income held constant after the hand-over made a
// lab worth nothing until the commander had built everything: lab first 28.7k vs 204k, lab at 6478 s.)
float TailGrowth(const Sim@ s, float end)
{
	if (s.lab < 0 || labs[s.lab].con is null || Economist::mexT1 is null) return 0.f;
	const Lab@ L = labs[s.lab];
	const float mexBuild = Economist::mexT1.buildTime / AiMax(1.f, L.con.buildSpeed);
	float v = 0.f; int k = 0;
	const float conCost = Economist::MetalValue(L.con), mexCost = Economist::MetalValue(Economist::mexT1);
	// constructors come as fast as the lab builds them AND our metal pays for them: early income compounds (more
	// income, more constructors, spots claimed sooner) - why players start at a spot cluster and take 3 extractors in
	// the first 20 s
	const float conEvery = AiMax(L.conTime, L.con.costM / AiMax(1e-3f, s.mInc));
	// Constructors claim the nearest spots first: the k-th claim needs the work of the k nearest (walk from home +
	// build), W_k; constructor-seconds available tau after the lab are tau^2 / (2 conEvery), so t_k = labAt +
	// sqrt(2 conEvery W_k). (The map-average walk let far spots decide the start: a central forward start won.)
	float W = 0.f;
	for (uint j = 0; j < tailOrder.length(); ++j) {
		if (s.usedSpot[tailOrder[j]]) continue;
		++k;
		W += tailDist[j] / AiMax(1.f, L.con.speed) + mexBuild;
		// builder time available tau after the lab: the constructors' tau^2 / (2 conEvery) plus the commander's own tau
		// (it keeps building - players' commanders take the near spots for the first minutes). Without it near spots
		// came no sooner than far ones and a central start beat the cluster starts players use (Canis 2026-11-26).
		const float tk = s.labAt + (-conEvery + sqrt(conEvery * conEvery + 2.f * conEvery * W));
		if (tk >= end) break;
		// Held only if our answer arrives before a raid kills it: a raider kills an extractor in its health / the
		// raider's dps; our lab's answer unit arrives in the spot's distance from home / its speed. P(hold) = kill time /
		// response time, at most 1 (unit facts). Counted as always held, far spots made a central start beat the
		// players' cluster start - which held the map twice on Canis while the central start lost its extractors
		// (forced-start games, 2026-11-26).
		float hold = 1.f;
		if (raidDps > 0.f && L.answer !is null) {
			const float tKill = Economist::mexT1.health / raidDps;
			const float tResp = tailDist[j] / AiMax(1.f, L.answer.speed);
			hold = AiMin(1.f, tKill / AiMax(1e-3f, tResp));
		}
		v += tailYield[j] * hold * (end - tk) - mexCost;
	}
	// constructors needed to claim them by then: one per rate x elapsed time... their cost
	const float conUsed = AiMin(float(k), (end - s.labAt) / AiMax(1.f, conEvery));
	return v - conUsed * conCost;
}

// the plan's value to the end of the horizon (now + H): what it lets us spend, minus what the first raid strips
float Value(const Sim@ s, float now, float H)
{
	const float end = now + H;
	// After the hand-over (a lab stands) the economy keeps expanding (owner: "you should be expanding at all times ...
	// more wind turbines, geothermal, fusions"): energy is built to match metal, so the metal income is what counts
	// and the energy it lacks costs once - the metal of the plants that close the gap at the cheapest plant's metal
	// per energy. (Valuing metal only as far as today's energy matched it made 4 early extractors worth less than a
	// lab at 25 s with one solar: starts went to box centres, 500-700 from the spots.)
	float econRate = SpendRate(s), oneOff = 0.f;
	if (s.lab >= 0) {
		const float epm = AiMax(1e-3f, Economist::energyPerMetal);
		const float eR = labs[s.lab].eRatio;
		const float needE = AiMax(0.f, s.mInc * eR - s.eInc);
		float perE = 1e9f;
		for (uint k = 0; k < plants.length(); ++k)
			perE = AiMin(perE, Economist::MetalValue(plants[k]) / AiMax(1e-3f, aiEconomyMgr.GetEnergyMake(plants[k])));
		econRate = s.mInc + AiMax(0.f, s.eInc - s.mInc * eR) / epm;
		oneOff = (perE < 1e9f) ? needE * perE : 0.f;
	}
	float v = s.realized + econRate * AiMax(0.f, end - s.t) - oneOff + s.M + s.E / AiMax(1e-3f, Economist::energyPerMetal)
		+ TailGrowth(s, end);
	if (raidArrive < end && s.nProd > 0.f) {
		// raid strength n(t) x one raider, n = 1 + rate x (t - arrival), the rate capped by an income like ours
		const float rate = AiMin(raidRate, s.mInc / raidCostM);
		// Ours: the commander - which stands by the first extractors (why players start at a spot cluster: early raids
		// lose to it) - plus the lab's answer units from when the first is out. The raid strips producers while it is
		// stronger: f(t) = commander + lab units(t) - raid(t) < 0. (Without the commander every exposed producer died
		// for the whole horizon: cluster starts lost ~57k to an early raid and the box centre won, 2026-11-25.)
		const float com = Strength(ComDef());
		float oursRate = 0.f, tU = end;
		if (s.lab >= 0) {
			const Lab@ L = labs[s.lab];
			const float uRate = AiMin(1.f / AiMax(1e-3f, L.unitTime), s.mInc / AiMax(1.f, L.answer.costM));
			oursRate = L.strength * uRate;
			tU = s.labAt + L.unitTime;
		}
		// f is linear on [arrival, tU] and on [tU, end]; the window is the time it is negative
		float window = 0.f;
		{
			array<float> ts = {raidArrive, AiMax(raidArrive, AiMin(tU, end)), end};
			for (uint seg = 0; seg + 1 < ts.length(); ++seg) {
				const float t0 = ts[seg], t1 = ts[seg + 1];
				if (t1 <= t0) continue;
				const float f0 = com + oursRate * AiMax(0.f, t0 - tU) - raidStrength * (1.f + rate * (t0 - raidArrive));
				const float f1 = com + oursRate * AiMax(0.f, t1 - tU) - raidStrength * (1.f + rate * (t1 - raidArrive));
				if (f0 < 0.f && f1 < 0.f) window += t1 - t0;
				else if (f0 < 0.f || f1 < 0.f) window += (t1 - t0) * ((f0 < 0.f) ? f0 : f1) / (f0 - f1) * ((f0 < 0.f) ? 1.f : -1.f);
			}
		}
		// producers it kills over the window: its damage (growing) over their mean health
		const float dmg = raidDps * (window + rate * window * window / 2.f);
		const float k = AiMin(s.nProd, dmg / AiMax(1.f, s.prodHp / s.nProd));
		// each lost one costs its metal and its yield for about half the window (they die across it)
		v -= k * (s.prodCost / s.nProd + s.prodYield / s.nProd * window / 2.f);
		// the far ones meet the raid without the commander: the same, with only the lab's units against it (#103: the
		// commander's strength counted for every producer closed the window and over-expansion cost nothing)
		if (s.nFar > 0.f) {
			float wF = 0.f;
			array<float> ts = {raidArrive, AiMax(raidArrive, AiMin(tU, end)), end};
			for (uint seg = 0; seg + 1 < ts.length(); ++seg) {
				const float t0 = ts[seg], t1 = ts[seg + 1];
				if (t1 <= t0) continue;
				const float f0 = oursRate * AiMax(0.f, t0 - tU) - raidStrength * (1.f + rate * (t0 - raidArrive));
				const float f1 = oursRate * AiMax(0.f, t1 - tU) - raidStrength * (1.f + rate * (t1 - raidArrive));
				if (f0 < 0.f && f1 < 0.f) wF += t1 - t0;
				else if (f0 < 0.f || f1 < 0.f) wF += (t1 - t0) * ((f0 < 0.f) ? f0 : f1) / (f0 - f1) * ((f0 < 0.f) ? 1.f : -1.f);
			}
			const float dF = raidDps * (wF + rate * wF * wF / 2.f);
			const float kF = AiMin(s.nFar, dF / AiMax(1.f, s.farHp / s.nFar));
			v -= kF * (s.farCost / s.nFar + s.farYield / s.nFar * wF / 2.f);
		}
	}
	return v;
}

// The commander's walk: the engine's path length for its move type over its speed (a straight line priced the third
// extractor - spot 49 on Canis, behind a detour - at 9 s; it took 20+, and the lab came at 86-101 s against the
// winners' ~61; minute-1 checklist gap: no factory, 50 energy vs 0.9 and 79)
float Walk(const AIFloat3& in a, const AIFloat3& in b, float speed)
{
	CCircuitDef@ d = ai.GetCircuitDef(ComDef().GetName());
	return AiPathLength(d, a, b) / AiMax(1.f, speed);
}
float DefenceReach(const CCircuitDef@ d)
{
	const CCircuitDef@ c = ComDef();
	return c.speed * d.health / AiMax(1e-3f, raidDps) + c.GetMaxRange();
}
// do o from state s (walk + build at bp, waiting for missing resources)
void Apply(Sim@ s, const Opt@ o, float bp, float speed)
{
	const float walk = Walk(s.pos, o.pos, speed);
	const float build = o.def.buildTime / AiMax(1.f, bp);
	const float wM = AiMax(0.f, o.def.costM - s.M - s.mInc * (walk + build)) / AiMax(1e-3f, s.mInc);
	const float wE = AiMax(0.f, o.def.costE - s.E - s.eInc * (walk + build)) / AiMax(1e-3f, s.eInc);
	const float dur = walk + build + AiMax(wM, wE);
	s.realized += SpendRate(s) * dur;
	s.M += s.mInc * dur - o.def.costM;
	s.E += s.eInc * dur - o.def.costE;
	s.t += dur;
	s.pos = o.pos;
	s.mInc += o.yieldM; s.eInc += o.yieldE;
	if (o.kind == 0 && o.spot >= 0) s.usedSpot[o.spot] = true;
	if (o.kind <= 1) {  // what a raid kills (Favs and Flashes killed turbines as often as extractors)
		s.nProd += 1.f; s.prodYield += o.yieldM + o.yieldE / AiMax(1e-3f, Economist::energyPerMetal);
		s.prodHp += o.def.health; s.prodCost += Economist::MetalValue(o.def);
		// beyond where the commander can arrive before a raider kills it (its speed x the producer's health over a
		// raider's dps, plus its range; unit facts), the producer faces the raid without the commander (#103)
		if (Home().distance2D(o.pos) > DefenceReach(o.def)) {
			s.nFar += 1.f; s.farYield += o.yieldM + o.yieldE / AiMax(1e-3f, Economist::energyPerMetal);
			s.farHp += o.def.health; s.farCost += Economist::MetalValue(o.def);
		}
	}
	if (o.kind == 2) { s.lab = o.lab; s.labAt = s.t; }
}

array<Opt@> Options(const Sim@ s, const array<AIFloat3>@ sp, const array<float>@ si, const array<bool>@ so)
{
	array<Opt@> opts;
	if (Economist::mexT1 !is null) {
		for (uint i = 0; i < sp.length(); ++i) {
			if (!so[i] || s.usedSpot[i] || EcoPos::OwnSpot(sp[i]) || failedSpots.find(int(i)) >= 0) continue;
			// the commander builds these: never where the chance of losing it (and the game) outweighs the extractor
			if (!planning && CommPDeath(sp[i], EscapeTime(sp[i])) * GameValue() > Economist::AssetValue(Economist::mexT1)) continue;
			Opt o; o.kind = 0; @o.def = Economist::mexT1; o.pos = sp[i]; o.spot = int(i);
			const float dUs = Home().distance2D(sp[i]), dThem = Them().distance2D(sp[i]);
			const float keep = (dUs + dThem > 0.f) ? dThem / (dUs + dThem) : 1.f;  // the share we keep
			o.yieldM = si[i] * Economist::Extract(Economist::mexT1.GetName()) * keep;
			opts.insertLast(o);
		}
	}
	for (uint k = 0; k < plants.length(); ++k) {
		Opt o; o.kind = 1; @o.def = plants[k]; o.pos = plantPos[k]; o.yieldE = aiEconomyMgr.GetEnergyMake(plants[k]);
		AIFloat3 nx;
		if (PlaceNextTo(plants[k], s.pos, nx)) o.pos = nx;  // where the commander stands, not back home
		opts.insertLast(o);
	}
	if (s.lab < 0 && Intel::allFactories.length() == 0) {
		for (uint k = 0; k < labs.length(); ++k) {
			if (labOnly != -2 && int(k) != labOnly) continue;  // a rollout plans with one lab (or none: -1)
			Opt o; o.kind = 2; @o.def = labs[k].def; o.pos = labs[k].pos; o.lab = int(k);
			opts.insertLast(o);
		}
	}
	return opts;
}

Sim@ Copy(const Sim@ a)
{
	Sim b;
	b.t = a.t; b.M = a.M; b.E = a.E; b.mInc = a.mInc; b.eInc = a.eInc; b.labAt = a.labAt; b.lab = a.lab; b.pos = a.pos;
	b.usedSpot = a.usedSpot; b.realized = a.realized;
	b.nProd = a.nProd; b.prodYield = a.prodYield; b.prodHp = a.prodHp; b.prodCost = a.prodCost;
	b.nFar = a.nFar; b.farYield = a.farYield; b.farHp = a.farHp; b.farCost = a.farCost;
	return b;
}

// the best plan from state s0: every first option followed by the best next step while one adds value
int labOnly = -2;  // -2: any lab; -1: none; k: only labs[k]
Sim@ lastOne = null;
/*
 * The best plan from s0 (#95). The lab's timing is searched, not left to a greedy step: a lab pays off over time, so a
 * greedy rollout added it only when one step of it beat one more extractor (the extractor-first plan built its lab at
 * 249 s while players build 3 extractors, energy, then the lab at ~45 s). For each first step: the greedy sequence
 * without a lab, then each lab inserted at every point of that sequence, followed greedily; the best counts. First
 * steps: the extractor worth most one step ahead (that ranks walk and richness), each energy plant, each lab.
 */
float BestPlan(const Sim@ s0, float now, float H, const array<Opt@>@ first, int &out best, float bp, float speed,
	const array<AIFloat3>@ sp, const array<float>@ si, const array<bool>@ so)
{
	best = -1;
	float bestV = Value(s0, now, H);  // doing nothing more is the baseline
	@lastBest = null;
	int bestMex = -1; float bestMexV = -1e30f;
	for (uint a = 0; a < first.length(); ++a) {
		if (first[a].kind != 0) continue;
		Sim@ s = Copy(s0);
		Apply(s, first[a], bp, speed);
		const float v = Value(s, now, H);
		if (v > bestMexV) { bestMexV = v; bestMex = int(a); }
	}
	for (uint a = 0; a < first.length(); ++a) {
		if (first[a].kind == 0 && int(a) != bestMex) continue;
		Sim@ end = null;
		const float v = PlanFrom(s0, first[a], now, H, bp, speed, sp, si, so, end);
		if (v > bestV) { bestV = v; best = int(a); @lastBest = end; }
	}
	return bestV;
}
// greedy: the best next step while one adds value (labs only as labOnly allows)
float Greedy(Sim@ s, float now, float H, float bp, float speed, const array<AIFloat3>@ sp, const array<float>@ si,
	const array<bool>@ so, array<Opt@>@ seq)
{
	float cur = Value(s, now, H);
	while (s.t < now + H) {
		array<Opt@> nx = Options(s, sp, si, so);
		int nb = -1; float nv = cur;
		for (uint b = 0; b < nx.length(); ++b) {
			Sim@ s2 = Copy(s);
			Apply(s2, nx[b], bp, speed);
			const float v2 = Value(s2, now, H);
			if (v2 > nv) { nv = v2; nb = int(b); }
		}
		if (nb < 0) break;
		Apply(s, nx[nb], bp, speed);
		if (seq !is null) seq.insertLast(nx[nb]);
		cur = nv;
	}
	return cur;
}
float PlanFrom(const Sim@ s0, const Opt@ firstStep, float now, float H, float bp, float speed,
	const array<AIFloat3>@ sp, const array<float>@ si, const array<bool>@ so, Sim@ &out endState)
{
	// The plan ends where the opening's job ends, when a lab stands (the builders' valuation takes over); its value
	// extrapolates the rates from there. Without a lab yet: grow the sequence one best step at a time and try each
	// lab after every step, until a later lab is worth less than an earlier one for every lab (delay only costs then).
	Sim@ s1 = Copy(s0);
	Apply(s1, firstStep, bp, speed);
	@endState = s1;
	float best = Value(s1, now, H);
	if (s1.lab >= 0 || Intel::allFactories.length() > 0) return best;
	labOnly = -1;
	array<float> prev(labs.length(), -1e30f);
	array<bool> falling(labs.length(), false);
	Sim@ sj = Copy(s1);
	while (sj.t < now + H) {
		bool any = false;
		for (uint L = 0; L < labs.length(); ++L) {
			if (falling[L]) continue;
			Opt lo; lo.kind = 2; @lo.def = labs[L].def; lo.pos = labs[L].pos; lo.lab = int(L);
			Sim@ s2 = Copy(sj);
			Apply(s2, lo, bp, speed);
			const float v = Value(s2, now, H);
			if (v > best) { best = v; @endState = s2; }
			if (v < prev[L]) falling[L] = true; else { prev[L] = v; any = true; }
		}
		if (!any) break;
		// one more step without a lab: the one worth most
		array<Opt@> nx = Options(sj, sp, si, so);
		int nb = -1; float nv = -1e30f;
		for (uint k = 0; k < nx.length(); ++k) {
			Sim@ s3 = Copy(sj);
			Apply(s3, nx[k], bp, speed);
			const float v3 = Value(s3, now, H);
			if (v3 > nv) { nv = v3; nb = int(k); }
		}
		if (nb < 0) break;
		Apply(sj, nx[nb], bp, speed);
		if (nv > best) { best = nv; @endState = Copy(sj); }
	}
	labOnly = -2;
	return best;
}
Sim@ lastBest = null;  // the best plan's end state (for the decision log)
string Describe(const Sim@ s, float now, float H)
{
	if (s is null) return "-";
	return "end t " + int(s.t) + " mInc " + F1(s.mInc) + " eInc " + F1(s.eInc) + " lab " + (s.lab >= 0 ? labs[s.lab].def.GetName() + "@" + int(s.labAt) : "none")
		+ " realized " + int(s.realized) + " rate " + F1(SpendRate(s)) + " producers " + int(s.nProd);
}

/*
 * Where to start (#97, owner: "you haven't even made start picking dynamic"): when the game lets us choose, every
 * candidate in our box - each extractor spot in it (the commander starts next to it) and the box's centre - is
 * valued by the best opening plan from there against the enemy's box, and the best is taken. The plan already
 * weighs the spots we keep (nearer us than them), the walk, energy, the lab and the earliest raid.
 */
AIFloat3 PickStart(const AIFloat3& in lo, const AIFloat3& in hi, const AIFloat3& in them)
{
	@planDef = aiSetupMgr.commChoice;
	if (planDef is null) return AIFloat3(0.f, 0.f, 0.f);
	planning = true;
	planThem = them;
	array<AIFloat3> sp; array<float> si; array<bool> so;
	AiGetMetalSpots(sp, si, so);
	array<AIFloat3> cands;
	cands.insertLast(AIFloat3((lo.x + hi.x) / 2.f, 0.f, (lo.z + hi.z) / 2.f));
	// each spot in the box offers the centre of the spots the commander can build from one place there (within its
	// build distance of that spot): it builds them without walking - players start ~170 elmos from their nearest
	// spot with 3 within ~210 (median of 106 winners, 1v1 replays.db)
	const float reach = planDef.GetBuildDistance();
	for (uint i = 0; i < sp.length(); ++i) {
		if (!(sp[i].x >= lo.x && sp[i].x <= hi.x && sp[i].z >= lo.z && sp[i].z <= hi.z)) continue;
		AIFloat3 c(0.f, 0.f, 0.f); int k = 0;
		for (uint j = 0; j < sp.length(); ++j)
			if (sp[j].distance2D(sp[i]) <= 2.f * reach) { c.x += sp[j].x; c.z += sp[j].z; ++k; }
		cands.insertLast(AIFloat3(c.x / k, 0.f, c.z / k));
		// ...and the spot with its two nearest: the centre of a triangle the commander builds from one place. The cluster
		// average of 4-5 spots missed it - winners on Canis stand at (2525,5854), the centre of three spots 127-179 away,
		// building them at 9/16/23 s; ours chose (2464,5696), 51 from one and 248 from the next (ob4/ob6)
		int n1 = -1, n2 = -1;
		for (uint j = 0; j < sp.length(); ++j) {
			if (j == i) continue;
			const float dj = sp[j].distance2D(sp[i]);
			if (n1 < 0 || dj < sp[uint(n1)].distance2D(sp[i])) { n2 = n1; n1 = int(j); }
			else if (n2 < 0 || dj < sp[uint(n2)].distance2D(sp[i])) n2 = int(j);
		}
		if (n2 >= 0) {
			const AIFloat3 t3((sp[i].x + sp[uint(n1)].x + sp[uint(n2)].x) / 3.f, 0.f, (sp[i].z + sp[uint(n1)].z + sp[uint(n2)].z) / 3.f);
			cands.insertLast(t3);  // (the simulation prices the short steps; winners' spots are 127-179 away, just past reach)
		}
	}
	const float H = AiMax(1.f, Economist::Horizon());
	const float ext = (Economist::mexT1 !is null) ? Economist::Extract(Economist::mexT1.GetName()) : 0.f;
	AIFloat3 bestP = cands[0]; float bestV = -1e30f;
	for (uint c = 0; c < cands.length(); ++c) {
		planHome = cands[c];
		planHome.y = AiGetElevation(planHome.x, planHome.z);
		// the commander must be able to stand there and walk to the spots it would build (a centroid can fall on a
		// cliff or inside rock: on Theta Crystals the commander took no job at all for minutes)
		{
			int reachable = 0;
			CCircuitDef@ walker = ai.GetCircuitDef(planDef.GetName());
			for (uint i = 0; i < sp.length() && reachable == 0; ++i)
				if (sp[i].distance2D(planHome) <= 2.f * reach && AiDefCanReach(walker, planHome, sp[i])) ++reachable;
			if (reachable == 0) { AiLog("[ANV-START] candidate (" + int(planHome.x) + "," + int(planHome.z) + ") unreachable ground: skipped"); continue; }
		}
		ready = false; raidArrive = 1e9f;
		Init();
		Sim s0;
		// the game's start: its starting stock (setup; the engine gives 1000/1000 at frame 0 when the setup sets none,
		// [HARNESS] stats f=0) and what the commander makes (unit facts) - before the game the economy reads 0 and
		// no plan could pay for anything (every candidate scored "plan 0")
		s0.t = 0.f; s0.M = AiSetupNumber("startmetal", 1000.f); s0.E = AiSetupNumber("startenergy", 1000.f);
		s0.mInc = Facts::MetalMake(planDef.GetName()); s0.eInc = AiMax(Facts::EnergyMake(planDef.GetName()), aiEconomyMgr.GetEnergyMake(planDef));
		s0.pos = planHome; s0.labAt = 1e9f;
		s0.usedSpot.resize(sp.length());
		for (uint i = 0; i < sp.length(); ++i) s0.usedSpot[i] = false;
		PrepareTail(sp, si, so);
		// what the opener will actually do from here: its own decisions (Bottleneck) until its lab stands, then valued
		// over the horizon - income, the expansion its lab drives, minus what the earliest raid strips (a forward start
		// is raided sooner; a scattered one makes the commander walk). (The retired rollout planner judged the starts.)
		Sim@ os = Copy(s0);
		for (int step = 0; os.lab < 0 && os.t < H; ++step) {
			array<Opt@> opts = Options(os, sp, si, so);
			int ob = -1; string why;
			Bottleneck(os, opts, planDef.buildSpeed, planDef.speed, ob, why);
			if (ob < 0) break;
			Apply(os, opts[ob], planDef.buildSpeed, planDef.speed);
		}
		float v = Value(os, 0.f, H);
		// (No separate territory term: every spot's yield x kept share x horizon grew with every step forward and
		// outweighed the plan - starts at 0.91 forward, 3rd spot 758 away, winners 0.50-0.80 and 188-381. What a start
		// changes is in the plan's value: the commander's first extractors, the constructors' walks to every later
		// spot at the share kept from here (TailGrowth), and how soon the raid comes.)
		const float terr = 0.f;
		AiLog("[ANV-START] candidate (" + int(planHome.x) + "," + int(planHome.z) + ") value " + int(v) + " [" + Describe(os, 0.f, H) + " tail " + int(TailGrowth(os, H))
			+ " con " + ((os.lab >= 0 && labs[os.lab].con !is null) ? labs[os.lab].con.GetName() : "none") + " raid " + int(raidArrive) + "]");
		if (v > bestV) { bestV = v; bestP = planHome; }
	}
	planning = false; ready = false; raidArrive = 1e9f;
	return bestP;
}

void Update()
{
	if (done || commander is null) return;  // from frame 0: the opening also decides the first building
	CheckFailedSpot();
	if (!ready) {
		Init();
		// tell a watching player which side is Anarva (owner, 2026-11-25: "i have no idea of who is who")
		const AIFloat3 cp = commander.GetPos(ai.frame);
		AiSay("Anarva here: team " + ai.teamId + ", commander " + commander.circuitDef.GetName() + " at (" + int(cp.x) + ", " + int(cp.z) + ")");
	}
	const float now = float(ai.frame) / SECOND;
	// a lab of ours stands: the opening's decision is made, the builders' job valuation takes over
	if (Intel::allFactories.length() > 0) {
		done = true;
		// The enemy commander faces the same economy and start: the time our opener, weighing extractors against the lab,
		// got its lab up is the time theirs comes (the estimate assumed a lab first, ~99 s raids on Canis: the first
		// tower came at 109 s while BARb's first unit reached us at 2:00 and winners' first tower stands at ~217 s,
		// replays.db). A seen enemy still moves it up (below, and Intel).
		if (raidArrive < 1e9f && now > raidLabAt) {
			const float was = raidArrive;
			raidArrive += now - raidLabAt;
			raidLabAt = now;
			AiLog("[ANV-OPEN] their lab expected when ours stood (" + int(now) + " s): earliest raid " + int(was) + " -> " + int(raidArrive) + " s");
		}
		AiLog("[ANV-OPEN] lab standing at " + int(now) + " s after " + plans + " plans: the builders' job valuation takes over");
		return;
	}
	// an armed enemy seen closer than the raid we planned for moves it up: its distance over its speed
	{
		array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
		const uint n = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
		for (uint i = 0; i < n; ++i) {
			if (ed[i] is null || !ed[i].IsMobile() || ed[i].GetSustainedDps() <= 0.f || ed[i].IsRoleAny(Unit::Role::COMM.mask)) continue;
			const float arrive = now + ep[i].distance2D(Home()) / AiMax(1.f, ed[i].speed);
			if (arrive < raidArrive) {
				AiLog("[ANV-OPEN] raid sooner: " + ed[i].GetName() + " can reach us at " + int(arrive) + " s (was " + int(raidArrive) + ")");
				raidArrive = arrive;
			}
		}
	}
	// One plan at a time: while the planned job exists, the commander goes back to it rather than a new plan being
	// made (an assignment the core refused left the job orphaned; each re-plan queued another wind, the orphans timed
	// out half-built and their frames were reclaimed: 4 wind plans, 2 turbines, BarR 2026-11-25). OnTaskRemoved clears
	// it when the job ends.
	if (planned !is null) {
		if (commander.task !is planned) aiBuilderMgr.AssignTask(commander, planned);
		return;
	}
	array<AIFloat3> sp; array<float> si; array<bool> so;
	AiGetMetalSpots(sp, si, so);
	Sim s0;
	s0.t = now; s0.M = aiEconomyMgr.metal.current; s0.E = aiEconomyMgr.energy.current;
	if (aiEconomyMgr.metal.storage <= 0.f) {  // nothing measured yet (frame 0): the game's starting stock
		s0.M = AiSetupNumber("startmetal", 1000.f); s0.E = AiSetupNumber("startenergy", 1000.f);
	}
	s0.mInc = AiMax(aiEconomyMgr.metal.income, Facts::MetalMake(ComDef().GetName()));  // at least what the commander makes
	s0.eInc = AiMax(aiEconomyMgr.energy.income, Facts::EnergyMake(ComDef().GetName()));
	s0.pos = commander.GetPos(ai.frame); s0.labAt = 1e9f;
	s0.usedSpot.resize(sp.length());
	for (uint i = 0; i < sp.length(); ++i) s0.usedSpot[i] = false;
	const float bp = ComDef().buildSpeed, speed = ComDef().speed;
	const float H = AiMax(1.f, Economist::Horizon());
	array<Opt@> first = Options(s0, sp, si, so);
	int best = -1;
	string why = "";
	const float bestV = Bottleneck(s0, first, bp, speed, best, why);
	if (false) {  // (the rollout planner's step log, retired with it)
		array<float> kv = {-1e30f, -1e30f, -1e30f}; array<string> kn = {"", "", ""};
		for (uint a = 0; a < first.length(); ++a) {
			array<Opt@> one = {first[a]};
			int bb = -1;
			@lastBest = null;
			const float v = BestPlan(s0, now, H, one, bb, bp, speed, sp, si, so);
			if (v > kv[first[a].kind]) { kv[first[a].kind] = v; kn[first[a].kind] = first[a].def.GetName() + " [" + Describe(lastBest, now, H) + "]"; }
		}
		AiLog("[ANV-OPEN] first step values: extractor " + kn[0] + " " + int(kv[0]) + ", energy " + kn[1] + " " + int(kv[1]) + ", lab " + kn[2] + " " + int(kv[2]));
	}
	if (best < 0) return;  // nothing the commander can do here adds value: the builders' valuation decides
	const Opt@ o = first[best];
	++plans;
	plannedSpot = (o.kind == 0) ? o.spot : -1;
	if (o.kind == 0)
		@planned = aiBuilderMgr.Enqueue(TaskB::Spot(Task::BuildType::MEX, Task::Priority::NOW, o.def, o.pos, o.spot, true, OrderLife(o.def, o.pos)));
	else if (o.kind == 1)
		@planned = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::ENERGY, Task::Priority::NOW, o.def, o.pos, 0.f, true, OrderLife(o.def, o.pos)));  // the site chosen next to it, no shake
	else
		@planned = aiBuilderMgr.Enqueue(TaskB::Factory(Task::Priority::NOW, o.def, o.pos, o.def, 0.f, false, true, OrderLife(o.def, o.pos)));
	if (planned !is null) aiBuilderMgr.AssignTask(commander, planned);
	AiLog("[ANV-OPEN] t=" + int(now) + "s commander -> " + o.def.GetName() + (o.kind == 0 ? (" at spot " + o.spot) : "") + " (" + why + ")");
}
/*
 * The opener as a player reasons it (owner: "everyone knows that if you choose the lab as the first building you
 * will immediately stall energy"; the guides: extractors first - metal is the most limiting resource - then energy,
 * then one factory; replays: first extractor 4 s, 3 by 60 s, solar 24 s, lab 43 s; 106 winners):
 *  1. the lab, when it can be built now without waiting for resources AND energy income covers the production it
 *     starts right after (its first product, a constructor, at the rate metal allows) - else it stalls energy;
 *  2. otherwise the commander uses the time until then for the producer worth most per second of its time (walk +
 *     build): an extractor's metal; a plant's energy, at the production ratio while energy is what keeps the lab
 *     from running, else at the converter rate.
 * The lab is the best one for this map (strength per metal it fields, its units can reach their base).
 */
float Bottleneck(const Sim@ s0, const array<Opt@>@ opts, float bp, float speed, int &out best, string &out why)
{
	best = -1;
	int lab = -1; float labV = -1e30f;
	for (uint a = 0; a < opts.length(); ++a) {
		if (opts[a].kind != 2) continue;
		const Lab@ L = labs[opts[a].lab];
		const float v = L.strength / AiMax(1.f, Economist::MetalValue(L.answer));
		if (v > labV) { labV = v; lab = int(a); }
	}
	float drawE = 0.f, needE = 0.f, drawM = 0.f, needM = 0.f;
	if (lab >= 0) {
		const Lab@ L = labs[opts[lab].lab];
		const CCircuitDef@ firstUnit = (L.con !is null) ? L.con : L.answer;
		const float ut = firstUnit.buildTime / AiMax(1.f, L.def.buildSpeed);
		// a factory pulls at its full build rate whatever the income (and starves the rest when short): that is why a
		// lab first stalls energy. Its draw is its first product's cost per its build time at the lab's build power.
		// (Drawing "at the rate metal allows" read 29 E/s and built the lab first: energy stalled at 30/s.)
		drawE = firstUnit.costE / AiMax(1.f, ut);
		drawM = firstUnit.costM / AiMax(1.f, ut);
		// (Planning for the commander's boost made the opener wait for an income it can't reach alone: the lab came at
		// ~3.5 min and there was no army until minute 8, Canis 2026-11-26. The lab is planned for its own draw.)
		Sim@ t = Copy(s0);
		const float t0 = t.t;
		Apply(t, opts[lab], bp, speed);
		const float walkBuild = Walk(s0.pos, opts[lab].pos, speed) + opts[lab].def.buildTime / AiMax(1.f, bp);
		const bool noWait = (t.t - t0) <= walkBuild + 1e-3f;
		needE = drawE - s0.eInc;
		needM = drawM - s0.mInc;
		// A small gap doesn't stall: the stock left when the lab stands carries it while the commander closes it (the
		// players start the lab at ~43 s with energy still short). It stalls only if the stock runs out first.
		// Time to close a gap: the best plant (or extractor) of that resource per second of commander time.
		bool carried = true;
		if (needE > 0.f || needM > 0.f) {
			float bestE = 0.f, bestM = 0.f;  // resource per second of commander time
			for (uint a = 0; a < opts.length(); ++a) {
				if (opts[a].kind == 2) continue;
				const float tt = opts[a].def.buildTime / AiMax(1.f, bp) + Walk(t.pos, opts[a].pos, speed);
				bestE = AiMax(bestE, opts[a].yieldE / AiMax(1e-3f, tt));
				bestM = AiMax(bestM, opts[a].yieldM / AiMax(1e-3f, tt));
			}
			// one commander closes both gaps one after the other (g / r each), and each deficit runs until then: the stock
			// must carry each for the sum (half-credit for a shrinking deficit let the lab go first and stall, minute 1-2)
			const float tFix = ((needE > 0.f) ? needE / AiMax(1e-3f, bestE) : 0.f) + ((needM > 0.f) ? needM / AiMax(1e-3f, bestM) : 0.f);
			// energy must be there before the lab, not carried by the stock: BARb builds 3 solars before its plant and has
			// 90 E/s at 2:00 against our 50 - the second stat to swing (tools/swing.py sw2); after the lab the commander builds
			// extractors, not plants, so a gap the stock "carries" stays open and the lab runs short
			if (needE > 0.f) carried = false;
			if (needM > 0.f) carried = carried && (bestM > 0.f) && (t.M >= needM * tFix);
		}
		// An extractor the commander builds first yields from now until the lab's first constructor could have built it
		// (lab standing + constructor + its walk there): that is what it gains. It costs the lab the commander's time
		// for it: so many seconds of the lab's production (its draw, in metal-eq). Players take the near spots first and
		// the lab after (Canis winners: extractors at 9/16/23 s, two plants, lab at ~61 s, replays.db; ours took the lab
		// at 28 s as soon as it was affordable and had 6-7 extractors by 4:00 against their 9).
		float firstGain = 0.f, firstCost = 0.f; string firstName = ""; int firstOpt = -1;
		if (noWait && carried) {
			const float drawEq = drawM + drawE / AiMax(1e-3f, Economist::energyPerMetal);
			const float conSpeed = (L.con !is null) ? AiMax(1.f, L.con.speed) : AiMax(1.f, speed);
			for (uint a = 0; a < opts.length(); ++a) {
				if (opts[a].kind != 0) continue;
				// simulated, with the resource waits: the extractor first, then the lab - against the lab now (t). It costs the
				// lab's production for every second the lab stands later; the commander's time alone missed that the stock
				// spent on it makes the lab wait (pl1: spot 49 "111 vs 104", then the lab took 46 s, standing at 119 s)
				Sim@ w = Copy(s0);
				Apply(w, opts[a], bp, speed);
				const float mexDone = w.t;
				Apply(w, opts[lab], bp, speed);
				const float tt = mexDone - s0.t;
				const float tByCon = w.t + L.conTime + opts[lab].pos.distance2D(opts[a].pos) / conSpeed;
				const float gain = opts[a].yieldM * AiMax(0.f, tByCon - mexDone);
				// A later lab loses no resources (they bank and are spent once it stands); what it costs is the army later, and
				// that matters only past the earliest enemy raid: the lab's production for the time its first unit comes
				// later than the raid can arrive (#41). Charged for the whole delay, the opener built one extractor before
				// the lab while BARb built two and three solars before its plant: metal 6.6 vs 8.9 at 2:00 - the first stat
				// to swing (tools/swing.py, sw1).
				const float tR = raidArrive;
				const float cost = drawEq * (AiMax(0.f, w.t + L.unitTime - tR) - AiMax(0.f, t.t + L.unitTime - tR));
				if (gain - cost > firstGain - firstCost) { firstGain = gain; firstCost = cost; firstName = "spot " + opts[a].spot; firstOpt = int(a); }
			}
		}
		// that extractor, then: it is what beat the lab (the general producer choice below built winds instead, and the lab
		// waited until 123 s, op1)
		if (noWait && carried && firstOpt >= 0 && firstGain > firstCost) {
			best = firstOpt;
			why = "extractor first: " + firstName + " yields " + int(firstGain) + " before a constructor could build it, the lab loses " + int(firstCost);
			return firstGain - firstCost;
		}
		if (noWait && carried && firstGain <= firstCost) {
			best = lab;
			why = "lab: affordable now; income " + F1(s0.mInc) + " M/s, " + int(s0.eInc) + " E/s covers its production (" + F1(drawM) + " M/s, " + int(drawE) + " E/s)";
			return 1.f;
		}
		why = (noWait ? "" : "lab not affordable yet; ") + (needM > 0.f ? ("metal " + F1(s0.mInc) + "/s short of " + F1(drawM) + "; ") : "")
			+ (needE > 0.f ? ("energy " + int(s0.eInc) + "/s short of " + int(drawE) + "; ") : "");
	}
	const float epm = AiMax(1e-3f, Economist::energyPerMetal);
	// energy's worth in metal: at the production ratio while it keeps the lab from running, else the converter rate
	// each resource is worth as much as it closes the gap that keeps the lab from running: a unit of the short one
	// closes 1/need of it (both short: each by its own gap); not short: energy at the converter rate, metal at 1
	// each resource is worth the share of ITS gap it closes; once a gap is closed, more of that resource doesn't bring
	// the lab closer (players switch to energy after the extractors: 3 extractors, solar 24 s, wind 29 s, lab 45 s;
	// metal at worth 1 kept the commander on extractors until 56 s with energy short)
	float eWorth = 1.f / epm, mWorth = 1.f;
	if (needM > 0.f || needE > 0.f) {
		mWorth = (needM > 0.f) ? 1.f / needM : 0.f;
		eWorth = (needE > 0.f) ? 1.f / needE : 0.f;
	}
	// Production is the least of what metal and energy allow (owner). While the lab's draw isn't covered, our share of
	// it is min(metal income / its metal draw, energy income / its energy draw); a producer is worth how much it raises
	// that minimum per second of commander time - the resource that isn't the limit adds nothing until the other catches
	// up. "The share of its own gap" picked a third extractor at 14 s with metal at 69% and energy at 43% of the lab's
	// draw: no plant until 146 s, the lab at 136 s, energy stalled (owner's game, BarR 1.1, 2026-11-25: "stalling metal
	// extractors on energy - bad!"; winners: solar 24 s, wind 29 s, lab 64 s).
	const bool leontief = (drawM > 0.f) && (drawE > 0.f) && (needM > 0.f || needE > 0.f);
	const float rM = (drawM > 0.f) ? s0.mInc / drawM : 1.f, rE = (drawE > 0.f) ? s0.eInc / drawE : 1.f;
	float bestV = -1e30f, bestTie = -1e30f;
	for (uint a = 0; a < opts.length(); ++a) {
		if (opts[a].kind == 2) continue;
		const float time = s0.pos.distance2D(opts[a].pos) / AiMax(1.f, speed) + opts[a].def.buildTime / AiMax(1.f, bp);
		const float tie = (opts[a].yieldM * mWorth + opts[a].yieldE * eWorth) / AiMax(1e-3f, time);
		float v = tie;
		if (leontief) {
			const float gain = AiMin(AiMin(1.f, rM + opts[a].yieldM / drawM), AiMin(1.f, rE + opts[a].yieldE / drawE)) - AiMin(AiMin(1.f, rM), AiMin(1.f, rE));
			v = gain / AiMax(1e-3f, time);
		}
		if (v > bestV || (v == bestV && tie > bestTie)) { bestV = v; bestTie = tie; best = int(a); }
	}
	if (best >= 0) why += "best producer per second of commander time: " + opts[best].def.GetName() + " " + F2(bestV) + (leontief ? (" (lab share: metal " + F2(rM) + ", energy " + F2(rE) + ")") : " metal-eq/s per s");
	return bestV;
}

// a planned extractor whose job ended without the extractor standing failed there (taken, blocked or unreachable):
// the opening stops planning that spot
array<int> failedSpots;
int plannedSpot = -1;
void OnTaskRemoved(IUnitTask@ task)
{
	if (task !is planned) return;
	@planned = null;
	checkSpot = plannedSpot;  // judged on the next update: a finished extractor registers after its job ends
	plannedSpot = -1;
}
int checkSpot = -1;
void CheckFailedSpot()
{
	if (checkSpot < 0) return;
	array<AIFloat3> sp; array<float> si; array<bool> so;
	AiGetMetalSpots(sp, si, so);
	if (uint(checkSpot) < sp.length() && !EcoPos::OwnSpot(sp[checkSpot]) && failedSpots.find(checkSpot) < 0) {
		failedSpots.insertLast(checkSpot);
		AiLog("[ANV-OPEN] spot " + checkSpot + " failed (job ended, no extractor): dropped from the plan");
	}
	checkSpot = -1;
}
}  // namespace Opening

/*
 * Command: Anarva's own army (owner, 2026-11-25: scrap BARb's army handling and rebuild it). BARb's squads, quotas,
 * promotions and raid/attack/defend tasks no longer get our combat units: military.as hands every armed mobile unit
 * to the module's player task, and this decides what each one does, every second.
 *
 *  1. Objectives: every known enemy unit and building (value = what it cost them + what it would yield them over our
 *     horizon + our buildings it threatens), and every spot we expect their economy at (EcoPos raid targets).
 *  2. Defence of an objective = the threat of every armed enemy that covers it: within its reach, or able to get in
 *     reach while we travel there.
 *  3. Assignment: objectives by value per second of travel; each takes the nearest free units until our strength
 *     beats its defence at our trade rate, and only if the square-law loss is below its value (no feeding).
 *  4. Execution: a defended objective is approached to just outside its defenders' reach and attacked when the squad
 *     has gathered there; in a fight every unit shoots the enemy in its reach worth most per point of health, and a
 *     unit that out-ranges the nearest enemy holds its own range from it (top 1v1 players' units keep moving in
 *     combat: 0.68 of top speed for bots and tanks, replays.db motion, 69 games).
 *  5. A squad whose strength no longer beats what defends its objective pulls back home.
 *  Free units wait at home. Every decision is logged ([ANV-CMD]).
 */
namespace Command {
/*
 * Pickets (owner's winners: singles spread early across their half, then one main squad; ~2 extractors lost by 12:00 vs
 * our 12-19 - replays.db): a lone raider kills a far extractor in seconds and the army needs 30-50 s to walk there (rv1:
 * nearly every loss a single Grunt 640-1920 from base). A unit stationed by an extractor answers in time. A site is worth
 * the losses measured around it (metal lost there per second of game, over the horizon) x the share of the fight our unit
 * wins against the raiders that killed there (as seen at each loss), where the main army can't arrive before an extractor
 * dies (its health over their dps); the unit is worth what it adds to the main fights instead (its metal at the lab's
 * value per metal of army now). Nearest free unit to the best site while that beats it; one unit covers what lies within
 * its reach in that kill time.
 */
dictionary picketAt;  // unit id -> "x,z"
void Pickets(array<CCircuitUnit@>@ freeUnits)
{
	if (freeUnits.length() == 0) return;
	const float tGame = AiMax(1.f, float(ai.frame) / SECOND);
	const float H = AiMax(1.f, Economist::Horizon());
	AIFloat3 ac(0.f, 0.f, 0.f); float aSpeed = 1e9f; uint na = 0;
	for (uint i = 0; i < freeUnits.length(); ++i) { ac = ac + freeUnits[i].GetPos(ai.frame); aSpeed = AiMin(aSpeed, freeUnits[i].circuitDef.speed); ++na; }
	ac = ac / float(AiMax(1, int(na)));
	const array<CCircuitUnit@>@ mine = AiGetTeamUnits();
	array<AIFloat3> site; array<float> siteHp; array<float> siteLoss;
	for (uint i = 0; i < mine.length(); ++i)
		if (!mine[i].circuitDef.IsMobile() && Facts::ExtractsMetal(mine[i].circuitDef.GetName()) > 0.f) {
			site.insertLast(mine[i].GetPos(ai.frame)); siteHp.insertLast(mine[i].circuitDef.health);
			siteLoss.insertLast(MexPorc::RaidLoss(mine[i], EcoPos::CheapestConstructor()));
		}
	// Before any loss is measured: the raiders we see. Each seen armed enemy can reach some of our extractors before our
	// army can (its walk + the kill time < the army's walk); it raids one at a time, so each such site carries 1/n of it.
	// (rv1/ca1: the first raids at 3:00-5:00 came before pickets had a measured loss to place them by.)
	array<float> seenLoss(site.length(), 0.f), seenE(site.length(), 0.f), seenD(site.length(), 0.f);
	{
		array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
		const uint ne = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
		for (uint e = 0; e < ne; ++e) {
			const CCircuitDef@ d = ed[e];
			if (d is null || !d.IsMobile() || d.IsAbleToFly() || d.GetSustainedDps() <= 0.f) continue;
			array<int> reach;
			for (uint k = 0; k < site.length(); ++k) {
				const float tE = ep[e].distance2D(site[k]) / AiMax(1.f, d.speed) + siteHp[k] / AiMax(1e-3f, d.GetSustainedDps());
				const float tA = ac.distance2D(site[k]) / AiMax(1.f, aSpeed);
				if (tE < tA) reach.insertLast(int(k));
			}
			const float st = sqrt(d.GetSustainedDps() * AiMax(1.f, eh[e] * d.health));
			for (uint r = 0; r < reach.length(); ++r) { seenLoss[reach[r]] += siteLoss[reach[r]] / float(reach.length()); seenE[reach[r]] = AiMax(seenE[reach[r]], st); seenD[reach[r]] = AiMax(seenD[reach[r]], d.GetSustainedDps()); }
		}
	}
	array<bool> used(freeUnits.length(), false), covered(site.length(), false);
	dictionary now;
	while (true) {
		int bs = -1, bu = -1; float bestNet = 0.f, bestV = 0.f, bestC = 0.f, bestT = 0.f, bestL = 0.f, bestW = 0.f;
		for (uint k = 0; k < site.length(); ++k) {
			if (covered[k]) continue;
			int nu = -1; float nd = 1e30f;
			for (uint i = 0; i < freeUnits.length(); ++i) if (!used[i]) { const float d = freeUnits[i].GetPos(ai.frame).distance2D(site[k]); if (d < nd) { nd = d; nu = int(i); } }
			if (nu < 0) break;
			const CCircuitDef@ ud = freeUnits[nu].circuitDef;
			float lm = 0.f, le = 0.f, ld = 0.f, nl = 0.f;
			for (uint j = 0; j < Economist::lossPos.length(); ++j) {
				// a loss counts where this unit, standing here, could have reached it while the raider shot
				const float tK = siteHp[k] / AiMax(1e-3f, Economist::lossD[j]);
				if (Economist::lossPos[j].distance2D(site[k]) > ud.GetMaxRange() + ud.speed * tK) continue;
				lm += Economist::lossM[j]; le += Economist::lossE[j]; ld += Economist::lossD[j]; nl += 1.f;
			}
			const float us = sqrt(AiMax(0.f, ud.GetSustainedDps()) * AiMax(1.f, ud.health));
			float V = 0.f, win = 0.f, tKill = 0.f;
			if (nl > 0.f) {
				const float eRaid = le / nl;
				tKill = siteHp[k] / AiMax(1e-3f, ld / nl);
				if (ac.distance2D(site[k]) / AiMax(1.f, aSpeed) > tKill) {  // else the army gets there in time anyway
					win = Production::WinShare(us, eRaid);
					V = lm / tGame * H * win;
				}
			}
			if (seenLoss[k] > 0.f) {
				const float w2 = Production::WinShare(us, seenE[k]);
				if (seenLoss[k] * w2 > V) { V = seenLoss[k] * w2; win = w2; tKill = siteHp[k] / AiMax(1e-3f, seenD[k]); lm = seenLoss[k]; }
			}
			if (V <= 0.f) continue;
			const float C = ud.costM * AiMax(0.f, Production::lastBestRatio);
			if (V - C > bestNet) { bestNet = V - C; bs = int(k); bu = nu; bestV = V; bestC = C; bestT = tKill; bestL = lm; bestW = win; }
		}
		if (bs < 0) break;
		used[bu] = true;
		CCircuitUnit@ u = freeUnits[bu];
		const CCircuitDef@ ud = u.circuitDef;
		for (uint k = 0; k < site.length(); ++k) if (site[k].distance2D(site[bs]) <= ud.GetMaxRange() + ud.speed * bestT) covered[k] = true;
		const string key = int(site[bs].x) + "," + int(site[bs].z);
		string prev = "";
		if (!picketAt.get("" + u.id, prev)) prev = "";
		if (prev != key) AiLog("[ANV-PICKET] " + ud.GetName() + " -> (" + key + "): losses there " + int(bestL) + " over " + int(tGame) + " s, x H " + int(H)
			+ " x win " + F2(bestW) + " = " + int(bestV) + " > its value in the army " + int(bestC) + " (kill time " + int(bestT) + " s)");
		now.set("" + u.id, key);
		// a picket holds its post: on attack-move it chased fast raiders away from it (Pawns killed chasing Incisors, 39 in
		// rp2); standing, it fires at what enters its reach
		if (u.GetPos(ai.frame).distance2D(site[bs]) > ud.GetMaxRange()) u.CmdMoveTo(site[bs]);
	}
	picketAt = now;
	for (int i = int(freeUnits.length()) - 1; i >= 0; --i) if (used[i]) freeUnits.removeAt(i);
}
class Op {
	float wpDist = 1e30f;  // the squad's summed distance to its current waypoint at the last update (progress test)
	int enemyId = -1;  // -1: a place (expected economy)
	AIFloat3 pos;
	float value = 0.f;
	float defence = 0.f;
	bool engaged = false;
	array<CCircuitUnit@> units;
	array<AIFloat3> route;  // waypoints (group movement, #93)
	bool arrived = false;
	AIFloat3 routeTo;
	uint leg = 0;
	float startMetal = 0.f;  // for the outcome log
	int startFrame = 0;
	float killedAtStart = 0.f;
}
array<Op@> ops;

/*
 * Group movement (#93, owner: BARb's movement is stupid; squads move and path as one). A route is a search over the
 * Intel grid: a cell costs its length x (1 + enemy threat covering it / our squad's strength), so time under fire
 * costs in proportion to how outmatched we are there, and cells our units can't stand on are skipped. The squad walks
 * it waypoint by waypoint at its slowest member's speed, moving on only when every unit is within its own reach of
 * the current waypoint.
 */
array<AIFloat3> Route(const AIFloat3& in from, const AIFloat3& in to, CCircuitUnit@ probe, float S)
{
	array<AIFloat3> path;
	const int w = Intel::gw, h = Intel::gh;
	const float cell = Intel::CELL;
	if (w <= 0 || h <= 0 || cell <= 0.f) { path.insertLast(to); return path; }
	const int sx = AiMin(w - 1, AiMax(0, int(from.x / cell))), sz = AiMin(h - 1, AiMax(0, int(from.z / cell)));
	const int tx = AiMin(w - 1, AiMax(0, int(to.x / cell))), tz = AiMin(h - 1, AiMax(0, int(to.z / cell)));
	const int N = w * h;
	array<float> cost(N); array<int> prev(N); array<bool> done(N); array<float> thr(N); array<bool> pass(N);
	for (int c = 0; c < N; ++c) {
		cost[c] = 1e30f; prev[c] = -1; done[c] = false;
		const AIFloat3 centre((float(c % w) + 0.5f) * cell, 0.f, (float(c / w) + 0.5f) * cell);
		pass[c] = probe.CanMoveTo(centre);
		thr[c] = pass[c] ? Cover(centre, 0.f) : 0.f;
	}
	const int start = sz * w + sx, goal = tz * w + tx;
	pass[start] = true; pass[goal] = true;
	cost[start] = 0.f;
	const float strength = AiMax(1e-3f, S);
	for (int it = 0; it < N; ++it) {
		int u = -1; float best = 1e30f;
		for (int c = 0; c < N; ++c) if (!done[c] && cost[c] < best) { best = cost[c]; u = c; }
		if (u < 0 || u == goal) break;
		done[u] = true;
		const int ux = u % w, uz = u / w;
		for (int dz = -1; dz <= 1; ++dz) for (int dx = -1; dx <= 1; ++dx) {
			if (dx == 0 && dz == 0) continue;
			const int vx = ux + dx, vz = uz + dz;
			if (vx < 0 || vz < 0 || vx >= w || vz >= h) continue;
			const int v = vz * w + vx;
			if (done[v] || !pass[v]) continue;
			const float len = cell * sqrt(float(dx * dx + dz * dz));
			const float c2 = cost[u] + len * (1.f + thr[v] / strength);
			if (c2 < cost[v]) { cost[v] = c2; prev[v] = u; }
		}
	}
	array<int> cells;
	for (int c = goal; c >= 0 && c != start; c = prev[c]) cells.insertLast(c);
	for (int k = int(cells.length()) - 1; k >= 1; --k) {  // the goal cell itself is replaced by the exact target
		const int c = cells[k];
		path.insertLast(AIFloat3((float(c % w) + 0.5f) * cell, 0.f, (float(c / w) + 0.5f) * cell));
	}
	path.insertLast(to);
	return path;
}
// move the op's squad toward dest as one; returns true once every unit is within its own reach of dest
bool MoveGroup(Op@ op, uint o, const AIFloat3& in dest)
{
	if (op.units.length() == 0) return false;
	CCircuitUnit@ lead = op.units[0];
	float slowest = 1e9f;
	AIFloat3 c(0.f, 0.f, 0.f);
	for (uint k = 0; k < op.units.length(); ++k) { c = c + op.units[k].GetPos(ai.frame); slowest = AiMin(slowest, op.units[k].circuitDef.speed); }
	c = c / float(op.units.length());
	if (op.route.length() == 0 || op.routeTo.distance2D(dest) > Intel::CELL) {
		op.route = Route(c, dest, lead, Strength(op.units));
		// every waypoint must be reachable by each unit's move type (the engine's own reach test): one on a crater rim a unit
		// can't climb was never "reached", the squad waited on it and its units pushed at the slope instead of fighting
		// (owner, 2026-11-26: "you stopped microing the army because it cant reach the top of the crater edge"; #113)
		for (int w = int(op.route.length()) - 1; w >= 0; --w) {
			bool ok = true;
			for (uint k = 0; k < op.units.length() && ok; ++k)
				ok = AiDefCanReach(ai.GetCircuitDef(op.units[k].circuitDef.GetName()), op.units[k].GetPos(ai.frame), op.route[w]);
			if (!ok) op.route.removeAt(w);
		}
		if (op.route.length() == 0) op.route.insertLast(dest);
		op.routeTo = dest; op.leg = 0;
		AiLog("[ANV-CMD] route for " + op.units.length() + " units: " + op.route.length() + " waypoints to (" + int(dest.x) + "," + int(dest.z) + ")");
	}
	bool atWp = true;
	float dsum = 0.f;
	for (uint k = 0; k < op.units.length(); ++k) {
		const float dk = op.units[k].GetPos(ai.frame).distance2D(op.route[op.leg]);
		dsum += dk;
		if (dk > op.units[k].circuitDef.GetMaxRange()) atWp = false;
	}
	// no waiting on a condition that may never come (owner, 2026-11-26): when the squad stopped getting closer to the
	// waypoint since the last update (a unit blocked by terrain or by others), it goes on to the next one
	if (!atWp && dsum >= op.wpDist) atWp = true;
	op.wpDist = dsum;
	if (atWp && op.leg + 1 < op.route.length()) { ++op.leg; atWp = false; op.wpDist = 1e30f; }
	if (atWp && op.leg + 1 >= op.route.length()) return true;
	for (uint k = 0; k < op.units.length(); ++k) {
		if (FightInReach(op.units[k])) continue;  // what it meets on the way, it fights
		string prevKey;
		const string key = "grp" + o + ":" + op.leg + ":" + int(op.routeTo.x) + "," + int(op.routeTo.z);
		if (lastOrder.get("" + op.units[k].id, prevKey) && prevKey == key) continue;
		lastOrder.set("" + op.units[k].id, key);
		// attack-move (owner, 2026-11-26: "maybe your fighting principles are kinda bad"): on a plain move the squad
		// walked past what shot it - ops lost 3800-7000 metal for 0 killed ("target gone", mm1); Fight engages on the way
		op.units[k].CmdFightTo(op.route[op.leg]);
		op.units[k].CmdWantedSpeed(slowest);  // together: the squad moves at its slowest member's pace
	}
	return false;
}
dictionary lastOrder;  // unit id -> last order key (re-issued only when it changes)
dictionary lastTarget;  // unit id -> enemy id it was told to prefer
dictionary strafeSide;  // unit id -> "+" / "-" (side of its next sideways step)
int created = 0, retreats = 0;

// every armed mobile unit (BARb's scout role also covers raiders such as the Grunt, so it can't exclude anything)
bool Owns(const CCircuitDef@ d) { return IsArmy(d); }

// enemy snapshot, refreshed each second
array<AIFloat3> ePos; array<AIFloat3> eVel; array<CCircuitDef@> eDef; array<float> eCost, eHp, eBuilt; array<int> eFlags, eIds;
float spotIncome = 0.f;

float EnemyValue(uint i, float H)
{
	const CCircuitDef@ d = eDef[i];
	if (d is null) return eCost[i];
	const string nm = d.GetName();
	float v = Economist::MetalValue(d);
	const float upkeep = Facts::EnergyUpkeep(nm);
	const float eYield = Facts::EnergyMake(nm) + ((upkeep < 0.f) ? -upkeep : 0.f);
	float yield = Economist::Extract(nm) * MexPorc::SpotMetalAt(ePos[i], d) + Facts::MetalMake(nm) + eYield / AiMax(1e-3f, Economist::energyPerMetal);
	// a factory yields its production: its build power x the metal per build-second of what it makes (as our own lab is
	// valued, MexPorc::RaidLoss)
	if (!d.IsMobile() && d.buildSpeed > 0.f) {
		const array<string>@ fo = Facts::BuildOptions(nm);
		float sm = 0.f, sbt = 0.f;
		for (uint k = 0; k < fo.length(); ++k) { CCircuitDef@ o = ai.GetCircuitDef(fo[k]); if (o !is null && o.IsMobile()) { sm += o.costM; sbt += o.buildTime; } }
		if (sbt > 0.f) yield += d.buildSpeed * sm / sbt;
	}
	// Valued as we value our own (#107, owner: "you should judge enemy buildings the same way you judge ours";
	// "usefulness to the enemy is the detriment to us"): its cost and what it yields them over the same horizon we give
	// our own producers. Counted only until they could rebuild it, a seen enemy extractor was worth ~1/5 of the same
	// extractor of ours (and of an unseen enemy spot, valued over the horizon): the army skipped them while BARb's
	// buildings reached 28-38k against our 1.5-5k at 20:00.
	// what a kill takes from them is its yield until they could stand it again (a constructor's walk from their base and
	// its build), symmetric with what a raid takes from us (MexPorc::RaidLoss). (Over the whole horizon - #107 - the
	// army over-committed: trades 0.46-0.67 in six games against 0.76-0.92 without, ev1-6.)
	if (yield > 0.f) {
		const CCircuitDef@ con = EcoPos::CheapestConstructor();
		float rebuild = H;
		if (con !is null) rebuild = AiMin(H, AiEnemyBasePos().distance2D(ePos[i]) / AiMax(1.f, con.speed) + d.buildTime / AiMax(1.f, con.buildSpeed));
		v += yield * rebuild;
	}
	return v;
}
// armed enemies covering p: in their reach now, or able to get there within t seconds
float Cover(const AIFloat3& in p, float t)
{
	float d = 0.f;
	for (uint i = 0; i < ePos.length(); ++i) {
		const CCircuitDef@ ed = eDef[i];
		if (ed is null || ed.threat <= 0.f || ed.surfThrDmg <= 0.f) continue;
		const float reach = ed.GetMaxRange() + (ed.IsMobile() ? ed.speed * t : 0.f);
		if (ePos[i].distance2D(p) <= reach) d += ed.threat;
	}
	return d;
}
// value of our buildings an enemy threatens (killing it saves them)
// (tAnswer: how long our army needs to reach it - what it can get to before we can answer is what it threatens. It
// was one second: an army two minutes out threatened nothing until it stood in our base.)
float OursThreatened(uint i, const array<CCircuitUnit@>@ mine, float tAnswer)
{
	const CCircuitDef@ ed = eDef[i];
	if (ed is null || ed.surfThrDmg <= 0.f) return 0.f;
	float v = 0.f;
	for (uint k = 0; k < mine.length(); ++k) {
		const CCircuitDef@ d = mine[k].circuitDef;
		// the commander is the game: threatened, it is worth everything (left out, Raiders killed it at home at 13:12
		// while the army of 58-69 reinforced an attack 1200 away, cmd_m77)
		if (mine[k] is commander) {
			// worth the game only as far as it can kill the commander: the chance the commander dies there in the time we
			// need to answer (CommPDeath, all enemies near), this enemy's share of the threat near it. Counted as the
			// whole game, every raider at home read 15000-16000 - every home op as valuable as every other, so no op gave
			// units to another and lone Incisors met 2 units at a time (en6, 3:00-5:20)
			const AIFloat3 cpos = commander.GetPos(ai.frame);
			if (cpos.distance2D(ePos[i]) <= ed.GetMaxRange() + ed.speed * AiMax(1.f, tAnswer)) {
				float near = 0.f;
				for (uint j = 0; j < eDef.length(); ++j) {
					const CCircuitDef@ ej = eDef[j];
					if (ej is null || ej.surfThrDmg <= 0.f) continue;
					if (cpos.distance2D(ePos[j]) <= ej.GetMaxRange() + ej.speed * AiMax(1.f, tAnswer)) near += ej.threat;
				}
				const float share = (near > 0.f) ? ed.threat / near : 1.f;
				v += GameValue() * CommPDeath(cpos, AiMax(1.f, tAnswer)) * share;
			}
			continue;
		}
		if (d.IsMobile()) continue;
		if (mine[k].GetPos(ai.frame).distance2D(ePos[i]) <= ed.GetMaxRange() + ed.speed * AiMax(1.f, tAnswer)) {
			// what we lose with it: its cost and what it would yield us over the horizon (same terms as an enemy's value)
			const string nm = d.GetName();
			const float upkeep = Facts::EnergyUpkeep(nm);
			const float eYield = Facts::EnergyMake(nm) + ((upkeep < 0.f) ? -upkeep : 0.f);
			const float yield = Economist::Extract(nm) * MexPorc::SpotMetalAt(mine[k].GetPos(ai.frame), d) + Facts::MetalMake(nm) + eYield / AiMax(1e-3f, Economist::energyPerMetal);
			// what a raid takes: its cost and its yield until it stands again, as for raid towers (MexPorc::RaidLoss).
			// With its whole future yield every defence looked worth any odds and the army threw itself away (army
			// 54-354 at minute 8 in round 31 vs 1400-1900 at minute 12 in round 30).
			if (yield >= 0.f) v += MexPorc::RaidLoss(mine[k], EcoPos::CheapestConstructor());
		}
	}
	return v;
}
// An enemy this unit can shoot now: visible (not a radar blip), ground or air as its weapon allows, within its reach;
// the one with the most damage per remaining health (the squads' fire order, Lanchester). -1 if none.
// (Moving on with an enemy in reach, units didn't fire 20-35% of contact samples: most were Pawns beside Gators on group
// moves - a forward-arc weapon can't shoot what it walks away from; mu2/mu3/ml3/bt2, [ANV-IDLE] id1.)
array<AIFloat3> rePos; array<CCircuitDef@> reDef; array<float> reHp; array<int> reFlags, reIds; int reFrame = -1;
int InReachTarget(CCircuitUnit@ u)
{
	if (reFrame != ai.frame) {
		reFrame = ai.frame;
		array<AIFloat3> ev; array<float> ec, eb;
		AiGetEnemies(rePos, ev, reDef, ec, reFlags, reHp, eb);
		AiGetEnemyIds(reIds);
	}
	const CCircuitDef@ d = u.circuitDef;
	if (d.GetSustainedDps() <= 0.f) return -1;
	const AIFloat3 p = u.GetPos(ai.frame);
	const float reach = d.GetMaxRange();
	int best = -1; float bv = -1.f;
	for (uint k = 0; k < rePos.length() && k < reIds.length(); ++k) {
		const CCircuitDef@ e = reDef[k];
		if (e is null || (reFlags[k] & 2) == 0) continue;  // a blip has no known type
		if (e.IsAbleToFly() ? d.airThrDmg <= 0.f : d.surfThrDmg <= 0.f) continue;  // our weapon can't hit it
		if (rePos[k].distance2D(p) > reach) continue;
		const float v = e.GetSustainedDps() / AiMax(1.f, reHp[k] * e.health) + 1e-6f / AiMax(1.f, reHp[k] * e.health);  // unarmed last, weakest first
		if (v > bv) { bv = v; best = reIds[k]; }
	}
	return best;
}
// a unit with an enemy in reach fights it; otherwise it takes the order (re-issued only when the key changes)
bool FightInReach(CCircuitUnit@ u)
{
	const int t = InReachTarget(u);
	if (t < 0) return false;
	const string key = "hit" + t;
	string prev;
	if (lastOrder.get("" + u.id, prev) && prev == key) return true;
	lastOrder.set("" + u.id, key);
	u.CmdAttackEnemy(t);
	return true;
}
void Order(CCircuitUnit@ u, const string& in key, int kind, const AIFloat3& in p, int target)
{
	if (key.findFirst("home") != 0 && FightInReach(u)) return;  // pulling back means leaving: no stopping to fight
	string prev;
	if (lastOrder.get("" + u.id, prev) && prev == key) return;
	lastOrder.set("" + u.id, key);

	u.CmdMoveTo(p);
}
// A fight is worth taking when what it keeps beats what it risks: p = our share at strength S x trade against defence
// D (the win share production uses); winning keeps the value at a square-law share of our metal lost, losing costs it
// all. A fixed "S x trade > D" gate skipped a Pawn raid at our base 7 times at 11.0 vs 11.4 while it killed 1880
// metal of economy (Theta, round 30): an even fight for that much is taken by any player.
array<AIFloat3> shownPos; array<float> shownDef; array<float> shownReach;  // defences fights revealed (pulled back)
// Lanchester square law, as the fights play out: the stronger side wins and loses metal x (D/S)^2; the weaker loses all
// it sent and kills (S/D)^2 of what it faces. (WinShare S/(S+D) read as a probability of winning gave a squad 5.5x the
// defence a 15% chance of losing everything: 31 units pulled back from undefended raid spots within a second, and an
// army 2x BARb's sat idle from 12:00 to 20:00 while their buildings stood at 28810 vs our 5085 - pl3.)
float FightGain(float value, float S, float D, float metal)
{
	const float st = S * AiMax(1e-3f, Assess::trade);
	if (D <= 0.f) return value;
	if (st > D) {
		const float r = D / st;
		return value - metal * r * r;
	}
	// the weaker side kills (S/D)^2 of what it FACES - the defenders' metal (their strength at our metal per strength) -
	// not of the target's value: as value x k^2 a half-strength fight on a 15000 target read +1750 and went in; 54 ops
	// lost >500 each against predicted losses of ~1000 they took anyway (trade 0.45 over 304 ops, bp1-2/lr1-3/lp1/kt1/dp1)
	const float k = st / AiMax(1e-6f, D);
	const float defMetal = D * metal / AiMax(1e-3f, S);
	return defMetal * k * k - metal;
}
// A unit's threat in a fight against the enemies we've seen: its generic threat x its fighting power against them
// (Production::SurfPower: range gap, splash on a massed squad, hit chance) over its plain sqrt(dps x health). Summed
// as generic threat, 11 Pawns judged 15.7 vs 9.3 attacked two Levelers and 10 died in 2 s to splash (cmd_m28, 7:00).
Brain::Production::Mix fightMix;
int fightMixFrame = -1;
float EffThreat(const CCircuitDef@ d)
{
	if (fightMixFrame != ai.frame) { fightMix = Brain::Production::Mix(); Brain::Production::FillMix(fightMix, null); fightMixFrame = ai.frame; }
	if (fightMix.w.length() == 0 || d.surfThrDmg <= 0.f) return d.threat;
	const float plain = sqrt(AiMax(0.f, d.surfThrDmg) * AiMax(1.f, d.health));
	string tm;
	return d.threat * Brain::Production::SurfPower(d, fightMix, tm) / AiMax(1e-3f, plain);
}
float Strength(const array<CCircuitUnit@>@ us)
{
	float s = 0.f;
	for (uint i = 0; i < us.length(); ++i) s += EffThreat(us[i].circuitDef);
	return s;
}

void Update()
{
	if (!HasBase()) return;
	const IUnitTask@ mine = aiMilitaryMgr.GetPlayerTask();
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	array<CCircuitUnit@> force;
	for (uint i = 0; i < all.length(); ++i)
		if (Owns(all[i].circuitDef) && all[i].task is mine && !Scout::IsScout(all[i])) force.insertLast(all[i]);
	const uint n = AiGetEnemies(ePos, eVel, eDef, eCost, eFlags, eHp, eBuilt);
	AiGetEnemyIds(eIds);
	{
		array<AIFloat3> sp; array<float> si; array<bool> so;
		const uint ns = AiGetMetalSpots(sp, si, so);
		float sum = 0.f;
		for (uint i = 0; i < ns; ++i) sum += si[i];
		const float avg = (ns > 0) ? sum / float(ns) : 0.f;
		spotIncome = (Economist::mexT1 is null) ? 0.f : avg * Economist::Extract(Economist::mexT1.GetName());
	}
	const float H = AiMax(1.f, Economist::Horizon());
	const float trade = AiMax(1e-3f, Assess::trade);

	// a shown defence holds while enemies are still seen there
	for (int k = int(shownPos.length()) - 1; k >= 0; --k)
		if (Cover(shownPos[k], 0.f) <= 0.f) { shownPos.removeAt(k); shownDef.removeAt(k); shownReach.removeAt(k); }
	// keep live ops: drop dead units, finished targets, and fights we no longer win
	dictionary assigned;
	for (int o = int(ops.length()) - 1; o >= 0; --o) {
		Op@ op = ops[o];
		for (int k = int(op.units.length()) - 1; k >= 0; --k)
			if (force.findByRef(op.units[k]) < 0) op.units.removeAt(k);
		bool alive = op.enemyId < 0;
		int ti = -1;
		for (uint i = 0; i < n && !alive; ++i)
			if (eIds[i] == op.enemyId) { alive = true; op.pos = ePos[i]; ti = int(i); }
		// still catchable, the launch test: a mobile target moving away at least as fast as the squad is gone. Kept on it,
		// the whole army (48-51) followed a fleeing unit to their base while their push took ours and the commander at
		// 17:17 (cmd_m104)
		if (alive && ti >= 0 && eDef[ti] !is null && eDef[ti].IsMobile() && op.units.length() > 0) {
			AIFloat3 sc(0.f, 0.f, 0.f); float slow = 1e9f, rng = 0.f;
			for (uint k = 0; k < op.units.length(); ++k) { sc = sc + op.units[k].GetPos(ai.frame); slow = AiMin(slow, op.units[k].circuitDef.speed); rng = AiMax(rng, op.units[k].circuitDef.GetMaxRange()); }
			sc = sc / float(op.units.length());
			const AIFloat3 away = ePos[ti] - sc;
			const float dist = away.Length2D();
			const float vAway = (dist > 0.f) ? (eVel[ti].x * away.x + eVel[ti].z * away.z) / dist * SECOND : 0.f;
			if (dist > rng && vAway >= slow) alive = false;  // ends below as "target gone"
		}
		if (op.enemyId < 0 && AiIsInLOS(op.pos)) {
			bool there = false;
			for (uint i = 0; i < n && !there; ++i)
				if (eDef[i] !is null && !eDef[i].IsMobile() && ePos[i].distance2D(op.pos) <= eDef[i].GetRadius() * 2.f) there = true;
			alive = there;  // the place is in sight and holds nothing: nothing to raid there
		}
		const float S = Strength(op.units);
		// What can fight this squad: at the target, and on its way there - enemies that can reach the squad where it is
		// now within the time it still needs to arrive (raids were checked at the target only, at launch; single Grunts
		// walked on into Blitzes and died 4000+ elmos from base, 7 kills for 71 losses on Canis, 2026-11-26).
		op.defence = Cover(op.pos, 0.f);
		if (op.units.length() > 0) {
			AIFloat3 oc0(0.f, 0.f, 0.f);
			float slow = 1e9f;
			for (uint k = 0; k < op.units.length(); ++k) { oc0 = oc0 + op.units[k].GetPos(ai.frame); slow = AiMin(slow, op.units[k].circuitDef.speed); }
			oc0 = oc0 / float(op.units.length());
			const float tLeft = oc0.distance2D(op.pos) / AiMax(1.f, slow);
			// the launch test's terms, so launch and continuation read one defence: at the target while we kill it, half
			// way by half the walk, at the squad now. Cover(squad, whole walk) read 16.5 where launch read 7.5 for the
			// same raid spot: launched and pulled back every update, 24-30 units idle for minutes (fb1 11:30-12:30)
			float dpsN = 0.f;
			for (uint k = 0; k < op.units.length(); ++k) dpsN += op.units[k].circuitDef.GetSustainedDps();
			float hpT = (Economist::mexT1 !is null) ? Economist::mexT1.health : 1.f;
			for (uint i = 0; i < n; ++i) if (eIds[i] == op.enemyId && eDef[i] !is null) { hpT = eDef[i].health * eHp[i]; break; }
			const float tFightN = hpT / AiMax(1e-3f, dpsN);
			op.defence = AiMax(AiMax(Cover(op.pos, AiMax(tFightN, tLeft)), Cover((oc0 + op.pos) * 0.5f, tLeft * 0.5f)), Cover(oc0, 0.f));
		}
		float opMetal = 0.f;
		for (uint k = 0; k < op.units.length(); ++k) opMetal += op.units[k].circuitDef.costM;
		// what the fight has shown: by the square law the loss ratio is the strength ratio, so the defence it meets is at
		// least our strength x metal lost / enemy metal killed since it began - also when the shooters are out of sight.
		// Counting seen enemies only, one op took Pawns in one at a time from minute 8 to 10 at ratio 1.2 -> 0.1 and lost
		// 2179 without pulling back (Thuds and Grunts, Canis vs Cortex cmd_m37)
		{
			const float lostM = AiMax(0.f, op.startMetal - opMetal);
			const float killedM = Assess::killedTotal - op.killedAtStart;
			// ...once the fight has had time to kill anything: kills lag losses by the target's health over our dps. Read
			// from the first second, one loss over ~0 kills gave defence 57227-90056 and the army pulled back and
			// relaunched 8 times in 10 s in our own base while Mists killed the commander (cmd_m73, 14:12-14:42)
			float dps = 0.f;
			for (uint k = 0; k < op.units.length(); ++k) dps += op.units[k].circuitDef.GetSustainedDps();
			float tgtHp = (Economist::mexT1 !is null) ? Economist::mexT1.health : 1.f;
			for (uint i = 0; i < n; ++i) if (eIds[i] == op.enemyId && eDef[i] !is null) { tgtHp = eDef[i].health * eHp[i]; break; }
			const float age = float(ai.frame - op.startFrame) / SECOND;
			// square law: the loss ratio is the strength ratio squared (as FightGain prices it), so D = S x sqrt(lost/killed);
			// linear, a pull-back with ~nothing killed read defence 34795 against our 129 and the army skipped every target
			// for the rest of the game while 2.3x stronger (fr1, 16:07)
			// The square law's own inversion: a won fight costs our metal x (D/S)^2, so the defence our losses imply is
			// D = S x sqrt(lost / metal sent) - independent of what we've killed. (From lost/killed, with ~nothing killed in
			// the first seconds it read 448-491 against our 62-67: 33 units launched and pulled back 1-2 s later, 205
			// times in hc2, and the army never finished a fight.)
			if (lostM > 0.f && age >= tgtHp / AiMax(1e-3f, dps)) op.defence = AiMax(op.defence, S * sqrt(lostM / AiMax(1.f, op.startMetal)));
		}
		if (!alive || op.units.length() == 0 || FightGain(op.value, S, op.defence, opMetal) <= 0.f) {
			if (alive && op.units.length() > 0) {
				// what this fight showed, for the next launch here (launch and keep must read the same defence: relaunched
				// fresh, the army pulled back and returned ~15 times in 40 s at a group of Levelers and lost 7586 in a
				// minute, cmd_m75). Its reach: the longest enemy weapon there.
				float rmax = 0.f;
				for (uint i = 0; i < n; ++i)
					if (eDef[i] !is null && eDef[i].surfThrDmg > 0.f && ePos[i].distance2D(op.pos) <= eDef[i].GetMaxRange() + eDef[i].speed * float(ai.frame - op.startFrame) / SECOND)
						rmax = AiMax(rmax, eDef[i].GetMaxRange() + eDef[i].speed * float(ai.frame - op.startFrame) / SECOND);
				shownPos.insertLast(op.pos); shownDef.insertLast(op.defence); shownReach.insertLast(rmax);
				++retreats;
				AiLog("[ANV-CMD] pull back from (" + int(op.pos.x) + "," + int(op.pos.z) + "): strength " + F1(S) + " x trade "
					+ F1(trade) + " <= defence " + F1(op.defence));
				for (uint k = 0; k < op.units.length(); ++k) Order(op.units[k], "home", 0, basePos, -1);
			}
			{  // outcome: what the op cost and what was killed meanwhile (all kills, our whole army's)
				float left = 0.f;
				for (uint k = 0; k < op.units.length(); ++k) left += op.units[k].circuitDef.costM;
				AiLog("[ANV-FIGHT] f=" + ai.frame + " op " + (op.enemyId < 0 ? "raid spot" : ("enemy " + op.enemyId)) + " at (" + int(op.pos.x) + "," + int(op.pos.z)
					+ ") ended after " + ((ai.frame - op.startFrame) / SECOND) + " s: " + (alive ? (op.units.length() == 0 ? "squad lost" : "pulled back") : "target gone")
					+ ", metal sent " + int(op.startMetal) + " left " + int(left) + ", enemy metal killed meanwhile " + int(Assess::killedTotal - op.killedAtStart)
					// where it was: share of the way to their base (0 ours, 1 theirs), to judge pushes by depth (#116)
					+ ", forward " + F2(basePos.distance2D(op.pos) / AiMax(1.f, basePos.distance2D(AiEnemyBasePos()))));
			}
			ops.removeAt(o);
			continue;
		}
		for (uint k = 0; k < op.units.length(); ++k) assigned.set("" + op.units[k].id, true);
	}
	array<CCircuitUnit@> freeUnits;
	for (uint i = 0; i < force.length(); ++i)
		if (!assigned.exists("" + force[i].id)) freeUnits.insertLast(force[i]);
	Pickets(freeUnits);
	// concentration: free units reinforce the most valuable defended fight already running (the square law rewards
	// every unit added there); undefended raids keep their single unit
	{
		int bestOp = -1;
		for (uint o = 0; o < ops.length(); ++o)
			if (ops[o].defence > 0.f && (bestOp < 0 || ops[o].value > ops[bestOp].value)) bestOp = int(o);
		if (bestOp >= 0 && freeUnits.length() > 0) {
			for (uint i = 0; i < freeUnits.length(); ++i) { ops[bestOp].units.insertLast(freeUnits[i]); ops[bestOp].startMetal += freeUnits[i].circuitDef.costM; }
			ops[bestOp].route.resize(0);  // re-route the bigger squad
			AiLog("[ANV-CMD] reinforce (" + int(ops[bestOp].pos.x) + "," + int(ops[bestOp].pos.z) + ") +" + freeUnits.length() + " units");
			freeUnits.resize(0);
		}
	}

	// new ops, best first, while the free units can win them
	// Targets are weighed even when no unit is free: with the whole army out on an op, Grunts killing our extractors were
	// never looked at, so nothing was ever detached to them (spectator, spec1 3:44: the army, 2.5x the enemy known, on a
	// raid at their corner; cc1: 27 extractors lost, the army 740-3420 away each time). The pool measured is then the army.
	array<CCircuitUnit@> pool = freeUnits;
	if (pool.length() == 0) for (uint o = 0; o < ops.length(); ++o) for (uint k = 0; k < ops[o].units.length(); ++k) pool.insertLast(ops[o].units[k]);
	if (pool.length() > 0) {
		AIFloat3 fc(0.f, 0.f, 0.f);
		float fSpeed = 1e9f;
		for (uint i = 0; i < pool.length(); ++i) { fc = fc + pool[i].GetPos(ai.frame); fSpeed = AiMin(fSpeed, pool[i].circuitDef.speed); }
		fc = fc / float(pool.length());
		fSpeed = AiMax(1.f, fSpeed);
		float freeDps = 0.f;
		for (uint i = 0; i < pool.length(); ++i) freeDps += pool[i].circuitDef.GetSustainedDps();
		array<AIFloat3> cp; array<float> cv; array<int> cid; array<float> chp; array<float> cspd; array<int> cix;
		for (uint i = 0; i < n; ++i) {
			if (eDef[i] is null || eDef[i].IsAbleToFly() || (eFlags[i] & 2) == 0) continue;
			bool taken = false;
			for (uint o = 0; o < ops.length() && !taken; ++o) if (ops[o].enemyId == eIds[i]) taken = true;
			if (taken) continue;
			cp.insertLast(ePos[i]); cv.insertLast(EnemyValue(i, H) + OursThreatened(i, all, fc.distance2D(ePos[i]) / fSpeed)); cid.insertLast(eIds[i]);
			chp.insertLast(eHp[i] * eDef[i].health);
			cspd.insertLast(eDef[i].IsMobile() ? eVel[i].Length2D() * SECOND : 0.f);  // how fast it moves now
			cix.insertLast(int(i));
		}
		for (uint i = 0; i < EcoPos::raidPos.length(); ++i) {
			if (AiIsInLOS(EcoPos::raidPos[i])) continue;  // in sight: the known enemies above cover it
			// a spot an op already has is taken, as an enemy an op has is (raid spots carry no id, so the same corner was
			// picked again each update: ops [1@6800,752 1@6800,752 2@6800,752] at 3:00 - the army in singles, aw1)
			bool had = false;
			for (uint o = 0; o < ops.length() && !had; ++o) if (ops[o].enemyId < 0 && ops[o].pos.distance2D(EcoPos::raidPos[i]) < 1.f) had = true;
			if (had) continue;
			cp.insertLast(EcoPos::raidPos[i]); cv.insertLast(EcoPos::raidVal[i]); cid.insertLast(-1);
			chp.insertLast(Economist::mexT1 !is null ? Economist::mexT1.health : 0.f);  // what a raid spot holds
			cspd.insertLast(0.f);
			cix.insertLast(-1);
		}
		float fRange = 0.f;
		for (uint i = 0; i < pool.length(); ++i) fRange += pool[i].circuitDef.GetMaxRange();
		fRange /= AiMax(1.f, float(pool.length()));
		array<float> score(cp.length());
		array<float> dfc(cp.length());
		// An unscouted spot isn't undefended: expect the enemy's towers per extractor among what we've seen, at their mean
		// threat (live). Taken as 0, ten lone Pawns raided nine spots at 5:40 and light lasers killed 8 of them (Canis vs
		// Cortex, cmd_m19); Armada winners there face 6.2 towers by 8:00 the other way round (replays.db, 28 games).
		float eTowers = 0.f, eMexes = 0.f, eTowerThreat = 0.f;
		for (uint i = 0; i < n; ++i) {
			const CCircuitDef@ ed = eDef[i];
			if (ed is null || ed.IsMobile()) continue;
			if (ed.surfThrDmg > 0.f && ed.threat > 0.f) { eTowers += 1.f; eTowerThreat += ed.threat; }
			else if (Facts::ExtractsMetal(ed.GetName()) > 0.f) eMexes += 1.f;
		}
		const float unseenDefence = (eTowers > 0.f) ? AiMin(1.f, eTowers / AiMax(1.f, eMexes)) * eTowerThreat / eTowers : 0.f;
		const array<float> cv0 = cv;  // each target's own value, before the groups are summed
		for (uint i = 0; i < cp.length(); ++i) {
			// a moving target is reached when we catch it: the gap beyond our range over how fast we close on it (its
			// speed now). The army of 21-25 chased lone Grunts as fast as itself, "target gone" after 19-31 s each,
			// while other Grunts killed 13 extractors and 7 constructors (Canis vs Cortex, 9:00-12:00, cmd_m21)
			float t = fc.distance2D(cp[i]) / fSpeed;
			if (cspd[i] > 0.f) {
				const float gap = fc.distance2D(cp[i]) - fRange;
				const float closing = fSpeed - cspd[i];
				t = (gap <= 0.f) ? 0.f : ((closing > 0.f) ? gap / closing : 1e9f);
			}
			// The defence is what fights there while we kill the target: enemies within reach of it for as long as the
			// fight lasts (its health over our dps; they answer once it starts). Counting everything that could reach the
			// spot during our whole march (60 s+) put BARb's whole army, commander included, on every lone raider: no op
			// was ever made, defend=0 while Favs and Flashes killed 13 producers (Eye of Horus 1v1, 2026-11-25).
			const float tFight = chp[i] / AiMax(1e-3f, freeDps);
			// the same test a running op must keep passing (what can reach the squad on its way, not only at the
			// target): launched on the target alone, 269 of 292 raids pulled back at once (Canis 2026-11-26)
			// on the way: an enemy fights the squad only where it can reach the path by the time the squad is there - here
			// now, half way at half the walk, the target on arrival. Cover(squad, whole walk) counted every enemy within its
			// speed x the trip of where the squad stands - on a long walk their whole army (defence 40-67 vs our ~100):
			// every raid read -2000..-4000 and the army sat idle at ratio 2.5-17 (cmd_m111)
			const AIFloat3 midW = (fc + cp[i]) * 0.5f;
			dfc[i] = AiMax(AiMax(Cover(cp[i], AiMax(tFight, t)), Cover(midW, t * 0.5f)), Cover(fc, 0.f));
			if (cid[i] < 0) dfc[i] = AiMax(dfc[i], unseenDefence);
			// what a fight revealed holds until we see the place again: then what we see there is the defence
			for (int k = int(shownPos.length()) - 1; k >= 0; --k) {
				if (AiIsInLOS(shownPos[k])) { shownPos.removeAt(k); shownDef.removeAt(k); shownReach.removeAt(k); continue; }
				if (shownPos[k].distance2D(cp[i]) <= shownReach[k]) dfc[i] = AiMax(dfc[i], shownDef[k]);
			}
			// the fight is with every enemy the defence counts there, and winning it kills them all and saves what they
			// threaten: its value is theirs together, as its defence is. Valued at the one target, our army (66-88) skipped
			// every unit of a push (defence 41-66, gain -1000 to -3000 each) while it took the base and the commander
			// at 14:19 (Canis vs Cortex, cmd_m44)
			if (cid[i] >= 0) {
				float cl = 0.f;
				for (uint j = 0; j < cp.length(); ++j) {
					if (cix[j] < 0) continue;
					const CCircuitDef@ ej = eDef[cix[j]];
					const float reach = ej.GetMaxRange() + (ej.IsMobile() ? ej.speed * tFight : 0.f);
					if (cp[j].distance2D(cp[i]) <= reach) cl += cv0[j];
				}
				cv[i] = AiMax(cv[i], cl);
			}
			score[i] = (t >= 1e8f) ? 0.f : cv[i] / AiMax(1.f, t);  // uncatchable: not a target
		}
		while (true) {
			int best = -1;
			float bestScore = 0.f;
			for (uint i = 0; i < cp.length(); ++i)
				if (score[i] > bestScore) { bestScore = score[i]; best = int(i); }
			if (best < 0) break;
			score[best] = 0.f;
			// the nearest free units until our strength beats the defence at our trade rate
			const float need = dfc[best] / trade;
			array<CCircuitUnit@> pick;
			float S = 0.f, metal = 0.f;
			array<float> dist(freeUnits.length());
			array<bool> used(freeUnits.length());
			for (uint k = 0; k < freeUnits.length(); ++k) { dist[k] = freeUnits[k].GetPos(ai.frame).distance2D(cp[best]); used[k] = false; }
			// Square law: the loss is our metal x (defence / strength)^2, so every unit added to a defended fight lowers
			// it: a defended objective takes every free unit (concentration; just-enough squads of 2-4 bled and pulled
			// back 23 times on Avalanche, 2026-11-25). An undefended one takes the single nearest: nothing there can hurt it.
			const bool defended = dfc[best] > 0.f;
			while (defended || pick.length() == 0) {
				int nk = -1;
				for (uint k = 0; k < freeUnits.length(); ++k)
					if (!used[k] && (nk < 0 || dist[k] < dist[nk])) nk = int(k);
				if (nk < 0) break;
				used[nk] = true;
				pick.insertLast(freeUnits[nk]);
				S += EffThreat(freeUnits[nk].circuitDef);
				metal += freeUnits[nk].circuitDef.costM;
			}
			// our own armed buildings within reach fight there too (as the enemy's count in its defence)
			for (uint k = 0; k < all.length(); ++k) {
				const CCircuitDef@ sd = all[k].circuitDef;
				if (sd.IsMobile() || sd.threat <= 0.f || sd.surfThrDmg <= 0.f) continue;
				if (all[k].GetPos(ai.frame).distance2D(cp[best]) <= sd.GetMaxRange()) S += sd.threat;
			}
			// A threat at home that the free units can't beat: recall units from raid ops (raid spots, the least valuable
			// first) until it can be won, if it is worth more than those raids (players pull raiders back when the base
			// is hit: on Feast of Hades our Grunts raided far spots one by one while Gators killed our extractors and
			// Command skipped them, strength 1.1 vs 4.3, round 20).
			if (S <= need && cid[best] >= 0 && Assess::OnOurSide(cp[best])) {
				// A detachment, not whole ops: the units nearest the raid, from ops worth less than what it threatens, one
				// by one until they beat it; the rest keep their task (owner, 2026-11-26: the cheapest units that beat the
				// raider). Each op gives up its value in the share of strength it loses.
				array<CCircuitUnit@> du; array<int> dop; array<float> dd;
				for (uint o = 0; o < ops.length(); ++o) {
					if (ops[o].enemyId >= 0 && ops[o].value >= cv[best]) continue;
					for (uint k = 0; k < ops[o].units.length(); ++k) {
						du.insertLast(ops[o].units[k]); dop.insertLast(int(o)); dd.insertLast(ops[o].units[k].GetPos(ai.frame).distance2D(cp[best]));
					}
				}
				array<float> opS(ops.length());
				for (uint o = 0; o < ops.length(); ++o) { opS[o] = 0.f; for (uint k = 0; k < ops[o].units.length(); ++k) opS[o] += EffThreat(ops[o].units[k].circuitDef); }
				array<bool> du2(du.length());
				float S2 = S, given = 0.f, metal2 = metal;
				array<int> takeIdx;
				while (S2 <= need) {
					int nk = -1;
					for (uint k = 0; k < du.length(); ++k) if (!du2[k] && (nk < 0 || dd[k] < dd[nk])) nk = int(k);
					if (nk < 0) break;
					du2[nk] = true;
					const float e = EffThreat(du[nk].circuitDef);
					S2 += e; metal2 += du[nk].circuitDef.costM;
					given += ops[dop[nk]].value * e / AiMax(1e-3f, opS[dop[nk]]);
					takeIdx.insertLast(nk);
				}
				if (takeIdx.length() > 0 && FightGain(cv[best], S2, dfc[best], metal2) > FightGain(cv[best], S, dfc[best], metal) + given) {
					for (uint q = 0; q < takeIdx.length(); ++q) {
						CCircuitUnit@ u = du[takeIdx[q]];
						Op@ src = ops[dop[takeIdx[q]]];
						const int at = src.units.findByRef(u);
						if (at >= 0) src.units.removeAt(at);
						pick.insertLast(u);
					}
					for (int o = int(ops.length()) - 1; o >= 0; --o) if (ops[o].units.length() == 0) ops.removeAt(o);
					S = S2; metal = metal2;
					AiLog("[ANV-CMD] detach " + takeIdx.length() + " units to defend (" + int(cp[best].x) + "," + int(cp[best].z) + ") value " + int(cv[best])
						+ ": strength " + F1(S) + " > " + F1(need) + ", ops give up " + int(given));
				}
			}
			if (pick.length() == 0) continue;
			const float gain = FightGain(cv[best], S, dfc[best], metal);
			const float loss = cv[best] - gain;  // for the log
			if (gain <= 0.f) {  // what it keeps doesn't beat what it risks
				if (cid[best] >= 0) AiLog("[ANV-CMD] skip enemy " + cid[best] + " at (" + int(cp[best].x) + "," + int(cp[best].z) + ") value " + int(cv[best])
					+ ": strength " + F1(S) + " vs defence " + F1(dfc[best]) + " (trade " + F2(trade) + ") gain " + int(gain));
				continue;
			}
			Op op;
			op.enemyId = cid[best]; op.pos = cp[best]; op.value = cv[best]; op.defence = dfc[best]; op.engaged = dfc[best] <= 0.f;
			op.startMetal = metal; op.startFrame = ai.frame; op.killedAtStart = Assess::killedTotal;
			for (uint k = 0; k < pick.length(); ++k) op.units.insertLast(pick[k]);
			ops.insertLast(op);
			++created;
			AiLog("[ANV-CMD] op " + (op.enemyId < 0 ? "raid spot" : ("enemy " + op.enemyId)) + " at (" + int(op.pos.x) + "," + int(op.pos.z)
				+ ") value " + int(op.value) + " defence " + F1(op.defence) + " strength " + F1(S) + " units " + pick.length() + " loss~" + int(loss));
			for (int k = int(freeUnits.length()) - 1; k >= 0; --k)
				if (used[k]) freeUnits.removeAt(k);
		}
	}

	// execute
	for (uint o = 0; o < ops.length(); ++o) {
		Op@ op = ops[o];
		AIFloat3 oc(0.f, 0.f, 0.f);
		float minReach = 1e9f;
		for (uint k = 0; k < op.units.length(); ++k) { oc = oc + op.units[k].GetPos(ai.frame); minReach = AiMin(minReach, op.units[k].circuitDef.GetMaxRange()); }
		oc = oc / float(op.units.length());
		minReach = AiMax(1.f, minReach);
		if (op.engaged && op.defence <= 0.f && oc.distance2D(op.pos) > minReach && !op.arrived) {
			// undefended target far away: approach as one squad along the route, then fight
			if (!MoveGroup(op, o, op.pos)) continue;
			op.arrived = true;
			for (uint k = 0; k < op.units.length(); ++k) op.units[k].CmdWantedSpeed(op.units[k].circuitDef.speed);
		}
		if (!op.engaged) {
			// gather just outside the defenders' reach, on our side; engage once everyone is within its reach of the spot
			float defReach = 0.f;
			for (uint i = 0; i < n; ++i)
				if (eDef[i] !is null && eDef[i].threat > 0.f && ePos[i].distance2D(op.pos) <= eDef[i].GetMaxRange() + eDef[i].speed)
					defReach = AiMax(defReach, eDef[i].GetMaxRange());
			AIFloat3 dir = oc - op.pos;
			const float len = AiMax(1.f, dir.Length2D());
			const AIFloat3 stage = op.pos + dir * ((defReach + minReach) / len);
			if (!MoveGroup(op, o, stage)) continue;  // the squad walks there together
			op.engaged = true;
			for (uint k = 0; k < op.units.length(); ++k) op.units[k].CmdWantedSpeed(op.units[k].circuitDef.speed);  // fight at full speed
			AiLog("[ANV-CMD] engage (" + int(op.pos.x) + "," + int(op.pos.z) + ") with " + op.units.length() + " units");
		}
		// the squad's centre and spread, for reinforcements: a unit that arrives alone fights alone (square law; #93) -
		// the logs were full of "+1 units" walking straight into the fight one by one
		AIFloat3 sq(0.f, 0.f, 0.f);
		for (uint k = 0; k < op.units.length(); ++k) sq = sq + op.units[k].GetPos(ai.frame);
		sq = sq / float(AiMax(1, int(op.units.length())));
		float spread = 0.f;
		{
			array<float> dd;
			for (uint k = 0; k < op.units.length(); ++k) dd.insertLast(op.units[k].GetPos(ai.frame).distance2D(sq));
			dd.sortAsc();
			if (dd.length() > 0) spread = dd[dd.length() / 2];  // the median unit's distance: the squad's body
		}
		for (uint k = 0; k < op.units.length(); ++k) {
			CCircuitUnit@ u = op.units[k];
			const AIFloat3 p = u.GetPos(ai.frame);
			const float reach = AiMax(1.f, u.circuitDef.GetMaxRange());
			// a straggler joins the squad first: farther from its centre than the squad's body plus its own reach,
			// it walks to the centre, not into the fight
			if (op.engaged && op.units.length() > 1 && p.distance2D(sq) > spread + reach) {
				Order(u, "join" + o + ":" + int(sq.x / reach) + "," + int(sq.z / reach), 0, sq, -1);
				continue;
			}
			int bi = -1, ni = -1, ai2 = -1;  // best unarmed, nearest armed, best armed
			float bv = 0.f, nd = 1e9f, av = 0.f;
			for (uint i = 0; i < n; ++i) {
				if (eDef[i] is null || eDef[i].IsAbleToFly()) continue;
				const float dd = ePos[i].distance2D(p);
				if (eDef[i].threat > 0.f && dd < nd) { nd = dd; ni = int(i); }
				if (dd > reach) continue;
				// fire order: what removes the most of their damage per damage we spend - dps over remaining health
				// (Lanchester's optimal order). By metal value, high-dps Levelers and Thuds ranked below dearer units while
				// they dealt us most of our losses (trade 0.45-0.89 every game, cmd_m89-m118). Targets that don't shoot
				// back (buildings) rank after every armed one, by value per health.
				const float hpLeft = AiMax(1.f, eHp[i] * eDef[i].health);
				const float dps = eDef[i].GetSustainedDps();
				if (dps > 0.f) { const float v = dps / hpLeft; if (ai2 < 0 || v > av) { av = v; ai2 = int(i); } }
				else { const float v = EnemyValue(i, H) / hpLeft; if (bi < 0 || v > bv) { bv = v; bi = int(i); } }
			}
			// focus fire without stopping: set target (the unit keeps following its moves; plain moves still shoot
			// whatever is in reach). Owner: attack orders and attack-moves stand still and don't dodge.
			const int tgt = (ai2 >= 0) ? ai2 : ((bi >= 0) ? bi : ni);
			if (tgt >= 0) {
				string pt;
				if (!lastTarget.get("" + u.id, pt) || pt != ("" + eIds[tgt])) {
					lastTarget.set("" + u.id, "" + eIds[tgt]);
					u.CmdSetTarget(eIds[tgt]);
				}
			}
			if (ni >= 0 && nd <= reach + eDef[ni].GetMaxRange()) {
				// in the fight: hold at our own reach from the nearest armed enemy (out-ranging it, that is outside its
				// reach; otherwise as far as we can still hit from) and keep stepping sideways by one second of our
				// speed, switching sides on arrival, so we are never standing where aimed shots land
				AIFloat3 away = p - ePos[ni];
				const float l = AiMax(1.f, away.Length2D());
				away = away / l;
				const AIFloat3 side(-away.z, 0.f, away.x);
				int sgn = 1;
				{ string ss; if (strafeSide.get("" + u.id, ss) && ss == "-") sgn = -1; }
				const float step = AiMax(1.f, u.circuitDef.speed);
				const AIFloat3 spot = ePos[ni] + away * reach + side * (step * float(sgn));
				if (p.distance2D(spot) <= AiMax(u.circuitDef.GetRadius(), step / float(SECOND))) {
					sgn = -sgn;
					strafeSide.set("" + u.id, sgn < 0 ? "-" : "+");
				}
				Order(u, "fpos" + eIds[ni] + ":" + sgn + ":" + int(spot.x / step) + "," + int(spot.z / step), 0, spot, -1);
			} else {
				Order(u, "to" + o + ":" + int(op.pos.x / reach) + "," + int(op.pos.z / reach), 0, op.pos, -1);
			}
		}
	}
	// Hold (#106): free units stand together at the point that covers most of our extractors - from where the squad
	// reaches an extractor before a raider kills it (extractor health / the raiders' dps seen, x the squad's slowest
	// speed, + its range; unit facts) - and wait there, not at the base centre. Winners' main squads stand in their own
	// half, mostly idle (holding), 1450-2300 from start at 6-8 min; losers keep moving and fragment (6 replays, #106).
	const AIFloat3 hold = HoldPoint(freeUnits);
	for (uint i = 0; i < freeUnits.length(); ++i)
		if (freeUnits[i].GetPos(ai.frame).distance2D(hold) > freeUnits[i].circuitDef.GetMaxRange()) Order(freeUnits[i], "hold:" + int(hold.x / 64.f) + "," + int(hold.z / 64.f), 0, hold, -1);
}
int lastHoldPtLog = -1000000;
AIFloat3 HoldPoint(const array<CCircuitUnit@>@ units)
{
	if (units.length() == 0 || Economist::mexT1 is null) return basePos;
	// A raider kills an extractor in a few seconds (extractor health / raider dps, unit facts: ~3 s against Cortex's
	// strongest seen), so no point reaches every spot in time; what a player holds is where the squad is nearest, on
	// average, to everything it defends - the median point of our extractors and the base (the spot with the least
	// summed distance to them): raids anywhere are answered soonest from there.
	const array<CCircuitUnit@>@ mx = Economist::mexes;
	AIFloat3 best = basePos; float bestSum = 1e30f;
	for (uint c = 0; c <= mx.length(); ++c) {
		const AIFloat3 q = (c < mx.length()) ? mx[c].GetPos(ai.frame) : basePos;
		float sum = q.distance2D(basePos);
		for (uint m = 0; m < mx.length(); ++m) sum += mx[m].GetPos(ai.frame).distance2D(q);
		if (sum < bestSum) { bestSum = sum; best = q; }
	}
	const float bestV = bestSum / float(AiMax(1, int(mx.length()) + 1));
	if (ai.frame - lastHoldPtLog >= MINUTE) { lastHoldPtLog = ai.frame; AiLog("[ANV-CMD] hold at (" + int(best.x) + "," + int(best.z) + "): mean distance " + int(bestV) + " to " + mx.length() + " extractors and the base"); }
	return best;
}
string Status() { return "ops=" + ops.length() + " created=" + created + " pulledBack=" + retreats; }
// a dead unit leaves its squad at once (a handle kept until the next update crashed the game when read: GetPos)
// Raids measured: raider-seconds on raid ops (no enemy id: their economy), raiders lost there, and the enemy metal killed
// within a raider's reach. A raider's worth is what raids actually kill per raider-second over its measured life - 0
// until a raid has killed (valued on its target's worth and an assumed life, the lab made 143 Ticks while raids killed 4
// units by 12:00, tk1-2).
float raidExposure = 0.f, raidKilled = 0.f, raidDps = 0.f; int raidDeaths = 0, raidFrame = -1, raidN = 0;
void RaidTick()
{
	int r = 0; float dps = 0.f;
	for (uint o = 0; o < ops.length(); ++o) if (ops[o].enemyId < 0)
		for (uint k = 0; k < ops[o].units.length(); ++k) { ++r; dps += ops[o].units[k].circuitDef.GetSustainedDps(); }
	if (raidFrame >= 0) raidExposure += float(r) * float(ai.frame - raidFrame) / SECOND;
	raidFrame = ai.frame;
	if (r > 0) { raidDps = dps / float(r); raidN = r; }
}
void CreditRaid(const AIFloat3& in p, float metal)
{
	for (uint o = 0; o < ops.length(); ++o) {
		if (ops[o].enemyId >= 0) continue;
		for (uint k = 0; k < ops[o].units.length(); ++k)
			if (ops[o].units[k].GetPos(ai.frame).distance2D(p) <= ops[o].units[k].circuitDef.GetMaxRange() + ops[o].units[k].circuitDef.GetRadius()) {
				raidKilled += metal; return;
			}
	}
}
float RaiderLife()
{
	if (raidDeaths > 0) return raidExposure / float(raidDeaths);
	return (raidN > 0) ? raidExposure / float(raidN) : 0.f;
}
// metal a raider of this def kills over its life: measured kill rate x measured life, at its dps against the raiders'
float RaiderWorth(const CCircuitDef@ d)
{
	if (raidExposure <= 0.f || raidKilled <= 0.f || raidDps <= 0.f) return 0.f;
	return raidKilled / raidExposure * RaiderLife() * d.GetSustainedDps() / raidDps;
}
void OnDestroyed(CCircuitUnit@ unit)
{
	for (uint o = 0; o < ops.length(); ++o) {
		const int k = ops[o].units.findByRef(unit);
		if (k >= 0) { ops[o].units.removeAt(k); if (ops[o].enemyId < 0) ++raidDeaths; }
	}
	lastOrder.delete("" + unit.id);
	lastTarget.delete("" + unit.id);
	strafeSide.delete("" + unit.id);
}
}  // namespace Command

/*
 * Self-assessment, once per game minute (owner #92, CHECKLIST.md). Every verdict is measured from the game:
 *  - waste: storage is full and income exceeds spending -> the excess is thrown away (per second)
 *  - stall: stock is below one second of the deficit (spending exceeds income and nothing is left to draw on)
 *  - army: our armed mobile metal vs the enemy's known armed mobile metal
 *  - moving: an army unit that covered at least one second of its own top speed since the last check
 *  - fighting: army units on attack/raid tasks vs defend/guard/none; metal killed and lost since the last check
 *  - idle: builders and factories with no job
 * Logged as one [ANV-CHECK] line; tools/check_game.py turns a game's lines into the checklist.
 */
/*
 * Awareness (owner, 2026-11-26: "all missing parts such as awareness (missing info about own army position, map,
 * etc)"): what the AI knows, logged every half minute as one line - our army (where, how spread, how far forward),
 * squads and pickets, the commander, the map (spots ours / theirs seen / open, how much we have seen in the last minute,
 * radars) and the enemy we know (armed units, strength, groups, the nearest group to our base). A blind input shows up
 * here as a 0 or a stale value before it shows up as a lost game.
 */
namespace Awareness {
int lastFrame = NEVER;
void Update()
{
	if (lastFrame != NEVER && ai.frame - lastFrame < 30 * SECOND) return;
	lastFrame = ai.frame;
	const AIFloat3 home = basePos, them = AiEnemyBasePos();
	const float span = AiMax(1.f, home.distance2D(them));
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	AIFloat3 c(0.f, 0.f, 0.f); float metal = 0.f, S = 0.f; uint n = 0, radars = 0;
	for (uint i = 0; i < all.length(); ++i) {
		const CCircuitDef@ d = all[i].circuitDef;
		if (!d.IsMobile() && Facts::RadarRange(d.GetName()) > 0.f) ++radars;
		if (!IsArmy(d) || d.GetSustainedDps() <= 0.f) continue;
		c = c + all[i].GetPos(ai.frame); metal += d.costM; S += Opening::Strength(d); ++n;
	}
	string army = "army 0";
	if (n > 0) {
		c = c / float(n);
		float spread = 0.f;
		for (uint i = 0; i < all.length(); ++i) {
			const CCircuitDef@ d = all[i].circuitDef;
			if (IsArmy(d) && d.GetSustainedDps() > 0.f) spread += all[i].GetPos(ai.frame).distance2D(c);
		}
		army = "army " + n + " (" + int(metal) + " metal, strength " + int(S) + ") at (" + int(c.x) + "," + int(c.z) + ") spread " + int(spread / float(n))
			+ " forward " + F2(home.distance2D(c) / span);
	}
	string sq = "ops " + Command::ops.length() + " [";
	for (uint o = 0; o < Command::ops.length(); ++o) sq += (o > 0 ? " " : "") + Command::ops[o].units.length() + "@" + int(Command::ops[o].pos.x) + "," + int(Command::ops[o].pos.z);
	sq += "] pickets " + Command::picketAt.getSize();
	string com = (commander !is null) ? ("commander " + int(commander.GetPos(ai.frame).distance2D(home)) + " from base") : "commander -";
	// the map: extractor spots, sight in the last minute (scout cells)
	array<AIFloat3> sp; array<float> si; array<bool> so;
	const uint ns = AiGetMetalSpots(sp, si, so);
	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
	const uint ne = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	uint ours = 0, theirs = 0;
	for (uint i = 0; i < ns; ++i) {
		if (EcoPos::OwnSpot(sp[i])) { ++ours; continue; }
		for (uint k = 0; k < ne; ++k)
			if (ed[k] !is null && !ed[k].IsMobile() && Facts::ExtractsMetal(ed[k].GetName()) > 0.f && ep[k].distance2D(sp[i]) <= ed[k].GetRadius() * 2.f) { ++theirs; break; }
	}
	uint seen = 0;
	const uint cells = Scout::lastSeen.length();
	for (uint k = 0; k < cells; ++k) if (ai.frame - Scout::lastSeen[k] <= MINUTE) ++seen;
	// the enemy we know
	float eS = 0.f; uint eN = 0;
	for (uint k = 0; k < ne; ++k) if (ed[k] !is null && ed[k].IsMobile() && ed[k].GetSustainedDps() > 0.f) { eS += Opening::Strength(ed[k]); ++eN; }
	array<AIFloat3> gp; array<float> gc, gt;
	const uint g = AiGetEnemyGroups(gp, gc, gt);
	float nearest = 1e30f;
	for (uint k = 0; k < g; ++k) nearest = AiMin(nearest, gp[k].distance2D(home));
	AiLog("[ANV-AWARE] t=" + (ai.frame / SECOND) + "s " + army + " | " + sq + " | " + com
		+ " | spots " + ours + " ours " + theirs + " theirs seen " + (ns - ours - theirs) + " other | seen last minute " + (cells > 0 ? F2(float(seen) / float(cells)) : "-")
		+ " of the map, radars " + radars + " | enemy armed " + eN + " strength " + int(eS) + " groups " + g + " nearest " + (g > 0 ? ("" + int(nearest)) : "-") + " from base");
}
}  // namespace Awareness

namespace Check {
int lastFrame = NEVER;
dictionary lastPos;  // unit id -> "x,z"
float lastKilled = 0.f, lastLost = 0.f;
string Res(const SResourceInfo@ r, float realPull)
{
	const float net = r.income - realPull;
	if (r.current >= r.storage && net > 0.f) return "WASTE " + F1(net) + "/s";
	if (net < 0.f && r.current < -net) return "STALL " + F1(-net) + "/s short";
	return "ok";
}
// per our unit type: damage it dealt and received so far (the live trade, #116: which of our units earn their metal
// against the mix they meet) - one line a minute
dictionary tradeTypes;
void TradeLog(const array<CCircuitUnit@>@ all)
{
	for (uint i = 0; i < all.length(); ++i) if (IsArmy(all[i].circuitDef)) tradeTypes.set(all[i].circuitDef.GetName(), true);
	const array<string>@ ks = tradeTypes.getKeys();
	string tl = "";
	for (uint k = 0; k < ks.length(); ++k) {
		const float dealt = AiDamageDealt(ks[k]), rec = AiDamageReceived(ks[k]);
		if (dealt <= 0.f && rec <= 0.f) continue;
		tl += " " + ks[k] + " dealt " + int(dealt) + " got " + int(rec) + " (" + F2(dealt / AiMax(1.f, rec)) + ")";
	}
	if (tl.length() > 0) AiLog("[ANV-TRADE] t=" + (ai.frame / SECOND) + "s" + tl);
}
void Update()
{
	if (lastFrame != NEVER && ai.frame - lastFrame < MINUTE) return;
	lastFrame = ai.frame;
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	TradeLog(all);
	float army = 0.f; uint armyN = 0, moved = 0, onAttack = 0, onRaid = 0, onDefend = 0, noFight = 0;
	uint builders = 0, idleBuilders = 0, facs = 0, idleFacs = 0;
	dictionary now;
	for (uint i = 0; i < all.length(); ++i) {
		CCircuitUnit@ u = all[i];
		const CCircuitDef@ d = u.circuitDef;
		const bool idle = u.task is null || u.task.GetType() == Task::Type::IDLE;
		if (IsArmy(d)) {
			army += d.costM; ++armyN;
			const AIFloat3 p = u.GetPos(ai.frame);
			now.set("" + u.id, p.x + "," + p.z);
			string prev;
			if (lastPos.get("" + u.id, prev)) {
				const array<string>@ xz = prev.split(",");
				const float dx = p.x - parseFloat(xz[0]), dz = p.z - parseFloat(xz[1]);
				if (sqrt(dx * dx + dz * dz) >= d.speed) ++moved;  // at least one second of its top speed
			}
			// Command's ops (BARb's fight types are gone): attack = an op on a known enemy, raid = an op on a raid spot,
			// defend = an op on an enemy within reach of our buildings, none = free
			int kind = -1;
			for (uint o = 0; o < Command::ops.length() && kind < 0; ++o) {
				if (Command::ops[o].units.findByRef(u) < 0) continue;
				kind = (Command::ops[o].enemyId < 0) ? 1 : ((HasBase() && Command::ops[o].pos.distance2D(basePos) < Command::ops[o].pos.distance2D(AiEnemyBasePos())) ? 2 : 0);
			}
			if (kind < 0) ++noFight;
			else if (kind == 0) ++onAttack;
			else if (kind == 1) ++onRaid;
			else ++onDefend;
		} else if (d.IsMobile() && d.IsRoleAny(Unit::Role::BUILDER.mask) && d.buildSpeed > 0.f) {
			++builders; if (idle) ++idleBuilders;
		} else if (!d.IsMobile() && Facts::BuildOptions(d.GetName()).length() > 0) {
			++facs; if (idle) ++idleFacs;
		}
	}
	lastPos = now;
	float enemyArmy = 0.f;
	{
		array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
		const uint n = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
		for (uint i = 0; i < n; ++i)
			if (ed[i] !is null && ed[i].IsMobile() && ed[i].defDmg > 0.f) enemyArmy += ec[i];
	}
	const float killed = Assess::killedTotal - lastKilled, lost = (Assess::lostNearTotal + Assess::lostFarTotal) - lastLost;
	lastKilled = Assess::killedTotal; lastLost = Assess::lostNearTotal + Assess::lostFarTotal;
	{  // what every constructor is doing (job def, or task type when it has none)
		array<string> jk; array<int> jn;
		const array<CCircuitUnit@>@ mine = AiGetTeamUnits();
		for (uint i = 0; i < mine.length(); ++i) {
			CCircuitUnit@ u = mine[i];
			const CCircuitDef@ d = u.circuitDef;
			if (!d.IsMobile() || !d.IsRoleAny(Unit::Role::BUILDER.mask) || u is commander) continue;
			IBuilderTask@ bt = cast<IBuilderTask>(u.task);
			const string k = (bt !is null && bt.buildDef !is null) ? bt.buildDef.GetName() : ((u.task is null) ? "none" : ("type" + int(u.task.GetType()) + (bt !is null ? ("/b" + int(bt.GetBuildType())) : "")));
			const int at = jk.find(k);
			if (at < 0) { jk.insertLast(k); jn.insertLast(1); } else ++jn[at];
		}
		string line = "";
		for (uint i = 0; i < jk.length(); ++i) line += " " + jk[i] + ":" + jn[i];
		{  // the enemy's army as seen, by unit type (what our unit choices were made against)
			array<AIFloat3> ep2, ev2; array<CCircuitDef@> ed2; array<float> ec2, eh2, eb2; array<int> ef2;
			const uint ne2 = AiGetEnemies(ep2, ev2, ed2, ec2, ef2, eh2, eb2);
			array<string> ek; array<int> en;
			for (uint i = 0; i < ne2; ++i) {
				if (ed2[i] is null || !ed2[i].IsMobile() || ed2[i].GetSustainedDps() <= 0.f) continue;
				const string nm = ed2[i].GetName();
				const int at = ek.find(nm);
				if (at < 0) { ek.insertLast(nm); en.insertLast(1); } else ++en[at];
			}
			string el = "";
			for (uint i = 0; i < ek.length(); ++i) el += " " + ek[i] + ":" + en[i];
			AiLog("[ANV-ENEMY] t=" + Minute() + "m armed mobile enemies seen:" + (el.length() == 0 ? " none" : el));
		}
		AiLog("[ANV-JOBS] t=" + Minute() + "m" + line + " | metal income " + F1(aiEconomyMgr.metal.income) + " pull " + F1(aiEconomyMgr.metal.pull)
			+ " bank " + int(aiEconomyMgr.metal.current) + "/" + int(aiEconomyMgr.metal.storage) + " | producer life " + int(Economist::ProducerLife()) + " s (threat floor " + int(Economist::Horizon())
			+ ", lost " + Economist::producerLosses + "; covered " + int(Economist::CoveredLife()) + " s / " + Economist::coveredLosses
			+ " lost, uncovered " + int(Economist::UncoveredLife()) + " s / " + Economist::uncoveredLosses + " lost)");
	}
	AiLog("[ANV-CHECK] t=" + Minute() + "m metal=" + Res(aiEconomyMgr.metal, aiEconomyMgr.metal.pull)
		+ " energy=" + Res(aiEconomyMgr.energy, Economist::RealPull())
		+ " banked=" + int(aiEconomyMgr.metal.current) + "/" + int(aiEconomyMgr.metal.storage)
		+ " army=" + int(army) + " enemyArmyKnown=" + int(enemyArmy) + " ratio=" + F1(Director::ratio)
		+ " moving=" + moved + "/" + armyN + " attack=" + onAttack + " raid=" + onRaid + " defend=" + onDefend + " none=" + noFight
		+ " killed=" + int(killed) + " lost=" + int(lost)
		+ " idleBuilders=" + idleBuilders + "/" + builders + " idleFactories=" + idleFacs + "/" + facs
		+ " mInc=" + F1(aiEconomyMgr.metal.income) + " eInc=" + F1(aiEconomyMgr.energy.income)
		+ " mex=" + Economist::mexes.length()
		+ " " + Command::Status()
		+ " microContact=" + minContact + " microFired=" + minFired + " microNoReply=" + minNoReply
		+ " microOutranged=" + minOutranged + " microIdleInRange=" + minIdleInRange + " microStillHit=" + minStillHit);
	minContact = minFired = minNoReply = minOutranged = minIdleInRange = minStillHit = 0;
}
/*
 * Micro, every second (owner: "for the army micro you will need to do it like every second"). For each army unit
 * in contact (an enemy within its weapon reach, or it lost health since the last second):
 *  fired      its weapons fired this second (LastShotFrame)
 *  noReply    it lost health and did not fire
 *  outranged  it lost health and no enemy is within its own reach
 *  idleInRange an enemy is within its reach and it did not fire
 *  stillHit   it lost health while standing still
 * plus each squad's spread (mean distance of its units from their centre, in its units' own reach).
 * One [ANV-MICRO] line per second with contact; the minute line carries the totals.
 */
dictionary microHp;  // unit id -> health last second
int microFrame = NEVER;
dictionary idleWhy; int idleLogFrame = 0;
uint minContact = 0, minNoReply = 0, minOutranged = 0, minIdleInRange = 0, minStillHit = 0, minFired = 0;
void Micro()
{
	const int since = (microFrame == NEVER) ? ai.frame : microFrame;
	microFrame = ai.frame;
	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
	const uint n = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	uint contact = 0, fired = 0, noReply = 0, outranged = 0, idleInRange = 0, stillHit = 0, kited = 0;
	dictionary hpNow;
	for (uint i = 0; i < all.length(); ++i) {
		CCircuitUnit@ u = all[i];
		const CCircuitDef@ d = u.circuitDef;
		if (!IsArmy(d)) continue;
		const float hp = u.GetHealth();
		hpNow.set("" + u.id, double(hp));
		double prev = hp;
		const bool known = microHp.get("" + u.id, prev);
		const bool hit = known && hp < float(prev);
		const AIFloat3 p = u.GetPos(ai.frame);
		const float reach = d.GetMaxRange();
		bool inReach = false; int rk = -1;
		for (uint k = 0; k < n && !inReach; ++k)
			if (ed[k] !is null && ep[k].distance2D(p) <= reach) { inReach = true; rk = int(k); }
		if (!hit && !inReach) continue;
		++contact;
		// Fight from its own reach (#116; winners' squads in contact: longer-range types stand back by their range edge,
		// REPLAYS.md): a unit that outranges the nearest armed enemy, with it inside our reach, steps back to our reach
		// from it - its weapon turns (Facts::FiresMoving), so it keeps firing while the enemy can't reply. Closing in
		// stays the squad's order when they outrange us.
		{
			int nk = -1; float nd = 1e30f;
			for (uint k = 0; k < n; ++k) {
				if (ed[k] is null || !ed[k].IsMobile() || ed[k].GetSustainedDps() <= 0.f) continue;
				const float dk = ep[k].distance2D(p);
				if (dk < nd) { nd = dk; nk = int(k); }
			}
			// Formation (#117, owner: short-range units guard long-range ones; "rocketeers must stand in a line because they
			// don't shoot over each other - unlike plasma bots or blitz"): in contact - the nearest armed enemy within our
			// reach plus theirs - each unit takes its place at its OWN range from it: short range in front, long range behind
			// by its range edge (winners' squads in contact, REPLAYS.md). Direct-fire units of a squad (Facts::DirectFire)
			// spread sideways on the line facing the enemy, a footprint apart, each with a clear shot; arcing ones fire over.
			// A unit that outranges the nearest enemy keeps that distance (it fires while moving - Facts::FiresMoving).
			if (nk >= 0 && Facts::FiresMoving(d.GetName()) > 0.f && nd < reach + ed[nk].GetMaxRange()) {
				AIFloat3 away = p - ep[nk];
				const float len = AiMax(1.f, away.Length2D());
				const float ux = away.x / len, uz = away.z / len;
				float side = 0.f;
				if (Facts::DirectFire(d.GetName()) > 0.f) {
					// its slot among the squad's direct-fire units
					for (uint q = 0; q < Command::ops.length(); ++q) {
						const int at = Command::ops[q].units.findByRef(u);
						if (at < 0) continue;
						int idx = 0, nd2 = 0;
						for (uint r = 0; r < Command::ops[q].units.length(); ++r) {
							if (Facts::DirectFire(Command::ops[q].units[r].circuitDef.GetName()) <= 0.f) continue;
							if (int(r) < at) ++idx;
							++nd2;
						}
						side = (float(idx) - float(nd2 - 1) * 0.5f) * 2.f * d.GetRadius();
						break;
					}
				}
				AIFloat3 to(ep[nk].x + ux * reach - uz * side, 0.f, ep[nk].z + uz * reach + ux * side);
				to.y = AiGetElevation(to.x, to.z);
				if (to.distance2D(p) > d.GetRadius()) { u.CmdMoveTo(to); ++kited; }
			}
		}
		// fired within its own reload time (a weapon that reloads in more than a second can't fire every second)
		const bool didFire = u.LastShotFrame() > AiMin(since, ai.frame - d.GetReloadTime());
		const AIFloat3 v = u.GetVel();
		const bool still = v.x * v.x + v.z * v.z <= 0.f;
		if (didFire) ++fired;
		if (hit && !didFire) ++noReply;
		if (hit && !inReach) ++outranged;
		if (inReach && !didFire) {
			++idleInRange;
			// who, against what, on which order (why does a unit with an enemy in reach not fire?)
			string ord = "-"; if (!Command::lastOrder.get("" + u.id, ord)) ord = "-";
			const string key = d.GetName() + ">" + ed[rk].GetName() + (ed[rk].IsAbleToFly() ? "(air)" : "") + ((ef[rk] & 2) == 0 ? "(radar)" : "") + " " + (still ? "still" : "moving") + " " + ord.split(":")[0];
			int c = 0; if (!idleWhy.get(key, c)) c = 0; idleWhy.set(key, c + 1);
		}
		if (hit && still) ++stillHit;
	}
	microHp = hpNow;
	if (ai.frame - idleLogFrame >= 2 * MINUTE) {
		idleLogFrame = ai.frame;
		const array<string>@ ks = idleWhy.getKeys();
		string idleOut = "";
		for (uint q = 0; q < ks.length(); ++q) { int c = 0; if (!idleWhy.get(ks[q], c)) c = 0; if (c >= 3) idleOut += " | " + ks[q] + " x" + c; }
		if (idleOut.length() > 0) AiLog("[ANV-IDLE]" + idleOut);
		idleWhy.deleteAll();
	}
	if (contact == 0) return;
	minContact += contact; minFired += fired; minNoReply += noReply; minOutranged += outranged;
	minIdleInRange += idleInRange; minStillHit += stillHit;
	// squad spread: mean distance from the squad centre, over the squad's shortest reach
	string spread = "";
	for (uint q = 0; q < Command::ops.length(); ++q) {
		const array<CCircuitUnit@>@ su = Command::ops[q].units;
		if (su.length() < 2) continue;  // (dead units leave squads on death: Command::OnDestroyed)
		AIFloat3 c(0.f, 0.f, 0.f); float minReach = 1e9f;
		for (uint k = 0; k < su.length(); ++k) { c = c + su[k].GetPos(ai.frame); minReach = AiMin(minReach, su[k].circuitDef.GetMaxRange()); }
		c = c / float(su.length());
		float md = 0.f;
		for (uint k = 0; k < su.length(); ++k) md += su[k].GetPos(ai.frame).distance2D(c);
		md /= float(su.length());
		spread += " " + su.length() + "u:" + F1(md / AiMax(1.f, minReach)) + "r";
	}
	AiLog("[ANV-MICRO] f=" + ai.frame + " contact=" + contact + " kited=" + kited + " fired=" + fired + " noReply=" + noReply
		+ " outranged=" + outranged + " idleInRange=" + idleInRange + " stillHit=" + stillHit + " squadSpread=" + spread);
}
}  // namespace Check

CCircuitUnit@ commander = null;
int commRedirects = 0;

/*
 * The commander is the win condition: it takes a job only when the job's value beats P(death) there x
 * everything we own (CommWorth, see Commander risk below); otherwise it takes the safest productive job.
 */
// Squads, measured as the replay analyzer measures them (tools/replay_harness ... zz_replay_analyzer.lua, SQUAD): our
// armed mobile units (no builders, no air, no commander) grouped by single linkage - two units in one squad when within
// the longer of their two weapon ranges - every 15 s: units, squad sizes (largest first), the largest squad's units.
// For comparing our squads and composition with winning players' (owner, 2026-11-26).
int squadLogFrame = 0;
void SquadLog()
{
	if (ai.frame - squadLogFrame < 15 * SECOND) return;
	squadLogFrame = ai.frame;
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	array<AIFloat3> p; array<float> r; array<string> nm;
	for (uint i = 0; i < all.length(); ++i) {
		const CCircuitDef@ d = all[i].circuitDef;
		if (all[i] is commander || !d.IsMobile() || d.IsAbleToFly() || d.buildSpeed > 0.f || d.GetSustainedDps() <= 0.f) continue;
		p.insertLast(all[i].GetPos(ai.frame)); r.insertLast(d.GetMaxRange()); nm.insertLast(d.GetName());
	}
	const uint n = p.length();
	if (n == 0) return;
	array<int> cl(n, -1); int nc = 0;
	for (uint i = 0; i < n; ++i) {
		if (cl[i] >= 0) continue;
		cl[i] = nc;
		array<uint> stack = {i};
		while (stack.length() > 0) {
			const uint a = stack[stack.length() - 1]; stack.removeLast();
			for (uint j = 0; j < n; ++j) {
				if (cl[j] >= 0) continue;
				const float link = AiMax(r[a], r[j]);
				if (p[a].distance2D(p[j]) <= link) { cl[j] = nc; stack.insertLast(j); }
			}
		}
		++nc;
	}
	array<int> size(nc, 0);
	for (uint i = 0; i < n; ++i) size[cl[i]]++;
	array<int> order;
	for (int c = 0; c < nc; ++c) order.insertLast(c);
	for (uint a = 0; a < order.length(); ++a)
		for (uint b = a + 1; b < order.length(); ++b)
			if (size[order[b]] > size[order[a]]) { const int t = order[a]; order[a] = order[b]; order[b] = t; }
	string sizes = "";
	for (uint k = 0; k < order.length() && k < 12; ++k) sizes += (k > 0 ? "," : "") + size[order[k]];
	dictionary comp;
	for (uint i = 0; i < n; ++i) if (cl[i] == order[0]) { int c = 0; if (!comp.get(nm[i], c)) c = 0; comp.set(nm[i], c + 1); }
	const array<string>@ ks = comp.getKeys();
	string big = "";
	for (uint k = 0; k < ks.length(); ++k) { int c = 0; if (!comp.get(ks[k], c)) c = 0; big += (k > 0 ? "," : "") + ks[k] + ":" + c; }
	AiLog("[ANV-SQUAD] f=" + ai.frame + " units=" + n + " squads=" + nc + " sizes=" + sizes + " big=" + big);
}
IUnitTask@ CommanderTask(CCircuitUnit@ comm, IUnitTask@ task)
{
	if (task is null || !HasBase() || task.GetType() != Task::Type::BUILDER || Brain::Intel::allFactories.length() == 0)
		return task;
	IBuilderTask@ bt = cast<IBuilderTask>(task);
	if (bt is null)
		return task;
	if (CommWorth(bt.GetBuildPos(), JobValue(bt), JobTime(bt)))
		return task;
	++commRedirects;
	AiLog("[ANV] CommRedirect: " + bt.buildDef.GetName() + " gain " + int(lastGain) + " < risk " + int(lastRisk) + " (danger " + F1(commDanger) + " cover " + F1(commCover) + ")");
	IUnitTask@ safe = CommSafeJob(comm.GetPos(ai.frame));
	if (safe is null) return task;
	// the safe job holds until the place it left is safe, like any builder's escape (it carries the game's value, and
	// builder safety ends it): without, the core re-offered a forward job each second and the commander was
	// redirected 50 times in 50 s 1242 from base, never going home, until it died at 13:35 (cmd_m71)
	IBuilderTask@ sbt = cast<IBuilderTask>(safe);
	if (sbt !is null) sbt.value = GameValue();
	safeTasks.insertLast(safe);
	leftAt.set("" + comm.id, bt.GetBuildPos());
	// held at least for the window it refused (the job's time + the escape), the same window the refusal was judged
	// over: builder safety's return test (escape time only) read the site safe at once and the commander was redirected
	// 200 times, about once a second, 1116 out until it died at 14:08 (cmd_m100)
	commSafeUntil = ai.frame + int((JobTime(bt) + EscapeTime(bt.GetBuildPos())) * SECOND);
	return safe;
}

/*
 * Commander guard (C++ bridge): every 2 s the commander's current job is weighed by the same risk test
 * (CommGuardUpdate); when it isn't worth it the commander moves to the safest productive job.
 */
IUnitTask@ commGuardTask = null;
int commGuards = 0;

CCircuitUnit@ NearestFactory(const AIFloat3& in p)
{
	CCircuitUnit@ best = null; float bd = 1e9f;
	for (uint i = 0; i < Brain::Intel::allFactories.length(); ++i) {
		const float d = Brain::Intel::allFactories[i].GetPos(ai.frame).distance2D(p);
		if (d < bd) { bd = d; @best = Brain::Intel::allFactories[i]; }
	}
	return best;
}



/*
 * Commander risk (the most important decision: losing the last commander loses the game). The best
 * players bring it to the front anyway: it is the strongest early unit and the biggest early build power.
 * So the question is never "is it in danger" but "is this job worth the chance of losing everything":
 *   risk = P(death) x V      V = everything we own (the game)
 *   P(death) = d^2 / (d^2 + c^2)  (Lanchester square law: enemy force that can reach the spot before the
 *              commander is back under cover, against everything that can cover it there incl. itself)
 *   gain = metal value of the job
 * It takes the job if gain > risk; otherwise it takes the safest job that still produces something.
 */

// What we believe the enemy has but can't see (the Director's estimate minus what is in sight), placed at
// their centre and moving at their seen mean speed (ours, if none seen). Unscouted is not empty: a blind
// commander walking into the far half of the map meets exactly this.
float CommFog(const AIFloat3& in p, float tHome, float seenThreat, float seenSpeed, uint seenN)
{
	const float hidden = AiMax(0.f, Brain::Economist::EnemyThreat() - seenThreat);
	if (hidden <= 0.f) return 0.f;
	// a hidden army can only be where it could have walked since it could first be built: before the earliest enemy
	// raid can arrive, there is nothing hidden near us (fog read danger 12.8 at minute 1 and pulled the commander off
	// its jobs, Feast of Hades 2026-11-25)
	if (float(ai.frame) / SECOND < Opening::raidArrive) return 0.f;
	Director::MeasuredPower();
	const float sp = seenN > 0 ? seenSpeed / float(seenN) : AiMax(1.f, Director::allSpeed);
	// where it is: with their seen units, not at home - the hidden part of an army moves with the part we see. Placed
	// at their base, unseen Thuds and Mists 1400-1800 out read no danger and killed the commander at 14:22 and
	// 15:08 (cmd_m79, cmd_m81). The known enemy nearest the spot, else their base.
	const float dist = AiMin(AiEnemyBasePos().distance2D(p), commNearestEnemy);
	return dist / AiMax(1.f, sp) <= tHome ? hidden : 0.f;
}
float commNearestEnemy = 1e9f;  // distance from the measured spot to the nearest known armed enemy mobile (CommForces)
float commDanger = 0.f, commCover = 0.f, commDps = 0.f;
float commEnemyHp = 0.f, commOurDps = 0.f;
float commInFire = 0.f, commERange = 0.f;  // our power standing in the reaching enemies' range now; their longest range  // the reaching enemies' health, our dps there (how long the fight lasts)

/*
 * Wreck reclaim (owner: "24 minutes in, zero reclaim" with ~3000 metal in 47 wrecks and metal at 0/6700).
 * Each wreck field (wrecks within a builder's sight of its centre) is worth its metal, minus the walk (the
 * builder's share of our spending while it walks) and P(death) there x the builder's cost. The constructor that
 * reaches it soonest takes it when that beats its current job. One builder per field per round.
 */
int reclaimOrders = 0;
array<IUnitTask@> reclaimTasks;
void ReclaimUpdate()
{
	array<AIFloat3> wp; array<float> wm; array<bool> wr;
	const uint w = AiGetWrecks(wp, wm, wr);
	if (w == 0) return;
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	array<CCircuitUnit@> cons;
	for (uint i = 0; i < all.length(); ++i) {
		const CCircuitDef@ d = all[i].circuitDef;
		if (all[i] is commander || !d.IsMobile() || !d.IsRoleAny(Unit::Role::BUILDER.mask) || d.buildSpeed <= 0.f) continue;
		if (all[i].task !is null && reclaimTasks.findByRef(all[i].task) >= 0) continue;
		cons.insertLast(all[i]);
	}
	if (cons.length() == 0) return;
	const float income = aiEconomyMgr.metal.income;
	const float bp = AiMax(1.f, aiBuilderMgr.GetBuildPower());
	array<bool> taken(w, false);
	for (uint i = 0; i < w; ++i) {
		if (taken[i]) continue;
		// the builder that reaches this field soonest
		CCircuitUnit@ best = null; float bt = 1e30f;
		for (uint k = 0; k < cons.length(); ++k) {
			if (cons[k] is null) continue;
			const float t = MoveTime(cons[k].circuitDef, cons[k].GetPos(ai.frame).distance2D(wp[i]));
			if (t < bt) { bt = t; @best = cons[k]; }
		}
		if (best is null) break;
		const float R = best.circuitDef.losRadius;
		float metal = 0.f;
		for (uint j = 0; j < w; ++j) if (!taken[j] && wp[j].distance2D(wp[i]) <= R) metal += wm[j];
		const float walk = best.circuitDef.buildSpeed / bp * income * bt;  // what it would have built meanwhile
		const float risk = UnitPDeath(best, wp[i], bt) * Brain::Economist::MetalValue(best.circuitDef);
		IBuilderTask@ cur = cast<IBuilderTask>(best.task);
		// the job it would leave is worth what it yields (an extractor: its extraction over its life), not its price: at
		// its price (50 x a build-power share, a few metal) any wreck field pulled constructors off extractors - 49
		// extractor jobs and 24 energy jobs dropped for reclaim, 8 extractors built after 8:00 vs 22 lost (pk1)
		const float curV = (cur !is null && cur.buildDef !is null) ? AiMax(Brain::Economist::MetalValue(cur.buildDef), Brain::Economist::AssetValue(cur.buildDef)) : best.circuitDef.buildSpeed / bp * income * Brain::Economist::Horizon();
		if (metal - walk - risk <= curV) continue;
		// a rez bot revives what can be revived (at least the wreck's metal back as a working unit) unless energy would stall
		const bool canRez = Brain::Production::rezDefs.findByRef(best.circuitDef) >= 0 && wr[i] && !aiEconomyMgr.isEnergyStalling;
		IUnitTask@ t = canRez ? aiBuilderMgr.Enqueue(TaskB::Resurrect(Task::Priority::HIGH, wp[i], metal, ReclaimLife(metal, wp[i]), R))
			: aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::HIGH, wp[i], metal, ReclaimLife(metal, wp[i]), R));  // (pos, cost, timeout, radius)
		if (t is null) continue;
		aiBuilderMgr.AssignTask(best, t);
		reclaimTasks.insertLast(t);
		++reclaimOrders;
		for (uint j = 0; j < w; ++j) if (wp[j].distance2D(wp[i]) <= R) taken[j] = true;
		for (uint k = 0; k < cons.length(); ++k) if (cons[k] is best) @cons[k] = null;
	}
	for (int k = int(reclaimTasks.length()) - 1; k >= 0; --k)
		if (reclaimTasks[k] is null || reclaimTasks[k].GetUnits().length() == 0) reclaimTasks.removeAt(k);
}

CCircuitUnit@ riskUnit = null;  // whose danger is being measured (the commander, or any builder)
float riskHealth = 0.f;          // >0: measure a structure being built (its health), not riskUnit's
void CommForces(const AIFloat3& in p, float tHome)
{
	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
	const uint n = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	commDanger = 0.f; commDps = 0.f; commEnemyHp = 0.f; commOurDps = 0.f; commInFire = 0.f; commERange = 0.f;
	commNearestEnemy = 1e9f;
	for (uint i = 0; i < n; ++i)
		if (ed[i] !is null && ed[i].IsMobile() && ed[i].surfThrDmg > 0.f) commNearestEnemy = AiMin(commNearestEnemy, ep[i].distance2D(p));
	for (uint i = 0; i < n; ++i) {
		CCircuitDef@ d = ed[i];
		if (d is null || d.threat <= 0.f || (ef[i] & 4) != 0) continue;
		const float reach = AiMax(0.f, ep[i].distance2D(p) - d.GetMaxRange());
		if (!d.IsMobile()) { if (reach <= 0.f) { commDanger += d.threat; commDps += d.surfThrDmg; commEnemyHp += d.health * eh[i]; commERange = AiMax(commERange, d.GetMaxRange()); } continue; }
		if (MoveTime(d, reach) <= tHome) { commDanger += d.threat * eh[i]; commDps += d.surfThrDmg * eh[i]; commEnemyHp += d.health * eh[i]; commERange = AiMax(commERange, d.GetMaxRange()); }
	}
	{
		float seenT = 0.f, seenS = 0.f, perThreatDps = 0.f; uint seenN = 0;
		for (uint i = 0; i < n; ++i) if (ed[i] !is null && ed[i].IsMobile() && ed[i].threat > 0.f) { seenT += ed[i].threat; seenS += ed[i].speed; ++seenN; perThreatDps += ed[i].surfThrDmg; }
		const float fog = CommFog(p, tHome, seenT, seenS, seenN);
		if (fog > 0.f) {
			commDanger += fog;
			// its damage at the seen damage-per-threat, or ours if nothing is seen
			commDps += fog * (seenT > 0.f ? perThreatDps / seenT : riskUnit.circuitDef.surfThrDmg / AiMax(1.f, riskUnit.circuitDef.threat));
		}
	}
	commCover = riskUnit.circuitDef.power;
	commOurDps = riskUnit.circuitDef.surfThrDmg;
	commInFire = riskUnit.circuitDef.power;
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	for (uint i = 0; i < all.length(); ++i) {
		CCircuitUnit@ u = all[i];
		const CCircuitDef@ d = u.circuitDef;
		if (u is riskUnit || d.power <= 0.f || d.IsRoleAny(Unit::Role::BUILDER.mask)) continue;
		const float dist = u.GetPos(ai.frame).distance2D(p);
		if (d.IsMobile() ? (MoveTime(d, dist) <= tHome) : (dist <= d.GetMaxRange())) {
			commCover += d.power;
			commOurDps += AiMax(0.f, d.surfThrDmg);
		}
		if (dist <= commERange) commInFire += d.power;  // standing in their fire with it now: shares it
	}
}
float RiskPDeath(const AIFloat3& in p, float tHome0)
{
	CommForces(p, tHome0);
	// escaping is getting out of their reach, not reaching a factory: at home the factory is 0 s away and the risk
	// read 0 while the enemy stood at the factory - the commander fought at stake-risk 30 and 245 in a base fight and
	// died at 18:29, 196 from base (cmd_m63). At least their longest range over its speed.
	const float tHome = AiMax(tHome0, commERange / AiMax(1.f, riskUnit.circuitDef.speed));
	const float d2 = commDanger * commDanger, c2 = commCover * commCover;
	const float lose = d2 / AiMax(1e-3f, d2 + c2);  // the fight there goes against us
	// ...and it can't walk out: time to burn through its health vs time back to cover
	// its health now, not its maximum: a damaged commander read as a fresh 3700 hp, re-engaged Levelers and Raiders
	// three times in 6 s and died at 12:51 (cmd_m32) - the risk never rose as it took hits
	const float tKill = (riskHealth > 0.f ? riskHealth : AiMax(1.f, riskUnit.GetHealth())) / AiMax(1e-3f, commDps);
	const float pLose = lose * tHome / AiMax(1e-3f, tHome + tKill);
	// ...or it is shot down while the fight is won: the fire aimed at it (its share of our power there x the reaching
	// enemies' dps) over the time it stands in it - until they're dead (their health / our dps there) or it is out
	// (tHome) - against its health now. With the "fight lost" term alone, an army of 3726 nearby made the commander's
	// risk ~0 and it fought Levelers until it died at 13:26, the game lost (cmd_m33).
	const float health = (riskHealth > 0.f ? riskHealth : AiMax(1.f, riskUnit.GetHealth()));
	// fire is split among what stands in it now, not what could arrive: counted over all cover, an army on its way made
	// the commander's share ~0 and it took 54 fights, dying at 14:16; winners' commanders have an enemy within 600 only
	// 4-9% of the time at minutes 4-14 (replays.db comm table, 1v1 winners, 660-1284 samples per minute)
	// ...except where it is the prize: the enemy shoots what is worth most in its reach, and for the commander that is
	// the game - its share is all of it (P read 0.00 with a Leveler 238 away and the army around; it died at 14:45, cmd_m65)
	const float share = (riskUnit is commander) ? 1.f : riskUnit.circuitDef.power / AiMax(1e-3f, commInFire);
	const float tExposed = AiMin(tHome, commEnemyHp / AiMax(1e-3f, commOurDps));
	const float pFocus = AiMin(1.f, commDps * share * tExposed / health);
	return 1.f - (1.f - pLose) * (1.f - pFocus);
}
float CommPDeath(const AIFloat3& in p, float tHome) { @riskUnit = commander; return RiskPDeath(p, tHome); }
float UnitPDeath(CCircuitUnit@ u, const AIFloat3& in p, float tHome) { @riskUnit = u; riskHealth = 0.f; return RiskPDeath(p, tHome); }
// P that a structure being built at p dies before it is finished (tDone): its own health against what can reach it
float JobPDeath(CCircuitUnit@ builder, const CCircuitDef@ job, const AIFloat3& in p, float tDone) { @riskUnit = builder; riskHealth = AiMax(1.f, job.health); const float r = RiskPDeath(p, tDone); riskHealth = 0.f; return r; }

/*
 * Builder safety (owner: "you let your builders be decimated, no reaction"). Every constructor weighs its job
 * like the commander does, with its own stakes: staying is worth (1-P) x job value - P x its own cost; the safe
 * alternative is assisting the factory it reaches soonest (its build power on our income for the span of that
 * job). It leaves only when staying is worth less. P is the same fight-and-escape estimate as the commander's.
 */
int builderEvacs = 0;
int commSafeUntil = 0;  // frame until which the commander's redirect safe job holds
array<IUnitTask@> safeTasks;
dictionary leftAt;  // unit id -> the place an evacuated builder left
void BuilderSafeUpdate()
{
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	const float income = aiEconomyMgr.metal.income;
	const float bp = AiMax(1.f, aiBuilderMgr.GetBuildPower());
	for (uint i = 0; i < all.length(); ++i) {
		CCircuitUnit@ u = all[i];
		const CCircuitDef@ d = u.circuitDef;
		if (!d.IsMobile() || !d.IsRoleAny(Unit::Role::BUILDER.mask) || d.buildSpeed <= 0.f) continue;
		// the commander too: its fights are CommNet's, its building is weighed here like any builder's - left out, it
		// built where raids came and died on a build job at 16:21 and 19:27, each time the game (cmd_m56, cmd_m58)
		if (u is commander && commFightTask !is null && u.task is commFightTask) continue;
		const AIFloat3 c = u.GetPos(ai.frame);
		CCircuitUnit@ fac = FactoryReachedSoonest(c, d);
		if (fac is null) continue;
		const float tHome = MoveTime(d, fac.GetPos(ai.frame).distance2D(c));
		const float P = UnitPDeath(u, c, tHome);
		// on its safe job: back to work once the place it left is safe - not its own position, which is safe the moment
		// it arrives (rez bots fled and returned 618 times in one game, Canis 2026-11-26)
		if (u.task !is null && safeTasks.findByRef(u.task) >= 0) {
			if (u is commander && ai.frame < commSafeUntil) continue;  // its refusal's window isn't over
			AIFloat3 left;
			const bool known = leftAt.get("" + u.id, left);
			const float Pleft = known ? UnitPDeath(u, left, MoveTime(d, left.distance2D(c))) : P;
			if (Pleft <= 0.f) { u.task.Abort(); leftAt.delete("" + u.id); }
			continue;
		}
		IBuilderTask@ bt = cast<IBuilderTask>(u.task);
		if (bt is null && u.task !is null && u.task.GetType() != Task::Type::BUILDER) continue;  // retreating etc.: the core has it
		// the job is worth what it yields over the horizon, like the builder's own future (cost alone made every
		// builder run: 134 evacuations in 5 minutes on Avalanche, 1-2 extractors standing, 2026-11-25). A job that builds
		// nothing (reclaim, resurrect, repair, waiting) is worth what its decision gave it: skipped before, rez bots
		// stood in the open and died (owner, 2026-11-25: "standing with rezbots letting them die").
		// a job that builds nothing is worth its decision's value, or what it brings back (a reclaim: the wreck's metal
		// and energy - the script couldn't read it and rez bots' jobs counted 0: SCRIPT_SIGHT.md)
		float jobV = (bt !is null && bt.buildDef !is null) ? Brain::Economist::AssetValue(bt.buildDef) : 0.f;
		if (bt !is null && bt.buildDef is null)
			jobV = AiMax(bt.value, bt.GetCostM() + bt.GetCostE() / AiMax(1e-3f, Brain::Economist::energyPerMetal));
		// what is lost with it: its metal - and for the commander the game (everything we own)
		const float own = (u is commander) ? GameValue() : Brain::Economist::MetalValue(d);
		// the job is at risk too (owner: kept upgrading a mex with 4 pawns on it): if the structure dies before it is
		// finished, the metal sunk into it is lost (bounded by its full value; progress isn't visible to the script)
		float Pj = 0.f;
		if (bt !is null && bt.buildDef !is null) {
			const float tDone = bt.buildDef.buildTime / AiMax(1.f, d.buildSpeed);
			Pj = JobPDeath(u, bt.buildDef, bt.GetBuildPos(), tDone);
		}
		// Both choices share the builder's future work (its share of our spending over the horizon) if it survives.
		// Stay: the job's expected gain, minus the chance of losing the builder and that future. Leave: the future,
		// safe. Stay when (1-2Pj) x job - P x (builder + future) >= 0. (Comparing one job with the whole future made
		// builders run 490 times in 12 minutes: 1v1 Avalanche 2026-11-25.)
		const float future = d.buildSpeed / bp * income * Brain::Economist::Horizon();
		// If the structure dies unfinished we lose the metal sunk into it, not the yield it never produced.
		const float sunk = (bt !is null && bt.buildDef !is null) ? Brain::Economist::MetalValue(bt.buildDef) : 0.f;
		const float stay = (1.f - Pj) * jobV - Pj * sunk - P * (own + future);
		if (stay >= 0.f) continue;
		AiLog("[ANV-EVAC] t=" + (ai.frame / SECOND) + "s " + d.GetName() + " leaves " + ((bt !is null && bt.buildDef !is null) ? bt.buildDef.GetName() : "-")
			+ ": P " + F2(P) + " Pj " + F2(Pj) + " job " + int(jobV) + " sunk " + int(sunk) + " own " + int(own) + " future " + int(future)
			+ " danger " + int(commDanger) + " cover " + int(commCover));
		IUnitTask@ g = aiBuilderMgr.Enqueue(TaskB::Guard(Task::Priority::HIGH, fac, true, int(Brain::Economist::Horizon() * SECOND) + 1));
		if (g is null) continue;
		safeTasks.insertLast(g);
		leftAt.set("" + u.id, (bt !is null) ? bt.GetBuildPos() : c);  // where it fled from
		{  // the escape is this decision's job: worth what it keeps (the builder and its future work), so nothing else
		   // ends it (energy-binding ended these guards and rez bots looped evacuate -> guard -> reclaim 675 times)
			IBuilderTask@ gt = cast<IBuilderTask>(g);
			if (gt !is null) gt.value = own + future;
		}
		aiBuilderMgr.AssignTask(u, g);
		++builderEvacs;
	}
	for (int k = int(safeTasks.length()) - 1; k >= 0; --k)
		if (safeTasks[k] is null || safeTasks[k].GetUnits().length() == 0) safeTasks.removeAt(k);
}
float GameValue()
{
	float v = 0.f;
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	for (uint i = 0; i < all.length(); ++i) v += all[i].circuitDef.costM;
	return v;
}
// Escaping is leaving the reach of the enemies that can hit p: for each armed enemy, the way still inside its range
// over the commander's speed; the longest. (It was the walk to the nearest factory: a factory inside a base fight read
// as the best escape and a quiet structure away from it as dangerous - the commander guarded a factory in the fight and
// died at base at 17:52, cmd_m102.)
float EscapeTime(const AIFloat3& in p)
{
	if (commander is null) return 0.f;
	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
	const uint n = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	float t = 0.f;
	for (uint i = 0; i < n; ++i) {
		if (ed[i] is null || ed[i].surfThrDmg <= 0.f) continue;
		const float inside = ed[i].GetMaxRange() - ep[i].distance2D(p);
		if (inside > 0.f) t = AiMax(t, inside / AiMax(1.f, commander.circuitDef.speed));
	}
	return t;
}
// A build job is worth what it builds. Any other job (assist, reclaim, repair) is worth the commander's
// share of our build power applied to our income over the job's span: that's the spending it carries.
// The commander's worth on a job is its marginal value: what would NOT get done without it. Early it is most
// of our build power (it is the expander and the porc); once constructors and an army exist, others would do
// the same job anyway and its share, and with it the gain from risking it, collapses (Vritrasura108, #48:
// "as soon as we have army and constructors available we should stop putting our commander into risk").
float CommShare() { return AiMin(1.f, commander.circuitDef.buildSpeed / AiMax(1.f, aiBuilderMgr.GetBuildPower())); }
float JobValue(IBuilderTask@ bt)
{
	const float share = CommShare();
	// a job is worth what it produces over the horizon (cost + yield), as for every builder: valued at its cost (~40
	// for an extractor against P(death) x everything we own, ~3000) the fog's 1-2% sent the commander back from every
	// extractor 300 elmos out - 27 redirects, first extractor at 87 s on Gasbag Grabens (2026-11-25)
	if (bt !is null && bt.buildDef !is null) return Brain::Economist::AssetValue(bt.buildDef) * share;
	return share * aiEconomyMgr.metal.income * Brain::Economist::Horizon();  // over the planning horizon (the span of the jobs we hand out)
}
// Best job by gain - risk among: assisting a factory, reclaiming a wreck field (the frontline reclaim
// strong players do with the commander: it's metal, presence and the strongest unit on the spot), and
// reclaiming around one of our structures. Risk is P(death) there x the game. When the base is overrun
// this can be a far outpost; with a fight won nearby it is the battlefield's wrecks.
int commRetreats = 0, commReclaims = 0; float lastRisk = 0.f, lastGain = 0.f, lastV = 0.f;
IUnitTask@ CommBestJob(const AIFloat3& in from, float floorScore)
{
	const float V = GameValue();
	const float assist = JobValue(null);
	CCircuitUnit@ bestU = null; AIFloat3 bestP; int bestKind = -1; float best = floorScore;
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	for (uint i = 0; i < all.length(); ++i) {
		CCircuitUnit@ g = all[i];
		if (g.circuitDef.IsMobile() || g is commander) continue;
		const bool fac = Brain::Intel::allFactories.findByRef(g) >= 0;
		const AIFloat3 q = g.GetPos(ai.frame);
		const float sc = (fac ? assist : 0.f) - CommPDeath(q, EscapeTime(q)) * V - q.distance2D(from) / AiMax(1.f, commander.circuitDef.speed) * assist / AiMax(1.f, Brain::Economist::Horizon());  // walking costs its work
		if (sc > best) { best = sc; @bestU = g; bestP = q; bestKind = fac ? 0 : 2; }
	}
	array<AIFloat3> wp; array<float> wm; array<bool> wr;
	const uint w = AiGetWrecks(wp, wm, wr);
	const float R = commander.circuitDef.GetBuildDistance();  // reclaim area = what it reaches without walking
	for (uint i = 0; i < w; ++i) {
		float metal = 0.f;
		for (uint j = 0; j < w; ++j) if (wp[j].distance2D(wp[i]) < R) metal += wm[j];
		const float sc = metal - CommPDeath(wp[i], EscapeTime(wp[i])) * V - wp[i].distance2D(from) / AiMax(1.f, commander.circuitDef.speed) * assist / AiMax(1.f, Brain::Economist::Horizon());
		if (sc > best) { best = sc; @bestU = null; bestP = wp[i]; bestKind = 1; }
	}
	if (bestKind < 0) return null;
	if (bestKind == 0) return aiBuilderMgr.Enqueue(TaskB::Guard(Task::Priority::HIGH, bestU, true, int(Brain::Economist::Horizon() * SECOND) + 1));
	if (bestKind == 1) ++commReclaims;
	return aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::HIGH, bestP, 0.f, int(Brain::Economist::Horizon() * SECOND) + 1, R));  // (pos, cost, timeout, radius)
}
IUnitTask@ CommSafeJob(const AIFloat3& in from) { ++commRetreats; return CommBestJob(from, -1e30f); }

/*
 * Forward commander (replay study, 124 human commanders): after building eco at the start for ~3 min,
 * humans walk the commander 2000-3000 out and use it as the front builder: extractors, turrets, radar,
 * repairs, in even fights. The reasoning: early on it is the strongest builder on the map and what the
 * enemy has out there is weak against it, so the territory it claims is cheap. Here: each free extractor
 * spot is worth its income over the planning horizon times how holdable it is (dE/(dU+dE)), minus the
 * extractor, the walk (its build rate x the time) and P(death) there x everything we own. The commander
 * takes the best spot when that beats the job it has.
 */
int commFwd = 0, fwdCalls = 0, fwdBusy = 0, fwdNone = 0; float fwdBestSeen = 0.f, fwdCurSeen = 0.f; IUnitTask@ commFwdTask = null; float lastFwdGain = 0.f; int fwdDue = 0, fwdFailed = 0;
void OnBuilderTaskRemoved(IUnitTask@ task) { Radar::OnTaskRemoved(task); MexPorc::OnTaskRemoved(task); Strategic::OnTaskRemoved(task); Opening::OnTaskRemoved(task); if (task is commFwdTask) @commFwdTask = null; if (task is commGuardTask) @commGuardTask = null; }
IUnitTask@ CommForward(const AIFloat3& in from, float curScore)
{
	if (Brain::Economist::mexT1 is null) return null;
	// Energy is the binding constraint while it stalls: more metal income can't be spent until energy catches up,
	// so a walk to a far extractor is worth nothing then (smoke 2026-11-25: 20 claims in 3 min, E at 0, M banked).
	if (aiEconomyMgr.isEnergyStalling) return null;
	++fwdCalls;
	if (commFwdTask !is null) {
		// one claim at a time; whoever builds it (the commander or a constructor nearby), the spot is ours
		if (ai.frame <= fwdDue) { ++fwdBusy; return null; }
		++fwdFailed;  // later than its own estimate: blocked or nobody could take it
		IUnitTask@ stale = commFwdTask;
		@commFwdTask = null;
		stale.Abort();
	}
	array<AIFloat3> sp; array<float> si; array<bool> so;
	const uint n = AiGetMetalSpots(sp, si, so);
	if (n == 0) return null;
	float avg = 0.f; for (uint k = 0; k < n; ++k) avg += si[k]; avg = AiMax(1e-3f, avg / float(n));
	const float perMex = aiEconomyMgr.metal.income / float(AiMax(1, int(Brain::Economist::mexes.length())));
	const float H = Brain::Economist::Horizon();
	const AIFloat3 ec0 = AiEnemyBasePos();
	const float V = GameValue();
	const float rate = JobValue(null) / AiMax(1.f, Brain::Economist::Horizon());  // metal/s the commander's build power carries
	const float cost = Brain::Economist::MetalValue(Brain::Economist::mexT1);
	int best = -1; float bestScore = curScore; float topSeen = -1e30f;
	for (uint k = 0; k < n; ++k) {
		if (!so[k]) continue;
		const float dU = HasBase() ? basePos.distance2D(sp[k]) : 0.f;
		const float dE = ec0.distance2D(sp[k]);
		const float hold = dE / AiMax(1.f, dU + dE);
		const float t = from.distance2D(sp[k]) / AiMax(1.f, commander.circuitDef.speed);
		const float gain = (perMex * si[k] / avg * AiMax(0.f, H - t) * hold - cost) * CommShare() - rate * t;  // marginal: the share only it would do
		if (gain <= bestScore) continue;
		const float sc = gain - CommPDeath(sp[k], EscapeTime(sp[k])) * V;
		topSeen = AiMax(topSeen, sc);
		if (sc > bestScore) { bestScore = sc; best = int(k); }
	}
	fwdBestSeen = topSeen; fwdCurSeen = curScore;
	if (best < 0) { ++fwdNone; return null; }
	++commFwd; lastFwdGain = bestScore;
	// the claim's own estimate: walk there, then build the extractor at the commander's rate
	const float tWalk = from.distance2D(sp[best]) / AiMax(1.f, commander.circuitDef.speed);
	fwdDue = ai.frame + int((tWalk + cost / AiMax(1e-3f, rate)) * SECOND);
	@commFwdTask = aiBuilderMgr.Enqueue(TaskB::Spot(Task::BuildType::MEX, Task::Priority::HIGH, Brain::Economist::mexT1, sp[best], best, true, OrderLife(Brain::Economist::mexT1, sp[best])));
	return commFwdTask;
}

// the commander stands at p for the job and then must get out: enemies that can reach it in that whole window count.
// Counted over the escape time alone, the risk hovered just under the gain (27 vs 29-38) 1700 out until a Thud
// walked in during the job and killed it at 15:08 (cmd_m79).
float JobTime(IBuilderTask@ bt)
{
	if (bt is null || bt.buildDef is null || commander is null) return 0.f;
	const float walk = commander.GetPos(ai.frame).distance2D(bt.GetBuildPos()) / AiMax(1.f, commander.circuitDef.speed);
	return walk + bt.buildDef.buildTime / AiMax(1.f, commander.circuitDef.buildSpeed);
}
// Ground we watch: in our sight, or inside the radar of one of our buildings (unit facts, gen_facts.py).
bool Watched(const AIFloat3& in p)
{
	if (AiIsInLOS(p)) return true;
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	for (uint i = 0; i < all.length(); ++i) {
		if (all[i].circuitDef.IsMobile()) continue;
		const float r = Facts::RadarRange(all[i].circuitDef.GetName());
		if (r > 0.f && all[i].GetPos(ai.frame).distance2D(p) <= r) return true;
	}
	return false;
}
bool CommWorth(const AIFloat3& in p, float gain, float tJob = 0.f)
{
	// Its risk is read from the enemies we see: on ground nobody watches it reads ~0 whatever is there, and the commander
	// walked to an extractor 2651 out and died to an attacker nobody saw (cs2). Where we can't watch, the risk can't
	// be known, so it doesn't go (a constructor does). 1v1 winners keep it home: from start, median 276 at 3-6 min,
	// 501 at 6-9, ~1000 at 12-15 (replays.db, 107 winners); the 2000-3000 forward commander is the team-game cluster.
	// Before the earliest enemy raid can arrive nothing of theirs can be there, watched or not (refusing unwatched ground
	// from the start left 4 extractors at 8:00 in two of three games, ck2/ck3: no radar yet, spots out of sight).
	const bool knownEmpty = float(ai.frame) / SECOND + tJob < Opening::raidArrive;
	if (commander !is null && !knownEmpty && !Watched(p) && p.distance2D(commander.GetPos(ai.frame)) > commander.circuitDef.GetBuildDistance()) {
		lastV = GameValue(); lastRisk = lastV; lastGain = gain;
		return false;
	}
	lastV = GameValue();
	lastRisk = CommPDeath(p, EscapeTime(p) + tJob) * lastV;
	lastGain = gain;
	return gain >= lastRisk;  // a tie (e.g. idle, out of danger) stays and looks for its best job
}

/*
 * The commander defends home (players pull the commander onto raiders at their base; the guides: early defence is the
 * commander and a laser tower). Each second, every armed enemy on our side is a candidate:
 *   stake  = our buildings it reaches before we answer (Command::OursThreatened) + its own value
 *   win    = commander + our armed units near it beat what fights there during the fight (Command::Cover)
 *   risk   = P(commander dies there) x everything we own
 * The best stake - risk > 0 that we can win gets the commander, on a builder wait task for the fight (the builders'
 * ranking doesn't pull it back), attacking directly; when the target is gone it builds again. (Round 18: BARb's
 * raiders killed 10 extractors while Command skipped them, strength 1.4 vs 10.2, and the commander built on.)
 */
IUnitTask@ commFightTask = null;
int commFightTarget = -1, commFights = 0;
// Seconds until the commander has the target in reach: 0 if it already has, the gap closed at the speed difference if
// the commander is faster, never (1e9) if the target is as fast or faster (unit facts: range and speed from the defs).
float CatchTime(const AIFloat3& in c, const CCircuitDef@ cd, const AIFloat3& in p, const CCircuitDef@ d, float curSpeed = -1.f)
{
	const float gap = c.distance2D(p) - cd.GetMaxRange();
	if (gap <= 0.f) return 0.f;
	// how fast it is moving now (a raider shooting our buildings stands still: two Grunts dismantled our base - lab
	// twice - while the commander, which beats them, judged them by top speed and stayed away; Canis 2026-11-26)
	const float theirs = (curSpeed >= 0.f) ? curSpeed : ((d !is null && d.IsMobile()) ? d.speed : 0.f);
	const float closing = cd.speed - theirs;
	return (closing > 0.f) ? gap / closing : 1e9f;
}
// What fighting enemy i is worth to the commander now: what it saves and kills, less the game it risks and the
// building its time would do (-1e30 when it can't or shouldn't: not on our side, uncatchable, outgunned).
float CommNet(uint i, const AIFloat3& in c, const CCircuitDef@ cd, const array<AIFloat3>@ ep, const array<AIFloat3>@ ev,
	const array<CCircuitDef@>@ ed, const array<int>@ ef, const array<float>@ eh, const array<CCircuitUnit@>@ all, float V, float commRate)
{
	const CCircuitDef@ d = ed[i];
	if (d is null || !d.IsMobile() || d.IsAbleToFly() || d.surfThrDmg <= 0.f || (ef[i] & 2) == 0) return -1e30f;
	if (!Assess::OnOurSide(ep[i])) return -1e30f;
	const float t = CatchTime(c, cd, ep[i], d, ev[i].Length2D() * SECOND);
	if (t >= 1e8f) return -1e30f;  // faster than the commander and out of its reach: a chase it can't win
	const float stake = Command::OursThreatened(i, all, t) + Command::EnemyValue(i, Economist::Horizon());
	// what fights there while we kill it, against the commander and our armed units within their reach
	const float tFight = eh[i] * d.health / AiMax(1e-3f, cd.GetSustainedDps());
	const float theirs = Command::Cover(ep[i], tFight);
	float ours = cd.threat;
	for (uint k = 0; k < all.length(); ++k) {
		const CCircuitDef@ ud = all[k].circuitDef;
		if (all[k] is commander || ud.threat <= 0.f || ud.surfThrDmg <= 0.f) continue;
		const float reach = ud.GetMaxRange() + (ud.IsMobile() ? ud.speed * (t + tFight) : 0.f);
		if (all[k].GetPos(ai.frame).distance2D(ep[i]) <= reach) ours += ud.threat;
	}
	if (ours <= theirs) return -1e30f;
	// what the commander adds is only the difference it makes: the chance the fight is won with it less without it.
	// Credited with the whole stake whenever our side was stronger, it took 9 fights in 30 s beside an army 3.5x
	// theirs and was killed by Levelers at 16:01, the game lost with 5596 army standing (cmd_m47)
	const float marginal = AiMax(0.f, Brain::Production::WinShare(ours, theirs) - Brain::Production::WinShare(ours - cd.threat, theirs));
	// the risk on the way too, not only at the target: where it stands now, half way and there (measured at the target
	// alone, it walked 1400 toward a resurrected Pawn past Thuds and died at 12:17, cmd_m40)
	const AIFloat3 mid = (c + ep[i]) * 0.5f;
	// at the target it stands under fire for the whole fight and only then walks out: exposed tFight + the escape
	// (escape alone counted none of the fight: it fought Levelers 1561 out at stake-risk 36-261 and died at 12:28 with
	// 25 extractors standing, op4)
	float pD = CommPDeath(ep[i], tFight + EscapeTime(ep[i]));
	pD = AiMax(pD, CommPDeath(mid, EscapeTime(mid)));
	pD = AiMax(pD, CommPDeath(c, EscapeTime(c)));
	const float risk = pD * V;
	// what it saves only counts if it lives: dead, the game is lost and the stake with it. Counted in full whatever P,
	// a Gator near the base read 5186-10544 and the commander died in the fight 3 s later (cmd_m69, 15:44)
	return (1.f - pD) * stake * marginal - risk - (t + tFight) * commRate;  // its time is our best builder's time
}
void CommDefendUpdate()
{
	if (commander is null || !Opening::done || !HasBase()) return;
	// escaping is its job while builder safety has it on a safe task: a fight started from the escape route undid it
	// (left at 14:00, sent at a Raider 1 s later, dead at 14:05 - cmd_m67)
	if (commander.task !is null && safeTasks.findByRef(commander.task) >= 0) return;
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef, ids;
	const uint n = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	AiGetEnemyIds(ids);
	const AIFloat3 c = commander.GetPos(ai.frame);
	const CCircuitDef@ cd = commander.circuitDef;
	// still on a fight: keep at it while the target lives, can still be caught and is on our side (a chase without
	// those took the commander away after Pawns, faster than it, with no base, no extractors and no units: owner,
	// 2026-11-25 "WHERE ARE YOU WALKING WITH THE COMMANDER ... YOU GO AWAY WITH THE COMMANDER TO HUNT PAWNS")

	// what a second of the commander's time builds: the extractor it could put up per second of its build power
	// (as the opener ranks producers per second of commander time)
	float commRate = 0.f;
	if (Economist::mexT1 !is null) {
		CCircuitDef@ m = Economist::mexT1;
		const float yield = Economist::Extract(m.GetName()) * Command::spotIncome;
		commRate = (Economist::MetalValue(m) + yield * Economist::Horizon()) * cd.buildSpeed / AiMax(1.f, m.buildTime);
	}
	const float V = GameValue();
	// the same arrays Command reads
	Command::ePos = ep; Command::eDef = ed; Command::eFlags = ef; Command::eHp = eh; Command::eIds = ids; Command::eCost = ec;
	// still on a fight: keep at it only while the same test that started it still pays - the risk is re-read as the
	// commander takes damage (kept on target alone, it fought a Rogue while stake-risk fell 940 -> 213 -> 55 -> 15
	// and died at 13:05 with an army of 3056 standing: the game lost, Canis vs Cortex cmd_m30)
	if (commFightTask !is null && commander.task is commFightTask) {
		for (uint i = 0; i < n && i < ids.length(); ++i)
			if (ids[i] == commFightTarget) {
				if (CommNet(i, c, cd, ep, ev, ed, ef, eh, all, V, commRate) > 0.f) { commander.CmdAttackEnemy(commFightTarget); return; }
				break;
			}
		AiLog("[ANV] CommDefend: commander stops (target gone, or the fight no longer pays)");
		commFightTask.Abort(); @commFightTask = null; commFightTarget = -1;
		return;
	}
	int best = -1; float bestNet = 0.f;
	for (uint i = 0; i < n && i < ids.length(); ++i) {
		const float net = CommNet(i, c, cd, ep, ev, ed, ef, eh, all, V, commRate);
		if (net > bestNet) { bestNet = net; best = int(i); }
	}
	if (best < 0) return;
	const float t = CatchTime(c, cd, ep[best], ed[best], ev[best].Length2D() * SECOND);
	const float tFight = eh[best] * ed[best].health / AiMax(1e-3f, cd.GetSustainedDps());
	@commFightTask = aiBuilderMgr.Enqueue(TaskB::Wait(int((t + tFight) * SECOND) + SECOND));
	if (commFightTask is null) return;
	aiBuilderMgr.AssignTask(commander, commFightTask);
	commFightTarget = ids[best];
	commander.CmdAttackEnemy(commFightTarget);
	++commFights;
	AiLog("[ANV] CommDefend: commander -> " + ed[best].GetName() + " at (" + int(ep[best].x) + "," + int(ep[best].z) + "), stake-risk " + int(bestNet));
}

// Cloak (owner: "commander cloaked and standing is invisible unless he moves or units stand next to him"). Unit facts:
// the Armada commander cloaks at 100 E/s standing, 1000 moving, and is revealed within 50. It cloaks while the risk
// where it stands over this update - P(death) x the game - beats the energy for that time at the energy price, and
// only with the energy for it in store (a stall drops the cloak anyway).
bool commCloaked = false; int commCloakFrame = -1;
void CommCloakUpdate()
{
	if (commander is null || !commander.circuitDef.IsAbleToCloak()) return;
	const string nm = commander.circuitDef.GetName();
	const float dt = (commCloakFrame < 0) ? 1.f : AiMax(1.f, float(ai.frame - commCloakFrame) / SECOND);
	commCloakFrame = ai.frame;
	const AIFloat3 v = commander.GetVel();
	const bool moving = v.x * v.x + v.z * v.z > 0.f;
	const float costE = moving ? Facts::CloakCostMoving(nm) : Facts::CloakCost(nm);
	const AIFloat3 c = commander.GetPos(ai.frame);
	const float risk = CommPDeath(c, AiMax(dt, EscapeTime(c))) * GameValue();
	const float cost = costE * dt / AiMax(1e-3f, Economist::energyPerMetal);
	const bool want = costE > 0.f && risk > cost && aiEconomyMgr.energy.current >= costE * dt;
	if (want != commCloaked) {
		commander.CmdCloak(want);
		commCloaked = want;
		AiLog("[ANV] CommCloak: " + (want ? "on" : "off") + " (" + (moving ? "moving" : "standing") + ", risk " + int(risk) + " vs energy " + int(cost) + " metal-eq over " + F1(dt) + " s)");
	}
}
void CommGuardUpdate()
{
	if (!Opening::done) return;  // the opening directs the commander until its lab stands (#95)
	if (commander is null || Brain::Intel::allFactories.length() == 0) return;
	if (commGuardTask !is null && commander.task is commGuardTask) return;
	if (commFightTask !is null && commander.task is commFightTask) return;  // defending: CommDefendUpdate decides
	const AIFloat3 c = commander.GetPos(ai.frame);
	IBuilderTask@ cur = cast<IBuilderTask>(commander.task);
	// Worth staying: the core's ranking picks the commander's jobs (travel + payback, like every builder). The script's
	// forward claims and best-job overrides were a second decision-maker for the same choice: 40 claims in 5 minutes
	// pulled the commander off each job before it finished (1 extractor by minute 3, 1v1 Avalanche 2026-11-25).
	// Only the risk decision stays here.
	if (CommWorth(c, JobValue(cur), JobTime(cur)))
		return;
	@commGuardTask = CommSafeJob(c);
	if (commGuardTask is null) return;
	aiBuilderMgr.AssignTask(commander, commGuardTask);
	++commGuards;
	AiLog("[ANV] CommRisk: leaving job, risk " + int(lastRisk) + " > gain " + int(lastGain) + " (danger " + F1(commDanger) + " cover " + F1(commCover) + " dps " + F1(commDps) + " V " + int(lastV) + ")");
}

string NearestEnemyText(const AIFloat3& in p)
{
	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
	const uint n = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	int best = -1; float bd = 1e30f;
	for (uint i = 0; i < n; ++i) { const float d = ep[i].distance2D(p); if (d < bd) { bd = d; best = int(i); } }
	if (best < 0) return "none";
	return ((ed[best] is null) ? "unknown" : ed[best].GetName()) + "@" + int(bd) + " flags=" + ef[best];
}
void OnUnitDestroyed(CCircuitUnit@ unit)
{
	Command::OnDestroyed(unit);
	Scout::OnDestroyed(unit);
	if (Economist::IsProducer(unit.circuitDef)) Economist::OnProducerLost(unit);
	{  // every loss, for the checklist: what, where, on which job
		const AIFloat3 p = unit.GetPos(ai.frame);
		IBuilderTask@ bt = cast<IBuilderTask>(unit.task);
		AiLog("[ANV-DEAD] t=" + (ai.frame / SECOND) + "s " + unit.circuitDef.GetName() + " m=" + int(unit.circuitDef.costM)
			+ " at (" + int(p.x) + "," + int(p.z) + ") fromBase=" + int(HasBase() ? basePos.distance2D(p) : -1.f)
			+ " job=" + ((bt !is null && bt.buildDef !is null) ? bt.buildDef.GetName() : (unit.task is null ? "-" : ("task" + int(unit.task.GetType()))))
			+ " nearestEnemy=" + NearestEnemyText(p));
	}
	if (unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask)) {
		const AIFloat3 p = unit.GetPos(ai.frame);
		AiLog("[ANV] COMMANDER LOST at (" + int(p.x) + "," + int(p.z) + ") dist-from-base=" + int(HasBase() ? basePos.distance2D(p) : -1.f)
			+ " task=" + (unit.task is null ? -1 : int(unit.task.GetType())) + " t=" + Minute() + "m");
		@commander = null;
	}
	if (Strategic::mlvDef !is null && unit.circuitDef is Strategic::mlvDef)
		Strategic::minelayers = AiMax(0, Strategic::minelayers - 1);
	Strategic::ownedMetal = AiMax(0.f, Strategic::ownedMetal - unit.circuitDef.costM);
	if (IsArmy(unit.circuitDef))
		Strategic::armyMetal = AiMax(0.f, Strategic::armyMetal - unit.circuitDef.costM);
	const bool recycled = Recycler::OnDestroyed(unit);
	if (!recycled) {
		Intel::OnLoss(unit);
		Assess::OnLoss(unit);
	}
	Intel::OnDestroyed(unit);
	Strategic::OnDestroyed(unit);
	Economist::OnDestroyed(unit);
	Production::OnDestroyed(unit);
	if (!unit.circuitDef.IsMobile() && (Factory::userData[unit.circuitDef.id].attr & (Factory::Attr::T2 | Factory::Attr::T3)) != 0)
		Recycler::advFactories = AiMax(0, Recycler::advFactories - 1);
}

void Update()  // every 30 frames
{
	CheckSide();
	Check::Update();
	Awareness::Update();
	Command::RaidTick();
	Check::Micro();
	aiSwitchHighGroundArty = true;
	aiSwitchHeightSquads = true;
	aiSwitchScoutMap = true;
	aiSwitchEngageSeen = true;
	aiSwitchFocusFire = true;
	aiSwitchStrafe = true;
	Intel::Update();
	Assess::Update();
	Director::Update();
	// the core values builder jobs and smooths energy demand over the same horizon as the script (it was never set:
	// the core ran on a 1-second horizon)
	Economist::MeasureExtraction();
	Economist::UpdateProducerLife();
	aiMilitaryMgr.SetValueHorizon(Economist::ProducerLife());
	aiMilitaryMgr.SetProducerLife((Economist::producerLosses > 0) ? Economist::MeasuredLife() : 0.f);  // feedback to job values
	// (BARb's attack/raid quotas and the core raid task's targets are gone: no combat unit is in a BARb task any more;
	// Brain::Command decides each fight from its own defence estimate)
	Opening::Update();  // map-based opening, re-planned after every job (#94)
	Command::Update();  // Anarva's own army (BARb squads, recalls and holds retired)
	// every module re-decides on the engine's own slow-update tick (no per-module polling periods)
	Recycler::Update();
	Strategic::Update(Intel::jamAlert);
	Scout::Update();
	EcoPos::Update();
	RezLab::Update();
	MexPorc::Update();
	SquadLog();
	Radar::Update();
	Storage::Update();
	Storage::UpdateEnergy();
	CommDefendUpdate();
	CommGuardUpdate();
	CommCloakUpdate();
	BuilderSafeUpdate();
	ReclaimUpdate();
	Recycler::EcoReclaimUpdate();
	Recycler::NanoUpdate();

	if (ai.frame % MINUTE < SECOND) {
		if (commander !is null) {
			const AIFloat3 cp = commander.GetPos(ai.frame);
			AiLog("[ANV] commander at (" + int(cp.x) + "," + int(cp.z) + ") dist-from-base=" + int(HasBase() ? basePos.distance2D(cp) : -1.f)
				+ " task=" + (commander.task is null ? -1 : int(commander.task.GetType())) + " redirects=" + commRedirects + " guards=" + commGuards + " reclaimOrders=" + reclaimOrders + " builderEvacs=" + builderEvacs + " retreats=" + commRetreats + " frontReclaims=" + commReclaims + " fwdClaims=" + commFwd + " fwdFailed=" + fwdFailed + " fwd(calls/busy/none)=" + fwdCalls + "/" + fwdBusy + "/" + fwdNone + " fwdBest=" + int(fwdBestSeen) + " vs cur " + int(fwdCurSeen));
		}
		AiLog("[ANV] " + Scout::Status());
		uint spotsOpenOurs = 0, spotsOpen = 0, spotsAll = 0;
		{
			array<AIFloat3> lsp; array<float> lsi; array<bool> lso;
			spotsAll = AiGetMetalSpots(lsp, lsi, lso);
			for (uint i = 0; i < spotsAll; ++i)
				if (lso[i]) { ++spotsOpen; if (Assess::OnOurSide(lsp[i])) ++spotsOpenOurs; }
		}
		AiLog("[ANV] spots all=" + spotsAll + " open=" + spotsOpen + " openOurSide=" + spotsOpenOurs);
		AiLog("[ANV] eco t=" + Minute() + "m workers=" + aiBuilderMgr.GetWorkerCount() + " mex=" + Economist::mexes.length()
			+ " M inc=" + F1(aiEconomyMgr.metal.income) + " M " + int(aiEconomyMgr.metal.current) + "/" + int(aiEconomyMgr.metal.storage)
			+ " E inc=" + F1(aiEconomyMgr.energy.income) + " E " + int(aiEconomyMgr.energy.current) + "/" + int(aiEconomyMgr.energy.storage)
			+ " stall=" + aiEconomyMgr.isEnergyStalling + " bpTarget=" + F1(aiEconomyMgr.metal.income * aiFactoryMgr.buildpowerRatio));
		Intel::BridgeLog();

		AiLog("[ANV] t=" + Minute() + "m " + Director::Status() + " | " + Assess::Status() + " | allPow=" + F1(Director::MeasuredPower()) + " units=" + Army::ground.length()
			+ " raiders=" + Army::raiders.length() + " " + Command::Status()

			+ " enemyMob=" + F1(Brain::Economist::KnownEnemyThreat()) + " coreMob=" + F1(aiEnemyMgr.mobileThreat) + " jamCost=" + F1(Intel::jammerCost)
			+ " maxHeat=" + F1(Intel::MaxHeat()) + " eyes=" + Intel::eyes.length() + "/" + Intel::eyesOrdered
			+ " | " + Production::Status() + " | " + Recycler::Status() + " | " + Strategic::Status()
			+ " | E inc=" + F1(aiEconomyMgr.energy.income) + " pull=" + F1(aiEconomyMgr.energy.pull)
			+ " M inc=" + F1(aiEconomyMgr.metal.income));
	}
}

}  // namespace Brain
