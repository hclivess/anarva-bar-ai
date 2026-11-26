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
float constructorValue = 0.f;  // metal-eq one more constructor saves (Production compares it with every other unit)
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
		array<AIFloat3> rp; array<float> rv;
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
			if (pTaken < 1.f && !Assess::OnOurSide(msp[i]) && !AiIsInLOS(msp[i])) {
				const float age = scouted2 ? float(ai.frame - Scout::lastSeen[Intel::CellOf(msp[i])]) / SECOND : float(ai.frame) / SECOND;
				pTaken = AiMin(1.f, age / AiMax(1.f, cross2));
			}
			if (pTaken <= 0.f) continue;
			rp.insertLast(msp[i]);
			// what killing their extractor there is worth: its cost + what it would extract over our horizon
			const float yieldH = (Economist::mexT1 is null) ? 0.f : msi[i] * Economist::Extract(Economist::mexT1.GetName()) * Economist::Horizon();
			rv.insertLast(pTaken * (mexV + yieldH));
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
			}
	}
	const float N = float(AiMax(1, int(aiBuilderMgr.GetWorkerCount())));
	const float saved = claimYield * claimWork / 2.f * (1.f / N - 1.f / (N + 1.f));
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
			if (bt is null || bt.buildDef is null) ++unemployed;
		}
	}
	const bool work = unclaimed > 0 && unemployed == 0 && conDef !is null && saved > Economist::MetalValue(conDef) && Director::ratio >= 1.f;
	// the value Production weighs against every other unit: the yield saved, while every constructor has a job
	constructorValue = (unclaimed > 0 && unemployed == 0) ? saved : 0.f;
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
void OnTaskRemoved(IUnitTask@ t) { if (t is pending) @pending = null; }
bool IsFactory(const CCircuitDef@ d) { return !d.IsMobile() && d.buildSpeed > 0.f && Facts::BuildOptions(d.GetName()).length() > 0; }
float RaidLoss(CCircuitUnit@ u, const CCircuitDef@ con)
{
	const CCircuitDef@ d = u.circuitDef;
	const string nm = d.GetName();
	const float upkeep = Facts::EnergyUpkeep(nm);
	const float eYield = Facts::EnergyMake(nm) + ((upkeep < 0.f) ? -upkeep : 0.f);
	array<AIFloat3> sp; array<float> si; array<bool> so;
	const uint ns = AiGetMetalSpots(sp, si, so);
	float avg = 0.f; for (uint i = 0; i < ns; ++i) avg += si[i]; avg = (ns > 0) ? avg / float(ns) : 0.f;
	float yield = Economist::Extract(nm) * avg + Facts::MetalMake(nm) + eYield / AiMax(1e-3f, Economist::energyPerMetal);
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
	if (pending !is null) return;  // the last tower first
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
			const float expected = val[i] * val[i] / AiMax(1.f, total);
			if (expected > bestHeat) { bestHeat = expected; @best = mx[i]; }
		}
	}
	if (best is null) return;
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
	@pending = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE, seen ? Task::Priority::NOW : Task::Priority::NORMAL,
		tur, p, around, true, OrderLife(tur, p)));
	IBuilderTask@ pbt = cast<IBuilderTask>(pending);
	if (pbt !is null) pbt.value = bestHeat;
	AiLog("[ANV] MexPorc: " + tur.GetName() + (seen ? " NOW" : " valued") + " at extractor (loss there, seen or expected from the raid, " + int(bestHeat) + " > turret " + int(cost) + ")");
}
}  // namespace MexPorc

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

void Update()
{
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
	return pickVals[k] * pOccupied * alive * AiMin(1.f, 2.f * d.losRadius / AiMax(1.f, Intel::CELL));
}
void OnFinished(CCircuitUnit@ u)
{
	const int at = pendingDefs.find(u.circuitDef.id);
	if (at < 0) return;
	pendingDefs.removeAt(at);
	scouts.insertLast(u);
}
void OnDestroyed(CCircuitUnit@ u) { const int at = scouts.findByRef(u); if (at >= 0) { scouts.removeAt(at); ++lost; } }
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
		scouts[best].CmdMoveTo(picks[p]);
	}
}

