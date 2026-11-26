--------------------------------------------------------------------------------
--  Run BAR's unit-definition chain outside the game.
--  Driven by tools/gen_facts.py's scan_chain(); see its docstring for why.
--
--  Runs under LuaJIT 2.1 (Lua 5.1 semantics), which is what Recoil uses and
--  what analyze_maps.py already brings in.
--
--  scan() evaluates each units/*.lua on its own, which gets the literals and
--  anything the file computes for itself. What it cannot see is what the game
--  does to those tables afterwards. Here the whole chain runs:
--
--      init.lua                     the BAR global, common/ helpers
--      gamedata/unitdefs.lua        every units/*.lua into an env whose
--                                   __index is gamedata/system.lua
--      gamedata/unitdefs_post.lua   BAR's modifications, which assign raptor
--                                   costs and generate the scavenger variants
--
--  Two things are deliberately NOT emulated, because the engine's own
--  def-parsing environment does not have them either:
--
--    Script.GetName   left nil, which makes init.lua select the "LuaParser"
--                     environment -- the one the engine uses to parse defs.
--                     That keeps i18n, commands and graphics out of the
--                     dependency graph.
--    modoptions       only what the driver passes. Unit families are gated on
--                     them, so the choice is explicit rather than accidental.
--
--  Supplied by the driver before this file runs:
--      _HOST_READ(path)       file contents as a string, or nil
--      _HOST_EXISTS(path)     over the FULL package manifest, not just the
--                             .lua we can read, so the model-file check in
--                             unitdefs.lua does not wrongly delete units
--      _HOST_LIST(dir, pat, recursive)
--      _HOST_WARN(msg)
--      _HOST_RESULT(table, count)
--      _HOST_MODOPTIONS, _HOST_ENGINE_VERSION
--------------------------------------------------------------------------------

local host = { read = _HOST_READ, exists = _HOST_EXISTS, list = _HOST_LIST }

--------------------------------------------------------------------------------
--  VFS
--------------------------------------------------------------------------------

VFS = {
	-- Mode constants. The engine picks archives with these; we have a single
	-- flattened view, so they only need to exist and concatenate.
	RAW = "r", MOD = "M", MAP = "m", BASE = "b", MENU = "e", ZIP = "z",
	RAW_FIRST = "rz", ZIP_FIRST = "zr",
}

function VFS.LoadFile(path)
	return host.read(path)
end

function VFS.FileExists(path)
	return host.exists(path)
end

function VFS.DirList(dir, pattern, _mode, recursive)
	return host.list(dir, pattern or "*", recursive and true or false)
end

function VFS.SubDirs()
	return {}
end

function VFS.Include(path, env)
	local src = host.read(path)
	if src == nil then
		error("VFS.Include: file not found: " .. tostring(path), 2)
	end
	local chunk, err = loadstring(src, "@" .. path)
	if chunk == nil then
		error("VFS.Include: parse error in " .. path .. ": " .. tostring(err), 2)
	end
	if env == nil then
		-- Match the engine: with no explicit env the file runs in the caller's.
		local ok, callerEnv = pcall(getfenv, 2)
		env = ok and callerEnv or _G
	end
	setfenv(chunk, env)
	return chunk()
end

--------------------------------------------------------------------------------
--  Spring
--
--  A coherent 1v1 plus Gaia. common/springUtilities/teamFunctions.lua derives
--  the whole gametype (isScavengers, isRaptors, isFFA...) by walking ally
--  teams, team info and LuaAI names, and gamedata/unitdefs.lua calls into that
--  before deciding which unit families to load. So this has to be consistent,
--  not a pile of nils. No LuaAI, so family selection comes from the modoptions
--  the driver passes rather than from an accidental lobby shape.
--------------------------------------------------------------------------------

Script = {}  -- no GetName: see the header

LOG = { DEBUG = 0, INFO = 1, NOTICE = 2, WARNING = 3, ERROR = 4, FATAL = 5 }

local modOptions = _HOST_MODOPTIONS or {}
local GAIA_TEAM = 2

Spring = {
	GetModOptions = function() return modOptions end,
	GetModOption = function(k, d)
		local v = modOptions[k]
		if v == nil then return d end
		return v
	end,

	Echo = function() end,
	Log = function(section, level, msg)
		if level == LOG.ERROR or level == LOG.FATAL then
			_HOST_WARN(tostring(section) .. ": " .. tostring(msg))
		end
	end,
	TimeCheck = function(_, fn) return fn() end,

	GetConfigInt = function(_, d) return d or 0 end,
	GetConfigFloat = function(_, d) return d or 0 end,
	GetConfigString = function(_, d) return d or "" end,

	GetGameFrame = function() return 0 end,
	GetGameRulesParam = function() return nil end,
	GetTeamRulesParam = function() return nil end,
	GetTeamRulesParams = function() return {} end,
	SetGameRulesParam = function() end,
	SetTeamRulesParam = function() end,
	IsCheatingEnabled = function() return false end,
	GetSpringVersion = function() return "105" end,

	GetGaiaTeamID = function() return GAIA_TEAM end,
	GetAllyTeamList = function() return { 0, 1, 2 } end,
	GetTeamList = function(allyTeamID)
		if allyTeamID == nil then return { 0, 1, 2 } end
		return { allyTeamID }
	end,
	-- teamID, leader, isDead, isAiTeam, side, allyTeamID, incomeMultiplier, custom
	GetTeamInfo = function(teamID)
		return teamID, teamID, false, false,
			(teamID == 0 and "armada" or "cortex"), teamID, 1.0, {}
	end,
	GetPlayerList = function(teamID)
		if teamID == GAIA_TEAM then return {} end
		return { teamID }
	end,
	GetPlayerInfo = function(playerID)
		return "player" .. tostring(playerID), true, false, playerID, playerID
	end,
	GetTeamLuaAI = function() return nil end,
	GetTeamMaxUnits = function() return 2000 end,
	GetTeamUnitCount = function() return 0 end,

	-- Never reached while parsing defs; present so a stray call degrades to a
	-- harmless value instead of a nil-call traceback.
	GetGroundHeight = function() return 0 end,
	GetGroundNormal = function() return 0, 1, 0 end,
	GetGroundExtremes = function() return 0, 100 end,
	GetMetalMapSize = function() return 0, 0 end,
	GetMetalAmount = function() return 0 end,
	GetAllFeatures = function() return {} end,
	GetUnitPosition = function() return nil end,
	GetFacingFromHeading = function() return 0 end,
	GetHeadingFromFacing = function() return 0 end,
	MarkerAddPoint = function() end,
	TestBuildOrder = function() return 0 end,
	Pos2BuildPos = function(_, x, y, z) return x, y, z end,

	Utilities = {},
}

--------------------------------------------------------------------------------
--  Game and Engine
--
--  Game must be POPULATED, not absent and not empty.
--  gamedata/alldefs_post.lua reads Game.gameSpeed, while
--  common/springUtilities/color.lua opens with `if not Game then return end`
--  and then indexes Game.textColorCodes -- an empty stub passes the guard and
--  dies on the next line. Engine.FeatureSupport is read during init.
--------------------------------------------------------------------------------

Game = {
	gameSpeed = 30,
	maxUnits = 32000,
	speedModClasses = { Tank = 0, KBot = 1, Hover = 2, Ship = 3 },
	textColorCodes = { Color = "\255", ColorAndOutline = "\254", Reset = "\008" },
}

local ev = _HOST_ENGINE_VERSION or "2026.09.03"
local maj, min, pat = string.match(ev, "^(%d+)%.(%d+)%.(%d+)")

Engine = {
	version = ev,
	versionMajor = tonumber(maj) or 2026,
	versionMinor = tonumber(min) or 9,
	versionPatchSet = tonumber(pat) or 3,
	commitsNumber = 0,
	-- Modern engine: the historical quirks these guard against are all fixed,
	-- and none of them influences a unitdef value.
	FeatureSupport = {
		noOffsetForFeatureID = true,
		smoothCameraHeightTracking = true,
		targetBorderBug = false,
	},
}

gl = nil

--------------------------------------------------------------------------------
--  Run the chain
--------------------------------------------------------------------------------

VFS.Include("init.lua", _G)

local unitDefs = VFS.Include("gamedata/unitdefs.lua", nil, VFS.ZIP)

--------------------------------------------------------------------------------
--  Project to the same facts scan() reads
--
--  Field selection and the rules below mirror gen_facts.py's scan() exactly,
--  so scan_chain() returns the identical shape and main() needs no changes.
--------------------------------------------------------------------------------

-- As _num(): numbers pass, booleans do not, strings may be "a" or "a / b"
-- because customparams hold numbers as text.
local function num(v)
	local t = type(v)
	if t == "number" then
		return v
	elseif t == "string" then
		local a, b = string.match(v, "^%s*(-?[%d.]+)%s*/%s*([%d.]+)%s*$")
		if a and b and tonumber(b) ~= 0 then
			return tonumber(a) / tonumber(b)
		end
		local only = string.match(v, "^%s*(-?[%d.]+)%s*$")
		if only then
			return tonumber(only)
		end
	end
	return nil
