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
const float EXPECTED_TURN = 90.f;  // mean of a uniform 0..180 deg turn (heading unknown), not a tuning knob
float MoveTime(const CCircuitDef@ d, float dist)
{
	const float v = AiMax(1.f, d.speed);
	const float tTurn = d.turnRate > 0.f ? EXPECTED_TURN / d.turnRate : 0.f;
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

AIFloat3 basePos = AIFloat3(-1.f, 0.f, -1.f);
bool HasBase() { return basePos.x >= 0.f; }

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

	{
		array<string> probe = {"armflash", "armstump", "armbull", "armpw", "armham", "armzeus", "corgator", "corak"};
		string s = "[ANV] Motion (turn deg/s, in place, accel, 500 elmos):";
		for (uint i = 0; i < probe.length(); ++i) {
			CCircuitDef@ d = ai.GetCircuitDef(probe[i]);
			if (d is null) continue;
			s += " " + probe[i] + "=" + int(d.turnRate) + "/" + (d.turnInPlace ? "y" : "n") + "/" + int(d.accel) + "/" + F1(MoveTime(d, 500.f)) + "s";
		}
		AiLog(s);
	}
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

/*
 * Broken-squad recall. The core keeps a raid going until its *leader* dies, and an attack until it
 * drops under the quota it was created with, so the last survivors keep walking into the enemy one
 * at a time. We track each squad's peak power and abort it once it's lost most of it: survivors go
 * back into the gather pipeline and come out again as part of a full squad.
 */
array<IFighterTask@> squads;
array<float> squadPeak;
array<int> squadStart;
int recalls = 0;

int tasksSeen = 0, fightersSeen = 0;
array<int> ftHist(13, 0);
string Hist() { string s; for (uint i = 0; i < ftHist.length(); ++i) s += "" + ftHist[i] + ","; return s; }

void OnTaskAdded(IUnitTask@ task)
{
	++tasksSeen;
	if (task.GetType() != Task::Type::FIGHTER)
		return;
	IFighterTask@ f = cast<IFighterTask>(task);
	if (f is null)
		return;
	++fightersSeen;
	const int ft = int(f.GetFightType()) & 0xFF;
	if (ft >= 0 && ft < 13) ftHist[ft]++;
	if (ft != Task::FightType::RAID && ft != Task::FightType::ATTACK)
		return;
	squads.insertLast(f);
	squadPeak.insertLast(0.f);
	squadStart.insertLast(ai.frame);
}

void OnTaskRemoved(IUnitTask@ task)
{
	Hold::OnTaskRemoved(task);
	IFighterTask@ f = cast<IFighterTask>(task);
	if (f is null)
		return;
	int idx = squads.findByRef(f);
	if (idx >= 0) {
		squads.removeAt(idx);
		squadPeak.removeAt(idx);
		squadStart.removeAt(idx);
	}
}

float SquadPower(IFighterTask@ task)
{
	const array<CCircuitUnit@>@ units = task.GetUnits();
	float p = 0.f;
	for (uint i = 0; i < units.length(); ++i)
		p += units[i].circuitDef.power;
	return p;
}

void CheckSquads()
{
	for (int i = int(squads.length()) - 1; i >= 0; --i) {
		IFighterTask@ task = squads[i];
		const float p = SquadPower(task);
		if (p > squadPeak[i])
			squadPeak[i] = p;
		if (squadPeak[i] <= 0.f)
			continue;
		// Keep a squad that is still bigger than what we'd send out fresh.
		const bool isRaid = task.GetFightType() == Task::FightType::RAID;
		const float fresh = isRaid ? aiMilitaryMgr.quota.raid.min : aiMilitaryMgr.quota.attack;
		// Recall once the squad has bled and is now weaker than what we'd send fresh, scaled by how well we trade.
		// decide: it has bled and what is left, at our trade rate, no longer beats what a fresh squad is sized against
		// it has bled, and what is left, at our trade rate, no longer beats what a fresh squad is sized against
		const bool recall = p < squadPeak[i] && p * Brain::Assess::trade < fresh;
		if (recall) {
			++recalls;
			AiLog("[ANV] Army: recalling broken " + (isRaid ? "raid" : "attack") + " squad power "
				+ F1(p) + "/" + F1(squadPeak[i]) + " (" + task.GetUnits().length() + " units)");
			squads.removeAt(i);
			squadPeak.removeAt(i);
			squadStart.removeAt(i);
			task.Abort();
		}
	}
}

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
int ordered = 0, orderFrame = -10 * MINUTE, countAtOrder = -1;

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
	if (countAtOrder >= 0 && storeDef.count <= countAtOrder && ai.frame - orderFrame < 3 * MINUTE) return;
	const float saved = AiMin(want, storeDef.storageM);
	if (saved <= Economist::MetalValue(storeDef)) return;
	aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::STORE, Task::Priority::NORMAL, storeDef, basePos, SQUARE_SIZE * 32, true, 3 * MINUTE));
	countAtOrder = storeDef.count; orderFrame = ai.frame; ++ordered;
	AiLog("[ANV] Storage: ordering " + storeDef.GetName() + " (reclaims held back: " + int(want) + " metal over free storage, it holds " + int(storeDef.storageM) + ")");
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
int ordered = 0, orderFrame = -10 * MINUTE;
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
	if (lab is null || rez is null || !lab.IsAvailable(ai.frame) || ai.frame - orderFrame < 5 * MINUTE) return;  // the order queued below lives 5 min: one at a time
	array<AIFloat3> wp; array<float> wm; array<bool> wr;
	const uint w = AiGetWrecks(wp, wm, wr);
	float pool = 0.f;
	for (uint i = 0; i < w; ++i) pool += wm[i];
	if (pool <= Economist::MetalValue(lab) + Economist::MetalValue(rez)) return;
	orderFrame = ai.frame;
	++ordered;
	aiBuilderMgr.Enqueue(TaskB::Factory(Task::Priority::HIGH, lab, basePos, lab, SQUARE_SIZE * 32, false, true, 5 * MINUTE));
	AiLog("[ANV] RezLab: ordering " + lab.GetName() + " (wreck metal " + int(pool) + " > lab + rez bot)");
}
}  // namespace RezLab

namespace EcoPos {
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
	behind = ours < theirs;
	// the core's constructor rule (decide): builds constructors while build power < income x ratio
	aiFactoryMgr.buildpowerRatio = behind ? 1e9f
		: aiBuilderMgr.GetBuildPower() / AiMax(1e-3f, aiEconomyMgr.metal.income);  // ahead: hold constructors where they are
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
dictionary guarded;  // mex id -> frame ordered
void Update()
{
	if (!HasBase()) return;
	CCircuitDef@ tur = Strategic::BestTurret();
	if (tur is null || !tur.IsAvailable(ai.frame)) return;
	const float cost = Economist::MetalValue(tur);
	const array<CCircuitUnit@>@ mx = Economist::mexes;
	CCircuitUnit@ best = null; float bestHeat = cost;
	for (uint i = 0; i < mx.length(); ++i) {
		if (guarded.exists("" + mx[i].id)) continue;
		const float h = Intel::heat[Intel::CellOf(mx[i].GetPos(ai.frame))];
		if (h > bestHeat) { bestHeat = h; @best = mx[i]; }
	}
	if (best is null) return;
	const AIFloat3 p = best.GetPos(ai.frame);
	if (!TurretSurvives(tur, p)) return;
	guarded.set("" + best.id, ai.frame);
	++orders;
	aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE, Task::Priority::HIGH, tur, p, SQUARE_SIZE * 8, true, 3 * MINUTE));
	AiLog("[ANV] MexPorc: " + tur.GetName() + " at raided extractor (lost " + int(bestHeat) + " metal around it > turret " + int(cost) + ")");
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
					if (da > 3.14159265f) da = 2.f * 3.14159265f - da;
					dir = AiMin(dir, da / 3.14159265f);
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
	aiMilitaryMgr.quota.scout = AiMax(1, int(worthy));
}

