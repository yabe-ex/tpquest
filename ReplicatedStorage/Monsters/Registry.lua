local RS = game:GetService("ReplicatedStorage")
local Monsters = RS:WaitForChild("Monsters")

return {
	require(Monsters.Slime),
	require(Monsters.Slime_pink),
	-- 将来追加するモンスター:
	-- require(Monsters.Dragon),
	-- require(Monsters.Goblin),
}