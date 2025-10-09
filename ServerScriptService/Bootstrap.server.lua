-- ServerScriptService/Bootstrap.server.lua
-- ゲーム初期化スクリプト（ステップ5: 依存関係整理版）

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

print("[Bootstrap] === ゲーム初期化開始 (ステップ5) ===")

-- ============================================
-- 1. 共有モジュールの初期化
-- ============================================
local SharedState = require(ReplicatedStorage:WaitForChild("SharedState"))
local GameEvents = require(ReplicatedStorage:WaitForChild("GameEvents"))
print("[Bootstrap] SharedState/GameEvents 初期化完了")

-- ============================================
-- 2. コアモジュールの読み込み
-- ============================================
local ZoneManager = require(ServerScriptService:WaitForChild("ZoneManager"))
local PlayerStats = require(ServerScriptService:WaitForChild("PlayerStats"))
print("[Bootstrap] ZoneManager/PlayerStats 読み込み完了")

-- ============================================
-- 3. 定数定義
-- ============================================
local START_ZONE_NAME = "ContinentTown"
local LOAD_TIMEOUT = 10 -- DataStoreロードのタイムアウト(秒)

-- ============================================
-- 4. プレイヤーごとのロードデータ管理
-- ============================================
local LastLoadedLocation = {}

-- ============================================
-- 5. 初期地形生成
-- ============================================
-- print("[Bootstrap] 街を生成中...")
-- ZoneManager.LoadZone(START_ZONE_NAME)
-- print("[Bootstrap] 地形生成完了（待機なし）")

print("[Bootstrap] 街を生成中（非同期）...")
task.spawn(function()
    ZoneManager.LoadZone(START_ZONE_NAME)
    print("[Bootstrap] 地形生成完了")
end)

-- ============================================
-- 6. 街の設定取得
-- ============================================
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

-- ============================================
-- 7. プレイヤースポーン処理
-- ============================================
local function setupPlayerSpawn(player)
    local characterAddedConnection = nil

    -- DataStoreからのロード処理（非同期）
    local function startDataStoreLoad()
        task.spawn(function()
            print(("[Bootstrap] %s のDataStoreロード開始"):format(player.Name))

            local loadedLocation = PlayerStats.initPlayer(player)

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

            LastLoadedLocation[player] = loadedLocation
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
        local loadedLocation = LastLoadedLocation[player]
        local waited = 0

        while not loadedLocation and waited < LOAD_TIMEOUT do
            task.wait(0.1)
            waited = waited + 0.1
            loadedLocation = LastLoadedLocation[player]
        end

        -- タイムアウト時のフォールバック
        if not loadedLocation then
            warn(("[Bootstrap] %s のロードタイムアウト、デフォルト座標使用"):format(player.Name))
            loadedLocation = {
                ZoneName = "ContinentTown",
                X = townConfig.centerX,
                Y = townConfig.baseY + 25,
                Z = townConfig.centerZ
            }
            LastLoadedLocation[player] = loadedLocation
        end

        -- テレポート処理が完了したらイベント接続を切断
        if characterAddedConnection then
            characterAddedConnection:Disconnect()
            characterAddedConnection = nil
        end

        task.spawn(function()
            -- 既にゾーンが設定済みならスキップ
            if ZoneManager.GetPlayerZone(player) then
                return
            end

            local spawnZone = loadedLocation.ZoneName
            task.wait(0.05) -- 物理エンジン安定化

            local hrp = character:WaitForChild("HumanoidRootPart", 5)
            if not hrp then return end

            -- Town以外のゾーンの場合、地形生成とアセットロードを非同期化
            if spawnZone ~= START_ZONE_NAME then
                task.spawn(function()
                    print(("[Bootstrap] 非同期: %s のロード開始"):format(spawnZone))

                    ZoneManager.LoadZone(spawnZone)

                    -- ポータル/モンスター生成
                    if _G.DestroyPortalsForZone and _G.CreatePortalsForZone then
                        _G.DestroyPortalsForZone(START_ZONE_NAME)
                        _G.CreatePortalsForZone(spawnZone)
                    end

                    if _G.SpawnMonstersForZone then
                        _G.SpawnMonstersForZone(spawnZone)
                    end

                    print(("[Bootstrap] 非同期: %s のロード完了"):format(spawnZone))
                end)
            end

            -- 最終座標の決定
            local spawnX = loadedLocation.X
            local spawnY = loadedLocation.Y
            local spawnZ = loadedLocation.Z

            -- Town内で、デフォルト座標の場合は中心に上書き
            local DEFAULT_X = -50
            local DEFAULT_Y = 50
            local DEFAULT_Z = 50
            local isDefaultLocation = (spawnX == DEFAULT_X and spawnY == DEFAULT_Y and spawnZ == DEFAULT_Z)

            if spawnZone == START_ZONE_NAME and isDefaultLocation then
                spawnY = townConfig.baseY + 50
                spawnX = townConfig.centerX
                spawnZ = townConfig.centerZ
                print(("[Bootstrap] Town中心座標に上書き: (%.0f, %.0f, %.0f)"):format(spawnX, spawnY, spawnZ))
            end

            print(("[Bootstrap] 最終テレポート座標: %s (%.0f, %.0f, %.0f)"):format(
                spawnZone, spawnX, spawnY, spawnZ
            ))

            -- テレポート実行
            hrp.CFrame = CFrame.new(spawnX, spawnY, spawnZ)

            -- ゾーン情報を設定
            ZoneManager.PlayerZones[player] = spawnZone

            -- Townの場合のみポータル生成
            if spawnZone == START_ZONE_NAME and _G.CreatePortalsForZone then
                _G.CreatePortalsForZone(START_ZONE_NAME)
            end
        end)
    end

    -- CharacterAddedイベント接続
    characterAddedConnection = player.CharacterAdded:Connect(function(character)
        performTeleportAndZoneSetup(player, character)
    end)

    -- ロード開始
    startDataStoreLoad()

    -- 既にスポーン済みの場合
    if player.Character then
        performTeleportAndZoneSetup(player, player.Character)
    end
end

-- ============================================
-- 8. プレイヤー管理イベント
-- ============================================
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

-- ============================================
-- 9. 効果音の初期化
-- ============================================
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

-- ============================================
-- 10. モジュール初期化（順序重要）
-- ============================================
print("[Bootstrap] モジュール初期化開始...")

-- PlayerStats初期化（最優先）
PlayerStats.init()
print("[Bootstrap] PlayerStats初期化完了")

-- BattleSystemは自動的にPlayerStatsを参照（循環依存なし）
print("[Bootstrap] BattleSystem準備完了")

-- MonsterSpawnerはイベント駆動で動作（循環依存なし）
print("[Bootstrap] MonsterSpawner準備完了")

print("[Bootstrap] === ゲーム初期化完了 ===")
print(("[Bootstrap] プレイヤーは街（%s）からスタートします"):format(START_ZONE_NAME))