--[[

    Title: Random Patches
    Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=2806290767
    GitHub: https://github.com/Pika-Software/gmod_random_patches

--]]

local addon_name = "Random Patches"
local version = "2.7.4"

local hook_Run = hook.Run
local IsValid = IsValid
local ipairs = ipairs
local math_random = math.random
local is_ttt = engine.ActiveGamemode() == "terrortown"

do -- Improved default garry's mod functions
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

    function table.Shuffle( tbl )
        local len = #tbl
        for i = len, 1, -1 do
            local rand = math_random( len )
            tbl[i], tbl[rand] = tbl[rand], tbl[i]
        end
        return tbl
    end
end

-- Improved is mounted
do
    local Mounted = {}

    local function CacheMount()
        table.Empty( Mounted )
        for i, data in ipairs( engine.GetGames() ) do
            if data.mounted then
                Mounted[ data.depot ] = true
                Mounted[ data.folder ] = true
            end
        end
    end
    hook.Add("GameContentChanged", "CacheMount", CacheMount)

    CacheMount()

    function IsMounted( name )
        local data = Mounted[ name ]
        if data then return true end

        return false
    end
end

if (SERVER) then
    CreateConVar( "room_type", "0" )
    scripted_ents.Register({
        ["Base"] = "base_point",
        ["Type"] = "point"
    }, "info_ladder")

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

                if (is_ttt) then return end
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

        -- Attempts to fix this issue: ValveSoftware/source-sdk-2013#442
        {"https://raw.githubusercontent.com/wgetJane/gmod-shootpos-fix/master/lua/autorun/shootpos_fix.lua", "wgetJane/gmod-shootpos-fix", SHARED},

        -- Fixes the hook bloat caused by gmod_hands
        {"https://raw.githubusercontent.com/CFC-Servers/gmod_hands_fix/master/lua/autorun/cfc_fix_hands.lua", "CFC-Servers/gmod_hands_fix", SHARED},

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

    __RandomPatches = __RandomPatches or {}

    local file_Find = file.Find
    __RandomPatches.file_IsDir = __RandomPatches.file_IsDir or file.IsDir
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

    __RandomPatches.file_Exists = __RandomPatches.file_Exists or file.Exists
    function file.Exists( path, gamePath )
        -- Fucking LSAC using this function
        if path:StartWith( "addons/lsac/" ) then
            return __RandomPatches.file_Exists( path, gamePath )
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

    hook.Add("PlayerBindPress", "Bind Press Fix", function( ply, bind, pressed, code )
        if (bind:sub(1, 1) == "+") then
            if (ply.BindsPressed == nil) then ply.BindsPressed = {} end
            ply.BindsPressed[ code ] = bind
        end
    end)

    hook.Add("PlayerButtonUp", "Bind Press Fix", function( ply, code )
        if (ply.BindsPressed == nil) then ply.BindsPressed = {} end
        local bind = ply.BindsPressed[ code ]
        if (bind) then
            hook.Run( "PlayerBindPress", ply, "-" .. bind:sub(2, #bind ), true, code )
            ply.BindsPressed[ code ] = nil
        end
    end)

    do
        local angle_up = Angle( 0.5, 0, 0 )
        hook.Add("PlayerBindPress", "Lookup-down Fix", function( ply, bind, pressed )
            if (pressed) then
                local bind_name = bind:sub( 2, #bind )
                if (bind_name == "lookup") then
                    if (bind:sub( 1, 1 ) == "+") then
                        hook.Add("Think", "Lookup Fix", function()
                            if IsValid( ply ) and system.HasFocus() then
                                ply:SetEyeAngles( ply:EyeAngles() - angle_up )
                            else
                                hook.Remove( "Think", "Lookup Fix" )
                            end
                        end)
                    else
                        hook.Remove( "Think", "Lookup Fix" )
                    end

                    return true
                end

                if (bind_name == "lookdown") then
                    if (bind:sub( 1, 1 ) == "+") then
                        hook.Add("Think", "Lookdown Fix", function()
                            if IsValid( ply ) and system.HasFocus() then
                                ply:SetEyeAngles( ply:EyeAngles() + angle_up )
                            else
                                hook.Remove( "Think", "Lookdown Fix" )
                            end
                        end)
                    else
                        hook.Remove( "Think", "Lookdown Fix" )
                    end

                    return true
                end
            end
        end)
    end

    -- Broken binding "+zoom" on TTT #1
    hook.Add("PostGamemodeLoaded", "TTT +zoom fix", function()
        function GAMEMODE:PlayerBindPress(ply, bind, pressed)
            if not IsValid(ply) then return end

            if bind == "invnext" and pressed then
               if ply:IsSpec() then
                  TIPS.Next()
               else
                  WSWITCH:SelectNext()
               end
               return true
            elseif bind == "invprev" and pressed then
               if ply:IsSpec() then
                  TIPS.Prev()
               else
                  WSWITCH:SelectPrev()
               end
               return true
            elseif bind == "+attack" then
               if WSWITCH:PreventAttack() then
                  if not pressed then
                     WSWITCH:ConfirmSelection()
                  end
                  return true
               end
            elseif bind == "+sprint" then
               -- set voice type here just in case shift is no longer down when the
               -- PlayerStartVoice hook runs, which might be the case when switching to
               -- steam overlay
               ply.traitor_gvoice = false
               RunConsoleCommand("tvog", "0")
               return true
            elseif bind == "+use" and pressed then
               if ply:IsSpec() then
                  RunConsoleCommand("ttt_spec_use")
                  return true
               elseif TBHUD:PlayerIsFocused() then
                  return TBHUD:UseFocused()
               end
            elseif string.sub(bind, 1, 4) == "slot" and pressed then
               local idx = tonumber(string.sub(bind, 5, -1)) or 1

               -- if radiomenu is open, override weapon select
               if RADIO.Show then
                  RADIO:SendCommand(idx)
               else
                  WSWITCH:SelectSlot(idx)
               end
               return true
            elseif bind == "+zoom" and pressed then
               -- open or close radio
               RADIO:ShowRadioCommands(not RADIO.Show)
               return true
            elseif bind == "+voicerecord" then
               if not VOICE.CanSpeak() then
                  return true
               end
            elseif bind == "gm_showteam" and pressed and ply:IsSpec() then
               local m = VOICE.CycleMuteState()
               RunConsoleCommand("ttt_mute_team", m)
               return true
            elseif bind == "+duck" and pressed and ply:IsSpec() then
               if not IsValid(ply:GetObserverTarget()) then
                  if GAMEMODE.ForcedMouse then
                     gui.EnableScreenClicker(false)
                     GAMEMODE.ForcedMouse = false
                  else
                     gui.EnableScreenClicker(true)
                     GAMEMODE.ForcedMouse = true
                  end
               end
            elseif bind == "noclip" and pressed then
               if not GetConVar("sv_cheats"):GetBool() then
                  RunConsoleCommand("ttt_equipswitch")
                  return true
               end
            elseif (bind == "gmod_undo" or bind == "undo") and pressed then
               RunConsoleCommand("ttt_dropammo")
               return true
            elseif bind == "phys_swap" and pressed then
               RunConsoleCommand("ttt_quickslot", "5")
            end
         end
    end)


    -- DScrollPanel fix
    do

        local function replace( self )

            local Tall = self.pnlCanvas:GetTall()
            local Wide = self:GetWide()

            self.VBar:SetUp( self:GetTall(), self.pnlCanvas:GetTall() )
            self.pnlCanvas:SetPos( 0, self.VBar:GetOffset() )
            self.pnlCanvas:SetWide( Wide )

            self:Rebuild()

            if Tall ~= self.pnlCanvas:GetTall() then
                self.VBar:SetScroll( self.VBar:GetScroll() )
            end

        end

        __RandomPatches["derma.DefineControl"] = derma.DefineControl
        local func = __RandomPatches["derma.DefineControl"]

        function derma.DefineControl( name, description, tab, base )
            if (name == "DScrollPanel") then
                tab.PerformLayoutInternal = replace
            end

            return func( name, description, tab, base )
        end

    end

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
            if IsValid( ent ) then
                if (mdl ~= nil) then
                    ent:SetModel( Model( mdl ) )
                end

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
                MsgN( "[Random Patches] Activated TF2 textures replacement." )
                resource.AddWorkshop( "110560370" )
                break
            end
        end
    end

    -- Simple server protection
    do

        local family_sharing = CreateConVar("allow_family_sharing", "0", FCVAR_ARCHIVE, " - Allows connecting players with family shared Garry's Mod copy.", 0, 1 ):GetBool()
        cvars.AddChangeCallback("allow_family_sharing", function( name, old, new )
            family_sharing = new == "1"
        end)

        hook.Add("PlayerInitialSpawn", addon_name, function( ply )
            if ply:IsBot() or ply:IsListenServerHost() then return end

            if not ply:IsFullyAuthenticated() then
                ply:Kick( "Your SteamID wasn't fully authenticated, try restart steam." )
            end

            if family_sharing and (ply:OwnerSteamID64() ~= ply:SteamID64()) then
                ply:Kick( "Family sharing restricted!" )
            end
        end)

        do
            local connect_times = {}
            hook.Add("CheckPassword", addon_name, function( sid64 )
                if (connect_times[ sid64 ] ~= nil) and (connect_times[ sid64 ] > SysTime()) then
                    return false, "Too fast. Please be slowly :)"
                end

                connect_times[ sid64 ] = SysTime() + 5

                for num, ply in ipairs( player.GetHumans() ) do
                    if (ply:SteamID64() == sid64) then
                        return false, "Player with your steamid already on server!"
                    end
                end
            end)
        end

    end

end

MsgC( "\n[" .. addon_name .." v" .. version .. "] ", HSVToColor( math.random( 360 ) % 360, 0.9, 0.8 ), "Game Patched!\n" )
