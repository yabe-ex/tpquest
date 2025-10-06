-- ===== ./ReplicatedStorage/Continents/ContinentKyushu.lua (新規) =====
return {
	name = "ContinentKyushu",
	displayName = "Kyushu Region",

	islands = {
		"Kyushu_N1", "Kyushu_C1", "Kyushu_S1",
		"Kyushu_NE1", "Kyushu_SW1", "Kyushu_W1",
	},

	bridges = {},

	portals = {
			{
				name = "Kyushu_to_Town",
				toZone = "ContinentTown",
				islandName = "Kyushu_C1", -- 中央の島からポータル
				offsetX = 0,
				offsetZ = 0,
				label = "→ Town",
				color = Color3.fromRGB(255, 100, 100), -- 赤色のポータル
			},
		},

	BGM = "rbxassetid://115666507179769", -- 後でアセットIDに変更
	BGMVolume = 0.3,
}