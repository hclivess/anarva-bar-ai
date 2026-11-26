// Drives AnarvaTerrain.h over hand-built terrain. Checks the four fields against values worked
// out by hand, and the Flea's real footprint (movedef xsize 3 -> needs clearance >= 1 square).
#include "AnarvaTerrain.h"

#include <cstdio>
#include <cstring>
#include <cstdlib>

namespace springai { int AIFloat3::maxxpos = 0; int AIFloat3::maxzpos = 0; }

using namespace circuit;

static int failures = 0;

static void Check(const char* what, long got, long want)
{
	const bool ok = (got == want);
	if (!ok) ++failures;
	printf("  %-46s got %5ld  want %5ld  %s\n", what, got, want, ok ? "ok" : "FAIL");
}

// A map built from a picture. '.' passable, '#' impassable (made so by slope).
// Each character is one 8-elmo square.
struct Scene {
	CCircuitAI ai;
	terrain::SAreaData areaData;
	int w = 0, h = 0;

	void Build(const char* const* rows, int rowCount, float maxSlope)
	{
		w = (int)strlen(rows[0]);
		h = rowCount;
		springai::AIFloat3::maxxpos = w * SQUARE_SIZE;
		springai::AIFloat3::maxzpos = h * SQUARE_SIZE;

		// height map: flat land at 100 elmos, so only slope decides passability
		areaData.heightMapXSize = w;
		areaData.heightMap.assign((size_t)w * h, 100.f);
		ai.tm.areaData = &areaData;

		// slope map is one cell per 2x2 squares; mark a cell steep if any of its squares is '#'
		const int sw = w / anarva::CTerrainFields::SLOPE_PER_TILE;
		const int sh = h / anarva::CTerrainFields::SLOPE_PER_TILE;
		ai.m.slope.assign((size_t)sw * sh, 0.f);
		for (int z = 0; z < h; ++z) {
			for (int x = 0; x < w; ++x) {
				if (rows[z][x] != '#') continue;
				const int sx = x / 2, sz = z / 2;
				if (sx < sw && sz < sh) ai.m.slope[(size_t)sz * sw + sx] = 1.0f;  // far above any maxSlope
			}
		}

		terrain::SMobileType mt;
		mt.maxSlope = maxSlope;
		mt.minElevation = -1000.f;   // land unit: no water here anyway
		mt.maxElevation = 1000.f;
		ai.tm.mobileTypes.assign(1, mt);
	}

	springai::AIFloat3 At(int x, int z) const
	{
		return springai::AIFloat3(float(x * SQUARE_SIZE + 1), 0.f, float(z * SQUARE_SIZE + 1));
	}
};

