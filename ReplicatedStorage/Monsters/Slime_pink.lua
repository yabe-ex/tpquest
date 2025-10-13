return {
	Name = "Slime_pink",
	TemplatePath = {"ServerStorage", "EnemyTemplates", "Slime_pink"},
	WalkSpeed = 5,
	RespawnTime = 5,

	-- 【新】バトルステータス
	HP = 120,           -- ライフ
	Speed = 80,         -- 素早さ
	Attack = 40,        -- 攻撃力
	Defense = 12,       -- 守備力

	-- 【新】報酬
	Experience = 300,   -- 倒した時に得られる経験値
	Gold = 25,         -- 倒した時に得られるゴールド

	-- タイピングレベル（重み付き）
	TypingLevels = {
		{level = "level_1", weight = 30},  -- 70%の確率でレベル1
		{level = "level_2", weight = 70},  -- 30%の確率でレベル2
	},

	-- 旧設定（互換性のため残す）
	Damage = 1,  -- 後で削除予定

	-- スポーン設定
	SpawnLocations = {
		{
			islandName = "Hokkaido_N1",
			count = 7,
			radiusPercent = 65,  -- 島のサイズの75%範囲内
		},
		{
			islandName = "Hokkaido_N4",
			count = 15,
			radiusPercent = 85,  -- 島のサイズの75%範囲内
		},
				{
			islandName = "Kyushu_NE1",
			count = 5,
			radiusPercent = 55,  -- 島のサイズの75%範囲内
		},
		{
			islandName = "Kyushu_C22",
			count = 5,
			radiusPercent = 55,  -- 島のサイズの75%範囲内
		},
		{
			islandName = "ContinentKyushu_C20",
			count = 5,
			radiusPercent = 55,  -- 島のサイズの75%範囲内
		},
		{
			islandName = "ContinentKyushu_C21",
			count = 5,
			radiusPercent = 55,  -- 島のサイズの75%範囲内
		},
		{
			islandName = "ContinentKyushu_C22",
			count = 5,
			radiusPercent = 55,  -- 島のサイズの75%範囲内
		},
--
	},

	-- AI設定
	ChaseDistance = 60,
	EscapeDistance = 80,
	WanderRadius = 30,
	UpdateNearby = 0.2,
	UpdateFar = 1.0,
}