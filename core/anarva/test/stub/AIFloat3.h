#pragma once
namespace springai {
struct AIFloat3 {
	float x = 0.f, y = 0.f, z = 0.f;
	AIFloat3() {}
	AIFloat3(float X, float Y, float Z) : x(X), y(Y), z(Z) {}
	static int maxxpos, maxzpos;
};
}
