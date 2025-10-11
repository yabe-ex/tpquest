-- ReplicatedStorage/Monsters/[モンスター名]

return {
	Name = "Slime_pink",
	TemplatePath = {"ServerStorage", "EnemyTemplates", "Slime_pink"},
	WalkSpeed = 8,
	RespawnTime = 20,

	-- 【新】バトルステータス
	HP = 80,           -- ライフ
	Speed = 10,         -- 素早さ
	Attack = 30,        -- 攻撃力
	Defense = 10,       -- 守備力

	-- 【新】報酬
	Experience = 50,   -- 倒した時に得られる経験値
	Gold = 25,         -- 倒した時に得られるゴールド

	-- タイピングレベル（重み付き）
	TypingLevels = {
		{level = "level_2", weight = 70},  -- 70%の確率でレベル1
		{level = "level_3", weight = 30},  -- 30%の確率でレベル2
	},

	-- 旧設定（互換性のため残す）
	Damage = 1,  -- 後で削除予定

	-- スポーン設定
	SpawnLocations = {
		{
			islandName = "Kyushu_C23",
			count = 3,
			radiusPercent = 80,
		},
		{
			islandName = "Kyushu_C24",
			count = 5,
			radiusPercent = 80,
		},

	},

	-- AI設定
	ChaseDistance = 60,
	EscapeDistance = 30,
	WanderRadius = 30,
	UpdateNearby = 0.2,
	UpdateFar = 1.0,
}