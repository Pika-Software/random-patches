local SERVER = SERVER
local realmColor = SERVER and Color( 50, 100, 250 ) or Color( 250, 100, 50 )
local addonName = "Random Patches"
local version = "4.1.0"

if type( rpatches ) ~= "table" then
	rpatches = {
		["List"] = {
			["GLua Fixes/Improvements"] = false
		}
	}
end

rpatches.Name = addonName
rpatches.VERSION = version

local CreateConVar = CreateConVar
local _G = _G

do

	local cvarFlags = bit.bor( FCVAR_ARCHIVE, FCVAR_REPLICATED )
	local cvars_AddChangeCallback = cvars.AddChangeCallback
	local isfunction = isfunction
	local isstring = isstring
	local hook = hook

	function rpatches.Register( name, enable, disable )
		assert( isstring( name ), "Argument #1 must be a string!" )
		assert( isfunction( enable ), "Argument #2 must be a function!" )

		local env = {}

		do

			local h = {}
			env.hook = setmetatable( h, { __index = hook } )

			function h.Add( str1, str2, ... )
				hook.Add( str1, addonName .. " - " .. name .. "/" .. str2, ... )
			end

			function h.Remove( str1, str2 )
				hook.Remove( str1, addonName .. " - " .. name .. "/" .. str2 )
			end

		end

		setmetatable( env, { __index = _G, __newindex = _G } )
		setfenv( enable, env )

		if not isfunction( disable ) then
			rpatches.List[ name ] = false
			enable()
			return
		end

		setfenv( disable, env )

		local cvarName = "rpatch_" .. string.gsub( string.lower( name ), "[%s%p]", "_" )
		rpatches.List[ name ] = cvarName

		local cvar = CreateConVar( cvarName, "1", cvarFlags, "", 0, 1 )
		if cvar:GetBool() then
			enable()
		else
			disable()
		end

		cvars_AddChangeCallback( cvarName, function( _, __, str )
			if str == "1" then enable() else disable() end
		end, addonName )
	end

end

do

	local RunConsoleCommand = RunConsoleCommand

	function rpatches.Enable( name )
		local cvarName = rpatches.List[ name ]
		if not cvarName then return end
		RunConsoleCommand( cvarName, "1" )
	end

	function rpatches.Disable( name )
		local cvarName = rpatches.List[ name ]
		if not cvarName then return end
		RunConsoleCommand( cvarName, "0" )
	end

end

do

	local actions = {
		["list"] = function( args )
			local str = "Patches:\n"
			for name, cvarName in pairs( rpatches.List ) do
				local state = "*"
				if cvarName and not cvars.Bool( cvarName, false ) then
					state = " "
				end

				str = string.format( "%s[%s] %s\n", str, state, name )
			end

			MsgC( realmColor, str )
		end,
		["enable"] = function( args )
			for _, name in ipairs( args ) do
				rpatches.Enable( name )
			end
		end,
		["disable"] = function( args )
			for _, name in ipairs( args ) do
				rpatches.Disable( name )
			end
		end,
		["info"] = function()
			MsgN( "Random Patches - pack of patches/fixes for Garry's Mod.\nCreated by Pika Software." )
		end
	}

	actions.on, actions.off = actions.enable, actions.disable

	concommand.Add( ( SERVER and "" or "cl_" ) .. "rpatches", function( ply, __, args )
		if SERVER and IsValid( ply ) and not ply:IsListenServerHost() then
			ply:ChatPrint( "[RPatches] You do not have enough permissions to run this command." )
			return
		end

		local func = actions[ args[ 1 ] ]
		if not func then return end
		table.remove( args, 1 )
		func( args )
	end )

end

MsgC( realmColor, string.format( "[%s v%s] ", addonName, version ), color_white, "Game Patched!\n" )

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

rpatches.Register( "Improved IsMounted", function()
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

	function _G.IsMounted( name )
		if mounted[ name ] then
			return true
		end

		return false
	end

	hook.Add( "GameContentChanged", "Content Changed", cacheMounted )
	cacheMounted()
end )

rpatches.Register( "Invisible Sound Source Fix", function()
	hook.Add( "EntityEmitSound", "Catching", function( data )
		local entity = data.Entity
		if IsValid( entity ) and entity:GetNoDraw() then return true end
	end )
end, function()
	hook.Remove( "EntityEmitSound", "Catching" )
end )

local function iscfunction( func )
	if type( func ) ~= "function" then return false end
	return debug.getinfo( func ).short_src == "[C]"
end

