/*
 * AnarvaTerrain.h
 *
 * Map awareness read from the live game (#98): for any unit, which ground it can cross, how much
 * room it has there, which ground it can reach at all, and how narrow the widest way in is.
 *
 * Replaces the offline map table (mapfacts.as, tools/analyze_maps.py), which masked the height map
 * with one hand-picked slope (0.41, the bot tier) for every unit, covered only the maps it had been
 * run on, and could not see terrain change in game. Everything here is derived from facts the engine
 * already holds: the queried unit's own movedef limits, the live height map and the live slope map.
 * No map table, no tuned constants.
 *
 * Grids are the engine's own, and they differ:
 *   height map  HEIGHT_TILE = SQUARE_SIZE      = 8 elmos
 *   slope map   SLOPE_TILE  = SQUARE_SIZE * 2  = 16 elmos
 *   footprints  a movedef's xsize is a count of 8-elmo squares, forced odd by the engine so the
 *               footprint has a unique centre square (Flea/SBOT2: footprint 2 -> xsize 3 -> 24 elmos)
 *
 * The fields are kept at 8 elmos, so the water term and every footprint threshold are exact, and
 * each square takes the slope of the 16-elmo cell containing it. That mirrors the core's own
 * CTerrainData::IsWalkable, which indexes the slope map and samples height at the slope cell: slope
 * is simply not defined finer than 16 elmos, so a unit needing 24 elmos of ground in practice needs
 * two clear slope cells unless the gap happens to align.
 *
 * Per movedef, built on first use and dropped when the terrain epoch moves on:
 *   mask       can a unit of this movedef stand on this square
 *   clearance  Chebyshev (L-inf) distance in squares to the nearest square it cannot stand on.
 *              L-inf rather than Euclidean because the footprint is a square block of xsize
 *              squares: it fits exactly when clearance >= xsize / 2, the engine's own half-size.
 *   component  connected traversable region. Two squares are mutually reachable over terrain when
 *              their ids match, so reachability costs a lookup instead of a path query.
 *   approach   widest-bottleneck width from a source square: over all routes, the one whose
 *              narrowest point is as wide as possible, and that width. The room an attacker coming
 *              from the source has, and what it must squeeze through to arrive.
 *
 * Read-only: nothing here changes what the core does, so there is no switch (see AnarvaSwitches.h).
 */

#ifndef SRC_CIRCUIT_UTIL_ANARVATERRAIN_H_
#define SRC_CIRCUIT_UTIL_ANARVATERRAIN_H_

#include "terrain/TerrainManager.h"
#include "terrain/TerrainData.h"
#include "unit/CircuitDef.h"
#include "spring/SpringMap.h"
#include "util/GameAttribute.h"
#include "util/Defines.h"
#include "CircuitAI.h"

#include "AIFloat3.h"

#include <algorithm>
#include <cstdint>
#include <queue>
#include <unordered_map>
#include <vector>

namespace circuit {
namespace anarva {

class CTerrainFields {
public:
	static constexpr int TILE = SQUARE_SIZE;            // 8 elmos: the field's square
	static constexpr int SLOPE_PER_TILE = SLOPE_TILE / SQUARE_SIZE;  // 2 field squares per slope cell
	static constexpr uint8_t CLEAR_MAX = 255;           // saturating; 255 squares = 2040 elmos
	static constexpr uint16_t NO_COMPONENT = 0;

	struct SField {
		std::vector<uint8_t> mask;       // 1 = this movedef can stand here
		std::vector<uint8_t> clearance;  // squares to the nearest square it cannot stand on
		std::vector<uint16_t> component;  // 0 = impassable, else region id
		std::vector<uint8_t> approach;   // squares; 0 = not reached from approachFrom
		std::vector<int32_t> approachPrev;  // the widest route's previous square, -1 at the source
		int approachFrom = -1;           // square index the approach field was grown from
		int epoch = -1;                  // terrain epoch this was built for

		bool IsBuilt() const { return !mask.empty(); }
	};

	CTerrainFields() : width(0), height(0), epoch(0) {}

	// A new epoch drops every cached field: the next query rebuilds from the current terrain.
	// Called on the cadence the core already re-derives its own area data on, not per explosion:
	// a rebuild is milliseconds, and deformation rarely changes who can walk where.
	void Invalidate() { ++epoch; }
	int GetEpoch() const { return epoch; }

	int GetWidth() const { return width; }
	int GetHeight() const { return height; }

	// --- queries; all take the def whose movedef decides what counts as passable ---

