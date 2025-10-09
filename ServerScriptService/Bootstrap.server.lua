-- ServerScriptService/Bootstrap.server.lua
-- ゲーム初期化スクリプト（最終安定版 - DataStoreロード安定化）

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

print("[Bootstrap] === ゲーム初期化開始 (最終安定版) ===")

-- ZoneManagerを読み込み（ServerScriptServiceの兄弟モジュール）
local ZoneManager = require(script.Parent:WaitForChild("ZoneManager"))

-- PlayerStatsのModuleScriptの実行結果をロード（ServerScriptServiceの兄弟モジュール）
local PlayerStatsModule = require(script.Parent:WaitForChild("PlayerStats"))
local DataCollectors = require(script.Parent:WaitForChild("DataCollectors"))

local START_ZONE_NAME = "ContinentTown"
local LOAD_TIMEOUT = 10 -- DataStoreロードのタイムアウト(秒)

-- プレイヤーごとのロードデータ管理
local LastLoadedLocation = {}
local LastLoadedData = {}

-- PlayerStatsの初期化（DataStoreロード処理を含む）
PlayerStatsModule.init()

print("[Bootstrap] セーブ機能を初期化中...")

local SaveGameEvent = ReplicatedStorage:FindFirstChild("SaveGame")
if not SaveGameEvent then
    SaveGameEvent = Instance.new("RemoteEvent")
    SaveGameEvent.Name = "SaveGame"
    SaveGameEvent.Parent = ReplicatedStorage
    print("[Bootstrap] ✓ SaveGameイベント作成")
end

local SaveSuccessEvent = ReplicatedStorage:FindFirstChild("SaveSuccess")
if not SaveSuccessEvent then
    SaveSuccessEvent = Instance.new("RemoteEvent")
    SaveSuccessEvent.Name = "SaveSuccess"
    SaveSuccessEvent.Parent = ReplicatedStorage
    print("[Bootstrap] ✓ SaveSuccessイベント作成")
end

-- DataStoreManagerとDataCollectorsをロード
local DataStoreManager = require(ServerScriptService:WaitForChild("DataStoreManager"))
local DataCollectors = require(ServerScriptService:WaitForChild("DataCollectors"))

-- セーブイベントハンドラを登録
SaveGameEvent.OnServerEvent:Connect(function(player)
    print(("[Bootstrap] 💾 %s からセーブリクエスト受信"):format(player.Name))

    -- プレイヤーのステータスを取得
    local stats = PlayerStatsModule.getStats(player)
    if not stats then
        warn(("[Bootstrap] ❌ %s のステータスが見つかりません"):format(player.Name))
        SaveSuccessEvent:FireClient(player, false)
        return
    end

    -- セーブデータを作成
    local saveData = DataCollectors.createSaveData(player, stats)

    print(("[Bootstrap] 📦 セーブデータ作成完了"):format())

    -- DataStoreに保存
    local success = DataStoreManager.SaveData(player, saveData)

    if success then
        print(("[Bootstrap] ✅ %s のセーブ成功"):format(player.Name))
    else
        warn(("[Bootstrap] ❌ %s のセーブ失敗"):format(player.Name))
    end
end)

print("[Bootstrap] ✓ セーブ機能の初期化完了")

