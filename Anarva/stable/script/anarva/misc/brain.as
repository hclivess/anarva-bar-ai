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
const bool F_RECALL = true;    // broken-squad recall
const bool F_PROD = false;      // capability-based production chooser (incl. rez bots)
const bool F_SCALE = true;     // Director drives buildpowerRatio
const bool F_ECOGATE = false;   // moho energy-headroom gate
const bool F_RECYCLE = true;   // eco recycling + T1 salvage
const bool F_STRAT = true;     // strategic structures + AA counter
const bool F_FORTIFY = false;   // turrets + teeth at hot fronts
const bool F_WASTE = false;     // overflow: nanos + converters
const bool F_TECH = false;      // payback-based tech gate
const bool F_REDIRECT = false;  // assist factories by army deficit
const bool F_INTEL = true;     // eyes, scouting, phantom threat
const bool F_QUOTA = false;
const bool F_OPENER = true;
const bool F_SCOUT = false;     // scout quota >=3 and timed scout recruits (keep sight)
const bool F_AA = false;        // static AA counter
const bool F_FUSREC = false;
const bool F_NEWRECALL = false;
const bool F_MAPECO = false;
const bool F_COMMSAFE = false;
const bool F_DETAIL = false;
const bool F_TERRAIN = false;
const bool F_BOOM = false;      // scale on pressure, not presence: boom while nothing presses us (human playbook vs BARbs)   // fortify the choke from the high ground (map analysis)    // 1vN: defeat in detail - size against one opponent's army, not their sum  // commander only works inside the zone our army protects    // constructor share from free extractor spots (map analysis) // need-based recall (false = first-gen 40%-of-peak rule)    // recycle fusions once AFUS carry the grid    // constructor-rich T1 opener (false = BARb hard opener)     // attack/raid quotas sized from needed power

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
	aiMilitaryMgr.quota.attack = AiMax(baseAttack, Brain::Director::needPower);

	// A raid pack must beat the raiders that will answer it (their raider threat at our trade rate).
	float raidMin = AiMax(baseRaidMin, aiEnemyMgr.GetEnemyThreat(RT::RAIDER) / AiMax(0.25f, Brain::Assess::trade));	aiMilitaryMgr.quota.raid.min = raidMin;
	// raid.avg caps how big a raid may grow by joining; never below the gather size
	aiMilitaryMgr.quota.raid.avg = AiMax(aiMilitaryMgr.quota.raid.avg, raidMin * 1.5f);

	CheckSquads();

	aiMilitaryMgr.quota.scout = jamAlert ? baseScout + 3 : baseScout;
}

}  // namespace Army

