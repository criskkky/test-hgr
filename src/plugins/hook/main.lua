---@class PlayerGrappleState
---@field IsPlayerGrappling boolean
---@field GrappleWire CBeam|nil
---@field NewVelocity Vector
---@field StaticVelocity Vector

local PlayerGrappleState = {}
PlayerGrappleState.__index = PlayerGrappleState

function PlayerGrappleState:new()
    local obj = setmetatable({}, PlayerGrappleState)
    obj.IsPlayerGrappling = false
    obj.IsGrappleEnabled = false
    obj.GrappleWire = nil
    obj.NewVelocity = Vector(0, 0, 0)
    obj.StaticVelocity = Vector(0, 0, 0)
    return obj
end

local playerStates = {}
local connectedPlayers = {}
local activeGrapplers = {}
local roundEnd = false
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

-- Cleanup player state and references
local function CleanupPlayer(player)
    if not player or not player:IsValid() then return end
    DespawnGrappleWire(player)
    local slot = player:GetSlot()
    playerStates[slot] = nil
    connectedPlayers[slot] = nil
    activeGrapplers[slot] = nil
end

local function InitPlayer(player)
    if not player or not player:IsValid() or player:IsFakeClient() then return end
    connectedPlayers[player:GetSlot()] = player
    playerStates[player:GetSlot()] = PlayerGrappleState:new()
    -- print("Player added: " .. player:CBasePlayerController().PlayerName)
end

-- Start Hook
commands:Register("hook1", function(playerId)
    local player = GetPlayer(playerId)
    if not player or not player:IsValid() then return end
    local state = playerStates[player:GetSlot()]
    if state and state.IsGrappleEnabled and not state.IsPlayerGrappling then
        state.IsPlayerGrappling = true
        activeGrapplers[player:GetSlot()] = true
        -- Inicializar StaticVelocity aquí al comenzar el grapple
        local pawn = player:CCSPlayerPawn()
        local eyeAngles = nil
        if pawn and pawn.EyeAngles then
            eyeAngles = pawn.EyeAngles
        end
        local grappleSpeed = 800
        if eyeAngles then
            local pitch = math.rad(eyeAngles.x)
            local yaw = math.rad(eyeAngles.y)
            local dir = Vector(math.cos(yaw)*math.cos(pitch), math.sin(yaw)*math.cos(pitch), -math.sin(pitch))
            state.StaticVelocity = Vector(dir.x*grappleSpeed, dir.y*grappleSpeed, dir.z*grappleSpeed)
        else
            state.StaticVelocity = Vector(0,0,0)
        end
    end
end)

-- Stop Hook
commands:Register("hook0", function(playerId)
    local player = GetPlayer(playerId)
    if not player or not player:IsValid() then return end
    local state = playerStates[player:GetSlot()]
    if state and state.IsGrappleEnabled then
        state.IsPlayerGrappling = false
        activeGrapplers[player:GetSlot()] = nil
    end
end)

-- Toggle hook
commands:Register("enablehook", function(playerId)
    if roundEnd then return end
    local player = GetPlayer(playerId)
    if not player or not player:IsValid() then return end
    local state = playerStates[player:GetSlot()]
    if state and not state.IsGrappleEnabled then
        state.IsGrappleEnabled = true
        print(player:CBasePlayerController().PlayerName .. " has enabled hook")
    end
end)

commands:Register("disablehook", function(playerId)
    if roundEnd then return end
    local player = GetPlayer(playerId)
    if not player or not player:IsValid() then return end
    local state = playerStates[player:GetSlot()]
    if state and state.IsGrappleEnabled then
        state.IsGrappleEnabled = false
        state.IsPlayerGrappling = false
        activeGrapplers[player:GetSlot()] = nil
        DespawnGrappleWire(player)
        print(player:CBasePlayerController().PlayerName .. " has disabled hook")
    end
end)

