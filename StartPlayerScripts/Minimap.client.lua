-- StarterPlayer/StarterPlayerScripts/Minimap.client.lua
-- ミニマップシステム（ズーム機能・ポータル表示対応版）

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

print("[Minimap] 初期化開始")

-- ズームレベル設定
local ZOOM_LEVELS = {
	{
		name = "詳細",
		scale = 2,           -- 2スタッド/ピクセル
		terrainGrid = 45,    -- 60→45に削減（負荷軽減）
		terrainUpdateInterval = 0.25,  -- 0.15秒 → 0.25秒（更新頻度を下げる）
		iconUpdateInterval = 0.05,
		monsterIconSize = 7,
		portalIconSize = 9,
	},
	{
		name = "中間",
		scale = 4,           -- 4スタッド/ピクセル
		terrainGrid = 50,    -- 50x50グリッド
		terrainUpdateInterval = 0.25,
		iconUpdateInterval = 0.05,
		monsterIconSize = 5,
		portalIconSize = 7,
	},
	{
		name = "広域",
		scale = 8,           -- 8スタッド/ピクセル
		terrainGrid = 40,    -- 40x40グリッド（広域は負荷軽減）
		terrainUpdateInterval = 0.4,
		iconUpdateInterval = 0.08,
		monsterIconSize = 3,
		portalIconSize = 5,
	},
}

local currentZoomLevel = 1

-- 現在の設定を取得
local function getCurrentSettings()
	return ZOOM_LEVELS[currentZoomLevel]
end

-- 基本設定
local MINIMAP_SIZE = 200
local WATER_LEVEL = -15

-- 色設定
local LAND_COLOR = Color3.fromRGB(50, 70, 50)
local SEA_COLOR = Color3.fromRGB(30, 30, 30)
local PLAYER_COLOR = Color3.fromRGB(100, 200, 255)
local MONSTER_COLOR = Color3.fromRGB(255, 50, 50)
local PORTAL_TOWN_COLOR = Color3.fromRGB(255, 200, 100)
local PORTAL_OTHER_COLOR = Color3.fromRGB(200, 100, 255)

-- ScreenGui作成
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MinimapUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- ミニマップの背景フレーム
local minimapFrame = Instance.new("Frame")
minimapFrame.Name = "MinimapFrame"
minimapFrame.Size = UDim2.new(0, MINIMAP_SIZE, 0, MINIMAP_SIZE)
minimapFrame.Position = UDim2.new(0, 20, 1, -MINIMAP_SIZE - 20)
minimapFrame.BackgroundColor3 = SEA_COLOR
minimapFrame.BackgroundTransparency = 0.3
minimapFrame.BorderSizePixel = 2
minimapFrame.BorderColor3 = Color3.fromRGB(255, 255, 255)
minimapFrame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = minimapFrame

-- 地形レイヤー
local terrainLayer = Instance.new("Frame")
terrainLayer.Name = "TerrainLayer"
terrainLayer.Size = UDim2.new(1, 0, 1, 0)
terrainLayer.BackgroundTransparency = 1
terrainLayer.ClipsDescendants = true
terrainLayer.ZIndex = 1
terrainLayer.Parent = minimapFrame

-- タイトル（ズームレベル表示）
local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, 0, 0, 20)
titleLabel.Position = UDim2.new(0, 0, 0, -25)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "MAP [Z: 詳細]"
titleLabel.TextColor3 = Color3.new(1, 1, 1)
titleLabel.TextSize = 14
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.TextStrokeTransparency = 0.5
titleLabel.Parent = minimapFrame

