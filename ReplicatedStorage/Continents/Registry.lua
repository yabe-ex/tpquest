-- ReplicatedStorage/Continents/Registry.lua
local RS = game:GetService("ReplicatedStorage")
local ContinentsFolder = RS:WaitForChild("Continents")

return {
	require(ContinentsFolder.ContinentTown),
	require(ContinentsFolder.ContinentHokkaido),
	-- require(ContinentsFolder.ContinentShikoku),
	require(ContinentsFolder.ContinentKyushu),
	require(ContinentsFolder.Snowland),
	require(ContinentsFolder.BananaLand),
	require(ContinentsFolder.ContinentVendant),
}
