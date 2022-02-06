function math.Clamp(inval, minval, maxval)
	if (inval < minval) then return minval end
	if (inval > maxval) then return maxval end
	return inval
end

do

    local math_random = math.random
    local table_GetKeys = table.GetKeys
    function table.Random( tab, issequential )
        local keys = issequential and tab or table_GetKeys(tab)
        local rand = keys[math_random(1, #keys)]
        return tab[rand], rand
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

    if util.NetworkStringToID("LocalVoiceVolume.Relay") ~= 0 then return end

    local plyBits = math_ceil(math_log(game.MaxPlayers(), 2))
    local voiceVolumeBits = math_ceil(math_log(100, 2))
    local voiceVolumePoll = math_max(0.25, engine.TickInterval())

    local PLAYER = FindMetaTable("Player")
    local ENTITY = FindMetaTable("Entity")

    local PLAYER_IsSpeaking = PLAYER.IsSpeaking
    local PLAYER_VoiceVolume = PLAYER.VoiceVolume
    local ENTITY_IsValid = ENTITY.IsValid
    local ENTITY_EntIndex = ENTITY.EntIndex

    local hook_Add = hook.Add

    if SERVER then
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

        return
    end

    LVV_VANILLA_VOICE_VOLUME = LVV_VANILLA_VOICE_VOLUME or PLAYER.VoiceVolume
    local LVV_VANILLA_VOICE_VOLUME = LVV_VANILLA_VOICE_VOLUME

    local timer_Create = timer.Create
    local LocalPlayer = LocalPlayer
    local GetConVar = GetConVar
    local IsValid = IsValid

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

MsgN( "Random Patches - Game Patched!" )