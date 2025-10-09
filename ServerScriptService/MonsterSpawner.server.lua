-- ServerScriptService/MonsterSpawner.server.lua
-- ゾーン対応版モンスター配置システム（バトル高速化版、徘徊AI修正版）

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FieldGen = require(ReplicatedStorage:WaitForChild("FieldGen"))
local ZoneManager = require(script.Parent.ZoneManager)

local SharedState = require(ReplicatedStorage:WaitForChild("SharedState"))
local GameEvents = require(ReplicatedStorage:WaitForChild("GameEvents"))

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

-- 島の設定を読み込み
local IslandsRegistry = require(ReplicatedStorage.Islands.Registry)
local Islands = {}
for _, island in ipairs(IslandsRegistry) do
	Islands[island.name] = island
end

-- グローバル変数
local ActiveMonsters = {}
local UpdateInterval = 0.05
local MonsterCounts = {}
local TemplateCache = {}
local RespawnQueue = {}

-- 安全地帯チェック
local function isSafeZone(zoneName)
	local island = Islands[zoneName]
	if island and island.safeZone then
		return true
	end
	return false
end

-- ユーティリティ関数
local function resolveTemplate(pathArray: {string}): Model?
	local node: Instance = game
	for _, seg in ipairs(pathArray) do
		node = node:FindFirstChild(seg)
		if not node then return nil end
	end
	return (node and node:IsA("Model")) and node or nil
end

local function ensureHRP(model: Model): BasePart?
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		if not model.PrimaryPart then model.PrimaryPart = hrp end
		return hrp
	end
	return nil
end

local function attachLabel(model: Model, maxDist: number)
	local hrp = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local _, bboxSize = model:GetBoundingBox()
	local labelOffset = math.min(bboxSize.Y * 0.5 + 2, 15)

	local gui = Instance.new("BillboardGui")
	gui.Name = "DebugInfo"
	gui.Adornee = hrp
	gui.AlwaysOnTop = true
	gui.Size = UDim2.new(0, 150, 0, 50)
	gui.StudsOffset = Vector3.new(0, labelOffset, 0)
	gui.MaxDistance = maxDist
	gui.Parent = hrp

	local lb = Instance.new("TextLabel")
	lb.Name = "InfoText"
	lb.BackgroundTransparency = 1
	lb.TextScaled = true
	lb.Font = Enum.Font.GothamBold
	lb.TextColor3 = Color3.new(1, 1, 1)
	lb.TextStrokeTransparency = 0.5
	lb.Size = UDim2.fromScale(1, 1)
	lb.Text = "Ready"
	lb.Parent = gui
end

local function placeOnGround(model: Model, x: number, z: number)
	local hrp = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		warn("[MonsterSpawner] HumanoidRootPart が見つかりません: " .. model.Name)
		return
	end

	local groundY = FieldGen.raycastGroundY(x, z, 100)
		or FieldGen.raycastGroundY(x, z, 200)
		or FieldGen.raycastGroundY(x, z, 50)
		or 10

	local _, yaw = hrp.CFrame:ToOrientation()
	model:PivotTo(CFrame.new(x, groundY + 20, z) * CFrame.Angles(0, yaw, 0))

	local bboxCFrame, bboxSize = model:GetBoundingBox()
	local bottomY = bboxCFrame.Position.Y - (bboxSize.Y * 0.5)
	local offset = hrp.Position.Y - bottomY

	model:PivotTo(CFrame.new(x, groundY + offset, z) * CFrame.Angles(0, yaw, 0))
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

-- AI状態管理（高速化版）
local AIState = {}
AIState.__index = AIState

