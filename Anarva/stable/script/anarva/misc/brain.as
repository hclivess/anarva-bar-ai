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

// Feature flags: tools/install.ps1 -Flags "F_PROD=true,..." flips them in an installed copy so each
// module can be A/B-tested head-to-head against the first-gen build. A module ships ON only after it\n// has measurably won; defaults below are the best-measured configuration (bisect round 4: 5-3 vs first-gen).
const bool F_WAVES = false;     // script-owned wave/pack gathering
const bool F_RECALL = true;     // broken-squad recall
const bool F_PROD = false;      // capability-based production chooser (incl. rez bots)
const bool F_SCALE = true;      // Director drives buildpowerRatio
const bool F_ECOGATE = false;   // moho energy-headroom gate
const bool F_RECYCLE = true;    // eco recycling + T1 salvage
const bool F_STRAT = true;      // strategic structures + AA counter
const bool F_FORTIFY = false;   // turrets + teeth at hot fronts
const bool F_WASTE = false;     // overflow: nanos + converters
const bool F_TECH = false;      // payback-based tech gate
const bool F_REDIRECT = false;  // assist factories by army deficit
const bool F_INTEL = true;      // eyes, scouting, phantom threat
const bool F_QUOTA = false;     // attack/raid quotas sized from needed power
const bool F_OPENER = true;     // constructor-rich T1 opener (false = BARb hard opener)
const bool F_SCOUT = false;     // scout quota >=3 and timed scout recruits (keep sight)
const bool F_AA = false;        // static AA counter
const bool F_FUSREC = false;    // recycle fusions once AFUS carry the grid
const bool F_NEWRECALL = false; // need-based recall (false = first-gen 40%-of-peak rule)
const bool F_MAPECO = false;    // constructor share from free extractor spots (map analysis)
const bool F_COMMSAFE = false;  // commander only works inside the zone our army protects
const bool F_DETAIL = false;    // 1vN: defeat in detail - size against one opponent's army, not their sum
const bool F_TERRAIN = true;    // fortify the choke from the high ground (map analysis)
const bool F_CONVERT = false;   // wasted energy -> converters, chosen by payback incl. build time
const bool F_EXPAND = false;    // constructors from the free extractor spots (marginal value), not from income
const bool F_DEFSIZE = false;   // terrain defence sized to the metal deficit (false: one turret per attack)
const bool F_ENERGY = false;    // energy decided live (with profile anarva_e, where the fixed curve is off)
const bool F_STAKE = false;     // trade estimate weighted by the army at stake (no all-in on a few kills)
const bool F_COMMZONE = false;  // commander works only inside the zone where nothing of ours has died (with F_COMMSAFE)
const bool F_REZ = false;       // rez-bot fleet sized to the wreck metal on the map
const bool F_BOOM = false;      // scale on pressure, not presence (human playbook vs BARbs)
const bool F_HOLD = true;       // just-in-time extractor defence: meet each incoming enemy group at the extractor it is heading for (C++ bridge)
const bool F_ARTYHIGH = true;   // core switch: artillery fires from the spot it reaches soonest, height-aware range (C++)
const bool F_HEIGHTSQUAD = false; // core switch: squad units stand at their range from the height of their spot (C++)
const bool F_ZONES = false;     // trade measured on our side vs theirs (kills located via the bridge); attacks/raids sized by the away trade
const bool F_COMMGUARD = true;  // commander goes home when a known force it can't survive could reach it first (C++ bridge)
const bool F_COMMFOG = false;   // commander danger also counts the enemy strength we believe exists but can't see, from their centre
const bool F_RECLAIM = false;   // constructors reclaim wreck fields when the metal, minus walk and risk, beats their current job
const bool F_DEFRISK = false;   // a turret is built only where it is more likely to survive than not (cover vs the danger that can reach it)
const bool F_BUILDERSAFE = false; // constructors leave a job when (1-P) x job - P x own cost is worth less than assisting a factory
const bool F_HOLDALL = false;   // the just-in-time defence covers every constructor and structure, not only extractors
const bool F_STORAGE = false;   // reclaims only start when the metal fits; metal storage built when held-back reclaims are worth more than it costs
const bool F_ENGAGE = false;    // core switch: gathering squads fight enemies inside their own sight that they can beat (owner saw a raider pace past a lone pawn)
const bool F_TURN = false;      // travel times include turning (turn rate, arcs) and acceleration, not distance/top speed
const bool F_SCOUTMAP = false;  // scouts go where vision is worth most: our assets an unseen enemy could have reached since we last looked (C++ switch)
const bool F_MOHO = true;       // T2 lab builds T2 constructors while one more saves more on the extractor-upgrade queue than it costs
const bool F_COMMFWD = false;   // (with F_COMMRISK) commander claims the free extractor spot with the best gain - risk, anywhere: the human front-builder pattern
const bool F_COMMRISK = false;  // commander takes any job whose value beats P(death) x everything we own (Lanchester), else the safest productive job; never idle
const bool F_COMMSPOT = false;  // commander retreats to the safe spot where its death explosion would destroy least (not into the eco)
const bool F_JIT = false;       // build-power scale from the ratio at each enemy arrival time (just in time), not from everything at once
const bool F_POWERALL = true;   // our power = every armed mobile unit that can hit the surface (bridge), not only the gather pool


/*
 * Travel time with the unit's real motion: turn to face the target, accelerate, cruise. Vehicles turn slowly
 * and on an arc (no turn in place); distance/top speed makes them look as agile as bots, which overstates how
 * fast they reach a raid, retreat or kite. Heading unknown: the expected turn of a random heading is 90 deg.
 */
