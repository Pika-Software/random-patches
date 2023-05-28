local addonName = "Random Patches"
local version = "3.8.0"
local NULL = NULL

function IsValid( object )
	if not object then return false end
	if object == NULL then return false end

	local func = object.IsValid
	if not func then return false end

	return func( object )
end

local IsValid = IsValid
local ipairs = ipairs
local string = string
local table = table
local math = math
local hook = hook

string.StartsWith = string.StartsWith or string.StartWith

function math.Clamp( num, min, max )
	if num < min then return min end
	if num > max then return max end
	return num
end

function table.Shuffle( tbl )
	local len = #tbl
	for i = len, 1, -1 do
		local rand = math.random( len )
		tbl[ i ], tbl[ rand ] = tbl[ rand ], tbl[ i ]
	end

	return tbl
end

function table.Random( tbl, issequential )
	local keys = issequential and tbl or table.GetKeys( tbl )
	local rand = keys[ math.random( 1, #keys ) ]
	return tbl[ rand ], rand
end

-- Improved IsMounted
do

	local engine_GetGames = engine.GetGames
	local mounted = {}

	local function cacheMounted()
		table.Empty( mounted )

		for _, tbl in ipairs( engine_GetGames() ) do
			if tbl.mounted then
				mounted[ tbl.folder ] = true
				mounted[ tbl.depot ] = true
			end
		end
	end

	function IsMounted( name )
		if mounted[ name ] then
			return true
		end

		return false
	end

	hook.Add( "GameContentChanged", addonName .. " - Improved IsMounted", cacheMounted )
	cacheMounted()

end

if SERVER then

	-- Normal Deploy Speed
	RunConsoleCommand( "sv_defaultdeployspeed", "1" )

	-- Missing Stuff
	-- From metastruct code
	CreateConVar( "room_type", "0" )
	scripted_ents.Register( {
		["Base"] = "base_point",
		["Type"] = "point"
	}, "info_ladder" )

	-- ENTITY metatable optimization
	-- Based on Earu#7089 ENTITY.__index optimization
	-- Edited by Jaff#2843 and Radon#0952
	-- Temporarily disabled due to critical metatable overflow bug

	--[[
	do
		local ENTITY = FindMetaTable( "Entity" )
		local entTabMT = { __index = ENTITY }

		local entMetaID = ENTITY.MetaID
		local entMetaName = ENTITY.MetaName
		local ent__tostring = ENTITY.__tostring
		local ent__eq = ENTITY.__eq
		local ent__concat = ENTITY.__concat

		local function changeEntMetaTable(ent)
			local tab = ent:GetTable()
			setmetatable(tab, entTabMT)

			debug.setmetatable(ent, {
				__index = tab,
				__newindex = tab,
				__metatable = ENTITY,

				MetaID = entMetaID,
				MetaName = entMetaName,
				__tostring = ent__tostring,
				__eq = ent__eq,
				__concat = ent__concat,
			})
		end

		hook.Add( "OnEntityCreated", addonName .. " - ChangeEntMeta", function(ent)
			-- Experimental optimization, can be disabled by convar, report all problems on our github
			if CreateConVar( "randpatches_replace_entmeta", "1", FCVAR_ARCHIVE ):GetBool() then
				timer.Simple(0, function()
					if IsValid(ent) and getmetatable(ent) == ENTITY then
						changeEntMetaTable(ent)
					end
				end)
			end
		end, HOOK_MONITOR_HIGH )
	end
	--]]

	-- Little optimization idea by Billy (used in voicebox)
	-- "for something that really shouldn't be O(n)"
	-- https://i.imgur.com/yPtoNvO.png
	-- https://i.imgur.com/a0lmB9m.png
	do

		local meta = FindMetaTable( "Player" )
		if meta.UserID and debug.getinfo( meta.UserID ).short_src == "[C]" then
			RandomPatches_UserID = RandomPatches_UserID or meta.UserID

			function meta:UserID()
				return self.__UserID or RandomPatches_UserID( self )
			end

			local function cacheUserID( ply )
				ply.__UserID = RandomPatches_UserID( ply )
			end

			hook.Add( "PlayerInitialSpawn", addonName .. " - CacheUserID", cacheUserID, HOOK_MONITOR_HIGH )
			hook.Add( "PlayerAuthed", addonName .. " - CacheUserID", cacheUserID, HOOK_MONITOR_HIGH )

		end

	end

	-- Areaportals fix
	do

		local mapIsCleaning = false
		hook.Add( "PreCleanupMap", addonName .. " - Areaportal fix", function() mapIsCleaning = true end )
		hook.Add( "PostCleanupMap", addonName .. " - Areaportal fix", function() mapIsCleaning = false end )

		local doorClasses = {
			["func_door_rotating"] = true,
			["prop_door_rotating"] = true,
			["func_movelinear"] = true,
			["func_door"] = true
		}

		local ents_FindByClass = ents.FindByClass
		hook.Add( "EntityRemoved", addonName .. " - Areaportal fix", function( ent )
			if not mapIsCleaning and doorClasses[ ent:GetClass() ] then
				local name = ent:GetName()
				if name == "" then return end

				for _, portal in ipairs( ents_FindByClass( "func_areaportal" ) ) do
					if portal:GetInternalVariable( "target" ) ~= name then continue end
					portal:SetSaveValue( "target", "" )
					portal:Fire( "open" )
				end
			end
		end )

	end

	-- Fixes for prop_vehicle_prisoner_pod, worldspawn (and other not Valid but not NULL entities) damage taking (bullets only)
	-- Explosive damage only works if is located in front of prop_vehicle_prisoner_pod (wtf?)
	hook.Add( "EntityTakeDamage", addonName .. " - Prisoner fix", function( ent, dmg )
		if not IsValid( ent ) or ent:IsNPC() then return end
		if ent.AcceptDamageForce or ent:GetClass() == "prop_vehicle_prisoner_pod" then
			ent:TakePhysicsDamage( dmg )
		end
	end )

	hook.Add( "OnFireBulletCallback", addonName .. " - Prisoner damage", function( _, tr, damageInfo )
		local ent = tr.Entity
		if not IsValid( ent ) then return end
		hook.Run( "EntityTakeDamage", ent, damageInfo )
	end )

	-- Literally garrysmod-requests #1845
	hook.Add( "EntityFireBullets", addonName .. " - Bullet callback", function( ent, data )
		local oldCallback = data.Callback
		function data.Callback( ... )
			hook.Run( "OnFireBulletCallback", ... )
			if not oldCallback then return end
			return oldCallback( ... )
		end
	end, HOOK_MONITOR_HIGH )

	-- Steam Auth Check
	do

		local sv_lan = GetConVar( "sv_lan" )

		hook.Add( "PlayerInitialSpawn", addonName .. " - Steam auth check", function( ply )
			if sv_lan:GetBool() or ply:IsBot() or ply:IsListenServerHost() or ply:IsFullyAuthenticated() then return end
			ply:Kick( "Your SteamID wasn\'t fully authenticated, try restart steam." )
		end, HOOK_MONITOR_HIGH )

	end

	-- Pod network fix by Kefta (code_gs#4197)
	-- Literally garrysmod-issues #2452
	do

		local EFL_NO_THINK_FUNCTION = EFL_NO_THINK_FUNCTION

		hook.Add( "OnEntityCreated", addonName .. " - Pod fix", function( veh )
			if veh:GetClass() ~= "prop_vehicle_prisoner_pod" then return end
			veh:AddEFlags( EFL_NO_THINK_FUNCTION )
		end )

		hook.Add( "PlayerEnteredVehicle", addonName .. " - Pod fix", function( _, veh )
			if veh:GetClass() ~= "prop_vehicle_prisoner_pod" then return end
			veh:RemoveEFlags( EFL_NO_THINK_FUNCTION )
		end )

		hook.Add( "PlayerLeaveVehicle", addonName .. " - Pod fix", function( _, veh )
			if veh:GetClass() ~= "prop_vehicle_prisoner_pod" then return end
			hook.Add( "Think", veh, function( self )
				hook.Remove( "Think", self )

				if self:GetInternalVariable( "m_bEnterAnimOn" ) then return end
				if self:GetInternalVariable( "m_bExitAnimOn" ) then return end
				self:AddEFlags( EFL_NO_THINK_FUNCTION )
			end )
		end )

	end

	-- Chargers physics fix
	do

		local SOLID_VPHYSICS = SOLID_VPHYSICS
		local timer_Simple = timer.Simple

		hook.Add( "OnEntityCreated", addonName .. " - Chargers physics fix", function( ent )
			if ent:CreatedByMap() then return end

			timer_Simple( 0, function()
				if not IsValid( ent ) then return end

				local className = ent:GetClass()
				if className ~= "item_suitcharger" and className ~= "item_healthcharger" then return end
				ent:PhysicsInit( SOLID_VPHYSICS )
				ent:PhysWake()
			end )
		end )

	end

	-- Fix for https://github.com/Facepunch/garrysmod-issues/issues/2447
	-- https://github.com/SuperiorServers/dash/blob/master/lua/dash/extensions/player.lua#L44-L57
	local ENTITY, PLAYER = FindMetaTable( "Entity" ), FindMetaTable( "Player" )

	do

		local positions = {}
		function PLAYER:SetPos( pos )
			positions[ self ] = pos
		end

		hook.Add( "FinishMove", addonName .. " - Player:SetPos fix", function( ply )
			local pos = positions[ ply ]
			if not pos then return end

			ENTITY.SetPos( ply, pos )
			positions[ ply ] = nil

			return true
		end )

	end

end

if CLIENT then

	-- Bind Fix
	do

		local hookName = addonName .. " - Bind fix"
		local bindsPressed = {}

		hook.Add( "PlayerBindPress", hookName, function( _, bindName, isDown, keyCode )
			if not string.StartsWith( bindName, "+" ) then return end
			bindsPressed[ keyCode ] = string.sub( bindName, 2, #bindName )
		end )

		hook.Add( "PlayerButtonUp", hookName, function( ply, keyCode )
			local bindName = bindsPressed[ keyCode ]
			if not bindName or not IsFirstTimePredicted() then return end
			hook.Run( "PlayerBindPress", ply, "-" .. bindName, true, keyCode )
			bindsPressed[ keyCode ] = nil
		end )

	end

	-- Look Up/Down Fix
	do

		local hookName = addonName .. " - Look up/down fix"
		local cl_pitchspeed = GetConVar( "cl_pitchspeed" )
		local system_HasFocus = system.HasFocus
		local lookDown = false
		local lookUp = false

		hook.Add( "PlayerBindPress", hookName, function( ply, bindName, isDown )
			if not isDown then return end

			local bind = string.sub( bindName, 2, #bindName )
			if bind == "lookdown" then
				lookDown = string.sub( bindName, 1, 1 ) == "+"
				return true
			elseif bind == "lookup" then
				lookUp = string.sub( bindName, 1, 1 ) == "+"
				return true
			end
		end )

		hook.Add( "Think", hookName, function()
			if not system_HasFocus() then
				lookDown = false
				lookUp = false
				return
			end

			if lookDown then
				local ply = LocalPlayer()
				if IsValid( ply ) then
					local ang = ply:EyeAngles()
					ang[1] = ang[1] + cl_pitchspeed:GetFloat() * FrameTime() / (ply:KeyDown( IN_SPEED ) and 1.5 or 1)
					ply:SetEyeAngles( ang )
				end
			end

			if lookUp then
				local ply = LocalPlayer()
				if IsValid( ply ) then
					local ang = ply:EyeAngles()
					ang[1] = ang[1] - cl_pitchspeed:GetFloat() * FrameTime() / (ply:KeyDown( IN_SPEED ) and 1.5 or 1)
					ply:SetEyeAngles( ang )
				end
			end
		end )

	end

	-- Speeding up LocalPlayer
	do

		local localPlayer = LocalPlayer
		local ply

		function _G.LocalPlayer()
			ply = localPlayer()

			if IsValid( ply ) then
				_G.LocalPlayer = function()
					return ply
				end
			end

			return ply
		end

	end

	-- Shoots in focus fix
	do

		local system_HasFocus = system.HasFocus
		local lastNoFocusTime = 0
		local CurTime = CurTime

		hook.Add( "CreateMove", addonName .. " - Shoots in focus fix", function( cmd )
			if CurTime() - lastNoFocusTime < 0.25 then
				cmd:RemoveKey( IN_ATTACK )
				cmd:RemoveKey( IN_ATTACK2 )
			end

			if system_HasFocus() then return end
			lastNoFocusTime = CurTime()
		end )

	end

end

MsgC( SERVER and Color( 50, 100, 250 ) or Color( 250, 100, 50 ), string.format( "[%s v%s] ", addonName, version ), color_white, "Game Patched!\n" )