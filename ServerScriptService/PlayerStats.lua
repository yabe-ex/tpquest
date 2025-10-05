-- ServerScriptService/PlayerStats.lua
-- プレイヤーのステータスを管理するModuleScript

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerStats = {}

-- RemoteEventを取得する関数
local function getRemoteEvent(name)
	return ReplicatedStorage:WaitForChild(name, 10)
end

-- デフォルトステータス
local DEFAULT_STATS = {
	Level = 1,
	Experience = 0,
	Gold = 100,  -- 初期ゴールド100G

	MaxHP = 100,
	CurrentHP = 100,

	Speed = 10,      -- 素早さ
	Attack = 10,     -- 攻撃力
	Defense = 10,    -- 守備力
	MonstersDefeated = 0,
}

-- レベルアップに必要な経験値（レベル * 100）
local function getRequiredExp(level)
	return level * 100
end

-- 各プレイヤーのステータスを保存
local PlayerData = {}

-- プレイヤーのステータスを初期化
function PlayerStats.initPlayer(player: Player)
	if PlayerData[player] then
		warn(("[PlayerStats] %s は既に初期化済みです"):format(player.Name))
		return
	end

	-- デフォルト値でステータスを作成
	PlayerData[player] = {}
	for key, value in pairs(DEFAULT_STATS) do
		PlayerData[player][key] = value
	end

	print(("[PlayerStats] %s のステータスを初期化しました"):format(player.Name))

	-- TODO: DataStoreから読み込み
end

-- プレイヤーのステータスを取得
function PlayerStats.getStats(player: Player)
	return PlayerData[player]
end

-- 特定のステータスを取得
function PlayerStats.getStat(player: Player, statName: string)
	local stats = PlayerData[player]
	if not stats then
		warn(("[PlayerStats] %s のステータスが見つかりません"):format(player.Name))
		return nil
	end
	return stats[statName]
end

-- 特定のステータスを設定
function PlayerStats.setStat(player: Player, statName: string, value)
	local stats = PlayerData[player]
	if not stats then
		warn(("[PlayerStats] %s のステータスが見つかりません"):format(player.Name))
		return
	end

	stats[statName] = value
	print(("[PlayerStats] %s の %s を %s に設定"):format(player.Name, statName, tostring(value)))
end

-- HPを回復
function PlayerStats.healHP(player: Player, amount: number)
	local stats = PlayerData[player]
	if not stats then return end

	stats.CurrentHP = math.min(stats.CurrentHP + amount, stats.MaxHP)
	print(("[PlayerStats] %s のHPを %d 回復（現在: %d/%d）"):format(
		player.Name, amount, stats.CurrentHP, stats.MaxHP
		))
end

-- HPを全回復
function PlayerStats.fullHeal(player: Player)
	local stats = PlayerData[player]
	if not stats then return end

	stats.CurrentHP = stats.MaxHP
	print(("[PlayerStats] %s のHPを全回復"):format(player.Name))
end

-- ダメージを受ける
function PlayerStats.takeDamage(player: Player, damage: number): boolean
	local stats = PlayerData[player]
	if not stats then return false end

	stats.CurrentHP = math.max(0, stats.CurrentHP - damage)
	print(("[PlayerStats] %s が %d ダメージを受けた（残りHP: %d/%d）"):format(
		player.Name, damage, stats.CurrentHP, stats.MaxHP
		))

	-- ステータス更新を送信
	local StatusUpdateEvent = getRemoteEvent("StatusUpdate")
	if StatusUpdateEvent then
		local expToNext = getRequiredExp(stats.Level)
		StatusUpdateEvent:FireClient(
			player,
			stats.CurrentHP,
			stats.MaxHP,
			stats.Level,
			stats.Experience,
			expToNext,
			stats.Gold
		)
	end

	-- 死亡判定
	if stats.CurrentHP <= 0 then
		print(("[PlayerStats] %s は倒れた！"):format(player.Name))
		return true  -- 死亡
	end

	return false  -- 生存
end

-- 経験値を追加
function PlayerStats.addExperience(player: Player, exp: number)
	local stats = PlayerData[player]
	if not stats then return end

	stats.Experience = stats.Experience + exp
	print(("[PlayerStats] %s が経験値 %d を獲得（合計: %d）"):format(
		player.Name, exp, stats.Experience
		))

	-- レベルアップチェック
	local requiredExp = getRequiredExp(stats.Level)
	while stats.Experience >= requiredExp do
		PlayerStats.levelUp(player)
		requiredExp = getRequiredExp(stats.Level)
	end

	-- ステータス更新を送信
	local StatusUpdateEvent = getRemoteEvent("StatusUpdate")
	if StatusUpdateEvent then
		local expToNext = getRequiredExp(stats.Level)
		StatusUpdateEvent:FireClient(
			player,
			stats.CurrentHP,
			stats.MaxHP,
			stats.Level,
			stats.Experience,
			expToNext,
			stats.Gold
		)
	end
end

-- ゴールドを追加
function PlayerStats.addGold(player: Player, gold: number)
	local stats = PlayerData[player]
	if not stats then return end

	stats.Gold = stats.Gold + gold
	print(("[PlayerStats] %s がゴールド %d を獲得（合計: %d）"):format(
		player.Name, gold, stats.Gold
		))

	-- ステータス更新を送信
	local StatusUpdateEvent = getRemoteEvent("StatusUpdate")
	if StatusUpdateEvent then
		local expToNext = getRequiredExp(stats.Level)
		StatusUpdateEvent:FireClient(
			player,
			stats.CurrentHP,
			stats.MaxHP,
			stats.Level,
			stats.Experience,
			expToNext,
			stats.Gold
		)
	end