const float EXPECTED_TURN = 90.f;  // mean of a uniform 0..180 deg turn (heading unknown), not a tuning knob
float MoveTime(const CCircuitDef@ d, float dist)
{
	const float v = AiMax(1.f, d.speed);
	if (!F_TURN) return dist / v;
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
// The factory with the fewest caretakers, each caretaker counted for the factory nearest to it.
CCircuitUnit@ FactoryWithFewestNanos(const CCircuitDef@ nanoDef)
{
	const array<CCircuitUnit@>@ facs = Brain::Intel::allFactories;
	if (facs.length() == 0) return null;
	array<int> n(facs.length(), 0);
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	for (uint i = 0; i < all.length(); ++i) {
		if (all[i].circuitDef !is nanoDef) continue;
		const AIFloat3 p = all[i].GetPos(ai.frame);
		int k = -1; float bd = 1e30f;
		for (uint j = 0; j < facs.length(); ++j) { const float d = facs[j].GetPos(ai.frame).distance2D(p); if (d < bd) { bd = d; k = int(j); } }
		if (k >= 0) ++n[k];
	}
	int best = 0;
	for (uint j = 1; j < facs.length(); ++j) if (n[j] < n[best]) best = int(j);
	return facs[best];
}


// A turret alone at the front dies without trading (owner: "absolutely not covered, gets destroyed"). Build it only
// where it is more likely to survive than not: (1-P) x cost > P x cost, P from the same fight-and-escape estimate,
// at the turret's health, against everything that can reach it while it is being built.
bool TurretSurvives(const CCircuitDef@ tur, const AIFloat3& in pos)
{
	if (!F_DEFRISK) return true;
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

float baseAttack = 60.f;
float baseRaidMin = 6.f;
uint baseScout = 2;
float raiderPower = 0.f;

array<CCircuitUnit@> ground;   // units that end up in defend->attack squads
array<CCircuitUnit@> scouts;
float groundPower = 0.f;

uint excludeMask = 0;

void Init()
{
	baseAttack  = aiMilitaryMgr.quota.attack;
	baseRaidMin = aiMilitaryMgr.quota.raid.min;
	baseScout   = aiMilitaryMgr.quota.scout;

	excludeMask = Unit::Role::SCOUT.mask | Unit::Role::RAIDER.mask | Unit::Role::AA.mask
		| Unit::Role::ARTY.mask | Unit::Role::SUPPORT.mask | Unit::Role::BUILDER.mask
		| Unit::Role::COMM.mask | Unit::Role::MINE.mask | Unit::Role::TRANS.mask
		| Unit::Role::BOMBER.mask | Unit::Role::AS.mask;

	array<CCircuitDef@> raiders = Defs({"armflash", "armpw", "corgator", "corak", "leggob", "legmrv", "armfav", "corfav"});
	float sum = 0.f;
	for (uint i = 0; i < raiders.length(); ++i)
		sum += raiders[i].power;
	raiderPower = (raiders.length() > 0) ? sum / raiders.length() : 0.f;

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
	AiLog("[ANV] Army init: attack=" + F1(baseAttack) + " raidMin=" + F1(baseRaidMin)
		+ " scout=" + baseScout + " raiderPower=" + F1(raiderPower));
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
float raiderPoolPower = 0.f;

void OnAdded(CCircuitUnit@ unit)
{
	const CCircuitDef@ d = unit.circuitDef;
	if (d.IsRoleAny(Unit::Role::SCOUT.mask)) {
		scouts.insertLast(unit);
	}
	if (IsGround(d)) {
		ground.insertLast(unit);
		groundPower += d.power;
	} else if (IsRaider(d)) {
		raiders.insertLast(unit);
		raiderPoolPower += d.power;
	}
}

void OnRemoved(CCircuitUnit@ unit)
{
	int idx = ground.findByRef(unit);
	if (idx >= 0) {
		ground.removeAt(idx);
		groundPower = AiMax(0.f, groundPower - unit.circuitDef.power);
	}
	idx = raiders.findByRef(unit);
	if (idx >= 0) {
		raiders.removeAt(idx);
		raiderPoolPower = AiMax(0.f, raiderPoolPower - unit.circuitDef.power);
	}
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
	ForgetTask(task);
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

/*
 * Wave control. The core sizes each gathering squad as max(quota, enemy's 2nd-biggest group threat);
 * once the enemy has any big blob that bar is unreachable and the army never launches, then gets
 * ground down at home. Instead we keep ONE gathering task per kind, sized by the Director, and put
 * every new unit into it. When it reaches its size the core promotes it to an attack/raid and we
 * start the next wave.
 */
IUnitTask@ waveTask = null;
IUnitTask@ packTask = null;
float waveSize = 0.f;
int waves = 0;

IUnitTask@ MakeTask(CCircuitUnit@ unit)
{
	if (!F_WAVES)
		return null;
	const CCircuitDef@ d = unit.circuitDef;
	if (IsGround(d) && !d.IsRoleAny(Unit::Role::RIOT.mask | Unit::Role::SUPER.mask)) {
		if (waveTask is null) {
			waveSize = AiMax(baseAttack, aiMilitaryMgr.quota.attack);
			@waveTask = aiMilitaryMgr.Enqueue(TaskF::Defend(Task::FightType::ATTACK, waveSize));
			++waves;
		}
		return waveTask;
	}
	if (IsRaider(d)) {
		if (packTask is null)
			@packTask = aiMilitaryMgr.Enqueue(TaskF::Defend(Task::FightType::RAID, aiMilitaryMgr.quota.raid.min));
		return packTask;
	}
	return null;
}

void ForgetTask(IUnitTask@ task)
{
	if (task is waveTask)
		@waveTask = null;
	if (task is packTask)
		@packTask = null;
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
	if (!F_RECALL)
		return;
	for (int i = int(squads.length()) - 1; i >= 0; --i) {
		IFighterTask@ task = squads[i];
		const float p = SquadPower(task);
		if (p > squadPeak[i])
			squadPeak[i] = p;
		if (ai.frame - squadStart[i] < 20 * SECOND || squadPeak[i] <= 0.f)
			continue;
		// Keep a squad that is still bigger than what we'd send out fresh.
		const bool isRaid = task.GetFightType() == Task::FightType::RAID;
		const float fresh = isRaid ? aiMilitaryMgr.quota.raid.min : aiMilitaryMgr.quota.attack;
		// Recall once the squad has bled and is now weaker than what we'd send fresh, scaled by how well we trade.
		const bool recall = F_NEWRECALL ? (p < squadPeak[i] && p < fresh * AiMin(1.f, Brain::Assess::trade))
			: (p < 0.4f * squadPeak[i] && p < fresh);  // first-gen rule
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

void Update(bool jamAlert)
{
	// A wave must be able to win what it will meet (Director: needed power, incl. jammer guesses).
	// If we can't reach it, the wave doesn't launch: the gathered army defends at home, where trades are better.
	aiMilitaryMgr.quota.attack = AiMax(baseAttack, F_ZONES ? Brain::Director::needPowerAway : Brain::Director::needPower);

	// A raid pack must beat the raiders that will answer it (their raider threat at our trade rate).
	float raidMin = AiMax(baseRaidMin, aiEnemyMgr.GetEnemyThreat(RT::RAIDER) / AiMax(0.25f, F_ZONES ? Brain::Assess::tradeAway : Brain::Assess::trade));	aiMilitaryMgr.quota.raid.min = raidMin;
	// raid.avg caps how big a raid may grow by joining; never below the gather size
	aiMilitaryMgr.quota.raid.avg = AiMax(aiMilitaryMgr.quota.raid.avg, raidMin * 1.5f);

	CheckSquads();

	aiMilitaryMgr.quota.scout = jamAlert ? baseScout + 3 : baseScout;
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
	if (!F_STORAGE) return;
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
	if (!F_SCOUTMAP) return;
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
			float v = dots[c] * meanCost;
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
	// assets to defend: extractors, or (F_HOLDALL) every constructor and structure of ours
	array<CCircuitUnit@> mexes;
	if (F_HOLDALL) {
		const array<CCircuitUnit@>@ own = AiGetTeamUnits();
		for (uint k = 0; k < own.length(); ++k) {
			const CCircuitDef@ d = own[k].circuitDef;
			if (!d.IsMobile() || (d.IsRoleAny(Unit::Role::BUILDER.mask) && own[k] !is commander)) mexes.insertLast(own[k]);
		}
	} else mexes = Economist::mexes;
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
		for (uint i = 0; i < free.length(); ++i) {
			if (free[i] is null) continue;
			const float t = MoveTime(free[i].circuitDef, free[i].GetPos(ai.frame).distance2D(mp[m]));
			if (t > eta[m]) continue;
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
array<CCircuitDef@> fusDefs;     // plain fusions, recycled once advanced fusions carry the grid
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
	fusDefs = Defs({"armfus", "corfus", "legfus", "armckfus"});
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
	float m = aiEconomyMgr.GetEnergyMake(d);
	return (m > 0.f) ? m : 20.f;  // wind/tidal report 0 here; assume a typical value
}

float BigMake()
{
	float sum = 0.f;
	for (uint i = 0; i < bigEnergy.length(); ++i)
		sum += EnergyMake(bigEnergy[i].circuitDef);
	return sum;
}

bool HasAfus() { return AfusCount() > 0; }

int AfusCount()
{
	int n = 0;
	for (uint i = 0; i < bigEnergy.length(); ++i) {
		if (InList(afusDefs, bigEnergy[i].circuitDef))
			++n;
	}
	return n;
}

float AfusMake()
{
	float sum = 0.f;
	for (uint i = 0; i < bigEnergy.length(); ++i) {
		if (InList(afusDefs, bigEnergy[i].circuitDef))
			sum += EnergyMake(bigEnergy[i].circuitDef);
	}
	return sum;
}

array<CCircuitUnit@> Fusions()
{
	array<CCircuitUnit@> res;
	for (uint i = 0; i < bigEnergy.length(); ++i) {
		if (InList(fusDefs, bigEnergy[i].circuitDef))
			res.insertLast(bigEnergy[i]);
	}
	return res;
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

array<CCircuitDef@> t1Units;  // cheap T1 lab/vehicle combat units that stop mattering late

bool IsObsoleteT1(CCircuitUnit@ u)
{
	if (t1Units.length() == 0)
		t1Units = Defs({"armpw", "armflash", "armfav", "armflea", "armpincer", "armrock", "armjeth",
			"corak", "corgator", "corfav", "corstorm", "corgarp", "corcrash",
			"leggob", "legscout", "leglob", "legmrv", "legkark"});
	if (!InList(t1Units, u.circuitDef))
		return false;
	return HasBase() && basePos.distance2D(u.GetPos(ai.frame)) < 1200.f;
}

void Salvage()
{
	if (F_STORAGE) {
		// obsolete once we have advanced labs; the metal must fit (Reclaim checks), no clock or income bar
		if (advFactories <= 0 || salvagePending.length() >= 2 || ai.frame - lastSalvageFrame < 15 * SECOND)
			return;
	} else if (ai.frame < 22 * MINUTE || advFactories <= 0 || aiEconomyMgr.metal.income < 30.f
		|| aiEconomyMgr.isMetalFull || salvagePending.length() >= 2 || ai.frame - lastSalvageFrame < 15 * SECOND)
		return;
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
		if (IsObsoleteT1(u) && pending.findByRef(u) < 0 && Brain::Army::scouts.length() > 2)
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
	if (F_STORAGE && !Brain::Storage::Fits(u.circuitDef.costM)) {
		Brain::Storage::Block(u.circuitDef.costM);
		return;
	}
	aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::HIGH, u, RECLAIM_TIMEOUT));
	pending.insertLast(u);
	pendingFrame.insertLast(ai.frame);
}

void Update()
{
	PrunePending();

	const SResourceInfo@ e = aiEconomyMgr.energy;
	const float bigMake = BigMake();
	const float income = e.income;
	const float fill = (e.storage > 0.f) ? e.current / e.storage : 0.f;

	// Safety valve: if energy collapses after losing fusions, allow cheap energy again.
	if (aiEconomyMgr.isEnergyStalling && fill < 0.1f)
		++stallTicks;
	else
		stallTicks = 0;
	if (stallTicks >= 15 && bigMake < 0.5f * AiMax(income, 1.f)) {
		RestoreAll();
		stallTicks = 0;
		return;
	}

	if (int(pending.length()) >= MAX_PENDING)
		return;

	// --- energy ---
	if (bigMake > 0.f && bigMake >= 0.6f * income && !aiEconomyMgr.isEnergyStalling && fill > 0.5f) {
		CCircuitUnit@ cand = PickCandidate(lowEnergy);
		if (cand is null && (HasAfus() || bigMake >= 3000.f))
			@cand = PickCandidate(midEnergy);
		if (cand !is null) {
			float pendingMake = 0.f;
			for (uint i = 0; i < pending.length(); ++i)
				pendingMake += EnergyMake(pending[i].circuitDef);
			const float m = EnergyMake(cand.circuitDef);
			const float surplus = income - pendingMake - m - e.pull;
			if (surplus > AiMax(0.08f * income, 40.f)) {
				Retire(cand.circuitDef);
				Reclaim(cand);
				return;
			}
		}
	}

	// --- plain fusions once 2+ advanced fusions carry the grid ---
	if (F_FUSREC && AfusCount() >= 2 && AfusMake() >= 0.7f * income && fill > 0.6f && !aiEconomyMgr.isEnergyStalling) {
		CCircuitUnit@ cand = PickCandidate(Fusions());
		if (cand !is null) {
			const float surplus = income - EnergyMake(cand.circuitDef) - e.pull;
			if (surplus > AiMax(0.1f * income, 200.f)) {
				Retire(cand.circuitDef);
				Reclaim(cand);
				AiLog("[ANV] Recycler: recycling fusion " + cand.circuitDef.GetName() + " (afus carry the grid)");
				return;
			}
		}
	}

	Salvage();

	// --- T1 metal makers once T2 makers carry conversion ---
	if (highMakers.length() >= 4 && fill > 0.7f) {
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
	// Keep eyes on the enemy: planes on a timer, more when blind or jammed; ground scouts as fallback.
	const bool blind = Brain::Director::blind;
	const int interval = (jamAlert || blind) ? 90 * SECOND : (F_SCOUT ? 3 * MINUTE : 1 << 30);
	if (ai.frame - lastScoutFrame > interval && Brain::Army::scouts.length() < uint((jamAlert || blind) ? 4 : 2)) {
		array<CCircuitUnit@>@ facs = airFactories.length() > 0 ? airFactories : allFactories;
		if (facs.length() > 0) {
			CCircuitUnit@ fac = FactoryReachedSoonestIn(facs, basePos, null);
			CCircuitDef@ scout = aiFactoryMgr.GetRoleDef(fac.circuitDef, RT::SCOUT);
			if (scout !is null && scout.IsAvailable(ai.frame)) {
				aiFactoryMgr.Enqueue(TaskS::Recruit(Task::RecruitType::FIREPOWER, Task::Priority::HIGH,
					scout, fac.GetPos(ai.frame), 64.f));
				lastScoutFrame = ai.frame;
				AiLog("[ANV] Intel: scouting with " + scout.GetName() + (jamAlert ? " (jammers)" : (blind ? " (blind)" : " (keep sight)")));
			}
		}
	}
}

// Put a cheap long-sight camera where we keep dying. Under a jammer, sight is the only way to see.
void OrderVision()
{
	if (eyesDef is null || !eyesDef.IsAvailable(ai.frame))
		return;
	const uint maxEyes = jamAlert ? 16 : 8;
	if (eyes.length() >= maxEyes)
		return;
	const float threshold = jamAlert ? 250.f : 500.f;

	int best = -1;
	float bestHeat = threshold;
	for (uint c = 0; c < heat.length(); ++c) {
		if (heat[c] > bestHeat && ai.frame - lastEyesFrame[c] > 3 * MINUTE) {
			bestHeat = heat[c];
			best = int(c);
		}
	}
	if (best < 0)
		return;

	lastEyesFrame[best] = ai.frame;
	AIFloat3 hot = CellCenter(best);
	if (hot.distance2D(basePos) < 900.f)
		return;  // base already has sight
	// Stand off toward our base so the builder isn't fed to whatever is there.
	AIFloat3 dir = basePos - hot;
	dir.y = 0.f;
	const float len = dir.Length2D();
	if (len > 1.f)
		hot = hot + dir * (AiMin(350.f, len * 0.4f) / len);
	if (EyesNear(hot, 450.f))
		return;

	aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE, Task::Priority::HIGH, eyesDef, hot,
		SQUARE_SIZE * 16, true, 2 * MINUTE));
	++eyesOrdered;
	AiLog("[ANV] Intel: vision ordered at (" + int(hot.x) + "," + int(hot.z) + ") heat=" + F1(bestHeat));
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
	InitCounter();
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
	const float L = AMD_BUILDTIME / (Brain::Convert::CON_WORK * AiMax(1.f, workers * 0.5f)) + AMD_STOCKPILE_S;
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

void OnFinished(CCircuitUnit@ u)
{
	const CCircuitDef@ d = u.circuitDef;
	if (InList(junoDefs, d))        junos.insertLast(u);
	else if (InList(amdDefs, d))    amds.insertLast(u);
	else if (InList(tacDefs, d))    tacs.insertLast(u);
	else if (InList(siloDefs, d))   silos.insertLast(u);
	else if (InList(shieldDefs, d)) shields.insertLast(u);
	else if (InList(aaDefs, d))     aaTowers.insertLast(u);
	if (!d.IsMobile() && d.costM >= 250.f && !InList(shieldDefs, d))
		infra.insertLast(u);
}

void OnDestroyed(CCircuitUnit@ u)
{
	RemoveUnit(junos, u); RemoveUnit(amds, u); RemoveUnit(tacs, u);
	RemoveUnit(silos, u); RemoveUnit(shields, u); RemoveUnit(infra, u); RemoveUnit(aaTowers, u);
}

bool Ready(int kind, CCircuitDef@ d)
{
	return d !is null && d.IsAvailable(ai.frame) && ai.frame - lastOrder[kind] > 4 * MINUTE;
}

void Order(int kind, CCircuitDef@ d, const AIFloat3& in pos, Task::Priority pri, float shake)
{
	lastOrder[kind] = ai.frame;
	++orders;
	aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::BIG_GUN, pri, d, pos, shake, true, 5 * MINUTE));
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
	CounterUpdate();
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
	// Juno: EMP missile that wipes radar, jammers and mines in its blast. Our answer to jammers.
	if (jamAlert && minute >= 12 && junos.length() < 1 && Ready(0, junoDef)) {
		Order(0, junoDef, basePos, Task::Priority::HIGH, SQUARE_SIZE * 32);
		return;
	}
	// Everything below is an investment that doesn't fight today: only when our army covers what we need.
	if (Brain::Director::ratio < 1.f)
		return;
	// Shields over the most valuable uncovered infrastructure (they drain ~560 E/s recharging).
	const uint wantShields = uint(AiMin(6.f, AiMax(0.f, (m - 30.f) / 25.f)));
	if (minute >= 14 && e >= 1500.f && shields.length() < wantShields && Ready(4, shieldDef)) {
		AIFloat3 pos;
		float value;
		if (BestShieldSpot(pos, value) && value >= 2500.f) {
			Order(4, shieldDef, pos, Task::Priority::NORMAL, SQUARE_SIZE * 6);
			return;
		}
	}
	// Tactical / EMP launcher, forward of base.
	const uint wantTac = (minute >= 18 && m >= 40.f) ? (m >= 80.f ? 2 : 1) : 0;
	if (tacs.length() < wantTac && Ready(2, tacDef)) {
		Order(2, tacDef, ForwardPos(900.f), Task::Priority::NORMAL, SQUARE_SIZE * 24);
		return;
	}
	// Nuke: late, rich, and only under our own anti-nuke umbrella.
	if (minute >= 30 && m >= 90.f && amds.length() >= 1 && silos.length() < 1 && Ready(3, siloDef)) {
		Order(3, siloDef, basePos, Task::Priority::NORMAL, SQUARE_SIZE * 32);
		return;
	}
}

/*
 * Counter: react to what we've scouted. Air -> static AA over infrastructure (T1 missile towers,
 * then flak, then long-range AA), scaled to the enemy's seen air metal. The core's response
 * system already shifts mobile AA production; this covers the assets bombers go for.
 */
CCircuitDef@ aaT1, aaT2, aaT3;
array<CCircuitDef@> aaDefs;
array<CCircuitUnit@> aaTowers;
int lastAAOrder = 0;

void InitCounter()
{
	@aaT1 = Side("armrl", "corrl", "legrl");
	@aaT2 = Side("armflak", "corflak", "legflak");
	@aaT3 = Side("armmercury", "corscreamer", "leglraa");
	aaDefs = Defs({"armrl", "corrl", "legrl", "armflak", "corflak", "legflak", "armmercury", "corscreamer", "leglraa",
		"armcir", "cormadsam", "armferret", "corerad"});
}

void CounterUpdate()
{
	if (!F_AA)
		return;
	const float air = aiEnemyMgr.GetEnemyCost(RT::AIR);
	if (air < 300.f || infra.length() == 0 || ai.frame - lastAAOrder < 20 * SECOND)
		return;
	const uint want = uint(AiMin(14.f, air / 350.f));
	if (aaTowers.length() >= want)
		return;
	const float m = aiEconomyMgr.metal.income;
	CCircuitDef@ d = (m >= 60.f && aaT3 !is null && aaT3.IsAvailable(ai.frame) && aaTowers.length() % 4 == 3) ? aaT3
		: ((m >= 25.f && aaT2 !is null && aaT2.IsAvailable(ai.frame)) ? aaT2 : aaT1);
	if (d is null || !d.IsAvailable(ai.frame))
		return;
	// cover the infra unit with the fewest AA towers nearby
	CCircuitUnit@ best = null;
	int bestCount = 1 << 20;
	for (uint i = 0; i < infra.length(); ++i) {
		const AIFloat3 p = infra[i].GetPos(ai.frame);
		int c = 0;
		for (uint k = 0; k < aaTowers.length(); ++k) {
			if (aaTowers[k].GetPos(ai.frame).distance2D(p) < 600.f)
				++c;
		}
		if (c < bestCount) {
			bestCount = c;
			@best = infra[i];
		}
	}
	if (best is null)
		return;
	lastAAOrder = ai.frame;
	aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE, Task::Priority::HIGH, d, best.GetPos(ai.frame),
		SQUARE_SIZE * 20, true, 3 * MINUTE));
	AiLog("[ANV] Counter: enemy air " + F1(air) + "m seen -> " + d.GetName() + " (" + aaTowers.length() + "/" + want + ")");
}

/*
 * Fortify (HOLD/TURTLE): when outnumbered, fight where the enemy has to come to us. The loss
 * heatmap shows where fights happen; we put a turret there (tier by income) with a short row of
 * dragon's teeth in front of it, toward the threat, so attackers stall under fire.
 */
CCircuitDef@ turT1, turT2, turT3, wallDef;
int lastFortify = 0, forts = 0;
// terrain defence bookkeeping: build the next turret only once the last one stands AND something has
// come at us since (event-driven, no timer flood: one order per real attack)
int terrainBuilt = 0;
float terrainHit = 0.f, hitAtLastOrder = -1.f;
CCircuitDef@ terrainDef = null;
float terrainPower = 0.f;            // power of the turrets standing at our choke
float terrainMetal = 0.f;            // metal in them
float armyMetal = 0.f;               // our armed mobile units (not builders), metal
float EnemyArmyMetal()               // known enemy ground army, metal (the core remembers what it saw)
{
	return aiEnemyMgr.GetEnemyCost(RT::RAIDER) + aiEnemyMgr.GetEnemyCost(RT::ASSAULT) + aiEnemyMgr.GetEnemyCost(RT::SKIRM)
		+ aiEnemyMgr.GetEnemyCost(RT::RIOT) + aiEnemyMgr.GetEnemyCost(RT::HEAVY) + aiEnemyMgr.GetEnemyCost(RT::ARTY);
}
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
	 * How much defence: when the enemy comes to us, defence is the cheaper form of war (Clausewitz), so
	 * the choke takes turrets while the army can't cover what we need: deficit = power needed - army
	 * power - turret power already standing there. Plus one more whenever something came at us since
	 * the last order (the measured pressure). Humans vs several BARbs put ~20 light turrets and ~30 mines
	 * on the lanes in the first 8 minutes (Edict, Comet Catcher 1v2).
	 */
	const float hit = terrainHit + Brain::Assess::lostNearTotal;
	// in metal, which is what both sides actually spend: the known enemy army against our army plus the
	// turrets already standing at the choke (a turret holding ground is worth at least its cost)
	const float deficit = F_DEFSIZE ? EnemyArmyMetal() - armyMetal - terrainMetal : 0.f;
	if (forts > 0 && deficit <= 0.f && hit <= hitAtLastOrder)
		return true;
	// the turret that holds the most ground per metal we can build now (live, from the defs)
	CCircuitDef@ tur = BestTurret();
	if (tur is null || !tur.IsAvailable(ai.frame))
		return true;
	// orders still unbuilt (tasks live 3 min) count against the deficit; expired ones are forgotten
	if (ai.frame - lastFortify >= 3 * MINUTE)
		terrainBuilt = forts;
	const int pending = forts - terrainBuilt;
	const int need = (deficit > 0.f) ? int(ceil(deficit / AiMax(1.f, tur.costM))) : 1;
	const int n = AiMin(need - pending, AiMax(1, aiBuilderMgr.GetWorkerCount()));
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
		+ (minelayers > 0 ? " + mines" : "") + " deficit=" + int(deficit));
	return true;
}

