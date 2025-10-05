return {
	name = "ContinentHokkaido",
	displayName = "Hokkaido Continent",

	islands = {
		"Hokkaido_W1", "Hokkaido_C1", "Hokkaido_C2", "Hokkaido_C3",
		"Hokkaido_C4", "Hokkaido_C5", "Hokkaido_E1",
		"Hokkaido_N1", "Hokkaido_N2", "Hokkaido_N3", "Hokkaido_N4",
		"Hokkaido_NE1", "Hokkaido_NE2",
		"Hokkaido_S1", "Hokkaido_S2",
		"Hokkaido_SW1", "Hokkaido_SW2",
	},

	bridges = {},

	portals = {
			{
				name = "Hokkaido_to_Town",
				toZone = "ContinentTown",
				islandName = "Hokkaido_C3",
				offsetX = 0,
				offsetZ = 0,
				label = "→ Town",
				color = Color3.fromRGB(255, 200, 100),
			},
		},

	BGM = "rbxassetid://115666507179769",  -- 後でアセットIDに変更
	BGMVolume = 0.2,  -- 音量（0.0-1.0）
}