if file.Exists("ulib/shared/hook.lua", "LUA") then
	include("ulib/shared/hook.lua")
end
local _G = _G
local color_white, math, pairs, CurTime, CLIENT, SERVER = _G.color_white, _G.math, _G.pairs, _G.CurTime, _G.CLIENT, _G.SERVER
local PRE_HOOK = _G.PRE_HOOK or _G.HOOK_MONITOR_HIGH
local Add, Remove = hook.Add, hook.Remove
local Simple = timer.Simple
local addonName = "Random Patches v5.20.3"
local getHookName
getHookName = function(patchName, hookName)
	return addonName .. "::" .. patchName .. (hookName or "")
end
local Register
do
	local CreateConVar, FCVAR_ARCHIVE = _G.CreateConVar, _G.FCVAR_ARCHIVE
	local AddChangeCallback = cvars.AddChangeCallback
	local gsub, lower = string.gsub, string.lower
	local FCVAR_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY, FCVAR_DONTRECORD)
	Register = function(name, enable, disable, shared)
		local hookName = getHookName(name)
		if disable == nil then
			return enable(hookName)
		end
		local conVarName = (SERVER and "sv_" or "cl_") .. "patch_" .. gsub(lower(name), "[%s%p]", "_")
		if CreateConVar(conVarName, "1", shared and FCVAR_FLAGS or FCVAR_ARCHIVE, name, 0, 1):GetBool() then
			enable(hookName)
		end
		return AddChangeCallback(conVarName, function(_, __, value)
			if value == "1" then
				return enable(hookName)
			else
				return disable(hookName)
			end
		end, addonName)
	end
end
string.StartsWith = string.StartsWith or string.StartWith
table.Empty = function(tbl)
	for key in pairs(tbl) do
		tbl[key] = nil
	end
end
do
	local min, max = math.min, math.max
	math.Clamp = function(num, low, high)
		return min(max(num, low), high)
	end
end
do
	local floor = math.floor
	math.Round = function(num, idp)
		local mult = 10 ^ (idp or 0)
		return floor(num * mult + 0.5) / mult
	end
end
do
	local random = math.random
	math.Rand = function(low, high)
		return low + (high - low) * random()
	end
	local index, length = 1, 0
	table.Shuffle = function(tbl)
		length = #tbl
		for i = length, 1, -1 do
			index = random(1, length)
			tbl[i], tbl[index] = tbl[index], tbl[i]
		end
		return tbl
	end
	do
		local keys = setmetatable({ }, {
			__mode = "v"
		})
		table.Random = function(tbl, issequential)
			if issequential then
				length = #tbl
				if length == 0 then
					return nil, nil
				end
				if length == 1 then
					index = 1
				else
					index = random(1, length)
				end
			else
				length = 0
				for key in pairs(tbl) do
					length = length + 1
					keys[length] = key
				end
				if length == 0 then
					return nil, nil
				end
				if length == 1 then
					index = keys[1]
				else
					index = keys[random(1, length)]
				end
			end
			return tbl[index], index
		end
	end
end
do
	Remove("OnEntityCreated", "player.Iterator")
	Remove("EntityRemoved", "player.Iterator")
	Remove("OnEntityCreated", "ents.Iterator")
	Remove("EntityRemoved", "ents.Iterator")
	local iterator = ipairs({ })
	local players
	do
		local GetAll = player.GetAll
		player.Iterator = function()
			if players == nil then
				players = GetAll()
			end
			return iterator, players, 0
		end
	end
	local entities
	do
		local GetAll = ents.GetAll
		ents.Iterator = function()
			if entities == nil then
				entities = GetAll()
			end
			return iterator, entities, 0
		end
	end
	local invalidateCache
	invalidateCache = function(entity)
		if entity:IsPlayer() then
			players = nil
		end
		entities = nil
	end
	Add("OnEntityCreated", "player/ents.Iterator", invalidateCache, PRE_HOOK)
	Add("EntityRemoved", "player/ents.Iterator", invalidateCache, PRE_HOOK)
end
do
	local yield = coroutine.yield
	coroutine.wait = function(seconds)
		local endTime = CurTime() + seconds
		while true do
			if endTime < CurTime() then
				return
			end
			yield()
		end
	end