print("[Bootstrap] 街を生成中（非同期）...")
task.spawn(function()
    ZoneManager.LoadZone(START_ZONE_NAME)
    print("[Bootstrap] 地形生成完了")
end)

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
-- プレイヤーのスポーン位置を街に設定
local function setupPlayerSpawn(player)

    local characterAddedConnection = nil

    -- DataStoreからのロード処理（非同期）
    local function startDataStoreLoad()
        task.spawn(function()
            print(("[Bootstrap] %s のDataStoreロード開始"):format(player.Name))

            -- PlayerStatsModuleのinitPlayerを呼び出し、ロード結果（Locationテーブル）を取得
            local loadedLocation = PlayerStatsModule.initPlayer(player)

            -- 【追加】完全なロードデータも取得
            local fullLoadedData = PlayerStatsModule.getLastLoadedData(player)

            -- nilチェック（ロード失敗時のフォールバック）
            if not loadedLocation then
                warn(("[Bootstrap] %s のロードデータがnil、デフォルト使用"):format(player.Name))
                loadedLocation = {
                    ZoneName = "ContinentTown",
                    X = townConfig.centerX,
                    Y = townConfig.baseY + 25,
                    Z = townConfig.centerZ
                }
            end

            -- 【変更】LastLoadedLocation → LastLoadedData に変更し、全データを保存
            LastLoadedData[player] = {
                Location = loadedLocation,
                FieldState = fullLoadedData and fullLoadedData.FieldState or nil,
                CurrentZone = fullLoadedData and fullLoadedData.CurrentZone or nil,
            }

            print(("[Bootstrap] %s のロード完了: %s (%.0f, %.0f, %.0f)"):format(
                player.Name,
                loadedLocation.ZoneName,
                loadedLocation.X,
                loadedLocation.Y,
                loadedLocation.Z
            ))
        end)
    end

    -- キャラクタースポーン時の処理
    local function performTeleportAndZoneSetup(player, character)
        -- ロードデータが準備されるまで待機
        local loadedData = LastLoadedData[player]

        local waited = 0
        while not loadedData and waited < LOAD_TIMEOUT do
            task.wait(0.1)
            waited = waited + 0.1
            loadedData = LastLoadedData[player]
        end

        if not loadedData then
            warn(("[Bootstrap] %s のロードがタイムアウトしました。デフォルト位置を使用します"):format(player.Name))
            loadedData = {
                Location = {
                    ZoneName = "ContinentTown",
                    X = townConfig.centerX,
                    Y = townConfig.baseY + 25,
                    Z = townConfig.centerZ
                },
                FieldState = nil,
                CurrentZone = nil
            }
            LastLoadedData[player] = loadedData
        end

        local loadedLocation = loadedData.Location
        local targetZone = loadedLocation.ZoneName
        local targetX = loadedLocation.X
        local targetY = loadedLocation.Y
        local targetZ = loadedLocation.Z

        print(("[Bootstrap] %s をワープします: %s (%.0f, %.0f, %.0f)"):format(
            player.Name, targetZone, targetX, targetY, targetZ
        ))

        -- ゾーン読み込みとワープ
        if targetZone ~= START_ZONE_NAME then
            print(("[Bootstrap] %s のゾーンをロード: %s"):format(player.Name, targetZone))
            ZoneManager.LoadZone(targetZone)
            task.wait(1)
        end

        local success = ZoneManager.WarpPlayerToZone(player, targetZone, targetX, targetY, targetZ, true)

        if not success then
            warn(("[Bootstrap] %s のワープに失敗しました。デフォルト位置に配置します"):format(player.Name))
            ZoneManager.WarpPlayerToZone(player, START_ZONE_NAME,
                townConfig.centerX,
                townConfig.baseY + 25,
                townConfig.centerZ,
                true
            )
        end

        -- 【重要】モンスターとポータルの復元処理
        if loadedData.FieldState and loadedData.CurrentZone then
            task.spawn(function()
                task.wait(2) -- ゾーンが完全にロードされるまで待つ

                local zoneName = loadedData.CurrentZone
                print(("[Bootstrap] %s のフィールド状態を復元: %s"):format(player.Name, zoneName))

                -- モンスター復元
                local restoreSuccess = DataCollectors.restoreFieldState(zoneName, loadedData.FieldState)

                if restoreSuccess then
                    print(("[Bootstrap] %s のモンスター復元成功"):format(player.Name))
                else
                    print(("[Bootstrap] %s のモンスター復元失敗または不要"):format(player.Name))
                end

                -- ポータル生成
                if _G.CreatePortalsForZone then
                    _G.CreatePortalsForZone(zoneName)
                    print(("[Bootstrap] %s のポータル生成完了"):format(player.Name))
                end
            end)
        else
            print(("[Bootstrap] %s は初回プレイまたはフィールド状態なし"):format(player.Name))

            -- 初回プレイの場合、通常のモンスター・ポータル生成
            if targetZone ~= START_ZONE_NAME then
                task.spawn(function()
                    task.wait(1)
                    if _G.SpawnMonstersForZone then
                        _G.SpawnMonstersForZone(targetZone)
                        print(("[Bootstrap] %s の初回モンスタースポーン完了"):format(player.Name))
                    end
                    if _G.CreatePortalsForZone then
                        _G.CreatePortalsForZone(targetZone)
                        print(("[Bootstrap] %s の初回ポータル生成完了"):format(player.Name))
                    end
                end)
            end
        end

        print(("[Bootstrap] %s のスポーン処理完了"):format(player.Name))
    end

    -- CharacterAddedイベントを接続
    characterAddedConnection = player.CharacterAdded:Connect(function(character)
        performTeleportAndZoneSetup(player, character)

        -- 一度使ったらキャッシュをクリア
        if characterAddedConnection then
            characterAddedConnection:Disconnect()
            characterAddedConnection = nil

            LastLoadedData[player] = nil
        end
    end)

    -- ロード開始
    startDataStoreLoad()

    -- 既にスポーン済みの場合
    if player.Character then
        performTeleportAndZoneSetup(player, player.Character)
    end
end
-- 既存プレイヤーに適用
for _, player in ipairs(Players:GetPlayers()) do
    setupPlayerSpawn(player)
end

-- 新規プレイヤーに適用
Players.PlayerAdded:Connect(setupPlayerSpawn)

-- 退出時のクリーンアップ
Players.PlayerRemoving:Connect(function(player)
    LastLoadedLocation[player] = nil
end)

-- 効果音の初期化
task.spawn(function()
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

-- 【追加】セーブイベントハンドラの登録
local SaveGameEvent = ReplicatedStorage:FindFirstChild("SaveGame")
if not SaveGameEvent then
    SaveGameEvent = Instance.new("RemoteEvent")
    SaveGameEvent.Name = "SaveGame"
    SaveGameEvent.Parent = ReplicatedStorage
    print("[Bootstrap] SaveGameイベントを作成しました")
end

local DataStoreManager = require(ServerScriptService:WaitForChild("DataStoreManager"))
local DataCollectors = require(ServerScriptService:WaitForChild("DataCollectors"))

SaveGameEvent.OnServerEvent:Connect(function(player)
    print(("[Bootstrap] %s からセーブリクエストを受信"):format(player.Name))

    -- プレイヤーのステータスを取得
    local stats = PlayerStatsModule.getStats(player)
    if not stats then
        warn(("[Bootstrap] %s のステータスが見つかりません"):format(player.Name))
        local SaveSuccessEvent = ReplicatedStorage:FindFirstChild("SaveSuccess")
        if SaveSuccessEvent then
            SaveSuccessEvent:FireClient(player, false)
        end
        return
    end

    -- セーブデータを作成
    local saveData = DataCollectors.createSaveData(player, stats)

    -- DataStoreに保存
    local success = DataStoreManager.SaveData(player, saveData)

    if success then
        print(("[Bootstrap] %s のセーブ成功"):format(player.Name))
    else
        warn(("[Bootstrap] %s のセーブ失敗"):format(player.Name))
    end
end)

print("[Bootstrap] セーブイベントハンドラを登録しました")

print("[Bootstrap] === ゲーム初期化完了 ===")
print(("[Bootstrap] プレイヤーは街（%s）からスタートします"):format(START_ZONE_NAME))