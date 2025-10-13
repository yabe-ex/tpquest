-- ServerScriptService/Bootstrap.server.lua
-- ゲーム初期化スクリプト（最終安定版 - DataStoreロード安定化）

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

print("[Bootstrap] === ゲーム初期化開始 (最終安定版) ===")
-- ★ 効果音の初期化（早期）: 場所ズレ/種類ミスでも落ちないローダー
do
    local function findSoundRegistry()
        -- 1) ServerScriptService 直下
        local m = ServerScriptService:FindFirstChild("SoundRegistry")
        -- 2) Modules フォルダ配下
        if not m then
            local modules = ServerScriptService:FindFirstChild("Modules")
            if modules then
                m = modules:FindFirstChild("SoundRegistry")
            end
        end
        -- 3) ReplicatedStorage 側に置いた場合
        if not m then
            m = ReplicatedStorage:FindFirstChild("SoundRegistry")
        end
        return m
    end

    local m = findSoundRegistry()
    print("[Bootstrap] (early) SoundRegistry =", m and m:GetFullName() or "nil", m and m.ClassName)

    if m and m:IsA("ModuleScript") then
        local okReq, modOrErr = pcall(require, m)
        if okReq and type(modOrErr) == "table" and type(modOrErr.init) == "function" then
            local okInit, errInit = pcall(modOrErr.init)
            if okInit then
                print("[Bootstrap] Sounds初期化完了（SoundRegistry・早期）")
            else
                warn("[Bootstrap] SoundRegistry.init エラー（早期）: ", errInit)
            end
        else
            warn("[Bootstrap] SoundRegistry の戻り値が不正 or require 失敗（早期）: ", modOrErr)
        end
    else
        -- フォールバック: とりあえず Sounds フォルダと最低限の音を用意（クライアントの WaitForChild 対策）
        local folder = ReplicatedStorage:FindFirstChild("Sounds")
        if not folder then
            folder = Instance.new("Folder")
            folder.Name = "Sounds"
            folder.Parent = ReplicatedStorage
        end

        local function ensure(name, id, vol)
            local s = folder:FindFirstChild(name)
            if not s then
                s = Instance.new("Sound")
                s.Name = name
                s.SoundId = id
                s.Volume = vol
                s.Parent = folder
            end
        end
        ensure("TypingCorrect", "rbxassetid://159534615",        0.4)
        ensure("TypingError",   "rbxassetid://113721818600044",  0.5)
        ensure("EnemyHit",      "rbxassetid://155288625",        0.6)

        warn("[Bootstrap] SoundRegistry が見つからない/ModuleScriptでないため、暫定で Sounds を用意（早期）")
    end