string Status() { return "scout: worthy=" + worthy + " top=" + int(topValue) + " quota=" + aiMilitaryMgr.quota.scout; }

}  // namespace Scout

/* ======================================================================== */
// ---- Hold: just-in-time defence of extractors (needs the C++ bridge) ----
// Each armed enemy is assigned to the extractor it is closing on soonest (its velocity says where it goes).
// An extractor with incoming threat T gets a hold task sized to T, filled by the units that can be there
// before the enemy, nearest first. If those units cannot reach T in time we do not commit: feeding units
// one by one into a lost fight costs more than the extractor. When nothing is coming any more, release.
namespace Hold {

class SHold { CCircuitUnit@ mex; IUnitTask@ task; float need; }
array<SHold@> holds;
uint opened = 0, skipped = 0;

float Power(const array<CCircuitUnit@>@ units)
{
	float p = 0.f;
	for (uint i = 0; i < units.length(); ++i) p += units[i].circuitDef.power;
	return p;
}

int Find(CCircuitUnit@ mex)
{
	for (uint i = 0; i < holds.length(); ++i) if (holds[i].mex is mex) return int(i);
	return -1;
}

void OnTaskRemoved(IUnitTask@ task)
{
	for (uint i = 0; i < holds.length(); ++i) if (holds[i].task is task) { holds.removeAt(i); return; }
}

void Update()
{
	// assets to defend: every constructor and structure of ours
	array<CCircuitUnit@> mexes;
	{
		const array<CCircuitUnit@>@ own = AiGetTeamUnits();
		for (uint k = 0; k < own.length(); ++k) {
			const CCircuitDef@ d = own[k].circuitDef;
			if (!d.IsMobile() || (d.IsRoleAny(Unit::Role::BUILDER.mask) && own[k] !is commander)) mexes.insertLast(own[k]);
		}
	}
	const uint M = mexes.length();
	if (M == 0) return;
	array<AIFloat3> mp(M);
	for (uint m = 0; m < M; ++m) mp[m] = mexes[m].GetPos(ai.frame);

	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
	const uint n = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	array<float> incoming(M, 0.f), eta(M, 1e9f);
	for (uint i = 0; i < n; ++i) {
		CCircuitDef@ d = ed[i];
		if (d is null || !d.IsMobile() || d.threat <= 0.f) continue;
		int best = -1; float bestEta = 1e9f;
		for (uint m = 0; m < M; ++m) {
			const float dist = ep[i].distance2D(mp[m]);
			float t;
			if (dist <= d.GetMaxRange()) t = 0.f;  // already shooting it
			else {
				const float closing = ((mp[m].x - ep[i].x) * ev[i].x + (mp[m].z - ep[i].z) * ev[i].z) / dist * 30.f;  // elmo/s
				if (closing <= 0.f) continue;
				t = (dist - d.GetMaxRange()) / closing;
			}
			if (t < bestEta) { bestEta = t; best = int(m); }
		}
		if (best < 0) continue;
		incoming[best] += d.threat;
		eta[best] = AiMin(eta[best], bestEta);
	}

	// release holds whose extractor is gone or no longer threatened
	for (int h = int(holds.length()) - 1; h >= 0; --h) {
		int m = -1;
		for (uint k = 0; k < M; ++k) if (mexes[k] is holds[h].mex) { m = int(k); break; }
		if (m < 0 || incoming[m] <= 0.f) {
			aiMilitaryMgr.AbortTask(holds[h].task);  // OnTaskRemoved drops it from the list
		}
	}

	// candidate responders: our armed ground/hover units on ordinary fighter tasks
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	array<CCircuitUnit@> free;
	for (uint i = 0; i < all.length(); ++i) {
		CCircuitUnit@ u = all[i];
		const CCircuitDef@ d = u.circuitDef;
		if (!d.IsMobile() || d.power <= 0.f || d.IsAbleToFly() || u is commander) continue;
		if (d.IsRoleAny(Unit::Role::BUILDER.mask | Unit::Role::SCOUT.mask)) continue;
		if (u.task is null || u.task.GetType() != Task::Type::FIGHTER) continue;
		bool held = false;
		for (uint h = 0; h < holds.length() && !held; ++h) held = holds[h].task is u.task;
		if (!held) free.insertLast(u);
	}

	for (uint m = 0; m < M; ++m) {
		if (incoming[m] <= 0.f) continue;
		const int h = Find(mexes[m]);
		float have = (h >= 0) ? Power(holds[h].task.GetUnits()) : 0.f;
		if (have >= incoming[m]) continue;
		// who can be there before the enemy, nearest first
		array<float> arr; array<uint> idx;
		// A raid already on the asset (eta 0) can't be beaten to it; what matters then is whether anything of ours is
		// still there when help arrives: the assets within the raiders' reach of this one after our travel time.
		float raidSpeed = 1.f;
		for (uint i = 0; i < n; ++i) if (ed[i] !is null && ed[i].IsMobile() && ep[i].distance2D(mp[m]) <= ed[i].GetMaxRange() + ed[i].speed) raidSpeed = AiMax(raidSpeed, ed[i].speed);
		for (uint i = 0; i < free.length(); ++i) {
			if (free[i] is null) continue;
			const float t = MoveTime(free[i].circuitDef, free[i].GetPos(ai.frame).distance2D(mp[m]));
			if (eta[m] <= 0.f) {
				float stake = 0.f;
				for (uint k = 0; k < M; ++k) if (mp[k].distance2D(mp[m]) <= raidSpeed * t + mexes[k].circuitDef.GetMaxRange()) stake += mexes[k].circuitDef.costM;
				if (stake <= 0.f) continue;
			} else if (t > eta[m]) continue;
			uint k = 0; while (k < arr.length() && arr[k] < t) ++k;
			arr.insertAt(k, t); idx.insertAt(k, i);
		}
		float add = 0.f; uint take = 0;
		while (take < idx.length() && have + add < incoming[m]) { add += free[idx[take]].circuitDef.power; ++take; }
		if (have + add < incoming[m]) { ++skipped; continue; }  // cannot win it in time: do not feed units in
		IUnitTask@ task;
		if (h >= 0) @task = holds[h].task;
		else {
			@task = aiMilitaryMgr.EnqueueDefendAt(mp[m], incoming[m]);
			SHold hd; @hd.mex = mexes[m]; @hd.task = task; hd.need = incoming[m];
			holds.insertLast(hd); ++opened;
		}
		for (uint k = 0; k < take; ++k) {
			aiMilitaryMgr.AssignTask(free[idx[k]], task);
			@free[idx[k]] = null;
		}
	}
}

string Status() { return "holds=" + holds.length() + " opened=" + opened + " skipped=" + skipped; }

}  // namespace Hold


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
int stallTicks = 0;

