-- ServerScriptService/Bootstrap.server.lua
-- ゲーム初期化スクリプト（最終安定版 - BGM初期化無効化）

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

print("[Bootstrap] === ゲーム初期化開始 ===")

-- ZoneManagerを読み込み
local ZoneManager = require(script.Parent.ZoneManager)
local PlayerStats = require(ServerScriptService:WaitForChild("PlayerStats"))

-- ZoneChangeイベントの取得や操作は行わない（BGM再生を無効化）
local START_ZONE_NAME = "ContinentTown"

PlayerStats.init()

print("[Bootstrap] 街を生成中...")

ZoneManager.LoadZone(START_ZONE_NAME)

task.wait(5)
print("[Bootstrap] 地形生成の待機完了（5秒）")

-- 街の設定を取得 (Town大陸の最初の島であるStartTownを参照)
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

    -- キャラクター追加時の処理を定義 (スポーン処理の本体)
    local function onCharacterAdded(character)
        task.spawn(function()

            -- 【重要】物理エンジン安定のため待機
            task.wait(0.5)

            local hrp = character:FindFirstChild("HumanoidRootPart")
            if not hrp then
                -- 確実なHumanoidRootPartの取得（フォールバック）
                hrp = character:WaitForChild("HumanoidRootPart", 5)
                if not hrp then
                    return
                end
            end

            local currentZone = ZoneManager.GetPlayerZone(player)

            -- ゾーンが設定済み（＝一度移動した）の場合は、二重スポーンを防ぐためスキップ
            if currentZone then
                return
            end

            local spawnX = townConfig.centerX
            local spawnZ = townConfig.centerZ
            local spawnY = townConfig.baseY + 50

            print(("[Bootstrap] %s を街にスポーン: (%.0f, %.0f, %.0f)"):format(
                player.Name, spawnX, spawnY, spawnZ
                ))

            -- CFrame設定は一度だけ (1回目のスポーン処理のみ実行される)
            hrp.CFrame = CFrame.new(spawnX, spawnY, spawnZ)

            ZoneManager.PlayerZones[player] = START_ZONE_NAME

            -- BGM再生ロジックを完全に削除

        end)
    end

    -- イベント接続
    player.CharacterAdded:Connect(onCharacterAdded)

    -- BGM再生のための即時実行ロジックも削除
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