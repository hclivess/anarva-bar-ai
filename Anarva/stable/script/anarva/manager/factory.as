#include "../../define.as"
#include "../../unit.as"
#include "../../task.as"
#include "../misc/commander.as"


namespace Factory {

enum Attr {
	T1 = 0x0001, T2 = 0x0002, T3 = 0x0004, T4 = 0x0008
}

class SUserData {
	SUserData(int a) {
		attr = a;
	}
	SUserData() {}
	int attr = 0;
}

// Example of userData per UnitDef
array<SUserData> userData(ai.GetDefCount() + 1);

string armlab  ("armlab");
string armalab ("armalab");
string armvp   ("armvp");
string armavp  ("armavp");
string armsy   ("armsy");
string armasy  ("armasy");
string armap   ("armap");
string armaap  ("armaap");
string armshltx("armshltx");

string corlab  ("corlab");
string coralab ("coralab");
string corvp   ("corvp");
string coravp  ("coravp");
string corsy   ("corsy");
string corasy  ("corasy");
string corap   ("corap");
string coraap  ("coraap");
string corgant ("corgant");

string leglab  ("leglab");
string legalab ("legalab");
string legvp   ("legvp");
string legavp  ("legavp");
string legap   ("legap");
string legsy   ("legsy");
string legadvshipyard   ("legadvshipyard");
string legaap  ("legaap");
string leggant ("leggant");


IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	IUnitTask@ task = Brain::Production::MakeTask(unit);
	if (task !is null)
		return task;
	return aiFactoryMgr.DefaultMakeTask(unit);
}

void AiTaskAdded(IUnitTask@ task)
{
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
}

void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
	if (usage != Unit::UseAs::FACTORY)
		return;

	Brain::OnFactoryAdded(unit);

	const CCircuitDef@ facDef = unit.circuitDef;
	if (userData[facDef.id].attr & Attr::T3 != 0) {
		// if (ai.teamId != ai.GetLeadTeamId()) then this change affects only target selection,
		// while threatmap still counts "ignored" here units.
		array<string> spam = {"armpw", "corak", "armflea", "armfav", "corfav", "leggob", "legscout"};
		for (uint i = 0; i < spam.length(); ++i) {
			CCircuitDef@ cdef = ai.GetCircuitDef(spam[i]);
			if (cdef !is null)
				cdef.SetIgnore(true);
		}
	}
}

void AiUnitRemoved(CCircuitUnit@ unit, Unit::UseAs usage)
{
}

void AiLoad(IStream& istream)
{
}

void AiSave(OStream& ostream)
{
}

/*
 * New factory switch condition; switch event is also based on eco + caretakers.
 */
// The next-tier factory our own constructors can build (their build options), the one our tech decision judges - not
// BARb's config pick: the switch asked whether BARb's default was a higher tier, which it never was, so an approved
// advanced lab was never enqueued (cmd_m135: "Tech: building armalab", no factory job).
CCircuitDef@ NextTierLab()
{
	CCircuitDef@ con = Brain::EcoPos::CheapestConstructor();
	if (con is null) return null;
	const array<string> opts = Facts::BuildOptions(con.GetName());
	const int have = Brain::Tech::TierWeHave();
	for (uint k = 0; k < opts.length(); ++k) {
		CCircuitDef@ d = ai.GetCircuitDef(opts[k]);
		if (d is null || d.IsMobile() || d.buildSpeed <= 0.f || !d.IsAvailable(ai.frame)) continue;
		if (Facts::BuildOptions(d.GetName()).length() == 0) continue;
		if (Brain::Tech::Tier(d) == have + 1) return d;
	}
	return null;
}
bool AiIsSwitchTime(int lastSwitchFrame)
{
	if (Brain::HasBase() && Brain::Intel::allFactories.length() > 0) {
		CCircuitDef@ nt = NextTierLab();
		if (nt !is null && Brain::Tech::Allowed(nt) && FactoryValue(nt) > 0.f) return true;
	}
	// No clock, no dice (the inherited rule waited for a random 8000-12000 s limit). Switch when the lab the core
	// would build next is a higher tier than any we have and the tech decision says it pays now.
	if (!Brain::HasBase() || Brain::Intel::allFactories.length() == 0)
		return false;
	CCircuitDef@ next = aiFactoryMgr.DefaultGetFactoryToBuild(Brain::basePos, false, false);
	if (next is null)
		return false;
	return Brain::Tech::Tier(next) > Brain::Tech::TierWeHave() && Brain::Tech::Allowed(next);
}