-- プレイヤーアイコン（縦長の矢印型）
-- local playerIconContainer = Instance.new("Frame")
-- playerIconContainer.Name = "PlayerIconContainer"
-- playerIconContainer.Size = UDim2.new(0, 12, 0, 18)
-- playerIconContainer.AnchorPoint = Vector2.new(0.5, 0.5)
-- playerIconContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
-- playerIconContainer.BackgroundTransparency = 1
-- playerIconContainer.ZIndex = 10
-- playerIconContainer.Parent = minimapFrame
local playerIcon = Instance.new("ImageLabel")
playerIcon.Name = "PlayerIcon"
playerIcon.Size = UDim2.new(0, 24, 0, 24) -- サイズは調整可能
playerIcon.AnchorPoint = Vector2.new(0.5, 0.5)
playerIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
playerIcon.BackgroundTransparency = 1
playerIcon.Image = "rbxassetid://137204683713117" -- 上向
-- playerIcon.Image = "rbxassetid://88281133700630"
playerIcon.ImageColor3 = PLAYER_COLOR
playerIcon.ZIndex = 10
playerIcon.Parent = minimapFrame


-- アイコンを格納するフォルダ
local monstersFolder = Instance.new("Folder")
monstersFolder.Name = "MonsterIcons"
monstersFolder.Parent = minimapFrame

local portalsFolder = Instance.new("Folder")
portalsFolder.Name = "PortalIcons"
portalsFolder.Parent = minimapFrame

-- 地形タイルのプール
local terrainTilePool = {}
local activeTiles = {}

local function getTerrainTile()
	for _, tile in ipairs(terrainTilePool) do
		if not tile.Visible then
			tile.Visible = true
			return tile
		end
	end

	local tile = Instance.new("Frame")
	tile.Name = "TerrainTile"
	tile.BackgroundColor3 = LAND_COLOR
	tile.BackgroundTransparency = 0.2
	tile.BorderSizePixel = 0
	tile.ZIndex = 2
	tile.Parent = terrainLayer

	table.insert(terrainTilePool, tile)
	return tile
end

local function hideAllTerrainTiles()
	for _, tile in ipairs(terrainTilePool) do
		tile.Visible = false
	end
	activeTiles = {}
end

-- モンスターアイコンのプール
local monsterIconPool = {}

local function getMonsterIcon(size)
	for _, icon in ipairs(monsterIconPool) do
		if not icon.Visible then
			icon.Visible = true
			icon.Size = UDim2.new(0, size, 0, size)
			return icon
		end
	end

	local icon = Instance.new("Frame")
	icon.Name = "MonsterIcon"
	icon.Size = UDim2.new(0, size, 0, size)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.BackgroundColor3 = MONSTER_COLOR
	icon.BorderSizePixel = 0
	icon.ZIndex = 5
	icon.Parent = monstersFolder

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(1, 0)
	iconCorner.Parent = icon

	table.insert(monsterIconPool, icon)
	return icon
end

local function hideAllMonsterIcons()
	for _, icon in ipairs(monsterIconPool) do
		icon.Visible = false
	end
end

-- ポータルアイコンのプール
local portalIconPool = {}

local function getPortalIcon(size)
	for _, icon in ipairs(portalIconPool) do
		if not icon.Visible then
			icon.Visible = true
			icon.Size = UDim2.new(0, size, 0, size)
			return icon
		end
	end

	local icon = Instance.new("Frame")
	icon.Name = "PortalIcon"
	icon.Size = UDim2.new(0, size, 0, size)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.BackgroundColor3 = PORTAL_OTHER_COLOR
	icon.BorderSizePixel = 0
	icon.ZIndex = 6
	icon.Parent = portalsFolder

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(1, 0)
	iconCorner.Parent = icon

	table.insert(portalIconPool, icon)
	return icon
end

local function hideAllPortalIcons()
	for _, icon in ipairs(portalIconPool) do
		icon.Visible = false
	end
end

-- レイキャストで地形チェック
local function isLand(worldX, worldZ)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {workspace.Terrain}
	params.IgnoreWater = false

	local origin = Vector3.new(worldX, 200, worldZ)
	local direction = Vector3.new(0, -250, 0)

	local result = workspace:Raycast(origin, direction, params)

	if result then
		if result.Material == Enum.Material.Water then
			return false
		end
		if result.Position.Y > WATER_LEVEL then
			return true
		end
	end

	return false
