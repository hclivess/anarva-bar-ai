#pragma once
#include "terrain/TerrainManager.h"
#include "spring/SpringMap.h"
#include "util/GameAttribute.h"
namespace circuit {
class CCircuitAI {
public:
	CTerrainManager tm;
	CMap m;
	CGameAttribute ga;
	CTerrainManager* GetTerrainManager() const { return const_cast<CTerrainManager*>(&tm); }
	CMap* GetMap() const { return const_cast<CMap*>(&m); }
	CGameAttribute* GetGameAttribute() const { return const_cast<CGameAttribute*>(&ga); }
};
}
