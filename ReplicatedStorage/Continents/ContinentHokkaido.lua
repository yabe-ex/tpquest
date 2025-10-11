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

	fieldObjects = {
		{
			model = "Tree1",
			position = {3237.0, 22.0, -10.8},
			size = 1.5,
			rotation = {0, 0, 0},
			stickToGround = true,   -- 省略可（trueが既定）
			groundOffset  = 0.15,   -- 芝生で少し浮かせたい時
			alignToSlope  = true,  -- 斜面に木を傾けたくないならfalse
		},
		{
			model = "Tree1",
			position = {3092.5, 9.1, -175.5},
			size = 1.0,
			rotation = {0, 0, 0},
			stickToGround = true,   -- 省略可（trueが既定）
			groundOffset  = 0.15,   -- 芝生で少し浮かせたい時
			alignToSlope  = true,  -- 斜面に木を傾けたくないならfalse
		},

		{
			model = "Tree1",
			position = {3118.2, 7.3, -182.6},
			size = 1.0,
			rotation = {0, 30, 0},
			stickToGround = true,   -- 省略可（trueが既定）
			groundOffset  = 0.15,   -- 芝生で少し浮かせたい時
			alignToSlope  = true,  -- 斜面に木を傾けたくないならfalse
		},

		{
			model = "Small House",
			position = {3080.8, 32.0, -162.8},
			size = 1.8,
			rotation = {0, 180, 0},
			stickToGround = false,   -- 省略可（trueが既定）
			groundOffset  = 0.15,   -- 芝生で少し浮かせたい時
			alignToSlope  = false,  -- 斜面に木を傾けたくないならfalse
		},

		{
			model = "Chest",
			position = {3387.2, 3.4, 178.2},
			size = 1.0,
			rotation = {0, 0, 0},
			stickToGround = true,   -- 省略可（trueが既定）
			groundOffset  = 0,   -- 芝生で少し浮かせたい時
			alignToSlope  = true,  -- 斜面に木を傾けたくないならfalse
		},
	},

	paths = {
		{
			name = "MainRoad01",
			points = {                 -- 制御点：ワールド座標（YはだいたいでOK）
{3028.7, 16.1, 79.4},
{3077.0, 16.1, 119.9},
{3190.9, 16.1, 92.3},
{3276.1, 16.1, 100.2},
{3367.9, 16.0, 77.1},
			},
			width = 24,                -- 道の幅（stud）
			method = "terrain",        -- "terrain"（地形を塗る） or "parts"（パーツ敷き）
			material = Enum.Material.Ground,  -- method="terrain"時の塗り材質
			step = 3,                  -- サンプリング間隔（小さいほど滑らか＆重い）
			alignToSlope = false,      -- 斜面に道面を傾けるか（見た目：true、歩きやすさ：false）
			groundOffset = 4.8,       -- めり込み回避の微小オフセット
		},
	},

	BGM = "rbxassetid://115666507179769",  -- 後でアセットIDに変更
	BGMVolume = 0.2,  -- 音量（0.0-1.0）
}