bool AiIsSwitchAllowed(CCircuitDef@ facDef)
{
	return Brain::Tech::Allowed(facDef);
}

CCircuitDef@ AiGetFactoryToBuild(const AIFloat3& in pos, bool isStart, bool isReset)
{
	// Which factory is our decision (#97, think like the player): a higher tier only when the tech decision allows
	// it; otherwise the T1 lab the opener judges best for this map (strength per metal it fields, units that reach
	// their side). BARb's pick rebuilt a lost lab as an advanced lab with one extractor standing (Canis River).
	CCircuitDef@ d = aiFactoryMgr.DefaultGetFactoryToBuild(pos, isStart, isReset);
	{ CCircuitDef@ nt = NextTierLab(); if (nt !is null && !isStart) @d = nt; }  // our next tier, not BARb's pick
	// the first lab is the opener's; later ones are chosen against the enemy we have seen
	CCircuitDef@ lab = (Brain::Intel::allFactories.length() == 0) ? Brain::Opening::BestLab() : Brain::Opening::BestLabVsEnemy();
	// A higher tier competes on the same value as a T1 lab, the one the builders rank it by: the metal it lets us spend
	// that we otherwise don't (min of our overflow and its build power x metal per build-second of what it makes) over
	// the horizon, less its cost, per second of building it. Returned whenever "allowed", the advanced lab (2247-3620
	// metal, value -1154 to -3378 at the builders' prices) stood in for every second factory: one lab all game while
	// winners add a T1 vehicle or air plant at a median 7:29 (78 of 94 second factories; replays.db 1v1 winners; cmd_m61).
	if (d !is null && Brain::Tech::Tier(d) > 1 && Brain::Tech::Allowed(d) && lab !is null && Brain::Intel::allFactories.length() > 0) {
		const float vT = FactoryValue(d), vL = FactoryValue(lab);
		AiLog("[ANV] next factory: " + d.GetName() + " " + int(vT) + " vs " + lab.GetName() + " " + int(vL) + " (value per build-second x 1000)");
		if (vT > vL) return d;
	} else if (d !is null && Brain::Tech::Tier(d) > 1 && Brain::Tech::Allowed(d)) return d;
	if (lab !is null) AiLog("[ANV] next factory: " + lab.GetName());
	return (lab !is null) ? lab : d;
}

/* --- Utils --- */

// what a factory is worth per second of building it, x1000 (as the core's build-power value)
float FactoryValue(CCircuitDef@ f)
{
	const array<string> opts = Facts::BuildOptions(f.GetName());
	float sm = 0.f, sbt = 0.f;
	for (uint k = 0; k < opts.length(); ++k) {
		CCircuitDef@ o = ai.GetCircuitDef(opts[k]);
		if (o is null || !o.IsMobile()) continue;
		sm += o.costM; sbt += o.buildTime;
	}
	const float rate = (sbt > 0.f) ? f.buildSpeed * sm / sbt : 0.f;  // metal/s it can spend
	const float H = AiMax(1.f, Brain::Economist::ProducerLife());
	const float overflow = AiMax(0.f, aiEconomyMgr.metal.income - AiSmoothMetalPull()) + aiEconomyMgr.metal.current / H;
	const float busy = f.buildTime / AiMax(1.f, aiBuilderMgr.GetBuildPower());
	const float V = AiMin(overflow, rate) * AiMax(0.f, H - busy) - Brain::Economist::MetalValue(f) + Brain::Production::UpgradeValue(f, busy);
	return 1000.f * V / AiMax(1.f, busy);
}


}  // namespace Factory