end
local registry
do
	debug = debug or { }
	if isfunction(debug.getregistry) then
		registry = debug.getregistry() or { }
	else
		registry = { }
	end
	local CFindMetaTable = _G.CFindMetaTable
	if not CFindMetaTable then
		CFindMetaTable = _G.FindMetaTable
		_G.CFindMetaTable = CFindMetaTable
	end
	setmetatable(registry, {
		["__index"] = function(tbl, key)
			local metatable = CFindMetaTable(key)
			if metatable == nil then
				return
			end
			rawset(tbl, key, metatable)
			return metatable
		end
	})
	FindMetaTable = function(name)
		return registry[name]
	end
	debug.getregistry = function()
		return registry
	end
end
local ENTITY, PLAYER
do
	ENTITY, PLAYER = registry.Entity, registry.Player
	local GetCTable = ENTITY.GetCTable
	if not GetCTable then
		GetCTable = ENTITY.GetTable
		ENTITY.GetCTable = GetCTable
	end
	local cache = { }
	Add("EntityRemove", getHookName("Entity.GetTable"), function(entity)
		return Simple(0, function()
			cache[entity] = nil
		end)
	end, PRE_HOOK)
	local getTable
	getTable = function(entity)
		if cache[entity] == nil then
			cache[entity] = GetCTable(entity) or { }
		end
		return cache[entity]
	end
	ENTITY.GetTable = getTable
	ENTITY.__index = function(self, key)
		local value = ENTITY[key]
		if value == nil then
			value = getTable(self)[key]
		end
		return value
	end
	PLAYER.__index = function(self, key)
		local value = PLAYER[key]
		if value == nil then
			value = ENTITY[key]
			if value == nil then
				value = getTable(self)[key]
			end
		end
		return value
	end
	do
		local GetOwner = ENTITY.GetOwner
		local Weapon = registry.Weapon
		Weapon.__index = function(self, key)
			local value = Weapon[key]
			if value == nil then
				value = ENTITY[key]
				if value == nil then
					value = getTable(self)[key]
					if value == nil and key == "Owner" then
						return GetOwner(self)
					end
				end
			end
			return value
		end
	end
	do
		local Vehicle = registry.Vehicle
		Vehicle.__index = function(self, key)
			local value = Vehicle[key]
			if value == nil then
				value = ENTITY[key]
				if value == nil then
					value = getTable(self)[key]
				end
			end
			return value
		end
	end
	do
		local NPC = registry.NPC
		NPC.__index = function(self, key)
			local value = NPC[key]
			if value == nil then
				value = ENTITY[key]
				if value == nil then
					value = getTable(self)[key]
				end
			end
			return value
		end
	end
	do
		local getmetatable, setmetatable = debug.getmetatable, debug.setmetatable
		local object
		local metatable = getmetatable(object)
		if metatable == nil then
			metatable = { }
			setmetatable(object, metatable)
		end
		registry["nil"] = metatable
		object = 0
		metatable = getmetatable(object)
		if metatable == nil then
			metatable = { }
			setmetatable(object, metatable)
		end
		registry["number"] = metatable
		object = ""
		metatable = getmetatable(object)
		if metatable == nil then
			metatable = { }
			setmetatable(object, metatable)
		end
		registry["string"] = metatable
		object = false
		metatable = getmetatable(object)
		if metatable == nil then
			metatable = { }
			setmetatable(object, metatable)
		end
		registry["boolean"] = metatable
		object = function() end
		metatable = getmetatable(object)
		if getmetatable(object) == nil then
			metatable = { }
			setmetatable(object, metatable)
		end
		registry["function"] = metatable
		object = coroutine.create(object)
		metatable = getmetatable(object)
		if metatable == nil then
			metatable = { }
			setmetatable(object, metatable)
		end
		registry["thread"] = metatable
	end