string Status() { return "scout: worthy=" + worthy + " top=" + int(topValue) + " quota=" + aiMilitaryMgr.quota.scout; }

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
		const float gain = d.costM - make * H / epm;
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
		nanoUse.get(key, use);
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
		for (uint i = 0; i < w; ++i) if (wr[i]) pool += wm[i];
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
	const float saving = (C == 0) ? 1e9f : extra * tau * float(U * U) / (2.f * float(C) * float(C + 1));
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
	// The ground units a fighter of ours will meet: the enemy's as seen (weighted by strength); none seen yet, the
	// units this factory offers (they build the same class of units). A unit outranged by them takes their fire while
	// it closes the gap: its health in the fight is less that damage (range, speed and dps from the unit defs). Without
	// it, sqrt(dps x health) per metal made the Flea - a scout with a needle gun - our best fighter: 14-16 per game
	// and the extractors raided away (short test s32, 2026-11-25).
	array<float> mixDps, mixRange, mixW, mixAoe, mixShot, mixSpeed, mixRad;
	{
		array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
		const uint ne = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
		for (uint i = 0; i < ne; ++i) {
			const CCircuitDef@ d = ed[i];
			if (d is null || !d.IsMobile() || d.IsAbleToFly() || d.GetSustainedDps() <= 0.f) continue;
			mixDps.insertLast(d.GetSustainedDps()); mixRange.insertLast(d.GetMaxRange()); mixAoe.insertLast(d.GetAoe());
			mixShot.insertLast(d.GetShotSpeed()); mixSpeed.insertLast(d.speed); mixRad.insertLast(d.GetRadius());
			mixW.insertLast(sqrt(d.GetSustainedDps() * AiMax(1.f, d.health)));
		}
		if (mixW.length() == 0) {
			for (uint i = 0; i < opts.length(); ++i) {
				CCircuitDef@ d = ai.GetCircuitDef(opts[i]);
				if (d is null || !d.IsMobile() || d.IsAbleToFly() || d.GetSustainedDps() <= 0.f || d.IsRoleAny(Unit::Role::BUILDER.mask)) continue;
				mixDps.insertLast(d.GetSustainedDps()); mixRange.insertLast(d.GetMaxRange()); mixAoe.insertLast(d.GetAoe());
				mixShot.insertLast(d.GetShotSpeed()); mixSpeed.insertLast(d.speed); mixRad.insertLast(d.GetRadius()); mixW.insertLast(1.f);
			}
		}
	}
	// An army holds the flow, not only the stock: our income over the horizon is what a raid takes and what holding
	// the map keeps (the constructor's value counts the yield it claims over the horizon; against a stake of owned
	// metal alone the lab made 19 constructors and 86 army by minute 8 vs the winners' 10.8 and 2036, Feast 2026-11-25)
	const float H0 = AiMax(1.f, Economist::Horizon());
	const float flow = (aiEconomyMgr.metal.income + aiEconomyMgr.energy.income / AiMax(1e-3f, Economist::energyPerMetal)) * H0;
	const float stake = Strategic::ownedMetal + Assess::EnemyValue() + flow;
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
	CCircuitDef@ bestDef = null; float bestRatio = 0.f, bestV = 0.f; int bestJob = -1;  // 0 fight, 1 build, 2 scout
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
			float gapDmg = 0.f, wSum = 0.f;
			for (uint k = 0; k < mixW.length(); ++k) {
				gapDmg += mixW[k] * mixDps[k] * AiMax(0.f, mixRange[k] - d.GetMaxRange()) / AiMax(1.f, d.speed);
				wSum += mixW[k];
			}
			if (wSum > 0.f) gapDmg /= wSum;
			// Splash: a shot with area of effect hits every unit of ours within its radius. Units in a squad stand about
			// a body apart (two of their radii), so one shot hits ~(aoe / that spacing)^2 of them, at least one - a small
			// unit massed takes each splash shot several times over (44 Pawns lost to Pounders in one minute, Canis
			// 2026-11-26). Its health in the fight is divided by the hits a shot makes, averaged over the enemy mix.
			float hitsW = 0.f;
			for (uint k = 0; k < mixW.length(); ++k) {
				const float spacing = AiMax(1.f, 2.f * d.GetRadius());
				hitsW += mixW[k] * AiMax(1.f, (mixAoe[k] / spacing) * (mixAoe[k] / spacing));
			}
			const float hits = (wSum > 0.f) ? hitsW / wSum : 1.f;
			// Dodging: a shell fired at range R with speed v lands R/v later; a target of radius r moving at u has moved
			// u*R/v by then, so it is hit with chance ~ r / max(r, u*R/v) (instant weapons always hit). Our damage counts
			// the hits we land on the units we'll meet; our health, the hits theirs land on us (unit facts).
			float landW = 0.f, takenW = 0.f;
			for (uint k = 0; k < mixW.length(); ++k) {
				landW += mixW[k] * HitChance(d.GetShotSpeed(), d.GetMaxRange(), mixSpeed[k], mixRad[k]);
				takenW += mixW[k] * HitChance(mixShot[k], mixRange[k], d.speed, d.GetRadius());
			}
			const float land = (wSum > 0.f) ? landW / wSum : 1.f;
			const float taken = (wSum > 0.f) ? AiMax(1e-3f, takenW / wSum) : 1.f;
			const float hpSurf = AiMax(1.f, (hp - gapDmg) / hits / taken);
			const float ua = sqrt(AiMax(0.f, d.airThrDmg) * hp), us = sqrt(AiMax(0.f, d.surfThrDmg) * land * hpSurf);
			terms = "(hits " + F2(land) + " taken " + F2(taken) + " splash " + F1(hits) + " gapDmg " + int(gapDmg) + ")";
			vFight = stakeAir * (WinShare(sAir + ua, eAir) - WinShare(sAir, eAir))
				+ stakeSurf * (WinShare(sSurf + us, eSurf) - WinShare(sSurf, eSurf));
			vFight *= AiMax(0.f, 1.f - dist / AiMax(1.f, d.speed) / H);
		}
		// information is worth what we can do with it: the share of a fight our forces could contest (a warning saves
		// nothing when the army can't answer - 29 Fleas and 3 fighters at our 25 strength against 3789, round 20)
		vScout = Scout::NextValue(d) * WinShare(sSurf + sAir, eSurf + eAir);
		const float v = AiMax(vFight, AiMax(vBuild, vScout));
		const float ratio = v / AiMax(1.f, Economist::CostNow(d));  // energy at its price now (binding or not)
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
	AiLog("[ANV-PROD] " + fdef.GetName() + " -> " + bestDef.GetName() + " as " + (bestJob == 2 ? "scout" : (bestJob == 1 ? "constructor" : "fighter"))
		+ " (value " + int(bestV) + " per metal " + F2(bestRatio) + "; S air/surf " + int(sAir) + "/" + int(sSurf) + " E " + int(eAir) + "/" + int(eSurf) + ")" + " |" + why);
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
float HitChance(float shotSpeed, float range, float targetSpeed, float targetRadius)
{
	if (shotSpeed <= 0.f) return 1.f;
	const float drift = targetSpeed * range / shotSpeed;
	return AiMin(1.f, AiMax(1.f, targetRadius) / AiMax(AiMax(1.f, targetRadius), drift));
}
float WinShare(float S, float E) { return (S + E > 0.f) ? S / (S + E) : 0.f; }

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
void UpdateProducerLife()
{
	const int f = ai.frame;
	if (producerFrame >= 0) {
		int n = 0;
		const array<CCircuitUnit@>@ mine = AiGetTeamUnits();
		for (uint i = 0; i < mine.length(); ++i) if (IsProducer(mine[i].circuitDef)) ++n;
		producerExposure += float(n) * float(f - producerFrame) / SECOND;
	}
	producerFrame = f;
}
float ProducerLife()
{
	const float floorH = Horizon();
	return (producerLosses > 0) ? AiMax(floorH, producerExposure / float(producerLosses)) : AiMax(floorH, producerExposure);
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
	return (MetalValue(lab) + n * MetalValue(mexT2)) / gain;
}

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
		const bool banked = aiEconomyMgr.metal.current >= Brain::Economist::MetalValue(facDef);
		ok = (payback < H && (banked || payback < mexBack)) || forced;
		why = "payback " + int(payback) + "s vs horizon " + int(H) + "s, next extractor " + (mexBack >= 1e9f ? "none" : (int(mexBack) + "s")) + (forced ? ", enemy teched" : "");
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
float raidRate = 0.f;         // raiders per second it adds (lab rate; capped by income in Value)
float raidStrength = 0.f;     // sqrt(dps x health) of one raider
float raidDps = 0.f;
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
AIFloat3 Home() { if (planning) return planHome; return HasBase() ? basePos : commander.GetPos(ai.frame); }
AIFloat3 Them() { return planning ? planThem : AiEnemyBasePos(); }
float Strength(const CCircuitDef@ d) { return sqrt(AiMax(0.f, d.GetSustainedDps()) * AiMax(1.f, d.health)); }