const int MAX_PENDING = 3;
const int RECLAIM_TIMEOUT = 90 * SECOND;

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
void MeasureBestBuildable()
{
	bestBuildablePerMetal = 0.f;
	const array<CCircuitUnit@>@ facs = Brain::Intel::allFactories;
	for (uint i = 0; i < facs.length(); ++i) {
		const array<string> opts = Facts::BuildOptions(facs[i].circuitDef.GetName());
		for (uint k = 0; k < opts.length(); ++k) {
			CCircuitDef@ d = ai.GetCircuitDef(opts[k]);
			if (d is null || !d.IsMobile() || d.costM <= 0.f || !d.IsAvailable(ai.frame)) continue;
			bestBuildablePerMetal = AiMax(bestBuildablePerMetal, d.power / d.costM);
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
	return d.power / d.costM < bestBuildablePerMetal;
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
		if (ai.frame - pendingFrame[i] > RECLAIM_TIMEOUT + 10 * SECOND) {
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
	aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::HIGH, u, RECLAIM_TIMEOUT));
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
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	CCircuitUnit@ best = null; float bestGain = 0.f, bestMake = 0.f;
	for (uint i = 0; i < all.length(); ++i) {
		CCircuitUnit@ u = all[i];
		const CCircuitDef@ d = u.circuitDef;
		if (d.IsMobile() || pending.findByRef(u) >= 0) continue;
		const float make = AiEnergyMake(ai.GetCircuitDef(d.id));
		if (make <= 0.f) continue;
		const float gain = d.costM - make * H / epm;
		if (gain > bestGain) { bestGain = gain; @best = u; bestMake = make; }
	}
	if (best is null) return;
	// no stall: after losing its output, energy must last longer than it takes to build a new plant
	const float net = e.income - bestMake - e.pull;
	if (net < 0.f && e.current / (-net) < Economy::LeadTime(Economy::cheapEnergy)) return;
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
	if (aiEconomyMgr.isEnergyStalling && bigMake < e.pull) {
		RestoreAll();
		return;
	}

	if (int(pending.length()) >= MAX_PENDING)
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

const float CELL = 512.f;
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
int lastScoutFrame = -10 * MINUTE;
int eyesOrdered = 0;

void Init()
{
	gw = AiMax(1, int(AiTerrainWidth() / CELL) + 1);
	gh = AiMax(1, int(AiTerrainHeight() / CELL) + 1);
	heat.resize(gw * gh);
	lastEyesFrame.resize(gw * gh);
	for (uint i = 0; i < heat.length(); ++i) {
		heat[i] = 0.f;
		lastEyesFrame[i] = -10 * MINUTE;
	}

	jammerDefs = Defs({"armjamt", "corjamt", "armveil", "corshroud", "armjam", "coreter", "armsjam", "corsjam",
		"armaser", "corspec", "armmlv", "cormlv", "legjam", "legajam", "legajamk", "legavjam",
		"leganavyradjamship", "legmlv"});
	eyesDefs = Defs({"armeyes", "coreyes", "legeyes"});
	const string side = ai.GetSideName();
	if (side == "cortex")       @eyesDef = Def("coreyes");
	else if (side == "legion")  @eyesDef = Def("legeyes");
	else                        @eyesDef = Def("armeyes");

	InitPhantomThreat();
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

void InitPhantomThreat()
{
	const float t1 = RefInfluence({"armham", "armwar", "corthud", "corstorm", "armstump", "corraid", "legkark", "legcen"});
	const float t2 = RefInfluence({"armfido", "armzeus", "corcan", "corsumo", "armbull", "correap", "legshot", "legaskirmtank"});
	AiLog("[ANV] Intel: ref influence T1=" + F1(t1) + " T2=" + F1(t2));
	for (uint i = 0; i < jammerDefs.length(); ++i) {
		CCircuitDef@ d = jammerDefs[i];
		if (d.defDmg > 0.f)
			continue;  // armed (e.g. commando): keep real threat
		const bool t2tier = d.costM >= 120.f;
		const float squad = d.IsMobile() ? 4.f : 6.f;
		const float k = squad * (t2tier ? t2 : t1);
		if (k <= 0.f)
			continue;
		d.SetThreatKernel(k);
		AiLog("[ANV] Intel: phantom threat " + d.GetName() + " cost=" + F1(d.costM) + " kernel=" + F1(k));
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
	for (uint i = 0; i < heat.length(); ++i)
		heat[i] *= 0.995f;  // half-life ~2.3 min at one update per second

	jammerCost = aiEnemyMgr.GetEnemyCost(RT::JAMMER);
	const bool wasAlert = jamAlert;
	jamAlert = jammerCost > 0.f;
	if (jamAlert != wasAlert)
		AiLog("[ANV] Intel: jammer alert " + (jamAlert ? "ON" : "OFF") + " (known jammer metal=" + F1(jammerCost) + ")");

	if (ai.frame < 3 * MINUTE || !HasBase())
		return;

	if (ai.frame % (5 * SECOND) < SECOND)
		OrderVision();

	// Real line of sight beats radar dots: a blip has no type, so no real threat, counter or target.
	// Keep eyes on the enemy when blind or jammed: planes on a timer; ground scouts as fallback.
	const bool blind = Brain::Director::blind;
	if ((jamAlert || blind) && ai.frame - lastScoutFrame > 90 * SECOND && Brain::Army::scouts.length() < 4) {
		array<CCircuitUnit@>@ facs = airFactories.length() > 0 ? airFactories : allFactories;
		if (facs.length() > 0) {
			CCircuitUnit@ fac = FactoryReachedSoonestIn(facs, basePos, null);
			CCircuitDef@ scout = aiFactoryMgr.GetRoleDef(fac.circuitDef, RT::SCOUT);
			if (scout !is null && scout.IsAvailable(ai.frame)) {
				aiFactoryMgr.Enqueue(TaskS::Recruit(Task::RecruitType::FIREPOWER, Task::Priority::HIGH,
					scout, fac.GetPos(ai.frame), 64.f));
				lastScoutFrame = ai.frame;
				AiLog("[ANV] Intel: scouting with " + scout.GetName() + (jamAlert ? " (jammers)" : " (blind)"));
			}
		}
	}
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
		if (heat[c] > bestHeat && !AiIsInLOS(CellCenter(int(c)))) {
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
	aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE, Task::Priority::HIGH, eyesDef, hot,
		SQUARE_SIZE * 16, true, 2 * MINUTE));
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
array<int> lastOrder(5, -10 * MINUTE);  // juno, amd, tac, silo, shield
int orders = 0;

const float SHIELD_RADIUS = 550.f;

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
	const float workers = float(AiMax(1, aiBuilderMgr.GetWorkerCount()));
	const float L = AMD_BUILDTIME / (CON_WORK * AiMax(1.f, workers * 0.5f)) + AMD_STOCKPILE_S;
	float feasible = 1.f;
	if (aiEnemyMgr.GetEnemyCost(RT::NUKE) <= 0.f) {
		if (ourT2Frame < 0)
			return 0.f;  // nobody near T2 yet (parity): a silo is out of reach
		const float since = float(ai.frame - ourT2Frame) / SECOND + L;
		// each enemy earns about what we do (parity prior; scouted BARbs out-earn us, so it's a floor)
		const float enemyMetal = float(AiMax(1, ai.GetEnemyTeamSize())) * aiEconomyMgr.metal.income * since;
		feasible = AiMin(1.f, enemyMetal / (siloDef.costM + SILO_MISSILE_M) - SILO_STOCKPILE_S / AiMax(1.f, since));
		if (feasible <= 0.f)
			return 0.f;
	}
	return feasible * InfraValue() / AiMax(1.f, Brain::Economist::MetalValue(amdDef));
}
const float AMD_BUILDTIME = 60000.f, AMD_STOCKPILE_S = 90.f, SILO_STOCKPILE_S = 180.f, SILO_MISSILE_M = 1000.f;
const float CON_WORK = 85.f;  // T1 constructor workertime (unit facts), the rate one builder adds

void OnFinished(CCircuitUnit@ u)
{
	const CCircuitDef@ d = u.circuitDef;
	if (InList(junoDefs, d))        junos.insertLast(u);
	else if (InList(amdDefs, d))    amds.insertLast(u);
	else if (InList(tacDefs, d))    tacs.insertLast(u);
	else if (InList(siloDefs, d))   silos.insertLast(u);
	else if (InList(shieldDefs, d)) shields.insertLast(u);
	if (!d.IsMobile() && d.costM >= 250.f && !InList(shieldDefs, d))
		infra.insertLast(u);
}

void OnDestroyed(CCircuitUnit@ u)
{
	RemoveUnit(junos, u); RemoveUnit(amds, u); RemoveUnit(tacs, u);
	RemoveUnit(silos, u); RemoveUnit(shields, u); RemoveUnit(infra, u);
}

// No cooldown clock: a kind is ready when no order of it is still outstanding (one more exists, or the build task
// we queued has expired at its own lifetime, ORDER_LIFE, set where it is enqueued).
const int ORDER_LIFE = 5 * MINUTE;
array<int> countAtOrder(8, -1);
bool Ready(int kind, CCircuitDef@ d)
{
	if (d is null || !d.IsAvailable(ai.frame)) return false;
	return countAtOrder[kind] < 0 || d.count > countAtOrder[kind] || ai.frame - lastOrder[kind] > ORDER_LIFE;
}

void Order(int kind, CCircuitDef@ d, const AIFloat3& in pos, Task::Priority pri, float shake)
{
	lastOrder[kind] = ai.frame;
	countAtOrder[kind] = d.count;
	++orders;
	aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::BIG_GUN, pri, d, pos, shake, true, ORDER_LIFE));
	AiLog("[ANV] Strategic: ordering " + d.GetName() + " at (" + int(pos.x) + "," + int(pos.z) + ")");
}

// Toward the map centre: tactical launchers have 2250-3650 range and must sit forward.
AIFloat3 ForwardPos(float dist)
{
	AIFloat3 c = AiTerrainCenter();
	AIFloat3 dir = c - basePos;
	dir.y = 0.f;
	const float len = dir.Length2D();
	if (len < 1.f)
		return basePos;
	return basePos + dir * (AiMin(dist, len * 0.5f) / len);
}

// Most valuable spot not yet under a shield: sum of infra cost within the shield radius.
bool BestShieldSpot(AIFloat3& out pos, float& out value)
{
	value = 0.f;
	for (uint i = 0; i < infra.length(); ++i) {
		const AIFloat3 p = infra[i].GetPos(ai.frame);
		bool covered = false;
		for (uint s = 0; s < shields.length() && !covered; ++s)
			covered = shields[s].GetPos(ai.frame).distance2D(p) < SHIELD_RADIUS * 0.8f;
		if (covered)
			continue;
		float v = 0.f;
		for (uint j = 0; j < infra.length(); ++j) {
			if (infra[j].GetPos(ai.frame).distance2D(p) < SHIELD_RADIUS * 0.85f)
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
	if (amds.length() < wantAmd && Ready(1, amdDef)) {
		Order(1, amdDef, basePos, enemyNuke ? Task::Priority::NOW : Task::Priority::HIGH, SQUARE_SIZE * 32);
		return;
	}
	// Juno: EMP missile that wipes radar, jammers and mines in its blast. Worth it when the enemy jammers it can wipe
	// are worth more than it (no game clock).
	if (jamAlert && junos.length() < 1 && Ready(0, junoDef)
		&& aiEnemyMgr.GetEnemyCost(RT::JAMMER) > Brain::Economist::MetalValue(junoDef)) {
		Order(0, junoDef, basePos, Task::Priority::HIGH, SQUARE_SIZE * 32);
		return;
	}
	// Everything below is an investment that doesn't fight today: only when our army covers what we need.
	if (Brain::Director::ratio < 1.f)
		return;
	// Shields over the most valuable uncovered infrastructure: one more while what it would cover is worth more than
	// the shield (no clock, no energy level, no count formula, no fixed value floor).
	if (Ready(4, shieldDef)) {
		AIFloat3 pos;
		float value;
		if (BestShieldSpot(pos, value) && value > Brain::Economist::MetalValue(shieldDef)) {
			Order(4, shieldDef, pos, Task::Priority::NORMAL, SQUARE_SIZE * 6);
			return;
		}
	}
	// Tactical / EMP launcher, forward of base: one more while the enemy's static metal exceeds what our launchers cost.
	const float enemyStatic = aiEnemyMgr.GetEnemyCost(RT::STATIC);
	if (tacDef !is null && Ready(2, tacDef) && enemyStatic > Brain::Economist::MetalValue(tacDef) * float(tacs.length() + 1)) {
		Order(2, tacDef, ForwardPos(900.f), Task::Priority::NORMAL, SQUARE_SIZE * 24);
		return;
	}
	// Nuke: only under our own anti-nuke umbrella, while the enemy's static metal exceeds the silo.
	if (amds.length() >= 1 && silos.length() < 1 && siloDef !is null && Ready(3, siloDef)
		&& enemyStatic > Brain::Economist::MetalValue(siloDef)) {
		Order(3, siloDef, basePos, Task::Priority::NORMAL, SQUARE_SIZE * 32);
		return;
	}
}

/*
 * Fortify: fight where the enemy has to come to us. The choke from the map analysis first (TerrainFortify);
 * otherwise the loss heatmap shows where fights happen and a turret covers the hottest cell (Fortify).
 */
CCircuitDef@ turT1, turT2, turT3, wallDef;
int lastFortify = 0, forts = 0;
// terrain defence bookkeeping: build the next turret only once the last one stands AND something has
// come at us since (event-driven, no timer flood: one order per real attack)
int terrainBuilt = 0;
float terrainHit = 0.f, hitAtLastOrder = -1.f;
CCircuitDef@ terrainDef = null;
float armyMetal = 0.f;               // our armed mobile units (not builders), metal
CCircuitDef@ mlvDef, mineDef;        // minelayer vehicle and its light land mine
int minelayers = 0, mlvOrderedAt = -10000;
void OnTerrainLoss(const AIFloat3& in pos, float costM)
{
	MapFacts::SMap@ m = Brain::Production::mapInfo;
	if (myStart < 0 || m is null)
		return;
	const AIFloat3 high(m.hx[myStart], 0.f, m.hz[myStart]);
	const AIFloat3 choke(m.cx[myStart], 0.f, m.cz[myStart]);
	if (pos.distance2D(high) < 900.f || pos.distance2D(choke) < 900.f)
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
			if (d < best && d < 0.25f * AiMax(m.straight, 1.f)) {  // must actually be our start
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
	if ((Brain::Director::ratio >= 1.f && !outnumbered) || ai.frame - lastFortify < 30 * SECOND)
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
	if (ai.frame - lastFortify >= 3 * MINUTE)
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
	for (int k = 0; k < n; ++k)
		aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE, Task::Priority::HIGH, tur, high, SQUARE_SIZE * (12 + 4 * k), true, 3 * MINUTE));
	if (wallDef !is null && wallDef.IsAvailable(ai.frame) && forts % 2 == 1) {
		AIFloat3 dir = choke - AIFloat3(m.sx[myStart], 0.f, m.sz[myStart]);
		const float len = AiMax(1.f, dir.Length2D());
		dir = dir / len;
		const AIFloat3 side(-dir.z, 0.f, dir.x);
		for (int k = -3; k <= 3; ++k)
			aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE, Task::Priority::NORMAL, wallDef, choke + side * (48.f * k), 0.f, true, 3 * MINUTE));
	}
	// mines in the choke mouth, on the enemy's side of the teeth: BARb walks its lanes and never sweeps
	if (minelayers > 0 && mineDef !is null && mineDef.IsAvailable(ai.frame)) {
		AIFloat3 dir = choke - AIFloat3(m.sx[myStart], 0.f, m.sz[myStart]);
		dir = dir / AiMax(1.f, dir.Length2D());
		const AIFloat3 side(-dir.z, 0.f, dir.x);
		for (int k = -2; k <= 2; ++k)
			aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE, Task::Priority::NORMAL, mineDef,
				choke + dir * (96.f + 48.f * (forts % 3)) + side * (64.f * k), 0.f, true, 3 * MINUTE));
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
	if (ai.frame - lastFortify < 3 * MINUTE) return;
	CCircuitDef@ tur = BestTurret();
	if (tur is null || !tur.IsAvailable(ai.frame) || !HasBase()) return;
	int best = -1;
	float bestHeat = Economist::MetalValue(tur);
	for (uint c = 0; c < Brain::Intel::heat.length(); ++c)
		if (Brain::Intel::heat[c] > bestHeat) { bestHeat = Brain::Intel::heat[c]; best = int(c); }
	if (best < 0) return;
	const AIFloat3 hot = Brain::Intel::CellCenter(best);
	AIFloat3 dir = hot - basePos;
	dir.y = 0.f;
	const float len = AiMax(1.f, dir.Length2D());
	const AIFloat3 tpos = basePos + dir / len * AiMax(0.f, len - tur.GetMaxRange());
	if (!TurretSurvives(tur, tpos)) return;
	lastFortify = ai.frame;
	++forts;
	aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE, Task::Priority::HIGH, tur, tpos, SQUARE_SIZE * 8, true, 3 * MINUTE));
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
int choices = 0, builders = 0, lastDump = 0;
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
const float WRECK_SHARE = 0.6f;  // a wreck holds ~60% of the unit's metal (BAR corpse defs)
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
		for (uint i = 0; i < w; ++i) pool += wm[i];
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
		|| ai.frame - Strategic::mlvOrderedAt < 2 * MINUTE || !Strategic::mlvDef.IsAvailable(ai.frame)
		|| Facts::BuildOptions(fac.circuitDef.GetName()).find(Strategic::mlvDef.GetName()) < 0)
		return null;
	Strategic::mlvOrderedAt = ai.frame;
	AiLog("[ANV] Terrain: recruiting a minelayer");
	return aiFactoryMgr.Enqueue(TaskS::Recruit(Task::RecruitType::BUILDPOWER, Task::Priority::HIGH, Strategic::mlvDef,
		fac.GetPos(ai.frame), 64.f));
}


