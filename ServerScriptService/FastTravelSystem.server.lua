-- ServerScriptService/FastTravelSystem.server.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

print("[FastTravel] 初期化開始")

-- 依存モジュール
local ContinentsRegistry = require(ReplicatedStorage:WaitForChild("Continents"):WaitForChild("Registry"))
local IslandsRegistry = require(ReplicatedStorage:WaitForChild("Islands"):WaitForChild("Registry"))
local ZoneManager = require(ServerScriptService:WaitForChild("ZoneManager"))

-- 【追加】IslandsRegistryを辞書形式に変換
local Islands = {}
for _, island in ipairs(IslandsRegistry) do
	if island and island.name then
		Islands[island.name] = island
	end
end

-- RemoteEvent作成
local FastTravelEvent = ReplicatedStorage:FindFirstChild("FastTravelEvent")
if not FastTravelEvent then
	FastTravelEvent = Instance.new("RemoteEvent")
	FastTravelEvent.Name = "FastTravelEvent"
	FastTravelEvent.Parent = ReplicatedStorage
end

local GetContinentsEvent = ReplicatedStorage:FindFirstChild("GetContinentsEvent")
if not GetContinentsEvent then
	GetContinentsEvent = Instance.new("RemoteFunction")
	GetContinentsEvent.Name = "GetContinentsEvent"
	GetContinentsEvent.Parent = ReplicatedStorage
end

-- 大陸一覧を取得
local function getContinentsList()
	local continents = {}

	for _, continent in ipairs(ContinentsRegistry) do
		table.insert(continents, {
			name = continent.name,
			displayName = continent.displayName or continent.name
		})
	end

	return continents
end

-- ワープ処理
local function handleFastTravel(player, continentName)
	print(("[FastTravel] %s が %s へのワープを要求"):format(player.Name, continentName))

	-- 大陸情報を取得
	local continent = nil
	for _, cont in ipairs(ContinentsRegistry) do
		if cont.name == continentName then
			continent = cont
			break
		end
	end

	if not continent then
		warn(("[FastTravel] 大陸 '%s' が見つかりません"):format(continentName))
		return false
	end

	-- 最初の島を取得
	local firstIslandName = continent.islands[1]
	if not firstIslandName then
		warn(("[FastTravel] 大陸 '%s' に島がありません"):format(continentName))
		return false
	end

	-- 辞書から島を取得
	local island = Islands[firstIslandName]
	if not island then
		warn(("[FastTravel] 島 '%s' が見つかりません"):format(firstIslandName))
		return false
	end

	-- ワープ実行
	local success = ZoneManager.WarpPlayerToZone(
		player,
		continentName,
		island.centerX,
		island.baseY + 25,
		island.centerZ,
		true
	)

	if success then
		print(("[FastTravel] %s を %s にワープしました"):format(player.Name, continentName))

		-- 【追加】モンスターとポータルを生成
		task.spawn(function()
			task.wait(1) -- ゾーンロード完了を待つ

			-- モンスター生成
			if _G.SpawnMonstersForZone then
				_G.SpawnMonstersForZone(continentName)
				print(("[FastTravel] %s のモンスターを生成しました"):format(continentName))
			else
				warn("[FastTravel] SpawnMonstersForZone が見つかりません")
			end

			-- ポータル生成
			if _G.CreatePortalsForZone then
				_G.CreatePortalsForZone(continentName)
				print(("[FastTravel] %s のポータルを生成しました"):format(continentName))
			else
				warn("[FastTravel] CreatePortalsForZone が見つかりません")
			end
		end)
	else
		warn(("[FastTravel] %s のワープに失敗しました"):format(player.Name))
	end

	return success
end

-- イベント接続
GetContinentsEvent.OnServerInvoke = function(player)
	return getContinentsList()
end

FastTravelEvent.OnServerEvent:Connect(function(player, continentName)
	handleFastTravel(player, continentName)
end)

print("[FastTravel] 初期化完了")