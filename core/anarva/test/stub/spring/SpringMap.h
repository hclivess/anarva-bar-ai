#pragma once
#include "util/Defines.h"
namespace circuit {
class CMap {
public:
	FloatVec slope;
	void GetSlopeMap(FloatVec& out) const { out = slope; }
};
}
