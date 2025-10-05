-- ReplicatedStorage/FieldGen (最適化版)
-- パフォーマンスを大幅に改善した地形生成エンジン

local FieldGen = {}

-- ノイズ関数（変更なし）
local function noise2D(x, z, scale)
	local s = (x / scale + z / scale * 57)
	return (math.sin(s * 12.9898) * 43758.5453) % 1
end

local function smoothNoise(x, z, scale)
	local intX, intZ = math.floor(x / scale), math.floor(z / scale)
	local fracX, fracZ = (x / scale) - intX, (z / scale) - intZ

	local v1 = noise2D(intX, intZ, 1)
	local v2 = noise2D(intX + 1, intZ, 1)
	local v3 = noise2D(intX, intZ + 1, 1)
	local v4 = noise2D(intX + 1, intZ + 1, 1)

	local i1 = v1 * (1 - fracX) + v2 * fracX
	local i2 = v3 * (1 - fracX) + v4 * fracX

	return i1 * (1 - fracZ) + i2 * fracZ
end

-- 【最適化1】バッチ生成システム
local function fillTerrainBatch(terrain, blocks)
	local batchSize = 100  -- 一度に処理する数
	local totalBlocks = #blocks

	for i = 1, totalBlocks, batchSize do
		local endIdx = math.min(i + batchSize - 1, totalBlocks)

		for j = i, endIdx do
			local block = blocks[j]
			terrain:FillBlock(block.cframe, block.size, block.material)
		end

		-- サーバーの負荷分散
		if i % 500 == 0 then
			task.wait()
			print(("[FieldGen] 進行状況: %d/%d (%.1f%%)"):format(i, totalBlocks, i/totalBlocks*100))
		end
	end
end

