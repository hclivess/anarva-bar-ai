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
		if (ai.frame - squadStart[i] < 20 * SECOND || squadPeak[i] <= 0.f)
			continue;
		// Keep a squad that is still bigger than what we'd send out fresh.
		const bool isRaid = task.GetFightType() == Task::FightType::RAID;
		const float fresh = isRaid ? aiMilitaryMgr.quota.raid.min : aiMilitaryMgr.quota.attack;
		if (p < 0.4f * squadPeak[i] && p < fresh) {
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
	// Share of the army a wave must reach before launching: set by the Director's posture.
	const float frac = Brain::Director::waveFrac;
	float target = frac * groundPower;
	if (jamAlert)
		target *= 1.25f;  // we can't see what's waiting: go in heavier
	const float cap = AiMax(baseAttack, 0.75f * groundPower);
	aiMilitaryMgr.quota.attack = AiMin(cap, AiMax(baseAttack, target));

	// Raiders hunt in packs: at least 3, growing to ~40% of the raider pool, capped at ~10.
	float raidMin = AiMax(3.f * raiderPower, 0.4f * raiderPoolPower);
	raidMin = AiMax(baseRaidMin, AiMin(raidMin, 10.f * raiderPower));
	if (jamAlert)
		raidMin *= 1.5f;
	aiMilitaryMgr.quota.raid.min = raidMin;
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
	if (AfusCount() >= 2 && AfusMake() >= 0.7f * income && fill > 0.6f && !aiEconomyMgr.isEnergyStalling) {
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
}

void OnFactory(CCircuitUnit@ unit)
{
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

	if (ai.frame < 4 * MINUTE || !HasBase())
		return;

	if (ai.frame % (5 * SECOND) < SECOND)
		OrderVision();

	if (jamAlert && ai.frame - lastScoutFrame > 2 * MINUTE && Brain::Army::scouts.length() < 3 && airFactories.length() > 0) {
		CCircuitUnit@ fac = airFactories[AiRandom(0, int(airFactories.length()) - 1)];
		CCircuitDef@ scout = aiFactoryMgr.GetRoleDef(fac.circuitDef, RT::SCOUT);
		if (scout !is null && scout.IsAvailable(ai.frame)) {
			aiFactoryMgr.Enqueue(TaskS::Recruit(Task::RecruitType::FIREPOWER, Task::Priority::HIGH,
				scout, fac.GetPos(ai.frame), 64.f));
			lastScoutFrame = ai.frame;
			AiLog("[ANV] Intel: recruiting air scout " + scout.GetName() + " vs jammers");
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

string Status()
{
	return "aa=" + aaTowers.length() + " juno=" + junos.length() + " amd=" + amds.length() + " tac=" + tacs.length() + " silo=" + silos.length()
		+ " shield=" + shields.length() + " infra=" + infra.length() + " orders=" + orders;
}

}  // namespace Strategic

/* ======================================================================== */
/*
 * Director: every few seconds, ask "what is the next reasonable move?". It weighs our army against
 * the enemy's known mobile threat, our economy and the clock, picks a posture, and logs why.
 * The other modules read the posture.
 */
namespace Director {

enum Posture { BOOM = 0, HOLD, BALANCED, PRESSURE, ALLIN }
array<string> names = {"BOOM", "HOLD", "BALANCED", "PRESSURE", "ALLIN"};

Posture posture = BOOM;
Posture pending = BOOM;
int pendingSince = 0;
float waveFrac = 0.30f;
float ratio = 1.f;
string reason = "start";

float OurPower() { return Brain::Army::groundPower + Brain::Army::raiderPoolPower; }

void Update()
{
	const float minute = float(ai.frame) / MINUTE;
	const float ours = OurPower();
	const float theirs = AiMax(1.f, aiEnemyMgr.mobileThreat);
	ratio = ours / theirs;
	const int enemies = AiMax(1, ai.GetEnemyTeamSize());

	Posture want;
	string why;
	if (minute < 4.f) {
		want = BOOM;
		why = "opening";
	} else if (ratio < 0.6f) {
		want = HOLD;
		why = "outgunned " + F1(ratio) + "x: defend, only strike with a big wave";
	} else if (ratio > 2.5f && minute >= 8.f && ours > 4.f * Brain::Army::baseAttack) {
		want = ALLIN;
		why = "dominant " + F1(ratio) + "x: keep the pressure rolling";
	} else if (ratio > 1.3f) {
		want = PRESSURE;
		why = "ahead " + F1(ratio) + "x: attack in frequent waves";
	} else {
		want = (enemies > 1 && minute < 15.f) ? HOLD : BALANCED;
		why = "even " + F1(ratio) + "x vs " + enemies + " enemies";
	}

	// Hysteresis: a posture must persist 15 s before we switch.
	if (want != pending) {
		pending = want;
		pendingSince = ai.frame;
	} else if (want != posture && ai.frame - pendingSince >= 15 * SECOND) {
		AiLog("[ANV] Director: " + names[posture] + " -> " + names[want] + " (" + why + ")");
		posture = want;
		reason = why;
	}

	switch (posture) {
		case BOOM:     waveFrac = 0.30f; break;
		case HOLD:     waveFrac = 0.65f; break;
		case BALANCED: waveFrac = 0.30f + 0.20f * AiMin(1.f, AiMax(0.f, (minute - 5.f) / 20.f)); break;
		case PRESSURE: waveFrac = 0.25f; break;
		case ALLIN:    waveFrac = 0.15f; break;
	}
}

string Status() { return names[posture] + " r=" + F1(ratio) + " wave=" + F1(waveFrac); }

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
	if (!HasBase() && !unit.circuitDef.IsMobile())
		basePos = unit.GetPos(ai.frame);
	Recycler::OnFinished(unit);
	Intel::OnFinished(unit);
	Strategic::OnFinished(unit);
}

void OnUnitDestroyed(CCircuitUnit@ unit)
{
	const bool recycled = Recycler::OnDestroyed(unit);
	if (!recycled)
		Intel::OnLoss(unit);
	Intel::OnDestroyed(unit);
	Strategic::OnDestroyed(unit);
	if (!unit.circuitDef.IsMobile() && (Factory::userData[unit.circuitDef.id].attr & (Factory::Attr::T2 | Factory::Attr::T3)) != 0)
		Recycler::advFactories = AiMax(0, Recycler::advFactories - 1);
}

void Update()  // every 30 frames
{
	Intel::Update();
	Director::Update();
	Army::Update(Intel::jamAlert);
	if (ai.frame % (2 * SECOND) < SECOND)
		Recycler::Update();
	if (ai.frame % (10 * SECOND) < SECOND)
		Strategic::Update(Intel::jamAlert);

	if (ai.frame % MINUTE < SECOND) {
		AiLog("[ANV] t=" + Minute() + "m " + Director::Status() + " groundPow=" + F1(Army::groundPower) + " units=" + Army::ground.length()
			+ " raiders=" + Army::raiders.length() + " squads=" + Army::squads.length() + " recalls=" + Army::recalls + " ft=" + Army::Hist()
			+ " quota.attack=" + F1(aiMilitaryMgr.quota.attack) + " raidMin=" + F1(aiMilitaryMgr.quota.raid.min)
			+ " enemyMob=" + F1(aiEnemyMgr.mobileThreat) + " jamCost=" + F1(Intel::jammerCost)
			+ " maxHeat=" + F1(Intel::MaxHeat()) + " eyes=" + Intel::eyes.length() + "/" + Intel::eyesOrdered
			+ " | " + Recycler::Status() + " | " + Strategic::Status()
			+ " | E inc=" + F1(aiEconomyMgr.energy.income) + " pull=" + F1(aiEconomyMgr.energy.pull)
			+ " M inc=" + F1(aiEconomyMgr.metal.income));
	}
}

}  // namespace Brain
