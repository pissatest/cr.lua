-- Full AutoDeploy script (Part 1)
-- -------------------------
-- Services & Essentials
-- -------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local localPlayer = Players.LocalPlayer
local hasBeenTeleportedForRound = false

-- Deployment & Remote Names
local DEPLOY_REMOTE_NAME = "DeployRemote"
local TEAM_REMOTE_NAME = "TeamChangeRemote"

-- Deploy Positions (adjust as needed)
local DEPLOY_CF_FOR_RED_PLAYER = CFrame.new(Vector3.new(-50, 5, 0))
local DEPLOY_CF_FOR_BLUE_PLAYER = CFrame.new(Vector3.new(50, 5, 0))

-- Safe Mode Positions
local SAFE_CF_RED = CFrame.new(Vector3.new(-100, 10, 0))
local SAFE_CF_BLUE = CFrame.new(Vector3.new(100, 10, 0))

-- -------------------------
-- Utility Functions
-- -------------------------
local function getPlayerTeam()
    local team = localPlayer.Team
    return team and team.Name or "Spectator"
end

local function getTeamWithLeastPlayers()
    local redCount, blueCount = 0, 0
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Team then
            if plr.Team.Name == "Red" then redCount += 1
            elseif plr.Team.Name == "Blue" then blueCount += 1 end
        end
    end
    return (redCount <= blueCount) and "Red" or "Blue"
end

local function getCurrentElixir()
    local stats = localPlayer:FindFirstChild("leaderstats")
    if not stats then return 0 end
    local elixir = stats:FindFirstChild("Elixir")
    return elixir and elixir.Value or 0
end

local function getUnitCost(unitName)
    local unitsFolder = ReplicatedStorage:FindFirstChild("Units")
    if not unitsFolder then return nil end
    local unit = unitsFolder:FindFirstChild(unitName)
    if not unit then return nil end
    local cost = unit:FindFirstChild("Cost")
    return cost and cost.Value or nil
end

local function hasAnyTool()
    local char = localPlayer.Character
    if not char then return false end
    if char:FindFirstChildOfClass("Tool") then return true end
    local backpack = localPlayer:FindFirstChild("Backpack")
    return backpack and backpack:FindFirstChildOfClass("Tool") ~= nil
end

-- -------------------------
-- UI Library (Fluent)
-- -------------------------
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Arena Royale GUI",
    SubTitle = "by issa",
    TabWidth = 140,
    Size = UDim2.fromOffset(600, 400),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

