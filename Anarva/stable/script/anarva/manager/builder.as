#include "../../unit.as"


namespace Builder {

CCircuitUnit@ energizer1 = null;
CCircuitUnit@ energizer2 = null;

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	// the opener owns the commander until its lab stands: the core's own pick re-ordered it every few seconds and the
	// commander crawled (100 elmos in 11 s at 37/s, Feast of Hades 2026-11-25)
	if (unit is Brain::commander && !Brain::Opening::done && Brain::Opening::planned !is null)
		return Brain::Opening::planned;
	IUnitTask@ task = aiBuilderMgr.DefaultMakeTask(unit);
	if (unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
		return Brain::CommanderTask(unit, task);
	return task;
}

void AiTaskAdded(IUnitTask@ task)
{
	// a lab whose constructors upgrade extractors carries that value into the builders' ranking (valued by the metal it
	// spends alone, an approved advanced lab loses every pick)
	IBuilderTask@ bt = cast<IBuilderTask>(task);
	if (bt is null || bt.buildDef is null || bt.GetBuildType() != Task::BuildType::FACTORY) return;
	const float busy = bt.buildDef.buildTime / AiMax(1.f, aiBuilderMgr.GetBuildPower());
	// the value the tier-2 gate measured when it allowed this lab: its return per metal x its cost (the same decision;
	// UpgradeValue's separate estimate, 2216, never beat the lab's 3240 cost, so the core never took the job and there
	// was no tier 2 by minute 17 in the owner's game, 2026-11-26)
	float up = Brain::Production::UpgradeValue(bt.buildDef, busy);
	if (Brain::Tech::Tier(bt.buildDef) >= 2) up = AiMax(up, Brain::Tech::lastT2Return * Brain::Economist::MetalValue(bt.buildDef));
	if (up > 0.f) { bt.value = up; AiLog("[ANV] factory job " + bt.buildDef.GetName() + " carries its upgrade value " + int(up)); }
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
	Brain::OnBuilderTaskRemoved(task);
}

void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
	const CCircuitDef@ cdef = unit.circuitDef;
	if (cdef.IsRoleAny(Unit::Role::COMM.mask) && Brain::commander is null)
		@Brain::commander = unit;
	if (usage != Unit::UseAs::BUILDER || cdef.IsRoleAny(Unit::Role::COMM.mask))
		return;

	// constructor with BASE attribute is assigned to tasks near base
	if (!cdef.IsRoleAny(Unit::Role::BUILDER2.mask)) {  // T1 constructor: not in the T2-builder role (no cost line)
		if (energizer1 is null
			&& (uint(cdef.count) > aiMilitaryMgr.GetGuardTaskNum() || cdef.IsAbleToFly()))
		{
			@energizer1 = unit;
			unit.AddAttribute(Unit::Attr::BASE.type);
		}
	} else {
		if (energizer2 is null) {
			@energizer2 = unit;
			unit.AddAttribute(Unit::Attr::BASE.type);
		}
	}
}

void AiUnitRemoved(CCircuitUnit@ unit, Unit::UseAs usage)
{
	if (energizer1 is unit)
		@energizer1 = null;
	else if (energizer2 is unit)
		@energizer2 = null;
}

void AiLoad(IStream& istream)
{
	Id e1id = -1, e2id = -1;
	istream >> e1id >> e2id;
	@energizer1 = ai.GetTeamUnit(e1id);
	@energizer2 = ai.GetTeamUnit(e2id);
	if (energizer1 !is null)
		energizer1.AddAttribute(Unit::Attr::BASE.type);
	if (energizer2 !is null)
		energizer2.AddAttribute(Unit::Attr::BASE.type);
}

void AiSave(OStream& ostream)
{
	ostream << Id(energizer1 !is null ? energizer1.id : -1)
			<< Id(energizer2 !is null ? energizer2.id : -1);
}

}  // namespace Builder