function AIState.new(monster, def)
	local self = setmetatable({}, AIState)
	self.monster = monster
	self.def = def
	self.humanoid = monster:FindFirstChildOfClass("Humanoid")
	self.root = monster.PrimaryPart
	self.courage = math.random()
	self.brave = (self.courage > 0.5)
	self.wanderGoal = nil
	self.nextWanderAt = 0
	self.lastUpdateTime = 0
	self.lastDistanceLog = 0
	self.updateRate = def.AiTickRate or 0.3
	self.nearUpdateRate = 0.05 -- 0.05秒に高速化（バトル判定が速くなる）
	self.farUpdateRate = 0.5 -- 0.5秒に高速化

	self.originalSpeed = self.humanoid.WalkSpeed
	self.wasInBattle = false

    -- 【修正点1】徘徊ステート管理を整理
    self.isMoving = false     -- 移動状態か
    self.isWaiting = false    -- 待機状態か (停止状態)
    self.waitEndTime = 0      -- 待機終了時刻
    -- 【修正点1 終わり】

	return self
end

function AIState:shouldUpdate(currentTime)
	local _, dist = nearestPlayer(self.root.Position)
	-- 近距離判定を150スタッドに拡大（バトル判定をより頻繁に）
	local rate = dist < 150 and self.nearUpdateRate or self.farUpdateRate
	return (currentTime - self.lastUpdateTime) >= rate
end

