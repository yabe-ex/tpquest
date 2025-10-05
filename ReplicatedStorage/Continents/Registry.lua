-- ReplicatedStorage/Continents/Registry.lua
local RS = game:GetService("ReplicatedStorage")
local ContinentsFolder = RS:WaitForChild("Continents")

return {
    require(ContinentsFolder.ContientTown),
    require(ContinentsFolder.ContinentHokkaido),
}