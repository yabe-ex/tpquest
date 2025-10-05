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

	-- ★修正: Hokkaidoへのポータルのみを残す
	portals = {
		{
            name = "Town_to_Hokkaido",
            toZone = "ContinentHokkaido",
            islandName = "StartTown",
            offsetX = 0, -- Townの中心X座標からのオフセット
            offsetZ = -50, -- Townの中心Z座標からのオフセット
            size = Vector3.new(8, 12, 8),
            color = Color3.fromRGB(200, 200, 255),
            label = "→ Hokkaido"
        },
	},

	BGM = "rbxassetid://115666507179769",  -- 後でアセットIDに変更
	BGMVolume = 0.2,  -- 音量（0.0-1.0）
}