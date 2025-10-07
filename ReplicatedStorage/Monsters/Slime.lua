-- ReplicatedStorage/Monsters/Slime.lua
-- ReplicatedStorage/Monsters/Slime
-- スライムの定義（ステータス拡張版）

return {
	Name = "Slime",
	TemplatePath = {"ServerStorage", "EnemyTemplates", "Slime"},
	WalkSpeed = 10,
	RespawnTime = 10,

	-- 【新】バトルステータス
	HP = 50,           -- ライフ
	Speed = 5,         -- 素早さ
	Attack = 20,        -- 攻撃力
	Defense = 5,       -- 守備力

	-- 【新】報酬
	Experience = 20,   -- 倒した時に得られる経験値
	Gold = 10,         -- 倒した時に得られるゴールド

	-- タイピングレベル（重み付き）
	TypingLevels = {
		{level = "level_1", weight = 70},  -- 70%の確率でレベル1
		{level = "level_2", weight = 30},  -- 30%の確率でレベル2
	},

	-- 旧設定（互換性のため残す）
	Damage = 1,  -- 後で削除予定

	-- スポーン設定
	SpawnLocations = {
		{
			islandName = "Hokkaido_N1",
			count = 7,
			radiusPercent = 95,  -- 島のサイズの75%範囲内
		},
		{
			islandName = "Hokkaido_N4",
			count = 15,
			radiusPercent = 55,  -- 島のサイズの75%範囲内
		},
				{
			islandName = "Kyushu_NE1",
			count = 5,
			radiusPercent = 55,  -- 島のサイズの75%範囲内
		},

	},

	-- AI設定
	ChaseDistance = 60,
	EscapeDistance = 80,
	WanderRadius = 30,
	UpdateNearby = 0.2,
	UpdateFar = 1.0,
}