/*
 * Extractor upgrades (1v2 curve: we match each bot until minute 15, then lose outer extractors and stall at
 * ~55 m/s while each bot compounds to 150 on mohos). If we can't hold as many spots as two enemies, the
 * spots we can hold must give 4x. Upgrades are queued on T2 constructors: with U safe T1 extractors and C
 * constructors, the k-th upgrade waits ~k*tau/C, so one more constructor saves ~extra*tau*U^2/(2C(C+1))
 * of metal (extra = income an upgrade adds, tau = one upgrade's build time). Build it while that beats its cost.
 */
array<string> T2_CONS = {"armack", "corack", "legack", "armacv", "coracv", "legacv", "armacsub", "coracsub", "legacsub"};
int mohoCons = 0;
string mohoWhy = "";
IUnitTask@ MohoConTask(CCircuitUnit@ fac)
{
	CCircuitDef@ t2 = Brain::Economist::mexT2;
	if (t2 is null || !t2.IsAvailable(ai.frame)) return null;
	const array<string>@ opts = Facts::BuildOptions(fac.circuitDef.GetName());
	CCircuitDef@ con = null;
	for (uint i = 0; i < opts.length() && con is null; ++i)
		if (T2_CONS.find(opts[i]) >= 0) { CCircuitDef@ d = ai.GetCircuitDef(opts[i]); if (d !is null && d.IsAvailable(ai.frame)) @con = d; }
	if (con is null) return null;
	// safe T1 extractors left to upgrade
	uint U = 0;
	const array<CCircuitUnit@>@ mx = Brain::Economist::mexes;
	for (uint m = 0; m < mx.length(); ++m)
		if (mx[m].circuitDef is Brain::Economist::mexT1 && aiThreat.GetThreatAt(con, mx[m].GetPos(ai.frame)) <= 0.f) ++U;
	if (U == 0) { mohoWhy = "nothing safe to upgrade"; return null; }
	uint C = 0;
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	for (uint i = 0; i < all.length(); ++i) if (T2_CONS.find(all[i].circuitDef.GetName()) >= 0) ++C;
	const float perMex = aiEconomyMgr.metal.income / float(AiMax(1, int(mx.length())));
	const float extra = perMex * (Brain::Economist::MEX_T2_EXTRACT / Brain::Economist::MEX_T1_EXTRACT - 1.f)
		- (Brain::Economist::MEX_T2_UPKEEP_E - Brain::Economist::MEX_T1_UPKEEP_E) / AiMax(1e-3f, Brain::Economist::energyPerMetal);
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
	return aiFactoryMgr.Enqueue(TaskS::Recruit(Task::RecruitType::BUILDPOWER, Task::Priority::HIGH, con, fac.GetPos(ai.frame), 64.f));
}