end

-- As _find(): every value of `key` anywhere in the table. Weapon and
-- customparams facts live nested, so a top-level read would miss them.
local function findAll(t, key, out, depth)
	out = out or {}
	depth = depth or 0
	if type(t) ~= "table" or depth > 8 then
		return out
	end
	for k, v in pairs(t) do
		if type(k) == "string" and string.lower(k) == key then
			out[#out + 1] = v
		end
		findAll(v, key, out, depth + 1)
	end
	return out
end

local function maxNum(t, key)
	local best = nil
	local vals = findAll(t, key)
	for i = 1, #vals do
		local n = num(vals[i])
		if n ~= nil and (best == nil or n > best) then
			best = n
		end
	end
	return best
end

local SCALARS = {
	"metalcost", "energycost", "workertime", "extractsmetal", "energyupkeep",
	"buildtime", "metalmake", "energymake", "speed", "radardistance",
	"sightdistance", "cloakcost", "cloakcostmoving", "mincloakdistance",
}

local out = {}
local count = 0

for name, def in pairs(unitDefs) do
	if type(name) == "string" and type(def) == "table" then
		local row = {}

		for i = 1, #SCALARS do
			local k = SCALARS[i]
			local n = num(def[k])
			if n ~= nil then
				row[k] = n
			end
		end

		local cp = type(def.customparams) == "table" and def.customparams or {}
		local isc = cp.iscommander
		row.commander = (isc == true or isc == "true" or isc == "1" or isc == 1) and 1 or 0

		row.canresurrect = (def.canresurrect == true) and 1 or 0

		local par = findAll(def, "paralyzer")
		local isPar = 0
		for i = 1, #par do
			if par[i] == true then isPar = 1 break end
		end
		row.paralyzer = isPar

		-- Crawling bombs identify themselves by their explosion, not a flag.
		local ea = string.lower(tostring(def.explodeas or ""))
		local sa = string.lower(tostring(def.selfdestructas or ""))
		row.crawl = (string.sub(ea, 1, 5) == "crawl" or
		             string.sub(sa, 1, 5) == "crawl") and 1 or 0

		local cap = findAll(def, "energyconv_capacity")
		local eff = findAll(def, "energyconv_efficiency")
		if #cap > 0 and #eff > 0 then
			local c, e = num(cap[1]), num(eff[1])
			if c ~= nil and e ~= nil then
				row.conv_capE = c
				row.conv_eff = e
			end
		end

		local st = maxNum(def, "stockpiletime")
		if st ~= nil then row.stockpiletime = st end

		local mps = maxNum(def, "metalpershot")
		if mps ~= nil and mps > 0 then row.metalpershot = mps end

		local sr = maxNum(def, "shield_radius")
		if sr ~= nil then row.shieldradius = sr end

		-- A 'g' cell in the yardmap means the building must stand on a
		-- geothermal vent (engine yardmap code; a leading 'h' marks the
		-- high-resolution format).
		local ym = def.yardmap
		if type(ym) == "string" then
			local cells = string.lower(string.gsub(ym, " ", ""))
			if string.sub(cells, 1, 1) == "h" then
				cells = string.sub(cells, 2)
			end
			if string.find(cells, "g", 1, true) then
				row.needgeo = 1
			end
		end

		-- Post-pruned: gamedata/unitdefs.lua deletes options whose target
		-- unitDef does not exist.
		local bo = def.buildoptions
		if type(bo) == "table" then
			local list = {}
			for i = 1, #bo do
				if type(bo[i]) == "string" then
					list[#list + 1] = bo[i]
				end
			end
			row.buildoptions = list
		end

		out[name] = row
		count = count + 1
	end
end

_HOST_RESULT(out, count)