end

-- ゴールドを減らす
function PlayerStats.removeGold(player: Player, gold: number): boolean
	local stats = PlayerData[player]
	if not stats then return false end

	if stats.Gold < gold then
		print(("[PlayerStats] %s のゴールドが不足しています"):format(player.Name))
		return false
	end

	stats.Gold = stats.Gold - gold
	print(("[PlayerStats] %s がゴールド %d を失った（残り: %d）"):format(
		player.Name, gold, stats.Gold
		))
	return true
end

-- 倒したモンスター数を追加
function PlayerStats.addMonstersDefeated(player: Player, count: number)
	print(("[PlayerStats] ========================================"):format())
	print(("[PlayerStats] addMonstersDefeated 呼び出し"):format())
	print(("  プレイヤー: %s"):format(player.Name))
	print(("  追加数: %d"):format(count or 1))

	local stats = PlayerData[player]
	if not stats then
		warn(("[PlayerStats] ❌ %s のステータスが見つかりません（モンスターカウント失敗）"):format(player.Name))
		print(("[PlayerStats] ========================================"):format())
		return
	end

	local oldCount = stats.MonstersDefeated
	count = count or 1
	stats.MonstersDefeated = stats.MonstersDefeated + count

	print(("  変更前: %d"):format(oldCount))
	print(("  変更後: %d"):format(stats.MonstersDefeated))
	print(("[PlayerStats] ✅ モンスター撃破数更新成功"):format())
	print(("[PlayerStats] ========================================"):format())
end

-- レベルアップ
function PlayerStats.levelUp(player: Player)
	local stats = PlayerData[player]
	if not stats then return end

	local oldLevel = stats.Level
	stats.Level = stats.Level + 1

	-- ステータスアップ
	stats.MaxHP = stats.MaxHP + 10
	stats.CurrentHP = stats.MaxHP  -- 全回復
	stats.Speed = stats.Speed + 2
	stats.Attack = stats.Attack + 2
	stats.Defense = stats.Defense + 2

	print(("[PlayerStats] 🎉 %s がレベルアップ！ %d → %d"):format(
		player.Name, oldLevel, stats.Level
		))
	print(("  HP: %d, 素早さ: %d, 攻撃: %d, 守備: %d"):format(
		stats.MaxHP, stats.Speed, stats.Attack, stats.Defense
		))

	-- クライアントにレベルアップ演出を通知
	local LevelUpEvent = getRemoteEvent("LevelUp")
	if LevelUpEvent then
		LevelUpEvent:FireClient(player, stats.Level, stats.MaxHP, stats.Speed, stats.Attack, stats.Defense)
	end

	-- ステータス更新を送信
	local StatusUpdateEvent = getRemoteEvent("StatusUpdate")
	if StatusUpdateEvent then
		local expToNext = stats.Level * 100
		StatusUpdateEvent:FireClient(
			player,
			stats.CurrentHP,
			stats.MaxHP,
			stats.Level,
			stats.Experience,
			expToNext,
			stats.Gold
		)
	end
end

-- プレイヤーが退出したらデータをクリア
function PlayerStats.removePlayer(player: Player)
	-- TODO: DataStoreに保存
	PlayerData[player] = nil
	print(("[PlayerStats] %s のデータを削除しました"):format(player.Name))
end

-- 初期化
function PlayerStats.init()
	-- 既存のプレイヤーを初期化
	for _, player in ipairs(Players:GetPlayers()) do
		PlayerStats.initPlayer(player)
	end

	-- 新規参加プレイヤーを初期化
	Players.PlayerAdded:Connect(function(player)
		PlayerStats.initPlayer(player)
	end)

	-- 退出時にデータをクリア
	Players.PlayerRemoving:Connect(function(player)
		PlayerStats.removePlayer(player)
	end)

	-- 詳細ステータスリクエスト用RemoteEvent
	local RequestStatsDetailEvent = ReplicatedStorage:FindFirstChild("RequestStatsDetail")
	if not RequestStatsDetailEvent then
		RequestStatsDetailEvent = Instance.new("RemoteEvent")
		RequestStatsDetailEvent.Name = "RequestStatsDetail"
		RequestStatsDetailEvent.Parent = ReplicatedStorage
	end

	RequestStatsDetailEvent.OnServerEvent:Connect(function(player)
		local stats = PlayerStats.getStats(player)
		if stats then
			-- StatsDetailEventを取得または作成
			local StatsDetailEvent = ReplicatedStorage:FindFirstChild("StatsDetail")
			if not StatsDetailEvent then
				StatsDetailEvent = Instance.new("RemoteEvent")
				StatsDetailEvent.Name = "StatsDetail"
				StatsDetailEvent.Parent = ReplicatedStorage
				print("[PlayerStats] StatsDetailイベントを作成しました")
			end

			print(("[PlayerStats] 詳細ステータスを送信: MonstersDefeated=%d"):format(stats.MonstersDefeated or 0))
			StatsDetailEvent:FireClient(player, stats)
		end
	end)

	print("[PlayerStats] 初期化完了")
end

return PlayerStats