/* ======================================================================== */
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
	if (ai.frame < 22 * MINUTE || advFactories <= 0 || aiEconomyMgr.metal.income < 30.f
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
			CCircuitUnit@ fac = facs[AiRandom(0, int(facs.length()) - 1)];
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

	// Anti-nuke: immediately when a silo is spotted; proactively when rich.
	const uint wantAmd = enemyNuke ? (m >= 100.f ? 2 : 1) : ((minute >= 35 && m >= 60.f) ? 1 : 0);
	if (amds.length() < wantAmd && Ready(1, amdDef)) {
		Order(1, amdDef, basePos, enemyNuke ? Task::Priority::NOW : Task::Priority::NORMAL, SQUARE_SIZE * 32);
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

void InitFortify()
{
	@turT1 = Side("armllt", "corllt", "leglht");
	@turT2 = Side("armhlt", "corhlt", "legmg");
	@turT3 = Side("armpb", "corvipe", "legbastion");
	@wallDef = Side("armdrag", "cordrag", "legdrag");
}

/*
 * Terrain fortification: the choke on our side of the path to the enemy, and the highest ground
 * overlooking it (offline map analysis). Turrets on the high ground (reach, fire from above), teeth
 * across the choke mouth (attackers stall under fire). Done while we can't win an open fight
 * (power < needed) or whenever we're outnumbered (1vN), as long as the deficit lasts.
 */
int myStart = -2;
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
	const float m_inc = aiEconomyMgr.metal.income;
	CCircuitDef@ tur = (m_inc >= 45.f && turT3 !is null && turT3.IsAvailable(ai.frame)) ? turT3
		: ((m_inc >= 18.f && turT2 !is null && turT2.IsAvailable(ai.frame)) ? turT2 : turT1);
	if (tur is null || !tur.IsAvailable(ai.frame))
		return true;
	lastFortify = ai.frame;
	++forts;
	const AIFloat3 high(m.hx[myStart], 0.f, m.hz[myStart]);
	const AIFloat3 choke(m.cx[myStart], 0.f, m.cz[myStart]);
	aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE, Task::Priority::HIGH, tur, high, SQUARE_SIZE * 12, true, 3 * MINUTE));
	if (wallDef !is null && wallDef.IsAvailable(ai.frame) && forts % 2 == 1) {
		AIFloat3 dir = choke - AIFloat3(m.sx[myStart], 0.f, m.sz[myStart]);
		const float len = AiMax(1.f, dir.Length2D());
		dir = dir / len;
		const AIFloat3 side(-dir.z, 0.f, dir.x);
		for (int k = -3; k <= 3; ++k)
			aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE, Task::Priority::NORMAL, wallDef, choke + side * (48.f * k), 0.f, true, 3 * MINUTE));
	}
	AiLog("[ANV] Terrain: " + tur.GetName() + " on high ground (+" + int(m.gain[myStart]) + ")" + (forts % 2 == 1 ? " + teeth across the choke" : ""));
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
CCircuitDef@ RezToBuild(const CCircuitDef@ fdef)
{
	const float pool = 0.5f * (Brain::Assess::lostNear + Brain::Assess::lostFar + Brain::Assess::killed);
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

IUnitTask@ MakeTask(CCircuitUnit@ fac)
{
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
	if (NeedBuilder() || AiRandom(0, 99) < BuilderSharePercent()) {
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
	const int pick = AiDice(scores);
	if (pick < 0)
		return null;
	CCircuitDef@ d = cands[pick];
	++built[d.id];
	++choices;
	last = d.GetName();
	return aiFactoryMgr.Enqueue(TaskS::Recruit(Task::RecruitType::FIREPOWER, Task::Priority::NORMAL, d,
		fac.GetPos(ai.frame), 64.f));
}

string Status() { return "prod=" + choices + "/b" + builders + " rez=" + rezBots.length() + "/" + rezOrders + " last=" + last; }

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
			Brain::Intel::allFactories[AiRandom(0, int(Brain::Intel::allFactories.length()) - 1)].GetPos(ai.frame), SQUARE_SIZE * 12, true, 2 * MINUTE));
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
		CCircuitUnit@ fac = facs[AiRandom(0, int(facs.length()) - 1)];
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

bool Allowed(const CCircuitDef@ facDef)
{
	if (!F_TECH)
		return true;
	const int attr = Factory::userData[facDef.id].attr;
	const bool t3 = (attr & Factory::Attr::T3) != 0;
	const bool t2 = (attr & Factory::Attr::T2) != 0;
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
float enemyPrev = -1.f;
array<float> incomeHist;  // one sample per minute
float growth = 0.f;
bool pushedBack = false, pushing = false;
float trade = 1.f;

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
	if (dist < 1500.f)
		lostNear += d.costM;
	else
		lostFar += d.costM;
	if (d.IsMobile())
		frontDist = 0.9f * frontDist + 0.1f * dist;
}