IUnitTask@ MakeTask(CCircuitUnit@ fac)
{
	if (!fac.circuitDef.IsMobile()) {
		CCircuitDef@ rez = RezToBuild(fac.circuitDef);
		if (rez !is null) {
			++rezOrders;
			AiLog("[ANV] Rez: +" + rez.GetName() + " fleet=" + rezBots.length());
			return aiFactoryMgr.Enqueue(TaskS::Recruit(Task::RecruitType::BUILDPOWER, Task::Priority::HIGH, rez, fac.GetPos(ai.frame), 64.f));
		}
	}
	IUnitTask@ ml = MineLayerTask(fac);
	if (ml !is null)
		return ml;
	IUnitTask@ mc = MohoConTask(fac);
	if (mc !is null)
		return mc;
	if (aiEconomyMgr.isEnergyStalling)
		return null;  // energy stall: the core's first answer is energy; don't queue power-hungry units
	// (no opener window: production decides from the first unit; no fixed opener lists are queued)
	const CCircuitDef@ fdef = fac.circuitDef;
	if (fdef.IsMobile())
		return null;
	// Constructors are part of every factory's mix in the core's config (unit list index 0, ~25-35% of
	// T1/T2 weights). Hand that share of decisions back to the core so its constructor logic keeps the
	// economy growing; we choose only the army picks. (Debt: replace with a measured marginal value of a
	// constructor: income it adds now vs its cost and the horizon.)
	// constructor share as a quota, not a dice roll: a constructor whenever builders so far are below their share
	// A constructor while income goes unspent (we can't spend what we earn); otherwise the metal is worth more as army.
	if (aiEconomyMgr.metal.pull < aiEconomyMgr.metal.income && EcoPos::behind) {
		++builders;
		return null;
	}
	CCircuitDef@ rez = RezToBuild(fdef);
	if (rez !is null) {
		++rezOrders;
		last = rez.GetName();
		return aiFactoryMgr.Enqueue(TaskS::Recruit(Task::RecruitType::BUILDPOWER, Task::Priority::HIGH, rez,
			fac.GetPos(ai.frame), 64.f));
	}

	// Scouted enemy mix -> how much each damage domain matters.
	const float air = aiEnemyMgr.GetEnemyCost(RT::AIR);
	const float sub = aiEnemyMgr.GetEnemyCost(RT::SUB);
	const float stat = aiEnemyMgr.GetEnemyThreat(RT::STATIC);
	const float surf = AiMax(300.f, aiEnemyMgr.GetEnemyCost(RT::RAIDER) + aiEnemyMgr.GetEnemyCost(RT::ASSAULT)
		+ aiEnemyMgr.GetEnemyCost(RT::SKIRM) + aiEnemyMgr.GetEnemyCost(RT::RIOT) + aiEnemyMgr.GetEnemyCost(RT::HEAVY)
		+ aiEnemyMgr.GetEnemyCost(RT::ARTY) + aiEnemyMgr.GetEnemyCost(RT::STATIC) * 0.5f);
	const float total = air + sub + surf;
	const float wAir = air / total, wSub = sub / total, wSurf = surf / total;
	const float wStatic = AiMin(1.f, stat / AiMax(1.f, aiEnemyMgr.mobileThreat + stat));
	const float wHeavy = AiMin(1.f, (aiEnemyMgr.GetEnemyCost(RT::HEAVY) + aiEnemyMgr.GetEnemyCost(RT::ARTY)) / surf);

	MeasureArmy(wAir, wSurf, wSub);
	MeasureEnemyAA();
	wArty = AiMin(1.f, aiEnemyMgr.GetEnemyCost(RT::ARTY) / surf);
	wStaticCost = AiMin(1.f, aiEnemyMgr.GetEnemyCost(RT::STATIC) / (surf + aiEnemyMgr.GetEnemyCost(RT::STATIC)));
	array<CCircuitDef@> cands;
	array<float> scores;
	// Every unit this factory can build (facts: build options), not one per role.
	const array<string>@ opts = Facts::BuildOptions(fdef.GetName());
	for (uint i = 0; i < opts.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(opts[i]);
		if (d is null || !d.IsMobile() || d.IsRoleAny(Unit::Role::BUILDER.mask) || InList(rezDefs, d) || cands.findByRef(d) >= 0)
			continue;
		const float s = Score(d, wAir, wSurf, wSub, wStatic, wHeavy);
		if (s > 0.f) {
			cands.insertLast(d);
			scores.insertLast(s);
		}
	}
	// factories without facts fall back to one candidate per role
	for (uint i = 0; opts.length() == 0 && i < roles.length(); ++i) {
		CCircuitDef@ d = aiFactoryMgr.GetRoleDef(fdef, roles[i]);
		if (d is null || !d.IsMobile() || cands.findByRef(d) >= 0)
			continue;
		const float s = Score(d, wAir, wSurf, wSub, wStatic, wHeavy);
		if (s > 0.f) {
			cands.insertLast(d);
			scores.insertLast(s);
		}
	}	if (cands.length() == 0)
		return null;
	if (ai.frame - lastDump > 3 * MINUTE) {  // audit trail: what the chooser weighed
		lastDump = ai.frame;
		string s = "[ANV] Production @" + fdef.GetName() + " army(D=" + int(armyD) + " H=" + int(armyH) + " rng=" + int(armyRange) + " los=" + int(armyLos) + "):";
		for (uint i = 0; i < cands.length(); ++i)
			s += " " + cands[i].GetName() + "=" + formatFloat(scores[i], "", 0, 3);
		AiLog(s);
	}
	// Largest deficit, not dice: each candidate's target share of what we build is its share of the scores; pick the
	// one furthest below its target in metal built so far.
	float sumS = 0.f, sumB = 0.f;
	for (uint i = 0; i < cands.length(); ++i) { sumS += scores[i]; sumB += float(built[cands[i].id]) * cands[i].costM; }
	int pick = -1; float bestGap = -1e30f;
	for (uint i = 0; i < cands.length(); ++i) {
		const float want = scores[i] / AiMax(1e-6f, sumS);
		const float have = sumB > 0.f ? float(built[cands[i].id]) * cands[i].costM / sumB : 0.f;
		if (want - have > bestGap) { bestGap = want - have; pick = int(i); }
	}
	if (pick < 0)
		return null;
	CCircuitDef@ d = cands[pick];
	++built[d.id];
	++choices;
	last = d.GetName();
	return aiFactoryMgr.Enqueue(TaskS::Recruit(Task::RecruitType::FIREPOWER, Task::Priority::NORMAL, d,
		fac.GetPos(ai.frame), 64.f));
}

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
// Game facts the script API doesn't expose (from unitdefs: extractsmetal / energyupkeep). Not tunables.
const float MEX_T1_EXTRACT = 1.f, MEX_T2_EXTRACT = 4.f, MEX_T1_UPKEEP_E = 3.f, MEX_T2_UPKEEP_E = 20.f;
float lastEnemySeen = 0.f;    // for when we're blind

