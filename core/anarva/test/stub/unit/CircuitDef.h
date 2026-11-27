#pragma once
#include "terrain/TerrainData.h"
namespace circuit {
class CCircuitDef {
public:
	terrain::SMobileType::Id mobileTypeId = -1;
	int moveXSize = 0;
	bool ableToFly = false;
	terrain::SMobileType::Id GetMobileId() const { return mobileTypeId; }
	int GetMoveXSize() const { return moveXSize; }
	bool IsAbleToFly() const { return ableToFly; }
};
}