void Fortify()
{
	if (!F_FORTIFY && !F_TERRAIN)
		return;
	if (F_TERRAIN && TerrainFortify())
		return;
	const int p = Brain::Director::posture;
	if ((p != Brain::Director::HOLD && p != Brain::Director::TURTLE) || ai.frame < 5 * MINUTE
		|| ai.frame - lastFortify < 30 * SECOND)
		return;
	const float m = aiEconomyMgr.metal.income;
	if (forts >= int(4.f + m / 6.f))
		return;
	// hottest cell that is a real front: not our base core, not deep in enemy land
	int best = -1;
	float bestHeat = 150.f;
	for (uint c = 0; c < Brain::Intel::heat.length(); ++c) {
		const float h = Brain::Intel::heat[c];
		if (h <= bestHeat)
			continue;
		const float d = Brain::Intel::CellCenter(c).distance2D(basePos);
		if (d < 600.f || d > 2600.f)
			continue;
		bestHeat = h;
		best = int(c);
	}
	if (best < 0)
		return;
	CCircuitDef@ tur = (m >= 45.f && turT3 !is null && turT3.IsAvailable(ai.frame)) ? turT3
		: ((m >= 18.f && turT2 !is null && turT2.IsAvailable(ai.frame)) ? turT2 : turT1);
	if (tur is null || !tur.IsAvailable(ai.frame))
		return;
	const AIFloat3 hot = Brain::Intel::CellCenter(best);
	AIFloat3 dir = hot - basePos;
	dir.y = 0.f;
	const float len = AiMax(1.f, dir.Length2D());
	dir = dir / len;
	// turret a bit on our side of the hotspot
	const AIFloat3 tpos = basePos + dir * AiMax(500.f, len - 250.f);
	if (!TurretSurvives(tur, tpos)) return;
	lastFortify = ai.frame;
	++forts;
	aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE, Task::Priority::HIGH, tur, tpos, SQUARE_SIZE * 8, true, 3 * MINUTE));
	if (wallDef !is null && wallDef.IsAvailable(ai.frame)) {
		const AIFloat3 side(-dir.z, 0.f, dir.x);
		for (int k = -2; k <= 2; ++k) {
			const AIFloat3 wpos = tpos + dir * 140.f + side * (48.f * k);
			aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE, Task::Priority::NORMAL, wallDef, wpos, 0.f, true, 3 * MINUTE));
		}
	}
	AiLog("[ANV] Fortify: " + tur.GetName() + " + teeth at (" + int(tpos.x) + "," + int(tpos.z) + ") facing heat " + F1(bestHeat));
}