void Init()
{
	mexDefs = Defs({"armmex", "cormex", "legmex", "armamex", "armmoho", "cormoho", "legmoho", "cormexp", "armuwmex",
		"coruwmex", "armuwmme", "coruwmme"});
	@mexT1 = Brain::Strategic::Side("armmex", "cormex", "legmex");
	@mexT2 = Brain::Strategic::Side("armmoho", "cormoho", "legmoho");
	@makerDef = Brain::Strategic::Side("armmakr", "cormakr", "legeconv");
	if (makerDef !is null) {
		const float mm = aiEconomyMgr.GetMetalMake(makerDef);
		const float em = aiEconomyMgr.GetEnergyMake(makerDef);
		if (mm > 0.f && em < 0.f)
			energyPerMetal = -em / mm;
	}
	if (energyPerMetal <= 0.f)
		energyPerMetal = 70.f;  // game fact for T1 makers when the defs don't expose it
	AiLog("[ANV] Economist: converter rate " + F1(energyPerMetal) + " E per M");
}

void OnFinished(CCircuitUnit@ u) { if (InList(mexDefs, u.circuitDef)) mexes.insertLast(u); }
void OnDestroyed(CCircuitUnit@ u) { RemoveUnit(mexes, u); }

float MetalValue(const CCircuitDef@ d) { return d.costM + d.costE / energyPerMetal; }

// Planning horizon (s): with no other information the expected remaining game is about the time
// already played (Lindy), scaled by how safe we are: 2P/(P+T) is 1 at parity, ->0 when overwhelmed.
float Horizon()
{
	const float P = Brain::Director::OurPower();
	const float T = EnemyThreat();
	// plan as far ahead as the game has run, scaled by our share of the strength (x2: 1 at parity); no 60 s floor
	const float elapsed = AiMax(float(ai.frame) / SECOND, 1.f);
	return elapsed * 2.f * P / AiMax(1.f, P + T);
}

// Enemy mobile threat; when we see nothing, assume they grew at least as fast as we did.
float EnemyThreat()
{
	const float seen = aiEnemyMgr.mobileThreat;
	if (seen > 1.f)
		lastEnemySeen = seen;
	return Brain::Director::blind ? AiMax(lastEnemySeen, Brain::Director::OurPower()) : seen;
}

