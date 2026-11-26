#pragma once
#include "terrain/TerrainData.h"
#include "AIFloat3.h"
#include <vector>
namespace circuit {
class CTerrainManager {
public:
	std::vector<terrain::SMobileType> mobileTypes;
	terrain::SAreaData* areaData = nullptr;
	static inline int GetTerrainWidth() { return springai::AIFloat3::maxxpos; }
	static inline int GetTerrainHeight() { return springai::AIFloat3::maxzpos; }
	terrain::SMobileType* GetMobileTypeById(terrain::SMobileType::Id id) {
		return (id < 0 || id >= (int)mobileTypes.size()) ? nullptr : &mobileTypes[id];
	}
	terrain::SAreaData* GetAreaData() const { return areaData; }
	bool IsWaterAVoid() const { return false; }
};
}
