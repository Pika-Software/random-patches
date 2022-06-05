local addon_name = "Random Patches"
local version = "2.3.1"

CreateConVar( "room_type", "0" )
scripted_ents.Register({
    ["Base"] = "base_point",
    ["Type"] = "point"
}, "info_ladder")

-- Improved default garry's mod functions
do

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

    local math_random = math.random
    function table.Shuffle( tbl )
        local len = #tbl
        for i = len, 1, -1 do
            local rand = math_random( len )
            tbl[i], tbl[rand] = tbl[rand], tbl[i]
        end

        return tbl
    end

end

local hook_Run = hook.Run
local IsValid = IsValid
local ipairs = ipairs

if (SERVER) then

    -- Reset player color on spawn
    do
        local white = Color( 255, 255, 255 )
        hook.Add("PlayerSpawn", addon_name .. " - Reset Player Color", function( ply )
            ply:SetColor( white )
        end)
    end

    -- Area portal fix if door was removed
    do

        local MapIsCleaning = false
        hook.Add("PreCleanupMap", addon_name .. " - PreCleanup", function() MapIsCleaning = true end)
        hook.Add("PostCleanupMap", addon_name .. " - AfterCleanup", function() MapIsCleaning = false end)

        local doorClasses = {
            ["func_door"] = true,
            ["func_door_rotating"] = true,
            ["prop_door_rotating"] = true,
            ["func_movelinear"] = true
        }

        local ents_FindByClass = ents.FindByClass
        hook.Add("EntityRemoved", addon_name .. " - Area Portal Fix", function(ent)
            if (MapIsCleaning) then return end
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

        hook.Add("EntityTakeDamage", addon_name .. " - ApplyDamageForce", function( ent, dmg )
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

    hook.Add("OnFireBulletCallback", addon_name .. " - PrisonerTakeDamage", function( attk, tr, cdmg )
        local ent = tr.Entity
        if (ent ~= NULL) then
            hook_Run( "EntityTakeDamage", ent, cdmg )
        end
    end)

    hook.Add("EntityFireBullets", addon_name .. " - BulletCallbackHook", function( ent, data )
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

-- Online fix loader
do

    local SHARED = CLIENT or SERVER
    local online_fixes = {
        -- This fixes PLAYER:VoiceVolume() for the local player in Garry's Mod.
        -- By WilliamVenner (https://github.com/WilliamVenner/localvoicevolume)
        {"https://raw.githubusercontent.com/WilliamVenner/localvoicevolume/master/lua/autorun/localvoicevolume.lua", "WilliamVenner/localvoicevolume", SHARED},

        -- Thats better then a shitty glua table.Random function
        {"https://raw.githubusercontent.com/Be1zebub/Small-GLua-Things/master/sh_tablerandom.lua", "Be1zebub/Small-GLua-Things/sh_tablerandom.lua", SHARED},

        -- this mod attempts to fix this issue: ValveSoftware/source-sdk-2013#442
        {"https://raw.githubusercontent.com/wgetJane/gmod-shootpos-fix/master/lua/autorun/shootpos_fix.lua", "wgetJane/gmod-shootpos-fix", SHARED},

        -- Fixes the hook bloat caused by gmod_hands
        {"https://raw.githubusercontent.com/CFC-Servers/gmod_hands_fix/master/lua/autorun/cfc_fix_hands.lua", "CFC-Servers/gmod_hands_fix", SHARED},

        -- This is a small, somewhat janky script which I put together to fix a crash in gmod whenever a magnet entity was removed from a crane.
        {"https://raw.githubusercontent.com/OnTheMatter/gmodaddon-script-cranecrashpreventer-Obsolete-/main/cranecrashprevention/lua/autorun/CraneBugFixLuaHook.lua", "OnTheMatter/gmodaddon-script-cranecrashpreventer-Obsolete", SERVER},

        -- This addon aims to fix "fake hits" whenever a player shoots another player, this can cause the attacker to see fake blood particles while the player that's getting show at receives no damage at all.
        {"https://raw.githubusercontent.com/wrefgtzweve/blood-fix/master/lua/autorun/server/sv_blood_hit.lua", "wrefgtzweve/blood-fix", SERVER},

        -- Seats network optimization
        {"https://raw.githubusercontent.com/Kefta/gs_podfix/master/lua/autorun/server/gs_podfix.lua", SERVER}
    }

    for num, data in ipairs( online_fixes ) do
        if (data[3]) then
            timer.Simple(0.25 * num, function()
                http.Fetch(data[1], function( body, size, headers, code )
                    if ((code > 200) and (code < 300)) or (code == 0) then
                        local func = CompileString( body, data[2] )
                        if (func ~= nil) then
                            pcall( func )
                        end
                    end
                end)
            end)
        end
    end

end

-- file.IsDir & file.Exists fixes
do

    _GRandomPatches = _GRandomPatches or {}

    local file_Find = file.Find
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

-- Client side prop's fix
if (CLIENT) then

    do

        local ENT = {}
        ENT.Base = "base_anim"
        ENT.ClassName = "prop_client"

        function ENT:Draw( fl )
            self:DrawModel( fl )
        end

        scripted_ents.Register( ENT, "prop_client" )

    end

    do
        local ents_CreateClientside = ents.CreateClientside
        function ents.CreateClientProp( mdl )
            local ent = ents_CreateClientside( "prop_client" )
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

end

if (SERVER) and not game.SinglePlayer() then

    -- Fixes from workshop
    do

        local workshop_content = {
            -- Sand texture fix
            "1619797564",
        }

        for num, wsid in ipairs( workshop_content ) do
            resource.AddWorkshop( wsid )
        end

    end

    -- TF2 Maps fix
    if IsMounted( "tf" ) then
        local map = game.GetMap()
        for num, tag in ipairs( {"pl_", "tr_", "to_", "sd_", "rd_", "plr_", "pd_", "pass_", "mvm_", "koth_", "ctf_", "cp_", "arena_"} ) do
            if map:StartWith( tag ) then
                resource.AddWorkshop( "110560370" )
            end
        end
    end

    -- Simple server protection
    do

        local family_sharing = CreateConVar("allow_family_sharing", "0", FCVAR_ARCHIVE, " - Allows connecting players with family shared Garry's Mod copy.", 0, 1 ):GetBool()
        cvars.AddChangeCallback("allow_family_sharing", function( name, old, new )
            family_sharing = new == "1"
        end)

        hook.Add("PlayerInitialSpawn", addon_name .. " - Simple Server Protection", function( ply )
            if ply:IsBot() or ply:IsListenServerHost() then return end

            timer.Simple(0, function()
                if IsValid( ply ) then
                    if ply:IsFullyAuthenticated() then return end
                    ply:Kick( "Your SteamID wasn't fully authenticated, try restarting steam." )
                end
            end)

            if (family_sharing) and (ply:OwnerSteamID64() ~= ply:SteamID64()) then
                ply:Kick( "Family sharing restricted!" )
            end
        end)

    end

end

MsgC( "\n[" .. addon_name .." v" .. version .. "] ", HSVToColor( math.random( 360 ) % 360, 0.9, 0.8 ), "Game Patched!\n" )