	bool CanTraverse(CCircuitAI* circuit, CCircuitDef* cdef, const springai::AIFloat3& pos)
	{
		if (cdef == nullptr) {
			return false;
		}
		if (cdef->IsAbleToFly()) {
			return true;  // air has no terrain to cross
		}
		const SField* f = Field(circuit, cdef);
		const int i = Index(pos);
		return (f != nullptr) && (i >= 0) && (f->mask[i] != 0);
	}

	// Room at this point, in elmos: distance to the nearest ground this unit cannot stand on.
	float ClearanceAt(CCircuitAI* circuit, CCircuitDef* cdef, const springai::AIFloat3& pos)
	{
		if ((cdef != nullptr) && cdef->IsAbleToFly()) {
			return float(CLEAR_MAX * TILE);
		}
		const SField* f = Field(circuit, cdef);
		const int i = Index(pos);
		if ((f == nullptr) || (i < 0)) {
			return 0.f;
		}
		return float(f->clearance[i]) * float(TILE);
	}

	// Does this unit's footprint fit here? The engine's own condition: a unit occupies a block of
	// xsize squares centred on its square, so it fits when the L-inf clearance covers the half-size.
	bool Fits(CCircuitAI* circuit, CCircuitDef* cdef, const springai::AIFloat3& pos)
	{
		if (cdef == nullptr) {
			return false;
		}
		if (cdef->IsAbleToFly()) {
			return true;
		}
		const SField* f = Field(circuit, cdef);
		const int i = Index(pos);
		if ((f == nullptr) || (i < 0)) {
			return false;
		}
		return int(f->clearance[i]) >= (cdef->GetMoveXSize() / 2);
	}

	// Terrain reachability without a path query: the same traversable region, or not.
	// Blockers (buildings, wrecks) are deliberately not considered here -- they change constantly,
	// while terrain does not; ask the core's pathfinder when the answer must include them.
	bool SameGround(CCircuitAI* circuit, CCircuitDef* cdef, const springai::AIFloat3& a,
					const springai::AIFloat3& b)
	{
		if (cdef == nullptr) {
			return false;
		}
		if (cdef->IsAbleToFly()) {
			return true;
		}
		const SField* f = Field(circuit, cdef);
		const int ia = Index(a), ib = Index(b);
		if ((f == nullptr) || (ia < 0) || (ib < 0)) {
			return false;
		}
		const uint16_t ca = f->component[ia];
		return (ca != NO_COMPONENT) && (ca == f->component[ib]);
	}

	// The width, in elmos, of the widest way from `from` to `to` for this unit: over every route,
	// the one whose narrowest point is widest, and that narrowest width. 0 when it cannot get there.
	// `outAt` receives where that narrowest point is.
	float ApproachWidth(CCircuitAI* circuit, CCircuitDef* cdef, const springai::AIFloat3& from,
						const springai::AIFloat3& to, springai::AIFloat3* outAt = nullptr)
	{
		if (cdef == nullptr) {
			return 0.f;
		}
		if (cdef->IsAbleToFly()) {
			return float(CLEAR_MAX * TILE);
		}
		SField* f = Field(circuit, cdef);
		const int src = Index(from), dst = Index(to);
		if ((f == nullptr) || (src < 0) || (dst < 0)) {
			return 0.f;
		}
		if (f->approachFrom != src) {
			GrowApproach(*f, src);
		}
		const uint8_t w = f->approach[dst];
		if ((w != 0) && (outAt != nullptr)) {
			*outAt = Narrowest(*f, src, dst);
		}
		return float(w) * float(TILE);
	}

private:
	int width, height;          // in field squares
	int epoch;
	std::unordered_map<int, SField> byMove;  // key = movedef id (CCircuitDef::GetMobileId())

	int Index(const springai::AIFloat3& pos) const
	{
		if ((width <= 0) || (height <= 0)) {
			return -1;
		}
		const int x = int(pos.x) / TILE;
		const int z = int(pos.z) / TILE;
		if ((x < 0) || (z < 0) || (x >= width) || (z >= height)) {
			return -1;
		}
		return z * width + x;
	}

	springai::AIFloat3 Pos(int i) const
	{
		const int x = i % width, z = i / width;
		return springai::AIFloat3(float(x * TILE + TILE / 2), 0.f, float(z * TILE + TILE / 2));
	}

	// The cached field for this def's movedef, built if missing or stale. null when the def has no
	// movedef at all (a structure, or air -- callers short-circuit those).
	SField* Field(CCircuitAI* circuit, CCircuitDef* cdef)
	{
		if ((cdef == nullptr) || (cdef->GetMobileId() < 0)) {
			return nullptr;
		}
		SField& f = byMove[cdef->GetMobileId()];
		if (!f.IsBuilt() || (f.epoch != epoch)) {
			Build(circuit, cdef, f);
		}
		return f.IsBuilt() ? &f : nullptr;
	}

