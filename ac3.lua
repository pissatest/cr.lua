--[[
    Script: Auto Deploy for a new game (V4 - Proximity Fix)
    Author: Gemini (remade based on user's script & feedback)
    Description: This version moves the player near the chosen tile before deploying
    to satisfy games that require player proximity for spawning units.
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
    SubTitle = "Auto Deploy & More",
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
        if model.Name == "King Tower" and model:IsA("Model") then
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

-- ###############################################################
-- ##            START OF NEW DEPLOYMENT LOGIC V4               ##
-- ###############################################################
local function attemptToDeployUnit(unitName)
    local myTeam = getPlayerTeam()
    if myTeam == "Spectator" or unitName == "None" then return end
    
    local unitCost = getUnitCost(unitName)
    if getCurrentElixir() < unitCost then return end
    
    local deployTile = nil
    
    local arena = Workspace:WaitForChild("Arena", 5)
    if not arena then return end

    local teamTilesFolder = arena:WaitForChild(myTeam .. "Tiles", 5)
    if not teamTilesFolder then return end

    for _, tile in ipairs(teamTilesFolder:GetChildren()) do
        if tile:IsA("BasePart") or (tile:IsA("Model") and tile.PrimaryPart) then
            deployTile = tile
            break 
        end
    end
    
    if not deployTile then return end

    -- ## NEW STEP: Teleport character to the tile before deploying ##
    local character = localPlayer.Character
    if character and character:FindFirstChild("HumanoidRootPart") and deployTile:IsA("BasePart") then
        local rootPart = character.HumanoidRootPart
        rootPart.CFrame = CFrame.new(deployTile.Position + Vector3.new(0, 4, 0))
        task.wait(0.1) -- Short delay for the character to settle
    end

    -- Fire the events to select the unit and then "click" the tile
    pcall(function()
        ChoseUnitEvent:FireServer(unitName)
        task.wait(0.2) -- A slightly longer delay can help prevent remote event issues
        DeployEvent:FireServer(deployTile)
    end)
end
-- ###############################################################
-- ##             END OF NEW DEPLOYMENT LOGIC V4                ##
-- ###############################################################

local function autoDeployLoop()
    if (os.clock() - lastDeployTime) < 1.5 then return end -- Increased cooldown slightly

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
        if model.Name == "King Tower" and model.PrimaryPart then
            local z_pos = model.PrimaryPart.Position.Z
            local towerTeam = (math.abs(z_pos - 400) < 10) and "Blue" or (math.abs(z_pos - 600) < 10) and "Red"

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
    Title = "Script Updated",
    Content = "Deployment logic now teleports you to the tile first.",
    Duration = 8
})
pcall(function() SaveManager:LoadAutoloadConfig() end)





Oh ignore the tile thing . The game will default to playing a unit in a corner so it isn’t a problem. However, it still needs to teleport to the enemy towers, so the second it spawns it should send the user to the tower 

We can check when the here is in the game via 

workspace.Units.LocalPlayer
Similar to the old script I sent 


local args = {
    [1] = "Hog Rider"
}

game:GetService("ReplicatedStorage").Events.ChoseUnit:FireServer(unpack(args))


Also trophies are found her so for the thing that only shoes units you unlock

game:GetService("Players").LocalPlayer.leaderstats.Trophies
