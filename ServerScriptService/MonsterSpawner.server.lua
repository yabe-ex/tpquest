-- ServerScriptService/MonsterSpawner.server.lua
-- ゾーン対応版モンスター配置システム（新AI行動システム対応版 + デバッグログ強化版）

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- ★【新】AIBehaviorSystem の読み込み
local AIBehaviorSystem = require(ReplicatedStorage:WaitForChild("AIBehaviorSystem"))

local FieldGen = require(ReplicatedStorage:WaitForChild("FieldGen"))
local ZoneManager = require(script.Parent.ZoneManager)

local SharedState = require(ReplicatedStorage:WaitForChild("SharedState"))
local GameEvents = require(ReplicatedStorage:WaitForChild("GameEvents"))
local ContinentsRegistry = require(ReplicatedStorage.Continents.Registry)

-- BattleSystem読込（オプショナル）
local BattleSystem = nil
local battleSystemScript = script.Parent:FindFirstChild("BattleSystem")
if battleSystemScript then
	local success, result = pcall(function()
		return require(battleSystemScript)
	end)
	if success then
		BattleSystem = result
		print("[MonsterSpawner] BattleSystem読み込み成功")
	else
		warn("[MonsterSpawner] BattleSystem読み込み失敗:", result)
	end
else
	warn("[MonsterSpawner] BattleSystemが見つかりません - バトル機能は無効です")
end

-- Registry読込
local MonstersFolder = ReplicatedStorage:WaitForChild("Monsters")
local Registry = require(MonstersFolder:WaitForChild("Registry"))