string Status()
{
	return "forts=" + forts + " aa=" + aaTowers.length() + " juno=" + junos.length() + " amd=" + amds.length() + " tac=" + tacs.length() + " silo=" + silos.length()
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

// The core's own rule: build power should be income * buildpowerRatio (the Director sets the ratio).
// A T1 constructor brings ~85 workertime = ~4.25 build_speed units (unit facts), so that many workers.
const float BUILD_SPEED_PER_WORKER = 4.25f;
const int CORE_BUILDER_SHARE = 30;  // percent: mean constructor weight in factory.json T1/T2 tiers (config fact)
// Constructor share of factory decisions. With map analysis: free extractor spots on our side
// (map extractors / players - extractors we own) over (free spots + constructors): high when there is
// much to claim and few hands, falling to zero once the map is taken. Without it: the core's config share.
MapFacts::SMap@ mapInfo = null;
void LookAtMap()  // pre-match map study (tools/analyze_maps.py)
{
	MapFacts::Init();
	@mapInfo = MapFacts::Get(ai.GetMapName());
	AiLog("[ANV] Map: " + ai.GetMapName() + (mapInfo is null ? " (not analysed)" : (" mex=" + mapInfo.mex + " path=" + int(mapInfo.basePath) + " straight=" + int(mapInfo.straight) + " choke=" + int(mapInfo.choke) + " water=" + F1(mapInfo.water))));
}
int BuilderSharePercent()
{
	if (!F_MAPECO || mapInfo is null)
		return CORE_BUILDER_SHARE;
	const float players = float(AiMax(2, ai.GetEnemyTeamSize() + 1));
	const float free = AiMax(0.f, float(mapInfo.mex) / players - float(Brain::Economist::mexes.length()));
	const float workers = float(aiBuilderMgr.GetWorkerCount());
	return int(100.f * free / AiMax(1.f, free + workers));
}

bool NeedBuilder()
{
	const float want = aiEconomyMgr.metal.income * aiFactoryMgr.buildpowerRatio / BUILD_SPEED_PER_WORKER;
	return float(aiBuilderMgr.GetWorkerCount()) < want;
}

// Our current army, as the candidates would join it (Lanchester: strength ~ total damage x total health).
float armyH = 0.f, armyD = 0.f, armyCost = 0.f, armyRange = 0.f, armyLos = 0.f, armySpeed = 0.f, wArty = 0.f, wStaticCost = 0.f;

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
	const float pool = F_REZ
		? WRECK_SHARE * (Brain::Assess::lostNearTotal + HoldShare() * (Brain::Assess::lostFarTotal + Brain::Assess::killedTotal))
		: 0.5f * (Brain::Assess::lostNear + Brain::Assess::lostFar + Brain::Assess::killed);
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

// Constructors the expansion rule asks for, recruited directly: the core gates its own constructor
// choice behind a coin flip once a factory is "active", which throttles expansion exactly when it pays.
array<string> T1_CONS = {"armck", "armcv", "corck", "corcv", "legck", "legcv", "armcs", "corcs", "legnavyconship"};
int expandOrders = 0;
IUnitTask@ ExpandTask(CCircuitUnit@ fac)
{
	if (!F_EXPAND || Brain::Assess::pushedBack || aiEconomyMgr.isEnergyStalling)
		return null;
	const float income = aiEconomyMgr.metal.income;
	const float want = Brain::Director::expandWant + income * Brain::Director::baseBP / BUILD_SPEED_PER_WORKER;
	if (float(aiBuilderMgr.GetWorkerCount()) >= want)
		return null;
	const array<string>@ opts = Facts::BuildOptions(fac.circuitDef.GetName());
	for (uint i = 0; i < opts.length(); ++i) {
		if (T1_CONS.find(opts[i]) < 0)
			continue;
		CCircuitDef@ con = ai.GetCircuitDef(opts[i]);
		if (con is null || !con.IsAvailable(ai.frame))
			continue;
		++expandOrders;
		return aiFactoryMgr.Enqueue(TaskS::Recruit(Task::RecruitType::BUILDPOWER, Task::Priority::HIGH, con,
			fac.GetPos(ai.frame), 64.f));
	}
	return null;
}

IUnitTask@ MineLayerTask(CCircuitUnit@ fac)
{
	if (!F_TERRAIN || Strategic::myStart < 0 || Strategic::minelayers > 0 || Strategic::mlvDef is null
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
	if (!F_MOHO) return null;
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
	if (F_REZ && !F_PROD && !fac.circuitDef.IsMobile()) {
		CCircuitDef@ rez = RezToBuild(fac.circuitDef);
		if (rez !is null) {
			++rezOrders;
			AiLog("[ANV] Rez: +" + rez.GetName() + " fleet=" + rezBots.length() + " pool~" + int(WRECK_SHARE * (Brain::Assess::lostNearTotal
				+ HoldShare() * (Brain::Assess::lostFarTotal + Brain::Assess::killedTotal))));
			return aiFactoryMgr.Enqueue(TaskS::Recruit(Task::RecruitType::BUILDPOWER, Task::Priority::HIGH, rez, fac.GetPos(ai.frame), 64.f));
		}
	}
	IUnitTask@ ml = MineLayerTask(fac);
	if (ml !is null)
		return ml;
	IUnitTask@ mc = MohoConTask(fac);
	if (mc !is null)
		return mc;
	IUnitTask@ ex = ExpandTask(fac);
	if (ex !is null)
		return ex;
	if (!F_PROD || aiEconomyMgr.isEnergyStalling)
		return null;  // energy stall: the core's first answer is energy; don't queue power-hungry units
	if (ai.frame < 6 * MINUTE)
		return null;  // let the opener run
	const CCircuitDef@ fdef = fac.circuitDef;
	if (fdef.IsMobile())
		return null;
	// Constructors are part of every factory's mix in the core's config (unit list index 0, ~25-35% of
	// T1/T2 weights). Hand that share of decisions back to the core so its constructor logic keeps the
	// economy growing; we choose only the army picks. (Debt: replace with a measured marginal value of a
	// constructor: income it adds now vs its cost and the horizon.)
	// constructor share as a quota, not a dice roll: a constructor whenever builders so far are below their share
	if (NeedBuilder() || 100 * builders < BuilderSharePercent() * (builders + choices + 1)) {
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
 * Eco gate: reasoning, not imitation. A moho/exploiter gives ~+6 m/s over a T1 extractor but costs
 * ~+17-20 E/s upkeep to run (T1: 3 E/s). An energy stall slows every factory and constructor, so an
 * upgrade is only worth starting if energy headroom can carry it. We cap concurrent advanced
 * extractors at (current count + what the headroom carries) by adjusting maxThisUnit; the cap lifts
 * as energy comes online.
 */
namespace Eco {

array<CCircuitDef@> mohoDefs;
array<int> mohoOrigMax;
const float MOHO_UPKEEP = 22.f;  // 20 E/s upkeep + margin
int gated = 0;

void Init()
{
	mohoDefs = Defs({"armmoho", "cormoho", "legmoho", "cormexp", "armuwmme", "coruwmme", "leguwmme"});
	for (uint i = 0; i < mohoDefs.length(); ++i)
		mohoOrigMax.insertLast(mohoDefs[i].maxThisUnit);
}

void Update()
{
	const SResourceInfo@ e = aiEconomyMgr.energy;
	const float fill = (e.storage > 0.f) ? e.current / e.storage : 0.f;
	// Headroom: spare income, plus a little credit for a healthy storage buffer.
	float headroom = e.income - e.pull + (fill > 0.5f ? 0.02f * e.current : 0.f);
	if (aiEconomyMgr.isEnergyStalling)
		headroom = AiMin(headroom, 0.f);
	const int allowed = AiMax(0, int(headroom / MOHO_UPKEEP));
	gated = 0;
	for (uint i = 0; i < mohoDefs.length(); ++i) {
		CCircuitDef@ d = mohoDefs[i];
		const int cap = AiMin(mohoOrigMax[i], d.count + allowed);
		if (cap < mohoOrigMax[i])
			++gated;
		d.maxThisUnit = cap;
	}
}

string Status()
{
	return "mohoGate=" + (gated > 0 ? "on" : "off");
}

}  // namespace Eco

/* ======================================================================== */
/*
 * Waste: income that hits full storage is thrown away.
 *  - metal overflowing  -> we lack spending power: more constructors (Director scale), factory assist,
 *                          and nanos at a factory.
 *  - energy overflowing -> convert it: metal makers turn energy into metal (T1 ~70 E per 1 M, T2
 *                          better) and only run while energy storage is high, so surplus is their fuel.
 */
namespace Waste {

int metalSec = 0, energySec = 0;
bool metalOverflow = false, energyOverflow = false;
int lastNano = 0, lastMaker = 0, nanos = 0, makers = 0;
CCircuitDef@ nanoDef, makerT1, makerT2;

void Init()
{
	@nanoDef = Brain::Strategic::Side("armnanotc", "cornanotc", "legnanotc");
	@makerT1 = Brain::Strategic::Side("armmakr", "cormakr", "legeconv");
	@makerT2 = Brain::Strategic::Side("armmmkr", "cormmkr", "legadveconv");
}

void Update()  // every second
{
	const SResourceInfo@ m = aiEconomyMgr.metal;
	const SResourceInfo@ e = aiEconomyMgr.energy;
	metalSec = (m.storage > 0.f && m.current >= 0.95f * m.storage && m.income > m.pull) ? metalSec + 1 : 0;
	energySec = (e.storage > 0.f && e.current >= 0.92f * e.storage && e.income > e.pull) ? energySec + 1 : 0;
	const bool wasM = metalOverflow, wasE = energyOverflow;
	metalOverflow = metalSec >= 8;
	energyOverflow = energySec >= 15;
	if (metalOverflow && !wasM)
		AiLog("[ANV] Waste: metal overflowing (" + int(m.income - m.pull) + " m/s spare): more build power + assist");
	if (energyOverflow && !wasE)
		AiLog("[ANV] Waste: energy overflowing (" + int(e.income - e.pull) + " E/s spare): convert it");
	if (!HasBase() || Brain::Intel::allFactories.length() == 0)
		return;

	if (metalOverflow && ai.frame - lastNano > 45 * SECOND && nanoDef !is null && nanoDef.IsAvailable(ai.frame)) {
		lastNano = ai.frame;
		++nanos;
		aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::NANO, Task::Priority::HIGH, nanoDef,
			FactoryWithFewestNanos(nanoDef).GetPos(ai.frame), SQUARE_SIZE * 12, true, 2 * MINUTE));
	}
	if (energyOverflow && !metalOverflow && ai.frame - lastMaker > 30 * SECOND) {
		const float spare = e.income - e.pull;
		CCircuitDef@ mk = (aiEconomyMgr.metal.income >= 35.f && makerT2 !is null && makerT2.IsAvailable(ai.frame)) ? makerT2 : makerT1;
		if (mk !is null && mk.IsAvailable(ai.frame) && spare > 70.f) {
			lastMaker = ai.frame;
			const int n = AiMin(4, int(spare / (mk is makerT2 ? 600.f : 70.f)) + 1);
			for (int i = 0; i < n; ++i)
				aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::CONVERT, Task::Priority::NORMAL, mk, basePos,
					SQUARE_SIZE * 40, true, 2 * MINUTE));
			makers += n;
			AiLog("[ANV] Waste: +" + n + " " + mk.GetName() + " to convert " + int(spare) + " E/s surplus");
		}
	}
}

string Status()
{
	return "waste(m/e)=" + metalSec + "/" + energySec + "s nanos+" + nanos + " makers+" + makers;
}

}  // namespace Waste

/* ======================================================================== */
/*
 * Convert: energy that hits full storage is thrown away; a converter turns it into metal. Which
 * converter, and how many, is a live comparison, not a rule:
 *  - spare  = energy income - pull - what converters already ordered will consume
 *  - for each converter we can build (facts from the unit files: E/s capacity, metal per E, cost,
 *    build time): n = how many the spare runs, gain = n * capacity * efficiency (M/s),
 *    time to repay = n * cost (metal + energy priced at the converter rate) / gain
 *                    + time to finish (build time at one constructor's work rate: nothing pays until built)
 *  - build the quickest-repaying one, if it repays within the planning horizon.
 * Cheap T1 converters win when space and build time are free; dense T2 ones when the spare is large.
 */