	void Build(CCircuitAI* circuit, CCircuitDef* cdef, SField& f)
	{
		CTerrainManager* terrainMgr = circuit->GetTerrainManager();
		terrain::SMobileType* mt = terrainMgr->GetMobileTypeById(cdef->GetMobileId());
		if (mt == nullptr) {
			f = SField();
			return;
		}
		terrain::SAreaData* areaData = terrainMgr->GetAreaData();
		const FloatVec& heightMap = areaData->heightMap;
		const int hStride = areaData->heightMapXSize;
		if (heightMap.empty() || (hStride <= 0)) {
			f = SField();
			return;
		}

		FloatVec slopeMap;
		circuit->GetMap()->GetSlopeMap(slopeMap);

		width = CTerrainManager::GetTerrainWidth() / TILE;
		height = CTerrainManager::GetTerrainHeight() / TILE;
		width = std::min(width, hStride);
		const int sStride = width / SLOPE_PER_TILE;
		const int n = width * height;

		f.mask.assign(n, 0);
		f.approach.clear();
		f.approachFrom = -1;
		f.epoch = epoch;

		// The core's own walkability rule (CTerrainData::IsWalkable), fed by this movedef's limits
		// instead of the single reference type the core analyses the map with.
		const terrain::CTerrainData& td = circuit->GetGameAttribute()->GetTerrainData();
		const bool waterHarmful = td.waterIsHarmful;
		const bool waterVoid = td.waterIsAVoid;
		for (int z = 0; z < height; ++z) {
			for (int x = 0; x < width; ++x) {
				const float elevation = heightMap[z * hStride + x];
				float slope = 0.f;
				if (sStride > 0) {
					const int sx = std::min(x / SLOPE_PER_TILE, sStride - 1);
					const int sz = z / SLOPE_PER_TILE;
					const size_t si = size_t(sz) * size_t(sStride) + size_t(sx);
					if (si < slopeMap.size()) {
						slope = slopeMap[si];
					}
				}
				const bool ok =
					(mt->canHover && (mt->maxElevation >= elevation) && !waterVoid
						&& ((elevation <= 0.f) || (mt->maxSlope >= slope)))
					|| (mt->canFloat && (mt->maxElevation >= elevation) && !waterHarmful
						&& ((elevation <= 0.f) || (mt->maxSlope >= slope)))
					|| ((mt->maxSlope >= slope) && (mt->minElevation <= elevation)
						&& (mt->maxElevation >= elevation) && (!waterHarmful || (elevation >= 0.f)));
				f.mask[z * width + x] = ok ? 1 : 0;
			}
		}

		BuildClearance(f);
		BuildComponents(f);
	}

	// Chebyshev distance transform, two passes. An impassable square is 0; off-map reads as
	// impassable too, so the map edge limits room exactly as a cliff would. Each pass only reads
	// neighbours it has already written, which is what makes two passes exact for L-inf.
	void BuildClearance(SField& f)
	{
		const int n = width * height;
		f.clearance.assign(n, 0);
		auto at = [&](int x, int z) -> int {
			if ((x < 0) || (z < 0) || (x >= width) || (z >= height)) {
				return 0;
			}
			return int(f.clearance[z * width + x]);
		};
		for (int z = 0; z < height; ++z) {
			for (int x = 0; x < width; ++x) {
				const int i = z * width + x;
				if (f.mask[i] == 0) {
					continue;
				}
				const int best = std::min({at(x - 1, z), at(x, z - 1),
										   at(x - 1, z - 1), at(x + 1, z - 1)}) + 1;
				f.clearance[i] = uint8_t(std::min(best, int(CLEAR_MAX)));
			}
		}
		for (int z = height - 1; z >= 0; --z) {
			for (int x = width - 1; x >= 0; --x) {
				const int i = z * width + x;
				if (f.mask[i] == 0) {
					continue;
				}
				const int best = std::min({at(x + 1, z), at(x, z + 1),
										   at(x + 1, z + 1), at(x - 1, z + 1)}) + 1;
				f.clearance[i] = uint8_t(std::min(int(f.clearance[i]), std::min(best, int(CLEAR_MAX))));
			}
		}
	}

