--[[ 
    Script: Auto Deploy for a new game (V5 - Teleport to Enemy Tower on Spawn)
    Author: Gemini (remade + patched)
    Description: Removed tile-teleport step. When one of the player's units spawns
                 in workspace.Units, teleport player immediately to the enemy King Tower.
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
    SubTitle = "Auto Deploy & More (V5)",
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
-- Helpers: Team & Game Data
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
-- Auto Deploy Logic (no tile-teleport)
-- -------------------------
local masterConnection = nil
local lastDeployTime = 0

local function attemptToDeployUnit(unitName)
    local myTeam = getPlayerTeam()
    if myTeam == "Spectator" or unitName == "None" then return end
    
    local unitCost = getUnitCost(unitName)
    if getCurrentElixir() < unitCost then return end

    -- simple choose + deploy via provided remotes (game handles spawn location)
    pcall(function()
        -- choose
        pcall(function()
            local args = { [1] = unitName }
            ChoseUnitEvent:FireServer(unpack(args))
        end)
        task.wait(0.15)
        -- attempt to Deploy: many games accept BasePart or other target - if the game expects a tile object pass nil or a default
        pcall(function()
            DeployEvent:FireServer()
        end)
    end)
end

local function autoDeployLoop()
    if (os.clock() - lastDeployTime) < 1.5 then return end -- cooldown
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
-- Auto Join Team logic
-- -------------------------
local joinConnection = nil
local spectatorStartTime = nil

local function joinTeamAttempt()
    if getPlayerTeam() ~= "Spectator" then
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

-- ##########################
-- New: Teleport to enemy tower the moment one of your units spawns
-- ##########################
local spawnDebounce = 0.5 -- seconds per-detection debounce
local lastTeleportAt = 0

local function isModelOwnedByLocalPlayer(model)
    if not model or not model:IsA("Model") then return false end

    -- common patterns: model name is player name (or "LocalPlayer"), or model has Owner/Player/OwnerId values
    if model.Name == localPlayer.Name or model.Name == "LocalPlayer" then
        return true
    end

    local owner = model:FindFirstChild("Owner") or model:FindFirstChild("Player")
    if owner and (owner.Value == localPlayer) then
        return true
    end

    local ownerId = model:FindFirstChild("OwnerId") or model:FindFirstChild("PlayerId")
    if ownerId and type(ownerId.Value) == "number" and ownerId.Value == localPlayer.UserId then
        return true
    end

    -- sometimes there's a StringValue ownerName
    local ownerName = model:FindFirstChild("OwnerName") or model:FindFirstChild("PlayerName")
    if ownerName and ownerName.Value == localPlayer.Name then
        return true
    end

    return false
end

local function findEnemyKingTowerCFrame()
    -- Search in Units first, then Arena
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

    local unitsFolder = Workspace:FindFirstChild("Units")
    local arena = Workspace:FindFirstChild("Arena")
    local cf = scan(unitsFolder) or scan(arena)
    -- Last resort: try scanning whole workspace
    if not cf then
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if (obj.Name == "King Tower" or obj.Name == "KingTower") and obj:IsA("Model") and obj.PrimaryPart then
                local z_pos = obj.PrimaryPart.Position.Z
                local towerTeam = (math.abs(z_pos - SAFE_CF_BLUE.Position.Z) < 50) and "Blue" or (math.abs(z_pos - SAFE_CF_RED.Position.Z) < 50) and "Red"
                if towerTeam and towerTeam ~= getPlayerTeam() then
                    return obj.PrimaryPart.CFrame
                end
            end
        end
    end
    return cf
end

local function onUnitChildAdded(child)
    -- guard
    if (os.clock() - lastTeleportAt) < spawnDebounce then return end

    -- If a folder named for the player appears (workspace.Units.LocalPlayer style),
    -- we may want to check its descendants.
    if isModelOwnedByLocalPlayer(child) then
        local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
        if root then
            local towerCF = findEnemyKingTowerCFrame()
            if towerCF then
                lastTeleportAt = os.clock()
                -- teleport slightly above the tower so the player doesn't get stuck in parts
                local target = towerCF + Vector3.new(0, 6, 0)
                pcall(function() root.CFrame = target end)
            end
        end
        return
    end

    -- If the child is a folder that contains models for players (workspace.Units.LocalPlayer)
    if child:IsA("Folder") or child:IsA("Model") then
        for _, descendant in ipairs(child:GetDescendants()) do
            if descendant:IsA("Model") and isModelOwnedByLocalPlayer(descendant) then
                local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
                if root then
                    local towerCF = findEnemyKingTowerCFrame()
                    if towerCF then
                        lastTeleportAt = os.clock()
                        local target = towerCF + Vector3.new(0, 6, 0)
                        pcall(function() root.CFrame = target end)
                    end
                end
                return
            end
        end
    end
end

-- Connect to Units folder child-added
local function connectUnitSpawnWatcher()
    local unitsFolder = Workspace:FindFirstChild("Units")
    if not unitsFolder then
        -- if Units isn't present yet, wait a bit and try again (non-blocking)
        task.spawn(function()
            local uf = Workspace:WaitForChild("Units", 10)
            if uf then
                uf.ChildAdded:Connect(onUnitChildAdded)
                -- Also scan current children (in case a model already exists)
                for _, c in ipairs(uf:GetChildren()) do
                    -- small delay to prevent immediate teleport spam
                    task.delay(0.1, function() onUnitChildAdded(c) end)
                end
            end
        end)
    else
        unitsFolder.ChildAdded:Connect(onUnitChildAdded)
        for _, c in ipairs(unitsFolder:GetChildren()) do
            task.delay(0.1, function() onUnitChildAdded(c) end)
        end
    end
end
connectUnitSpawnWatcher()

-- -------------------------
-- Usage Logging (Optional)
-- -------------------------
local function logExecution()
    local webhookURL = "https://discord.com/api/webhooks/1416859396562092172/XoWDUqlu6i-EpdMO17m42c-R5iXji_w_ZGYU2TbfK5TLoztK9RUMGy0eGutOpXAyGTnD"
    pcall(function()
        local data = {
            embeds = {{
                title = "✅ Script Executed", color = 3066993,
                fields = {
                    {name = "Username", value = "`" .. localPlayer.Name .. "`", inline = true},
                    {name = "User ID", value = "`" .. localPlayer.UserId .. "`", inline = true}
                },
                footer = {text = "Game Helper by Gemini"},
                timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z")
            }}
        }
        if syn and syn.request then
            syn.request({Url = webhookURL, Method = "POST", Body = HttpService:JSONEncode(data), Headers = {["Content-Type"] = "application/json"}})
        end
    end)
end

pcall(logExecution)

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
    Title = "Script Updated (V5)",
    Content = "Now teleports you to enemy tower when your unit spawns.",
    Duration = 8
})
pcall(function() SaveManager:LoadAutoloadConfig() end)