end
local IsValid, GetClass = ENTITY.IsValid, ENTITY.GetClass
local Alive, IsBot = PLAYER.Alive, PLAYER.IsBot
do
	local getmetatable = _G.getmetatable
	ENTITY.IsPlayer = function(self)
		return getmetatable(self) == PLAYER
	end
	do
		local metatable = registry["Vehicle"]
		ENTITY.IsVehicle = function(self)
			return getmetatable(self) == metatable
		end
	end
	do
		local metatable = registry["NPC"]
		ENTITY.IsNPC = function(self)
			return getmetatable(self) == metatable
		end
	end
	do
		local metatable = registry["NextBot"]
		ENTITY.IsNextBot = function(self)
			return getmetatable(self) == metatable
		end
	end
	do
		local metatable = registry["number"]
		isnumber = function(self)
			return getmetatable(self) == metatable
		end
	end
	do
		local metatable = registry["string"]
		isstring = function(self)
			return getmetatable(self) == metatable
		end
	end
	do
		local metatable = registry["boolean"]
		isbool = function(self)
			return getmetatable(self) == metatable
		end
	end
	do
		local metatable = registry["function"]
		isfunction = function(self)
			return getmetatable(self) == metatable
		end
	end
	do
		local metatable = registry["Vector"]
		isvector = function(self)
			return getmetatable(self) == metatable
		end
	end
	do
		local metatable = registry["Angle"]
		isangle = function(self)
			return getmetatable(self) == metatable
		end
	end
	do
		local metatable = registry["VMatrix"]
		ismatrix = function(self)
			return getmetatable(self) == metatable
		end
	end
	if CLIENT then
		local metatable = registry["Panel"]
		ispanel = function(self)
			return getmetatable(self) == metatable
		end
	end
	do
		local metatable = registry["Color"] or getmetatable(color_white)
		IsColor = function(self)
			return getmetatable(self) == metatable
		end
		do
			local setmetatable, isnumber, tonumber = _G.setmetatable, _G.isnumber, _G.tonumber
			Color = function(r, g, b, a)
				if r then
					if not isnumber(r) then
						r = tonumber(r) or 255
					end
					if r > 255 then
						r = 255
					elseif r < 0 then
						r = 0
					end
				else
					r = 255
				end
				if g then
					if not isnumber(g) then
						g = tonumber(g) or 255
					end
					if g > 255 then
						g = 255
					elseif g < 0 then
						g = 0
					end
				else
					g = 255
				end
				if b then
					if not isnumber(b) then
						b = tonumber(b) or 255
					end
					if b > 255 then
						b = 255
					elseif b < 0 then
						b = 0
					end
				else
					b = 255
				end
				if a then
					if not isnumber(a) then
						a = tonumber(a) or 255
					end
					if a > 255 then
						a = 255
					elseif a < 0 then
						a = 0
					end
				else
					a = 255
				end
				return setmetatable({
					r = r,
					g = g,
					b = b,
					a = a
				}, metatable)
			end
		end
	end
end
do
	local FrameNumber = _G.FrameNumber
	local TraceLine = util.TraceLine
	local distance = 4096 * 8
	local trace = { }
	util.GetPlayerTrace = function(self, dir)
		local start = self:EyePos()
		return {
			start = start,
			endpos = start + ((dir or self:GetAimVector()) * distance),
			filter = self
		}
	end
	util.QuickTrace = function(origin, dir, filter)
		trace.start = origin
		trace.endpos = origin + dir
		trace.filter = filter
		return TraceLine(trace)
	end
	PLAYER.GetEyeTrace = function(self)
		if CLIENT then
			if self.m_iLastEyeTrace == FrameNumber() then
				return self.m_tEyeTrace
			end
			self.m_iLastEyeTrace = FrameNumber()
		end
		trace.start = self:EyePos()
		trace.endpos = trace.start + (self:GetAimVector() * distance)
		trace.filter = self
		self.m_tEyeTrace = TraceLine(trace)
		return self.m_tEyeTrace
	end
	PLAYER.GetEyeTraceNoCursor = function(self)
		if CLIENT then
			if self.m_iLastAimTrace == FrameNumber() then
				return self.m_tAimTrace
			end
			self.m_iLastAimTrace = FrameNumber()
		end
		trace.start = self:EyePos()
		trace.endpos = trace.start + (self:EyeAngles():Forward() * distance)
		trace.filter = self
		self.m_tAimTrace = TraceLine(trace)
		return self.m_tAimTrace
	end
end
do
	local GetConVar_Internal = _G.GetConVar_Internal
	local cache = { }
	GetConVar = function(name)
		if cache[name] == nil then
			local value = GetConVar_Internal(name)
			if value == nil then
				return
			end
			cache[name] = value
			return value
		end
		return cache[name]
	end