int main()
{
	// ---------------------------------------------------------------- clearance + footprint fit
	// A wall across the middle with a gap. The gap is 4 squares wide (32 elmos) at squares x=6..9.
	// Slope cells are 2x2, so the wall occupies whole slope cells and the gap is exactly 2 cells.
	{
		static const char* rows[] = {
			"................",
			"................",
			"................",
			"................",
			"######....######",
			"######....######",
			"................",
			"................",
			"................",
			"................",
		};
		Scene s;
		s.Build(rows, 10, 0.5f);

		CCircuitDef flea;          // SBOT2: movedef footprint 2 -> xsize 3 squares (24 elmos)
		flea.mobileTypeId = 0;
		flea.moveXSize = 3;

		anarva::CTerrainFields tf;
		printf("clearance and fit, 32-elmo gap (4 squares at x=6..9, wall rows z=4..5)\n");

		Check("passable inside the gap", tf.CanTraverse(&s.ai, &flea, s.At(7, 4)) ? 1 : 0, 1);
		Check("impassable inside the wall", tf.CanTraverse(&s.ai, &flea, s.At(2, 4)) ? 1 : 0, 0);

		// square (6,4) touches the wall at x=5, so L-inf clearance is 1
		Check("clearance at gap edge (elmos)", (long)tf.ClearanceAt(&s.ai, &flea, s.At(6, 4)), 8);
		// square (7,4): nearest impassable is x=5 (distance 2) and x=10 (distance 3) -> 2
		Check("clearance mid-gap (elmos)", (long)tf.ClearanceAt(&s.ai, &flea, s.At(7, 4)), 16);

		// Flea needs xsize/2 = 1 square of clearance; it fits even at the gap edge
		Check("Flea fits at gap edge", tf.Fits(&s.ai, &flea, s.At(6, 4)) ? 1 : 0, 1);

		CCircuitDef big;           // a 7-square footprint (56 elmos), e.g. HTANK4
		big.mobileTypeId = 0;
		big.moveXSize = 7;         // needs clearance >= 3 squares = 24 elmos
		Check("56-elmo unit does not fit mid-gap", tf.Fits(&s.ai, &big, s.At(7, 4)) ? 1 : 0, 0);

		// ---------------------------------------------------------------- approach (maximin)
		// Crossing the wall, the only way through is the gap, whose narrowest clearance is 2 squares.
		springai::AIFloat3 at;
		const float width = tf.ApproachWidth(&s.ai, &flea, s.At(1, 1), s.At(14, 8), &at);
		Check("approach width through the gap (elmos)", (long)width, 16);
		Check("narrowest point sits in the gap (x)", (long)(at.x / SQUARE_SIZE) >= 6
			  && (long)(at.x / SQUARE_SIZE) <= 9 ? 1 : 0, 1);

		// ---------------------------------------------------------------- same ground
		Check("both sides are one region (gap joins)",
			  tf.SameGround(&s.ai, &flea, s.At(1, 1), s.At(14, 8)) ? 1 : 0, 1);
	}

	// ---------------------------------------------------------------- components: sealed wall
	{
		static const char* rows[] = {
			"........",
			"........",
			"########",
			"########",
			"........",
			"........",
		};
		Scene s;
		s.Build(rows, 6, 0.5f);
		CCircuitDef flea;
		flea.mobileTypeId = 0;
		flea.moveXSize = 3;
		anarva::CTerrainFields tf;
		printf("\nsealed wall: the two halves are separate ground\n");
		Check("north and south not the same region",
			  tf.SameGround(&s.ai, &flea, s.At(1, 0), s.At(1, 5)) ? 1 : 0, 0);
		Check("approach width across a sealed wall", (long)tf.ApproachWidth(&s.ai, &flea, s.At(1, 0), s.At(1, 5)), 0);
	}

	// ---------------------------------------------------------------- maximin prefers the wide way
	// Two ways through: a narrow gap at x=2..3 (2 squares, so clearance 1) and a wide one at
	// x=10..15 (6 squares, clearance 3). Open ground 4 squares deep on each side of the wall, so
	// the approach itself does not pinch below 2. Sealing the wide gap must drop the answer.
	{
		static const char* open[] = {
			"................",
			"................",
			"................",
			"................",
			"##..######......",
			"##..######......",
			"................",
			"................",
			"................",
			"................",
		};
		static const char* sealed[] = {
			"................",
			"................",
			"................",
			"................",
			"##..############",
			"##..############",
			"................",
			"................",
			"................",
			"................",
		};
		CCircuitDef flea;
		flea.mobileTypeId = 0;
		flea.moveXSize = 3;
		printf("\ntwo ways through: the wide gap sets the width, sealing it falls back to the narrow\n");

		Scene a;
		a.Build(open, 10, 0.5f);
		anarva::CTerrainFields tfa;
		springai::AIFloat3 at;
		Check("width with the wide gap open (elmos)",
			  (long)tfa.ApproachWidth(&a.ai, &flea, a.At(1, 1), a.At(1, 8), &at), 16);
		Check("narrowest point is not in the narrow gap",
			  ((long)(at.x / SQUARE_SIZE) >= 2 && (long)(at.x / SQUARE_SIZE) <= 3) ? 1 : 0, 0);

		Scene b;
		b.Build(sealed, 10, 0.5f);
		anarva::CTerrainFields tfb;
		springai::AIFloat3 atb;
		const float sealedWidth = tfb.ApproachWidth(&b.ai, &flea, b.At(1, 1), b.At(1, 8), &atb);
		Check("width with only the narrow gap (elmos)", (long)sealedWidth, 8);
		// What Narrowest guarantees: the square it names is as narrow as the route. It does NOT
		// guarantee the square is the gap -- at clearance 1 a 2-square gap and a square tucked
		// against a wall are indistinguishable by room alone. Telling a separating pinch from a
		// merely cramped square needs a cut test, which the script layer wants on top of this.
		Check("named square is as narrow as the route (elmos)",
			  (long)tfb.ClearanceAt(&b.ai, &flea, atb), (long)sealedWidth);
	}

	// ---------------------------------------------------------------- per-unit: slope decides
	{
		// a ridge whose slope is 0.25: passable for a DIFFICULT-tier unit (0.41), not for MODERATE (0.161)
		static const char* rows[] = {
			"........",
			"........",
			"........",
			"........",
		};
		Scene s;
		s.Build(rows, 4, 0.41f);
		// make the middle slope cells 0.25
		const int sw = 8 / 2;
		s.ai.m.slope[(size_t)1 * sw + 1] = 0.25f;

		anarva::CTerrainFields bots, vehicles;
		CCircuitDef bot;
		bot.mobileTypeId = 0;
		bot.moveXSize = 3;
		printf("\nsame ground, different movedef: slope 0.25 ridge\n");
		Check("bot tier (maxSlope 0.41) crosses it", bots.CanTraverse(&s.ai, &bot, s.At(2, 2)) ? 1 : 0, 1);

		s.ai.tm.mobileTypes[0].maxSlope = 0.161f;  // MODERATE, the vehicle tier
		Check("vehicle tier (maxSlope 0.161) does not", vehicles.CanTraverse(&s.ai, &bot, s.At(2, 2)) ? 1 : 0, 0);
	}

	printf("\n%s (%d failure%s)\n", failures ? "FAILURES" : "all checks passed",
		   failures, failures == 1 ? "" : "s");
	return failures ? 1 : 0;
}
