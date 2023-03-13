--[[

	Title: Random Patches
	Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=2806290767
	GitHub: https://github.com/Pika-Software/gmod_random_patches

--]]

local addonName = 'Random Patches'
local version = '3.4.0'

-- Just in case, white should stay white.
color_white = Color( 255, 255, 255 )

function IsValid( object )
	if (object == nil) then return false end
	if (object == false) then return false end
	if (object == NULL) then return false end

	local func = object.IsValid
	if (func == nil) then
		return false
	end

	return func( object )
end

local IsValid = IsValid
local ipairs = ipairs
local table = table
local math = math
local hook = hook

function math.Clamp( num, min, max )
	if (num < min) then return min end
	if (num > max) then return max end
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

	hook.Add( 'GameContentChanged', addonName .. ' - Improved IsMounted', cacheMounted )
	cacheMounted()

end

if SERVER then

	-- Normal Deploy Speed
	RunConsoleCommand( 'sv_defaultdeployspeed', '1' )

	-- Missing Stuff
	-- From metastruct code
	CreateConVar( 'room_type', '0' )
	scripted_ents.Register( {
		['Base'] = 'base_point',
		['Type'] = 'point'
	}, 'info_ladder' )
	
	-- ENTITY metatable optimization
	-- Based on Earu#7089 ENTITY.__index optimization
	-- Edited by Jaff#2843 and Radon#0952
	do
		local ENTITY = FindMetaTable( 'Entity' )
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

		hook.Add( 'OnEntityCreated', addonName .. ' - ChangeEntMeta', function(ent)
			-- Experimental optimization, can be disabled by convar, report all problems on our github
			if CreateConVar( 'randpatches_replace_entmeta', '1', FCVAR_ARCHIVE ):GetBool() then
				timer.Simple(0, function()
					if IsValid(ent) and getmetatable(ent) == ENTITY then
						changeEntMetaTable(ent)
					end
				end)
			end
		end, HOOK_MONITOR_HIGH )
	end
	
	-- Little optimization idea by Billy (used in voicebox)
	-- "for something that really shouldn't be O(n)"
	-- https://i.imgur.com/yPtoNvO.png
	-- https://i.imgur.com/a0lmB9m.png
	do
		local meta = FindMetaTable( 'Player' )
		if meta.UserID and debug.getinfo( meta.UserID ).short_src == '[C]' then
			RandomPatches_UserID = RandomPatches_UserID or meta.UserID
		
			function meta:UserID()
				return self.__UserID or RandomPatches_UserID( self )
			end
		
			local function CacheUserID( ply )
				ply.__UserID = RandomPatches_UserID( ply )
			end
			hook.Add( 'PlayerInitialSpawn', addonName .. ' - CacheUserID', CacheUserID, HOOK_MONITOR_HIGH )
			hook.Add( 'PlayerAuthed', addonName .. ' - CacheUserID', CacheUserID, HOOK_MONITOR_HIGH )
		end
	end

	-- Area portals fix
	do

		local mapIsCleaning = false
		hook.Add( 'PreCleanupMap', addonName .. ' - Area Portal Fix', function() mapIsCleaning = true end )
		hook.Add( 'PostCleanupMap', addonName .. ' - Area Portal Fix', function() mapIsCleaning = false end )

		local doorClasses = {
			['func_door_rotating'] = true,
			['prop_door_rotating'] = true,
			['func_movelinear'] = true,
			['func_door'] = true
		}

		local ents_FindByClass = ents.FindByClass
		hook.Add( 'EntityRemoved', addonName .. ' - Area Portal Fix', function( ent )
			if (mapIsCleaning) then return end
			if IsValid( ent ) and doorClasses[ ent:GetClass() ] then
				local name = ent:GetName()
				if (name ~= '') then
					for _, portal in ipairs( ents_FindByClass( 'func_areaportal' ) ) do
						if (portal:GetInternalVariable( 'target' ) == name) then
							portal:SetSaveValue( 'target', '' )
							portal:Fire( 'open' )
						end
					end
				end
			end
		end )

	end

	-- Fixes for prop_vehicle_prisoner_pod, worldspawn (and other not Valid but not NULL entities) damage taking (bullets only)
	-- Explosive damage only works if is located in front of prop_vehicle_prisoner_pod (wtf?)
	hook.Add( 'EntityTakeDamage', addonName .. ' - PrisonerFix', function( ent, dmg )
		if not IsValid( ent ) then return end
		if ent:IsNPC() then return end

		if ent.AcceptDamageForce or ent:GetClass() == 'prop_vehicle_prisoner_pod' then
			ent:TakePhysicsDamage( dmg )
		end
	end )

	hook.Add( 'OnFireBulletCallback', addonName .. ' - PrisonerTakeDamage', function( attk, tr, cdmg )
		local ent = tr.Entity
		if (ent ~= NULL) then
			hook.Run( 'EntityTakeDamage', ent, cdmg )
		end
	end )

	hook.Add( 'EntityFireBullets', addonName .. ' - BulletCallbackHook', function( ent, data )
		local old_callback = data.Callback
		function data.Callback( attk, tr, cdmg, ... )
			hook.Run( 'OnFireBulletCallback', attk, tr, cdmg, ... )
			if old_callback then
				return old_callback( attk, tr, cdmg, ... )
			end
		end

		return true
	end, HOOK_MONITOR_HIGH )

	-- Steam Auth Check
	hook.Add( 'PlayerInitialSpawn', addonName .. ' - Steam Auth Check', function( ply )
		if ply:IsBot() or ply:IsListenServerHost() or ply:IsFullyAuthenticated() then return end
		ply:Kick( 'Your SteamID wasn\'t fully authenticated, try restart steam.' )
	end )

	-- Pod Fix
	do

		local EFL_NO_THINK_FUNCTION = EFL_NO_THINK_FUNCTION

		hook.Add( 'OnEntityCreated', addonName .. ' - Pod Fix', function( veh )
			if (veh:GetClass() == 'prop_vehicle_prisoner_pod') then
				veh:AddEFlags( EFL_NO_THINK_FUNCTION )
			end
		end )

		hook.Add( 'PlayerEnteredVehicle', addonName .. ' - Pod Fix', function( _, veh )
			if (veh:GetClass() == 'prop_vehicle_prisoner_pod') then
				veh:RemoveEFlags( EFL_NO_THINK_FUNCTION )
			end
		end )

		hook.Add( 'PlayerLeaveVehicle', addonName .. ' - Pod Fix', function( _, veh )
			if (veh:GetClass() == 'prop_vehicle_prisoner_pod') then
				hook.Add('Think', veh, function( self )
					if self:GetInternalVariable( 'm_bEnterAnimOn' ) then
						hook.Remove( 'Think', self )
					else
						if self:GetInternalVariable( 'm_bExitAnimOn' ) then return end
						self:AddEFlags( EFL_NO_THINK_FUNCTION )
						hook.Remove( 'Think', self )
					end
				end)
			end
		end )

	end

