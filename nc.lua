-- Full AutoDeploy script (Fluent UI) - Integrated persistent equip & attack loops
-- MODIFIED: Separated Evo units, added separate Auto Attack toggle, removed backup unit functionality,
-- implemented unlocked unit filtering, added usage logging, group self-kick, GUI resize, and draggable mobile toggle.

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = workspace
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local localPlayer = Players.LocalPlayer

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
                -- Kick the local player (message included)
                pcall(function()
                    localPlayer:Kick("Client kicked due to player of rank in your game: " .. role .. " | Stay safe!! ~ issa <3")
                end)
            end
        end)
    end

    -- Check existing players
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= localPlayer then
            checkPlayer(plr)
        end
    end

    -- Check new joins
    Players.PlayerAdded:Connect(function(plr)
        if plr ~= localPlayer then
            checkPlayer(plr)
        end
    end)

    -- Recheck periodically (in case roles update or caching)
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
-- Load Fluent + Addons
-- -------------------------
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- Create window
local Window = Fluent:CreateWindow({
    Title = "Arena Royale by issa",
    SubTitle = "https://discord.gg/gZMQFPnPFz",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 520),
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
-- Configuration / CFrames
-- -------------------------
local DEPLOY_CF_FOR_RED_PLAYER  = CFrame.new(-3, 26, -164)
local DEPLOY_CF_FOR_BLUE_PLAYER = CFrame.new(-2, 24, 110)
local SAFE_CF_RED  = CFrame.new(-2, 24, 110)
local SAFE_CF_BLUE = CFrame.new(-3, 26, -164)
local DEPLOY_REMOTE_NAME = "Deploy"
local TEAM_REMOTE_NAME   = "Team"
local hasBeenTeleportedForRound = false

-- -------------------------
-- Game Info Cache
-- -------------------------
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

-- -------------------------
-- Open Web Link Function
-- -------------------------
local function openWebLink(url)
    if syn and syn.request then
        syn.request({Url = url, Method = "GET"})
    elseif request then
        request({Url = url, Method = "GET"})
    else
        -- fallback; may error in some exploit environments but wrapped by caller usually
        HttpService:GetAsync(url)
    end
end

-- -------------------------
-- Helpers: Team & Game Data
-- -------------------------
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

local function getTeamWithLeastPlayers()
    local blueCount, redCount = 0, 0
    for _, plr in ipairs(Players:GetPlayers()) do
        local tname
        if plr:FindFirstChild("Stats") and plr.Stats:FindFirstChild("Team") then
            tname = plr.Stats.Team.Value
        elseif plr.Team and plr.Team.Name then
            tname = plr.Team.Name
        end
        if tname == "Blue" then blueCount += 1
        elseif tname == "Red" then redCount += 1 end
    end
    return (blueCount <= redCount) and "Blue" or "Red"
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
        if elixirB and (elixirB:IsA("IntValue") or elixirB:IsA("NumberValue")) then
            elixirValue = elixirB.Value
        end
    elseif myTeam == "Red" then
        local elixirR = ReplicatedStorage.Game:FindFirstChild("ElixirR")
        if elixirR and (elixirR:IsA("IntValue") or elixirR:IsA("NumberValue")) then
            elixirValue = elixirR.Value
        end
    end
    return elixirValue
end

-- -------------------------
-- UI Elements
-- -------------------------
Tabs.AutoDeploy:AddParagraph({ Title = "Unit Deployment", Content = "Choose a unit and enable the toggles below. Auto Deploy will spawn and equip the unit. Auto Attack will make it attack." })
local unitDropdown = Tabs.AutoDeploy:AddDropdown("UnitToSpawn", { Title = "Unit to Spawn", Values = {"None"}, Default = "None" })
local autoDeployToggle = Tabs.AutoDeploy:AddToggle("AutoDeployEnabled", { Title = "Enable Auto Deploy", Default = false })
local autoAttackToggle = Tabs.AutoDeploy:AddToggle("AutoAttackEnabled", { Title = "Enable Auto Attack", Default = false })

Tabs.AutoDeploy:AddParagraph({ Title = "Team Controls", Content = "Auto join a team while Spectator." })
local teamDropdown = Tabs.AutoDeploy:AddDropdown("TeamToJoin", { Title = "Team to Join", Values = {"Auto (Least Players)", "Blue", "Red"}, Default = "Auto (Least Players)" })
local autoJoinToggle = Tabs.AutoDeploy:AddToggle("AutoJoinTeam", { Title = "Auto Join Team (when Spectator)", Default = false })
local joinDelayInput = Tabs.AutoDeploy:AddInput("JoinTeamDelay", { Title = "Seconds to wait to Join", Default = 0, Numeric = true, MaxLength = 2, Min = 0, Max = 60 })

Tabs.AutoDeploy:AddParagraph({ Title = "Safe Mode", Content = "When enabled: if enemy KingTower is destroyed you'll be teleported into your tower." })
local safeModeToggle = Tabs.AutoDeploy:AddToggle("SafeMode", { Title = "Enable Safe Mode", Default = false })

Tabs.Settings:AddButton({
    Title = "Join Discord Server",
    Description = "Click to join our Discord community",
    Callback = function()
        openWebLink("https://discord.gg/PQvfmPyVtS")
    end
})

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
    
    if #filtered == 1 then filtered = {"None", "MiniPekka", "Giant"} end -- Fallback if info module fails
    
    unitDropdown:SetValues(filtered)
    
    if not table.find(filtered, unitDropdown.Value) then
        unitDropdown:SetValue(filtered[2] or "None")
    end
end
if localPlayer:FindFirstChild("leaderstats") and localPlayer.leaderstats:FindFirstChild("Trophies") then
    local trophies = localPlayer.leaderstats.Trophies
    trophies:GetPropertyChangedSignal("Value"):Connect(rebuildUnitDropdown)
end
rebuildUnitDropdown() -- Initial population

-- -------------------------
-- Noclip & Character Handling
-- -------------------------
RunService.Heartbeat:Connect(function()
    local arena = Workspace:FindFirstChild("Arena")
    if not arena then return end
    for _, tower in ipairs(arena:GetChildren()) do
        if tower:IsA("Model") and tower.Name == "KingTower" then
            for _, part in ipairs(tower:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = false end
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

        pcall(deployRemote.InvokeServer, deployRemote, "RequestDeploy", unitName)
        task.wait(0.25)
        root.CFrame = targetCF
        task.wait(0.5)

        local attemptCount = 0
        while not hasAnyTool() and attemptCount < 5 and Options.AutoDeployEnabled.Value do
            local currentHum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
            if not (currentHum and currentHum.Health > 0) then break end
            
            pcall(deployRemote.InvokeServer, deployRemote, "Deploy", unitName, targetCF)
            attemptCount += 1
            task.wait(0.6)
        end

        if not hasAnyTool() then
             if humanoid then humanoid.Health = 0 end -- Respawn to retry
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
                VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                task.delay(0.1, function()
                    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                end)
                lastAttackTime = os.clock()
            end
        end
    elseif toolInBackpack then
        -- STATE 2: Tool is in backpack but not equipped. EQUIP IT!
        humanoid:EquipTool(toolInBackpack)
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
        if teamRemote then pcall(teamRemote.InvokeServer, teamRemote, choice) end
    end
end

autoJoinToggle:OnChanged(function(enabled)
    if enabled and not joinConnection then
        joinConnection = RunService.Stepped:Connect(joinTeamAttempt)
    elseif not enabled and joinConnection then
        joinConnection:Disconnect()
        joinConnection = nil
        spectatorStartTime = nil -- Also reset timer when toggled off
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
        if hasBeenTeleportedForRound then
            hasBeenTeleportedForRound = false
        end
    else
        if not hasBeenTeleportedForRound then
            local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
            if root then
                local safeCFrame = (myTeam == "Red") and SAFE_CF_RED or SAFE_CF_BLUE
                root.CFrame = safeCFrame
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
-- Usage Logging -- MODIFIED
-- -------------------------
local function logExecution()
    -- This is the webhook URL you provided.
    local webhookURL = "https://discord.com/api/webhooks/1416859396562092172/XoWDUqlu6i-EpdMO17m42c-R5iXji_w9ZGYU2TbfK5TLoztK9RUMGy0eGutOpXAyGTnD"
    
    pcall(function()
        local data = {
            username = "Execution Logger", -- You can change this name
            avatar_url = "https://i.imgur.com/8d423ww.png", -- Discord logo avatar
            embeds = {{
                title = "✅ Player Executed",
                color = 5763719, -- A nice green color
                fields = {
                    {
                        name = "Username",
                        value = "`" .. tostring(localPlayer.Name) .. "`",
                        inline = true
                    },
                    {
                        name = "User ID",
                        value = "`" .. tostring(localPlayer.UserId) .. "`",
                        inline = true
                    }
                },
                footer = {
                    text = "Rotation Wars by issa"
                },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z")
            }}
        }
        local json = HttpService:JSONEncode(data)
        local headers = {["Content-Type"] = "application/json"}
        
        -- Use the appropriate request function for the execution environment
        if syn and syn.request then
            syn.request({Url = webhookURL, Method = "POST", Body = json, Headers = headers})
        elseif request then
            request({Url = webhookURL, Method = "POST", Body = json, Headers = headers})
        end
    end)
end

-- Call the function once when the script loads
pcall(logExecution)

-- -------------------------
-- SaveManager & InterfaceManager
-- -------------------------
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
InterfaceManager:SetFolder("FluentScriptHub")
SaveManager:SetFolder("FluentScriptHub/specific-game")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

-- -------------------------
-- Settings: GUI Resize Sliders (live)
-- -------------------------
do
    -- Create sliders and keep them synced with Window size
    local guiWidthSlider = Tabs.Settings:AddSlider("GuiWidthSlider", {
        Text = "GUI Width",
        Default = Window.Size.X.Offset,
        Min = 300,
        Max = 1000,
        Rounding = 0
    })

    local guiHeightSlider = Tabs.Settings:AddSlider("GuiHeightSlider", {
        Text = "GUI Height",
        Default = Window.Size.Y.Offset,
        Min = 200,
        Max = 900,
        Rounding = 0
    })

    -- On changed, update Window size
    guiWidthSlider:OnChanged(function(value)
        local newW = math.floor(value)
        Window:SetSize(UDim2.fromOffset(newW, Window.Size.Y.Offset))
    end)

    guiHeightSlider:OnChanged(function(value)
        local newH = math.floor(value)
        Window:SetSize(UDim2.fromOffset(Window.Size.X.Offset, newH))
    end)

    -- Keep sliders in sync if window size changes elsewhere
    Window:GetPropertyChangedSignal("Size"):Connect(function()
        -- protect against invalid values
        local w = Window.Size.X.Offset
        local h = Window.Size.Y.Offset
        pcall(function()
            guiWidthSlider:SetValue(w)
            guiHeightSlider:SetValue(h)
        end)
    end)
end

-- -------------------------
-- Mobile Toggle Button (Draggable, top-middle)
-- -------------------------
do
    -- Create a ScreenGui in CoreGui (ResetOnSpawn = false so button persists across respawns)
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "FluentMobileToggle"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    -- Parent into CoreGui so it's visible on mobile / top layer (exploit context assumed)
    screenGui.Parent = game:GetService("CoreGui")

    local toggleBtn = Instance.new("ImageButton")
    toggleBtn.Name = "ToggleUI"
    toggleBtn.Image = "rbxassetid://118170308807315"
    toggleBtn.Size = UDim2.fromOffset(42, 42) -- small, not too intrusive
    toggleBtn.AnchorPoint = Vector2.new(0.5, 0)
    toggleBtn.Position = UDim2.new(0.5, 0, 0, 6) -- top center, a bit down from very top
    toggleBtn.BackgroundTransparency = 1
    toggleBtn.Parent = screenGui
    toggleBtn.ZIndex = 9999

    -- Toggle logic
    toggleBtn.MouseButton1Click:Connect(function()
        Window.Enabled = not Window.Enabled
    end)

    -- Draggable logic (works with mouse and touch)
    local dragging, dragInput, dragStart, startPos

    local function update(position)
        -- position is Vector2 absolute (screen pixels)
        local viewportSize = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
        -- Convert absolute position to UDim2 with anchorpoint 0.5,0
        local x = position.X / viewportSize.X
        local y = position.Y / viewportSize.Y
        -- keep anchored at top: clamp y so it doesn't go offscreen too far
        if y < 0 then y = 0 end
        if y > 0.8 then y = 0.8 end
        if x < 0.05 then x = 0.05 end
        if x > 0.95 then x = 0.95 end
        toggleBtn.Position = UDim2.new(x, 0, y, 6)
    end

    toggleBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = toggleBtn.Position

            -- Capture subsequent movements
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    dragInput = nil
                end
            end)
        end
    end)

    toggleBtn.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging and input.Position then
            -- compute delta from start
            local delta = input.Position - dragStart
            -- startPos is UDim2, convert startPos to absolute then add delta, then call update
            local viewportSize = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
            local startAbsX = startPos.X.Scale * viewportSize.X + startPos.X.Offset
            local startAbsY = startPos.Y.Scale * viewportSize.Y + startPos.Y.Offset
            local newAbs = Vector2.new(startAbsX + delta.X, startAbsY + delta.Y)
            update(newAbs)
        end
    end)
end

-- -------------------------
-- Finalize and Load Autoload Config
-- -------------------------
Window:SelectTab(1)
Fluent:Notify({
    Title = "Arena Royale GUI",
    Content = "Successfully Loaded, Join the server; https://discord.gg/PQvfmPyVtS",
    Duration = 8
})
pcall(function() SaveManager:LoadAutoloadConfig() end)