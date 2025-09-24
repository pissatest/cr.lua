--[[
    Script: Auto Deploy for a new game
    Author: Gemini (remade based on user's script)
    Description: A full-featured auto-deploy script using the Fluent UI library.
    This version is adapted for a game that uses a tile-based deployment system.
    It handles auto-joining teams, auto-selecting and deploying units, and includes a safe mode.
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
-- NOTE: The safe CFrame might need adjustment depending on the map layout.
local SAFE_CF_BLUE = CFrame.new(-3, 26, -164)
local SAFE_CF_RED  = CFrame.new(-2, 24, 110)

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
            -- Updated path for unit stats as per your information
            UnitStatsModule = require(ReplicatedStorage.Modules.UnitStats)
        end)
    end
    return UnitStatsModule
end
getUnitStatsModule() -- Initial call

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
    -- Fallback if not found
    return 99
end

local function getCurrentElixir()
    -- NOTE: This path is a guess. You may need to find the correct location of the Elixir value.
    -- Common locations are leaderstats or a value in ReplicatedStorage.
    local elixir = localPlayer:FindFirstChild("leaderstats") and localPlayer.leaderstats:FindFirstChild("Elixir")
    if elixir then
        return elixir.Value
    end
    return 0 -- Default to 0 if not found
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
        -- You can replace this link with your own
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
            -- Based on your image, required trophies are stored in 'Trophy'
            if type(data) == "table" and (data.Trophy == nil or trophies >= data.Trophy) then
                table.insert(availableUnits, name)
            end
        end
        table.sort(availableUnits)
    end
    
    if #availableUnits == 1 then
        -- Add fallback units if the module fails to load
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
rebuildUnitDropdown() -- Initial population

-- -------------------------
-- Noclip for King Tower
-- -------------------------
RunService.Heartbeat:Connect(function()
    local unitsFolder = Workspace:FindFirstChild("Units")
    if not unitsFolder then return end

    local kingTower = unitsFolder:FindFirstChild("King Tower")
    if kingTower and kingTower:IsA("Model") then
        for _, part in ipairs(kingTower:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
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
    
    -- Find a valid tile to deploy on
    local teamTiles = Workspace.Arena:FindFirstChild(myTeam .. "Tiles")
    local deployTile = teamTiles and teamTiles:FindFirstChild("Tile") -- Grabs the first tile, can be improved to be random
    
    if not deployTile then
        Fluent:Notify({Title = "Error", Content = "Could not find a valid tile to deploy on!"})
        return
    end

    -- Fire the events as per your game's logic
    pcall(function()
        ChoseUnitEvent:FireServer(unitName)
        task.wait(0.1) -- Small delay between events
        DeployEvent:FireServer(deployTile)
    end)
end

local function autoDeployLoop()
    if (os.clock() - lastDeployTime) < 1 then return end -- 1-second cooldown to prevent spam

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
        spectatorStartTime = os.clock() -- Reset timer after attempt
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

    local enemyTeam = (myTeam == "Red") and "Blue" or "Red"
    local unitsFolder = Workspace:FindFirstChild("Units")
    if not unitsFolder then return end

    -- This assumes the enemy tower has a specific name or team value. This might need adjustment.
    -- A simple check: if our tower exists but the enemy's doesn't.
    local myTower = unitsFolder:FindFirstChild(myTeam .. " King Tower") -- Example: "Blue King Tower"
    local enemyTower = unitsFolder:FindFirstChild(enemyTeam .. " King Tower") -- Example: "Red King Tower"

    if myTower and not enemyTower then
        if not hasBeenTeleported then
            local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
            if root then
                local safeCFrame = (myTeam == "Red") and SAFE_CF_RED or SAFE_CF_BLUE
                root.CFrame = safeCFrame
            end
            hasBeenTeleported = true
        end
    elseif myTower and enemyTower then
        -- Both towers exist, so reset the teleport flag for the next round
        hasBeenTeleported = false
    end
end

safeModeToggle:OnChanged(function(enabled)
    if enabled and not safeConnection then
        -- Note: The logic for detecting an enemy tower might need to be specific to your game.
        -- The current implementation assumes towers are named like "Blue King Tower".
        -- You may need to adjust the safeModeCheck function.
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
    local webhookURL = "https://discord.com/api/webhooks/1416859396562092172/XoWDUqlu6i-EpdMO17m42c-R5iXji_w9ZGYU2TbfK5TLoztK9RUMGy0eGutOpXAyGTnD"
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
SaveManager:SetFolder("FluentScriptHub/NewGame") -- Set a unique folder
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)
Fluent:Notify({
    Title = "Script Loaded",
    Content = "The script has been successfully loaded and remade by Gemini.",
    Duration = 8
})
pcall(function() SaveManager:LoadAutoloadConfig() end)
