-- ServerScriptService/DebugCommands.server.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

print("[DebugCommands] 初期化開始")

-- デバッグモード（本番環境ではfalseに）
local DEBUG_MODE = true

if not DEBUG_MODE then
	print("[DebugCommands] デバッグモードOFF")
	return
end

-- 【修正】RemoteEventを必ず作成
local DebugCommandEvent = Instance.new("RemoteEvent")
DebugCommandEvent.Name = "DebugCommand"
DebugCommandEvent.Parent = ReplicatedStorage
print("[DebugCommands] RemoteEventを作成しました")

-- 依存モジュール
local PlayerStatsModule = require(ServerScriptService:WaitForChild("PlayerStats"))

-- コマンド処理
DebugCommandEvent.OnServerEvent:Connect(function(player, command, ...)
	print(("[DebugCommands] %s が実行: %s"):format(player.Name, command))

	if command == "reset_chests" then
		-- 宝箱リセット
		print("[DebugCommands DEBUG] リセット開始")

		local stats = PlayerStatsModule.getStats(player)
		if stats then
			print("[DebugCommands DEBUG] ステータス取得成功")

			-- リセット前の状態
			local beforeCount = 0
			for _ in pairs(stats.CollectedItems) do beforeCount = beforeCount + 1 end
			print(("[DebugCommands DEBUG] リセット前: %d個"):format(beforeCount))

			-- CollectedItemsを空にする
			stats.CollectedItems = {}

			-- リセット後の状態
			local afterCount = 0
			for _ in pairs(stats.CollectedItems) do afterCount = afterCount + 1 end
			print(("[DebugCommands DEBUG] リセット後: %d個"):format(afterCount))

			print(("[DebugCommands] %s の取得済みアイテムをリセットしました"):format(player.Name))

			-- 即座にセーブ
			if _G.AutoSavePlayer then
				print("[DebugCommands DEBUG] セーブ開始")
				_G.AutoSavePlayer(player, "デバッグリセット")
				task.wait(2)
				print("[DebugCommands DEBUG] セーブ完了")
			else
				warn("[DebugCommands DEBUG] AutoSavePlayer が見つかりません")
			end

			-- 手動セーブも試行
			local DataStoreManager = require(ServerScriptService:WaitForChild("DataStoreManager"))
			local DataCollectors = require(ServerScriptService:WaitForChild("DataCollectors"))

			local saveData = DataCollectors.createSaveData(player, stats)
			print(("[DebugCommands DEBUG] セーブデータ作成: CollectedItems = %s"):format(
				game:GetService("HttpService"):JSONEncode(saveData.CollectedItems)
			))

			DataStoreManager.SavePlayerData(player, saveData)
			print("[DebugCommands DEBUG] 手動セーブ完了")

		else
			warn(("[DebugCommands] %s のステータスが見つかりません"):format(player.Name))
		end
	else
		warn(("[DebugCommands] 未知のコマンド: %s"):format(command))
	end
end)

print("[DebugCommands] 初期化完了")