print("[MonsterSpawner] ★【デバッグ】Registry 読み込み完了")
print(("[MonsterSpawner] ★【デバッグ】Registry 内のモンスター数: %d"):format(#Registry))
for i, def in ipairs(Registry) do
	print(("[MonsterSpawner] ★【デバッグ】  [%d] %s"):format(i, def.Name or "Unknown"))
end

-- 島の設定を読み込み
local IslandsRegistry = require(ReplicatedStorage.Islands.Registry)
local Islands = {}
for _, island in ipairs(IslandsRegistry) do
	Islands[island.name] = island
end

print("[MonsterSpawner] ★【デバッグ】Islands 読み込み完了")
print(("[MonsterSpawner] ★【デバッグ】Islands 内の島数: %d"):format(#IslandsRegistry))
for i, island in ipairs(IslandsRegistry) do
	print(("[MonsterSpawner] ★【デバッグ】  [%d] %s"):format(i, island.name))
end

-- グローバル変数
local ActiveMonsters = {}
local UpdateInterval = 0.05
local MonsterCounts = {}
local TemplateCache = {}
local RespawnQueue = {}

-- ★【新】AIState を AIBehaviorSystem から取得
local AIState = AIBehaviorSystem.AIState

-- 安全地帯チェック
local function isSafeZone(zoneName)
	local island = Islands[zoneName]
	if island and island.safeZone then
		return true
	end
	return false
end

-- ユーティリティ関数
local function resolveTemplate(pathArray: { string }): Model?
	local node: Instance = game
	for _, seg in ipairs(pathArray) do
		print(
			("[MonsterSpawner] ★【デバッグ】テンプレート解決中: %s > %s"):format(tostring(node), seg)
		)
		node = node:FindFirstChild(seg)
		if not node then
			print(
				("[MonsterSpawner] ★【デバッグ】テンプレート解決失敗: %s が見つかりません"):format(
					seg
				)
			)
			return nil
		end
	end
	print(("[MonsterSpawner] ★【デバッグ】テンプレート解決成功: %s"):format(tostring(node)))
	return (node and node:IsA("Model")) and node or nil
end

local function ensureHRP(model: Model): BasePart?
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		if not model.PrimaryPart then
			model.PrimaryPart = hrp
		end
		print(("[MonsterSpawner] ★【デバッグ】HRP確認OK: %s"):format(model.Name))
		return hrp
	end
	print(("[MonsterSpawner] ★【デバッグ】HRP確認失敗: %s"):format(model.Name))
	return nil
end

-- 島から大陸名を逆引きするマップを作成
local IslandToContinentMap = {}
do
	for _, continent in ipairs(ContinentsRegistry) do
		if continent and continent.islands then
			for _, islandName in ipairs(continent.islands) do
				IslandToContinentMap[islandName] = continent.name
				print(("[MonsterSpawner] マップ: %s -> %s"):format(islandName, continent.name))
			end
		end
	end
	local mapCount = 0
	for _ in pairs(IslandToContinentMap) do
		mapCount = mapCount + 1
	end

	print("[MonsterSpawner] IslandToContinentMap 初期化完了 (" .. mapCount .. " 個)")
end

-- 島名から大陸名を取得
local function getContinentNameFromIsland(islandName)
	local result = IslandToContinentMap[islandName]
	if not result then
		warn(
			("[MonsterSpawner] 警告: 島 '%s' が IslandToContinentMap に見つかりません。島名をそのまま使用します"):format(
				islandName
			)
		)
		return islandName
	end
	return result
end

local function attachAILabel(model: Model, aiState)
	local hrp = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local _, bboxSize = model:GetBoundingBox()
	local labelOffset = math.min(bboxSize.Y * 0.5 + 2, 15)

	local gui = Instance.new("BillboardGui")
	gui.Name = "AIDebugInfo"
	gui.Adornee = hrp
	gui.AlwaysOnTop = true
	gui.Size = UDim2.new(0, 150, 0, 50)
	gui.StudsOffset = Vector3.new(0, labelOffset, 0)
	gui.MaxDistance = 100
	gui.Parent = hrp

	local lb = Instance.new("TextLabel")
	lb.Name = "InfoText"
	lb.BackgroundTransparency = 1
	lb.TextScaled = true
	lb.Font = Enum.Font.GothamBold
	lb.TextColor3 = Color3.new(1, 1, 1)
	lb.TextStrokeTransparency = 0.5
	lb.Size = UDim2.fromScale(1, 1)
	lb.Text = string.format("Brave:%.1f\n%s", aiState.brave, aiState.modeType or "INIT")
	lb.Parent = gui

	print(("[MonsterSpawner] ★【デバッグ】AIラベル追加: %s"):format(model.Name))
end

local function placeOnGround(model: Model, x: number, z: number)
	local hrp = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		warn("[MonsterSpawner] HumanoidRootPart が見つかりません: " .. model.Name)
		print(("[MonsterSpawner] ★【デバッグ】地面配置失敗（HRP未検出）: %s"):format(model.Name))
		return
	end

	print(("[MonsterSpawner] ★【デバッグ】地面配置開始: %s (%.1f, %.1f)"):format(model.Name, x, z))

	local groundY = FieldGen.raycastGroundY(x, z, 100)
		or FieldGen.raycastGroundY(x, z, 200)
		or FieldGen.raycastGroundY(x, z, 50)
		or 10

	print(("[MonsterSpawner] ★【デバッグ】レイキャスト結果: Y=%.1f"):format(groundY))

	local _, yaw = hrp.CFrame:ToOrientation()
	model:PivotTo(CFrame.new(x, groundY + 20, z) * CFrame.Angles(0, yaw, 0))

	local bboxCFrame, bboxSize = model:GetBoundingBox()
	local bottomY = bboxCFrame.Position.Y - (bboxSize.Y * 0.5)
	local offset = hrp.Position.Y - bottomY

	model:PivotTo(CFrame.new(x, groundY + offset, z) * CFrame.Angles(0, yaw, 0))

	print(
		("[MonsterSpawner] ★【デバッグ】地面配置完了: %s (最終Y: %.1f)"):format(
			model.Name,
			groundY + offset
		)
	)
end

local function nearestPlayer(position: Vector3)
	local best, bestDist = nil, math.huge
	for _, pl in ipairs(Players:GetPlayers()) do
		local ch = pl.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (position - hrp.Position).Magnitude
			if d < bestDist then
				best, bestDist = pl, d
			end
		end
	end
	return best, bestDist
end

-- スポーン処理（島指定版）
local function spawnMonster(template: Model, index: number, def, islandName)
	print(
		("[MonsterSpawner] ★【デバッグ】spawnMonster呼び出し: template=%s, index=%d, def=%s, island=%s"):format(
			template.Name,
			index,
			def.Name or "Unknown",
			islandName
		)
	)

	local m = template:Clone()
	m.Name = (def.Name or template.Name) .. "_" .. index

	print(("[MonsterSpawner] ★【デバッグ】クローン作成: %s"):format(m.Name))

	-- === 両目の生成（SurfaceGui方式・縦横比維持・貼り付き調整付き） ===
	-- === カラー設定＋両目生成 ===
	if def.ColorProfile then
		print(("[MonsterSpawner] ★【デバッグ】ColorProfile処理開始: %s"):format(m.Name))

		-- まず Body/Core の色とマテリアルを設定
		for _, part in ipairs(m:GetDescendants()) do
			if part:IsA("MeshPart") then
				-- SurfaceAppearance があると色が反映されないため削除
				for _, child in ipairs(part:GetChildren()) do
					if child:IsA("SurfaceAppearance") then
						child:Destroy()
					end
				end

				-- Body（外側）
				if part.Name == "Body" then
					if def.ColorProfile.Body then
						part.Color = def.ColorProfile.Body
					end
					part.Material = Enum.Material.Glass
					part.Transparency = 0.45

				-- Core（内側）
				elseif part.Name == "Core" then
					if def.ColorProfile.Core then
						part.Color = def.ColorProfile.Core
					end
					part.Material = Enum.Material.Neon
					part.Transparency = 0.1
				end
			end
		end

		-- === 両目の生成 ===
		if def.ColorProfile.EyeTexture then
			print(("[MonsterSpawner] ★【デバッグ】目の生成処理開始: %s"):format(m.Name))

			-- 目を貼る対象（Bodyに貼るのが自然）
			local targetPart = m:FindFirstChild("Body") or m.PrimaryPart
			if targetPart then
				print(("[MonsterSpawner] ★【デバッグ】目の配置対象パーツ: %s"):format(targetPart.Name))

				-- ▼ 調整用パラメータ（ColorProfileで上書き可能）
				local useDecal = def.ColorProfile.UseDecal == true
				local eyeSize = def.ColorProfile.EyeSize or 0.18
				local eyeY = def.ColorProfile.EyeY or 0.48
				local eyeSeparation = def.ColorProfile.EyeSeparation or 0.18
				local zOffset = def.ColorProfile.EyeZOffset or -0.05
				local alwaysOnTop = def.ColorProfile.EyeAlwaysOnTop == true
				local sizingMode = def.ColorProfile.EyeSizingMode or "Scale"
				local pps = def.ColorProfile.PixelsPerStud or 60
				local eyePixelSize = def.ColorProfile.EyePixelSize or 120

				if useDecal then
					print(("[MonsterSpawner] ★【デバッグ】Decal方式で目を生成: %s"):format(m.Name))
					-- ★ Decal方式（両目を1枚にした画像向け）
					local decal = Instance.new("Decal")
					decal.Texture = def.ColorProfile.EyeTexture
					decal.Face = Enum.NormalId.Front
					decal.Transparency = 0
					decal.Parent = targetPart
				else
					print(("[MonsterSpawner] ★【デバッグ】SurfaceGui方式で目を生成: %s"):format(m.Name))
					-- ★ SurfaceGui + ImageLabel方式（個別に左右配置）
					for _, sign in ipairs({ -1, 1 }) do
						local eyeGui = Instance.new("SurfaceGui")
						eyeGui.Name = (sign == -1) and "EyeGuiL" or "EyeGuiR"
						eyeGui.Adornee = targetPart
						eyeGui.Face = Enum.NormalId.Front
						eyeGui.AlwaysOnTop = alwaysOnTop
						eyeGui.LightInfluence = 1
						eyeGui.ZOffset = zOffset
						eyeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

						if sizingMode == "Pixels" then
							eyeGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
							eyeGui.PixelsPerStud = pps
						end

						eyeGui.Parent = targetPart

						local img = Instance.new("ImageLabel")
						img.Name = "Eye"
						img.BackgroundTransparency = 1
						img.Image = def.ColorProfile.EyeTexture
						img.AnchorPoint = Vector2.new(0.5, 0.5)

						if sizingMode == "Pixels" then
							img.Size = UDim2.new(0, eyePixelSize, 0, eyePixelSize)
							img.Position = UDim2.new(0.5 + (sign * eyeSeparation), 0, eyeY, 0)
						else
							img.Size = UDim2.new(eyeSize, 0, eyeSize, 0)
							img.Position = UDim2.new(0.5 + (sign * eyeSeparation), 0, eyeY, 0)
						end

						local aspect = Instance.new("UIAspectRatioConstraint")
						aspect.AspectRatio = 1
						aspect.DominantAxis = Enum.DominantAxis.Height
						aspect.Parent = img

						pcall(function()
							img.ScaleType = Enum.ScaleType.Fit
						end)

						img.ImageTransparency = 0
						img.Parent = eyeGui
					end
				end
			else
				print(
					("[MonsterSpawner] ★【デバッグ】目の配置対象パーツが見つかりません: %s"):format(
						m.Name
					)
				)
			end
		else
			print(("[MonsterSpawner] ★【デバッグ】EyeTextureが未設定: %s"):format(m.Name))
		end
	else
		print(("[MonsterSpawner] ★【デバッグ】ColorProfileが未設定: %s"):format(m.Name))
	end
	-- === カラー設定＋両目生成 ここまで ===

	local hum = m:FindFirstChildOfClass("Humanoid")
	local hrp = ensureHRP(m)

	if not hum or not hrp then
		warn("[MonsterSpawner] Humanoid または HRP がありません: " .. m.Name)
		print(("[MonsterSpawner] ★【デバッグ】Humanoid=%s, HRP=%s"):format(tostring(hum), tostring(hrp)))
		m:Destroy()
		return
	end

	print(("[MonsterSpawner] ★【デバッグ】Humanoid確認OK: %s"):format(m.Name))

	m:SetAttribute("IsEnemy", true)
	m:SetAttribute("MonsterKind", def.Name or "Monster")
	m:SetAttribute("ChaseDistance", def.ChaseDistance or 60)

	-- ★【修正】SpawnZone に大陸名を設定
	local continentName = getContinentNameFromIsland(islandName)
	m:SetAttribute("SpawnZone", continentName)
	m:SetAttribute("SpawnIsland", islandName)

	local speedMin = def.SpeedMin or 0.7
	local speedMax = def.SpeedMax or 1.3
	local speedMult = speedMin + math.random() * (speedMax - speedMin)
	hum.WalkSpeed = (def.WalkSpeed or 14) * speedMult
	hum.HipHeight = 0

	print(
		("[MonsterSpawner] ★【デバッグ】WalkSpeed設定: %.1f (倍率: %.2f)"):format(hum.WalkSpeed, speedMult)
	)

	hrp.Anchored = true
	hrp.CanCollide = false
	hrp.Transparency = 1

	for _, descendant in ipairs(m:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= hrp then
			descendant.CanCollide = true
			descendant.Anchored = false

			for _, child in ipairs(descendant:GetChildren()) do
				if child:IsA("WeldConstraint") or child:IsA("Weld") then
					child:Destroy()
				end
			end

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = hrp
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end

	print(("[MonsterSpawner] ★【デバッグ】Workspace に親設定前"):format())
	m.Parent = Workspace
	print(("[MonsterSpawner] ★【デバッグ】Workspace に配置完了: %s"):format(m.Name))

	local island = Islands[islandName]
	if not island then
		warn(("[MonsterSpawner] 島 '%s' が見つかりません"):format(islandName))
		print(("[MonsterSpawner] ★【デバッグ】利用可能な島:"):format())
		for name, _ in pairs(Islands) do
			print(("[MonsterSpawner] ★【デバッグ】  - %s"):format(name))
		end
		m:Destroy()
		return
	end

	print(("[MonsterSpawner] ★【デバッグ】島確認OK: %s"):format(islandName))

	local spawnRadius
	if def.radiusPercent then
		spawnRadius = (island.sizeXZ / 2) * (def.radiusPercent / 100)
		print(
			("[MonsterSpawner] ★【デバッグ】スポーン範囲（パーセント指定）: %.1f (島サイズ: %.1f, パーセント: %d%%)"):format(
				spawnRadius,
				island.sizeXZ / 2,
				def.radiusPercent
			)
		)
	else
		spawnRadius = def.spawnRadius or 50
		print(("[MonsterSpawner] ★【デバッグ】スポーン範囲（固定値）: %.1f"):format(spawnRadius))
	end

	local rx = island.centerX + math.random(-spawnRadius, spawnRadius)
	local rz = island.centerZ + math.random(-spawnRadius, spawnRadius)

	print(("[MonsterSpawner] ★【デバッグ】スポーン座標: (%.1f, ?, %.1f)"):format(rx, rz))

	placeOnGround(m, rx, rz)

	task.wait(0.05)
	hrp.Anchored = false

	print(("[MonsterSpawner] ★【デバッグ】AIState初期化前"):format())

	-- ★【新】AIState を新しいシステムで初期化
	local aiState = AIState.new(m, def)
	if aiState then
		table.insert(ActiveMonsters, aiState)
		attachAILabel(m, aiState)
		print(
			("[MonsterSpawner] %s AI初期化完了 (Brave=%.1f, Mode=%s)"):format(
				m.Name,
				aiState.brave,
				aiState.modeType
			)
		)
	else
		warn(("[MonsterSpawner] %s のAI初期化に失敗"):format(m.Name))
		print(("[MonsterSpawner] ★【デバッグ】AIState.new() が nil を返しました: %s"):format(m.Name))
		m:Destroy()
		return
	end

	local monsterName = def.Name or "Monster"
	if not MonsterCounts[islandName] then
		MonsterCounts[islandName] = {}
	end
	MonsterCounts[islandName][monsterName] = (MonsterCounts[islandName][monsterName] or 0) + 1

	print(
		("[MonsterSpawner] %s を %s (%s) にスポーン (大陸: %s)"):format(
			m.Name,
			islandName,
			def.Name,
			continentName
		)
	)
end

-- ゾーン内のモンスターカウントを取得
local function getZoneMonsterCounts(zoneName)
	local counts = {}

	-- 大陸名から島のリストを取得
	local islandNames = {}

	-- ContinentsRegistryをロード（まだロードされていない場合）
	if not ContinentsRegistry then
		local ContinentsFolder = ReplicatedStorage:FindFirstChild("Continents")
		if ContinentsFolder then
			local RegistryModule = ContinentsFolder:FindFirstChild("Registry")
			if RegistryModule then
				ContinentsRegistry = require(RegistryModule)
				print("[MonsterSpawner] ContinentsRegistryをロードしました")
			end
		end
	end

	-- 大陸の場合は、含まれる島をすべて取得
	local continent = nil
	if ContinentsRegistry then
		for _, cont in ipairs(ContinentsRegistry) do
			if cont.name == zoneName then
				continent = cont
				break
			end
		end
	end

	if continent and continent.islands then
		-- 大陸内の全島を対象にする
		for _, islandName in ipairs(continent.islands) do
			table.insert(islandNames, islandName)
		end
		print(("[MonsterSpawner] 大陸 %s の島リスト: %s"):format(zoneName, table.concat(islandNames, ", ")))
	else
		-- 大陸でない場合は、ゾーン名自体を島名とする
		table.insert(islandNames, zoneName)
		print(("[MonsterSpawner] %s は島として扱います"):format(zoneName))
	end

	-- 各島のモンスターカウントを集計
	for _, islandName in ipairs(islandNames) do
		if MonsterCounts[islandName] then
			for monsterName, count in pairs(MonsterCounts[islandName]) do
				counts[monsterName] = (counts[monsterName] or 0) + count
			end
		end
	end

	print(
		("[MonsterSpawner] ゾーン %s のモンスターカウント: %s"):format(
			zoneName,
			game:GetService("HttpService"):JSONEncode(counts)
		)
	)

	return counts
end

-- 全ゾーンのモンスター数をSharedStateに保存
local function updateAllMonsterCounts()
	print("[MonsterSpawner] 全ゾーンのモンスターカウントを更新中...")

	-- 一旦クリア
	SharedState.MonsterCounts = {}

	-- アクティブなゾーンごとにカウント
	local ZoneManager = require(script.Parent.ZoneManager)
	for zoneName, _ in pairs(ZoneManager.ActiveZones) do
		SharedState.MonsterCounts[zoneName] = getZoneMonsterCounts(zoneName)
	end

	print("[MonsterSpawner] モンスターカウント更新完了")
end

-- カスタムカウントでモンスターをスポーン（ロード時用）
local function spawnMonstersWithCounts(zoneName, customCounts)
	print(("[MonsterSpawner] ★【デバッグ】spawnMonstersWithCounts呼び出し: zone=%s"):format(zoneName))

	if isSafeZone(zoneName) then
		print(
			("[MonsterSpawner] %s は安全地帯です。モンスターをスポーンしません"):format(zoneName)
		)
		return
	end

	if not customCounts or type(customCounts) ~= "table" then
		print(
			("[MonsterSpawner] カスタムカウントが無効です。通常スポーンを実行: %s"):format(
				zoneName
			)
		)
		spawnMonstersForZone(zoneName)
		return
	end

	print(("[MonsterSpawner] カスタムカウントでモンスターをスポーン: %s"):format(zoneName))
	print(("[MonsterSpawner] カウント: %s"):format(game:GetService("HttpService"):JSONEncode(customCounts)))

	-- カスタムカウントに基づいてスポーン
	for monsterName, count in pairs(customCounts) do
		local template = TemplateCache[monsterName]
		local def = nil

		-- 定義を取得
		for _, regDef in ipairs(Registry) do
			if regDef.Name == monsterName then
				def = regDef
				break
			end
		end

		if template and def and count > 0 then
			print(("[MonsterSpawner] %s を %d 体スポーン"):format(monsterName, count))

			-- 各モンスターの配置先を決定
			if def.SpawnLocations then
				-- 各ロケーションに均等配分
				local locationsInZone = {}
				for _, location in ipairs(def.SpawnLocations) do
					-- このゾーンに含まれる島かチェック
					local isInZone = false

					-- 大陸の場合
					local Continents = {}
					for _, continent in ipairs(ContinentsRegistry) do
						Continents[continent.name] = continent
					end

					if Continents[zoneName] then
						for _, islandName in ipairs(Continents[zoneName].islands) do
							if islandName == location.islandName then
								isInZone = true
								break
							end
						end
					elseif zoneName == location.islandName then
						isInZone = true
					end

					if isInZone then
						table.insert(locationsInZone, location.islandName)
					end
				end

				-- 各ロケーションに配分
				if #locationsInZone > 0 then
					local countPerLocation = math.ceil(count / #locationsInZone)

					for _, islandName in ipairs(locationsInZone) do
						for i = 1, math.min(countPerLocation, count) do
							local spawnDef = {}
							for k, v in pairs(def) do
								spawnDef[k] = v
							end

							spawnMonster(template, i, spawnDef, islandName)
							count = count - 1

							if count <= 0 then
								break
							end
							if i % 5 == 0 then
								task.wait()
							end
						end

						if count <= 0 then
							break
						end
					end
				end
			end
		else
			if not template then
				warn(("[MonsterSpawner] テンプレート未発見: %s"):format(monsterName))
				print(("[MonsterSpawner] ★【デバッグ】キャッシュ内のテンプレート:"):format())
				for cacheName, _ in pairs(TemplateCache) do
					print(("[MonsterSpawner] ★【デバッグ】  - %s"):format(cacheName))
				end
			end
			if not def then
				warn(("[MonsterSpawner] 定義未発見: %s"):format(monsterName))
				print(("[MonsterSpawner] ★【デバッグ】Registry内の定義:"):format())
				for _, regDef in ipairs(Registry) do
					print(("[MonsterSpawner] ★【デバッグ】  - %s"):format(regDef.Name or "Unknown"))
				end
			end
		end
	end
end

-- ゾーンにモンスターをスポーンする（大陸対応版）
function spawnMonstersForZone(zoneName)
	print(("[MonsterSpawner] ★【デバッグ】spawnMonstersForZone呼び出し: zone=%s"):format(zoneName))

	if isSafeZone(zoneName) then
		print(
			("[MonsterSpawner] %s は安全地帯です。モンスターをスポーンしません"):format(zoneName)
		)
		return
	end

	print(("[MonsterSpawner] %s にモンスターを配置中..."):format(zoneName))

	local islandsInZone = {}

	local ContinentsRegistry = require(ReplicatedStorage.Continents.Registry)
	local Continents = {}
	for _, continent in ipairs(ContinentsRegistry) do
		Continents[continent.name] = continent
	end

	print(("[MonsterSpawner] ★【デバッグ】Continents数: %d"):format(#ContinentsRegistry))
	for _, continent in ipairs(ContinentsRegistry) do
		print(
			("[MonsterSpawner] ★【デバッグ】  大陸: %s, 島数: %d"):format(
				continent.name,
				#(continent.islands or {})
			)
		)
	end

	if Continents[zoneName] then
		local continent = Continents[zoneName]
		for _, islandName in ipairs(continent.islands) do
			islandsInZone[islandName] = true
		end
		print(("[MonsterSpawner] 大陸 %s の島: %s"):format(zoneName, table.concat(continent.islands, ", ")))
	else
		islandsInZone[zoneName] = true
		print(("[MonsterSpawner] ★【デバッグ】%s は島として処理されます"):format(zoneName))
	end

	print(("[MonsterSpawner] ★【デバッグ】Registry数: %d"):format(#Registry))

	for _, def in ipairs(Registry) do
		local monsterName = def.Name or "Monster"
		local template = TemplateCache[monsterName]

		print(
			("[MonsterSpawner] ★【デバッグ】モンスター: %s, テンプレート=%s, SpawnLocations=%s"):format(
				monsterName,
				template and "OK" or "NG",
				def.SpawnLocations and "あり" or "なし"
			)
		)

		if template then
			if def.SpawnLocations then
				print(("[MonsterSpawner] ★【デバッグ】SpawnLocations数: %d"):format(#def.SpawnLocations))
				for locIdx, location in ipairs(def.SpawnLocations) do
					local islandName = location.islandName

					print(
						("[MonsterSpawner] ★【デバッグ】  [%d] island=%s, count=%d, inZone=%s"):format(
							locIdx,
							islandName,
							location.count or 0,
							islandsInZone[islandName] and "YES" or "NO"
						)
					)

					if islandsInZone[islandName] then
						local radiusText = location.radiusPercent or 100
						print(
							("[MonsterSpawner] %s を %s に配置中 (数: %d, 範囲: %d%%)"):format(
								monsterName,
								islandName,
								location.count,
								radiusText
							)
						)

						if not MonsterCounts[islandName] then
							MonsterCounts[islandName] = {}
						end
						MonsterCounts[islandName][monsterName] = 0

						for i = 1, (location.count or 0) do
							local spawnDef = {}
							for k, v in pairs(def) do
								spawnDef[k] = v
							end
							spawnDef.radiusPercent = location.radiusPercent
							spawnDef.spawnRadius = location.spawnRadius

							print(
								("[MonsterSpawner] ★【デバッグ】スポーン実行 [%d/%d]"):format(
									i,
									location.count or 0
								)
							)
							spawnMonster(template, i, spawnDef, islandName)
							if i % 5 == 0 then
								task.wait()
							end
						end
					end
				end
			else
				warn(
					("[MonsterSpawner] %s は旧形式です。SpawnLocations形式に移行してください"):format(
						monsterName
					)
				)
				print(("[MonsterSpawner] ★【デバッグ】旧形式: %s"):format(monsterName))
			end
		else
			print(("[MonsterSpawner] ★【デバッグ】テンプレートキャッシュ:"):format())
			for cacheName, _ in pairs(TemplateCache) do
				print(("[MonsterSpawner] ★【デバッグ】  - %s"):format(cacheName))
			end
		end
	end
end

-- リスポーン処理（島対応版）
local function scheduleRespawn(monsterName, def, islandName)
	local respawnTime = def.RespawnTime or 10
	if respawnTime <= 0 then
		return
	end

	local respawnData = {
		monsterName = monsterName,
		def = def,
		islandName = islandName,
		respawnAt = os.clock() + respawnTime,
	}
	table.insert(RespawnQueue, respawnData)

	print(
		("[MonsterSpawner] ★【デバッグ】リスポーン予約: %s を %s に %d秒後"):format(
			monsterName,
			islandName,
			respawnTime
		)
	)
end

local function processRespawnQueue()
	task.spawn(function()
		while true do
			local now = os.clock()

			for i = #RespawnQueue, 1, -1 do
				local data = RespawnQueue[i]
				if now >= data.respawnAt then
					local isActive = false
					for zoneName, _ in pairs(ZoneManager.ActiveZones) do
						isActive = true
						break
					end

					if isActive then
						local template = TemplateCache[data.monsterName]
						if template and MonsterCounts[data.islandName] then
							local nextIndex = (MonsterCounts[data.islandName][data.monsterName] or 0) + 1
							spawnMonster(template, nextIndex, data.def, data.islandName)
						end
					end
					table.remove(RespawnQueue, i)
				end
			end

			task.wait(1)
		end
	end)
end

-- ★【新】AI更新ループ（新AI行動システム対応版）
local function startGlobalAILoop()
	print("[MonsterSpawner] AI更新ループ開始（新AI行動システム）")

	task.spawn(function()
		while true do
			if #ActiveMonsters > 0 then
				local currentTime = os.clock()

				for i = #ActiveMonsters, 1, -1 do
					local state = ActiveMonsters[i]

					-- 最も近いプレイヤーを取得
					local nearest, dist = nearestPlayer(state.root.Position)

					-- 更新判定
					if state:shouldUpdate(currentTime, dist) then
						local success, result = pcall(function()
							-- ★【新】新しい update() 関数を呼び出し
							local playerPos = nil
							if nearest and nearest.Character then
								local hrp = nearest.Character:FindFirstChild("HumanoidRootPart")
								if hrp then
									playerPos = hrp.Position
								end
							end

							return state:update(playerPos, dist or math.huge, BattleSystem)
						end)

						if not success then
							warn(
								("[MonsterSpawner ERROR] AI更新エラー: %s - %s"):format(
									state.monster.Name,
									tostring(result)
								)
							)
						elseif not result then
							-- モンスターが倒された
							local monsterDef = state.def
							local monsterName = monsterDef.Name or "Unknown"
							local zoneName = state.monster:GetAttribute("SpawnZone") or "Unknown"

							if MonsterCounts[zoneName] and MonsterCounts[zoneName][monsterName] then
								MonsterCounts[zoneName][monsterName] = MonsterCounts[zoneName][monsterName] - 1
							end

							table.remove(ActiveMonsters, i)
							scheduleRespawn(monsterName, monsterDef, zoneName)
						end
					end
				end
			end

			task.wait(UpdateInterval)
		end
	end)
end

-- ゾーンのモンスターを削除する
function despawnMonstersForZone(zoneName)
	print(("[MonsterSpawner] %s のモンスターを削除中..."):format(zoneName))

	local removedCount = 0

	-- ★【修正】SpawnZone は大陸名で比較
	for i = #ActiveMonsters, 1, -1 do
		local state = ActiveMonsters[i]
		local monsterZone = state.monster:GetAttribute("SpawnZone")

		if monsterZone == zoneName then
			state.monster:Destroy()
			table.remove(ActiveMonsters, i)
			removedCount = removedCount + 1
		end
	end

	-- RespawnQueue からも削除
	for i = #RespawnQueue, 1, -1 do
		if RespawnQueue[i].zoneName == zoneName then
			table.remove(RespawnQueue, i)
		end
	end

	print(("[MonsterSpawner] %s のモンスターを %d体 削除しました"):format(zoneName, removedCount))
end

-- ===== MemoryMonitor 用のモンスター詳細表示（更新版）=====
local function getZoneMonsterDetails(zoneName)
	local details = {}

	for _, state in ipairs(ActiveMonsters) do
		local spawnZone = state.monster:GetAttribute("SpawnZone")
		local spawnIsland = state.monster:GetAttribute("SpawnIsland")

		-- 大陸で比較
		if spawnZone == zoneName then
			if not details[spawnIsland] then
				details[spawnIsland] = 0
			end
			details[spawnIsland] = details[spawnIsland] + 1
		end
	end

	return details
end

-- ★【新】AI設定の検証関数
local function validateAIConfig()
	print("[MonsterSpawner] AI設定検証開始...")

	for _, def in ipairs(Registry) do
		local name = def.Name or "Unknown"

		-- AIBehavior の確認
		if not def.AIBehavior then
			warn(("[MonsterSpawner] %s に AIBehavior が見つかりません"):format(name))
			print(("[MonsterSpawner] ★【デバッグ】AIBehavior未設定: %s"):format(name))
		else
			print(("[MonsterSpawner] ✓ %s AIBehavior OK"):format(name))
		end

		-- BraveBehavior の確認
		if not def.BraveBehavior then
			warn(("[MonsterSpawner] %s に BraveBehavior が見つかりません"):format(name))
			print(("[MonsterSpawner] ★【デバッグ】BraveBehavior未設定: %s"):format(name))
		else
			local avg = def.BraveBehavior.AverageBrave
			local var = def.BraveBehavior.Variance
			print(("[MonsterSpawner] ✓ %s BraveBehavior (avg=%.1f, var=%.1f)"):format(name, avg, var))
		end
	end

	print("[MonsterSpawner] AI設定検証完了")
end

-- 初期化
print("[MonsterSpawner] === スクリプト開始（新AI行動システム対応版 + デバッグログ版）===")

if BattleSystem then
	BattleSystem.init()
	print("[MonsterSpawner] BattleSystem初期化完了")
else
	print("[MonsterSpawner] BattleSystemなしで起動")
end

-- モンスターカウントリクエストに応答
GameEvents.MonsterCountRequest.Event:Connect(function(zoneName)
	print(("[MonsterSpawner] モンスターカウントリクエスト受信: %s"):format(zoneName or "全ゾーン"))

	if zoneName then
		-- 特定ゾーンのみ
		SharedState.MonsterCounts[zoneName] = getZoneMonsterCounts(zoneName)
	else
		-- 全ゾーン
		updateAllMonsterCounts()
	end

	-- 完了通知
	GameEvents.MonsterCountResponse:Fire()
end)

print("[MonsterSpawner] GameEventsへの応答登録完了")

Workspace:WaitForChild("World", 10)
print("[MonsterSpawner] World フォルダ検出")

task.wait(1)

print("[MonsterSpawner] ★【デバッグ】モンスターテンプレートをキャッシュ中...")
for _, def in ipairs(Registry) do
	print(("[MonsterSpawner] ★【デバッグ】テンプレート解決中: %s"):format(def.Name or "Unknown"))
	local template = resolveTemplate(def.TemplatePath)
	if template then
		local monsterName = def.Name or "Monster"
		TemplateCache[monsterName] = template
		print(("[MonsterSpawner] テンプレートキャッシュ: %s"):format(monsterName))
	else
		warn(("[MonsterSpawner] テンプレート未発見: %s"):format(def.Name or "?"))
		print(
			("[MonsterSpawner] ★【デバッグ】TemplatePath: %s"):format(
				game:GetService("HttpService"):JSONEncode(def.TemplatePath)
			)
		)
	end
end

print("[MonsterSpawner] ★【デバッグ】テンプレートキャッシュ完了。キャッシュ内容:")
for name, _ in pairs(TemplateCache) do
	print(("[MonsterSpawner] ★【デバッグ】  - %s"):format(name))
end

-- ★【新】AI設定検証を実行
validateAIConfig()

startGlobalAILoop()
processRespawnQueue()

print("[MonsterSpawner] === 初期化完了（新AI行動システム対応）===")

_G.SpawnMonstersForZone = spawnMonstersForZone
_G.DespawnMonstersForZone = despawnMonstersForZone
_G.SpawnMonstersWithCounts = spawnMonstersWithCounts
_G.GetZoneMonsterCounts = getZoneMonsterCounts
_G.UpdateAllMonsterCounts = updateAllMonsterCounts

print("[MonsterSpawner] グローバル関数登録完了")
print("[MonsterSpawner] ★【デバッグ】=== MonsterSpawner 完全に起動完了 ===")
