-- ReplicatedStorage/Monsters/Slime.lua
-- ReplicatedStorage/Monsters/Slime
-- スライムの定義（ステータス拡張版）

return {
	Name = "RubySlime",
	TemplatePath = { "ServerStorage", "EnemyTemplates", "SlimeTemplate" },
	WalkSpeed = 10,
	RespawnTime = 10,

	-- 【新】バトルステータス
	HP = 80, -- ライフ
	Speed = 5, -- 素早さ
	Attack = 20, -- 攻撃力
	Defense = 5, -- 守備力

	-- 【新】報酬
	Experience = 10, -- 倒した時に得られる経験値
	Gold = 10, -- 倒した時に得られるゴールド

	-- タイピングレベル（重み付き）
	TypingLevels = {
		{ level = "level_1", weight = 70 }, -- 70%の確率でレベル1
		{ level = "level_2", weight = 30 }, -- 30%の確率でレベル2
	},

	-- 旧設定（互換性のため残す）
	Damage = 1, -- 後で削除予定

	-- スポーン設定
	SpawnLocations = {
		{
			islandName = "Hokkaido_02",
			count = 7,
			radiusPercent = 95, -- 島のサイズの75%範囲内
		},
		{
			islandName = "Hokkaido_N1",
			count = 7,
			radiusPercent = 95, -- 島のサイズの75%範囲内
		},
	},

	ColorProfile = {
		Body = Color3.fromRGB(255, 255, 255), -- 体の色
		Body = Color3.fromRGB(255, 0, 0), -- 体の色

		EyeTexture = "rbxassetid://126158076889568",
		EyeSize = 0.18, -- 比率での大きさ
		EyeY = 0.35, -- 縦位置
		EyeSeparation = 0.18, -- 左右の離れ具合
		EyeAlwaysOnTop = true, -- trueだと前面描画（浮きやすい）
		EyeSizingMode = "Scale", -- "Scale" or "Pixels"
		PixelsPerStud = 60, -- SizingMode="Pixels"時の密度
		EyePixelSize = 120, -- SizingMode="Pixels"時の正方形サイズ(px)

		-- GlowColor = nil, -- nilならBody/Coreから自動取得
		-- GlowBrightness = 1.5, -- 明るさ（1〜3）PointLight.Brightness
		-- GlowRange = 10, -- 光の届く範囲（8〜12が自然）
		-- GlowTransparency = 0.15, -- Highlight.FillTransparency（小さいほど強く光る）
		-- GlowOutline = 1, -- Highlight.OutlineTransparency（1で輪郭非表示）
		-- GlowEnabled = true, -- 発光を無効化したい場合はfalse
	},

	-- AI設定
	ChaseDistance = 60,
	EscapeDistance = 80,
	WanderRadius = 30,
	UpdateNearby = 0.2,
	UpdateFar = 1.0,
}