end
Register("Player Shoot Position Fix", function(hookName)
	local GetShootPos = PLAYER.GetShootPos
	Add("SetupMove", hookName, function(self)
		if IsBot(self) or not Alive(self) then
			return
		end
		self.m_RealShootPos = GetShootPos(self)
	end, PRE_HOOK)
	return Add("EntityFireBullets", hookName, function(self, data)
		if not self:IsPlayer() or IsBot(self) or not Alive(self) then
			return
		end
		local src = GetShootPos(self)
		if data.Src == src then
			data.Src = self.m_RealShootPos or src
			return true
		end
	end)
end, function(hookName)
	Remove("EntityFireBullets", hookName)
	return Remove("SetupMove", hookName)
end, true)
do
	gameevent.Listen("player_hurt")
	local Player = _G.Player
	Add("player_hurt", getHookName("Player Decals Fix"), function(data)
		local health = data.health
		if health > 0 then
			return
		end
		local ply = Player(data.userid)
		if IsValid(ply) and Alive(ply) then
			return Simple(0.25, function()
				if IsValid(ply) then
					ply:RemoveAllDecals()
					return
				end
			end)
		end
	end, PRE_HOOK)
end
do
	local CLagCompensation = PLAYER.CLagCompensation
	if not CLagCompensation then
		CLagCompensation = PLAYER.LagCompensation
		PLAYER.CLagCompensation = CLagCompensation
	end
	PLAYER.LagCompensation = function(self, bool)
		if self.m_bLagCompensation ~= bool then
			self.m_bLagCompensation = bool
			return CLagCompensation(self, bool)
		end
	end
end
do
	local IsOnGround, GetMoveType = ENTITY.IsOnGround, ENTITY.GetMoveType
	do
		local MOVETYPE_LADDER = _G.MOVETYPE_LADDER
		Add("PlayerFootstep", getHookName("Player Footstep Fix"), function(self)
			if not IsOnGround(self) and GetMoveType(self) ~= MOVETYPE_LADDER then
				return true
			end
		end)
	end
	local MOVETYPE_NOCLIP, IN_DUCK = _G.MOVETYPE_NOCLIP, _G.IN_DUCK
	Add("StartCommand", getHookName("Air Crouching Fix"), function(self, cmd)
		if GetMoveType(self) == MOVETYPE_NOCLIP or IsOnGround(self) or cmd:KeyDown(IN_DUCK) or not self:Crouching() then
			return
		end
		cmd:AddKey(IN_DUCK)
		return
	end, PRE_HOOK)
