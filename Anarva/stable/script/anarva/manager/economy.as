#include "../../define.as"


namespace Economy {

void AiLoad(IStream& istream)
{
}

void AiSave(OStream& ostream)
{
}

/*
 * struct SResourceInfo {
 *   const float current;
 *   const float storage;
 *   const float pull;
 *   const float income;
 * }
 */
int lastFrame = -1;
CCircuitDef@ cheapEnergy = null, mexDef = null;
const float MM_LEVEL = 0.75f;  // game rule: converters run while energy storage is above mmLevel (default 0.75)

// Seconds to put one more of def online with our average builder (build time / build power per builder)
float LeadTime(const CCircuitDef@ d)
{
	if (d is null) return 0.f;
	const float per = aiBuilderMgr.GetBuildPower() / AiMax(1.f, float(aiBuilderMgr.GetWorkerCount()));
	return d.buildTime / AiMax(1.f, per);
}

// Seconds until a store runs dry at the current net flow (infinite when it isn't draining)
float TimeToEmpty(const SResourceInfo@ r) { return (r.pull > r.income) ? r.current / (r.pull - r.income) : 1e9f; }

/*
 * No storage fractions (the inherited 20% / 99% / 30% / 60% / 88% and the 3-minute clock): projections.
 *  - stalling / empty: the store runs dry before one more producer could be built (its build time / our build power)
 *  - full: what arrives before the next update doesn't fit
 *  - energy full (for converters): above the game's own converter level (mmLevel)
 */
void AiUpdateEconomy()
{
	const SResourceInfo@ metal = aiEconomyMgr.metal;
	const SResourceInfo@ energy = aiEconomyMgr.energy;
	const float dt = (lastFrame < 0) ? 1.f : AiMax(1.f, float(ai.frame - lastFrame)) / SECOND;
	lastFrame = ai.frame;
	if (cheapEnergy is null) @cheapEnergy = Brain::Strategic::Side("armsolar", "corsolar", "legsolar");
	if (mexDef is null) @mexDef = Brain::Strategic::Side("armmex", "cormex", "legmex");

	aiEconomyMgr.isMetalEmpty = TimeToEmpty(metal) < LeadTime(mexDef);
	aiEconomyMgr.isMetalFull = metal.current + (metal.income - metal.pull) * dt > metal.storage;
	aiEconomyMgr.isEnergyEmpty = energy.current <= 0.f || TimeToEmpty(energy) < dt;
	aiEconomyMgr.isEnergyStalling = TimeToEmpty(energy) < LeadTime(cheapEnergy);
	aiEconomyMgr.isEnergyFull = energy.current + (energy.income - energy.pull) * dt > MM_LEVEL * energy.storage;

	aiFactoryMgr.isAssistRequired = (!aiEconomyMgr.isMetalEmpty && !aiEconomyMgr.isEnergyStalling)
		|| Brain::Waste::metalOverflow;  // never let income spill: assist factories
}

}  // namespace Economy
