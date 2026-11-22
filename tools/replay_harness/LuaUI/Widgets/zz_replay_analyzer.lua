-- Replay analyzer: logs per-team economy curve, build orders and the winner while a demo plays headless.
function widget:GetInfo()
	return { name = "Replay Analyzer", desc = "dev: dumps replay stats to infolog", author = "anarva-dev",
		layer = 0, enabled = true }
end

local SPEED = 80
local gaia = Spring.GetGaiaTeamID()

local function teamTag(t)
	local _, leader, _, isAI, side, ally = Spring.GetTeamInfo(t, false)
	local name = leader and Spring.GetPlayerInfo(leader, false) or "?"
	if isAI then
		local _, aiName, _, shortName = Spring.GetAIInfo(t)
		name = "AI:" .. tostring(shortName or aiName)
	end
	return string.format("team=%d ally=%d side=%s name=%s", t, ally or -1, tostring(side), tostring(name))
end

function widget:Initialize()
	local teams = Spring.GetTeamList()
	for i = 1, #teams do
		if teams[i] ~= gaia then
			Spring.Echo("[REPLAY] TEAM " .. teamTag(teams[i]))
		end
	end
	Spring.Echo("[REPLAY] MAP " .. tostring(Game.mapName) .. " " .. Game.mapSizeX .. "x" .. Game.mapSizeZ)
end

function widget:GameFrame(n)
	if n % 300 == 5 then
		Spring.SendCommands("setmaxspeed " .. SPEED, "setminspeed " .. SPEED, "setspeed " .. SPEED)
	end
	if n % 1800 == 0 and n > 0 then
		local teams = Spring.GetTeamList()
		for i = 1, #teams do
			local t = teams[i]
			if t ~= gaia then
				local _, _, _, mInc = Spring.GetTeamResources(t, "metal")
				local _, _, _, eInc = Spring.GetTeamResources(t, "energy")
				local units = Spring.GetTeamUnits(t) or {}
				local army, eco, def = 0, 0, 0
				for j = 1, #units do
					local ud = UnitDefs[Spring.GetUnitDefID(units[j])]
					if ud then
						if ud.canMove and #ud.weapons > 0 and not ud.isBuilder then army = army + ud.metalCost
						elseif not ud.canMove and #ud.weapons > 0 then def = def + ud.metalCost
						elseif not ud.canMove then eco = eco + ud.metalCost end
					end
				end
				Spring.Echo(string.format("[REPLAY] STAT min=%d team=%d m_inc=%.1f e_inc=%.0f army=%d def=%d eco=%d units=%d",
					n / 1800, t, mInc or 0, eInc or 0, army, def, eco, #units))
			end
		end
	end
end

function widget:UnitFinished(unitID, unitDefID, teamID)
	local ud = UnitDefs[unitDefID]
	if ud and teamID ~= gaia then
		Spring.Echo(string.format("[REPLAY] BUILT f=%d team=%d %s m=%d", Spring.GetGameFrame(), teamID, ud.name, ud.metalCost))
	end
end

function widget:GameOver(winners)
	Spring.Echo("[REPLAY] WINNERS ally=" .. table.concat(winners or {}, ",") .. " f=" .. Spring.GetGameFrame())
	Spring.SendCommands("quitforce")
end
