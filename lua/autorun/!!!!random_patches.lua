local addon_name = "Random Patches"
local version = "1.5.1"

CreateConVar( "room_type", "0" )

scripted_ents.Register({
    ["Base"] = "base_point",
    ["Type"] = "point"
}, "info_ladder")

function IsValid( object )
    if (object == nil) then return false end
    if (object == false) then return object end
    if (object == NULL) then return false end

	local func = object.IsValid
    if (func == nil) then return false end

	return func( object ) or false
end

function math.Clamp( inval, minval, maxval )
	if (inval < minval) then return minval end
	if (inval > maxval) then return maxval end
	return inval
end

do

    local math_random = math.random

    do
        local table_GetKeys = table.GetKeys
        function table.Random( tab, issequential )
            local keys = issequential and tab or table_GetKeys(tab)
            local rand = keys[math_random(1, #keys)]
            return tab[rand], rand
        end
    end

    do
        local table_Count = table.Count
        function table.shuffle( tbl )
            local len = table_Count( tbl )
            for i = len, 1, -1 do
                local rand = math_random( len )
                tbl[i], tbl[rand] = tbl[rand], tbl[i]
            end

            return tbl
        end

        table.Shuffle = table.shuffle
    end

end

local hook_Add = hook.Add
local IsValid = IsValid
local ipairs = ipairs

local MapIsCleaning = false
hook_Add("PreCleanupMap", addon_name .. " - PreCleanup", function() MapIsCleaning = true end)
hook_Add("PostCleanupMap", addon_name .. " - AfterCleanup", function() MapIsCleaning = false end)

if (SERVER) then

    -- Reset player color on spawn
    do
        local white = Color( 255, 255, 255 )
        hook_Add("PlayerSpawn", addon_name .. " - Reset Player Color", function( ply )
            ply:SetColor( white )
        end)
    end

    -- dll module require
    concommand.Add( "require", function( ply, cmd, args )
        if not IsValid( ply ) then
            for num, moduleName in ipairs( args ) do
                if isstring( moduleName ) then
                    pcall( require, moduleName )
                end
            end
        end
    end, nil, "Require dll/lua module", FCVAR_LUA_SERVER)

    do
        local doorClasses = {
            ["func_door"] = true,
            ["func_door_rotating"] = true,
            ["prop_door_rotating"] = true,
            ["func_movelinear"] = true
        }

        local ents_FindByClass = ents.FindByClass
        hook_Add("EntityRemoved", addon_name .. " - Area Portal Fix", function(ent)
            if MapIsCleaning then return end
            if IsValid( ent ) and doorClasses[ ent:GetClass() ] then
                local name = ent:GetName()
                if (name != "") then
                    for num, portal in ipairs( ents_FindByClass( "func_areaportal" ) ) do
                        if (portal:GetInternalVariable( "target" ) == name) then
                            portal:SetSaveValue( "target", "" )
                            portal:Fire( "Open" )
                        end
                    end
                end
            end
        end)
    end

    -- Fixes for prop_vehicle_prisoner_pod, worldspawn (and other not Valid but not NULL entities) damage taking (bullets only)
    -- Explosive damage only works if is located in front of prop_vehicle_prisoner_pod (wtf?)

    do

        local vector_origin = vector_origin
        local DMG_DISSOLVE = DMG_DISSOLVE

        hook_Add("EntityTakeDamage", addon_name .. " - ApplyDamageForce", function( ent, dmg )
            if IsValid( ent ) then
                if ent:IsNPC() then return end

                -- Zero health fix
                if ent:IsPlayer() then
                    timer.Simple(0, function()
                        if IsValid( ent ) and ent:Alive() and (ent:Health() < 1) then
                            dmg:SetDamageType( DMG_DISSOLVE )
                            dmg:SetDamage( 9999 )
                            ent:TakeDamageInfo( dmg )
                        end
                    end)
                end

                if ent.AcceptDamageForce or ent:GetClass() == "prop_vehicle_prisoner_pod" then
                    ent:TakePhysicsDamage( dmg )
                end

                local index = ent:EntIndex()
                local attacker = dmg:GetAttacker()
                if IsValid( attacker ) and (index == attacker:EntIndex()) then
                    return
                end

                local inflictor = dmg:GetInflictor()
                if IsValid( inflictor ) and (index == inflictor:EntIndex()) then
                    return
                end

                local phys = ent:GetPhysicsObject()
                if IsValid( phys ) then
                    phys:ApplyForceOffset( dmg:GetDamageForce() * (dmg:IsExplosionDamage() and math.max(1, math.floor(dmg:GetDamage() / 12)) or 1), dmg:GetDamagePosition() )
                    dmg:SetDamageForce( vector_origin )
                end

            end
        end)

    end

    do

        local hook_Run = hook.Run
        hook_Add("OnFireBulletCallback", addon_name .. " - PrisonerTakeDamage", function( attk, tr, cdmg )
            local ent = tr.Entity
            if (ent ~= NULL) then
                hook_Run( "EntityTakeDamage", ent, cdmg )
            end
        end)

        hook_Add("EntityFireBullets", addon_name .. " - BulletCallbackHook", function( ent, data )
            local old_callback = data.Callback
            function data.Callback( attk, tr, cdmg, ... )
                hook_Run( "OnFireBulletCallback", attk, tr, cdmg, ... )
                if old_callback then
                    return old_callback( attk, tr, cdmg, ... )
                end
            end

            return true
        end)

    end

end

do

    local math_ceil = math.ceil
    local math_log = math.log
    local math_max = math.max

    local net_WriteUInt = net.WriteUInt
    local net_WriteBool = net.WriteBool
    local net_ReadUInt = net.ReadUInt
    local net_ReadBool = net.ReadBool
    local net_Receive = net.Receive
    local net_Start = net.Start

    local Entity = Entity

    if (util.NetworkStringToID("LocalVoiceVolume.Relay") == 0) then

        local PLAYER = FindMetaTable( "Player" )
        local ENTITY = FindMetaTable( "Entity" )

        local plyBits = math_ceil(math_log(game.MaxPlayers(), 2))
        local voiceVolumeBits = math_ceil(math_log(100, 2))
        local voiceVolumePoll = math_max(0.25, engine.TickInterval())

        local PLAYER_IsSpeaking = PLAYER.IsSpeaking
        local PLAYER_VoiceVolume = PLAYER.VoiceVolume
        local ENTITY_IsValid = ENTITY.IsValid
        local ENTITY_EntIndex = ENTITY.EntIndex

        if (SERVER) then
            local util_AddNetworkString = util.AddNetworkString
            local net_Send = net.Send

            util_AddNetworkString("LocalVoiceVolume.Claim")
            util_AddNetworkString("LocalVoiceVolume.Relay")

            local function relay(ply, voiceVolume)
                net_Start("LocalVoiceVolume.Relay", true)
                    net_WriteUInt(voiceVolume, voiceVolumeBits)
                net_Send(ply)
            end

            local claimed = {}
            net_Receive("LocalVoiceVolume.Claim", function(_, sender)
                local ply = Entity(net_ReadUInt(plyBits))
                if not ENTITY_IsValid(ply) then return end

                local claim = net_ReadBool()
                if claim then
                    if claimed[ply] or not PLAYER_IsSpeaking(ply) then return end

                    claimed[ply] = sender

                    relay(ply, net_ReadUInt(voiceVolumeBits))

                    net_Start("LocalVoiceVolume.Claim")
                        net_WriteUInt(ENTITY_EntIndex(ply), plyBits)
                    net_Send(sender)
                elseif claimed[ply] == sender then
                    claimed[ply] = nil
                end
            end)

            net_Receive("LocalVoiceVolume.Relay", function(_, sender)
                local ply = Entity(net_ReadUInt(plyBits))
                if claimed[ply] ~= sender or not PLAYER_IsSpeaking(ply) then return end

                relay(ply, net_ReadUInt(voiceVolumeBits))
            end)

            hook_Add("PlayerDisconnected", "LocalVoiceVolume", function(ply)
                claimed[ply] = nil
            end)

        else

            LVV_VANILLA_VOICE_VOLUME = LVV_VANILLA_VOICE_VOLUME or PLAYER.VoiceVolume
            local LVV_VANILLA_VOICE_VOLUME = LVV_VANILLA_VOICE_VOLUME

            local timer_Create = timer.Create
            local LocalPlayer = LocalPlayer
            local GetConVar = GetConVar

            local Me
            timer_Create("LocalVoiceVolume.LocalPlayer", 0, 0, function()
                if IsValid(LocalPlayer()) then
                    Me = LocalPlayer()
                    timer.Remove("LocalVoiceVolume.LocalPlayer")
                end
            end)

            local networkedVoiceVolume = 0
            local voice_loopback = GetConVar("voice_loopback")
            local claimed = {}

            function PLAYER:VoiceVolume()
                if self == Me and not voice_loopback:GetBool() then
                    return networkedVoiceVolume
                else
                    return LVV_VANILLA_VOICE_VOLUME(self)
                end
            end

            local math_min = math.min

            net_Receive("LocalVoiceVolume.Relay", function()
                networkedVoiceVolume = math_min(net_ReadUInt(voiceVolumeBits) / 100, 100)
            end)

            local timer_Exists = timer.Exists
            local timer_Start = timer.Start

            hook_Add("PlayerStartVoice", "LocalVoiceVolume", function(ply)
                if not Me or ply == Me or ply:IsBot() or ply:GetVoiceVolumeScale() ~= 1 then return end

                local timerEndName = "LocalVoiceVolume.End:" .. ply:AccountID()
                if timer_Exists(timerEndName) then
                    timer_Start(timerEndName)
                else
                    net_Start("LocalVoiceVolume.Claim", true)
                        net_WriteUInt(ENTITY_EntIndex(ply), plyBits)
                        net_WriteBool(true)
                        net_WriteUInt(PLAYER_VoiceVolume(ply), voiceVolumeBits)
                    net_SendToServer()
                end
            end)

            hook_Add("PlayerEndVoice", "LocalVoiceVolume", function(ply)
                if Me and ply == Me then
                    networkedVoiceVolume = 0
                end
            end)

            local gui_IsConsoleVisible = CLIENT and gui.IsConsoleVisible
            local gui_IsGameUIVisible = CLIENT and gui.IsGameUIVisible
            local net_SendToServer = CLIENT and net.SendToServer

            local math_Round = math.Round

            net_Receive("LocalVoiceVolume.Claim", function()
                local plyId = net_ReadUInt(plyBits)
                local ply = Entity(plyId)
                if not ENTITY_IsValid(ply) then return end

                local timerName = "LocalVoiceVolume:" .. ply:AccountID()
                local timerEndName = "LocalVoiceVolume.End:" .. ply:AccountID()

                timer_Create(timerEndName, 1, 1, function()
                    timer.Remove(timerName)
                    claimed[ply] = nil

                    if ENTITY_IsValid(ply) then
                        net_Start("LocalVoiceVolume.Claim")
                            net_WriteUInt(plyId, plyBits)
                            net_WriteBool(false)
                        net_SendToServer()
                    end
                end)

                timer_Create(timerName, voiceVolumePoll, 0, function()
                    if not ENTITY_IsValid(ply) then
                        timer.Remove(timerName)
                        timer.Remove(timerEndName)
                        claimed[ply] = nil
                        return
                    end

                    if PLAYER_IsSpeaking(ply) and not gui_IsGameUIVisible() and not gui_IsConsoleVisible() then
                        timer_Start(timerEndName)

                        net_Start("LocalVoiceVolume.Relay", true)
                            net_WriteUInt(plyId, plyBits)
                            net_WriteUInt(math_Round(PLAYER_VoiceVolume(ply) * 100), voiceVolumeBits)
                        net_SendToServer()
                    end
                end)
            end)
        end
    end

end

do
    function string.getChar( str, pos )
        return str:sub( pos, pos )
    end

    string.GetChar = string.getChar
end

do

    local file_Find = file.Find
    _GRandomPatches = _GRandomPatches or {}
    _GRandomPatches.file_IsDir = _GRandomPatches.file_IsDir or file.IsDir
    function file.IsDir( path, gamePath )
        local files, folders = file_Find( path:GetPathFromFilename() .. "*", gamePath or "DATA" )

        local name = path:GetFileFromFilename():lower()
        for num, fol in ipairs( folders ) do
            if (fol == name) then
                return true
            end
        end

        return false
    end

    _GRandomPatches.file_Exists = _GRandomPatches.file_Exists or file.Exists
    function file.Exists( path, gamePath )
        -- Fucking LSAC using this function
        if path:StartWith( "addons/lsac/" ) then
            return _GRandomPatches.file_Exists( path, gamePath )
        end

        local files, folders = file_Find( path:GetPathFromFilename() .. "*", gamePath or "DATA" )

        local name = path:GetFileFromFilename():lower()
        for num, fl in ipairs( files ) do
            if (fl == name) then
                return true
            end
        end

        for num, fol in ipairs( folders ) do
            if (fol == name) then
                return true
            end
        end

        return false
    end
end

if (CLIENT) then

    do

        local ENT = {}
        ENT.Base = "base_anim"
        ENT.ClassName = "client_side_prop"

        function ENT:Draw( fl )
            self:DrawModel( fl )
        end

        scripted_ents.Register( ENT, "client_side_prop" )

    end

    do
        local ents_CreateClientside = ents.CreateClientside
        function ents.CreateClientProp( mdl )
            local ent = ents_CreateClientside( "client_side_prop" )
            if (mdl ~= nil) then
                ent:SetModel( Model( mdl ) )
                ent:SetMoveType( MOVETYPE_VPHYSICS )
                ent:SetSolid( SOLID_VPHYSICS )
                ent:PhysicsInit( SOLID_VPHYSICS )
                ent:PhysWake()
            end

            return ent
        end
    end

elseif game.IsDedicated() then

    hook_Add("PlayerInitialSpawn", addon_name .. " - async_stdout", function()
        hook.Remove("PlayerInitialSpawn", "async_stdout")
        local dll = "gmsv_async_stdout_"..(system.IsWindows()and"win"or system.IsLinux()and"linux"or"UNSUPPORTED")..(jit.arch=="x64"and"64"or(system.IsLinux()and""or"32"))..".dll"
        if file.Exists( "lua/bin/" .. dll, "GAME" ) then
            MsgC( Color( 220, 60, 60), 'If your console started to work strangely after this message, then delete ' .. dll .. '\nfrom the "lua/bin" folder, this dll file is not compatible with your hosting.' )
            if pcall( require, "async_stdout" ) then
                return
            end
        else
            MsgC( Color( 250, 150, 50), "\nIf your server using external controll panel, it's probably using the console.log file, which can reduce server performance by 95% by constantly stopping the thread!\n\nIn order to fix this you need to download '" .. dll .. "\nFrom Github: 'https://github.com/WilliamVenner/gmsv_async_stdout/releases' to 'garrysmod/lua/bin/'\n\n" )
        end
    end)

    -- Simple Server Protection
    do

        local family_sharing = CreateConVar("allow_family_sharing", "0", FCVAR_ARCHIVE, " - Allows connecting players with family shared Garry's Mod copy.", 0, 1 ):GetBool()
        cvars.AddChangeCallback("allow_family_sharing", function( name, old, new )
            family_sharing = new == "1"
        end)

        local util_SteamIDTo64 = util.SteamIDTo64
        hook_Add("PlayerInitialSpawn", addon_name .. " - Simple Server Protection", function( ply )
            if ply:IsBot() or ply:IsListenServerHost() then return end

            -- https://github.com/Be1zebub/Small-GLua-Things/blob/master/anti_steamid_spoof.lua
            timer.Simple(0, function()
                if IsValid( ply ) == false or ply:IsFullyAuthenticated() then return end
                ply:Kick("Your SteamID wasn't fully authenticated, try restarting steam.")
            end)

            if family_sharing and (ply:OwnerSteamID64() ~= ply:SteamID64()) then
                ply:Kick( "Family sharing restricted!" )
            end
        end)

    end

end

MsgC( "\n[" .. addon_name .." v" .. version .. "] ", HSVToColor( ( math.random( 360 ) ) % 360, 0.9, 0.8 ), "Game Patched!\n" )