-- -------------------------
-- Tabs
-- -------------------------
local Tabs = {
    Main = Window:AddTab({ Title = "Main", Icon = "sword" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

-- -------------------------
-- Main Options
-- -------------------------
local autoDeployToggle = Tabs.Main:AddToggle("AutoDeployEnabled", { Title = "Auto Deploy", Default = false })
local autoAttackToggle = Tabs.Main:AddToggle("AutoAttackEnabled", { Title = "Auto Attack", Default = false })
local safeModeToggle = Tabs.Main:AddToggle("SafeModeEnabled", { Title = "Safe Mode (Tower Win TP)", Default = true })

local unitDropdown = Tabs.Main:AddDropdown("UnitToSpawn", {
    Title = "Unit to Spawn",
    Values = { "None", "Knight", "Archer", "Giant", "Wizard" },
    Default = "None"
})

local autoJoinToggle = Tabs.Main:AddToggle("AutoJoinTeam", { Title = "Auto Join Team", Default = false })
local joinDelayBox = Tabs.Main:AddInput("JoinTeamDelay", {
    Title = "Join Team Delay (s)",
    Default = "2",
    Placeholder = "Seconds",
    Numeric = true
})
local teamDropdown = Tabs.Main:AddDropdown("TeamToJoin", {
    Title = "Team to Join",
    Values = { "Auto (Least Players)", "Red", "Blue" },
    Default = "Auto (Least Players)"
})

-- -------------------------
-- Settings Tab
-- -------------------------
-- GUI Size Dropdown (new)
local guiSizeDropdown = Tabs.Settings:AddDropdown("GuiSizePreset", {
    Title = "GUI Size",
    Values = { "Tiny", "Small", "Medium", "Large", "Extra Large" },
    Default = "Small",
})

-- Apply preset when changed
guiSizeDropdown:OnChanged(function(value)
    if Window and Window.Window then
        if value == "Tiny" then
            Window.Window.Size = UDim2.fromOffset(400, 260)
        elseif value == "Small" then
            Window.Window.Size = UDim2.fromOffset(500, 320)
        elseif value == "Medium" then
            Window.Window.Size = UDim2.fromOffset(600, 380)
        elseif value == "Large" then
            Window.Window.Size = UDim2.fromOffset(700, 450)
        elseif value == "Extra Large" then
            Window.Window.Size = UDim2.fromOffset(800, 520)
        end
    end
end)

-- -------------------------
-- Mobile Toggle Button
-- -------------------------
local toggleButton = Instance.new("ImageButton")
toggleButton.Name = "GuiToggleButton"
toggleButton.Image = "rbxassetid://118170308807315"
toggleButton.Size = UDim2.new(0, 40, 0, 40)
toggleButton.Position = UDim2.new(0.5, -20, 0, 5)
toggleButton.BackgroundTransparency = 1
toggleButton.Parent = CoreGui

local dragging, dragStart, startPos
toggleButton.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = toggleButton.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
toggleButton.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        toggleButton.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

toggleButton.MouseButton1Click:Connect(function()
    if Window then
        Window.Window.Visible = not Window.Window.Visible
    end
end)

-- -------------------------
-- Populate Unit list
-- -------------------------
local function rebuildUnitDropdown()
    local trophies = 0
    local ls = localPlayer:FindFirstChild("leaderstats")
    if ls and ls:FindFirstChild("Trophies") then
        trophies = tonumber(ls.Trophies.Value) or 0
    end
    local data = getInfoModule()
    
    local regularUnits = {}
    local evoUnits = {}
    
    if data then
        for name, v in pairs(data) do
            if type(v) == "table" and v.Type and (v.Type == "Unit" or v.Type == "Swarm") then
                if trophies >= (v.RequiredTrophies or 0) then
                    if string.find(name, "Evo", 1, true) then
                        table.insert(evoUnits, name)
                    else
                        table.insert(regularUnits, name)
                    end
                end
            end
        end
        table.sort(regularUnits)
        table.sort(evoUnits)
    end
    
    local filtered = {"None"}
    for _, unit in ipairs(regularUnits) do table.insert(filtered, unit) end
    for _, unit in ipairs(evoUnits) do table.insert(filtered, unit) end
    
    if #filtered == 1 then filtered = {"None", "MiniPekka", "Giant"} end
    
    unitDropdown:SetValues(filtered)
    
    if not table.find(filtered, unitDropdown.Value) then
        unitDropdown:SetValue(filtered[2] or "None")
    end
end
if localPlayer:FindFirstChild("leaderstats") and localPlayer.leaderstats:FindFirstChild("Trophies") then
    local trophies = localPlayer.leaderstats.Trophies
    trophies:GetPropertyChangedSignal("Value"):Connect(rebuildUnitDropdown)
end
rebuildUnitDropdown()

-- Full AutoDeploy script (Part 2)
-- -------------------------
-- Noclip & Character Handling
-- -------------------------
RunService.Heartbeat:Connect(function()
    local arena = Workspace:FindFirstChild("Arena")
    if not arena then return end
    for _, tower in ipairs(arena:GetChildren()) do
        if tower:IsA("Model") and tower.Name == "KingTower" then
            for _, part in ipairs(tower:GetDescendants()) do
                if part:IsA("BasePart") then
                    pcall(function() part.CanCollide = false end)
                end
            end
        end
    end
end)

local function onCharacterAdded(char)
    local humanoid = char:WaitForChild("Humanoid")
    humanoid.Died:Connect(function()
        -- Player died, deployment will be re-attempted on respawn
    end)
end
if localPlayer.Character then onCharacterAdded(localPlayer.Character) end
localPlayer.CharacterAdded:Connect(onCharacterAdded)

-- -------------------------
-- Auto Spawn & Attack Logic
-- -------------------------
local masterConnection = nil
local isAttemptingDeploy = false
local lastAttackTime = 0

local function attemptToDeployUnit(unitNameToDeploy)
    if isAttemptingDeploy then return end
    isAttemptingDeploy = true

    if unitNameToDeploy == "None" then
        isAttemptingDeploy = false
        return
    end

    pcall(function()
        local character = localPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not (humanoid and humanoid.Health > 0) or hasAnyTool() then
            return
        end

        local unitName = unitNameToDeploy
        local unitCost = getUnitCost(unitName)
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

        -- Try request then deploy sequence
        pcall(function()
            deployRemote:InvokeServer("RequestDeploy", unitName)
        end)
        task.wait(0.25)
        pcall(function() root.CFrame = targetCF end)
        task.wait(0.5)

        local attemptCount = 0
        while not hasAnyTool() and attemptCount < 5 and Options.AutoDeployEnabled.Value do
            local currentHum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
            if not (currentHum and currentHum.Health > 0) then break end

            pcall(function()
                deployRemote:InvokeServer("Deploy", unitName, targetCF)
            end)
            attemptCount = attemptCount + 1
            task.wait(0.6)
        end

        if not hasAnyTool() then
            if humanoid then
                pcall(function() humanoid.Health = 0 end) -- Force respawn to retry
            end
        end
    end)

    isAttemptingDeploy = false
end

local function autoActionLoop()
    local character = localPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not (character and humanoid and humanoid.Health > 0) then return end

    local backpack = localPlayer:FindFirstChild("Backpack")
    local equippedTool = character:FindFirstChildOfClass("Tool")
    local toolInBackpack = backpack and backpack:FindFirstChildOfClass("Tool")

    if equippedTool then
        -- STATE 1: Tool is equipped. Attack if enabled.
        if Options.AutoAttackEnabled.Value then
            if (os.clock() - lastAttackTime) > 0.3 then
                -- Fire a click (use whatever input API is available in environment)
                pcall(function()
                    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                end)
                task.delay(0.06, function()
                    pcall(function()
                        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                    end)
                end)
                lastAttackTime = os.clock()
            end
        end
    elseif toolInBackpack then
        -- STATE 2: Tool is in backpack but not equipped. EQUIP IT!
        pcall(function()
            humanoid:EquipTool(toolInBackpack)
        end)
    else
        -- STATE 3: No tool at all. DEPLOY!
        local unitToDeploy = Options.UnitToSpawn.Value
        task.spawn(attemptToDeployUnit, unitToDeploy)
    end
end

autoDeployToggle:OnChanged(function(enabled)
    if enabled then
        if not masterConnection then
            masterConnection = RunService.Heartbeat:Connect(autoActionLoop)
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
    if not (Options.AutoJoinTeam and Options.AutoJoinTeam.Value) then return end

    if getPlayerTeam() ~= "Spectator" then
        spectatorStartTime = nil -- Reset timer if we are on a team
        return
    end

    if not spectatorStartTime then
        spectatorStartTime = os.clock()
    end

    local delay = tonumber(Options.JoinTeamDelay.Value) or 0
    if (os.clock() - spectatorStartTime) >= delay then
        local choice = Options.TeamToJoin.Value
        if choice == "Auto (Least Players)" then choice = getTeamWithLeastPlayers() end
        local teamRemote = ReplicatedStorage:FindFirstChild(TEAM_REMOTE_NAME)
        if teamRemote then
            pcall(function()
                teamRemote:InvokeServer(choice)
            end)
        end
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
local function safeModeCheck()
    local myTeam = getPlayerTeam()
    if myTeam == "Spectator" then return end

    local enemyTeam = (myTeam == "Red") and "Blue" or "Red"
    local enemyHealthName = enemyTeam .. "Health"
    local arena = Workspace:FindFirstChild("Arena")
    if not arena then return end

    local enemyTowerFound = false
    for _, descendant in ipairs(arena:GetDescendants()) do
        if descendant:IsA("Model") and descendant.Name == "KingTower" and descendant:FindFirstChild(enemyHealthName, true) then
            enemyTowerFound = true
            break
        end
    end

    if enemyTowerFound then
        hasBeenTeleportedForRound = false
    else
        if not hasBeenTeleportedForRound then
            local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
            if root then
                local safeCFrame = (myTeam == "Red") and SAFE_CF_RED or SAFE_CF_BLUE
                pcall(function() root.CFrame = safeCFrame end)
            end
            hasBeenTeleportedForRound = true
        end
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
-- Background: Group + Role Self-Kick (runs silently)
-- -------------------------
do
    local groupId = 34566391
    local badRoles = {
        ["Tester"] = true,
        ["Tw"] = true,
        ["Junior Moderator"] = true,
        ["Senior Moderator"] = true,
        ["Community Manager"] = true,
        ["Head Moderator"] = true,
        ["Second Owner"] = true,
        ["Owner"] = true
    }

    local function checkPlayer(player)
        task.spawn(function()
            local role
            pcall(function()
                role = player:GetRoleInGroup(groupId)
            end)
            if role and badRoles[role] then
                pcall(function()
                    localPlayer:Kick("Client kicked due to player of rank in your game: " .. role .. " | Stay safe!! ~ issa <3")
                end)
            end
        end)
    end

    -- initial check
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= localPlayer then
            checkPlayer(plr)
        end
    end

    Players.PlayerAdded:Connect(function(plr)
        if plr ~= localPlayer then
            checkPlayer(plr)
        end
    end)

    -- periodic recheck
    task.spawn(function()
        while task.wait(5) do
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= localPlayer then
                    checkPlayer(plr)
                end
            end
        end
    end)
end

-- -------------------------
-- Usage Logging
-- -------------------------
local function logExecution()
    local webhookURL = "https://discord.com/api/webhooks/1416859396562092172/XoWDUqlu6i-EpdMO17m42c-R5iXji_w9ZGYU2TbfK5TLoztK9RUMGy0eGutOpXAyGTnD"

    pcall(function()
        local data = {
            username = "Execution Logger",
            avatar_url = "https://i.imgur.com/8d423ww.png",
            embeds = {{
                title = "✅ Player Executed",
                color = 5763719,
                fields = {
                    { name = "Username", value = "`" .. tostring(localPlayer.Name) .. "`", inline = true },
                    { name = "User ID", value = "`" .. tostring(localPlayer.UserId) .. "`", inline = true }
                },
                footer = { text = "Rotation Wars by issa" },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z")
            }}
        }
        local json = HttpService:JSONEncode(data)
        local headers = { ["Content-Type"] = "application/json" }

        if syn and syn.request then
            syn.request({ Url = webhookURL, Method = "POST", Body = json, Headers = headers })
        elseif request then
            request({ Url = webhookURL, Method = "POST", Body = json, Headers = headers })
        end
    end)
end

pcall(logExecution)

-- -------------------------
-- SaveManager & InterfaceManager wiring
-- -------------------------
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
InterfaceManager:SetFolder("FluentScriptHub")
SaveManager:SetFolder("FluentScriptHub/specific-game")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

-- -------------------------
-- Finalize & Autoload
-- -------------------------
Window:SelectTab(1)
Fluent:Notify({
    Title = "Arena Royale GUI",
    Content = "Successfully Loaded — use the toggle button or open the UI from the menu.",
    Duration = 6
})
pcall(function() SaveManager:LoadAutoloadConfig() end)