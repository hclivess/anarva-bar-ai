#include "manager/military.as"
#include "manager/builder.as"
#include "manager/factory.as"
#include "manager/economy.as"
#include "misc/facts.as"
#include "misc/mapfacts.as"
#include "misc/brain.as"
#include "../common.as"


namespace Main {

void AiMain()  // Initialize config params
{
	// An energy plant belongs inside the base when it costs more than the cheapest raider that could kill it outside:
	// a raid on it would be a losing trade for us.
	float cheapestRaider = 1e9f;
	for (Id defId = 1, count = ai.GetDefCount(); defId <= count; ++defId) {
		CCircuitDef@ rdef = ai.GetCircuitDef(defId);
		if (rdef !is null && rdef.IsMobile() && rdef.IsRoleAny(Unit::Role::RAIDER.mask) && rdef.costM > 0.f)
			cheapestRaider = AiMin(cheapestRaider, rdef.costM);
	}
	for (Id defId = 1, count = ai.GetDefCount(); defId <= count; ++defId) {
		CCircuitDef@ cdef = ai.GetCircuitDef(defId);
		if (cdef.costM >= cheapestRaider && !cdef.IsMobile() && aiEconomyMgr.GetEnergyMake(cdef) > 0.f)
			cdef.AddAttribute(Unit::Attr::BASE.type);  // Build heavy energy at base
	}

	// Example of user-assigned custom attributes
	array<string> names = {Factory::armalab, Factory::coralab, Factory::armavp, Factory::coravp,
		Factory::armaap, Factory::coraap, Factory::armasy, Factory::corasy, Factory::legadvshipyard,
		Factory::legalab, Factory::legavp, Factory::legaap};
	for (uint i = 0; i < names.length(); ++i) {
		CCircuitDef@ cdef = ai.GetCircuitDef(names[i]);
		if (cdef !is null)
			Factory::userData[cdef.id].attr |= Factory::Attr::T2;
	}
	names = {Factory::armshltx, Factory::corgant, Factory::leggant};
	for (uint i = 0; i < names.length(); ++i) {
		CCircuitDef@ cdef = ai.GetCircuitDef(names[i]);
		if (cdef !is null)
			Factory::userData[cdef.id].attr |= Factory::Attr::T3;
	}

	Init::EnableWallTargets();

	Brain::Init();
}

void AiUpdate()  // SlowUpdate, every 30 frames with initial offset of skirmishAIId
{
	Brain::Update();
}

void AiUnitFinished(CCircuitUnit@ unit)  // any of our units
{
	Brain::OnUnitFinished(unit);
}

void AiUnitDestroyed(CCircuitUnit@ unit)  // any of our units
{
	Brain::OnUnitDestroyed(unit);
}

// the start position, when the game lets us choose (#97): decided by the opening's plan value
AIFloat3 AiPickStartPos(const AIFloat3& in lo, const AIFloat3& in hi, const AIFloat3& in them)
{
	return Brain::Opening::PickStart(lo, hi, them);
}

}  // namespace Main
