---@class PlayerGrappleInfo
---@field IsPlayerGrappling boolean
---@field GrappleBeamSpawned boolean
---@field GrappleBeamActive boolean
---@field GrappleWire CBeam|nil
---@field NewVelocity Vector
---@field StaticVelocity Vector

local PlayerGrappleInfo = {}
PlayerGrappleInfo.__index = PlayerGrappleInfo

function PlayerGrappleInfo:new()
    local self = setmetatable({}, PlayerGrappleInfo)
    self.IsPlayerGrappling = false
    self.GrappleBeamSpawned = false
    self.GrappleBeamActive = false
    self.GrappleWire = nil
    self.NewVelocity = Vector(0, 0, 0)
    self.StaticVelocity = Vector(0, 0, 0)
    return self
end

local playerStates = {}
local connectedPlayers = {}
local use_key = {}
local GrappleBeamEnabled = false
local RoundEnd = false
local prefix = "[HOOK] "

-- Initialize player state

local function DespawnGrappleWire(player)
    local state = playerStates[player:GetSlot()]
    if state and state.GrappleWire then
        local cbe = CBaseEntity(state.GrappleWire:ToPtr())
        if cbe and cbe:IsValid() then
            cbe:Despawn()
        end
        state.GrappleWire = nil
    end
end

local function InitPlayer(player)
    if not player or not player:IsValid() or player:IsFakeClient() then return end
    connectedPlayers[player:GetSlot()] = player
    playerStates[player:GetSlot()] = PlayerGrappleInfo:new()
    -- print("Player added: " .. player:CBasePlayerController().PlayerName)
end

-- Start Hook
commands:Register("hook1", function(playerId)
    local player = GetPlayer(playerId)
    if not player or not player:IsValid() then return end
    if GrappleBeamEnabled then
        use_key[player:GetSlot()] = true
    end
end)

-- Stop Hook
commands:Register("hook0", function(playerId)
    local player = GetPlayer(playerId)
    if not player or not player:IsValid() then return end
    if GrappleBeamEnabled then
        use_key[player:GetSlot()] = false
    end
end)

-- Toggle hook
commands:Register("enablehook", function(playerId)
    if RoundEnd then return end
    local player = GetPlayer(playerId)
    if not player or not player:IsValid() then return end
    if not GrappleBeamEnabled then
        GrappleBeamEnabled = true
        print(player:CBasePlayerController().PlayerName .. " enabled hook")
    end
end)

commands:Register("disablehook", function(playerId)
    if RoundEnd then return end
    local player = GetPlayer(playerId)
    if not player or not player:IsValid() then return end
    if GrappleBeamEnabled then
        GrappleBeamEnabled = false
        for _, p in pairs(connectedPlayers) do
            local state = playerStates[p:GetSlot()]
            if state and state.GrappleWire then
                local cbe = CBaseEntity(state.GrappleWire:ToPtr())
                if cbe and cbe:IsValid() then
                    cbe:Despawn()
                end
                state.GrappleWire = nil
            end
        end
        print(player:CBasePlayerController().PlayerName .. " disabled hook")
    end
end)

-- Pull player towards target position
local function PullPlayer(player, targetPos, playerPos, dirVector)
    if not player or not player:IsValid() then return end
    local pawn = player:CCSPlayerPawn()
    if not pawn or not pawn:IsValid() then return end

    local state = playerStates[player:GetSlot()]
    if not state then return end

    local absVel = player:CBaseEntity().AbsVelocity
    if absVel then
        absVel.x = state.staticVelocity.x
        absVel.y = state.staticVelocity.y
        absVel.z = state.staticVelocity.z
        player:CBaseEntity().AbsVelocity = absVel
    end

    if state.GrappleWire then
        local cbe = CBaseEntity(state.GrappleWire:ToPtr())
        if cbe and cbe:IsValid() then
            cbe:Teleport(playerPos, QAngle(0,0,0), Vector(0,0,0))
        end
    end
end