namespace Convert {

array<CCircuitDef@> defs;
array<Facts::SConv@> facts;
float pendingE = 0.f;
int pendingUntil = 0, ordered = 0, built = 0, lastLog = 0;
const float CON_WORK = 85.f;  // T1 constructor workertime (unit facts), the rate one builder adds

void Init()
{
	Facts::InitConverters();
	array<string> names = {"armmakr", "cormakr", "legeconv", "armmmkr", "cormmkr", "legadveconv"};
	for (uint i = 0; i < names.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(names[i]);
		Facts::SConv@ c = Facts::Converter(names[i]);
		if (d !is null && c !is null) {
			defs.insertLast(d);
			facts.insertLast(c);
		}
	}
}

void OnFinished(CCircuitUnit@ u)
{
	for (uint i = 0; i < defs.length(); ++i)
		if (u.circuitDef is defs[i]) {
			pendingE = AiMax(0.f, pendingE - facts[i].capE);
			++built;
		}
}

void Update()  // every second
{
	if (!HasBase() || ai.frame % (5 * SECOND) != 0)
		return;
	if (ai.frame > pendingUntil)
		pendingE = 0.f;  // orders expired or were dropped
	const SResourceInfo@ e = aiEconomyMgr.energy;
	// energy is wasted only when storage is (nearly) full and still not drained
	if (!aiEconomyMgr.isEnergyFull || aiEconomyMgr.isMetalFull)
		return;
	const float spare = e.income - e.pull - pendingE;
	if (spare <= 0.f)
		return;
	int best = -1, bestN = 0;
	float bestPay = 1e9f;
	for (uint i = 0; i < defs.length(); ++i) {
		if (!defs[i].IsAvailable(ai.frame))
			continue;
		const int n = int(spare / facts[i].capE);
		if (n < 1)
			continue;
		const float gain = n * facts[i].capE * facts[i].eff;
		const float cost = n * (facts[i].costM + facts[i].costE / Economist::energyPerMetal);
		const float pay = cost / gain + facts[i].buildTime / CON_WORK;
		if (pay < bestPay) {
			bestPay = pay;
			best = int(i);
			bestN = n;
		}
	}
	if (best < 0)
		return;
	const float horizon = Economist::Horizon();
	if (bestPay >= horizon)
		return;
	// order what the spare can run, but no more at once than builders that could take it
	const int n = AiMin(bestN, AiMax(1, aiBuilderMgr.GetWorkerCount()));
	for (int k = 0; k < n; ++k)
		aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::CONVERT, Task::Priority::NORMAL, defs[best], basePos,
			SQUARE_SIZE * 48, true, 2 * MINUTE));
	pendingE += n * facts[best].capE;
	pendingUntil = ai.frame + 2 * MINUTE;
	ordered += n;
	AiLog("[ANV] Convert: +" + n + " " + defs[best].GetName() + " (spare " + int(spare) + " E/s, repays in "
		+ int(bestPay) + "s < horizon " + int(horizon) + "s)");
}

// The core sizes energy to a fixed multiple of metal income (economy.json "factor", 20x-60x), so it keeps
// assigning power plants while energy already overflows. At that moment a plant's marginal value is zero
// (its output is thrown away) and it costs metal; a T1 converter costs ~1 metal and turns the surplus into
// metal. So the builder takes the converter instead. Self-limiting: converters drain the storage, the
// overflow stops, and plants come back when energy is short again.
int swaps = 0;
IUnitTask@ Substitute(CCircuitUnit@ unit, IUnitTask@ task)
{
	if (task is null || task.GetType() != Task::Type::BUILDER || !HasBase())
		return task;
	IBuilderTask@ bt = cast<IBuilderTask>(task);
	if (bt is null || bt.GetBuildType() != Task::BuildType::ENERGY)
		return task;
	const SResourceInfo@ e = aiEconomyMgr.energy;
	if (!aiEconomyMgr.isEnergyFull || e.income <= e.pull || aiEconomyMgr.isMetalFull)
		return task;
	// cheapest converter by metal: the surplus is free, metal is what's short
	int best = -1;
	for (uint i = 0; i < defs.length(); ++i)
		if (defs[i].IsAvailable(ai.frame) && Facts::BuildOptions(unit.circuitDef.GetName()).find(defs[i].GetName()) >= 0
			&& (best < 0 || facts[i].costM < facts[best].costM))
			best = int(i);
	if (best < 0 || bt.buildDef is null || facts[best].costM >= bt.buildDef.costM)
		return task;
	++swaps;
	if (swaps % 10 == 1)
		AiLog("[ANV] Convert: energy overflowing, " + defs[best].GetName() + " instead of " + bt.buildDef.GetName() + " (swaps " + swaps + ")");
	return aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::CONVERT, Task::Priority::NORMAL, defs[best], basePos,
		SQUARE_SIZE * 48, true, MINUTE));
}

}  // namespace Convert

/* ======================================================================== */
/*
 * Energy, decided live. BARb sizes energy to a fixed multiple of metal income (20x-60x by the clock);
 * that curve is switched off in profile anarva_e, and this decides instead:
 *  - WHEN: a plant takes time to finish, and nothing pays until it's done. Watch net energy
 *    (income - pull) and the trend of pull. If, by the time a plant ordered now would be finished, the
 *    stock would already be empty, order now. Starving energy collapses everything (build power stops,
 *    extractors and converters stop), so the lead time is what matters, not the current balance.
 *  - WHICH: the plant with the lowest metal-equivalent cost per E/s whose build lead time still fits
 *    before the stock runs out; if none fits, the quickest one (stop the bleeding first).
 *  - HOW MANY: enough to cover the projected deficit.
 *  Surplus is not built for its own sake: real surplus goes to converters (Brain::Convert).
 */
namespace Energy {

array<CCircuitDef@> plants;
float prevPull = 0.f, trend = 0.f;   // E/s per second, smoothed
float pendingE = 0.f;
int pendingUntil = 0, orders = 0, lastLog = 0;

void Init()
{
	array<string> names = {"armsolar", "corsolar", "legsolar", "armadvsol", "coradvsol", "legadvsol",
		"armfus", "corfus", "legfus", "armafus", "corafus", "legafus"};
	for (uint i = 0; i + 2 < names.length(); i += 3) {
		CCircuitDef@ d = Brain::Strategic::Side(names[i], names[i + 1], names[i + 2]);  // our faction only
		if (d !is null && aiEconomyMgr.GetEnergyMake(d) > 0.f)
			plants.insertLast(d);
	}
}

const float MM_LEVEL = 0.75f;  // game fact: converters run while energy storage is above 75% (mmLevel)

void Update()  // every second
{
	const SResourceInfo@ e = aiEconomyMgr.energy;
	trend = 0.95f * trend + 0.05f * (e.pull - prevPull);   // ~20 s smoothing of how fast demand grows
	prevPull = e.pull;
	if (!HasBase() || ai.frame % (5 * SECOND) != 0)
		return;
	if (ai.frame > pendingUntil)
		pendingE = 0.f;
	// above the converters' threshold the game already treats energy as surplus: no plant is needed
	if (e.current > MM_LEVEL * e.storage)
		return;
	const int workers = AiMax(1, aiBuilderMgr.GetWorkerCount());
	CCircuitDef@ best = null;
	float bestCost = 1e9f, quickLead = 1e9f, need = 0.f;
	CCircuitDef@ quick = null;
	// lead time: build time at the build power that would take it (a share of our builders)
	for (uint i = 0; i < plants.length(); ++i) {
		const float lead = BuildTime(plants[i]) / (Brain::Convert::CON_WORK * AiMax(1.f, float(workers) * 0.5f));
		if (plants[i].IsAvailable(ai.frame) && lead < quickLead) { quickLead = lead; @quick = plants[i]; }
	}
	for (uint i = 0; i < plants.length(); ++i) {
		CCircuitDef@ d = plants[i];
		if (!d.IsAvailable(ai.frame))
			continue;
		const float lead = BuildTime(d) / (Brain::Convert::CON_WORK * AiMax(1.f, float(workers) * 0.5f));
		const float net = e.income + pendingE - e.pull - AiMax(0.f, trend) * lead;
		const float toEmpty = net < 0.f ? e.current / -net : 1e9f;
		// not yet: the stock outlasts this plant's lead plus the time the fastest plant needs to cover a miss
		if (toEmpty > lead + quickLead)
			continue;
		const float make = aiEconomyMgr.GetEnergyMake(d);
		const float cost = Brain::Economist::MetalValue(d) / make;
		if (toEmpty >= lead && cost < bestCost) {
			bestCost = cost;
			@best = d;
			need = -net;
		} else if (best is null && need <= 0.f) {
			need = -net;
		}
	}
	if (need <= 0.f)
		return;
	if (best is null)
		@best = quick;  // nothing finishes in time: the fastest plant first
	if (best is null)
		return;
	const float make = aiEconomyMgr.GetEnergyMake(best);
	const int n = AiMin(AiMax(1, int(ceil(need / make))), workers);
	for (int k = 0; k < n; ++k)
		aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::ENERGY, Task::Priority::HIGH, best, basePos, SQUARE_SIZE * 40, true, 2 * MINUTE));
	pendingE += n * make;
	pendingUntil = ai.frame + 2 * MINUTE;
	orders += n;
	AiLog("[ANV] Energy: +" + n + " " + best.GetName() + " (net " + int(e.income - e.pull) + " E/s, trend +" + F1(trend) + "/s, stock "
		+ int(e.current) + ")");
}

// build time from the unit facts (the API doesn't expose it): solar ~2600, adv solar ~8000, fusion ~55000, afus ~320000
float BuildTime(const CCircuitDef@ d)
{
	const string n = d.GetName();
	if (n.findFirst("afus") >= 0) return 320000.f;
	if (n.findFirst("fus") >= 0) return 56000.f;
	if (n.findFirst("advsol") >= 0) return 8000.f;
	return 2700.f;
}

}  // namespace Energy

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
	const float elapsed = AiMax(float(ai.frame) / SECOND, 60.f);
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
 * Redirect build power: the share of constructor build power that should serve the army equals the
 * army deficit (1 - ours/needed). Those builders get guard (assist) tasks on factories, so production
 * speeds up exactly as much as the deficit demands; with a surplus they return to eco work.
 */
