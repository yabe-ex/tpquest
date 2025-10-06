-- ===== ./ReplicatedStorage/Continents/ContientTown.lua =====
return {
	name = "ContinentTown",
	displayName = "Start Town",

	islands = {
		"StartTown",
        "Town_NE",
        "Town_SW",
        "Town_SE",
	},

	bridges = {},

	-- ★修正: 北海道、四国、九州へのポータルを追加
	portals = {
		{
            name = "Town_to_Hokkaido",
            toZone = "ContinentHokkaido",
            islandName = "StartTown",
            offsetX = 0,
            offsetZ = -50,
            size = Vector3.new(8, 12, 8),
            color = Color3.fromRGB(200, 200, 255),
            label = "→ Hokkaido"
        },
        {
            name = "Town_to_Shikoku", -- ★新規ポータル
            toZone = "ContinentShikoku",
            islandName = "Town_NE",
            offsetX = 0,
            offsetZ = 0,
            size = Vector3.new(8, 12, 8),
            color = Color3.fromRGB(150, 255, 150),
            label = "→ Shikoku"
        },
        {
            name = "Town_to_Kyushu",  -- ★新規ポータル
            toZone = "ContinentKyushu",
            islandName = "Town_SE",
            offsetX = 0,
            offsetZ = 0,
            size = Vector3.new(8, 12, 8),
            color = Color3.fromRGB(255, 100, 100),
            label = "→ Kyushu"
        },
	},

	BGM = "rbxassetid://115666507179769",  -- 後でアセットIDに変更
	BGMVolume = 0.2,
}