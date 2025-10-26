local RS = game:GetService("ReplicatedStorage")
local Monsters = RS:WaitForChild("Monsters")

return {
	require(Monsters.Slime),
	require(Monsters.Slime_pink),
	require(Monsters.golem),
	-- 将来追加するモンスター:
	require(Monsters.CuteSlime),
	require(Monsters.RubySlime),
	-- require(Monsters.Goblin),
}