	// Connected traversable regions, 8-connected (a unit crosses a diagonal join).
	void BuildComponents(SField& f)
	{
		const int n = width * height;
		f.component.assign(n, NO_COMPONENT);
		uint16_t next = NO_COMPONENT;
		std::vector<int> stack;
		for (int start = 0; start < n; ++start) {
			if ((f.mask[start] == 0) || (f.component[start] != NO_COMPONENT)) {
				continue;
			}
			if (next == 0xFFFF) {
				break;  // more regions than an id can hold; the rest stay unreachable-by-lookup
			}
			++next;
			stack.clear();
			stack.push_back(start);
			f.component[start] = next;
			while (!stack.empty()) {
				const int i = stack.back();
				stack.pop_back();
				const int x = i % width, z = i / width;
				for (int dz = -1; dz <= 1; ++dz) {
					for (int dx = -1; dx <= 1; ++dx) {
						if ((dx == 0) && (dz == 0)) {
							continue;
						}
						const int nx = x + dx, nz = z + dz;
						if ((nx < 0) || (nz < 0) || (nx >= width) || (nz >= height)) {
							continue;
						}
						const int j = nz * width + nx;
						if ((f.mask[j] != 0) && (f.component[j] == NO_COMPONENT)) {
							f.component[j] = next;
							stack.push_back(j);
						}
					}
				}
			}
		}
	}

	// Widest-bottleneck (maximin) spread from one square: approach[i] is the largest value of the
	// narrowest clearance along any route src -> i. Dijkstra with max-of-min instead of sum.
	void GrowApproach(SField& f, int src)
	{
		const int n = width * height;
		f.approach.assign(n, 0);
		f.approachPrev.assign(n, -1);
		f.approachFrom = src;
		if ((src < 0) || (src >= n) || (f.mask[src] == 0)) {
			return;
		}
		// A bucket queue, not a heap: a route's width is a square count in 0..CLEAR_MAX, and widening
		// never happens -- entering a square can only narrow the route -- so one sweep from the
		// widest bucket down to the narrowest visits every square once. O(squares), no log factor.
		//
		// The source is seeded wide open, not with its own clearance: how much room a unit has where
		// it already stands says nothing about the way out. A base in a map corner has a clearance of
		// a square or two, and counting it would report every route off the map as that narrow.
		std::vector<std::vector<int>> bucket(size_t(CLEAR_MAX) + 1);
		f.approach[src] = CLEAR_MAX;
		bucket[CLEAR_MAX].push_back(src);
		for (int w = CLEAR_MAX; w > 0; --w) {
			std::vector<int>& cur = bucket[size_t(w)];
			while (!cur.empty()) {
				const int i = cur.back();
				cur.pop_back();
				if (int(f.approach[i]) != w) {
					continue;  // already reached by a wider route
				}
				const int x = i % width, z = i / width;
				for (int dz = -1; dz <= 1; ++dz) {
					for (int dx = -1; dx <= 1; ++dx) {
						if ((dx == 0) && (dz == 0)) {
							continue;
						}
						const int nx = x + dx, nz = z + dz;
						if ((nx < 0) || (nz < 0) || (nx >= width) || (nz >= height)) {
							continue;
						}
						const int j = nz * width + nx;
						if (f.mask[j] == 0) {
							continue;
						}
						const int nw = std::min(w, int(f.clearance[j]));
						if (nw > int(f.approach[j])) {
							f.approach[j] = uint8_t(nw);
							f.approachPrev[j] = i;
							bucket[size_t(nw)].push_back(j);
						}
					}
				}
			}
		}
	}

	// Where the widest route to dst is at its narrowest. Several squares on a route often share the
	// narrowest width -- a corridor is narrow along its whole length, and squares beside the map edge
	// are narrow wherever they are -- so among them take the one nearest the middle of the route,
	// which is the pinch between the two ends rather than either end's own surroundings.
	springai::AIFloat3 Narrowest(const SField& f, int src, int dst) const
	{
		std::vector<int> route;
		route.reserve(64);
		for (int i = dst, guard = width * height; (i >= 0) && (guard-- > 0); i = f.approachPrev[i]) {
			route.push_back(i);
			if (i == src) {
				break;
			}
		}
		if (route.empty()) {
			return Pos(dst);
		}
		int best = -1;
		int bestClear = int(CLEAR_MAX) + 1;
		int bestOffCentre = 0;
		const int mid = int(route.size()) / 2;
		for (int k = 0; k < int(route.size()); ++k) {
			const int i = route[k];
			if (i == src) {
				continue;  // the source was seeded wide open; its own room is not the route's
			}
			const int c = int(f.clearance[i]);
			const int offCentre = std::abs(k - mid);
			if ((c < bestClear) || ((c == bestClear) && (offCentre < bestOffCentre))) {
				bestClear = c;
				bestOffCentre = offCentre;
				best = i;
			}
		}
		return Pos((best >= 0) ? best : dst);
	}
};

inline CTerrainFields terrainFields;

} // namespace anarva
} // namespace circuit

#endif // SRC_CIRCUIT_UTIL_ANARVATERRAIN_H_
