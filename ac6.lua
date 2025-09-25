--[[ 
    Script: Auto Deploy for a new game (V7 - Robust Deploy/Equip/Attack + Logging)
    Author: Gemini (patched per user's request)
    Description:
      - Auto Deploy and Auto Attack follow the working example's logic/state machine.
      - Uses ChoseUnitEvent + DeployEvent (tries multiple call shapes).
      - Verbose logging via Fluent:Notify and print to help debug.
      - Auto-join only runs when Spectator.
      - Teleport-on-spawn optional and only active while Auto Deploy is ON.
]]

-- Services & basics
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = workspace
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")
local localPlayer = Players.LocalPlayer

-- UI Libs
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- Window
local Window = Fluent:CreateWindow({
    Title = "Game Helper (V7)",
    SubTitle = "Auto Deploy & Attack (robust) by Gemini",
    TabWidth = 160,
    Size = UDim2.fromOffset(600, 520),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    AutoDeploy = Window:AddTab({ Title = "Auto Deploy", Icon = "package" }),
    Settings   = Window:AddTab({ Title = "Settings",    Icon = "settings" })
}
local Options = Fluent.Options

-- -------------------------
-- Config / CFrames / Names
-- -------------------------
local DEPLOY_CF_FOR_RED_PLAYER  = CFrame.new(-3, 26, -164)
local DEPLOY_CF_FOR_BLUE_PLAYER = CFrame.new(-2, 24, 110)
local SAFE_CF_RED  = CFrame.new(-2, 24, 110)
local SAFE_CF_BLUE = CFrame.new(-3, 26, -164)

-- Use the remotes you mentioned earlier
local EventsFolder = ReplicatedStorage:WaitForChild("Events")
local SetTeamEvent = EventsFolder:WaitForChild("SetTeam")
local ChoseUnitEvent = EventsFolder:WaitForChild("ChoseUnit")
local DeployEvent = EventsFolder:WaitForChild("Deploy")

local DEPLOY_REMOTE_NAME = "Deploy" -- fallback naming from example
local TEAM_REMOTE_NAME   = "Team"   -- fallback naming from example

-- -------------------------
-- Game Info cache (Info / Unit stats)
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
-- Helpers: Team & Game Data
-- -------------------------
local function getPlayerTeam()
    -- try Stats.Team first (some games use a Stats object)
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
    
    -- attempt common value locations
    if ReplicatedStorage:FindFirstChild("Game") then
        local g = ReplicatedStorage:FindFirstChild("Game")
        local elixirB = g:FindFirstChild("ElixirB")
        local elixirR = g:FindFirstChild("ElixirR")
        if myTeam == "Blue" and elixirB then elixirValue = (elixirB.Value or 0) end
        if myTeam == "Red" and elixirR then elixirValue = (elixirR.Value or 0) end
    end

    -- fallback to GameStatus style (some variants)
    if elixirValue == 0 then
        local gameStatus = ReplicatedStorage:FindFirstChild("GameStatus")
        if gameStatus then
            local obj = gameStatus:FindFirstChild(myTeam .. "Elixir")
            if obj then elixirValue = obj.Value end
        end
    end

    return elixirValue
end

-- -------------------------
-- UI (same layout as your working script)
-- -------------------------
Tabs.AutoDeploy:AddParagraph({ Title = "Unit Deployment", Content = "Choose a unit and enable the toggles below. Auto Deploy will spawn and equip the unit. Auto Attack will make it attack." })
local unitDropdown = Tabs.AutoDeploy:AddDropdown("UnitToSpawn", { Title = "Unit to Spawn", Values = {"None"}, Default = "None" })
local autoDeployToggle = Tabs.AutoDeploy:AddToggle("AutoDeployEnabled", { Title = "Enable Auto Deploy", Default = false })
local autoAttackToggle = Tabs.AutoDeploy:AddToggle("AutoAttackEnabled", { Title = "Enable Auto Attack", Default = false })
local teleportToggle = Tabs.AutoDeploy:AddToggle("TeleportOnSpawn", { Title = "Teleport to Enemy Tower on Spawn", Default = true })

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
        if syn and syn.request then syn.request({Url = "https://discord.gg/PQvfmPyVtS", Method = "GET"}) end
    end
})

-- -------------------------
-- Populate Unit list (info module based)
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
    
    if #filtered == 1 then filtered = {"None", "MiniPekka", "Giant"} end -- fallback
    
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

