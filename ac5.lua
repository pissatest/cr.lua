--[[ 
    Script: Auto Deploy for a new game (V6 - Clean Split: Join Team vs Teleport on Deploy)
    Author: Gemini (remade + patched)
    Description: 
        - Auto Join Team: joins team only when Spectator.
        - Auto Deploy: deploys unit + optional teleport to enemy tower on unit spawn.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = workspace
local HttpService = game:GetService("HttpService")
local Teams = game:GetService("Teams")
local localPlayer = Players.LocalPlayer

-- Load Fluent + Addons
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- Create window
local Window = Fluent:CreateWindow({
    Title = "Game Helper by Gemini",
    SubTitle = "Auto Deploy & More (V6)",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 480),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl
})

-- Tabs
local Tabs = {
    AutoDeploy = Window:AddTab({ Title = "Auto Deploy", Icon = "package" }),
    Settings   = Window:AddTab({ Title = "Settings",    Icon = "settings" })
}
local Options = Fluent.Options

-- -------------------------
-- Configuration
-- -------------------------
local SAFE_CF_BLUE = CFrame.new(-64, 19, 400)
local SAFE_CF_RED  = CFrame.new(-64, 19, 600)

-- Remote Event paths
local EventsFolder = ReplicatedStorage:WaitForChild("Events")
local SetTeamEvent = EventsFolder:WaitForChild("SetTeam")
local ChoseUnitEvent = EventsFolder:WaitForChild("ChoseUnit")
local DeployEvent = EventsFolder:WaitForChild("Deploy")

-- -------------------------
-- Game Info Cache
-- -------------------------
local UnitStatsModule = nil
local function getUnitStatsModule()
    if not UnitStatsModule then
        pcall(function()
            UnitStatsModule = require(ReplicatedStorage.Modules.UnitStats)
        end)
    end
    return UnitStatsModule
end
getUnitStatsModule()

-- -------------------------
-- Helpers
-- -------------------------
local function getPlayerTeam()
    return localPlayer.Team and localPlayer.Team.Name or "Spectator"
end

local function getTeamWithLeastPlayers()
    local blueCount, redCount = #Teams.Blue:GetPlayers(), #Teams.Red:GetPlayers()
    return (blueCount <= redCount) and "Blue" or "Red"
end

local function getUnitCost(unitName)
    local stats = getUnitStatsModule()
    if stats and stats[unitName] and stats[unitName].Elixir then
        return tonumber(stats[unitName].Elixir)
    end
    return 99
end

local function getCurrentElixir()
    local myTeam = getPlayerTeam()
    if myTeam == "Spectator" then return 0 end
    
    local gameStatus = ReplicatedStorage:FindFirstChild("GameStatus")
    if gameStatus then
        local elixirValueObj = gameStatus:FindFirstChild(myTeam .. "Elixir")
        if elixirValueObj then
            return elixirValueObj.Value
        end
    end
    return 0
end

-- -------------------------
-- UI Elements
-- -------------------------
Tabs.AutoDeploy:AddParagraph({ Title = "Unit Deployment", Content = "Select a unit and enable the toggle. The script will automatically deploy it when you have enough elixir." })
local unitDropdown = Tabs.AutoDeploy:AddDropdown("UnitToSpawn", { Title = "Unit to Spawn", Values = {"None"}, Default = "None" })
local autoDeployToggle = Tabs.AutoDeploy:AddToggle("AutoDeployEnabled", { Title = "Enable Auto Deploy", Default = false })
local teleportToggle = Tabs.AutoDeploy:AddToggle("TeleportOnSpawn", { Title = "Teleport to Enemy Tower on Spawn", Default = true })

Tabs.AutoDeploy:AddParagraph({ Title = "Team Controls", Content = "Automatically join a team when you are a Spectator." })
local teamDropdown = Tabs.AutoDeploy:AddDropdown("TeamToJoin", { Title = "Team to Join", Values = {"Auto (Least Players)", "Blue", "Red"}, Default = "Auto (Least Players)" })
local autoJoinToggle = Tabs.AutoDeploy:AddToggle("AutoJoinTeam", { Title = "Auto Join Team", Default = false })
local joinDelayInput = Tabs.AutoDeploy:AddInput("JoinTeamDelay", { Title = "Join Delay (seconds)", Default = 0, Numeric = true, MaxLength = 2, Min = 0, Max = 60 })

Tabs.AutoDeploy:AddParagraph({ Title = "Safe Mode", Content = "When enabled, you'll be teleported to a safe spot if the enemy King Tower is destroyed." })
local safeModeToggle = Tabs.AutoDeploy:AddToggle("SafeMode", { Title = "Enable Safe Mode", Default = false })

Tabs.Settings:AddButton({
    Title = "Join Discord Server",
    Description = "Click for support and updates (Example Link)",
    Callback = function()
        if syn and syn.request then syn.request({Url = "https://discord.com/", Method = "GET"}) end
    end
})

-- -------------------------
-- Populate Unit list
-- -------------------------
local function rebuildUnitDropdown()
    local trophies = 0
    local ls = localPlayer:FindFirstChild("leaderstats") and localPlayer.leaderstats:FindFirstChild("Trophies")
    if ls then trophies = ls.Value end

    local stats = getUnitStatsModule()
    local availableUnits = {"None"}
    
    if stats then
        for name, data in pairs(stats) do
            if type(data) == "table" and (data.Trophy == nil or trophies >= data.Trophy) then
                table.insert(availableUnits, name)
            end
        end
        table.sort(availableUnits)
    end
    
    if #availableUnits == 1 then
        availableUnits = {"None", "Bandit", "Berserker"}
    end
    
    unitDropdown:SetValues(availableUnits)
    
    if not table.find(availableUnits, unitDropdown.Value) then
        unitDropdown:SetValue(availableUnits[2] or "None")
    end
end

if localPlayer:FindFirstChild("leaderstats") and localPlayer.leaderstats:FindFirstChild("Trophies") then
    localPlayer.leaderstats.Trophies:GetPropertyChangedSignal("Value"):Connect(rebuildUnitDropdown)
end
rebuildUnitDropdown()

-- -------------------------
-- Noclip for King Towers
-- -------------------------
RunService.Heartbeat:Connect(function()
    local unitsFolder = Workspace:FindFirstChild("Units")
    if not unitsFolder then return end

    for _, model in ipairs(unitsFolder:GetChildren()) do
        if (model.Name == "King Tower" or model.Name == "KingTower") and model:IsA("Model") then
            for _, part in ipairs(model:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end
    end
end)

-- -------------------------
-- Auto Deploy Logic
-- -------------------------
local masterConnection = nil
local lastDeployTime = 0

local function attemptToDeployUnit(unitName)
    local myTeam = getPlayerTeam()
    if myTeam == "Spectator" or unitName == "None" then return end
    
    local unitCost = getUnitCost(unitName)
    if getCurrentElixir() < unitCost then return end

    pcall(function()
        ChoseUnitEvent:FireServer(unitName)
        task.wait(0.15)
        DeployEvent:FireServer()
    end)
end

local function autoDeployLoop()
    if (os.clock() - lastDeployTime) < 1.5 then return end
    local unitToDeploy = Options.UnitToSpawn.Value
    if unitToDeploy ~= "None" then
        attemptToDeployUnit(unitToDeploy)
        lastDeployTime = os.clock()
    end
end

autoDeployToggle:OnChanged(function(enabled)
    if enabled then
        if not masterConnection then
            masterConnection = RunService.Heartbeat:Connect(autoDeployLoop)
        end
    else
        if masterConnection then
            masterConnection:Disconnect()
            masterConnection = nil
        end
    end
end)

-- -------------------------
-- Auto Join Team (fixed)
-- -------------------------
local joinConnection = nil
local spectatorStartTime = nil

local function joinTeamAttempt()
    local team = getPlayerTeam()
    if team == "Blue" or team == "Red" then
        spectatorStartTime = nil
        return
    end

    if not spectatorStartTime then spectatorStartTime = os.clock() end

    local delay = tonumber(Options.JoinTeamDelay.Value) or 0
    if (os.clock() - spectatorStartTime) >= delay then
        local teamChoiceName = Options.TeamToJoin.Value
        if teamChoiceName == "Auto (Least Players)" then
            teamChoiceName = getTeamWithLeastPlayers()
        end
        
        local teamObject = Teams:FindFirstChild(teamChoiceName)
        if teamObject then
            SetTeamEvent:FireServer(teamObject)
        end
        spectatorStartTime = os.clock()
    end
end

autoJoinToggle:OnChanged(function(enabled)
    if enabled and not joinConnection then
        joinConnection = RunService.Stepped:Connect(joinTeamAttempt)
    elseif not enabled and joinConnection then
        joinConnection:Disconnect()
        joinConnection = nil
        spectatorStartTime = nil
    end
end)

-- -------------------------
-- Safe Mode
-- -------------------------
local safeConnection = nil
local hasBeenTeleported = false

local function safeModeCheck()
    local myTeam = getPlayerTeam()
    if myTeam == "Spectator" then return end

    local unitsFolder = Workspace:FindFirstChild("Units")
    if not unitsFolder then return end
    
    local myTowerFound = false
    local enemyTowerFound = false

    for _, model in ipairs(unitsFolder:GetChildren()) do
        if (model.Name == "King Tower" or model.Name == "KingTower") and model.PrimaryPart then
            local z_pos = model.PrimaryPart.Position.Z
            local towerTeam = (math.abs(z_pos - SAFE_CF_BLUE.Position.Z) < 20) and "Blue" or (math.abs(z_pos - SAFE_CF_RED.Position.Z) < 20) and "Red"
            if towerTeam == myTeam then
                myTowerFound = true
            else
                enemyTowerFound = true
            end
        end
    end

    if myTowerFound and not enemyTowerFound then
        if not hasBeenTeleported then
            local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
            if root then
                local safeCFrame = (myTeam == "Red") and SAFE_CF_RED or SAFE_CF_BLUE
                root.CFrame = safeCFrame
            end
            hasBeenTeleported = true
        end
    elseif myTowerFound and enemyTowerFound then
        hasBeenTeleported = false
    end
end

safeModeToggle:OnChanged(function(enabled)
    if enabled and not safeConnection then
        safeConnection = RunService.Heartbeat:Connect(safeModeCheck)
    elseif not enabled and safeConnection then
        safeConnection:Disconnect()
        safeConnection = nil
    end
end)

-- -------------------------
-- Teleport to Enemy Tower on Unit Spawn (optional)
-- -------------------------
local spawnDebounce = 0.5
local lastTeleportAt = 0
local spawnConnection = nil

local function isModelOwnedByLocalPlayer(model)
    if not model or not model:IsA("Model") then return false end
    if model.Name == localPlayer.Name or model.Name == "LocalPlayer" then return true end

    local owner = model:FindFirstChild("Owner") or model:FindFirstChild("Player")
    if owner and owner.Value == localPlayer then return true end

    local ownerId = model:FindFirstChild("OwnerId") or model:FindFirstChild("PlayerId")
    if ownerId and ownerId.Value == localPlayer.UserId then return true end

    local ownerName = model:FindFirstChild("OwnerName") or model:FindFirstChild("PlayerName")
    if ownerName and ownerName.Value == localPlayer.Name then return true end

    return false
end

local function findEnemyKingTowerCFrame()
    local function scan(container)
        if not container then return nil end
        for _, v in ipairs(container:GetChildren()) do
            if (v.Name == "King Tower" or v.Name == "KingTower") and v:IsA("Model") and v.PrimaryPart then
                local z_pos = v.PrimaryPart.Position.Z
                local towerTeam = (math.abs(z_pos - SAFE_CF_BLUE.Position.Z) < 50) and "Blue" or (math.abs(z_pos - SAFE_CF_RED.Position.Z) < 50) and "Red"
                if towerTeam and towerTeam ~= getPlayerTeam() then
                    return v.PrimaryPart.CFrame
                end
            end
        end
        return nil
    end

    return scan(Workspace:FindFirstChild("Units")) or scan(Workspace:FindFirstChild("Arena"))
end

local function teleportToEnemyTower()
    if not Options.TeleportOnSpawn.Value then return end
    local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local towerCF = findEnemyKingTowerCFrame()
    if towerCF then
        lastTeleportAt = os.clock()
        local target = towerCF + Vector3.new(0, 6, 0)
        pcall(function() root.CFrame = target end)
    end
end

local function onUnitChildAdded(child)
    if (os.clock() - lastTeleportAt) < spawnDebounce then return end
    if isModelOwnedByLocalPlayer(child) then
        teleportToEnemyTower()
    else
        for _, d in ipairs(child:GetDescendants()) do
            if d:IsA("Model") and isModelOwnedByLocalPlayer(d) then
                teleportToEnemyTower()
                break
            end
        end
    end
end

autoDeployToggle:OnChanged(function(enabled)
    if enabled and not spawnConnection then
        local unitsFolder = Workspace:WaitForChild("Units", 10)
        if unitsFolder then
            spawnConnection = unitsFolder.ChildAdded:Connect(onUnitChildAdded)
        end
    elseif not enabled and spawnConnection then
        spawnConnection:Disconnect()
        spawnConnection = nil
    end
end)

-- -------------------------
-- Final Setup
-- -------------------------
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
InterfaceManager:SetFolder("FluentScriptHub")
SaveManager:SetFolder("FluentScriptHub/NewGame")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)
Fluent:Notify({
    Title = "Script Updated (V6)",
    Content = "Auto Join Team & Auto Deploy are now separate. Teleport toggle added.",
    Duration = 8
})
pcall(function() SaveManager:LoadAutoloadConfig() end)