function AIState:update()
	if not self.monster.Parent or not self.humanoid or not self.root then
		return false
	end

	if self.monster:GetAttribute("Defeated") then
		if not self.loggedDefeated then
			-- print(("[AI DEBUG] %s - Defeated状態のためスキップ"):format(self.monster.Name))
			self.loggedDefeated = true
		end
		return false
	end

	-- バトル状態を確認
	local isGlobalBattle = BattleSystem and BattleSystem.isAnyBattleActive and BattleSystem.isAnyBattleActive()
	local isThisMonsterInBattle = self.monster:GetAttribute("InBattle")
	local isAnyBattle = isGlobalBattle or isThisMonsterInBattle

	-- いずれかのバトルが進行中なら停止
	if isAnyBattle then
		self.humanoid.WalkSpeed = 0
		self.humanoid:MoveTo(self.root.Position)
		self.wasInBattle = true
		return true
	end

	-- バトルが終了したら速度を復元
	if self.wasInBattle and not isAnyBattle then
		-- print(("[AI DEBUG] %s - バトル終了、速度復元: %.1f"):format(self.monster.Name, self.originalSpeed))
		self.humanoid.WalkSpeed = self.originalSpeed
		self.wasInBattle = false
		self.loggedDefeated = false
	end

	local p, dist = nearestPlayer(self.root.Position)
	local chaseRange = self.def.ChaseDistance or 60
	local now = os.clock()

	-- バトル判定（高速化・距離拡大）
	if BattleSystem and p and dist <= 7 then -- 7スタッドに拡大
		-- print(("[AI DEBUG] %s - 接触検出！距離=%.1f"):format(self.monster.Name, dist))

		if BattleSystem.isInBattle(p) then
			self.humanoid:MoveTo(self.root.Position)
			return true
		end

		if BattleSystem.isAnyBattleActive and BattleSystem.isAnyBattleActive() then
			self.humanoid:MoveTo(self.root.Position)
			return true
		end

		if self.monster:GetAttribute("InBattle") then
			return true
		end

		local character = p.Character
		if character then
			-- 【重要】即座にプレイヤーを停止（バトル開始前）
			local playerHumanoid = character:FindFirstChildOfClass("Humanoid")
			local playerHrp = character:FindFirstChild("HumanoidRootPart")

			if playerHumanoid and playerHrp then
				-- プレイヤーを即座に停止
				playerHumanoid.WalkSpeed = 0
				playerHumanoid.JumpPower = 0
				playerHrp.Anchored = true
			end

			self.monster:SetAttribute("InBattle", true)
			self.humanoid.WalkSpeed = 0
			self.humanoid:MoveTo(self.root.Position)

			local battleStarted = BattleSystem.startBattle(p, self.monster)
			-- print(("[AI DEBUG] バトル開始結果: %s"):format(tostring(battleStarted)))

			if not battleStarted then
				-- バトル開始失敗時はプレイヤーも解放
				self.monster:SetAttribute("InBattle", false)
				self.humanoid.WalkSpeed = self.originalSpeed

				if playerHumanoid and playerHrp then
					playerHumanoid.WalkSpeed = 16
					playerHumanoid.JumpPower = 50
					playerHrp.Anchored = false
				end
			end

			return true
		else
			self.monster:SetAttribute("InBattle", false)
		end
	end

	-- 海チェック
	local isInWater = self.root.Position.Y < 0 or self.humanoid:GetState() == Enum.HumanoidStateType.Swimming

	-- ラベル更新
	local label = self.root:FindFirstChild("DebugInfo")
		and self.root.DebugInfo:FindFirstChild("InfoText")
	if label then
		local behavior = self.brave and "CHASE" or "FLEE"
		label.Text = string.format("%s\n%s | %.1fm", self.monster.Name, behavior, dist or 999)
	end

	local gui = self.root:FindFirstChild("DebugInfo")
	if gui then
		gui.Enabled = not isInWater
	end

    -- 【修正点2】徘徊ロジックを再構築
    local function wanderLogic()
        local w = self.def.Wander or {}
        local minWait = w.MinWait or 2
        local maxWait = w.MaxWait or 5
        local minRadius = w.MinRadius or 20
        local maxRadius = w.MaxRadius or 60
        local stopDistance = 5 -- 目標到達と見なす距離

        local isGoalReached = self.wanderGoal and (self.root.Position - self.wanderGoal).Magnitude < stopDistance
        local isWaitFinished = self.isWaiting and now >= self.waitEndTime

        if self.isWaiting then
            -- ステート: 待機中（停止）
            self.humanoid:MoveTo(self.root.Position) -- 停止を維持
            self.isMoving = false

            if isWaitFinished then
                -- 待機終了。次の目標設定へ
                self.isWaiting = false
                self.wanderGoal = nil
            end
        elseif isGoalReached or not self.wanderGoal then
            -- ステート: 目標到達 or 目標なし -> 新目標設定 & 移動開始

            -- 目標に到達したら待機モードに移行
            if isGoalReached then
                self.isWaiting = true
                self.waitEndTime = now + math.random(minWait * 10, maxWait * 10) / 10
                self.humanoid:MoveTo(self.root.Position) -- 停止
                return
            end

            -- 新しい目標を設定
            local ang = math.random() * math.pi * 2
            local rad = math.random(minRadius, maxRadius)
            local gx = self.root.Position.X + math.cos(ang) * rad
            local gz = self.root.Position.Z + math.sin(ang) * rad

            local gy = FieldGen.raycastGroundY(gx, gz, 100) or self.root.Position.Y + 5 -- 見つからなければ現在のY+5

            self.wanderGoal = Vector3.new(gx, gy, gz)
            self.isMoving = true

            self.humanoid:MoveTo(self.wanderGoal)

        else
            -- ステート: 移動中（継続）
            self.isMoving = true
            self.humanoid:MoveTo(self.wanderGoal)
        end
    end
    -- 【修正点2 終わり】

	-- 行動決定
	if not p then
		-- プレイヤーがいない：徘徊のみ
		wanderLogic()
	elseif dist < chaseRange then
		-- 追跡 or 逃走
		self.wanderGoal = nil
        self.isMoving = false
        self.isWaiting = false -- 追跡中は徘徊ステートを強制解除
		if self.brave then
			self.humanoid:MoveTo(p.Character.HumanoidRootPart.Position)
		else
			local away = (self.root.Position - p.Character.HumanoidRootPart.Position).Unit
			self.humanoid:MoveTo(self.root.Position + away * 80)
		end
	else
		-- プレイヤーが遠い：徘徊
		wanderLogic()
	end

	self.lastUpdateTime = now
	return true
end