-- -------------------------
-- Noclip for King Towers
-- -------------------------
RunService.Heartbeat:Connect(function()
    local arena = Workspace:FindFirstChild("Arena")
    if not arena then return end
    for _, tower in ipairs(arena:GetChildren()) do
        if tower:IsA("Model") and (tower.Name == "KingTower" or tower.Name == "King Tower") then
            for _, part in ipairs(tower:GetDescendants()) do
                if part:IsA("BasePart") then pcall(function() part.CanCollide = false end) end
            end
        end
    end
end)

-- -------------------------
-- Character handling
-- -------------------------
local function onCharacterAdded(char)
    local humanoid = char:WaitForChild("Humanoid")
    humanoid.Died:Connect(function()
        -- will retry deploy on respawn due to main loop
        Fluent:Notify({Title="Character", Content="You died — deploy loop will retry on respawn.", Duration=3})
    end)
end
if localPlayer.Character then onCharacterAdded(localPlayer.Character) end
localPlayer.CharacterAdded:Connect(onCharacterAdded)

-- -------------------------
-- Deploy / Attack loops (state-machine like the working script)
-- -------------------------
local masterConnection = nil
local isAttemptingDeploy = false
local lastAttackTime = 0

-- helper: verbose logging
local function debugLog(title, msg, short)
    pcall(function()
        print(("[GH] %s: %s"):format(title, tostring(msg)))
        if Window and Fluent and Fluent.Notify then
            Fluent:Notify({ Title = title, Content = tostring(msg), Duration = short and 2 or 4 })
        end
    end)
end