namespace Redirect {

array<IUnitTask@> guards;
array<int> guardUntil;
int issued = 0;
const int GUARD_SPAN = 45 * SECOND;  // re-evaluated every update; this is only the task lifetime

void Update()
{
	for (int i = int(guards.length()) - 1; i >= 0; --i) {
		if (ai.frame > guardUntil[i]) {
			guards.removeAt(i);
			guardUntil.removeAt(i);
		}
	}
	const array<CCircuitUnit@>@ facs = Brain::Intel::allFactories;
	if (facs.length() == 0 || aiEconomyMgr.isMetalEmpty || aiEconomyMgr.isEnergyStalling)
		return;  // assisting with an empty bank (or no energy) only slows everything down
	const float deficit = AiMax(0.f, 1.f - Brain::Director::ratio);
	const int want = int(float(aiBuilderMgr.GetWorkerCount()) * deficit + 0.5f);
	while (int(guards.length()) < want) {
		CCircuitUnit@ fac = facs[issued % int(facs.length())];  // spread assist over the factories in turn (deterministic)
		IUnitTask@ g = aiBuilderMgr.Enqueue(TaskB::Guard(Task::Priority::HIGH, fac, true, GUARD_SPAN));
		if (g is null)
			break;
		guards.insertLast(g);
		guardUntil.insertLast(ai.frame + GUARD_SPAN);
		++issued;
	}
}

string Status() { return "assist=" + guards.length() + "/" + issued; }

}  // namespace Redirect

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
		ok = payback < H || forced || Brain::Waste::metalOverflow;
		why = "payback " + int(payback) + "s vs horizon " + int(H) + "s" + (forced ? ", enemy teched" : "");
	} else {
		// T3: when T2 production can no longer absorb our income (it overflows), or the enemy fields
		// super units while we're not ahead and must answer in kind.
		const bool enemySuper = aiEnemyMgr.GetEnemyCost(RT::SUPER) > 0.f && Brain::Director::ratio < 1.f;
		ok = Brain::Waste::metalOverflow || enemySuper;
		why = Brain::Waste::metalOverflow ? "income overflows T2 production" : (enemySuper ? "enemy fields super units" : "T2 still absorbs our income");
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
float killedHome = 0.f, killedAway = 0.f, tradeHome = 1.f, tradeAway = 1.f;
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
	if (F_TERRAIN)
		Brain::Strategic::OnTerrainLoss(unit.GetPos(ai.frame), d.costM);
	const bool home = F_ZONES ? OnOurSide(unit.GetPos(ai.frame)) : dist < 1500.f;
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
	lostNear *= 0.992f;  // half-life ~85 s
	lostFar *= 0.992f;
	killed *= 0.992f;
	killedHome *= 0.992f;
	killedAway *= 0.992f;
	if (F_ZONES) TrackKills();
	const float ev = EnemyValue();
	if (enemyPrev >= 0.f && ev < enemyPrev) {
		killed += AiMin(enemyPrev - ev, 3000.f);  // drops in known enemy value ~ our kills
		killedTotal += AiMin(enemyPrev - ev, 3000.f);
	}
	enemyPrev = ev;
	const float lost = lostNear + lostFar;
	// Evidence weighted by the stake: exchanges small next to the army we'd be risking can't swing the
	// estimate (a few cheap kills once turned 0.7 into 5.1 and launched an all-in), real exchanges do.
	const float stake = F_STAKE ? AiMax(50.f, Brain::Strategic::armyMetal) : 50.f;
	trade = (killed + stake) / (lost + stake);
	tradeHome = (killedHome + stake) / (lostNear + stake);
	tradeAway = (killedAway + stake) / (lostFar + stake);
	pushedBack = lostNear > 300.f && lostNear > 1.5f * lostFar;
	pushing = lostFar > 300.f && lostFar > 2.f * lostNear && frontDist > 1800.f;

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
		+ " home/away trade=" + F1(tradeHome) + "/" + F1(tradeAway) + " kill(h/a)=" + int(killedHome) + "/" + int(killedAway)
		+ " lost(n/f)=" + int(lostNear) + "/" + int(lostFar) + " front=" + int(frontDist) + " growth3m=" + int(growth * 100.f) + "%";
}

}  // namespace Assess

/* ======================================================================== */
/*
 * Director: every few seconds, ask "what is the next reasonable move?". It weighs our army against
 * the enemy's known mobile threat, our economy and the clock, picks a posture, and logs why.
 * The other modules read the posture.
 */
namespace Director {

enum Posture { BOOM = 0, HOLD, BALANCED, PRESSURE, ALLIN, TURTLE }
array<string> names = {"BOOM", "HOLD", "BALANCED", "PRESSURE", "ALLIN", "TURTLE"};

Posture posture = BOOM;
Posture pending = BOOM;
int pendingSince = 0;
float waveFrac = 0.30f;
float ratio = 1.f;
float baseBP = -1.f;     // core's constructor-vs-army knob (economy.buildpower)
float scale = 1.f;       // multiplier we apply to it
/*
 * Expansion demand. The core sizes build power to income, a loop that keeps a small economy small.
 * The real question: is one more constructor worth its cost? n constructors take F free extractor spots
 * in F*t/n seconds (t = one trip: walk the spot spacing + build the extractor). The metal a spot yields
 * while still unclaimed is lost, so the expansion loss is about s*F^2*t/(2n) (s = one spot's income).
 * One more constructor cuts it by s*F^2*t/(2n^2); that beats its cost c while n < F*sqrt(s*t/(2c)).
 * Every input is a game fact or a live measurement: spots from the map analysis (our fair share =
 * map extractors / players), speed and cost from the constructor's def, s from our own extractors.
 */
float expandWant = 0.f;
void Expand()
{
	MapFacts::SMap@ m = Brain::Production::mapInfo;
	CCircuitDef@ con = Brain::Strategic::Side("armck", "corck", "legck");
	const float income = aiEconomyMgr.metal.income;
	if (m is null || m.mex <= 0 || con is null || income <= 0.f)
		return;
	const float ours = float(Brain::Economist::mexes.length());
	// Free spots, counted live (C++ bridge): open (not ours, not queued), not under a known enemy
	// extractor, and safe for a constructor right now. No "fair share": a free spot is worth the same
	// whether we hold a third of the map or half of it.
	const float F = FreeSpots(con);
	if (F <= 0.f) {
		expandWant = 0.f;
		return;
	}
	float speed = con.speed;               // elmos per frame in the core
	if (speed < 10.f) speed *= SECOND;     // -> elmos per second
	const float spacing = AiMax(1.f, m.straight) / sqrt(float(m.mex));
	const float t = spacing / AiMax(1.f, speed) + MEX_BUILDTIME / (Brain::Production::BUILD_SPEED_PER_WORKER * 20.f);
	const float s = ours > 0.f ? AiMax(0.5f, income / ours) : 1.f;  // upper bound: includes reclaim/makers
	const float c = Brain::Economist::MetalValue(con);
	expandWant = F * sqrt(s * t / (2.f * c));
	// (danger is already per spot: threatened spots are not counted as free)
	// the core adds a constructor while workers' build power < income * ratio
	const float coreWorkers = income * aiFactoryMgr.buildpowerRatio / Brain::Production::BUILD_SPEED_PER_WORKER;
	const float want = AiMax(coreWorkers, expandWant + income * baseBP / Brain::Production::BUILD_SPEED_PER_WORKER);
	aiFactoryMgr.buildpowerRatio = want * Brain::Production::BUILD_SPEED_PER_WORKER / income;
}
const float MEX_BUILDTIME = 1800.f;  // T1 extractor buildtime (unit facts)

uint freeSpots = 0, enemySpots = 0, unsafeSpots = 0;
float FreeSpots(CCircuitDef@ con)
{
	array<AIFloat3> sp; array<float> si; array<bool> so;
	const uint n = AiGetMetalSpots(sp, si, so);
	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
	const uint ne = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	array<AIFloat3> emex, estatic;
	for (uint i = 0; i < ne; ++i) {
		if (ed[i] is null || ed[i].IsMobile()) continue;
		estatic.insertLast(ep[i]);
		const string nm = ed[i].GetName();
		if (nm.findFirst("mex") >= 0 || nm.findFirst("moho") >= 0) emex.insertLast(ep[i]);
	}
	if (estatic.length() == 0) estatic.insertLast(aiEnemyMgr.GetEnemyPos());  // the core's estimate of where they are
	// How holdable a spot is: the share of the way from the nearest enemy building to us that lies on
	// their side, dE/(dU+dE). Our half of the map counts most, their doorstep almost nothing; more enemy
	// bases shrink our side by themselves. No cutoff.
	freeSpots = 0; enemySpots = 0; unsafeSpots = 0;
	float holdable = 0.f;
	for (uint k = 0; k < n; ++k) {
		if (!so[k]) continue;
		bool held = false;
		for (uint j = 0; j < emex.length() && !held; ++j) held = emex[j].distance2D(sp[k]) < 64.f;  // an extractor sits on its spot
		if (held) { ++enemySpots; continue; }
		if (aiThreat.GetThreatAt(con, sp[k]) > 0.f) { ++unsafeSpots; continue; }
		++freeSpots;
		const float dU = basePos.distance2D(sp[k]);
		float dE = 1e9f;
		for (uint j = 0; j < estatic.length(); ++j) dE = AiMin(dE, estatic[j].distance2D(sp[k]));
		holdable += dE / AiMax(1.f, dU + dE);
	}
	return holdable;
}

string scaleWhy = "";
bool blind = false;
string reason = "start";

float PoolPower() { return Brain::Army::groundPower + Brain::Army::raiderPoolPower; }
// Everything of ours that fights on the surface. The gather pool alone drops every unit with a support,
// artillery or AA secondary role, which is most of a mixed army: measured 48 vs ~11k metal fielded.
float allPower = 0.f, allCost = 0.f, allSpeed = 0.f;
int allPowerFrame = -1;
float MeasuredPower()
{
	if (allPowerFrame == ai.frame) return allPower;
	allPowerFrame = ai.frame;
	allPower = 0.f; allCost = 0.f; allSpeed = 0.f; uint cnt = 0;
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	for (uint i = 0; i < all.length(); ++i) {
		const CCircuitDef@ d = all[i].circuitDef;
		if (!d.IsMobile() || d.power <= 0.f || d.surfThrDmg <= 0.f || all[i] is commander) continue;
		if (d.IsRoleAny(Unit::Role::BUILDER.mask)) continue;
		allPower += d.power;
		allCost += d.costM;
		allSpeed += d.speed; ++cnt;
	}
	if (cnt > 0) allSpeed /= float(cnt);
	return allPower;
}
float OurPower() { return F_POWERALL ? MeasuredPower() : PoolPower(); }

/*
 * Just in time (STRATEGY 29). An army that is far away is no threat yet: what matters is whether we can
 * have the answer by the time it gets here. Each armed enemy reaches our nearest asset at
 * t = (distance - its range) / its speed (worst case: it heads straight for us). Unseen strength arrives
 * from the enemy's centre. At every arrival time we compare what we'll have (our power now plus what our
 * income can still turn into army by then) with what has arrived (at our trade rate). The worst moment
 * is the ratio that decides how much goes into the economy now.
 */
float jitRatio = 0.f, jitWorstT = 0.f;
float JitRatio(float ours, float theirs, float trade)
{
	array<AIFloat3> assets;
	if (HasBase()) assets.insertLast(basePos);
	const array<CCircuitUnit@>@ mx = Brain::Economist::mexes;
	for (uint m = 0; m < mx.length(); ++m) assets.insertLast(mx[m].GetPos(ai.frame));
	const array<CCircuitUnit@>@ fa = Brain::Intel::allFactories;
	for (uint f = 0; f < fa.length(); ++f) assets.insertLast(fa[f].GetPos(ai.frame));
	if (assets.length() == 0) return ours / AiMax(1.f, theirs / trade);

	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
	const uint n = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	array<float> ts, th;
	float seen = 0.f, speedSum = 0.f; uint moving = 0;
	for (uint i = 0; i < n; ++i) {
		CCircuitDef@ d = ed[i];
		if (d is null || !d.IsMobile() || d.threat <= 0.f || (ef[i] & 4) != 0) continue;
		float dmin = 1e9f;
		for (uint a = 0; a < assets.length(); ++a) dmin = AiMin(dmin, ep[i].distance2D(assets[a]));
		const float t = MoveTime(d, AiMax(0.f, dmin - d.GetMaxRange()));
		uint k = 0; while (k < ts.length() && ts[k] < t) ++k;
		ts.insertAt(k, t); th.insertAt(k, d.threat);
		seen += d.threat; speedSum += d.speed; ++moving;
	}
	// what we believe exists but don't see: from their centre at their mean speed
	const float hidden = AiMax(0.f, theirs - seen);
	if (hidden > 0.f) {
		const AIFloat3 ec0 = aiEnemyMgr.GetEnemyPos();
		float dmin = 1e9f;
		for (uint a = 0; a < assets.length(); ++a) dmin = AiMin(dmin, ec0.distance2D(assets[a]));
		const float sp = moving > 0 ? speedSum / moving : AiMax(1.f, allSpeed);
		const float t = dmin / AiMax(1.f, sp);
		uint k = 0; while (k < ts.length() && ts[k] < t) ++k;
		ts.insertAt(k, t); th.insertAt(k, hidden);
	}
	// how fast income turns into power: our own army's power per metal
	MeasuredPower();
	const float perMetal = allCost > 0.f ? allPower / allCost : 0.f;
	const float rate = aiEconomyMgr.metal.income * perMetal;  // power per second at full army production
	float worst = 1e9f, cum = 0.f;
	jitWorstT = 0.f;
	for (uint k = 0; k < ts.length(); ++k) {
		cum += th[k];
		const float r = (ours + rate * ts[k]) / AiMax(1.f, cum / trade);
		if (r < worst) { worst = r; jitWorstT = ts[k]; }
	}
	return worst < 1e9f ? worst : ours / AiMax(1.f, theirs / trade);
}


float needPowerAway = 0.f;
float needPower = 0.f;   // army power needed to win against what we know (and guess) is out there

void Update()
{
	const float ours = OurPower();
	if (baseBP < 0.f)
		baseBP = aiFactoryMgr.buildpowerRatio;
	const float enemyStatic = aiEnemyMgr.GetEnemyCost(RT::STATIC);
	blind = aiEnemyMgr.mobileThreat <= 1.f && enemyStatic <= 0.f;

	// What we must be able to beat: the known (or, when blind, assumed) enemy army plus the army we
	// guess is hidden under seen jammers, divided by how efficiently we are actually trading.
	float theirs = Brain::Economist::EnemyThreat() + aiEnemyMgr.GetEnemyThreat(RT::JAMMER);
	// Napoleon: several enemies are several armies. Beat them one at a time before they combine.
	if (F_DETAIL)
		theirs /= float(AiMax(1, ai.GetEnemyTeamSize()));
	needPower = theirs / AiMax(0.25f, Brain::Assess::trade);  // 0.25: numeric guard, not a tuning knob
	needPowerAway = theirs / AiMax(0.25f, Brain::Assess::tradeAway);  // what an attack must bring, at the trade we get away
	ratio = ours / AiMax(1.f, needPower);

	/*
	 * Constructors vs army, continuously: surplus power over what we need goes into scaling, a deficit
	 * into army. The factory adds a constructor while buildpower < income * buildpowerRatio.
	 * Income spilling out of full storage means we lack spending power: more builders.
	 */
	// A deficit far from home is no reason to starve the economy (the only way back); only a deficit at
	// home is. So we cut scaling only while pushed back, and add to it with surplus.
	if (Brain::Assess::pushedBack) {
		scale = AiMin(1.f, AiMax(0.35f, ratio));
		scaleWhy = "pushed back with a deficit: army first";
	} else if (F_BOOM) {
		/*
		 * Humans beat several hard BARbs by booming: BARb armies gather at home and don't punish
		 * greed, so an army sitting in their base is no threat to us. What matters is force projected
		 * AT us: metal we lose near home, relative to what we earn. Pressure p = home losses /
		 * (home losses + a minute of income); scale toward eco by (1 - p).
		 */
		const float income60 = aiEconomyMgr.metal.income * 60.f;
		const float p = Brain::Assess::lostNear / AiMax(1.f, Brain::Assess::lostNear + income60);
		scale = AiMin(2.f, AiMax(1.f, ratio) * (1.f + (1.f - p)));
		scaleWhy = "boom: home pressure " + int(p * 100.f) + "%";
	} else {
		if (F_JIT) {
			jitRatio = JitRatio(ours, theirs, AiMax(0.25f, Brain::Assess::trade));
			scale = AiMin(2.f, AiMax(1.f, jitRatio));
		} else
			scale = AiMin(2.f, AiMax(1.f, ratio));
		scaleWhy = blind ? "blind: assume enemy kept pace" : (ratio >= 1.f ? "surplus power: scale" : "deficit away from home: keep the economy growing");
	}
	if (Brain::Waste::metalOverflow) {
		scale = AiMin(2.f, AiMax(scale, 1.f) * (1.f + float(Brain::Waste::metalSec) / 60.f));
		scaleWhy = "metal overflowing: more build power";
	}
	if (F_SCALE)
		aiFactoryMgr.buildpowerRatio = baseBP * scale;
	if (F_EXPAND && !Brain::Assess::pushedBack)
		Expand();
	if (F_SCOUT)
		aiMilitaryMgr.quota.scout = AiMax(int(aiMilitaryMgr.quota.scout), blind ? 4 : 3);

	// (see Expand)
	// Waves are sized to win: the gather completes when it holds the power needed.
	waveFrac = (Brain::Army::groundPower > 0.f) ? AiMin(1.f, needPower / Brain::Army::groundPower) : 1.f;

	// Posture is now only a label for the logs (and "can't win an open fight" for Fortify).
	Posture want = ratio < 0.5f ? TURTLE : (ratio < 1.f ? HOLD : (ratio < 1.5f ? BALANCED : (ratio < 3.f ? PRESSURE : ALLIN)));
	if (want != pending) {
		pending = want;
		pendingSince = ai.frame;
	}
	if (want != posture && ai.frame - pendingSince >= 10 * SECOND) {  // log hygiene only
		AiLog("[ANV] Director: " + names[posture] + " -> " + names[want] + " (power " + int(ours) + " vs needed " + int(needPower)
			+ ", trade " + F1(Brain::Assess::trade) + (Brain::Assess::pushedBack ? ", pushed back" : "") + (blind ? ", blind" : "") + ")");
		posture = want;
	}
}
string Status() { return names[posture] + " r=" + F1(ratio) + (F_JIT ? " jit=" + F1(jitRatio) + "@" + int(jitWorstT) + "s" : "") + " wave=" + F1(waveFrac) + " bp=" + F1(scale) + "(" + scaleWhy + ")"; }

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
	Eco::Init();
	Production::Init();
	Production::LookAtMap();
	Waste::Init();
	Economist::Init();
	Convert::Init();
	Energy::Init();
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
	if (F_TERRAIN && Strategic::terrainDef !is null && unit.circuitDef is Strategic::terrainDef) {
		++Strategic::terrainBuilt;
		Strategic::terrainPower += unit.circuitDef.power;
		Strategic::terrainMetal += unit.circuitDef.costM;
	}
	if (IsArmy(unit.circuitDef))
		Strategic::armyMetal += unit.circuitDef.costM;
	if (Strategic::mlvDef !is null && unit.circuitDef is Strategic::mlvDef)
		++Strategic::minelayers;
	Economist::OnFinished(unit);
	Production::OnFinished(unit);
	if (F_CONVERT) Convert::OnFinished(unit);
}