end

-- 地形マップを更新
local lastTerrainUpdate = 0
local lastPlayerPos = nil

local function updateTerrainMap()
	local settings = getCurrentSettings()
	local now = os.clock()

	if now - lastTerrainUpdate < settings.terrainUpdateInterval then
		return
	end

	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local playerPos = hrp.Position

	-- プレイヤーがあまり動いていなければスキップ
	if lastPlayerPos then
		local distance = (playerPos - lastPlayerPos).Magnitude
		-- 詳細モードは移動距離の閾値を上げる（頻繁に更新しない）
		local threshold = (settings.name == "詳細") and 8 or 5
		if distance < threshold then
			return
		end
	end

	lastTerrainUpdate = now
	lastPlayerPos = playerPos

	-- チラつき防止：古いタイルは残したまま、新しいタイルを配置
	local tileSize = MINIMAP_SIZE / settings.terrainGrid
	local newActiveTiles = {}
	local usedTileIndex = 1

	-- 一気に処理（task.wait()なし）
	for gridX = 0, settings.terrainGrid - 1 do
		for gridZ = 0, settings.terrainGrid - 1 do
			local mapX = (gridX + 0.5) / settings.terrainGrid
			local mapZ = (gridZ + 0.5) / settings.terrainGrid

			local relativeX = (mapX - 0.5) * MINIMAP_SIZE * settings.scale
			local relativeZ = (mapZ - 0.5) * MINIMAP_SIZE * settings.scale

			local worldX = playerPos.X + relativeX
			local worldZ = playerPos.Z + relativeZ

			-- 地形チェック
			if isLand(worldX, worldZ) then
				local tile = getTerrainTile()
				tile.Size = UDim2.new(0, tileSize + 1, 0, tileSize + 1)
				tile.Position = UDim2.new(0, gridX * tileSize, 0, gridZ * tileSize)
				table.insert(newActiveTiles, tile)
			end
		end
	end

	-- 古いタイルを非表示（新しいタイルを表示した後）
	for _, tile in ipairs(activeTiles) do
		local isStillActive = false
		for _, newTile in ipairs(newActiveTiles) do
			if tile == newTile then
				isStillActive = true
				break
			end
		end
		if not isStillActive then
			tile.Visible = false
		end
	end

	activeTiles = newActiveTiles

	-- print(("[Minimap] 地形マップ更新完了: 陸=%d"):format(#activeTiles))
end

-- ワールド座標をミニマップ座標に変換
local function worldToMinimap(worldPos, playerPos)
	local settings = getCurrentSettings()

	local relativeX = worldPos.X - playerPos.X
	local relativeZ = worldPos.Z - playerPos.Z

	local minimapX = (relativeX / settings.scale)
	-- local minimapZ = -(relativeZ / settings.scale)
	local minimapZ = (relativeZ / settings.scale)

	local normalizedX = 0.5 + (minimapX / MINIMAP_SIZE)
	local normalizedZ = 0.5 + (minimapZ / MINIMAP_SIZE)

	return normalizedX, normalizedZ
end

local function isInRange(worldPos, playerPos)
	local settings = getCurrentSettings()
	local range = (MINIMAP_SIZE * settings.scale) / 2

	local dx = worldPos.X - playerPos.X
	local dz = worldPos.Z - playerPos.Z
	local distance = math.sqrt(dx * dx + dz * dz)
	return distance <= range
end

-- プレイヤーアイコンの向きを更新
local function updatePlayerRotation_debug()
	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	if not playerIcon then return end

	-- プレイヤーの向きを取得
	local lookVector = hrp.CFrame.LookVector

	-- 8パターン全て試す
	local patterns = {
		{name = "パターン1", calc = function() return math.atan2(lookVector.X, lookVector.Z) end},
		{name = "パターン2", calc = function() return math.atan2(lookVector.Z, lookVector.X) end},
		{name = "パターン3", calc = function() return math.atan2(-lookVector.X, lookVector.Z) end},
		{name = "パターン4", calc = function() return math.atan2(lookVector.X, -lookVector.Z) end},
		{name = "パターン5", calc = function() return math.atan2(-lookVector.Z, lookVector.X) end},
		{name = "パターン6", calc = function() return math.atan2(lookVector.Z, -lookVector.X) end},
		{name = "パターン7", calc = function() return math.atan2(-lookVector.X, -lookVector.Z) end},
		{name = "パターン8", calc = function() return math.atan2(-lookVector.Z, -lookVector.X) end},
	}

	-- パターン1を使用（後で変更できる）
	local angle = patterns[1].calc()
	local degrees = math.deg(angle)

	-- 回転を適用
	playerIcon.Rotation = degrees

	-- 5秒に1回デバッグ情報を表示
	if os.clock() % 5 < 0.1 then
		print(string.format("[Minimap DEBUG] LookVector: (%.2f, %.2f, %.2f)", lookVector.X, lookVector.Y, lookVector.Z))
		print(string.format("[Minimap DEBUG] 角度: %.1f度", degrees))
	end
end

local function updatePlayerRotation_ok()
	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	if not playerIcon then return end

	-- プレイヤーの向きを取得
	local lookVector = hrp.CFrame.LookVector

	local angle = math.atan2(lookVector.X, lookVector.Z)
	local degrees = math.deg(angle)

	-- 回転を適用
	playerIcon.Rotation = degrees
end


local function updatePlayerRotationx()
	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	if not playerIcon then return end

	-- プレイヤーの向きを取得
	local lookVector = hrp.CFrame.LookVector

	local angle = math.atan2(lookVector.X, -lookVector.Z)
	local degrees =  - math.deg(angle)

	-- 回転を適用
	playerIcon.Rotation = - degrees
end

local function updatePlayerRotation_ok_up()
	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	if not playerIcon then return end

	-- プレイヤーの向きを取得
	local lookVector = hrp.CFrame.LookVector

	local angle = math.atan2(-lookVector.X, lookVector.Z)
	local degrees =  - math.deg(angle)

	-- 回転を適用
	playerIcon.Rotation = degrees
end

local function updatePlayerRotation_okl2()
	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	if not playerIcon then return end

	-- プレイヤーの向きを取得
	local lookVector = hrp.CFrame.LookVector

	-- 【変更】atan2の引数順序を変える
	local angle = math.atan2(lookVector.Z, lookVector.X)
	local degrees = math.deg(angle)

	-- そのまま適用
	playerIcon.Rotation = degrees

	if os.clock() % 5 < 0.1 then
		print(string.format("[Minimap DEBUG] LookVector: (%.2f, %.2f, %.2f)", lookVector.X, lookVector.Y, lookVector.Z))
		print(string.format("[Minimap DEBUG] 角度: %.1f度", degrees))
	end

end

local function updatePlayerRotation_x()
	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	if not playerIcon then return end

	local lookVector = hrp.CFrame.LookVector

	-- 角度計算
	local angle = math.atan2(lookVector.Z, lookVector.X)
	local degrees = math.deg(angle)

	-- 90度を加算して補正
	playerIcon.Rotation = degrees - 90
end

-- デバッグ版（方角名も表示）
local function updatePlayerRotation_news()
	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	if not playerIcon then return end

	local lookVector = hrp.CFrame.LookVector

	-- 方角を判定
	local direction = ""
	if math.abs(lookVector.Z) > math.abs(lookVector.X) then
		direction = lookVector.Z < 0 and "北" or "南"
	else
		direction = lookVector.X > 0 and "東" or "西"
	end

	local angle = math.atan2(lookVector.Z, lookVector.X)
	local degrees = math.deg(angle)

	playerIcon.Rotation = degrees

	if os.clock() % 5 < 0.1 then
		print(string.format("[Minimap DEBUG] 方角: %s", direction))
		print(string.format("[Minimap DEBUG] LookVector: (%.2f, %.2f, %.2f)", lookVector.X, lookVector.Y, lookVector.Z))
		print(string.format("[Minimap DEBUG] 角度: %.1f度", degrees))
	end
end

local function updatePlayerRotation()
	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	if not playerIcon then return end

	-- 【変更】CFrameから直接Y軸回転を取得
	local _, yRotation, _ = hrp.CFrame:ToOrientation()
	local degrees = math.deg(yRotation)

	-- 座標系を合わせる（地形マップと同じ反転）
	playerIcon.Rotation = -degrees

	if os.clock() % 1 < 0.1 then
		print(string.format("[DEBUG] Y軸回転: %.1f度 → 表示: %.1f度", degrees, -degrees))
	end
end


-- モンスターアイコンを更新
local lastIconUpdate = 0
local function updateMonsterIcons()
	local settings = getCurrentSettings()
	local now = os.clock()

	if now - lastIconUpdate < settings.iconUpdateInterval then
		return
	end
	lastIconUpdate = now

	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local playerPos = hrp.Position

	hideAllMonsterIcons()

	-- Monstersフォルダから取得
	local monstersWorkspace = workspace:FindFirstChild("Monsters")
	if monstersWorkspace then
		for _, model in ipairs(monstersWorkspace:GetChildren()) do
			if model:IsA("Model") then
				local monsterHrp = model:FindFirstChild("HumanoidRootPart")
				if monsterHrp then
					local monsterPos = monsterHrp.Position
					if isInRange(monsterPos, playerPos) then
						local mapX, mapZ = worldToMinimap(monsterPos, playerPos)
						if mapX >= 0 and mapX <= 1 and mapZ >= 0 and mapZ <= 1 then
							local icon = getMonsterIcon(settings.monsterIconSize)
							icon.Position = UDim2.new(mapX, 0, mapZ, 0)
						end
					end
				end
			end
		end
	end

	-- 旧形式（IsEnemy属性）にも対応
	for _, model in ipairs(workspace:GetChildren()) do
		if model:IsA("Model") and model:GetAttribute("IsEnemy") then
			local monsterHrp = model:FindFirstChild("HumanoidRootPart")
			if monsterHrp then
				local monsterPos = monsterHrp.Position
				if isInRange(monsterPos, playerPos) then
					local mapX, mapZ = worldToMinimap(monsterPos, playerPos)
					if mapX >= 0 and mapX <= 1 and mapZ >= 0 and mapZ <= 1 then
						local icon = getMonsterIcon(settings.monsterIconSize)
						icon.Position = UDim2.new(mapX, 0, mapZ, 0)
					end
				end
			end
		end
	end

	-- プレイヤーの向きを更新
	updatePlayerRotation()
end

-- ポータルアイコンを更新
local portalDebugDone = false
local function updatePortalIcons()
	local settings = getCurrentSettings()
	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local playerPos = hrp.Position

	hideAllPortalIcons()

	-- デバッグ: ポータルの配置場所を確認
	if not portalDebugDone then
		print("[Minimap DEBUG] ポータル検索開始")

		-- workspace.Worldの中身を確認
		local worldFolder = workspace:FindFirstChild("World")
		if worldFolder then
			print("[Minimap DEBUG] workspace.World発見: " .. #worldFolder:GetChildren() .. "個のオブジェクト")
			local portalCount = 0
			for _, obj in ipairs(worldFolder:GetChildren()) do
				local toZone = obj:GetAttribute("ToZone")
				if toZone then
					portalCount = portalCount + 1
					print("[Minimap DEBUG]   - " .. obj.Name .. " → " .. toZone .. " (Pos: " .. tostring(obj.Position) .. ")")
				end
			end
			print("[Minimap DEBUG] ポータル総数: " .. portalCount)
		else
			print("[Minimap DEBUG] workspace.Worldが見つかりません")
		end

		portalDebugDone = true
	end

	-- workspace.Worldからポータルを取得
	local worldFolder = workspace:FindFirstChild("World")
	if worldFolder then
		for _, portal in ipairs(worldFolder:GetChildren()) do
			-- ToZone属性があるものをポータルとして認識
			if portal:IsA("BasePart") and portal:GetAttribute("ToZone") then
				local portalPos = portal.Position
				if isInRange(portalPos, playerPos) then
					local mapX, mapZ = worldToMinimap(portalPos, playerPos)
					if mapX >= 0 and mapX <= 1 and mapZ >= 0 and mapZ <= 1 then
						local icon = getPortalIcon(settings.portalIconSize)
						icon.Position = UDim2.new(mapX, 0, mapZ, 0)

						-- Townへのポータルかそれ以外かで色分け
						local toZone = portal:GetAttribute("ToZone")
						if toZone == "StartTown" then
							-- Townへのポータル → オレンジ
							icon.BackgroundColor3 = PORTAL_TOWN_COLOR
						else
							-- それ以外（他の大陸へ） → ポータルの色またはデフォルト紫
							icon.BackgroundColor3 = portal.Color or PORTAL_OTHER_COLOR
						end
					end
				end
			end
		end
	end
end

-- ズーム切り替え
local function changeZoomLevel(delta)
	currentZoomLevel = math.clamp(currentZoomLevel + delta, 1, #ZOOM_LEVELS)
	local settings = getCurrentSettings()

	titleLabel.Text = "MAP [Z: " .. settings.name .. "]"

	-- 地形マップを即座に更新
	lastTerrainUpdate = 0
	lastPlayerPos = nil

	print("[Minimap] ズーム変更: " .. settings.name)
end

-- マウスホイール入力
UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local mousePos = UserInputService:GetMouseLocation()
		local framePos = minimapFrame.AbsolutePosition
		local frameSize = minimapFrame.AbsoluteSize

		if mousePos.X >= framePos.X and mousePos.X <= framePos.X + frameSize.X and
			mousePos.Y >= framePos.Y and mousePos.Y <= framePos.Y + frameSize.Y then
			if input.Position.Z > 0 then
				changeZoomLevel(-1)
			else
				changeZoomLevel(1)
			end
		end
	end
end)

-- Zキー入力
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.Z then
		local nextLevel = currentZoomLevel + 1
		if nextLevel > #ZOOM_LEVELS then
			nextLevel = 1
		end
		changeZoomLevel(nextLevel - currentZoomLevel)
	end
end)

-- メイン更新ループ
RunService.Heartbeat:Connect(function()
	updateTerrainMap()
	updateMonsterIcons()
	updatePlayerRotation()
end)

-- ポータル専用の高速更新ループ（独立）
task.spawn(function()
	while true do
		task.wait(0.1)  -- 0.1秒ごとに更新（高速）
		updatePortalIcons()
	end
end)

-- 初期化時に即座にポータルを検索
task.spawn(function()
	task.wait(0.5)  -- 少し待ってからポータル検索
	updatePortalIcons()
end)

-- workspace.Worldの変化を監視（ポータル追加時に即反映）
task.spawn(function()
	local worldFolder = workspace:WaitForChild("World", 10)
	if worldFolder then
		worldFolder.ChildAdded:Connect(function(child)
			if child:IsA("BasePart") and child:GetAttribute("ToZone") then
				print("[Minimap] 新しいポータル検出: " .. child.Name)
				task.wait(0.1)
				updatePortalIcons()
			end
		end)
	end
end)

print("[Minimap] 初期化完了（ズーム機能付き）")