-- Tick handler
AddEventHandler("OnGameTick", function(event, simulating, firstTick, lastTick)
    for i = 1, playermanager:GetPlayerCount() do
        local player = GetPlayer(i-1)
        if not player or not player:IsValid() then goto continue end
        local playerId = player:GetSlot()
        local state = playerStates[playerId]
        local pawn = player:CCSPlayerPawn()
        local basePawn = player:CCSPlayerPawnBase()
    if not state or not pawn:IsValid() then goto continue end

        local key_old = state.IsPlayerGrappling
        state.IsPlayerGrappling = use_key[playerId] or false

        -- Despawn wire if not grappling
        if not state.IsPlayerGrappling and state.GrappleWire then
            DespawnGrappleWire(player)
        end

        -- Initialize Grappling
        if not key_old and state.IsPlayerGrappling then
            local grappleSpeed = 800
            local eyeAngles = nil
            if basePawn then
                if basePawn.EyeAngles then
                    eyeAngles = basePawn.EyeAngles
                end
            end

            if not eyeAngles and pawn then
                if pawn.EyeAngles then
                    eyeAngles = pawn.EyeAngles
                end
            end

            if eyeAngles then
                local pitch = math.rad(eyeAngles.x)
                local yaw = math.rad(eyeAngles.y)
                local dir = Vector(math.cos(yaw)*math.cos(pitch), math.sin(yaw)*math.cos(pitch), -math.sin(pitch))
                state.staticVelocity = Vector(dir.x*grappleSpeed, dir.y*grappleSpeed, dir.z*grappleSpeed)
            else
                state.staticVelocity = Vector(0,0,0)
            end
        end

        -- Beam
        if state.IsPlayerGrappling then
            local baseEnt = player:CBaseEntity()
            if baseEnt and baseEnt:IsValid() and baseEnt.CBodyComponent and baseEnt.CBodyComponent.SceneNode and baseEnt.CBodyComponent.SceneNode.AbsOrigin then
                local eyePos = baseEnt.CBodyComponent.SceneNode.AbsOrigin + Vector(0,0,61)
                local endPos = eyePos + Vector(state.staticVelocity.x*3, state.staticVelocity.y*3, state.staticVelocity.z*3)

                if not state.GrappleWire then
                    local beam = CBeam(CreateEntityByName("beam"):ToPtr())
                    if beam and beam:IsValid() then
                        local cbe = CBaseEntity(beam:ToPtr())
                        cbe:Spawn()
                        cbe:Teleport(eyePos, QAngle(0,0,0), Vector(0,0,0))

                        -- Initialize colorObj
                        local colorObj = Color(0, 0, 255, 255) -- blue
                        beam.Parent.Render = colorObj

                        beam.Width = 4
                        state.GrappleWire = beam
                    end
                end
                PullPlayer(player, endPos, baseEnt.CBodyComponent.SceneNode.AbsOrigin, state.staticVelocity)
            end
        end

        ::continue::
    end
    return EventResult.Continue
end)

AddEventHandler("OnPluginStart", function(event)
    -- Initialize connected players
    for i = 1, playermanager:GetPlayerCount() do
        InitPlayer(GetPlayer(i-1))
    end
end)

AddEventHandler("OnPluginStop", function(event)
    -- Delete player states and despawn beams of PlayerInfoGrappleInfo
    for i, player in pairs(connectedPlayers) do
        DespawnGrappleWire(player)
        playerStates[player:GetSlot()] = nil
        connectedPlayers[player:GetSlot()] = nil
    end
end)

-- Connection/disconnection events
AddEventHandler("OnPlayerConnectFull", function(event)
    local player = GetPlayer(event:GetInt("userid"))
    InitPlayer(player)
    return EventResult.Continue
end)

AddEventHandler("OnPlayerDisconnect", function(event)
    local player = GetPlayer(event:GetInt("userid"))
    if player and player:IsValid() then
        DespawnGrappleWire(player)
        playerStates[player:GetSlot()] = nil
        connectedPlayers[player:GetSlot()] = nil
    end
    return EventResult.Continue
end)

-- Handle round states
AddEventHandler("OnRoundStart", function(event)
    RoundEnd = false
    return EventResult.Continue
end)

AddEventHandler("OnRoundEnd", function(event)
    RoundEnd = true
    if GrappleBeamEnabled then
        GrappleBeamEnabled = false
        for _, player in pairs(connectedPlayers) do
            DespawnGrappleWire(player)
        end
    end
    return EventResult.Continue
end)

-- Handle player death
AddEventHandler("OnPlayerDeath", function(event)
    local player = GetPlayer(event:GetInt("userid"))
    if player and player:IsValid() then
        DespawnGrappleWire(player)
        local state = playerStates[player:GetSlot()]
        if state then
            state.IsPlayerGrappling = false
        end
    end
    return EventResult.Continue
end)

print(prefix .. "Plugin loaded")