// Payback of upgrading every extractor we own: (lab + mohos) / (extra metal - upkeep priced in metal)
float MohoPayback(const CCircuitDef@ lab)
{
	if (mexT1 is null || mexT2 is null || mexes.length() == 0)
		return 1e9f;
	const float n = float(mexes.length());
	const float perMex = aiEconomyMgr.metal.income / n;  // upper bound: includes reclaim/makers
	const float extraM = perMex * (MEX_T2_EXTRACT / MEX_T1_EXTRACT - 1.f);
	const float upkeepM = (MEX_T2_UPKEEP_E - MEX_T1_UPKEEP_E) / energyPerMetal;
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

// Tier from unit facts (the old Factory::userData attrs were never set, so every lab looked like T1):
// a lab that builds a T2 constructor is T2; the T3 gantries are known by name.
int Tier(const CCircuitDef@ d)
{
	if (d is null) return 0;
	const string n = d.GetName();
	if (n == "armshltx" || n == "corgant" || n == "leggant" || n == "armshltxuw" || n == "corgantuw") return 3;
	const array<string>@ opts = Facts::BuildOptions(n);
	for (uint i = 0; i < opts.length(); ++i)
		if (Brain::Production::T2_CONS.find(opts[i]) >= 0) return 2;
	return 1;
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
		ok = payback < H || forced;
		why = "payback " + int(payback) + "s vs horizon " + int(H) + "s" + (forced ? ", enemy teched" : "");
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
float lostNearTotal = 0.f;  // never decays: has anything come at us since X?
float lostFarTotal = 0.f, killedTotal = 0.f;  // never decay: wrecks stay on the map
float enemyPrev = -1.f;
array<float> incomeHist;  // one sample per minute
float growth = 0.f;
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
	if (enemyStatics.length() == 0) return dU < basePos.distance2D(aiEnemyMgr.GetEnemyPos());
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
	dictionary now;
	for (uint i = 0; i < n && i < ids.length(); ++i) {
		SSeen e; e.pos = ep[i]; e.cost = ec[i];
		now.set(formatInt(ids[i]), @e);
	}
	array<string>@ keys = seen.getKeys();
	for (uint k = 0; k < keys.length(); ++k) {
		if (now.exists(keys[k])) continue;
		SSeen@ e = cast<SSeen>(seen[keys[k]]);
		if (e is null) continue;
		if (OnOurSide(e.pos)) killedHome += e.cost; else killedAway += e.cost;
	}
	seen = now;
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
	if (d.IsMobile())
		frontDist = 0.9f * frontDist + 0.1f * dist;
}

void Update()  // every second
{
	// Memory on the planning horizon itself (no hand-picked half-life): per second, evidence decays by e^(-1/H).
	const float H = AiMax(1.f, Brain::Economist::Horizon());
	const float decay = pow(2.71828183f, -1.f / H);  // e^(-1/H); the script math has pow, not exp
	lostNear *= decay;
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
	const float stake = AiMax(1.f, Brain::Strategic::armyMetal);
	trade = (killed + stake) / (lost + stake);
	// Pushed back = home losses
	// over that window exceed what our income replaces in it; pushing = our losses happen mostly away from home.
	const float window = H;  // the evidence window is the horizon (see decay above)
	pushedBack = lostNear > aiEconomyMgr.metal.income * window;
	pushing = lostFar > lostNear && lostFar > aiEconomyMgr.metal.income * window;

	if (ai.frame % MINUTE < SECOND) {
		incomeHist.insertLast(aiEconomyMgr.metal.income);
		const uint n = incomeHist.length();
		if (n >= 4)
			growth = (incomeHist[n - 1] - incomeHist[n - 4]) / AiMax(1.f, incomeHist[n - 4]);
	}
}

string Status()
{
	return (pushedBack ? "PUSHED-BACK" : (pushing ? "PUSHING" : "holding")) + " trade=" + F1(trade)
		+ " kill(h/a)=" + int(killedHome) + "/" + int(killedAway)
		+ " lost(n/f)=" + int(lostNear) + "/" + int(lostFar) + " front=" + int(frontDist) + " growth3m=" + int(growth * 100.f) + "%";
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
		if (!d.IsMobile() || d.power <= 0.f || d.surfThrDmg <= 0.f || all[i] is commander) continue;
		if (d.IsRoleAny(Unit::Role::BUILDER.mask)) continue;
		allPower += d.power;
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
	blind = aiEnemyMgr.mobileThreat <= 1.f && enemyStatic <= 0.f;

	// What we must be able to beat: the known (or, when blind, assumed) enemy army plus the army we
	// guess is hidden under seen jammers, divided by how efficiently we are actually trading.
	const float theirs = Brain::Economist::EnemyThreat() + aiEnemyMgr.GetEnemyThreat(RT::JAMMER);
	needPower = theirs / AiMax(1e-3f, Brain::Assess::trade);  // numeric guard only
	ratio = ours / AiMax(1.f, needPower);
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
	if (IsArmy(unit.circuitDef))
		Strategic::armyMetal += unit.circuitDef.costM;
	if (Strategic::mlvDef !is null && unit.circuitDef is Strategic::mlvDef)
		++Strategic::minelayers;
	Economist::OnFinished(unit);
	Production::OnFinished(unit);
}

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
	Director::MeasuredPower();
	const float sp = seenN > 0 ? seenSpeed / float(seenN) : AiMax(1.f, Director::allSpeed);
	const float dist = aiEnemyMgr.GetEnemyPos().distance2D(p);
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
		const float curV = (cur !is null && cur.buildDef !is null) ? Brain::Economist::MetalValue(cur.buildDef) * best.circuitDef.buildSpeed / bp : best.circuitDef.buildSpeed / bp * income * 20.f;
		if (metal - walk - risk <= curV) continue;
		// a rez bot revives what can be revived (at least the wreck's metal back as a working unit) unless energy would stall
		const bool canRez = Brain::Production::rezDefs.findByRef(best.circuitDef) >= 0 && wr[i] && !aiEconomyMgr.isEnergyStalling;
		IUnitTask@ t = canRez ? aiBuilderMgr.Enqueue(TaskB::Resurrect(Task::Priority::HIGH, wp[i], metal, 2 * MINUTE, R))
			: aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::HIGH, wp[i], metal, 2 * MINUTE, R));  // (pos, cost, timeout, radius)
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
void BuilderSafeUpdate()
{
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	const float income = aiEconomyMgr.metal.income;
	const float bp = AiMax(1.f, aiBuilderMgr.GetBuildPower());
	for (uint i = 0; i < all.length(); ++i) {
		CCircuitUnit@ u = all[i];
		const CCircuitDef@ d = u.circuitDef;
		if (u is commander || !d.IsMobile() || !d.IsRoleAny(Unit::Role::BUILDER.mask) || d.buildSpeed <= 0.f) continue;
		if (u.task !is null && safeTasks.findByRef(u.task) >= 0) continue;  // already on its safe job
		const AIFloat3 c = u.GetPos(ai.frame);
		CCircuitUnit@ fac = FactoryReachedSoonest(c, d);
		if (fac is null) continue;
		const float tHome = MoveTime(d, fac.GetPos(ai.frame).distance2D(c));
		const float P = UnitPDeath(u, c, tHome);
		IBuilderTask@ bt = cast<IBuilderTask>(u.task);
		const float jobV = (bt !is null && bt.buildDef !is null) ? Brain::Economist::MetalValue(bt.buildDef) : 0.f;
		const float own = Brain::Economist::MetalValue(d);
		// the job is at risk too (owner: kept upgrading a mex with 4 pawns on it): if the structure dies before it is
		// finished, the metal sunk into it is lost (bounded by its full value; progress isn't visible to the script)
		float Pj = 0.f;
		if (bt !is null && bt.buildDef !is null) {
			const float tDone = bt.buildDef.buildTime / AiMax(1.f, d.buildSpeed);
			Pj = JobPDeath(u, bt.buildDef, bt.GetBuildPos(), tDone);
		}
		const float stay = (1.f - Pj) * jobV - Pj * jobV - P * own;
		const float safe = d.buildSpeed / bp * income * 20.f;  // its share of our spending over the job span (Guard timeout)
		if (stay >= safe) continue;
		IUnitTask@ g = aiBuilderMgr.Enqueue(TaskB::Guard(Task::Priority::HIGH, fac, true, 20 * SECOND));
		if (g is null) continue;
		safeTasks.insertLast(g);
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
	if (bt !is null && bt.buildDef !is null) return Brain::Economist::MetalValue(bt.buildDef) * share;
	return share * aiEconomyMgr.metal.income * 20.f;  // 20 s: the span of the jobs we hand out (Guard/Reclaim timeouts)
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
		const float sc = (fac ? assist : 0.f) - CommPDeath(q, EscapeTime(q)) * V - q.distance2D(from) / AiMax(1.f, commander.circuitDef.speed) * assist / 20.f;  // walking costs its work
		if (sc > best) { best = sc; @bestU = g; bestP = q; bestKind = fac ? 0 : 2; }
	}
	array<AIFloat3> wp; array<float> wm; array<bool> wr;
	const uint w = AiGetWrecks(wp, wm, wr);
	const float R = 300.f;  // reclaim job radius handed to the core
	for (uint i = 0; i < w; ++i) {
		float metal = 0.f;
		for (uint j = 0; j < w; ++j) if (wp[j].distance2D(wp[i]) < R) metal += wm[j];
		const float sc = metal - CommPDeath(wp[i], EscapeTime(wp[i])) * V - wp[i].distance2D(from) / AiMax(1.f, commander.circuitDef.speed) * assist / 20.f;
		if (sc > best) { best = sc; @bestU = null; bestP = wp[i]; bestKind = 1; }
	}
	if (bestKind < 0) return null;
	if (bestKind == 0) return aiBuilderMgr.Enqueue(TaskB::Guard(Task::Priority::HIGH, bestU, true, 20 * SECOND));
	if (bestKind == 1) ++commReclaims;
	return aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::HIGH, bestP, 0.f, 20 * SECOND, R));  // (pos, cost, timeout, radius)
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
void OnBuilderTaskRemoved(IUnitTask@ task) { if (task is commFwdTask) @commFwdTask = null; if (task is commGuardTask) @commGuardTask = null; }
IUnitTask@ CommForward(const AIFloat3& in from, float curScore)
{
	if (Brain::Economist::mexT1 is null) return null;
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
	const AIFloat3 ec0 = aiEnemyMgr.GetEnemyPos();
	const float V = GameValue();
	const float rate = JobValue(null) / 20.f;  // metal/s the commander's build power carries
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
	@commFwdTask = aiBuilderMgr.Enqueue(TaskB::Spot(Task::BuildType::MEX, Task::Priority::HIGH, Brain::Economist::mexT1, sp[best], best, true, 2 * MINUTE));
	return commFwdTask;
}