end

if (CLIENT) then

	local string_StartsWith = string.StartWith or string.StartsWith
	local string_sub = string.sub

	-- Bind Fix
	do

		local hookName = addonName .. ' - Bind\'s Fix'
		local bindsPressed = {}

		hook.Add( 'PlayerBindPress', hookName, function( _, bindName, isDown, keyCode )
			if string_StartsWith( bindName, '+' ) then
				bindsPressed[ keyCode ] = string_sub( bindName, 2, #bindName )
			end
		end )

		hook.Add( 'PlayerButtonUp', hookName, function( ply, keyCode )
			local bindName = bindsPressed[ keyCode ]
			if (bindName == nil) or not IsFirstTimePredicted() then return end
			hook.Run( 'PlayerBindPress', ply, '-' .. bindName, true, keyCode )
			bindsPressed[ keyCode ] = nil
		end )

	end

	-- Look Up/Down Fix
	do

		local hookName = addonName .. ' - Look up/down Fix'
		local cl_pitchspeed = GetConVar( 'cl_pitchspeed' )
		local lookDown = false
		local lookUp = false

		hook.Add( 'PlayerBindPress', hookName, function( ply, bindName, isDown )
			if isDown then
				local bind = string_sub( bindName, 2, #bindName )
				if (bind == 'lookdown') then
					lookDown = string_sub( bindName, 1, 1 ) == '+'
					return true
				elseif (bind == 'lookup') then
					lookUp = string_sub( bindName, 1, 1 ) == '+'
					return true
				end
			end
		end )

		local system_HasFocus = system.HasFocus

		hook.Add( 'Think', hookName, function()
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

end

MsgC( SERVER and Color( 50, 100, 250 ) or Color( 250, 100, 50 ), string.format( '[%s v%s] ', addonName, version ), color_white, 'Game Patched!\n' )