-- スポーン処理（島指定版）
local function spawnMonster(template: Model, index: number, def, islandName)
	local m = template:Clone()
	m.Name = (def.Name or template.Name) .. "_" .. index

	local hum = m:FindFirstChildOfClass("Humanoid")
	local hrp = ensureHRP(m)

	if not hum or not hrp then
		warn("[MonsterSpawner] Humanoid または HRP がありません: " .. m.Name)
		m:Destroy()
		return
	end

	m:SetAttribute("IsEnemy", true)
	m:SetAttribute("MonsterKind", def.Name or "Monster")
	m:SetAttribute("ChaseDistance", def.ChaseDistance or 60)
	m:SetAttribute("SpawnZone", islandName)
	m:SetAttribute("SpawnIsland", islandName)

	local speedMin = def.SpeedMin or 0.7
	local speedMax = def.SpeedMax or 1.3
	local speedMult = speedMin + math.random() * (speedMax - speedMin)
	hum.WalkSpeed = (def.WalkSpeed or 14) * speedMult
	hum.HipHeight = 0

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

	m.Parent = Workspace

	local island = Islands[islandName]
	if not island then
		warn(("[MonsterSpawner] 島 '%s' が見つかりません"):format(islandName))
		m:Destroy()
		return
	end

	local spawnRadius
	if def.radiusPercent then
		spawnRadius = (island.sizeXZ / 2) * (def.radiusPercent / 100)
	else
		spawnRadius = def.spawnRadius or 50
	end

	local rx = island.centerX + math.random(-spawnRadius, spawnRadius)
	local rz = island.centerZ + math.random(-spawnRadius, spawnRadius)

	placeOnGround(m, rx, rz)
	-- attachLabel(m, def.LabelMaxDistance or 250)

	task.wait(0.05)
	hrp.Anchored = false

	local aiState = AIState.new(m, def)
	table.insert(ActiveMonsters, aiState)

	local monsterName = def.Name or "Monster"
	if not MonsterCounts[islandName] then
		MonsterCounts[islandName] = {}
	end
	MonsterCounts[islandName][monsterName] = (MonsterCounts[islandName][monsterName] or 0) + 1

	-- print(("[MonsterSpawner] %s を %s にスポーン"):format(m.Name, islandName))
end

-- ゾーン内のモンスター数をカウント
local function getZoneMonsterCounts(zoneName)
	local counts = {}

	for _, aiState in ipairs(ActiveMonsters) do
		if aiState.monster and aiState.monster.Parent then
			local monsterZone = aiState.monster:GetAttribute("SpawnZone")
			if monsterZone == zoneName then
				local monsterKind = aiState.def.Name or "Unknown"
				counts[monsterKind] = (counts[monsterKind] or 0) + 1
			end
		end
	end

	print(("[MonsterSpawner] ゾーン %s のモンスターカウント: %s"):format(
		zoneName,
		game:GetService("HttpService"):JSONEncode(counts)
	))

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
	if isSafeZone(zoneName) then
		print(("[MonsterSpawner] %s は安全地帯です。モンスターをスポーンしません"):format(zoneName))
		return
	end

	if not customCounts or type(customCounts) ~= "table" then
		print(("[MonsterSpawner] カスタムカウントが無効です。通常スポーンを実行: %s"):format(zoneName))
		spawnMonstersForZone(zoneName)
		return
	end

	print(("[MonsterSpawner] カスタムカウントでモンスターをスポーン: %s"):format(zoneName))
	print(("[MonsterSpawner] カウント: %s"):format(
		game:GetService("HttpService"):JSONEncode(customCounts)
	))

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

							if count <= 0 then break end
							if i % 5 == 0 then task.wait() end
						end

						if count <= 0 then break end
					end
				end
			end
		else
			if not template then
				warn(("[MonsterSpawner] テンプレート未発見: %s"):format(monsterName))
			end
			if not def then
				warn(("[MonsterSpawner] 定義未発見: %s"):format(monsterName))
			end
		end
	end
end