end
if SERVER then
	CreateConVar("room_type", "0")
	scripted_ents.Register({
		Base = "base_point",
		Type = "point"
	}, "info_ladder")
	do
		local GetPhysicsObject = ENTITY.GetPhysicsObject
		ENTITY.PhysWake = function(self)
			local phys = GetPhysicsObject(self)
			if phys and phys:IsValid() then
				phys:Wake()
				return true
			end
			return false
		end
	end
	Add("PlayerSpawn", getHookName("Player Color Fix"), function(self)
		return self:SetColor(color_white)
	end)
	Register("Default Deploy Speed Fix", function()
		return RunConsoleCommand("sv_defaultdeployspeed", "1")
	end, function()
		local conVar = GetConVar("sv_defaultdeployspeed")
		if conVar ~= nil then
			return RunConsoleCommand("sv_defaultdeployspeed", conVar:GetDefault())
		end
	end)
	Register("Steam Auth Protection", function(hookName)
		local sv_lan = GetConVar("sv_lan")
		return Add("PlayerInitialSpawn", hookName, function(self)
			if sv_lan:GetBool() then
				return
			end
			if IsBot(self) or self:IsListenServerHost() or self:IsFullyAuthenticated() then
				return
			end
			self:Kick("Your SteamID wasn\'t fully authenticated, try restart your Steam client.")
			return
		end, PRE_HOOK)
	end, function(hookName)
		return Remove("PlayerInitialSpawn", hookName)
	end)
	local GetInternalVariable = ENTITY.GetInternalVariable
	do
		local GetName, SetSaveValue, Fire = ENTITY.GetName, ENTITY.SetSaveValue, ENTITY.Fire
		local FindByClass = ents.FindByClass
		local hookName, classes = getHookName("Area Portals Fix"), {
			func_door_rotating = true,
			prop_door_rotating = true,
			func_movelinear = true,
			func_door = true
		}
		local start
		start = function()
			return Add("EntityRemoved", hookName, function(entity)
				if not classes[GetClass(entity)] then
					return
				end
				local name = GetName(entity)
				if #name == 0 then
					return
				end
				local _list_0 = FindByClass("func_areaportal")
				for _index_0 = 1, #_list_0 do
					local portal = _list_0[_index_0]
					if GetInternalVariable(portal, "target") == name then
						SetSaveValue(portal, "target", "")
						Fire(portal, "open")
					end
				end
			end, PRE_HOOK)
		end
		local stop
		stop = function()
			Remove("EntityRemoved", hookName)
			return
		end
		Add("PostCleanupMap", hookName, start, PRE_HOOK)
		Add("PreCleanupMap", hookName, stop, PRE_HOOK)
		Add("ShutDown", hookName, stop, PRE_HOOK)
		start()
	end
	do
		local SOLID_VPHYSICS = _G.SOLID_VPHYSICS
		Add("PlayerSpawnedSENT", getHookName("HL2 Chargers Physics"), function(_, entity)
			local className = GetClass(entity)
			if className == "item_suitcharger" or className == "item_healthcharger" then
				entity:PhysicsInit(SOLID_VPHYSICS)
				entity:PhysWake()
				return
			end
		end, PRE_HOOK)
	end
	do
		local CUserID = PLAYER.CUserID
		if not CUserID then
			CUserID = PLAYER.UserID
			PLAYER.CUserID = CUserID
		end
		PLAYER.UserID = function(self)
			return self.m_bUserID or CUserID(self)
		end
		do
			local hookName, cacheFunc
			hookName, cacheFunc = getHookName("UserID Cache"), function(self)
				self.m_bUserID = CUserID(self)
			end
			Add("PlayerInitialSpawn", hookName, cacheFunc, PRE_HOOK)
			Add("PlayerAuthed", hookName, cacheFunc, PRE_HOOK)
		end
	end
	do
		local hookName = getHookName("Pod Performance Fix")
		local EFL_NO_THINK_FUNCTION = _G.EFL_NO_THINK_FUNCTION
		Add("OnEntityCreated", hookName, function(entity)
			if GetClass(entity) == "prop_vehicle_prisoner_pod" then
				entity:AddEFlags(EFL_NO_THINK_FUNCTION)
				return
			end
		end, PRE_HOOK)
		Add("PlayerLeaveVehicle", hookName, function(_, entity)
			if GetClass(entity) == "prop_vehicle_prisoner_pod" then
				Add("Think", entity, function()
					Remove("Think", entity)
					if GetInternalVariable(entity, "m_bEnterAnimOn") or GetInternalVariable(entity, "m_bExitAnimOn") then
						return
					end
					entity:AddEFlags(EFL_NO_THINK_FUNCTION)
					return
				end, PRE_HOOK)
				return
			end
		end, PRE_HOOK)
		Add("PlayerEnteredVehicle", hookName, function(_, entity)
			if GetClass(entity) == "prop_vehicle_prisoner_pod" then
				entity:RemoveEFlags(EFL_NO_THINK_FUNCTION)
				Remove("Think", entity)
				return
			end
		end, PRE_HOOK)
	end
	do
		local TakePhysicsDamage = ENTITY.TakePhysicsDamage
		Add("EntityTakeDamage", getHookName("prop_vehicle_prisoner_pod Damage Fix"), function(entity, damageInfo)
			if GetClass(entity) ~= "prop_vehicle_prisoner_pod" or entity.AcceptDamageForce then
				return
			end
			TakePhysicsDamage(entity, damageInfo)
			return
		end, PRE_HOOK)
	end