void Update()  // every second
{
	lostNear *= 0.992f;  // half-life ~85 s
	lostFar *= 0.992f;
	killed *= 0.992f;
	const float ev = EnemyValue();
	if (enemyPrev >= 0.f && ev < enemyPrev)
		killed += AiMin(enemyPrev - ev, 3000.f);  // drops in known enemy value ~ our kills
	enemyPrev = ev;
	const float lost = lostNear + lostFar;
	trade = (killed + 50.f) / (lost + 50.f);
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
string scaleWhy = "";
bool blind = false;
string reason = "start";

float OurPower() { return Brain::Army::groundPower + Brain::Army::raiderPoolPower; }

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
		scale = AiMin(2.f, AiMax(1.f, ratio));
		scaleWhy = blind ? "blind: assume enemy kept pace" : (ratio >= 1.f ? "surplus power: scale" : "deficit away from home: keep the economy growing");
	}
	if (Brain::Waste::metalOverflow) {
		scale = AiMin(2.f, AiMax(scale, 1.f) * (1.f + float(Brain::Waste::metalSec) / 60.f));
		scaleWhy = "metal overflowing: more build power";
	}
	if (F_SCALE)
		aiFactoryMgr.buildpowerRatio = baseBP * scale;
	if (F_SCOUT)
		aiMilitaryMgr.quota.scout = AiMax(int(aiMilitaryMgr.quota.scout), blind ? 4 : 3);

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
string Status() { return names[posture] + " r=" + F1(ratio) + " wave=" + F1(waveFrac) + " bp=" + F1(scale) + "(" + scaleWhy + ")"; }

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
}

void OnFactoryAdded(CCircuitUnit@ unit)
{
	if ((Factory::userData[unit.circuitDef.id].attr & (Factory::Attr::T2 | Factory::Attr::T3)) != 0)
		++Recycler::advFactories;
	if (!HasBase())
		basePos = unit.GetPos(ai.frame);
	Intel::OnFactory(unit);
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
	Economist::OnFinished(unit);
	Production::OnFinished(unit);
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
	float front = Brain::Assess::frontDist;
	if (front <= 0.f && Brain::Production::mapInfo !is null && Brain::Production::mapInfo.basePath > 0.f)
		front = Brain::Production::mapInfo.basePath * 0.5f;
	if (front <= 0.f)
		return task;  // no idea where the fighting is yet (opening): let it build
	if (basePos.distance2D(bt.GetBuildPos()) <= 0.5f * front)
		return task;
	++commRedirects;
	CCircuitUnit@ fac = Brain::Intel::allFactories[AiRandom(0, int(Brain::Intel::allFactories.length()) - 1)];
	return aiBuilderMgr.Enqueue(TaskB::Guard(Task::Priority::HIGH, fac, true, 30 * SECOND));
}

void OnUnitDestroyed(CCircuitUnit@ unit)
{
	if (unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask)) {
		const AIFloat3 p = unit.GetPos(ai.frame);
		AiLog("[ANV] COMMANDER LOST at (" + int(p.x) + "," + int(p.z) + ") dist-from-base=" + int(HasBase() ? basePos.distance2D(p) : -1.f)
			+ " task=" + (unit.task is null ? -1 : int(unit.task.GetType())) + " t=" + Minute() + "m posture=" + Director::names[Director::posture]);
		@commander = null;
	}
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
	if (F_INTEL) Intel::Update();
	Assess::Update();
	if (F_WASTE) Waste::Update();
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

	if (ai.frame % MINUTE < SECOND) {
		if (commander !is null) {
			const AIFloat3 cp = commander.GetPos(ai.frame);
			AiLog("[ANV] commander at (" + int(cp.x) + "," + int(cp.z) + ") dist-from-base=" + int(HasBase() ? basePos.distance2D(cp) : -1.f)
				+ " task=" + (commander.task is null ? -1 : int(commander.task.GetType())) + " redirects=" + commRedirects);
		}
		AiLog("[ANV] t=" + Minute() + "m " + Director::Status() + " | " + Assess::Status() + " | groundPow=" + F1(Army::groundPower) + " units=" + Army::ground.length()
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
