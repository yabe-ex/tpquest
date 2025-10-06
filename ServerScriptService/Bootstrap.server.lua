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

-- 【修正】プレイヤーごとにロードした最終位置を保存するテーブル (このバージョンでは未使用だが、ロジック維持のため残す)
local LastLoadedLocation = {}

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


-- プレイヤーのスポーン位置を街に設定
local function setupPlayerSpawn(player)

    local characterAddedConnection = nil

    -- ロード後のテレポート、ゾーン初期化処理 (CharacterAdded接続時に実行される)
    local function performTeleportAndZoneSetup(player, character)

        -- 【重要】LastLoadedLocationにデータが入るまで待機
        local loadedLocation = LastLoadedLocation[player]
        while not loadedLocation do
            task.wait(0.05) -- 50msごとにチェック (短縮限界)
            loadedLocation = LastLoadedLocation[player]
        end

        -- ★テレポート処理が一度完了したら、イベント接続を切断する
        if characterAddedConnection then
            characterAddedConnection:Disconnect()
        end

        task.spawn(function()

            -- 【重要】既にテレポート処理が完了しているか、データがない場合はスキップ
            if ZoneManager.GetPlayerZone(player) then
                return
            end

            local spawnZone = loadedLocation.ZoneName

            -- 【修正】物理エンジン安定化のための待機時間を 0.1秒 → 0.05秒に短縮
            task.wait(0.05)

            local hrp = character:WaitForChild("HumanoidRootPart", 5)
            if not hrp then return end

            -- ロードされたゾーンがTown以外の場合、Terrain生成とポータル/モンスター生成をトリガー
            if spawnZone ~= START_ZONE_NAME then
                -- 【修正ブロック】LoadZoneをここで呼び出し、地形生成の完了を待つ
                ZoneManager.LoadZone(spawnZone)

                if _G.DestroyPortalsForZone and _G.CreatePortalsForZone then
                    _G.DestroyPortalsForZone(START_ZONE_NAME)
                    _G.CreatePortalsForZone(spawnZone)
                end

                if _G.SpawnMonstersForZone then
                    _G.SpawnMonstersForZone(spawnZone)
                end
            end

            -- 座標の最終決定
            local spawnX = loadedLocation.X
            local spawnZ = loadedLocation.Z
            local spawnY = loadedLocation.Y

            -- Townゾーンであっても、ロードデータがあればそれを優先する
            local DEFAULT_X = -50
            local DEFAULT_Y = 50
            local DEFAULT_Z = 50

            local isDefaultLocation = (spawnX == DEFAULT_X and spawnY == DEFAULT_Y and spawnZ == DEFAULT_Z)

            if spawnZone == START_ZONE_NAME then
                if isDefaultLocation then
                    print(("[Bootstrap] 判定: ロード座標がデフォルトのため、Town中心に上書き: (%.0f, %.0f, %.0f)"):format(townConfig.centerX, townConfig.baseY + 50, townConfig.centerZ))
                    spawnY = townConfig.baseY + 50
                    spawnX = townConfig.centerX
                    spawnZ = townConfig.centerZ
                else
                    print(("[Bootstrap] 判定: Town内のロード位置を使用: (%.0f, %.0f, %.0f)"):format(spawnX, spawnY, spawnZ))
                end
            elseif spawnZone ~= START_ZONE_NAME then
                print(("[Bootstrap] 判定: Town外(%s)のロード位置を使用: (%.0f, %.0f, %.0f)"):format(spawnZone, spawnX, spawnY, spawnZ))
            end


            print(("[Bootstrap] 最終テレポート座標 (決定): %s (%.0f, %.0f, %.0f)"):format(
                spawnZone, spawnX,
                spawnY, spawnZ
                ))

            local hrp = character:FindFirstChild("HumanoidRootPart")
            if not hrp then return end

            -- CFrame設定 (テレポート)
            hrp.CFrame = CFrame.new(spawnX, spawnY, spawnZ)

            -- ゾーン情報を設定
            ZoneManager.PlayerZones[player] = spawnZone

            -- ロード後のポータル生成（Townの場合）
            if spawnZone == START_ZONE_NAME and _G.CreatePortalsForZone then
                _G.CreatePortalsForZone(START_ZONE_NAME)
            end
        end)
    end

    -- 【新規】PlayerAdded時にDataStoreロードを開始
    local function startDataStoreLoad()
        task.spawn(function()
            -- ★1. DataStoreからロードし、結果を待つ
            local loadedLocation = require(PlayerStats).initPlayer(player)

            -- ★2. ロードが完了したら、結果を保存
            LastLoadedLocation[player] = loadedLocation
            print(("[Bootstrap] DataStoreロード完了。座標保存済み: %s"):format(loadedLocation.ZoneName))
        end)
    end

    -- CharacterAddedイベントを接続
    characterAddedConnection = player.CharacterAdded:Connect(function(character)
         performTeleportAndZoneSetup(player, character)
    end)

    -- ロードプロセスを開始
    startDataStoreLoad()

    -- プレイヤーが既にスポーンしている場合
    if player.Character then
         performTeleportAndZoneSetup(player, player.Character)
    end
end


-- 既存プレイヤーと新規プレイヤーに適用
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayerSpawn(player)
end

Players.PlayerAdded:Connect(setupPlayerSpawn)

Players.PlayerRemoving:Connect(function(player)
    -- 退出時に保存した位置情報をクリア
    LastLoadedLocation[player] = nil
end)


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
	end

	print("[Bootstrap] Soundsフォルダを初期化しました")
end)

print("[Bootstrap] === ゲーム初期化完了 ===")
print(("[Bootstrap] プレイヤーは街（%s）からスタートします"):format(START_ZONE_NAME))