end
if CLIENT and not MENU_DLL then
	do
		local cl_drawhud = GetConVar("cl_drawhud")
		local Close = chat.Close
		Add("StartChat", getHookName("cl_drawhud fix"), function()
			if cl_drawhud:GetBool() then
				return
			end
			Close()
			return true
		end)
		cvars.AddChangeCallback("cl_drawhud", Close, getHookName("cl_drawhud fix"))
	end
	do
		local OnConVarChanged = cvars.OnConVarChanged
		local GetDefault = registry.ConVar.GetDefault
		local GetConVar = GetConVar
		gameevent.Listen("server_cvar")
		local values = { }
		Add("server_cvar", "cvars.OnConVarChanged", function(data)
			local name = data.cvarname
			local old = values[name]
			if old == nil then
				local conVar = GetConVar(name)
				if not conVar then
					return
				end
				old = GetDefault(conVar)
				values[name] = old
			else
				values[name] = data.cvarvalue
			end
			OnConVarChanged(name, old, data.cvarvalue)
			return
		end, PRE_HOOK)
	end
	do
		local getLocalPlayer = util.GetLocalPlayer
		if not getLocalPlayer then
			getLocalPlayer = LocalPlayer
			util.GetLocalPlayer = getLocalPlayer
		end
		local entity = NULL
		LocalPlayer = function()
			entity = getLocalPlayer()
			if entity and IsValid(entity) then
				LocalPlayer = function()
					return entity
				end
			end
			return entity
		end
	end
	do
		local Start = cam.Start
		do
			local view = {
				type = "2D"
			}
			cam.Start2D = function()
				return Start(view)
			end
		end
		do
			local view = {
				type = "3D"
			}
			cam.Start3D = function(origin, angles, fov, x, y, w, h, znear, zfar)
				view.origin, view.angles, view.fov = origin, angles, fov
				if x ~= nil and y ~= nil and w ~= nil and h ~= nil then
					view.x, view.y = x, y
					view.w, view.h = w, h
					view.aspect = w / h
				else
					view.x, view.y = nil, nil
					view.w, view.h = nil, nil
					view.aspect = nil
				end
				if znear ~= nil and zfar ~= nil then
					view.znear, view.zfar = znear, zfar
				else
					view.znear, view.zfar = nil, nil
				end
				return Start(view)
			end
		end
	end
	do
		local camStack = 0
		local cStartOrthoView = cam.CStartOrthoView
		if not cStartOrthoView then
			cStartOrthoView = cam.StartOrthoView
			cam.CStartOrthoView = cStartOrthoView
		end
		cam.StartOrthoView = function(a, b, c, d)
			camStack = camStack + 1
			return cStartOrthoView(a, b, c, d)
		end
		local cEndOrthoView = cam.CEndOrthoView
		if not cEndOrthoView then
			cEndOrthoView = cam.EndOrthoView
			cam.CEndOrthoView = cEndOrthoView
		end
		cam.EndOrthoView = function()
			if camStack == 0 then
				return
			end
			camStack = camStack - 1
			if camStack < 0 then
				camStack = 0
			end
			return cEndOrthoView()
		end
	end
	do
		local HasFocus = system.HasFocus
		do
			local IN_ATTACK, IN_ATTACK2 = IN_ATTACK, IN_ATTACK2
			local lastNoFocusTime = 0
			Add("CreateMove", getHookName("Focus Attack Fix"), function(cmd)
				if (CurTime() - lastNoFocusTime) < 0.25 then
					cmd:RemoveKey(IN_ATTACK)
					cmd:RemoveKey(IN_ATTACK2)
				end
				if HasFocus() then
					return
				end
				lastNoFocusTime = CurTime()
			end, PRE_HOOK)
		end
		Register("Screen Capture Fix", function(hookName)
			local IsGameUIVisible, ActivateGameUI, HideGameUI = gui.IsGameUIVisible, gui.ActivateGameUI, gui.HideGameUI
			local CursorVisible = vgui.CursorVisible
			local lastState
			return Add("Think", hookName, function()
				if HasFocus() then
					if lastState ~= nil then
						if lastState then
							HideGameUI()
						end
						lastState = nil
					end
				elseif lastState == nil then
					if CursorVisible() then
						return
					end
					lastState = not IsGameUIVisible()
					if lastState then
						ActivateGameUI()
						return
					end
				end
			end, PRE_HOOK)
		end, function(hookName)
			return Remove("Think", hookName)
		end)
	end
end
return MsgC(SERVER and Color(50, 100, 250) or Color(250, 100, 50), "[" .. addonName .. "] ", color_white, table.Random({
	"Here For You ♪",
	"Game Patched!",
	"OK",
	"Successfully initialized!",
	"Powered by Pika Software!",
	"Made with <3",
	"Yeah, well",
	"Alright",
	"Hello there",
	"Specially for you!",
	"Hello?",
	"Wow",
	"I'm here :",
	"Init!",
	"Say hi!",
	"Performance Update",
	"Yippee!",
	"Thanks for installation <3"
}, true) .. "\n")
