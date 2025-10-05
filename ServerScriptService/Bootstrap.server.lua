-- ServerScriptService/Bootstrap.server.lua
-- ゲーム初期化スクリプト（最終安定版 - セーブ機能有効）

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

print("[Bootstrap] === ゲーム初期化開始 ===")

-- ZoneManagerを読み込み
local ZoneManager = require(script.Parent.ZoneManager)
-- PlayerStatsのロードはsetupPlayerSpawnに任せ、ここではWaitForChildで参照を用意
local PlayerStats = ServerScriptService:WaitForChild("PlayerStats")

local START_ZONE_NAME = "ContinentTown"

-- PlayerStatsの初期化（ロード処理はPlayerStats内でtask.spawnに任せる）
require(PlayerStats).init()

print("[Bootstrap] 街を生成中...")
-- 最初にデフォルトゾーンをロード (地形生成を開始)
ZoneManager.LoadZone(START_ZONE_NAME)

task.wait(5)
print("[Bootstrap] 地形生成の待機完了（5秒）")

-- 街の設定を取得
local IslandsRegistry = require(ReplicatedStorage.Islands.Registry)
local townConfig = nil
for _, island in ipairs(IslandsRegistry) do
	if island.name == "StartTown" then
		townConfig = island
		break
	end
end

if not townConfig then
	warn("[Bootstrap] StartTown の設定が見つかりません！")
	return
end

-- ポータル生成の呼び出し
if _G.CreatePortalsForZone then
    print(("[Bootstrap] %s のポータルを生成中..."):format(START_ZONE_NAME))
    _G.CreatePortalsForZone(START_ZONE_NAME)
else
    warn("[Bootstrap] ⚠️ エラー回避: WarpPortal.server.luaがまだ初期化されていないか、グローバル関数をエクスポートしていません。ポータル生成をスキップします。")
end


-- プレイヤーのスポーン位置を街に設定
local function setupPlayerSpawn(player)

    player.CharacterAdded:Connect(function(character)
        task.spawn(function()

            -- 【重要】物理エンジン安定のため待機
            task.wait(0.5)

            local hrp = character:WaitForChild("HumanoidRootPart", 5)
            if not hrp then return end

            -- PlayerStats.initPlayer(データロード)をここ（非同期タスク内）で実行し、スポーン位置を取得
            local loadedLocation = require(PlayerStats).initPlayer(player)

            local spawnZone = loadedLocation.ZoneName
            local currentZone = ZoneManager.GetPlayerZone(player)

            -- ゾーンが設定済み（＝一度移動した）の場合は、二重スポーンを防ぐためスキップ
            if currentZone then
                return
            end

            -- ロードされたゾーンがTown以外の場合、再度ロードをトリガー
            if spawnZone ~= START_ZONE_NAME then
                ZoneManager.LoadZone(spawnZone)
            end

            local spawnX = loadedLocation.X
            local spawnZ = loadedLocation.Z
            local spawnY = loadedLocation.Y

            -- ロード座標を使用するが、Townの場合は安全なY座標に固定
            if spawnZone == START_ZONE_NAME then
                spawnY = townConfig.baseY + 50
                spawnX = townConfig.centerX
                spawnZ = townConfig.centerZ
            end

            print(("[Bootstrap] %s を %s にテレポート: (%.0f, %.0f, %.0f)"):format(
                player.Name, spawnZone, spawnX, spawnY, spawnZ
                ))

            -- CFrame設定 (テレポート)
            hrp.CFrame = CFrame.new(spawnX, spawnY, spawnZ)

            -- プレイヤーのゾーン情報を設定
            ZoneManager.PlayerZones[player] = spawnZone

        end)
    end)
end


-- 既存プレイヤーと新規プレイヤーに適用
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayerSpawn(player)
end

Players.PlayerAdded:Connect(setupPlayerSpawn)

task.spawn(function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
	if not soundsFolder then
		soundsFolder = Instance.new("Folder")
		soundsFolder.Name = "Sounds"
		soundsFolder.Parent = ReplicatedStorage
	end

	if not soundsFolder:FindFirstChild("TypingCorrect") then
		local typingCorrect = Instance.new("Sound")
		typingCorrect.Name = "TypingCorrect"
		typingCorrect.SoundId = "rbxassetid://159534615"
		typingCorrect.Volume = 0.4
		typingCorrect.Parent = soundsFolder
	end

	if not soundsFolder:FindFirstChild("TypingError") then
		local typingError = Instance.new("Sound")
		typingError.Name = "TypingError"
		typingError.SoundId = "rbxassetid://113721818600044"
		typingError.Volume = 0.5
		typingError.Parent = soundsFolder
	end

	print("[Bootstrap] Soundsフォルダを初期化しました")
end)

print("[Bootstrap] === ゲーム初期化完了 ===")
print(("[Bootstrap] プレイヤーは街（%s）からスタートします"):format(START_ZONE_NAME))