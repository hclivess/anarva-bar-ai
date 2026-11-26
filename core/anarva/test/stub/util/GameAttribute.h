#pragma once
#include "terrain/TerrainData.h"
namespace circuit {
class CGameAttribute {
public:
	terrain::CTerrainData td;
	terrain::CTerrainData& GetTerrainData() { return td; }
};
}
