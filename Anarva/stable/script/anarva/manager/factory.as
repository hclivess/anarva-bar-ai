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
bool AiIsSwitchTime(int lastSwitchFrame)
{
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
	if (d !is null && Brain::Tech::Tier(d) > 1 && Brain::Tech::Allowed(d)) return d;
	// the first lab is the opener's; later ones are chosen against the enemy we have seen
	CCircuitDef@ lab = (Brain::Intel::allFactories.length() == 0) ? Brain::Opening::BestLab() : Brain::Opening::BestLabVsEnemy();
	if (lab !is null) AiLog("[ANV] next factory: " + lab.GetName());
	return (lab !is null) ? lab : d;
}

/* --- Utils --- */


}  // namespace Factory