CCircuitUnit@ commander = null;
int commRedirects = 0;

/*
 * The commander is the win condition: a far-off building gains a little metal, losing the commander
 * loses the game. So it only takes work inside the zone our army can protect, measured from where
 * fights actually happen (half the distance to the front; the map's base-to-base path early on).
 * Work outside stays queued for cheap constructors; the commander assists a factory at home instead.
 */
IUnitTask@ CommanderTask(CCircuitUnit@ comm, IUnitTask@ task)
{
	if (task is null || !HasBase() || task.GetType() != Task::Type::BUILDER || Brain::Intel::allFactories.length() == 0)
		return task;
	IBuilderTask@ bt = cast<IBuilderTask>(task);
	if (bt is null)
		return task;
	if (F_COMMRISK) {
		if (CommWorth(bt.GetBuildPos(), JobValue(bt)))
			return task;
		++commRedirects;
		IUnitTask@ safe = CommSafeJob(comm.GetPos(ai.frame));
		return safe is null ? task : safe;
	}
	if (F_COMMGUARD) {
		const AIFloat3 bp = bt.GetBuildPos();
		CCircuitUnit@ home = NearestFactory(bp);
		const float tHome = home.GetPos(ai.frame).distance2D(bp) / AiMax(1.f, comm.circuitDef.speed);
		if (CommExposure(bp, tHome) <= 0.f)
			return task;
		++commRedirects;
		return aiBuilderMgr.Enqueue(TaskB::Guard(Task::Priority::HIGH, F_COMMSPOT ? CommRefuge(comm.GetPos(ai.frame)) : NearestFactory(comm.GetPos(ai.frame)), true, 20 * SECOND));
	}
	if (F_COMMZONE) {
		/*
		 * The commander is the game. It only takes work closer to home than the nearest place where we
		 * have lost anything recently (the loss heat map; a cell counts while at least one metal of losses
		 * there hasn't decayed away), and never inside such a cell. Where nothing has died, nothing has
		 * reached. Work beyond stays queued for constructors, which are cheap to lose.
		 */
		const AIFloat3 bp = bt.GetBuildPos();
		const float d = basePos.distance2D(bp);
		float danger = 1e9f;
		for (uint c = 0; c < Brain::Intel::heat.length(); ++c)
			if (Brain::Intel::heat[c] >= 1.f)
				danger = AiMin(danger, Brain::Intel::CellCenter(int(c)).distance2D(basePos) - Brain::Intel::CELL);
		if (d < danger && Brain::Intel::heat[Brain::Intel::CellOf(bp)] < 1.f)
			return task;
	} else {
		float front = Brain::Assess::frontDist;
		if (front <= 0.f && Brain::Production::mapInfo !is null && Brain::Production::mapInfo.basePath > 0.f)
			front = Brain::Production::mapInfo.basePath * 0.5f;
		if (front <= 0.f)
			return task;  // no idea where the fighting is yet (opening): let it build
		if (basePos.distance2D(bt.GetBuildPos()) <= 0.5f * front)
			return task;
	}
	++commRedirects;
	CCircuitUnit@ fac = FactoryReachedSoonest(comm.GetPos(ai.frame), comm.circuitDef);
	return aiBuilderMgr.Enqueue(TaskB::Guard(Task::Priority::HIGH, fac, true, 30 * SECOND));
}

/*
 * Commander guard (C++ bridge). Losing the commander loses the game, so the only question is: could a
 * known enemy force that out-guns what can protect it get to it before it gets home? Enemies count
 * by their top speed, not their current heading (they can turn); protectors count when they can reach
 * the commander in the same time. If danger exceeds protection the commander goes home now. The same
 * test is run on a build site before the commander walks to it. No zone, no distance limit.
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
 * Chain loss: metal of ours destroyed if something with a death explosion (radius R, damage D) dies at p.
 * A unit at distance d takes ~D*(1-d/R); if that exceeds its health it dies and its own explosion
 * propagates. Converters, fusions, nanos and commanders packed together are one bomb.
 */
float ChainLoss(const AIFloat3& in p, float R, float D, CCircuitUnit@ skip)
{
	if (R <= 0.f || D <= 0.f) return 0.f;
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	const uint n = all.length();
	array<bool> dead(n, false);
	array<AIFloat3> qp = {p}; array<float> qr = {R}, qd = {D};
	float loss = 0.f;
	for (uint q = 0; q < qp.length() && q < 64; ++q) {
		for (uint i = 0; i < n; ++i) {
			if (dead[i] || all[i] is skip) continue;
			const float d = all[i].GetPos(ai.frame).distance2D(qp[q]);
			if (d >= qr[q]) continue;
			const CCircuitDef@ u = all[i].circuitDef;
			if (qd[q] * (1.f - d / qr[q]) < u.health) continue;
			dead[i] = true;
			loss += u.costM;
			if (u.deathAoe > 0.f && u.deathDamage > 0.f) {
				qp.insertLast(all[i].GetPos(ai.frame)); qr.insertLast(u.deathAoe); qd.insertLast(u.deathDamage);
			}
		}
	}
	return loss;
}

