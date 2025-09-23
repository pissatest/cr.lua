-- Simple Pekka Deployer
-- This script fires the two remotes required to deploy the "Pekka" unit one time.

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Configuration
local DEPLOY_REMOTE_NAME = "Deploy"
local UNIT_TO_DEPLOY = "Giant"
local DEPLOY_CF_FOR_RED_PLAYER  = CFrame.new(-3, 26, -164)
local DEPLOY_CF_FOR_BLUE_PLAYER = CFrame.new(-2, 24, 110)

-- Get Local Player and Team
local localPlayer = Players.LocalPlayer
local playerTeam = localPlayer.Team and localPlayer.Team.Name or "Spectator"

-- Determine the correct CFrame based on the player's team
local targetCF
if playerTeam == "Red" then
    targetCF = DEPLOY_CF_FOR_RED_PLAYER
elseif playerTeam == "Blue" then
    targetCF = DEPLOY_CF_FOR_BLUE_PLAYER
else
    -- Stop if the player is not on a valid team
    warn("Cannot deploy unit: Player is a Spectator.")
    return
end

-- Find the remote event/function in ReplicatedStorage
local deployRemote = ReplicatedStorage:WaitForChild(DEPLOY_REMOTE_NAME)

if deployRemote then
    -- Fire the first remote to request the unit
    pcall(function()
        deployRemote:InvokeServer("RequestDeploy", UNIT_TO_DEPLOY)
    end)

    -- A short delay is often necessary between requesting and deploying
    task.wait(0.5)

    -- Fire the second remote to place the unit at the target CFrame
    pcall(function()
        deployRemote:InvokeServer("Deploy", UNIT_TO_DEPLOY, targetCF)
    end)
    
    print("Deployment remotes for '" .. UNIT_TO_DEPLOY .. "' have been fired.")
else
    warn("Could not find the deployment remote: '" .. DEPLOY_REMOTE_NAME .. "'")
end
