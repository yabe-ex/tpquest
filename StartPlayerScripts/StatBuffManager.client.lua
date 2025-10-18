-- StarterPlayer/StarterPlayerScripts/StatBuffManager.client.lua
-- ステータスバフシステム（@ キー = WalkSpeed、- キー = JumpPower）

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
print("[StatBuffManager] 初期化開始")

-- バフレベル管理（1.0, 2.0, 3.0, 4.0, 8.0）
local buffState = {
	WalkSpeed = 1.0,
	JumpPower = 1.0,
}

-- デフォルト値（リセット用）
local defaultStats = {
	WalkSpeed = 16, -- Roblox デフォルト
	JumpPower = 50, -- Roblox デフォルト（古い方式）
	JumpHeight = 7.2, -- Roblox デフォルト（新しい方式）
}

-- ★ 汎用バフ適用関数
-- statName: "WalkSpeed" or "JumpPower"
-- multiplier: 1.0, 2.0, 3.0, 4.0 など
local function applyStatBuff(statName, multiplier)
	local character = player.Character
	if not character then
		warn("[StatBuffManager] キャラクターが見つかりません")
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("[StatBuffManager] Humanoid が見つかりません")
		return false
	end

	multiplier = math.clamp(tonumber(multiplier) or 1, 0.5, 10) -- 0.5x ～ 10x の範囲

	if statName == "WalkSpeed" then
		local newSpeed = defaultStats.WalkSpeed * multiplier
		humanoid.WalkSpeed = newSpeed
		print(
			("[StatBuffManager] WalkSpeed: %.1f → %.1f (倍率: %.1f倍)"):format(
				defaultStats.WalkSpeed,
				newSpeed,
				multiplier
			)
		)
		return true
	elseif statName == "JumpPower" then
		local newPower = defaultStats.JumpPower * multiplier
		humanoid.JumpPower = newPower
		-- 新しい方式（JumpHeight）にも対応
		humanoid.JumpHeight = defaultStats.JumpHeight * multiplier
		print(
			("[StatBuffManager] JumpPower: %.1f → %.1f (倍率: %.1f倍)"):format(
				defaultStats.JumpPower,
				newPower,
				multiplier
			)
		)
		return true
	else
		warn(("[StatBuffManager] 未知のステータス: %s"):format(statName))
		return false
	end
end

-- ★ バフレベルをサイクル
local buffMultipliers = { 1.0, 2.0, 3.0, 4.0, 8.0, 16.0 }

local function cycleBuffLevel(statName)
	local currentLevel = buffState[statName] or 1.0
	local currentIndex = 1

	-- 現在のレベルをテーブルから探す
	for i, mult in ipairs(buffMultipliers) do
		if math.abs(mult - currentLevel) < 0.01 then
			currentIndex = i
			break
		end
	end

	-- 次のレベルへサイクル
	local nextIndex = (currentIndex % #buffMultipliers) + 1
	local nextLevel = buffMultipliers[nextIndex]

	buffState[statName] = nextLevel
	applyStatBuff(statName, nextLevel)

	print(("[StatBuffManager] %s レベル: %d/4 (倍率: %.1f倍)"):format(statName, nextIndex, nextLevel))

	return nextLevel
end

-- キャラクター生成時にバフ状態をリセット
player.CharacterAdded:Connect(function(character)
	print("[StatBuffManager] 新しいキャラクターが生成されました")

	-- バフ状態を初期化
	buffState.WalkSpeed = 1.0
	buffState.JumpPower = 1.0

	-- デフォルト値を適用
	task.wait(0.1)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = defaultStats.WalkSpeed
		humanoid.JumpPower = defaultStats.JumpPower
		humanoid.JumpHeight = defaultStats.JumpHeight
		print("[StatBuffManager] デフォルト値をリセット完了")
	end
end)

-- @ キーでWalkSpeedバフ
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	-- ★ @ から P キーに変更（@ はシステム予約キーのため）
	if input.KeyCode == Enum.KeyCode.P then
		print("[StatBuffManager] P キーが押されました")
		cycleBuffLevel("WalkSpeed")
	end
end)

-- - キー（ハイフン）でJumpPowerバフ
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.Minus then
		print("[StatBuffManager] - キーが押されました")
		cycleBuffLevel("JumpPower")
	end
end)

-- ★ 外部から呼び出せるAPI（将来の拡張用）
_G.StatBuffManager = {
	applyStatBuff = applyStatBuff,
	getBuffLevel = function(statName)
		return buffState[statName] or 1.0
	end,
	resetBuffs = function()
		buffState.WalkSpeed = 1.0
		buffState.JumpPower = 1.0
		applyStatBuff("WalkSpeed", 1.0)
		applyStatBuff("JumpPower", 1.0)
		print("[StatBuffManager] すべてのバフをリセット")
	end,
}

print("[StatBuffManager] 初期化完了")
print("[StatBuffManager] P キー: WalkSpeed バフ (1.0x → 2.0x → 3.0x → 4.0x → 8.0x → 1.0x)")
print("[StatBuffManager] - キー: JumpPower バフ (1.0x → 2.0x → 3.0x → 4.0x → 8.0x → 1.0x)")