// Where the commander should wait out danger: something of ours to guard (factory or defence) that it can
// reach before an enemy that out-guns the cover there, and where its own death would cost the least.
CCircuitUnit@ CommRefuge(const AIFloat3& in from)
{
	CCircuitUnit@ best = null, leastBad = null;
	float bestLoss = 1e9f, bestT = 1e9f, leastExp = 1e9f;
	const float R = commander.circuitDef.deathAoe, D = commander.circuitDef.deathDamage;
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	for (uint i = 0; i < all.length(); ++i) {
		CCircuitUnit@ g = all[i];
		const CCircuitDef@ d = g.circuitDef;
		if (d.IsMobile() || g is commander) continue;
		if (!d.IsRoleAny(Unit::Role::STATIC.mask) && Brain::Intel::allFactories.findByRef(g) < 0) continue;
		if (Brain::Intel::allFactories.findByRef(g) < 0 && d.power <= 0.f) continue;  // defences and factories only
		const AIFloat3 q = g.GetPos(ai.frame);
		const float t = q.distance2D(from) / AiMax(1.f, commander.circuitDef.speed);
		const float exp = CommExposure(q, t);
		if (exp < leastExp) { leastExp = exp; @leastBad = g; }
		if (exp > 0.f) continue;
		const float loss = ChainLoss(q, R, D, commander);
		if (loss < bestLoss || (loss == bestLoss && t < bestT)) { bestLoss = loss; bestT = t; @best = g; }
	}
	if (best !is null) { lastRefugeLoss = bestLoss; return best; }
	return leastBad !is null ? leastBad : NearestFactory(from);
}
float lastRefugeLoss = 0.f;


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
	if (!F_COMMFOG) return 0.f;
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
	if (!F_RECLAIM) return;
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
		IUnitTask@ t = aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::HIGH, wp[i], R, 2 * MINUTE));
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
	if (!F_BUILDERSAFE) return;
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
	return aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::HIGH, bestP, R, 20 * SECOND));
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
	if (!F_COMMFWD || Brain::Economist::mexT1 is null) return null;
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

// enemy threat able to reach p within the commander's trip home from p, minus what can cover it there
float CommExposure(const AIFloat3& in p, float tHome)
{
	array<AIFloat3> ep, ev; array<CCircuitDef@> ed; array<float> ec, eh, eb; array<int> ef;
	const uint n = AiGetEnemies(ep, ev, ed, ec, ef, eh, eb);
	float danger = 0.f;
	for (uint i = 0; i < n; ++i) {
		CCircuitDef@ d = ed[i];
		if (d is null || d.threat <= 0.f || (ef[i] & 4) != 0) continue;
		const float reach = AiMax(0.f, ep[i].distance2D(p) - d.GetMaxRange());
		if (!d.IsMobile()) { if (reach <= 0.f) danger += d.threat; continue; }
		if (MoveTime(d, reach) <= tHome) danger += d.threat * eh[i];
	}
	if (F_COMMFOG) {
		float seenT = 0.f, seenS = 0.f; uint seenN = 0;
		for (uint i = 0; i < n; ++i) if (ed[i] !is null && ed[i].IsMobile() && ed[i].threat > 0.f) { seenT += ed[i].threat; seenS += ed[i].speed; ++seenN; }
		danger += CommFog(p, tHome, seenT, seenS, seenN);
	}
	float cover = commander.circuitDef.power;
	const array<CCircuitUnit@>@ all = AiGetTeamUnits();
	for (uint i = 0; i < all.length(); ++i) {
		CCircuitUnit@ u = all[i];
		const CCircuitDef@ d = u.circuitDef;
		if (u is commander || d.power <= 0.f || d.IsRoleAny(Unit::Role::BUILDER.mask)) continue;
		const float dist = u.GetPos(ai.frame).distance2D(p);
		if (d.IsMobile() ? (MoveTime(d, dist) <= tHome) : (dist <= d.GetMaxRange()))
			cover += d.power;
	}
	return danger - cover;
}

void CommGuardUpdate()
{
	if (commander is null || Brain::Intel::allFactories.length() == 0) return;
	if (commGuardTask !is null && commander.task is commGuardTask) return;
	const AIFloat3 c = commander.GetPos(ai.frame);
	if (F_COMMRISK) {
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
		return;
	}
	CCircuitUnit@ home = NearestFactory(c);
	const float tHome = MoveTime(commander.circuitDef, home.GetPos(ai.frame).distance2D(c));
	if (CommExposure(c, tHome) <= 0.f) return;
	if (F_COMMSPOT) {
		@home = CommRefuge(c);
		AiLog("[ANV] CommGuard: refuge " + home.circuitDef.GetName() + " chainLoss=" + int(lastRefugeLoss) + " commBlast=" + int(commander.circuitDef.deathAoe) + "/" + int(commander.circuitDef.deathDamage));
	}
	@commGuardTask = aiBuilderMgr.Enqueue(TaskB::Guard(Task::Priority::HIGH, home, true, 20 * SECOND));
	aiBuilderMgr.AssignTask(commander, commGuardTask);
	++commGuards;
}

void OnUnitDestroyed(CCircuitUnit@ unit)
{
	if (unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask)) {
		const AIFloat3 p = unit.GetPos(ai.frame);
		AiLog("[ANV] COMMANDER LOST at (" + int(p.x) + "," + int(p.z) + ") dist-from-base=" + int(HasBase() ? basePos.distance2D(p) : -1.f)
			+ " task=" + (unit.task is null ? -1 : int(unit.task.GetType())) + " t=" + Minute() + "m posture=" + Director::names[Director::posture]);
		@commander = null;
	}
	if (Strategic::mlvDef !is null && unit.circuitDef is Strategic::mlvDef)
		Strategic::minelayers = AiMax(0, Strategic::minelayers - 1);
	if (F_TERRAIN && Strategic::terrainDef !is null && unit.circuitDef is Strategic::terrainDef)
	{
		Strategic::terrainPower = AiMax(0.f, Strategic::terrainPower - unit.circuitDef.power);
		Strategic::terrainMetal = AiMax(0.f, Strategic::terrainMetal - unit.circuitDef.costM);
	}
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
	aiSwitchHighGroundArty = F_ARTYHIGH;
	aiSwitchHeightSquads = F_HEIGHTSQUAD;
	aiSwitchScoutMap = F_SCOUTMAP;
	aiSwitchEngageSeen = F_ENGAGE;
	if (F_INTEL) Intel::Update();
	Assess::Update();
	if (F_WASTE) Waste::Update();
	if (F_CONVERT) Convert::Update();
	if (F_ENERGY) Energy::Update();
	Director::Update();
	if (F_QUOTA) Army::Update(Intel::jamAlert);
	else Army::CheckSquads();
	if (ai.frame % (2 * SECOND) < SECOND) {
		if (F_RECYCLE) Recycler::Update();
		if (F_ECOGATE) Eco::Update();
	}
	if (F_REDIRECT && ai.frame % (5 * SECOND) < SECOND)
		Redirect::Update();
	if (F_STRAT && ai.frame % (10 * SECOND) < SECOND)
		Strategic::Update(Intel::jamAlert);
	if (F_HOLD && ai.frame % (3 * SECOND) < SECOND)
		Hold::Update();
	if (F_SCOUTMAP && ai.frame % (3 * SECOND) < SECOND)
		Scout::Update();
	if (F_STORAGE && ai.frame % (5 * SECOND) < SECOND)
		Storage::Update();
	if (F_COMMGUARD && ai.frame % (2 * SECOND) < SECOND)
		CommGuardUpdate();
	if (F_BUILDERSAFE && ai.frame % (2 * SECOND) < SECOND)
		BuilderSafeUpdate();
	if (F_RECLAIM && ai.frame % (5 * SECOND) < SECOND)
		ReclaimUpdate();

	if (ai.frame % MINUTE < SECOND) {
		if (commander !is null) {
			const AIFloat3 cp = commander.GetPos(ai.frame);
			AiLog("[ANV] commander at (" + int(cp.x) + "," + int(cp.z) + ") dist-from-base=" + int(HasBase() ? basePos.distance2D(cp) : -1.f)
				+ " task=" + (commander.task is null ? -1 : int(commander.task.GetType())) + " redirects=" + commRedirects + " guards=" + commGuards + " reclaimOrders=" + reclaimOrders + " builderEvacs=" + builderEvacs + " retreats=" + commRetreats + " frontReclaims=" + commReclaims + " fwdClaims=" + commFwd + " fwdFailed=" + fwdFailed + " fwd(calls/busy/none)=" + fwdCalls + "/" + fwdBusy + "/" + fwdNone + " fwdBest=" + int(fwdBestSeen) + " vs cur " + int(fwdCurSeen));
		}
		if (F_SCOUTMAP) AiLog("[ANV] " + Scout::Status());
		AiLog("[ANV] eco t=" + Minute() + "m workers=" + aiBuilderMgr.GetWorkerCount() + " mex=" + Economist::mexes.length()
			+ " M inc=" + F1(aiEconomyMgr.metal.income) + " M " + int(aiEconomyMgr.metal.current) + "/" + int(aiEconomyMgr.metal.storage)
			+ " E inc=" + F1(aiEconomyMgr.energy.income) + " E " + int(aiEconomyMgr.energy.current) + "/" + int(aiEconomyMgr.energy.storage)
			+ " stall=" + aiEconomyMgr.isEnergyStalling + " expandWant=" + F1(Director::expandWant) + " spots(free/enemy/unsafe)=" + Director::freeSpots + "/" + Director::enemySpots + "/" + Director::unsafeSpots + " bpTarget=" + F1(aiEconomyMgr.metal.income * aiFactoryMgr.buildpowerRatio));
		Intel::BridgeLog();
		if (F_HOLD) AiLog("[ANV] hold " + Hold::Status());

		AiLog("[ANV] t=" + Minute() + "m " + Director::Status() + " | " + Assess::Status() + " | groundPow=" + F1(Army::groundPower) + " allPow=" + F1(Director::MeasuredPower()) + " units=" + Army::ground.length()
			+ " raiders=" + Army::raiders.length() + " squads=" + Army::squads.length() + " waves=" + Army::waves + " recalls=" + Army::recalls + " ft=" + Army::Hist()
			+ " quota.attack=" + F1(aiMilitaryMgr.quota.attack) + " raidMin=" + F1(aiMilitaryMgr.quota.raid.min)
			+ " enemyMob=" + F1(aiEnemyMgr.mobileThreat) + " jamCost=" + F1(Intel::jammerCost)
			+ " maxHeat=" + F1(Intel::MaxHeat()) + " eyes=" + Intel::eyes.length() + "/" + Intel::eyesOrdered
			+ " | " + Production::Status() + " | " + Waste::Status() + " " + Redirect::Status() + " | " + Recycler::Status() + " " + Eco::Status() + " | " + Strategic::Status()
			+ " | E inc=" + F1(aiEconomyMgr.energy.income) + " pull=" + F1(aiEconomyMgr.energy.pull)
			+ " M inc=" + F1(aiEconomyMgr.metal.income));
	}
}

}  // namespace Brain