// a spot near home where it can stand: home, else the first point of a ring at the commander's build distance
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
				raidArrive = arrive; raidRate = 1.f / AiMax(1e-3f, ut); raidStrength = Strength(r); raidDps = r.GetSustainedDps();
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
	}
	return v;
}

// do o from state s (walk + build at bp, waiting for missing resources)
void Apply(Sim@ s, const Opt@ o, float bp, float speed)
{
	const float walk = s.pos.distance2D(o.pos) / AiMax(1.f, speed);
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
		@planned = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::ENERGY, Task::Priority::NOW, o.def, o.pos, ComDef().GetBuildDistance(), true, OrderLife(o.def, o.pos)));
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
		const float walkBuild = s0.pos.distance2D(opts[lab].pos) / AiMax(1.f, speed) + opts[lab].def.buildTime / AiMax(1.f, bp);
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
				const float tt = opts[a].def.buildTime / AiMax(1.f, bp) + t.pos.distance2D(opts[a].pos) / AiMax(1.f, speed);
				bestE = AiMax(bestE, opts[a].yieldE / AiMax(1e-3f, tt));
				bestM = AiMax(bestM, opts[a].yieldM / AiMax(1e-3f, tt));
			}
			// one commander closes both gaps one after the other (g / r each), and each deficit runs until then: the stock
			// must carry each for the sum (half-credit for a shrinking deficit let the lab go first and stall, minute 1-2)
			const float tFix = ((needE > 0.f) ? needE / AiMax(1e-3f, bestE) : 0.f) + ((needM > 0.f) ? needM / AiMax(1e-3f, bestM) : 0.f);
			if (needE > 0.f) carried = carried && (bestE > 0.f) && (t.E >= needE * tFix);
			if (needM > 0.f) carried = carried && (bestM > 0.f) && (t.M >= needM * tFix);
		}
		if (noWait && carried) {
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
class Op {
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
		op.routeTo = dest; op.leg = 0;
		AiLog("[ANV-CMD] route for " + op.units.length() + " units: " + op.route.length() + " waypoints to (" + int(dest.x) + "," + int(dest.z) + ")");
	}
	bool atWp = true;
	for (uint k = 0; k < op.units.length() && atWp; ++k)
		if (op.units[k].GetPos(ai.frame).distance2D(op.route[op.leg]) > op.units[k].circuitDef.GetMaxRange()) atWp = false;
	if (atWp && op.leg + 1 < op.route.length()) { ++op.leg; atWp = false; }
	if (atWp && op.leg + 1 >= op.route.length()) return true;
	for (uint k = 0; k < op.units.length(); ++k) {
		string prevKey;
		const string key = "grp" + o + ":" + op.leg + ":" + int(op.routeTo.x) + "," + int(op.routeTo.z);
		if (lastOrder.get("" + op.units[k].id, prevKey) && prevKey == key) continue;
		lastOrder.set("" + op.units[k].id, key);
		op.units[k].CmdMoveTo(op.route[op.leg]);
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
	const float yield = Economist::Extract(nm) * spotIncome + Facts::MetalMake(nm) + eYield / AiMax(1e-3f, Economist::energyPerMetal);
	// they rebuild as we do: what a kill takes from them is its yield until it stands again (a constructor's walk from
	// their base and its build), not its whole future - symmetric with what a raid takes from us (MexPorc::RaidLoss)
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
		if (d.IsMobile()) continue;
		if (mine[k].GetPos(ai.frame).distance2D(ePos[i]) <= ed.GetMaxRange() + ed.speed * AiMax(1.f, tAnswer)) {
			// what we lose with it: its cost and what it would yield us over the horizon (same terms as an enemy's value)
			const string nm = d.GetName();
			const float upkeep = Facts::EnergyUpkeep(nm);
			const float eYield = Facts::EnergyMake(nm) + ((upkeep < 0.f) ? -upkeep : 0.f);
			const float yield = Economist::Extract(nm) * spotIncome + Facts::MetalMake(nm) + eYield / AiMax(1e-3f, Economist::energyPerMetal);
			// what a raid takes: its cost and its yield until it stands again, as for raid towers (MexPorc::RaidLoss).
			// With its whole future yield every defence looked worth any odds and the army threw itself away (army
			// 54-354 at minute 8 in round 31 vs 1400-1900 at minute 12 in round 30).
			if (yield >= 0.f) v += MexPorc::RaidLoss(mine[k], EcoPos::CheapestConstructor());
		}
	}
	return v;
}
void Order(CCircuitUnit@ u, const string& in key, int kind, const AIFloat3& in p, int target)
{
	string prev;
	if (lastOrder.get("" + u.id, prev) && prev == key) return;
	lastOrder.set("" + u.id, key);

	u.CmdMoveTo(p);  // plain moves only: units fire at what is in reach while moving and can dodge
}
// A fight is worth taking when what it keeps beats what it risks: p = our share at strength S x trade against defence
// D (the win share production uses); winning keeps the value at a square-law share of our metal lost, losing costs it
// all. A fixed "S x trade > D" gate skipped a Pawn raid at our base 7 times at 11.0 vs 11.4 while it killed 1880
// metal of economy (Theta, round 30): an even fight for that much is taken by any player.
float FightGain(float value, float S, float D, float metal)
{
	const float st = S * AiMax(1e-3f, Assess::trade);
	if (D <= 0.f) return value;
	const float p = Production::WinShare(st, D);
	const float r = D / AiMax(1e-6f, st);
	const float loss = p * metal * AiMin(1.f, r * r) + (1.f - p) * metal;
	return value * p - loss;
}
float Strength(const array<CCircuitUnit@>@ us)
{
	float s = 0.f;
	for (uint i = 0; i < us.length(); ++i) s += us[i].circuitDef.threat;
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

	// keep live ops: drop dead units, finished targets, and fights we no longer win
	dictionary assigned;
	for (int o = int(ops.length()) - 1; o >= 0; --o) {
		Op@ op = ops[o];
		for (int k = int(op.units.length()) - 1; k >= 0; --k)
			if (force.findByRef(op.units[k]) < 0) op.units.removeAt(k);
		bool alive = op.enemyId < 0;
		for (uint i = 0; i < n && !alive; ++i)
			if (eIds[i] == op.enemyId) { alive = true; op.pos = ePos[i]; }
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
			op.defence = AiMax(op.defence, Cover(oc0, tLeft));
		}
		float opMetal = 0.f;
		for (uint k = 0; k < op.units.length(); ++k) opMetal += op.units[k].circuitDef.costM;
		if (!alive || op.units.length() == 0 || FightGain(op.value, S, op.defence, opMetal) <= 0.f) {
			if (alive && op.units.length() > 0) {
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
					+ ", metal sent " + int(op.startMetal) + " left " + int(left) + ", enemy metal killed meanwhile " + int(Assess::killedTotal - op.killedAtStart));
			}
			ops.removeAt(o);
			continue;
		}
		for (uint k = 0; k < op.units.length(); ++k) assigned.set("" + op.units[k].id, true);
	}
	array<CCircuitUnit@> freeUnits;
	for (uint i = 0; i < force.length(); ++i)
		if (!assigned.exists("" + force[i].id)) freeUnits.insertLast(force[i]);
	// concentration: free units reinforce the most valuable defended fight already running (the square law rewards
	// every unit added there); undefended raids keep their single unit
	{
		int bestOp = -1;
		for (uint o = 0; o < ops.length(); ++o)
			if (ops[o].defence > 0.f && (bestOp < 0 || ops[o].value > ops[bestOp].value)) bestOp = int(o);
		if (bestOp >= 0 && freeUnits.length() > 0) {
			for (uint i = 0; i < freeUnits.length(); ++i) ops[bestOp].units.insertLast(freeUnits[i]);
			ops[bestOp].route.resize(0);  // re-route the bigger squad
			AiLog("[ANV-CMD] reinforce (" + int(ops[bestOp].pos.x) + "," + int(ops[bestOp].pos.z) + ") +" + freeUnits.length() + " units");
			freeUnits.resize(0);
		}
	}

	// new ops, best first, while the free units can win them
	if (freeUnits.length() > 0) {
		AIFloat3 fc(0.f, 0.f, 0.f);
		float fSpeed = 1e9f;
		for (uint i = 0; i < freeUnits.length(); ++i) { fc = fc + freeUnits[i].GetPos(ai.frame); fSpeed = AiMin(fSpeed, freeUnits[i].circuitDef.speed); }
		fc = fc / float(freeUnits.length());
		fSpeed = AiMax(1.f, fSpeed);
		float freeDps = 0.f;
		for (uint i = 0; i < freeUnits.length(); ++i) freeDps += freeUnits[i].circuitDef.GetSustainedDps();
		array<AIFloat3> cp; array<float> cv; array<int> cid; array<float> chp;
		for (uint i = 0; i < n; ++i) {
			if (eDef[i] is null || eDef[i].IsAbleToFly() || (eFlags[i] & 2) == 0) continue;
			bool taken = false;
			for (uint o = 0; o < ops.length() && !taken; ++o) if (ops[o].enemyId == eIds[i]) taken = true;
			if (taken) continue;
			cp.insertLast(ePos[i]); cv.insertLast(EnemyValue(i, H) + OursThreatened(i, all, fc.distance2D(ePos[i]) / fSpeed)); cid.insertLast(eIds[i]);
			chp.insertLast(eHp[i] * eDef[i].health);
		}
		for (uint i = 0; i < EcoPos::raidPos.length(); ++i) {
			if (AiIsInLOS(EcoPos::raidPos[i])) continue;  // in sight: the known enemies above cover it
			cp.insertLast(EcoPos::raidPos[i]); cv.insertLast(EcoPos::raidVal[i]); cid.insertLast(-1);
			chp.insertLast(Economist::mexT1 !is null ? Economist::mexT1.health : 0.f);  // what a raid spot holds
		}
		array<float> score(cp.length());
		array<float> dfc(cp.length());
		for (uint i = 0; i < cp.length(); ++i) {
			const float t = fc.distance2D(cp[i]) / fSpeed;
			// The defence is what fights there while we kill the target: enemies within reach of it for as long as the
			// fight lasts (its health over our dps; they answer once it starts). Counting everything that could reach the
			// spot during our whole march (60 s+) put BARb's whole army, commander included, on every lone raider: no op
			// was ever made, defend=0 while Favs and Flashes killed 13 producers (Eye of Horus 1v1, 2026-11-25).
			const float tFight = chp[i] / AiMax(1e-3f, freeDps);
			// the same test a running op must keep passing (what can reach the squad on its way, not only at the
			// target): launched on the target alone, 269 of 292 raids pulled back at once (Canis 2026-11-26)
			dfc[i] = AiMax(Cover(cp[i], tFight), Cover(fc, t));
			score[i] = cv[i] / AiMax(1.f, t);
		}
		while (freeUnits.length() > 0) {
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
				S += freeUnits[nk].circuitDef.threat;
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
				array<int> raidOps;
				for (uint o = 0; o < ops.length(); ++o) if (ops[o].enemyId < 0) raidOps.insertLast(int(o));
				// least valuable first
				for (uint a2 = 0; a2 < raidOps.length(); ++a2)
					for (uint b2 = a2 + 1; b2 < raidOps.length(); ++b2)
						if (ops[raidOps[b2]].value < ops[raidOps[a2]].value) { const int tmp = raidOps[a2]; raidOps[a2] = raidOps[b2]; raidOps[b2] = tmp; }
				float S2 = S, given = 0.f;
				array<int> take;
				for (uint q = 0; q < raidOps.length() && S2 <= need; ++q) {
					for (uint k = 0; k < ops[raidOps[q]].units.length(); ++k) S2 += ops[raidOps[q]].units[k].circuitDef.threat;
					given += ops[raidOps[q]].value;
					take.insertLast(raidOps[q]);
				}
				if (FightGain(cv[best], S2, dfc[best], metal) > FightGain(cv[best], S, dfc[best], metal) + given) {
					take.sortDesc();  // remove from the highest index down (earlier removals shift the later ones)
					for (int q = 0; q < int(take.length()); ++q) {
						for (uint k = 0; k < ops[take[q]].units.length(); ++k) { pick.insertLast(ops[take[q]].units[k]); metal += ops[take[q]].units[k].circuitDef.costM; }
						ops.removeAt(take[q]);
					}
					S = S2;
					AiLog("[ANV-CMD] recall " + take.length() + " raid ops to defend (" + int(cp[best].x) + "," + int(cp[best].z) + "): strength " + F1(S) + " > " + F1(need));
				}
			}
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
		for (uint k = 0; k < op.units.length(); ++k) {
			CCircuitUnit@ u = op.units[k];
			const AIFloat3 p = u.GetPos(ai.frame);
			const float reach = AiMax(1.f, u.circuitDef.GetMaxRange());
			int bi = -1, ni = -1;
			float bv = 0.f, nd = 1e9f;
			for (uint i = 0; i < n; ++i) {
				if (eDef[i] is null || eDef[i].IsAbleToFly()) continue;
				const float dd = ePos[i].distance2D(p);
				if (eDef[i].threat > 0.f && dd < nd) { nd = dd; ni = int(i); }
				if (dd > reach) continue;
				const float v = EnemyValue(i, H) / AiMax(1.f, eHp[i] * eDef[i].health);
				if (bi < 0 || v > bv) { bv = v; bi = int(i); }
			}
			// focus fire without stopping: set target (the unit keeps following its moves; plain moves still shoot
			// whatever is in reach). Owner: attack orders and attack-moves stand still and don't dodge.
			const int tgt = (bi >= 0) ? bi : ni;
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
	// free units wait at home (plain move: units shoot what is in reach while moving; no attack-move)
	for (uint i = 0; i < freeUnits.length(); ++i)
		if (freeUnits[i].GetPos(ai.frame).distance2D(basePos) > freeUnits[i].circuitDef.GetMaxRange()) Order(freeUnits[i], "home", 0, basePos, -1);
}
string Status() { return "ops=" + ops.length() + " created=" + created + " pulledBack=" + retreats; }
// a dead unit leaves its squad at once (a handle kept until the next update crashed the game when read: GetPos)
void OnDestroyed(CCircuitUnit@ unit)
{
	for (uint o = 0; o < ops.length(); ++o) {
		const int k = ops[o].units.findByRef(unit);
		if (k >= 0) ops[o].units.removeAt(k);
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
void Update()
{
	if (lastFrame != NEVER && ai.frame - lastFrame < MINUTE) return;
	lastFrame = ai.frame;
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
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
			+ ", lost " + Economist::producerLosses + ")");
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
uint minContact = 0, minNoReply = 0, minOutranged = 0, minIdleInRange = 0, minStillHit = 0, minFired = 0;
void Micro()
{
	const int since = (microFrame == NEVER) ? ai.frame : microFrame;
	microFrame = ai.frame;
	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
	const uint n = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	uint contact = 0, fired = 0, noReply = 0, outranged = 0, idleInRange = 0, stillHit = 0;
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
		bool inReach = false;
		for (uint k = 0; k < n && !inReach; ++k)
			if (ed[k] !is null && ep[k].distance2D(p) <= reach) inReach = true;
		if (!hit && !inReach) continue;
		++contact;
		// fired within its own reload time (a weapon that reloads in more than a second can't fire every second)
		const bool didFire = u.LastShotFrame() > AiMin(since, ai.frame - d.GetReloadTime());
		const AIFloat3 v = u.GetVel();
		const bool still = v.x * v.x + v.z * v.z <= 0.f;
		if (didFire) ++fired;
		if (hit && !didFire) ++noReply;
		if (hit && !inReach) ++outranged;
		if (inReach && !didFire) ++idleInRange;
		if (hit && still) ++stillHit;
	}
	microHp = hpNow;
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
	AiLog("[ANV-MICRO] f=" + ai.frame + " contact=" + contact + " fired=" + fired + " noReply=" + noReply
		+ " outranged=" + outranged + " idleInRange=" + idleInRange + " stillHit=" + stillHit + " squadSpread=" + spread);
}
}  // namespace Check

CCircuitUnit@ commander = null;
int commRedirects = 0;

/*
 * The commander is the win condition: it takes a job only when the job's value beats P(death) there x
 * everything we own (CommWorth, see Commander risk below); otherwise it takes the safest productive job.
 */
IUnitTask@ CommanderTask(CCircuitUnit@ comm, IUnitTask@ task)
{
	if (task is null || !HasBase() || task.GetType() != Task::Type::BUILDER || Brain::Intel::allFactories.length() == 0)
		return task;
	IBuilderTask@ bt = cast<IBuilderTask>(task);
	if (bt is null)
		return task;
	if (CommWorth(bt.GetBuildPos(), JobValue(bt)))
		return task;
	++commRedirects;
	AiLog("[ANV] CommRedirect: " + bt.buildDef.GetName() + " gain " + int(lastGain) + " < risk " + int(lastRisk) + " (danger " + F1(commDanger) + " cover " + F1(commCover) + ")");
	IUnitTask@ safe = CommSafeJob(comm.GetPos(ai.frame));
	return safe is null ? task : safe;
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
	const float dist = AiEnemyBasePos().distance2D(p);
	return dist / AiMax(1.f, sp) <= tHome ? hidden : 0.f;
}
float commDanger = 0.f, commCover = 0.f, commDps = 0.f;

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
		const float curV = (cur !is null && cur.buildDef !is null) ? Brain::Economist::MetalValue(cur.buildDef) * best.circuitDef.buildSpeed / bp : best.circuitDef.buildSpeed / bp * income * Brain::Economist::Horizon();
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
	commDanger = 0.f; commDps = 0.f;
	for (uint i = 0; i < n; ++i) {
		CCircuitDef@ d = ed[i];
		if (d is null || d.threat <= 0.f || (ef[i] & 4) != 0) continue;
		const float reach = AiMax(0.f, ep[i].distance2D(p) - d.GetMaxRange());
		if (!d.IsMobile()) { if (reach <= 0.f) { commDanger += d.threat; commDps += d.surfThrDmg; } continue; }
		if (MoveTime(d, reach) <= tHome) { commDanger += d.threat * eh[i]; commDps += d.surfThrDmg * eh[i]; }
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
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	for (uint i = 0; i < all.length(); ++i) {
		CCircuitUnit@ u = all[i];
		const CCircuitDef@ d = u.circuitDef;
		if (u is riskUnit || d.power <= 0.f || d.IsRoleAny(Unit::Role::BUILDER.mask)) continue;
		const float dist = u.GetPos(ai.frame).distance2D(p);
		if (d.IsMobile() ? (MoveTime(d, dist) <= tHome) : (dist <= d.GetMaxRange()))
			commCover += d.power;
	}
}
float RiskPDeath(const AIFloat3& in p, float tHome)
{
	CommForces(p, tHome);
	const float d2 = commDanger * commDanger, c2 = commCover * commCover;
	const float lose = d2 / AiMax(1e-3f, d2 + c2);  // the fight there goes against us
	// ...and it can't walk out: time to burn through its health vs time back to cover
	const float tKill = (riskHealth > 0.f ? riskHealth : riskUnit.circuitDef.health) / AiMax(1e-3f, commDps);
	return lose * tHome / AiMax(1e-3f, tHome + tKill);
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
		if (u is commander || !d.IsMobile() || !d.IsRoleAny(Unit::Role::BUILDER.mask) || d.buildSpeed <= 0.f) continue;
		const AIFloat3 c = u.GetPos(ai.frame);
		CCircuitUnit@ fac = FactoryReachedSoonest(c, d);
		if (fac is null) continue;
		const float tHome = MoveTime(d, fac.GetPos(ai.frame).distance2D(c));
		const float P = UnitPDeath(u, c, tHome);
		// on its safe job: back to work once the place it left is safe - not its own position, which is safe the moment
		// it arrives (rez bots fled and returned 618 times in one game, Canis 2026-11-26)
		if (u.task !is null && safeTasks.findByRef(u.task) >= 0) {
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
		const float own = Brain::Economist::MetalValue(d);
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
float EscapeTime(const AIFloat3& in p)
{
	CCircuitUnit@ h = NearestFactory(p);
	return h is null ? 0.f : MoveTime(commander.circuitDef, h.GetPos(ai.frame).distance2D(p));
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
void OnBuilderTaskRemoved(IUnitTask@ task) { MexPorc::OnTaskRemoved(task); Strategic::OnTaskRemoved(task); Opening::OnTaskRemoved(task); if (task is commFwdTask) @commFwdTask = null; if (task is commGuardTask) @commGuardTask = null; }
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

bool CommWorth(const AIFloat3& in p, float gain)
{
	lastV = GameValue();
	lastRisk = CommPDeath(p, EscapeTime(p)) * lastV;
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
void CommDefendUpdate()
{
	if (commander is null || !Opening::done || !HasBase()) return;
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef, ids;
	const uint n = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	AiGetEnemyIds(ids);
	const AIFloat3 c = commander.GetPos(ai.frame);
	const CCircuitDef@ cd = commander.circuitDef;
	// still on a fight: keep at it while the target lives, can still be caught and is on our side (a chase without
	// those took the commander away after Pawns, faster than it, with no base, no extractors and no units: owner,
	// 2026-11-25 "WHERE ARE YOU WALKING WITH THE COMMANDER ... YOU GO AWAY WITH THE COMMANDER TO HUNT PAWNS")
	if (commFightTask !is null && commander.task is commFightTask) {
		for (uint i = 0; i < n && i < ids.length(); ++i)
			if (ids[i] == commFightTarget) {
				if (ed[i] !is null && Assess::OnOurSide(ep[i]) && CatchTime(c, cd, ep[i], ed[i], ev[i].Length2D() * SECOND) < 1e8f) { commander.CmdAttackEnemy(commFightTarget); return; }
				break;
			}
		AiLog("[ANV] CommDefend: commander stops (target gone, uncatchable or off our side)");
		commFightTask.Abort(); @commFightTask = null; commFightTarget = -1;
		return;
	}
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
	int best = -1; float bestNet = 0.f;
	for (uint i = 0; i < n && i < ids.length(); ++i) {
		const CCircuitDef@ d = ed[i];
		if (d is null || !d.IsMobile() || d.IsAbleToFly() || d.surfThrDmg <= 0.f || (ef[i] & 2) == 0) continue;
		if (!Assess::OnOurSide(ep[i])) continue;
		const float t = CatchTime(c, cd, ep[i], d, ev[i].Length2D() * SECOND);
		if (t >= 1e8f) continue;  // faster than the commander and out of its reach: a chase it can't win
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
		if (ours <= theirs) continue;
		const float risk = CommPDeath(ep[i], EscapeTime(ep[i])) * V;
		const float net = stake - risk - (t + tFight) * commRate;  // its time is our best builder's time
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
	if (CommWorth(c, JobValue(cur)))
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
	if (Economist::IsProducer(unit.circuitDef)) ++Economist::producerLosses;
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
	Storage::Update();
	Storage::UpdateEnergy();
	CommDefendUpdate();
	CommGuardUpdate();
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