bool CommWorth(const AIFloat3& in p, float gain)
{
	lastV = GameValue();
	lastRisk = CommPDeath(p, EscapeTime(p)) * lastV;
	lastGain = gain;
	return gain > lastRisk;
}

void CommGuardUpdate()
{
	if (commander is null || Brain::Intel::allFactories.length() == 0) return;
	if (commGuardTask !is null && commander.task is commGuardTask) return;
	const AIFloat3 c = commander.GetPos(ai.frame);
	IBuilderTask@ cur = cast<IBuilderTask>(commander.task);
	if (CommWorth(c, JobValue(cur))) {
		IUnitTask@ fwd = CommForward(c, lastGain - lastRisk);
		if (fwd !is null) { aiBuilderMgr.AssignTask(commander, fwd); return; }
		// worth staying; but an assist or nothing is the commander's weakest use: is a wreck field better?
		if (cur is null || cur.buildDef is null) {
			IUnitTask@ better = CommBestJob(c, lastGain - lastRisk);
			if (better !is null) { @commGuardTask = better; aiBuilderMgr.AssignTask(commander, better); }
		}
		return;
	}
	@commGuardTask = CommSafeJob(c);
	if (commGuardTask is null) return;
	aiBuilderMgr.AssignTask(commander, commGuardTask);
	++commGuards;
	AiLog("[ANV] CommRisk: leaving job, risk " + int(lastRisk) + " > gain " + int(lastGain) + " (danger " + F1(commDanger) + " cover " + F1(commCover) + " dps " + F1(commDps) + " V " + int(lastV) + ")");
}

void OnUnitDestroyed(CCircuitUnit@ unit)
{
	if (unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask)) {
		const AIFloat3 p = unit.GetPos(ai.frame);
		AiLog("[ANV] COMMANDER LOST at (" + int(p.x) + "," + int(p.z) + ") dist-from-base=" + int(HasBase() ? basePos.distance2D(p) : -1.f)
			+ " task=" + (unit.task is null ? -1 : int(unit.task.GetType())) + " t=" + Minute() + "m");
		@commander = null;
	}
	if (Strategic::mlvDef !is null && unit.circuitDef is Strategic::mlvDef)
		Strategic::minelayers = AiMax(0, Strategic::minelayers - 1);
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
	aiSwitchHighGroundArty = true;
	aiSwitchHeightSquads = true;
	aiSwitchScoutMap = true;
	aiSwitchEngageSeen = true;
	aiSwitchDecide = true;
	aiSwitchFocusFire = true;
	aiSwitchStrafe = true;
	Intel::Update();
	Assess::Update();
	Director::Update();
	// no config floors (quota.attack 60, raid min): an attack launches with the power needed to beat what we know of
	// the enemy at our trade rate; a raid with what beats the raiders that will answer it
	aiMilitaryMgr.quota.attack = Director::needPower;
	aiMilitaryMgr.quota.raid.min = aiEnemyMgr.GetEnemyThreat(RT::RAIDER) / AiMax(1e-3f, Assess::trade);
	aiMilitaryMgr.quota.raid.avg = AiMax(aiMilitaryMgr.quota.raid.avg, aiMilitaryMgr.quota.raid.min);
	Army::CheckSquads();
	if (ai.frame % (2 * SECOND) < SECOND)
		Recycler::Update();
	if (ai.frame % (10 * SECOND) < SECOND)
		Strategic::Update(Intel::jamAlert);
	if (ai.frame % (3 * SECOND) < SECOND)
		Hold::Update();
	if (ai.frame % (3 * SECOND) < SECOND)
		Scout::Update();
	if (ai.frame % (2 * SECOND) < SECOND)
		EcoPos::Update();
	if (ai.frame % (10 * SECOND) < SECOND)
		RezLab::Update();
	if (ai.frame % (5 * SECOND) < SECOND)
		MexPorc::Update();
	if (ai.frame % (5 * SECOND) < SECOND)
		Storage::Update();
	if (ai.frame % (2 * SECOND) < SECOND)
		CommGuardUpdate();
	if (ai.frame % (2 * SECOND) < SECOND)
		BuilderSafeUpdate();
	if (ai.frame % (5 * SECOND) < SECOND)
		ReclaimUpdate();
	if (ai.frame % (5 * SECOND) < SECOND)
		Recycler::EcoReclaimUpdate();
	if (ai.frame % (5 * SECOND) < SECOND)
		Recycler::NanoUpdate();

	if (ai.frame % MINUTE < SECOND) {
		if (commander !is null) {
			const AIFloat3 cp = commander.GetPos(ai.frame);
			AiLog("[ANV] commander at (" + int(cp.x) + "," + int(cp.z) + ") dist-from-base=" + int(HasBase() ? basePos.distance2D(cp) : -1.f)
				+ " task=" + (commander.task is null ? -1 : int(commander.task.GetType())) + " redirects=" + commRedirects + " guards=" + commGuards + " reclaimOrders=" + reclaimOrders + " builderEvacs=" + builderEvacs + " retreats=" + commRetreats + " frontReclaims=" + commReclaims + " fwdClaims=" + commFwd + " fwdFailed=" + fwdFailed + " fwd(calls/busy/none)=" + fwdCalls + "/" + fwdBusy + "/" + fwdNone + " fwdBest=" + int(fwdBestSeen) + " vs cur " + int(fwdCurSeen));
		}
		AiLog("[ANV] " + Scout::Status());
		AiLog("[ANV] eco t=" + Minute() + "m workers=" + aiBuilderMgr.GetWorkerCount() + " mex=" + Economist::mexes.length()
			+ " M inc=" + F1(aiEconomyMgr.metal.income) + " M " + int(aiEconomyMgr.metal.current) + "/" + int(aiEconomyMgr.metal.storage)
			+ " E inc=" + F1(aiEconomyMgr.energy.income) + " E " + int(aiEconomyMgr.energy.current) + "/" + int(aiEconomyMgr.energy.storage)
			+ " stall=" + aiEconomyMgr.isEnergyStalling + " bpTarget=" + F1(aiEconomyMgr.metal.income * aiFactoryMgr.buildpowerRatio));
		Intel::BridgeLog();
		AiLog("[ANV] hold " + Hold::Status());

		AiLog("[ANV] t=" + Minute() + "m " + Director::Status() + " | " + Assess::Status() + " | allPow=" + F1(Director::MeasuredPower()) + " units=" + Army::ground.length()
			+ " raiders=" + Army::raiders.length() + " squads=" + Army::squads.length() + " recalls=" + Army::recalls + " ft=" + Army::Hist()
			+ " quota.attack=" + F1(aiMilitaryMgr.quota.attack) + " raidMin=" + F1(aiMilitaryMgr.quota.raid.min)
			+ " enemyMob=" + F1(aiEnemyMgr.mobileThreat) + " jamCost=" + F1(Intel::jammerCost)
			+ " maxHeat=" + F1(Intel::MaxHeat()) + " eyes=" + Intel::eyes.length() + "/" + Intel::eyesOrdered
			+ " | " + Production::Status() + " | " + Recycler::Status() + " | " + Strategic::Status()
			+ " | E inc=" + F1(aiEconomyMgr.energy.income) + " pull=" + F1(aiEconomyMgr.energy.pull)
			+ " M inc=" + F1(aiEconomyMgr.metal.income));
	}
}

}  // namespace Brain