-- Pull player towards target position
local function PullPlayer(player, targetPos, playerPos, dirVector)
    if not player or not player:IsValid() then return end
    local pawn = player:CCSPlayerPawn()
    if not pawn or not pawn:IsValid() then return end

    local state = playerStates[player:GetSlot()]
    if not state then return end

    local baseEnt = player:CBaseEntity()
    if baseEnt and baseEnt.AbsVelocity then
        baseEnt.AbsVelocity.x = state.StaticVelocity.x
        baseEnt.AbsVelocity.y = state.StaticVelocity.y
        baseEnt.AbsVelocity.z = state.StaticVelocity.z
        player:CBaseEntity().AbsVelocity = state.StaticVelocity -- needed to update the velocity
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
    -- Procesar solo jugadores actualmente grappling
    local hasAny = false
    for slot, _ in pairs(activeGrapplers) do
        hasAny = true
        break
    end
    if not hasAny then return EventResult.Continue end

    for slot, _ in pairs(activeGrapplers) do
        local player = GetPlayer(slot)
        if not player or not player:IsValid() then
            activeGrapplers[slot] = nil
            goto continue
        end

        local state = playerStates[slot]
        if not state or not state.IsGrappleEnabled or not state.IsPlayerGrappling then
            activeGrapplers[slot] = nil
            goto continue
        end

        local pawn = player:CCSPlayerPawn()
        if not pawn or not pawn:IsValid() then
            activeGrapplers[slot] = nil
            goto continue
        end

        -- Despawn wire if se dejó de grapplar (seguridad)
        if not state.IsPlayerGrappling and state.GrappleWire then
            DespawnGrappleWire(player)
            activeGrapplers[slot] = nil
            goto continue
        end

        local baseEnt = player:CBaseEntity()
        if baseEnt and baseEnt:IsValid() and baseEnt.CBodyComponent and baseEnt.CBodyComponent.SceneNode and baseEnt.CBodyComponent.SceneNode.AbsOrigin then
            local absOrigin = baseEnt.CBodyComponent.SceneNode.AbsOrigin
            local eyePos = absOrigin + Vector(0,0,61)
            local endPos = eyePos + Vector(state.StaticVelocity.x*3, state.StaticVelocity.y*3, state.StaticVelocity.z*3)

            if not state.GrappleWire then
                local beam = CBeam(CreateEntityByName("beam"):ToPtr())
                if beam and beam:IsValid() then
                    local cbe = CBaseEntity(beam:ToPtr())
                    cbe:Spawn()
                    cbe:Teleport(eyePos, QAngle(0,0,0), Vector(0,0,0))
                    local colorObj = Color(0, 0, 255, 255) -- azul
                    beam.Parent.Render = colorObj
                    beam.Width = 4
                    state.GrappleWire = beam
                end
            end
            PullPlayer(player, endPos, absOrigin, state.StaticVelocity)
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
    -- Delete player states y despawn beams de PlayerGrappleState
    for i, player in pairs(connectedPlayers) do
        CleanupPlayer(player)
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
    CleanupPlayer(player)
    return EventResult.Continue
end)

-- Handle round states
AddEventHandler("OnRoundStart", function(event)
    roundEnd = false
    return EventResult.Continue
end)

AddEventHandler("OnRoundEnd", function(event)
    roundEnd = true
    for _, player in pairs(connectedPlayers) do
        local state = playerStates[player:GetSlot()]
        if state then
            state.IsPlayerGrappling = false
        end
        DespawnGrappleWire(player)
        activeGrapplers[player:GetSlot()] = nil
    end
    return EventResult.Continue
end)

-- Handle player death
AddEventHandler("OnPlayerDeath", function(event)
    local player = GetPlayer(event:GetInt("userid"))
    if player and player:IsValid() then
        DespawnGrappleWire(player)
        local slot = player:GetSlot()
        local state = playerStates[slot]
        if state then
            state.IsPlayerGrappling = false
        end
        activeGrapplers[slot] = nil
    end
    return EventResult.Continue
end)

print(prefix .. "Plugin loaded")