-- ゾーンにモンスターをスポーンする（大陸対応版）
function spawnMonstersForZone(zoneName)
	if isSafeZone(zoneName) then
		print(("[MonsterSpawner] %s は安全地帯です。モンスターをスポーンしません"):format(zoneName))
		return
	end

	print(("[MonsterSpawner] %s にモンスターを配置中..."):format(zoneName))

	local islandsInZone = {}

	local ContinentsRegistry = require(ReplicatedStorage.Continents.Registry)
	local Continents = {}
	for _, continent in ipairs(ContinentsRegistry) do
		Continents[continent.name] = continent
	end

	if Continents[zoneName] then
		local continent = Continents[zoneName]
		for _, islandName in ipairs(continent.islands) do
			islandsInZone[islandName] = true
		end
		print(("[MonsterSpawner] 大陸 %s の島: %s"):format(zoneName, table.concat(continent.islands, ", ")))
	else
		islandsInZone[zoneName] = true
	end

	for _, def in ipairs(Registry) do
		local monsterName = def.Name or "Monster"
		local template = TemplateCache[monsterName]

		if template then
			if def.SpawnLocations then
				for _, location in ipairs(def.SpawnLocations) do
					local islandName = location.islandName

					if islandsInZone[islandName] then
						local radiusText = location.radiusPercent or 100
						print(("[MonsterSpawner] %s を %s に配置中 (数: %d, 範囲: %d%%)"):format(
							monsterName, islandName, location.count, radiusText
							))

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

							spawnMonster(template, i, spawnDef, islandName)
							if i % 5 == 0 then task.wait() end
						end
					end
				end
			else
				warn(("[MonsterSpawner] %s は旧形式です。SpawnLocations形式に移行してください"):format(monsterName))
			end
		end
	end
end

-- リスポーン処理（島対応版）
local function scheduleRespawn(monsterName, def, islandName)
	local respawnTime = def.RespawnTime or 10
	if respawnTime <= 0 then return end

	local respawnData = {
		monsterName = monsterName,
		def = def,
		islandName = islandName,
		respawnAt = os.clock() + respawnTime
	}
	table.insert(RespawnQueue, respawnData)
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
							-- print(("[MonsterSpawner] %s が %s にリスポーン"):format(data.monsterName, data.islandName))
						end
					end
					table.remove(RespawnQueue, i)
				end
			end

			task.wait(1)
		end
	end)
end

-- AI更新ループ（高速化）
local function startGlobalAILoop()
	print("[MonsterSpawner] AI更新ループ開始（高速化版）")

	task.spawn(function()
		while true do
			if #ActiveMonsters > 0 then
				local currentTime = os.clock()

				for i = #ActiveMonsters, 1, -1 do
					local state = ActiveMonsters[i]

					if state:shouldUpdate(currentTime) then
						local success, result = pcall(function()
							return state:update()
						end)

						if not success then
							warn(("[MonsterSpawner ERROR] AI更新エラー: %s - %s"):format(
								state.monster.Name, tostring(result)
								))
						elseif not result then
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

	for i = #ActiveMonsters, 1, -1 do
		local state = ActiveMonsters[i]
		local monsterZone = state.monster:GetAttribute("SpawnZone")

		if monsterZone == zoneName then
			state.monster:Destroy()
			table.remove(ActiveMonsters, i)
			removedCount = removedCount + 1
		end
	end

	for i = #RespawnQueue, 1, -1 do
		if RespawnQueue[i].zoneName == zoneName then
			table.remove(RespawnQueue, i)
		end
	end

	MonsterCounts[zoneName] = nil

	print(("[MonsterSpawner] %s のモンスターを %d体 削除しました"):format(zoneName, removedCount))
end

-- 初期化
print("[MonsterSpawner] === スクリプト開始（バトル高速化版）===")

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

print("[MonsterSpawner] モンスターテンプレートをキャッシュ中...")
for _, def in ipairs(Registry) do
	local template = resolveTemplate(def.TemplatePath)
	if template then
		local monsterName = def.Name or "Monster"
		TemplateCache[monsterName] = template
		print(("[MonsterSpawner] テンプレートキャッシュ: %s"):format(monsterName))
	else
		warn(("[MonsterSpawner] テンプレート未発見: %s"):format(def.Name or "?"))
	end
end

startGlobalAILoop()
processRespawnQueue()

print("[MonsterSpawner] === 初期化完了（バトル即座開始対応）===")

_G.SpawnMonstersForZone = spawnMonstersForZone
_G.DespawnMonstersForZone = despawnMonstersForZone
_G.SpawnMonstersWithCounts = spawnMonstersWithCounts
_G.GetZoneMonsterCounts = getZoneMonsterCounts
_G.UpdateAllMonsterCounts = updateAllMonsterCounts

print("[MonsterSpawner] グローバル関数登録完了（カウント機能付き）")