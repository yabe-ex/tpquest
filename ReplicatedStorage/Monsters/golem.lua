return {
	Name = "golem",
	TemplatePath = { "ServerStorage", "EnemyTemplates", "golem" },
	WalkSpeed = 10,
	RespawnTime = 10,

	-- 【新】バトルステータス
	HP = 250, -- ライフ
	Speed = 5, -- 素早さ
	Attack = 20, -- 攻撃力
	Defense = 5, -- 守備力

	-- 【新】報酬
	Experience = 400, -- 倒した時に得られる経験値
	Gold = 100, -- 倒した時に得られるゴールド

	-- タイピングレベル（重み付き）
	TypingLevels = {
		{ level = "level_2", weight = 70 }, -- 70%の確率でレベル1
		{ level = "level_3", weight = 30 }, -- 30%の確率でレベル2
	},

	-- 旧設定（互換性のため残す）
	Damage = 1, -- 後で削除予定

	-- スポーン設定
	SpawnLocations = {
		-- {
		-- 	islandName = "Hokkaido_N1",
		-- 	count = 3,
		-- 	radiusPercent = 95, -- 島のサイズの75%範囲内
		-- },
		-- {
		-- 	islandName = "Hokkaido_N4",
		-- 	count = 3,
		-- 	radiusPercent = 55, -- 島のサイズの75%範囲内
		-- },
		{
			islandName = "Kyushu_NE1",
			count = 3,
			radiusPercent = 55, -- 島のサイズの75%範囲内
		},
	},

	-- AI設定
	ChaseDistance = 60,
	EscapeDistance = 80,
	WanderRadius = 30,
	UpdateNearby = 0.2,
	UpdateFar = 1.0,
}
