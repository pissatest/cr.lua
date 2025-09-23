-- Simple Auto-Deploy for "Pekka"
-- This script will automatically deploy and equip the Pekka unit when you have no tool.
-- It does not include auto-attack or any UI.

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local localPlayer = Players.LocalPlayer

-- Configuration
local DEPLOY_CF_FOR_RED_PLAYER  = CFrame.new(-3, 26, -164)
local DEPLOY_CF_FOR_BLUE_PLAYER = CFrame.new(-2, 24, 110)
local DEPLOY_REMOTE_NAME = "Deploy"
local UNIT_TO_DEPLOY = "Pekka"

-- Game Info Cache
local InfoModule = nil
local function getInfoModule()
    if not InfoModule then
        pcall(function()
            InfoModule = require(ReplicatedStorage:WaitForChild("Info"))
        end)
    end
    return InfoModule
end
getInfoModule()

-- Helper Functions
local function getPlayerTeam()
    if localPlayer and localPlayer:FindFirstChild("Stats") then
        local st = localPlayer.Stats:FindFirstChild("Team")
        if st and typeof(st.Value) == "string" and st.Value ~= "" then
            return st.Value
        end
    end
    if localPlayer and localPlayer.Team and localPlayer.Team.Name then
        return localPlayer.Team.Name
    end
    return "Spectator"
end

local function hasAnyTool()
    if not localPlayer or not localPlayer.Character or not localPlayer:FindFirstChild("Backpack") then return false end
    if localPlayer.Character:FindFirstChildOfClass("Tool") then return true end
    if localPlayer.Backpack:FindFirstChildOfClass("Tool") then return true end
    return false
end

local function getUnitCost(unitName)
    local info = getInfoModule()
    if info and info[unitName] and info[unitName].Elixir then
        return tonumber(info[unitName].Elixir)
    end
    return nil
end

local function getCurrentElixir()
    local myTeam = getPlayerTeam()
    local elixirValue = 0
    if myTeam == "Blue" then
        local elixirB = ReplicatedStorage.Game:FindFirstChild("ElixirB")
        if elixirB then elixirValue = elixirB.Value end
    elseif myTeam == "Red" then
        local elixirR = ReplicatedStorage.Game:FindFirstChild("ElixirR")
        if elixirR then elixirValue = elixirR.Value end
    end
    return elixirValue
end

-- Core Deploy Logic
local isAttemptingDeploy = false

local function attemptToDeployUnit(unitNameToDeploy)
    if isAttemptingDeploy then return end
    isAttemptingDeploy = true
    
    pcall(function()
        local character = localPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not (humanoid and humanoid.Health > 0) or hasAnyTool() then
            return
        end

        local unitCost = getUnitCost(unitNameToDeploy)
        if not unitCost or getCurrentElixir() < unitCost then
            return
        end

        local myTeam = getPlayerTeam()
        local targetCF = (myTeam == "Red" and DEPLOY_CF_FOR_RED_PLAYER) or (myTeam == "Blue" and DEPLOY_CF_FOR_BLUE_PLAYER)
        local deployRemote = ReplicatedStorage:FindFirstChild(DEPLOY_REMOTE_NAME)
        local root = character and character:FindFirstChild("HumanoidRootPart")
        
        if myTeam == "Spectator" or not targetCF or not deployRemote or not root then
            return
        end

        pcall(deployRemote.InvokeServer, deployRemote, "RequestDeploy", unitNameToDeploy)
        task.wait(0.25)
        root.CFrame = targetCF
        task.wait(0.5)

        local attemptCount = 0
        while not hasAnyTool() and attemptCount < 5 do
            local currentHum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
            if not (currentHum and currentHum.Health > 0) then break end
            
            pcall(deployRemote.InvokeServer, deployRemote, "Deploy", unitNameToDeploy, targetCF)
            attemptCount += 1
            task.wait(0.6)
        end

        if not hasAnyTool() then
             if humanoid then humanoid.Health = 0 end -- Respawn to retry
        end
    end)
    isAttemptingDeploy = false
end

-- Main Loop
RunService.Heartbeat:Connect(function()
    pcall(function()
        local character = localPlayer.Character
        if not character then return end
        
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not (humanoid and humanoid.Health > 0) then return end

        local backpack = localPlayer:FindFirstChild("Backpack")
        local equippedTool = character:FindFirstChildOfClass("Tool")
        local toolInBackpack = backpack and backpack:FindFirstChildOfClass("Tool")

        if equippedTool then
            -- Tool is equipped, do nothing.
            return
        elseif toolInBackpack then
            -- Tool is in backpack, equip it.
            humanoid:EquipTool(toolInBackpack)
        else
            -- No tool found, attempt to deploy.
            attemptToDeployUnit(UNIT_TO_DEPLOY)
        end
    end)
end)
