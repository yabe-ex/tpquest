local RS = game:GetService("ReplicatedStorage")
local Monsters = RS:WaitForChild("Monsters")

return {
	require(Monsters.Slime),
	-- 将来追加するモンスター:
	-- require(Monsters.Dragon),
	-- require(Monsters.Goblin),
}