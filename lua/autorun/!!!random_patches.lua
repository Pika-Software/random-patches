--[[

	Title: Random Patches
	Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=2806290767
	GitHub: https://github.com/Pika-Software/gmod_random_patches

--]]

local addonName = 'Random Patches'
local version = '3.0.1'

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
		tbl[i], tbl[rand] = tbl[rand], tbl[i]
	end

	return tbl
end

function table.Random( tbl, issequential )
	local keys = issequential and tbl or table.GetKeys( tbl )
	local rand = keys[ math.random(1, #keys) ]
	return tbl[ rand ], rand
end

-- Improved is mounted
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


	hook.Add('GameContentChanged', addonName .. ' - Improved IsMounted', cacheMounted)
	cacheMounted()

end

if (SERVER) then

	-- Missing Stuff
	CreateConVar( 'room_type', '0' )
	scripted_ents.Register({
		['Base'] = 'base_point',
		['Type'] = 'point'
	}, 'info_ladder')

	-- Area portals fix
	do

		local mapIsCleaning = false
		hook.Add('PreCleanupMap', addonName .. ' - Area Portal Fix', function() mapIsCleaning = true end)
		hook.Add('PostCleanupMap', addonName .. ' - Area Portal Fix', function() mapIsCleaning = false end)

		local doorClasses = {
			['func_door_rotating'] = true,
			['prop_door_rotating'] = true,
			['func_movelinear'] = true,
			['func_door'] = true
		}

		local ents_FindByClass = ents.FindByClass
		hook.Add('EntityRemoved', addonName .. ' - Area Portal Fix', function( ent )
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
		end)

	end

	-- Fixes for prop_vehicle_prisoner_pod, worldspawn (and other not Valid but not NULL entities) damage taking (bullets only)
	-- Explosive damage only works if is located in front of prop_vehicle_prisoner_pod (wtf?)
	hook.Add('EntityTakeDamage', addonName .. ' - PrisonerFix', function( ent, dmg )
		if IsValid( ent ) then
			if ent:IsNPC() then return end
			if ent.AcceptDamageForce or ent:GetClass() == 'prop_vehicle_prisoner_pod' then
				ent:TakePhysicsDamage( dmg )
			end
		end
	end)

	hook.Add('OnFireBulletCallback', addonName .. ' - PrisonerTakeDamage', function( attk, tr, cdmg )
		local ent = tr.Entity
		if (ent ~= NULL) then
			hook.Run( 'EntityTakeDamage', ent, cdmg )
		end
	end)

	hook.Add('EntityFireBullets', addonName .. ' - BulletCallbackHook', function( ent, data )
		local old_callback = data.Callback
		function data.Callback( attk, tr, cdmg, ... )
			hook.Run( 'OnFireBulletCallback', attk, tr, cdmg, ... )
			if old_callback then
				return old_callback( attk, tr, cdmg, ... )
			end
		end

		return true
	end)

	-- Steam Auth Check
	hook.Add('PlayerInitialSpawn', addonName .. ' - Steam Auth Check', function( ply )
		if ply:IsBot() or ply:IsListenServerHost() or ply:IsFullyAuthenticated() then return end
		ply:Kick( 'Your SteamID wasn\'t fully authenticated, try restart steam.' )
	end)

	-- Pod Fix
	do

		local EFL_NO_THINK_FUNCTION = EFL_NO_THINK_FUNCTION

		hook.Add('OnEntityCreated', addonName .. ' - Pod Fix', function( veh )
			if (veh:GetClass() == 'prop_vehicle_prisoner_pod') then
				veh:AddEFlags( EFL_NO_THINK_FUNCTION )
			end
		end)

		hook.Add('PlayerEnteredVehicle', addonName .. ' - Pod Fix', function( _, veh )
			if (veh:GetClass() == 'prop_vehicle_prisoner_pod') then
				veh:RemoveEFlags( EFL_NO_THINK_FUNCTION )
			end
		end)

		hook.Add('PlayerLeaveVehicle', addonName .. ' - Pod Fix', function( _, veh )
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
		end)

	end

end

if (CLIENT) then

	-- Fix Client Side Props
	do

		local ENT = {
			['Base'] = 'base_anim',
			['ClassName'] = 'prop_client'
		}

		function ENT:Draw( fl )
			self:DrawModel( fl )
		end

		scripted_ents.Register( ENT, 'prop_client' )

	end

	do

		local ents_CreateClientside = ents.CreateClientside
		local Model = Model

		function ents.CreateClientProp( model )
			local ent = ents_CreateClientside( 'prop_client' )
			if IsValid( ent ) then
				if (model ~= nil) then
					ent:SetModel( Model( model ) )
				end

				ent:SetMoveType( MOVETYPE_VPHYSICS )
				ent:PhysicsInit( SOLID_VPHYSICS )
				ent:SetSolid( SOLID_VPHYSICS )
				ent:PhysWake()
			end

			return ent
		end

	end

end

MsgC( string.format( '[%s v%s] ', addonName, version ), HSVToColor( math.random( 360 ) % 360, 0.9, 0.8 ), 'Game Patched!\n' )