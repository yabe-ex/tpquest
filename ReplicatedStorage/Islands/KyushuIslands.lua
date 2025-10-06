-- ===== ./ReplicatedStorage/Islands/KyushuIslands.lua (新規) =====
return {
	-- 北部
	{
        name = "Kyushu_N1", centerX = 750, centerZ = 50, sizeXZ = 150, baseY = 20, thickness = 10, grid = 10,
        hillAmplitude = 25, hillScale = 120, seed = 80001, generateOcean = false, baseMaterial = Enum.Material.Basalt,
    },
    -- 中央
	{
        name = "Kyushu_C1", centerX = 800, centerZ = 0, sizeXZ = 180, baseY = 20, thickness = 10, grid = 10,
        hillAmplitude = 30, hillScale = 140, seed = 80002, generateOcean = false, baseMaterial = Enum.Material.Basalt,
    },
    -- 南部
	{
        name = "Kyushu_S1", centerX = 850, centerZ = -50, sizeXZ = 150, baseY = 20, thickness = 10, grid = 10,
        hillAmplitude = 25, hillScale = 120, seed = 80003, generateOcean = false, baseMaterial = Enum.Material.Basalt,
    },
    -- 北東部
	{
        name = "Kyushu_NE1", centerX = 850, centerZ = 50, sizeXZ = 100, baseY = 20, thickness = 10, grid = 10,
        hillAmplitude = 20, hillScale = 100, seed = 80004, generateOcean = false, baseMaterial = Enum.Material.Basalt,
    },
    -- 南西部
	{
        name = "Kyushu_SW1", centerX = 750, centerZ = -50, sizeXZ = 100, baseY = 20, thickness = 10, grid = 10,
        hillAmplitude = 20, hillScale = 100, seed = 80005, generateOcean = false, baseMaterial = Enum.Material.Basalt,
    },
    -- 西部 (海あり)
	{
        name = "Kyushu_W1", centerX = 700, centerZ = 0, sizeXZ = 100, baseY = 20, thickness = 10, grid = 10,
        hillAmplitude = 15, hillScale = 80, seed = 80006, generateOcean = true, oceanRadius = 1000, baseMaterial = Enum.Material.Basalt,
    },
}