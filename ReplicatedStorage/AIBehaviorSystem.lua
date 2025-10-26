-- AIBehaviorSystem.lua
-- モンスターのAI行動システム（最適化版）

-- ============================================
-- ユーティリティ関数
-- ============================================

-- 正規分布でランダム値を生成
local function generateNormalRandom(mean, variance)
	-- Box-Muller変換
	local u1 = math.random()
	local u2 = math.random()

	if u1 < 0.0001 then
		u1 = 0.0001
	end

	local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
	local value = mean + (z * variance)

	-- 0-10 の範囲に正規化
	return math.max(0, math.min(10, value))
end

-- Brave値の初期化
local function initializeBraveValue(averageBrave, variance)
	local brave = generateNormalRandom(averageBrave, variance)
	return brave
end

-- 逃げモードのパラメータを計算
local function calculateFleeParameters(brave, aiConfig)
	local fleeFactor = (5 - brave) / 5 -- 0.0 ~ 1.0

	return {
		triggerDistance = aiConfig.TriggerDistance,
		escapeDistance = aiConfig.Flee.BaseEscapeDistance * (1 + fleeFactor),
		maxDuration = aiConfig.Flee.BaseMaxDuration + (fleeFactor * 10),
		cooldown = aiConfig.ActionCooldown,
	}
end

-- 追跡モードのパラメータを計算
local function calculateChaseParameters(brave, aiConfig)
	local chaseFactor = (brave - 5) / 5 -- 0.0 ~ 1.0

	return {
		triggerDistance = aiConfig.TriggerDistance,
		chaseDistance = aiConfig.Chase.BaseChaseDistance * (1 - chaseFactor),
		maxDuration = aiConfig.Chase.BaseMaxDuration + (chaseFactor * 10),
		cooldown = aiConfig.ActionCooldown,
	}
end

-- 中立モード（ランダムウォーク）のパラメータを計算
local function calculateWanderParameters(aiConfig)
	local wander = aiConfig.Wander

	return {
		steps = math.random(wander.MinSteps, wander.MaxSteps),
		stepDistance = wander.StepDistance,
		waitTime = wander.MinWaitTime + math.random() * (wander.MaxWaitTime - wander.MinWaitTime),
		pauseChance = wander.PauseChance,
		turnAngle = wander.TurnAngleMin + math.random() * (wander.TurnAngleMax - wander.TurnAngleMin),
		range = wander.Range,
	}
end

-- ============================================
-- AIState クラス
-- ============================================

local AIState = {}
AIState.__index = AIState

function AIState.new(monster, def)
	local self = setmetatable({}, AIState)

	-- 基本情報
	self.monster = monster
	self.def = def
	self.humanoid = monster:FindFirstChildOfClass("Humanoid")
	self.root = monster.PrimaryPart

	if not self.humanoid or not self.root then
		return nil
	end

	-- ★NEW: Brave値を初期化
	local braveConfig = def.BraveBehavior
	if braveConfig then
		self.brave = initializeBraveValue(braveConfig.AverageBrave, braveConfig.Variance)
	else
		self.brave = 5 -- デフォルト（中立）
	end

	-- ★NEW: モード別パラメータを事前計算
	self.aiConfig = def.AIBehavior or {}
	self:updateModeParameters()

	-- 行動状態管理
	self.currentMode = nil -- "FLEE", "CHASE", "WANDER", "COOLDOWN"
	self.modeStartTime = 0
	self.cooldownUntil = 0

	-- 更新タイミング
	self.lastUpdateTime = 0
	self.nearUpdateRate = 0.05
	self.farUpdateRate = 0.2

	-- バトル状態
	self.wasInBattle = false
	self.originalSpeed = self.humanoid.WalkSpeed

	-- ランダムウォーク用
	self.wanderState = {
		stepsRemaining = 0,
		isWaiting = false,
		waitUntil = 0,
		currentDirection = 0,
	}

	print(("[AIBehavior] %s 初期化完了 (Brave=%.1f)"):format(monster.Name, self.brave))

	return self
end

