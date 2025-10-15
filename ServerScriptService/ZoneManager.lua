-- ServerScriptService/ZoneManager.lua
-- あなたが送ってくれた版をベースに、DisplayConfig注入＋paths単体互換のみ最小改修

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- フィールド生成ユーティリティ（ラベルや道の生成で使用）
local FieldGen = require(ReplicatedStorage:WaitForChild("FieldGen"))

local ZoneManager = {}

ZoneManager.ActiveZones = {}
ZoneManager.PlayerZones = {}

-- 島と大陸の設定を読み込み
local IslandsRegistry = require(ReplicatedStorage.Islands.Registry)
local ContinentsRegistry = require(ReplicatedStorage.Continents.Registry)

-- 島の設定をマップ化
local Islands = {}
for _, island in ipairs(IslandsRegistry) do
	Islands[island.name] = island
end

-- 大陸の設定をマップ化
local Continents = {}
for _, continent in ipairs(ContinentsRegistry) do
	if continent and continent.name then
		Continents[continent.name] = continent
	else
		warn("[ZoneManager] 名前が設定されていない大陸定義をスキップしました")
	end
end

print("[ZoneManager] 初期化完了。島数:", #IslandsRegistry, "大陸数:", #ContinentsRegistry)

-- ▼ 追加：DisplayConfig を任意読み込み（無くても動作継続）
local DisplayConfig
do
	local ok, cfg = pcall(function()
		local cfgFolder = ReplicatedStorage:FindFirstChild("Config")
		if not cfgFolder then
			return nil
		end
		local m = cfgFolder:FindFirstChild("DisplayConfig")
		if not m then
			return nil
		end
		return require(m)
	end)
	if ok then
		DisplayConfig = cfg
	else
		DisplayConfig = nil
	end
end

-- ZoneChangeイベントを作成（クライアントへの通知用）
local ZoneChangeEvent = ReplicatedStorage:FindFirstChild("ZoneChange")
if not ZoneChangeEvent then
	ZoneChangeEvent = Instance.new("RemoteEvent")
	ZoneChangeEvent.Name = "ZoneChange"
	ZoneChangeEvent.Parent = ReplicatedStorage
	print("[ZoneManager] ZoneChangeイベントを作成しました")
end

-- ゾーンが大陸かチェック
local function isContinent(zoneName)
	return Continents[zoneName] ~= nil
end

-- ゾーンが島かチェック (Townが大陸化されたため、この関数は実質未使用に)
local function isIsland(zoneName)
	return Islands[zoneName] ~= nil and not isContinent(zoneName)
end

-- プレイヤーのゾーンを更新 (ワープポータルで使用)
local function updatePlayerZone(player, newZone)
	local oldZone = ZoneManager.PlayerZones[player]

	if oldZone == newZone then
		return
	end

	-- 古いゾーンから出た
	if oldZone then
		print(("[ZoneManager] %s が %s から出ました"):format(player.Name, oldZone))
		ZoneChangeEvent:FireClient(player, oldZone, false)
	end

	-- 新しいゾーンに入った
	if newZone then
		print(("[ZoneManager] %s が %s に入りました"):format(player.Name, newZone))
		ZoneManager.PlayerZones[player] = newZone
		ZoneChangeEvent:FireClient(player, newZone, true)
	else
		ZoneManager.PlayerZones[player] = nil
	end
end

-- 島ラベル（BillboardGui）生成
local function createIslandLabel(cfg)
	if not (cfg and cfg.showIslandLabel) then
		return
	end

	local worldFolder = workspace:FindFirstChild("World")
	if not worldFolder then
		worldFolder = Instance.new("Folder")
		worldFolder.Name = "World"
		worldFolder.Parent = workspace
	end

	-- 重複掃除（同名があれば消す）
	local anchorName = (cfg.name or "Island") .. "_LabelAnchor"
	local old = worldFolder:FindFirstChild(anchorName)
	if old then
		old:Destroy()
	end

	-- 透明アンカー
	local anchor = Instance.new("Part")
	anchor.Name = anchorName
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Transparency = 1

	local baseY = cfg.baseY or 0
	local thickness = cfg.thickness or 0
	local labelOffset = cfg.labelOffsetY or 6
	anchor.Position = Vector3.new(cfg.centerX, baseY + thickness + labelOffset, cfg.centerZ)
	anchor.Parent = worldFolder

	-- BillboardGui（Part配下に置けば Adornee 不要）
	local bb = Instance.new("BillboardGui")
	bb.Name = "Nameplate"
	bb.AlwaysOnTop = true
	bb.MaxDistance = cfg.labelMaxDistance or 5000
	bb.Size = UDim2.fromOffset(260, 72)
	bb.Parent = anchor

	local bg = Instance.new("Frame")
	bg.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
	bg.BackgroundTransparency = (cfg._labelBgTrans ~= nil) and cfg._labelBgTrans or 0.35
	bg.BorderSizePixel = 0
	bg.Size = UDim2.fromScale(1, 1)
	bg.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = bg

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextWrapped = true
	label.RichText = false
	label.Font = cfg._labelFont or Enum.Font.GothamBold
	label.TextScaled = false
	label.TextSize = cfg._labelTextSize or 16
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.5
	label.Text = string.format("%s\n(%.1f, %.1f)", tostring(cfg.name or "Island"), cfg.centerX, cfg.centerZ)
	label.Parent = bg

	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	pad.Parent = bg
end

-- 大陸をロード（複数の島と橋を生成）
local function loadContinent(continentName)
	local continent = Continents[continentName]
	if not continent then
		warn(("[ZoneManager] 大陸 '%s' が見つかりません"):format(continentName))
		return false
	end

	print(("[ZoneManager] 大陸生成開始: %s"):format(continentName))

	-- ▼ 追加：DisplayConfig によるラベル表示可否＆既定値の取得
	local showForThisContinent = false
	local labelParams = nil
	if DisplayConfig and DisplayConfig.isEnabledFor and DisplayConfig.getParamsFor then
		showForThisContinent = DisplayConfig.isEnabledFor(continent.name)
		labelParams = DisplayConfig.getParamsFor(continent.name)
	end

	-- 含まれる全ての島を生成
	for _, islandName in ipairs(continent.islands) do
		local islandConfig = Islands[islandName]
		if islandConfig then
			-- ▼ 追加：DisplayConfigが有効なら各島にラベル設定を注入（FieldGen.generateIsland が参照）
			if showForThisContinent and labelParams then
				islandConfig.showIslandLabel = (labelParams.showIslandLabel ~= false)
				islandConfig.labelOffsetY = labelParams.labelOffsetY
				islandConfig.labelMaxDistance = labelParams.labelMaxDistance
				-- 見た目パラメータ（任意）
				islandConfig._labelFont = labelParams.font
				islandConfig._labelTextSize = labelParams.textSize
				islandConfig._labelBgTrans = labelParams.backgroundTransparency
			end

			print(("[ZoneManager]   - 島を生成: %s"):format(islandName))

			FieldGen.generateIsland(islandConfig)
		else
			warn(
				("[ZoneManager]   - 島が見つかりません: %s (Island/Registryを確認してください)"):format(
					islandName
				)
			)
		end
	end

	-- 橋を生成
	if continent.bridges then
		for _, bridgeConfig in ipairs(continent.bridges) do
			local fromIsland = Islands[bridgeConfig.fromIsland]
			local toIsland = Islands[bridgeConfig.toIsland]

			if fromIsland and toIsland then
				print(("[ZoneManager]   - 橋を生成: %s"):format(bridgeConfig.name))
				FieldGen.generateBridge(fromIsland, toIsland, bridgeConfig)
			else
				warn(("[ZoneManager]   - 橋の生成失敗: %s"):format(bridgeConfig.name))
			end
		end
	end

	ZoneManager.ActiveZones[continentName] = {
		config = continent,
		loadedAt = os.time(),
	}

	-- 追加オブジェクト
	do
		local RS = game:GetService("ReplicatedStorage")
		local FieldGenLocal = require(RS:WaitForChild("FieldGen"))
		if continent.fieldObjects and #continent.fieldObjects > 0 then
			print(("[ZoneManager] 追加オブジェクトを配置: %d 個"):format(#continent.fieldObjects))
			FieldGenLocal.placeFieldObjects(continent.name, continent.fieldObjects) -- player引数なし
		end
	end

	-- 道（paths）…単一オブジェクト互換あり
	do
		local RS = game:GetService("ReplicatedStorage")
		local FieldGenLocal = require(RS:WaitForChild("FieldGen"))

		if continent.paths then
			local arr = continent.paths
			if #arr == 0 and arr.points then
				-- 単一オブジェクト形式に対応（後方互換）
				arr = { continent.paths }
			end
			if #arr > 0 then
				print(" 道をひきます")
				FieldGenLocal.buildPaths(continent.name, arr)
			end
		end
	end

	print(("[ZoneManager] 大陸生成完了: %s"):format(continentName))
	return true
end

-- ゾーンをロード（島または大陸をロード）
function ZoneManager.LoadZone(zoneName)
	if ZoneManager.ActiveZones[zoneName] then
		print(("[ZoneManager] %s は既に生成済みです"):format(zoneName))
		return true
	end

	if isContinent(zoneName) then
		return loadContinent(zoneName)
	else
		-- 島単独ロードは未対応（大陸経由で生成）
		warn(
			("[ZoneManager] ゾーン '%s' は大陸ではありません。ロードをスキップしました。"):format(
				zoneName
			)
		)
		return false
	end
end

-- ゾーンをアンロード
function ZoneManager.UnloadZone(zoneName)
	if not ZoneManager.ActiveZones[zoneName] then
		return
	end

	print(("[ZoneManager] ゾーン削除開始: %s"):format(zoneName))

	local terrain = workspace.Terrain
	local configsToUnload = {}

	-- 大陸としてのみ処理
	if isContinent(zoneName) then
		-- 大陸の場合は含まれる全ての島を削除
		local continent = Continents[zoneName]
		for _, islandName in ipairs(continent.islands) do
			table.insert(configsToUnload, Islands[islandName])
		end
	else
		warn(
			("[ZoneManager] ゾーン '%s' は大陸ではありません。アンロードをスキップしました。"):format(
				zoneName
			)
		)
		return
	end

	-- 各島の地形を削除
	for _, config in ipairs(configsToUnload) do
		if config then
			local halfSize = config.sizeXZ / 2 + 50
			local region = Region3.new(
				Vector3.new(config.centerX - halfSize, config.baseY - 50, config.centerZ - halfSize),
				Vector3.new(config.centerX + halfSize, config.baseY + 100, config.centerZ + halfSize)
			)
			region = region:ExpandToGrid(4)
			terrain:FillRegion(region, 4, Enum.Material.Air)

			-- マーカ削除は FieldGen.lua 側で行うためZoneManagerからは削除
		end
	end

	-- モンスター削除
	for _, model in ipairs(workspace:GetChildren()) do
		if model:IsA("Model") and model:GetAttribute("IsEnemy") then
			local spawnZone = model:GetAttribute("SpawnZone")
			if spawnZone == zoneName then
				model:Destroy()
			end
		end
	end

	ZoneManager.ActiveZones[zoneName] = nil
	print(("[ZoneManager] ゾーン削除完了: %s"):format(zoneName))
end

-- プレイヤーをワープ
function ZoneManager.WarpPlayerToZone(player, zoneName)
	print(("[ZoneManager] %s を %s にワープ中..."):format(player.Name, zoneName))

	-- ワープ先に地形がない場合はロード
	ZoneManager.LoadZone(zoneName)

	local character = player.Character
	if not character then
		warn(("[ZoneManager] %s のキャラクターが見つかりません"):format(player.Name))
		return false
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end

	-- ワープ先の座標を決定 (常に大陸の最初の島を参照するように統一)
	local targetX, targetZ, baseY, hillAmplitude

	if isContinent(zoneName) then
		-- 大陸の場合（Townも含む）
		local continent = Continents[zoneName]
		local firstIslandName = continent.islands[1]
		local firstIsland = Islands[firstIslandName]

		if not firstIsland then
			warn(
				("[ZoneManager] 大陸 '%s' の最初の島 '%s' が見つかりません。"):format(
					zoneName,
					firstIslandName
				)
			)
			return false
		end

		targetX = firstIsland.centerX
		targetZ = firstIsland.centerZ
		baseY = firstIsland.baseY
		hillAmplitude = firstIsland.hillAmplitude or 20
	else
		warn(
			("[ZoneManager] ゾーン '%s' は大陸ではありません。ワープできません。"):format(
				zoneName
			)
		)
		return false
	end

	-- 十分に高い位置からレイキャスト
	local FieldGenLocal = require(ReplicatedStorage:WaitForChild("FieldGen"))
	local rayStartY = baseY + hillAmplitude + 100
	local groundY = FieldGenLocal.raycastGroundY(targetX, targetZ, rayStartY)

	local spawnY
	if groundY then
		spawnY = groundY + 5
		print(("[ZoneManager] 地面検出成功: Y=%.1f"):format(groundY))
	else
		-- 安全な高度：baseY + hillAmplitude * 0.6 + 10 に固定
		spawnY = baseY + (hillAmplitude * 0.6) + 10
		warn(("[ZoneManager] 地面検出失敗、予想高度使用: Y=%.1f"):format(spawnY))
	end

	hrp.CFrame = CFrame.new(targetX, spawnY, targetZ)

	updatePlayerZone(player, zoneName)

	print(
		("[ZoneManager] %s を %s にワープ完了 (%.1f, %.1f, %.1f)"):format(
			player.Name,
			zoneName,
			targetX,
			spawnY,
			targetZ
		)
	)
	return true
end

function ZoneManager.GetPlayerZone(player)
	return ZoneManager.PlayerZones[player]
end

-- プレイヤーが退出した時の処理
Players.PlayerRemoving:Connect(function(player)
	local oldZone = ZoneManager.PlayerZones[player]
	if oldZone then
		print(("[ZoneManager] %s が退出しました。ゾーン: %s"):format(player.Name, oldZone))
		ZoneManager.PlayerZones[player] = nil
	end
end)

return ZoneManager
