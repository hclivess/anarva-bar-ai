#include "../../define.as"
#include "../../unit.as"


namespace Military {

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	return aiMilitaryMgr.DefaultMakeTask(unit);
}

void AiTaskAdded(IUnitTask@ task)
{
	Brain::Army::OnTaskAdded(task);
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
	Brain::Army::OnTaskRemoved(task);
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
	// a defence answers an army; none is worth its metal before any enemy army has been seen (no clock, no income gate)
	if (aiEnemyMgr.mobileThreat > 0.f) {
		aiMilitaryMgr.DefaultMakeDefence(cluster, pos);
	}
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