-- モード別パラメータを更新
function AIState:updateModeParameters()
	if self.brave < 5 then
		self.modeType = "FLEE"
		self.modeParams = calculateFleeParameters(self.brave, self.aiConfig)
	elseif self.brave > 5 then
		self.modeType = "CHASE"
		self.modeParams = calculateChaseParameters(self.brave, self.aiConfig)
	else
		self.modeType = "WANDER"
		self.modeParams = calculateWanderParameters(self.aiConfig)
	end
end

-- 更新判定
function AIState:shouldUpdate(currentTime, playerDist)
	local rate = playerDist and (playerDist < 150 and self.nearUpdateRate or self.farUpdateRate) or self.farUpdateRate
	return (currentTime - self.lastUpdateTime) >= rate
end

-- ============================================
-- 逃げモード実装
-- ============================================

function AIState:executeFleeMode(playerPos, playerDist)
	local params = self.modeParams

	-- トリガー距離内か確認
	if playerDist > params.triggerDistance then
		return false -- 逃げモード終了
	end

	-- モード開始
	if self.currentMode ~= "FLEE" then
		self.currentMode = "FLEE"
		self.modeStartTime = os.clock()
		print(("[AIBehavior] %s 逃げ開始 (距離: %.1f)"):format(self.monster.Name, playerDist))
	end

	local elapsed = os.clock() - self.modeStartTime

	-- 時間上限
	if elapsed > params.maxDuration then
		print(("[AIBehavior] %s 逃げ時間上限到達"):format(self.monster.Name))
		self.currentMode = "COOLDOWN"
		self.cooldownUntil = os.clock() + params.cooldown
		self.humanoid.WalkSpeed = self.originalSpeed
		return false
	end

	-- 逃げロジック
	if playerDist > params.escapeDistance then
		-- 十分に逃げた
		print(("[AIBehavior] %s 十分に逃げた (距離: %.1f)"):format(self.monster.Name, playerDist))
		self.currentMode = "COOLDOWN"
		self.cooldownUntil = os.clock() + params.cooldown
		self.humanoid.WalkSpeed = self.originalSpeed
		return false
	end

	-- プレイヤーから遠ざかる
	local away = (self.root.Position - playerPos).Unit
	local escapeTarget = self.root.Position + away * 50

	self.humanoid.WalkSpeed = self.originalSpeed * 1.5 -- 逃げ速度UP
	self.humanoid:MoveTo(escapeTarget)

	return true
end

-- ============================================
-- 追跡モード実装
-- ============================================

function AIState:executeChaseMode(playerPos, playerDist)
	local params = self.modeParams

	-- トリガー距離内か確認
	if playerDist > params.triggerDistance then
		return false -- 追跡モード終了
	end

	-- モード開始
	if self.currentMode ~= "CHASE" then
		self.currentMode = "CHASE"
		self.modeStartTime = os.clock()
		print(("[AIBehavior] %s 追跡開始 (距離: %.1f)"):format(self.monster.Name, playerDist))
	end

	local elapsed = os.clock() - self.modeStartTime

	-- 時間上限
	if elapsed > params.maxDuration then
		print(("[AIBehavior] %s 追跡時間上限到達"):format(self.monster.Name))
		self.currentMode = "COOLDOWN"
		self.cooldownUntil = os.clock() + params.cooldown
		self.humanoid.WalkSpeed = self.originalSpeed
		return false
	end

	-- 追跡終了距離
	if playerDist <= params.chaseDistance then
		-- プレイヤーに接近した
		print(("[AIBehavior] %s 追跡終了距離到達 (距離: %.1f)"):format(self.monster.Name, playerDist))
		self.currentMode = "COOLDOWN"
		self.cooldownUntil = os.clock() + params.cooldown
		self.humanoid.WalkSpeed = self.originalSpeed
		return false
	end

	-- プレイヤーを追跡
	self.humanoid.WalkSpeed = self.originalSpeed
	self.humanoid:MoveTo(playerPos)

	return true
end

-- ============================================
-- 中立モード（ランダムウォーク）実装
-- ============================================

