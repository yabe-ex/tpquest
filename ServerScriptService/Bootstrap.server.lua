-- ServerScriptService/Bootstrap.server.lua
-- ゲーム初期化スクリプト（最終安定版）

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

print("[Bootstrap] === ゲーム初期化開始 ===")

-- ZoneManagerを読み込み
local ZoneManager = require(script.Parent.ZoneManager)
local PlayerStats = require(ServerScriptService:WaitForChild("PlayerStats"))

PlayerStats.init()

print("[Bootstrap] 街を生成中...")
ZoneManager.LoadZone("StartTown") -- StartTown (Island) をロード

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

-- 【修正点 A：ポータル生成の呼び出しをグローバル関数に切り替え】
-- FindFirstChildのエラーを回避し、WarpPortal.server.luaで公開された関数を直接利用します。
if _G.createPortalsForZone then
    print("[Bootstrap] StartTownのポータルを生成中...")
    _G.createPortalsForZone("StartTown")
else
    warn("[Bootstrap] ⚠️ エラー回避: WarpPortal.server.luaがまだ初期化されていないか、グローバル関数をエクスポートしていません。ポータル生成をスキップします。")
end


-- プレイヤーのスポーン位置を街に設定
local function setupPlayerSpawn(player)
	player.CharacterAdded:Connect(function(character)
		-- 【重要】物理エンジン安定のため待機
		task.wait(0.5)

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

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

		-- CFrame設定は一度だけ
		hrp.CFrame = CFrame.new(spawnX, spawnY, spawnZ)

		ZoneManager.PlayerZones[player] = "StartTown"
	end)
end

-- 既存プレイヤーと新規プレイヤーに適用
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayerSpawn(player)

    -- 【修正点 B：二重落下防止】
    -- 既存プレイヤーへの即座のCFrame設定を完全に削除します。
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
print("[Bootstrap] プレイヤーは街（StartTown）からスタートします")