if SERVER then
	CreateConVar( "room_type", "0" )
	scripted_ents.Register( {
		["Base"] = "base_point",
		["Type"] = "point"
	}, "info_ladder" )

	rpatches.Register( "HL2 Deploy Speed", function()
		RunConsoleCommand( "sv_defaultdeployspeed", "1" )
	end, function()
		RunConsoleCommand( "sv_defaultdeployspeed", "4" )
	end )

	local ENTITY, PLAYER = FindMetaTable( "Entity" ), FindMetaTable( "Player" )

	if iscfunction( ENTITY.RemoveAllDecals ) then
		util.AddNetworkString( "RemoveAllDecalsFix" )

		local removeAllDecals = rpatches.RemoveAllDecals
		if type( removeAllDecals ) ~= "table" then
			removeAllDecals = ENTITY.RemoveAllDecals; rpatches.RemoveAllDecals = removeAllDecals
		end

		function ENTITY:RemoveAllDecals()
			removeAllDecals( self )
			net.Start( "RemoveAllDecalsFix" )
				net.WriteEntity( self )
			net.Broadcast()
		end

		hook.Add( "PlayerSpawn", "RemoveAllDecalsFix", function( ply, trans )
			if trans then return end
			ply:RemoveAllDecals()
		end )
	end

	rpatches.Register( "Steam Auth Protection", function()
		local sv_lan = GetConVar( "sv_lan" )
		hook.Add( "PlayerInitialSpawn", "Player Spawn", function( ply )
			if sv_lan:GetBool() or PLAYER.IsBot( ply ) or PLAYER.IsListenServerHost( ply ) or PLAYER.IsFullyAuthenticated( ply ) then return end
			PLAYER.Kick( ply, "Your SteamID wasn\'t fully authenticated, try restart steam." )
		end, HOOK_MONITOR_HIGH )
	end, function()
		hook.Remove( "PlayerInitialSpawn", "Player Spawn" )
	end )

	-- Fix for https://github.com/Facepunch/garrysmod-issues/issues/2447
	-- https://github.com/SuperiorServers/dash/blob/master/lua/dash/extensions/player.lua#L44-L57
	rpatches.Register( "SWEPs SetPos Fix", function()
		local positions = {}
		function PLAYER:SetPos( pos )
			positions[ self ] = pos
		end

		hook.Add( "FinishMove", "Teleport Player", function( ply )
			local pos = positions[ ply ]
			if not pos then return end

			ENTITY.SetPos( ply, pos )
			positions[ ply ] = nil
			return true
		end )
	end )

	rpatches.Register( "Smart Area Portals", function()
		local ents_FindByClass = ents.FindByClass
		local doorClasses = {
			["func_door_rotating"] = true,
			["prop_door_rotating"] = true,
			["func_movelinear"] = true,
			["func_door"] = true
		}

		local function enable()
			hook.Add( "EntityRemoved", "Entity Catch", function( entity )
				if not doorClasses[ entity:GetClass() ] then return end

				local name = entity:GetName()
				if #name == 0 then return end

				for _, portal in ipairs( ents_FindByClass( "func_areaportal" ) ) do
					if portal:GetInternalVariable( "target" ) ~= name then continue end
					portal:SetSaveValue( "target", "" )
					portal:Fire( "open" )
				end
			end )
		end

		local function disable()
			hook.Remove( "EntityRemoved", "Entity Catch" )
		end

		hook.Add( "PreCleanupMap", "Disable", disable )
		hook.Add( "PostCleanupMap", "Enable", enable )
		hook.Add( "ShutDown", "Disable", disable )
		enable()
	end, function()
		hook.Remove( "EntityRemoved", "Entity Catch" )
		hook.Remove( "PreCleanupMap", "Disable" )
		hook.Remove( "PostCleanupMap", "Enable" )
	end )

	rpatches.Register( "HL2 Chargers Physics", function()
		local SOLID_VPHYSICS = SOLID_VPHYSICS
		local timer_Simple = timer.Simple

		hook.Add( "OnEntityCreated", "Creation", function( entity )
			if entity:CreatedByMap() then return end

			timer_Simple( 0, function()
				if not IsValid( entity ) then return end
				local className = entity:GetClass()
				if className ~= "item_suitcharger" and className ~= "item_healthcharger" then return end
				entity:PhysicsInit( SOLID_VPHYSICS )
				entity:PhysWake()
			end )
		end )
	end, function()
		hook.Remove( "OnEntityCreated", "Creation" )
	end )

	-- Little optimization idea by Billy (used in voicebox)
	-- "for something that really shouldn't be O(n)"
	-- https://i.imgur.com/yPtoNvO.png
	-- https://i.imgur.com/a0lmB9m.png
	rpatches.Register( "UserID Cache", function()
		if not iscfunction( PLAYER.UserID ) then return end

		local userID = rpatches.UserID
		if not userID then
			userID = PLAYER.UserID; rpatches.UserID = userID
		end

		function PLAYER:UserID()
			return self.__UserID or userID( self )
		end

		local function cacheUserID( ply )
			ply.__UserID = userID( ply )
		end

		hook.Add( "PlayerInitialSpawn", "Cache", cacheUserID, HOOK_MONITOR_HIGH )
		hook.Add( "PlayerAuthed", "Cache", cacheUserID, HOOK_MONITOR_HIGH )
	end )

	-- Pod network fix by Kefta (code_gs#4197)
	-- Literally garrysmod-issues #2452
	rpatches.Register( "Pod Performance", function()
		local EFL_NO_THINK_FUNCTION = EFL_NO_THINK_FUNCTION

		hook.Add( "OnEntityCreated", "Created", function( vehicle )
			if vehicle:GetClass() ~= "prop_vehicle_prisoner_pod" then return end
			vehicle:AddEFlags( EFL_NO_THINK_FUNCTION )
		end )

		hook.Add( "PlayerLeaveVehicle", "Leave", function( _, vehicle )
			if vehicle:GetClass() ~= "prop_vehicle_prisoner_pod" then return end
			hook.Add( "Think", vehicle, function( self )
				hook.Remove( "Think", self )
				if self:GetInternalVariable( "m_bEnterAnimOn" ) then return end
				if self:GetInternalVariable( "m_bExitAnimOn" ) then return end
				self:AddEFlags( EFL_NO_THINK_FUNCTION )
			end )
		end )

		hook.Add( "PlayerEnteredVehicle", "Enter", function( _, vehicle )
			if vehicle:GetClass() ~= "prop_vehicle_prisoner_pod" then return end
			vehicle:RemoveEFlags( EFL_NO_THINK_FUNCTION )
		end )
	end, function()
		hook.Remove( "OnEntityCreated", "Created" )
		hook.Remove( "PlayerLeaveVehicle", "Leave" )
		hook.Remove( "PlayerEnteredVehicle", "Enter" )
	end )

	-- Fixes for prop_vehicle_prisoner_pod, worldspawn (and other not Valid but not NULL entities) damage taking (bullets only)
	-- Explosive damage only works if is located in front of prop_vehicle_prisoner_pod (wtf?)
	rpatches.Register( "prop_vehicle_prisoner_pod Explosive Damage", function()
		hook.Add( "EntityTakeDamage", "Catch Damage", function( entity, damageInfo )
			if not IsValid( entity ) or entity:IsNPC() then return end
			if entity.AcceptDamageForce or entity:GetClass() ~= "prop_vehicle_prisoner_pod" then return end
			entity:TakePhysicsDamage( damageInfo )
		end )
	end, function()
		hook.Remove( "EntityTakeDamage", "Catch Damage" )
	end )

	return
end

do

	local view = {
		["type"] = "2D"
	}

	function cam.Start2D()
		cam.Start( view )
	end

end

do
	local localPlayer = LocalPlayer
	if iscfunction( localPlayer ) then
		local entity
		function _G.LocalPlayer()
			entity = localPlayer()

			if IsValid( entity ) then
				_G.LocalPlayer = function()
					return entity
				end
			end

			return entity
		end
	end
end

rpatches.Register( "Focus Attack Fix", function()
	local system_HasFocus = system.HasFocus
	local lastNoFocusTime = 0
	local CurTime = CurTime

	hook.Add( "CreateMove", "Attack Limitter", function( cmd )
		if CurTime() - lastNoFocusTime < 0.25 then
			cmd:RemoveKey( IN_ATTACK )
			cmd:RemoveKey( IN_ATTACK2 )
		end

		if system_HasFocus() then return end
		lastNoFocusTime = CurTime()
	end )
end, function()
	hook.Remove( "CreateMove", "Attack Limitter" )
end )

rpatches.Register( "Bind Fix", function()
	local binds = {}
	hook.Add( "PlayerBindPress", "Down", function( _, bind, __, keyCode )
		if not string.StartsWith( bind, "+" ) then return end
		binds[ keyCode ] = string.sub( bind, 2, #bind )
	end )

	hook.Add( "PlayerButtonUp", "Up", function( ply, keyCode )
		local bind = binds[ keyCode ]
		if not bind then return end
		binds[ keyCode ] = nil

		hook.Run( "PlayerBindPress", ply, "-" .. bind, true, keyCode )
	end )
end )

rpatches.Register( "Arrow Camera Control Fix", function()
	local cl_pitchspeed, state = GetConVar( "cl_pitchspeed" ), 0
	hook.Add( "PlayerBindPress", "Bind", function( _, bind, keyIsDown )
		if not keyIsDown then return end

		local keyPrase = string.sub( bind, 2, #bind )
		if keyPrase == "lookup" then
			state = string.sub( bind, 1, 1 ) == "+" and 1 or 0
			return true
		elseif keyPrase == "lookdown" then
			state = string.sub( bind, 1, 1 ) == "+" and -1 or 0
			return true
		end
	end )

	hook.Add( "StartCommand", "Controll", function( _, cmd )
		if state == 0 then return end
		local angles = cmd:GetViewAngles()
		angles[ 1 ] = angles[ 1 ] - ( cl_pitchspeed:GetFloat() * ( FrameTime() * state  ) / ( cmd:KeyDown( IN_SPEED ) and 2 or 1 ) )
		cmd:SetViewAngles( angles )
	end )
end, function()
	hook.Remove( "StartCommand", "Controll" )
	hook.Remove( "PlayerBindPress", "Bind" )
end )

net.Receive( "RemoveAllDecalsFix", function()
	local entity = net.ReadEntity()
	if not IsValid( entity ) then return end
	entity:RemoveAllDecals()
end )