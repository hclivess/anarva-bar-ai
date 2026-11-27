// What the terrain fields cost, so the per-tick build budget can be sized from measurement
// rather than guessed. Public API only: the first query builds the field, the second grows the
// approach sweep. Map sizes span a 1v1 map up to a large team map.
#include "AnarvaTerrain.h"

#include <chrono>
#include <cstdio>

namespace springai { int AIFloat3::maxxpos = 0; int AIFloat3::maxzpos = 0; }

using namespace circuit;
using Clock = std::chrono::steady_clock;

static double Ms(Clock::time_point a, Clock::time_point b)
{
	return std::chrono::duration<double, std::milli>(b - a).count();
}

int main()
{
	printf("%-8s %-10s %10s %10s %10s\n", "squares", "map", "build ms", "approach", "MB/movedef");
	for (int dim : {500, 750, 1250}) {
		const int w = dim, h = dim;
		springai::AIFloat3::maxxpos = w * SQUARE_SIZE;
		springai::AIFloat3::maxzpos = h * SQUARE_SIZE;

		CCircuitAI ai;
		terrain::SAreaData ad;
		ad.heightMapXSize = w;
		ad.heightMap.assign((size_t)w * h, 100.f);
		ai.tm.areaData = &ad;

		// coarse ridges about 40 slope cells across, which is the grain of real terrain; a fine
		// speckle would fragment the map and flatter nothing but the flood fill
		const int sw = w / 2, sh = h / 2;
		ai.m.slope.assign((size_t)sw * sh, 0.f);
		for (int sz = 0; sz < sh; ++sz) {
			for (int sx = 0; sx < sw; ++sx) {
				const unsigned bx = unsigned(sx / 40), bz = unsigned(sz / 40);
				const bool steep = (((bx * 73856093u) ^ (bz * 19349663u)) % 100u) < 12u;
				ai.m.slope[size_t(sz) * sw + sx] = steep ? 1.0f : 0.05f;
			}
		}

		terrain::SMobileType mt;
		mt.maxSlope = 0.41f;         // SLOPE.DIFFICULT, the bot tier
		mt.minElevation = -1000.f;
		mt.maxElevation = 1000.f;
		ai.tm.mobileTypes.assign(1, mt);

		CCircuitDef def;
		def.mobileTypeId = 0;
		def.moveXSize = 3;           // SBOT2, the smallest movedef in the game

		anarva::CTerrainFields tf;
		const auto t0 = Clock::now();
		tf.CanTraverse(&ai, &def, springai::AIFloat3(100.f, 0.f, 100.f));  // builds the field
		const auto t1 = Clock::now();

		// two squares that really are connected, so the sweep crosses the map instead of
		// stopping at the edge of a sealed pocket
		springai::AIFloat3 a, b;
		bool haveA = false, haveB = false;
		for (int z = 0; (z < h) && !haveA; ++z) {
			for (int x = 0; (x < w) && !haveA; ++x) {
				a = springai::AIFloat3(float(x * SQUARE_SIZE + 1), 0.f, float(z * SQUARE_SIZE + 1));
				haveA = tf.CanTraverse(&ai, &def, a);
			}
		}
		for (int z = h - 1; (z >= 0) && !haveB; --z) {
			for (int x = w - 1; (x >= 0) && !haveB; --x) {
				b = springai::AIFloat3(float(x * SQUARE_SIZE + 1), 0.f, float(z * SQUARE_SIZE + 1));
				haveB = tf.CanTraverse(&ai, &def, b) && tf.SameGround(&ai, &def, a, b);
			}
		}

		const auto t2 = Clock::now();
		tf.ApproachWidth(&ai, &def, a, b);
		const auto t3 = Clock::now();

		const double mb = (double)((size_t)w * h * (1 + 1 + 2 + 1 + 4)) / (1024.0 * 1024.0);
		char squares[32], map[32];
		snprintf(squares, sizeof(squares), "%dx%d", w, h);
		snprintf(map, sizeof(map), "%d elmo", w * SQUARE_SIZE);
		printf("%-8s %-10s %10.1f %10.1f %10.1f\n", squares, map, Ms(t0, t1), Ms(t2, t3), mb);
	}
	return 0;
}
