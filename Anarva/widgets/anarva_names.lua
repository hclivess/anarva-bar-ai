-- Anarva player names: shows Anarva's own names for Anarva-controlled teams in your interface.
-- BAR names every AI with a random name (synced gadget luarules/gadgets/ai_namer.lua, stored as the game rule
-- "ainame_<team>"); an AI can't change that. This widget only changes what YOUR screen shows: it wraps the
-- game-rules lookup inside the UI for teams run by Anarva. Nothing synced changes, so it can't desync a game.
function widget:GetInfo()
	return {
		name    = "Anarva player names",
		desc    = "Shows Anarva's own names (Vritrasura, biong, fethar, PanHrnecPapinak, Liduric) for Anarva AI teams",
		author  = "Anarva",
		layer   = -100000,  -- before the player list and other UI that reads AI names
		enabled = true,
	}
end

local NAMES = { "Vritrasura", "biong", "fethar", "PanHrnecPapinak", "Liduric" }

local custom = {}        -- "ainame_<team>" -> our name
local original = nil

local function isAnarva(teamID)
	local _, _, _, isAI = Spring.GetTeamInfo(teamID, false)
	if not isAI then return false end
	local _, name, _, shortName = Spring.GetAIInfo(teamID)
	local s = tostring(shortName or "") .. " " .. tostring(name or "")
	return s:lower():find("anarv") ~= nil
end

local function assign()
	custom = {}
	local i = 0
	local teams = Spring.GetTeamList() or {}
	table.sort(teams)
	for _, teamID in ipairs(teams) do
		if isAnarva(teamID) then
			i = i + 1
			local name = NAMES[((i - 1) % #NAMES) + 1]
			if i > #NAMES then name = name .. " " .. tostring(math.floor((i - 1) / #NAMES) + 1) end
			custom["ainame_" .. teamID] = name
			Spring.Echo("[Anarva names] team " .. teamID .. " -> " .. name)
		end
	end
end

function widget:Initialize()
	assign()
	if next(custom) == nil then
		widgetHandler:RemoveWidget(self)  -- no Anarva in this game: nothing to do
		return
	end
	original = Spring.GetGameRulesParam
	Spring.GetGameRulesParam = function(key, ...)
		local mine = custom[key]
		if mine then return mine end
		return original(key, ...)
	end
end

function widget:Shutdown()
	if original then
		Spring.GetGameRulesParam = original
		original = nil
	end
end
