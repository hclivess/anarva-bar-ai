#pragma once
#include "util/Defines.h"
#include "AIFloat3.h"
#include <vector>
namespace terrain {
struct SMobileType {
	using Id = int;
	float maxSlope = 0.f, maxElevation = 0.f, minElevation = 0.f;
	bool canHover = false, canFloat = false;
};
struct SAreaData {
	FloatVec heightMap;
	int heightMapXSize = 0;
};
class CTerrainData {
public:
	bool waterIsHarmful = false, waterIsAVoid = false;
};
}