-- attempt deploy using ChoseUnitEvent & DeployEvent with multiple signatures & retries
local function doDeploySequence(unitName, targetCF)
    -- choose unit
    local ok, err = pcall(function() ChoseUnitEvent:FireServer(unitName) end)
    if not ok then
        debugLog("Deploy Error", "Failed to fire ChoseUnitEvent: "..tostring(err))
    end
    task.wait(0.12)

    -- Try several DeployEvent call shapes in order:
    local attempts = 0
    local maxAttempts = 5
    while attempts < maxAttempts do
        attempts = attempts + 1
        local deployed = false
        local triedSignatures = {}

        -- Try Deploy(unitName, targetCF) if targetCF provided
        if targetCF then
            triedSignatures[#triedSignatures+1] = "Deploy(unitName, targetCF)"
            local ok1, e1 = pcall(function() DeployEvent:FireServer(unitName, targetCF) end)
            if ok1 then deployed = true end
            if not ok1 then debugLog("Deploy Attempt", "sig1 failed: "..tostring(e1), true) end
        end

        -- Try Deploy(targetCF)
        if not deployed and targetCF then
            triedSignatures[#triedSignatures+1] = "Deploy(targetCF)"
            local ok2, e2 = pcall(function() DeployEvent:FireServer(targetCF) end)
            if ok2 then deployed = true end
            if not ok2 then debugLog("Deploy Attempt", "sig2 failed: "..tostring(e2), true) end
        end

        -- Try Deploy() with no args
        if not deployed then
            triedSignatures[#triedSignatures+1] = "Deploy()"
            local ok3, e3 = pcall(function() DeployEvent:FireServer() end)
            if ok3 then deployed = true end
            if not ok3 then debugLog("Deploy Attempt", "sig3 failed: "..tostring(e3), true) end
        end

        if deployed then
            debugLog("Deploy", ("Deployed %s (attempt %d) via: %s"):format(unitName, attempts, table.concat(triedSignatures, ", ")))
            return true
        end

        task.wait(0.5)
    end

    debugLog("Deploy Failure", ("Failed to deploy %s after %d attempts. Tried: %s"):format(unitName, maxAttempts, table.concat({"sig1","sig2","sig3"}, ", ")))
    return false
end

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
        if not (humanoid and humanoid.Health > 0) then
            debugLog("Deploy", "Cannot deploy: no living character.")
            return
        end

        if hasAnyTool() then
            debugLog("Deploy", "Has tool already — skipping deploy.")
            return
        end

        local unitCost = getUnitCost(unitNameToDeploy)
        if not unitCost then
            debugLog("Deploy", "Unit cost unknown for "..tostring(unitNameToDeploy))
            return
        end
        if getCurrentElixir() < unitCost then
            debugLog("Deploy", ("Not enough elixir: need %s, have %s"):format(tostring(unitCost), tostring(getCurrentElixir())), true)
            return
        end

        local myTeam = getPlayerTeam()
        if myTeam == "Spectator" then
            debugLog("Deploy", "You are Spectator — cannot deploy.")
            return
        end

        local targetCF = (myTeam == "Red" and DEPLOY_CF_FOR_RED_PLAYER) or (myTeam == "Blue" and DEPLOY_CF_FOR_BLUE_PLAYER)
        if not targetCF then
            debugLog("Deploy", "No deploy CFrame available for team "..tostring(myTeam))
            return
        end

        -- request + teleport like working script
        local deployRemote = ReplicatedStorage:FindFirstChild(DEPLOY_REMOTE_NAME)
        if deployRemote and type(deployRemote.InvokeServer) == "function" then
            pcall(function() deployRemote:InvokeServer("RequestDeploy", unitNameToDeploy) end)
            task.wait(0.25)
        end

        -- Move player to deploy cframe (helps games that require proximity)
        if character and character:FindFirstChild("HumanoidRootPart") then
            pcall(function() character.HumanoidRootPart.CFrame = targetCF end)
        end
        task.wait(0.45)

        -- Attempt deploying (and wait for tool to appear)
        local attemptCount = 0
        while not hasAnyTool() and attemptCount < 5 and Options.AutoDeployEnabled.Value do
            local ok = doDeploySequence(unitNameToDeploy, targetCF)
            attemptCount = attemptCount + 1
            task.wait(0.6)
            if hasAnyTool() then break end
        end

        if not hasAnyTool() then
            debugLog("Deploy", "Deploy attempts exhausted; forcing respawn to retry.")
            if humanoid then
                pcall(function() humanoid.Health = 0 end)
            end
        else
            debugLog("Deploy", "Successfully obtained tool after deploy.")
        end
    end)

    isAttemptingDeploy = false
end

-- Attack / equip / deploy state machine loop
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
                local ok, e = pcall(function()
                    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                end)
                task.delay(0.08, function()
                    pcall(function()
                        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                    end)
                end)
                if ok then
                    lastAttackTime = os.clock()
                else
                    debugLog("Attack", "VIM send failed: "..tostring(e), true)
                end
            end
        end
    elseif toolInBackpack then
        -- STATE 2: Tool in backpack but not equipped -> equip it
        local success, err = pcall(function() humanoid:EquipTool(toolInBackpack) end)
        if not success then debugLog("Equip", "Failed to equip tool: "..tostring(err), true) end
    else
        -- STATE 3: No tool -> attempt deploy
        local unitToDeploy = Options.UnitToSpawn.Value
        task.spawn(attemptToDeployUnit, unitToDeploy)
    end
end

autoDeployToggle:OnChanged(function(enabled)
    if enabled then
        if not masterConnection then
            masterConnection = RunService.Heartbeat:Connect(autoActionLoop)
            debugLog("AutoDeploy", "Enabled")
        end
        -- when enabling AutoDeploy also attach spawn watcher if teleport-on-spawn is enabled
        if Options.TeleportOnSpawn.Value then
            -- spawn watcher connection handled below in spawn watcher setup (connect function below will check spawnConnection)
            if not spawnConnection then
                -- (connectUnitSpawnWatcher is called below; this toggles spawnConnection)
            end
        end
    else
        if masterConnection then
            masterConnection:Disconnect()
            masterConnection = nil
            debugLog("AutoDeploy", "Disabled")
        end
    end
end)

-- -------------------------
-- Auto Join Team (Spectator only)
-- -------------------------
local joinConnection = nil
local spectatorStartTime = nil

local function joinTeamAttempt()
    if getPlayerTeam() == "Blue" or getPlayerTeam() == "Red" then
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

        -- Try SetTeamEvent (Events.SetTeam), or fallback to Team remote if present
        local success, err = pcall(function() SetTeamEvent:FireServer(teamChoiceName) end)
        if not success then
            local teamRemote = ReplicatedStorage:FindFirstChild(TEAM_REMOTE_NAME)
            if teamRemote and type(teamRemote.InvokeServer) == "function" then
                pcall(function() teamRemote:InvokeServer(teamChoiceName) end)
            else
                debugLog("AutoJoin", "Failed to join team; no SetTeamEvent or TEAM remote available.")
            end
        else
            debugLog("AutoJoin", "Requested join team: "..tostring(teamChoiceName))
        end

        spectatorStartTime = os.clock()
    end
end

autoJoinToggle:OnChanged(function(enabled)
    if enabled and not joinConnection then
        joinConnection = RunService.Stepped:Connect(joinTeamAttempt)
        debugLog("AutoJoin", "Enabled")
    elseif not enabled and joinConnection then
        joinConnection:Disconnect()
        joinConnection = nil
        spectatorStartTime = nil
        debugLog("AutoJoin", "Disabled")
    end
end)

-- -------------------------
-- Safe Mode
-- -------------------------
local safeConnection = nil
local hasBeenTeleportedForRound = false

local function safeModeCheck()
    local myTeam = getPlayerTeam()
    if myTeam == "Spectator" then return end

    local enemyTeam = (myTeam == "Red") and "Blue" or "Red"
    local enemyHealthName = enemyTeam .. "Health"
    local arena = Workspace:FindFirstChild("Arena")
    if not arena then return end

    local enemyTowerFound = false
    for _, descendant in ipairs(arena:GetDescendants()) do
        if descendant:IsA("Model") and (descendant.Name == "KingTower" or descendant.Name == "King Tower") and descendant:FindFirstChild(enemyHealthName, true) then
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
                debugLog("SafeMode", "Teleported to safe CFrame due to enemy tower absence.")
            end
            hasBeenTeleportedForRound = true
        end
    end
end

safeModeToggle:OnChanged(function(enabled)
    if enabled and not safeConnection then
        safeConnection = RunService.Heartbeat:Connect(safeModeCheck)
        debugLog("SafeMode", "Enabled")
    elseif not enabled and safeConnection then
        safeConnection:Disconnect()
        safeConnection = nil
        debugLog("SafeMode", "Disabled")
    end
end)

-- -------------------------
-- Teleport to Enemy Tower on Unit Spawn (optional, only when AutoDeploy ON)
-- -------------------------
local spawnDebounce = 0.5
local lastTeleportAt = 0
spawnConnection = nil

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
            if (v.Name == "KingTower" or v.Name == "King Tower") and v:IsA("Model") and v.PrimaryPart then
                local z_pos = v.PrimaryPart.Position.Z
                -- approximate team by z distance to our SAFE positions
                local towerTeam = (math.abs(z_pos - SAFE_CF_BLUE.Position.Z) < 80) and "Blue" or (math.abs(z_pos - SAFE_CF_RED.Position.Z) < 80) and "Red"
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
    if (os.clock() - lastTeleportAt) < spawnDebounce then return end

    local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local towerCF = findEnemyKingTowerCFrame()
    if towerCF then
        lastTeleportAt = os.clock()
        local target = towerCF + Vector3.new(0, 6, 0)
        pcall(function() root.CFrame = target end)
        debugLog("Teleport", "Teleported to enemy tower on unit spawn.")
    end
end

local function onUnitChildAdded(child)
    if (os.clock() - lastTeleportAt) < spawnDebounce then return end
    if isModelOwnedByLocalPlayer(child) then
        teleportToEnemyTower()
        return
    end
    if child:IsA("Folder") or child:IsA("Model") then
        for _, d in ipairs(child:GetDescendants()) do
            if d:IsA("Model") and isModelOwnedByLocalPlayer(d) then
                teleportToEnemyTower()
                break
            end
        end
    end
end

local function connectUnitSpawnWatcher()
    if spawnConnection then return end
    local unitsFolder = Workspace:FindFirstChild("Units")
    if not unitsFolder then
        task.spawn(function()
            local uf = Workspace:WaitForChild("Units", 10)
            if uf then
                spawnConnection = uf.ChildAdded:Connect(onUnitChildAdded)
            end
        end)
    else
        spawnConnection = unitsFolder.ChildAdded:Connect(onUnitChildAdded)
    end
end

local function disconnectUnitSpawnWatcher()
    if spawnConnection then
        spawnConnection:Disconnect()
        spawnConnection = nil
    end
end

-- Toggle spawn watcher with AutoDeploy toggle changes
autoDeployToggle:OnChanged(function(enabled)
    if enabled then
        connectUnitSpawnWatcher()
    else
        disconnectUnitSpawnWatcher()
    end
end)

-- -------------------------
-- Usage Logging (webhook) - same as example (safe pcall)
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
                footer = { text = "Game Helper by Gemini" },
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

Window:SelectTab(1)
Fluent:Notify({
    Title = "Game Helper (V7)",
    Content = "Loaded — Auto Deploy/Attack loops aligned with working example. Check notifications/console for logs.",
    Duration = 6
})
pcall(function() SaveManager:LoadAutoloadConfig() end)