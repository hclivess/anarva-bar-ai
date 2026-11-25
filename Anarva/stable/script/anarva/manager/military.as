#include "../../define.as"
#include "../../unit.as"


namespace Military {

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	// Anarva commands its own army (Brain::Command); BARb's squads/quotas/raid tasks no longer get combat units.
	// Every armed mobile unit (BARb tags raiders like the Grunt as scouts too); unarmed scouts aren't army.
	if (Brain::Command::Owns(unit.circuitDef))
		return aiMilitaryMgr.GetPlayerTask();
	return aiMilitaryMgr.DefaultMakeTask(unit);
}

void AiTaskAdded(IUnitTask@ task)
{
	// (BARb squad tracking removed; Brain::Command owns the army)
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
	// (BARb squad tracking removed)
}

void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
	if (usage == Unit::UseAs::COMBAT)
		Brain::Army::OnAdded(unit);
}

void AiUnitRemoved(CCircuitUnit@ unit, Unit::UseAs usage)
{
	if (usage == Unit::UseAs::COMBAT)
		Brain::Army::OnRemoved(unit);
}

void AiLoad(IStream& istream)
{
}

void AiSave(OStream& ostream)
{
}

void AiMakeDefence(int cluster, const AIFloat3& in pos)
{
	// No BARb porcupine: a tower at every cluster from its config list once any enemy army was seen. Towers are decided
	// by value in Brain::MexPorc (the raid loss they prevent vs their cost) and Fortify. Both ran: 12 towers built for
	// 5 valued orders, up to 11 constructors on towers at minute 8 while extractors stopped at 10 (Feast 2026-11-25).
}

/*
 * anti-air threat threshold;
 * air factories will stop production when AA threat exceeds
 */
// FIXME: Remove/replace, deprecated.
bool AiIsAirValid()
{
	// air pays while the enemy can shoot ground units better than aircraft (same measure as the production value)
	return Brain::Production::airExposure >= 1.f;
}

}  // namespace Military