-- ReplicatedStorage/FieldGen.lua
-- 【修正】generateIsland 関数全体
function FieldGen.generateIsland(config)
	local terrain = workspace.Terrain

	local cfg = {
		name = config.name or "Island",
		centerX = config.centerX or 0,
		centerZ = config.centerZ or 0,
		sizeXZ = config.sizeXZ or 500,
		baseY = config.baseY or 0,
		thickness = config.thickness or 10,
		hillAmplitude = config.hillAmplitude or 20,
		hillScale = config.hillScale or 150,
		seed = config.seed or 12345,
		generateOcean = config.generateOcean ~= false,
		oceanRadius = config.oceanRadius or 1500,
		grid = config.grid or 12,

        -- 【修正点 A】新しいプロパティを取得。デフォルトは Grass に設定
        baseMaterial = config.baseMaterial or Enum.Material.Grass,
	}

	print(("[FieldGen] 生成開始: %s at (%.0f, %.0f, Material: %s)"):format(cfg.name, cfg.centerX, cfg.centerZ, tostring(cfg.baseMaterial)))

	math.randomseed(cfg.seed)

	local halfSize = cfg.sizeXZ / 2
	local oceanY = cfg.baseY - 10
	local cliffHeight = oceanY + 8

	-- 【重要】ブロックを配列に溜めてからバッチ処理
	local terrainBlocks = {}
	local waterBlocks = {}

	-- 地形ブロックを準備
	for x = -halfSize, halfSize, cfg.grid do
		for z = -halfSize, halfSize, cfg.grid do
			local worldX = cfg.centerX + x
			local worldZ = cfg.centerZ + z

			local distFromCenter = math.sqrt(x*x + z*z)
			local normalizedDist = distFromCenter / halfSize
			local edgeFade = math.max(0, 1 - normalizedDist * 1.2)

			if edgeFade > 0 then
				local height = smoothNoise(worldX + cfg.seed, worldZ + cfg.seed, cfg.hillScale)
				local hillY = cfg.baseY + (height * cfg.hillAmplitude * edgeFade)
				local targetY = math.max(hillY, cliffHeight)

				table.insert(terrainBlocks, {
					cframe = CFrame.new(worldX, targetY - cfg.thickness/2, worldZ),
					size = Vector3.new(cfg.grid, cfg.thickness, cfg.grid),

                    -- 【修正点 B】ハードコードされた Material を設定値に置き換え
					material = cfg.baseMaterial
				})
			end
		end
	end

	print(("[FieldGen] 地形ブロック数: %d"):format(#terrainBlocks))
	fillTerrainBatch(terrain, terrainBlocks)

	-- 海の生成
	if cfg.generateOcean then
		local oceanGrid = 20
		local oceanHalfSize = cfg.oceanRadius / 2
		local maxDistWithTerrain = halfSize * 0.8

		for x = -oceanHalfSize, oceanHalfSize, oceanGrid do
			for z = -oceanHalfSize, oceanHalfSize, oceanGrid do
				local dist = math.sqrt(x*x + z*z)
				if dist > maxDistWithTerrain then
					table.insert(waterBlocks, {
						cframe = CFrame.new(cfg.centerX + x, oceanY, cfg.centerZ + z),
						size = Vector3.new(oceanGrid, 20, oceanGrid),
						material = Enum.Material.Water
					})
				end
			end
		end

		print(("[FieldGen] 海ブロック数: %d"):format(#waterBlocks))
		fillTerrainBatch(terrain, waterBlocks)
	end

	-- マーカー作成
	local worldFolder = workspace:FindFirstChild("World")
	if not worldFolder then
		worldFolder = Instance.new("Folder")
		worldFolder.Name = "World"
		worldFolder.Parent = workspace
	end

	local marker = Instance.new("Part")
	marker.Name = cfg.name .. "_Center"
	marker.Size = Vector3.new(10, 1, 10)
	marker.Position = Vector3.new(cfg.centerX, cfg.baseY + 5, cfg.centerZ)
	marker.Anchored = true
	marker.CanCollide = false
	marker.Transparency = 0.5
	marker.BrickColor = BrickColor.new("Bright blue")
	marker.Parent = worldFolder

	print(("[FieldGen] 完了: %s"):format(cfg.name))
end

-- レイキャスト（変更なし）
function FieldGen.raycastGroundY(x, z, startY)
	startY = startY or 500

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {workspace.Terrain}
	params.IgnoreWater = false

	local origin = Vector3.new(x, startY, z)
	local direction = Vector3.new(0, -startY - 500, 0)

	local result = workspace:Raycast(origin, direction, params)
	return result and result.Position.Y or nil
end

-- 橋の生成（バッチ処理版）
function FieldGen.generateBridge(fromIsland, toIsland, config)
	local terrain = workspace.Terrain

	local cfg = {
		name = config.name or "Bridge",
		width = config.width or 20,
		height = config.height or 5,
		thickness = config.thickness or 5,
	}

	print(("[FieldGen] 橋を生成中: %s"):format(cfg.name))

	local x1, z1 = fromIsland.centerX, fromIsland.centerZ
	local x2, z2 = toIsland.centerX, toIsland.centerZ

	local dx = x2 - x1
	local dz = z2 - z1
	local distance = math.sqrt(dx*dx + dz*dz)

	local bridgeY = ((fromIsland.baseY or 0) + (toIsland.baseY or 0)) / 2 + cfg.height
	local segments = math.ceil(distance / 10)

	local bridgeBlocks = {}

	for i = 0, segments do
		local t = i / segments
		local x = x1 + dx * t
		local z = z1 + dz * t

		local perpX = -dz / distance
		local perpZ = dx / distance

		for w = -cfg.width/2, cfg.width/2, 8 do
			local worldX = x + perpX * w
			local worldZ = z + perpZ * w

			table.insert(bridgeBlocks, {
				cframe = CFrame.new(worldX, bridgeY, worldZ),
				size = Vector3.new(8, cfg.thickness, 8),
				material = Enum.Material.Slate
			})
		end
	end

	fillTerrainBatch(terrain, bridgeBlocks)
	print(("[FieldGen] 橋生成完了: %s (距離: %.1f)"):format(cfg.name, distance))
end

return FieldGen