end


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
local function setupPlayerSpawn(player)

    -- DataStoreからのロード処理（同期的に待つ）
    local function loadDataAndPrepareSpawn()
        local startTime = os.clock()
        print(("[Bootstrap] %s のDataStoreロード開始"):format(player.Name))

        local loadedLocation = PlayerStatsModule.initPlayer(player)
        local fullLoadedData = PlayerStatsModule.getLastLoadedData(player)

        print(("[Bootstrap] ⏱️ DataStoreロード完了: %.2f秒"):format(os.clock() - startTime))

        if not loadedLocation then
            warn(("[Bootstrap] %s のロードデータがnil、デフォルト使用"):format(player.Name))
            loadedLocation = {
                ZoneName = "ContinentTown",
                X = townConfig.centerX,
                Y = townConfig.baseY + 25,
                Z = townConfig.centerZ
            }
        end

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

        player:SetAttribute("ContinentName", loadedLocation.ZoneName)
        return LastLoadedData[player]
    end

    -- メイン処理
    task.spawn(function()
        local totalStartTime = os.clock()

        -- DataStoreロードを待つ
        local loadedData = loadDataAndPrepareSpawn()
        local loadedLocation = loadedData.Location
        local targetZone = loadedLocation.ZoneName

        -- 【重要】キャラクター生成前にゾーンをロード
        if targetZone ~= START_ZONE_NAME then
            local zoneLoadStart = os.clock()
            print(("[Bootstrap] キャラ生成前: %s のゾーンをロード"):format(targetZone))
            ZoneManager.LoadZone(targetZone)
            task.wait(2) -- 地形生成完了を待つ
            print(("[Bootstrap] ⏱️ ゾーンロード完了: %.2f秒"):format(os.clock() - zoneLoadStart))
        end

        -- キャラクター生成
        local charGenStart = os.clock()
        print(("[Bootstrap] %s のキャラクター生成を開始"):format(player.Name))

        -- 【追加】SpawnReadyEventを取得/作成
        local SpawnReadyEvent = ReplicatedStorage:FindFirstChild("SpawnReady")
        if not SpawnReadyEvent then
            SpawnReadyEvent = Instance.new("RemoteEvent")
            SpawnReadyEvent.Name = "SpawnReady"
            SpawnReadyEvent.Parent = ReplicatedStorage
        end

        -- CharacterAddedを先に接続（生成と同時にワープするため）
        local connection
        connection = player.CharacterAdded:Connect(function(character)
            connection:Disconnect() -- 一度だけ実行

            print(("[Bootstrap] ⏱️ キャラクター生成完了: %.2f秒"):format(os.clock() - charGenStart))

            -- 即座にワープ（描画される前に）
            task.spawn(function()
                local hrpStart = os.clock()
                local hrp = character:WaitForChild("HumanoidRootPart", 5)
                print(("[Bootstrap] ⏱️ HRP取得完了: %.2f秒"):format(os.clock() - hrpStart))

                if not hrp then
                    warn(("[Bootstrap] %s のHRPが見つかりません"):format(player.Name))
                    return
                end

                local targetX = loadedLocation.X
                local targetY = loadedLocation.Y
                local targetZ = loadedLocation.Z

                print(("[Bootstrap] 即座にワープ: %s → (%.0f, %.0f, %.0f)"):format(player.Name, targetX, targetY, targetZ))

                -- 即座に配置
                hrp.CFrame = CFrame.new(targetX, targetY, targetZ)
                ZoneManager.PlayerZones[player] = targetZone

                print(("[Bootstrap] %s を配置完了"):format(player.Name))
                print(("[Bootstrap] ⏱️ 合計時間: %.2f秒"):format(os.clock() - totalStartTime))

                -- 【追加】ワープ完了後、即座にローディング解除通知
                SpawnReadyEvent:FireClient(player)
                print(("[Bootstrap] %s にスポーン準備完了を通知（即座）"):format(player.Name))

                -- 【修正】モンスターとポータルの復元を並行処理に変更
                task.spawn(function()
                    task.wait(1) -- 少し待ってから復元

                    if loadedData.FieldState and loadedData.CurrentZone then
                        local zoneName = loadedData.CurrentZone
                        print(("[Bootstrap] %s のフィールド状態を復元: %s"):format(player.Name, zoneName))

                        DataCollectors.restoreFieldState(zoneName, loadedData.FieldState)

                        if _G.CreatePortalsForZone then
                            _G.CreatePortalsForZone(zoneName)
                        end
                    else
                        print(("[Bootstrap] %s は初回プレイ"):format(player.Name))

                        if targetZone ~= START_ZONE_NAME then
                            if _G.SpawnMonstersForZone then
                                _G.SpawnMonstersForZone(targetZone)
                            end
                            if _G.CreatePortalsForZone then
                                _G.CreatePortalsForZone(targetZone)
                            end
                        else
                            if _G.CreatePortalsForZone then
                                _G.CreatePortalsForZone(START_ZONE_NAME)
                            end
                        end
                    end

                    -- クリーンアップ
                    LastLoadedData[player] = nil
                end)

                -- ステータス更新（並行処理）
                task.spawn(function()
                    local stats = PlayerStatsModule.getStats(player)
                    if stats then
                        local expToNext = stats.Level * 100
                        local StatusUpdateEvent = ReplicatedStorage:FindFirstChild("StatusUpdate")
                        if StatusUpdateEvent then
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
                end)

                print(("[Bootstrap] %s のスポーン処理完了"):format(player.Name))
            end)
        end)

        -- キャラクター生成
        player:LoadCharacter()
    end)
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

-- 効果音の初期化（場所ズレ/種類ミスにも強いローダー）
do
    local function findSoundRegistry()
        -- 1) まずは直下
        local m = ServerScriptService:FindFirstChild("SoundRegistry")
        -- 2) よくある Modules フォルダ配下
        if not m then
            local modules = ServerScriptService:FindFirstChild("Modules")
            if modules then
                m = modules:FindFirstChild("SoundRegistry")
            end
        end
        -- 3) もし ReplicatedStorage に置いた場合
        if not m then
            m = ReplicatedStorage:FindFirstChild("SoundRegistry")
        end
        return m
    end

    local m = findSoundRegistry()
    print("[Bootstrap] SoundRegistry child =", m, m and m.ClassName, m and m:GetFullName())

    if not m then
        warn("[Bootstrap] SoundRegistry が見つかりません。ServerScriptService 直下（または Modules 配下）に ModuleScript を作成してください。")
    elseif not m:IsA("ModuleScript") then
        warn(("[Bootstrap] SoundRegistry は %s です。ModuleScript に作り直してください。"):format(m.ClassName))
    else
        local ok, SoundRegistryOrErr = pcall(require, m)
        if not ok then
            warn("[Bootstrap] require に失敗: ", SoundRegistryOrErr)
        else
            local SoundRegistry = SoundRegistryOrErr
            if type(SoundRegistry) == "table" and type(SoundRegistry.init) == "function" then
                local okInit, errInit = pcall(SoundRegistry.init)
                if okInit then
                    print("[Bootstrap] Sounds初期化完了（SoundRegistry）")
                else
                    warn("[Bootstrap] SoundRegistry.init でエラー: ", errInit)
                end
            else
                warn("[Bootstrap] SoundRegistry はテーブル+init関数ではありません。ModuleScriptの戻り値を確認してください。")
            end
        end
    end
end


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