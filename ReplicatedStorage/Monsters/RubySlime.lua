-- ReplicatedStorage/Monsters/RubySlime.lua
-- 新AI行動システム対応版

return {
	Name = "RubySlime",
	TemplatePath = { "ServerStorage", "EnemyTemplates", "SlimeTemplate" },
	WalkSpeed = 10,
	RespawnTime = 10,

	-- ============================================
	-- バトルステータス
	-- ============================================
	HP = 80,
	Speed = 5,
	Attack = 20,
	Defense = 5,
	Experience = 10,
	Gold = 10,

	-- ============================================
	-- 【NEW】AI行動パラメータ（最適化版）
	-- ============================================
	AIBehavior = {
		-- 【共通】トリガー距離とクールタイム
		TriggerDistance = 60, -- プレイヤー検出距離
		ActionCooldown = 15, -- 行動後のクールタイム（秒）

		-- 【逃げモード】Brave < 5 時のパラメータ
		Flee = {
			BaseEscapeDistance = 80, -- 逃げ終了距離の基準値
			BaseMaxDuration = 15, -- 逃げ時間の上限（秒）
		},

		-- 【追跡モード】Brave > 5 時のパラメータ
		Chase = {
			BaseChaseDistance = 10, -- 追跡終了距離の基準値
			BaseMaxDuration = 20, -- 追跡時間の上限（秒）
		},

		-- 【ランダムウォーク】Brave == 5 時のパラメータ
		Wander = {
			MinSteps = 3, -- 最小歩数
			MaxSteps = 8, -- 最大歩数
			StepDistance = 5, -- 1ステップの距離（スタッド）

			MinWaitTime = 0.5, -- 最小停止時間（秒）
			MaxWaitTime = 3, -- 最大停止時間（秒）

			PauseChance = 0.4, -- 一定確率で停止（0-1）

			TurnAngleMin = 30, -- 最小ターン角度（度）
			TurnAngleMax = 120, -- 最大ターン角度（度）

			Range = 50, -- ウォーク範囲（中心からの距離）
		},
	},

	-- ============================================
	-- 【NEW】勇敢さパラメータ
	-- ============================================
	BraveBehavior = {
		-- 平均勇敢さ（0-10）
		-- 0: 全力で逃げる
		-- 5: その場で待機（ランダムウォーク）
		-- 10: 全力で追いかける
		AverageBrave = 2,

		-- 分散（標準偏差）
		-- ほぼ 平均 ± 分散 の範囲でランダム決定
		Variance = 1.5,

		-- 結果例: AverageBrave=2, Variance=1.5
		-- → ほぼ 0.5 ～ 3.5 の値になる
		-- → 実際には 0 ～ 10 でクランプ
	},

	-- ============================================
	-- タイピングレベル（既存のまま）
	-- ============================================
	TypingLevels = {
		{ level = "level_1", weight = 70 },
		{ level = "level_2", weight = 30 },
	},

	Damage = 1, -- 後で削除予定

	-- ============================================
	-- スポーン設定（既存のまま）
	-- ============================================
	SpawnLocations = {
		{
			islandName = "Hokkaido_02",
			count = 7,
			radiusPercent = 95,
		},
		{
			islandName = "Hokkaido_N1",
			count = 7,
			radiusPercent = 95,
		},
	},

	-- ============================================
	-- カラー設定（既存のまま）
	-- ============================================
	ColorProfile = {
		Body = Color3.fromRGB(255, 0, 0), -- 赤色

		EyeTexture = "rbxassetid://126158076889568",
		EyeSize = 0.18,
		EyeY = 0.35,
		EyeSeparation = 0.18,
		EyeAlwaysOnTop = true,
		EyeSizingMode = "Scale",
		PixelsPerStud = 60,
		EyePixelSize = 120,
	},
}
