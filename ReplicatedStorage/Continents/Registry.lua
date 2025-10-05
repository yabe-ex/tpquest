-- ReplicatedStorage/Continents/Registry.lua
local RS = game:GetService("ReplicatedStorage")
local ContinentsFolder = RS:WaitForChild("Continents")

return {
    -- require(ContinentsFolder.Town),             -- 【削除】Town大陸の参照
    require(ContinentsFolder.ContinentHokkaido),
}