function AIState:executeWanderMode()
	local wander = self.wanderState
	local params = self.modeParams

	-- モード開始時の初期化
	if self.currentMode ~= "WANDER" then
		self.currentMode = "WANDER"
		wander.stepsRemaining = params.steps
		wander.isWaiting = false
		wander.currentDirection = math.random() * 2 * math.pi
		print(("[AIBehavior] %s ランダムウォーク開始 (Brave=%.1f)"):format(self.monster.Name, self.brave))
	end

	-- 待機中
	if wander.isWaiting then
		self.humanoid:MoveTo(self.root.Position)
		self.humanoid.WalkSpeed = 0

		if os.clock() >= wander.waitUntil then
			wander.isWaiting = false
			self.humanoid.WalkSpeed = self.originalSpeed
		end

		return true
	end

	-- 歩行中
	if wander.stepsRemaining > 0 then
		local nextPos = self.root.Position
			+ Vector3.new(
				math.cos(wander.currentDirection) * params.stepDistance,
				0,
				math.sin(wander.currentDirection) * params.stepDistance
			)

		self.humanoid.WalkSpeed = self.originalSpeed * 0.5 -- ゆっくり歩く
		self.humanoid:MoveTo(nextPos)

		wander.stepsRemaining = wander.stepsRemaining - 1
		return true
	end

	-- 歩数完了 → 方向変更 or 停止
	if math.random() < params.pauseChance then
		-- 停止
		wander.isWaiting = true
		wander.waitUntil = os.clock() + params.waitTime
		self.humanoid:MoveTo(self.root.Position)
		self.humanoid.WalkSpeed = 0
	else
		-- 方向を変更してリセット
		wander.stepsRemaining = params.steps
		wander.currentDirection = wander.currentDirection + math.rad(params.turnAngle)
	end

	return true
end

-- ============================================
-- クールタイムモード
-- ============================================

function AIState:executeCooldownMode()
	-- クールタイム終了
	if os.clock() >= self.cooldownUntil then
		self.currentMode = nil
		print(("[AIBehavior] %s クールタイム終了"):format(self.monster.Name))
		return false
	end

	-- クールタイム中は徘徊
	self:executeWanderMode()
	return true
end

-- ============================================
-- メイン更新関数
-- ============================================

function AIState:update(playerPos, playerDist, BattleSystem)
	-- 基本チェック
	if not self.monster.Parent or not self.humanoid or not self.root then
		return false
	end

	-- 倒された状態
	if self.monster:GetAttribute("Defeated") then
		return false
	end

	-- バトル状態確認
	local isGlobalBattle = BattleSystem and BattleSystem.isAnyBattleActive and BattleSystem.isAnyBattleActive()
	local isThisMonsterInBattle = self.monster:GetAttribute("InBattle")
	local isAnyBattle = isGlobalBattle or isThisMonsterInBattle

	-- バトル中は停止
	if isAnyBattle then
		self.humanoid.WalkSpeed = 0
		self.humanoid:MoveTo(self.root.Position)
		self.wasInBattle = true
		return true
	end

	-- バトル終了後は速度復元
	if self.wasInBattle and not isAnyBattle then
		self.humanoid.WalkSpeed = self.originalSpeed
		self.wasInBattle = false
	end

	-- 海チェック
	local isInWater = self.root.Position.Y < 0 or self.humanoid:GetState() == Enum.HumanoidStateType.Swimming
	if isInWater then
		return true
	end

	-- 行動モード処理
	if self.currentMode == "COOLDOWN" then
		return self:executeCooldownMode()
	elseif self.modeType == "FLEE" then
		return self:executeFleeMode(playerPos, playerDist)
	elseif self.modeType == "CHASE" then
		return self:executeChaseMode(playerPos, playerDist)
	else -- WANDER
		return self:executeWanderMode()
	end
end

-- ============================================
-- エクスポート
-- ============================================

return {
	AIState = AIState,
	initializeBraveValue = initializeBraveValue,
	calculateFleeParameters = calculateFleeParameters,
	calculateChaseParameters = calculateChaseParameters,
	calculateWanderParameters = calculateWanderParameters,
}
