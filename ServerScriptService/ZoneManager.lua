-- ServerScriptService/ZoneManager.lua (IslandとContinentの両方に対応した安定版)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FieldGen = require(ReplicatedStorage:WaitForChild("FieldGen"))
local Players = game:GetService("Players")
local ZoneManager = {}

ZoneManager.ActiveZones = {}
ZoneManager.PlayerZones = {}

-- 島と大陸の設定を読み込み
local IslandsRegistry = require(ReplicatedStorage.Islands.Registry)
local ContinentsRegistry = require(ReplicatedStorage.Continents.Registry)

-- 島の設定をマップ化
local Islands = {}
for _, island in ipairs(IslandsRegistry) do
    Islands[island.name] = island
end

-- 大陸の設定をマップ化
local Continents = {}
for _, continent in ipairs(ContinentsRegistry) do
    if continent and continent.name then
        Continents[continent.name] = continent
    else
        warn("[ZoneManager] 名前が設定されていない大陸定義をスキップしました")
    end
end

print("[ZoneManager] 初期化完了。島数:", #IslandsRegistry, "大陸数:", #ContinentsRegistry)

-- ZoneChangeイベントを作成（クライアントへの通知用）
local ZoneChangeEvent = ReplicatedStorage:FindFirstChild("ZoneChange")
if not ZoneChangeEvent then
    ZoneChangeEvent = Instance.new("RemoteEvent")
    ZoneChangeEvent.Name = "ZoneChange"
    ZoneChangeEvent.Parent = ReplicatedStorage
    print("[ZoneManager] ZoneChangeイベントを作成しました")
end

-- ゾーンが大陸かチェック
local function isContinent(zoneName)
    return Continents[zoneName] ~= nil
end

-- ゾーンが島かチェック (Townが大陸化されたため、この関数は実質未使用に)
local function isIsland(zoneName)
    return Islands[zoneName] ~= nil and not isContinent(zoneName)
end

-- プレイヤーのゾーンを更新 (ワープポータルで使用)
local function updatePlayerZone(player, newZone)
    local oldZone = ZoneManager.PlayerZones[player]

    if oldZone == newZone then
        return
    end

    -- 古いゾーンから出た
    if oldZone then
        print(("[ZoneManager] %s が %s から出ました"):format(player.Name, oldZone))
        ZoneChangeEvent:FireClient(player, oldZone, false)
    end

    -- 新しいゾーンに入った
    if newZone then
        print(("[ZoneManager] %s が %s に入りました"):format(player.Name, newZone))
        ZoneManager.PlayerZones[player] = newZone
        ZoneChangeEvent:FireClient(player, newZone, true)
    else
        ZoneManager.PlayerZones[player] = nil
    end
end

-- 大陸をロード（複数の島と橋を生成）
local function loadContinent(continentName)
    local continent = Continents[continentName]
    if not continent then
        warn(("[ZoneManager] 大陸 '%s' が見つかりません"):format(continentName))
        return false
    end

    print(("[ZoneManager] 大陸生成開始: %s"):format(continentName))

    -- 含まれる全ての島を生成
    for _, islandName in ipairs(continent.islands) do
        local islandConfig = Islands[islandName]
        if islandConfig then
            print(("[ZoneManager]   - 島を生成: %s"):format(islandName))
            FieldGen.generateIsland(islandConfig)
        else
            warn(("[ZoneManager]   - 島が見つかりません: %s (Island/Registryを確認してください)"):format(islandName))
        end
    end

    -- 橋を生成
    if continent.bridges then
        for _, bridgeConfig in ipairs(continent.bridges) do
            local fromIsland = Islands[bridgeConfig.fromIsland]
            local toIsland = Islands[bridgeConfig.toIsland]

            if fromIsland and toIsland then
                print(("[ZoneManager]   - 橋を生成: %s"):format(bridgeConfig.name))
                FieldGen.generateBridge(fromIsland, toIsland, bridgeConfig)
            else
                warn(("[ZoneManager]   - 橋の生成失敗: %s"):format(bridgeConfig.name))
            end
        end
    end

    ZoneManager.ActiveZones[continentName] = {
        config = continent,
        loadedAt = os.time(),
    }

    print(("[ZoneManager] 大陸生成完了: %s"):format(continentName))
    return true
end

-- ゾーンをロード（島または大陸をロード）
function ZoneManager.LoadZone(zoneName)
    if ZoneManager.ActiveZones[zoneName] then
        print(("[ZoneManager] %s は既に生成済みです"):format(zoneName))
        return true
    end
print(("[ZoneManager] cska: %s"):format(zoneName))
    if isContinent(zoneName) then
        return loadContinent(zoneName)
    else
        -- ★修正: 単一の島をロードするロジックを削除。すべて大陸経由でロード。
        warn(("[ZoneManager] ゾーン '%s' は大陸ではありません。ロードをスキップしました。"):format(zoneName))
        return false
    end
end

-- ゾーンをアンロード（省略）
function ZoneManager.UnloadZone(zoneName)
    if not ZoneManager.ActiveZones[zoneName] then
        return
    end

    print(("[ZoneManager] ゾーン削除開始: %s"):format(zoneName))

    local terrain = workspace.Terrain
    local configsToUnload = {}

    -- ★修正: 大陸としてのみ処理
    if isContinent(zoneName) then
        -- 大陸の場合は含まれる全ての島を削除
        local continent = Continents[zoneName]
        for _, islandName in ipairs(continent.islands) do
            table.insert(configsToUnload, Islands[islandName])
        end
    else
         -- ★修正: 大陸でないゾーンはアンロードできない
         warn(("[ZoneManager] ゾーン '%s' は大陸ではありません。アンロードをスキップしました。"):format(zoneName))
         return
    end

    -- 各島の地形を削除
    for _, config in ipairs(configsToUnload) do
        if config then
            local halfSize = config.sizeXZ / 2 + 50
            local region = Region3.new(
                Vector3.new(config.centerX - halfSize, config.baseY - 50, config.centerZ - halfSize),
                Vector3.new(config.centerX + halfSize, config.baseY + 100, config.centerZ + halfSize)
            )
            region = region:ExpandToGrid(4)
            terrain:FillRegion(region, 4, Enum.Material.Air)

            -- マーカ削除は FieldGen.lua で行うためZoneManagerからは削除
        end
    end

    -- モンスター削除
    for _, model in ipairs(workspace:GetChildren()) do
        if model:IsA("Model") and model:GetAttribute("IsEnemy") then
            local spawnZone = model:GetAttribute("SpawnZone")
            if spawnZone == zoneName then
                model:Destroy()
            end
        end
    end

    ZoneManager.ActiveZones[zoneName] = nil
    print(("[ZoneManager] ゾーン削除完了: %s"):format(zoneName))
end


-- プレイヤーをワープ
function ZoneManager.WarpPlayerToZone(player, zoneName)
    print(("[ZoneManager] %s を %s にワープ中..."):format(player.Name, zoneName))

    -- ワープ先に地形がない場合はロード
    ZoneManager.LoadZone(zoneName)

    local character = player.Character
    if not character then
        warn(("[ZoneManager] %s のキャラクターが見つかりません"):format(player.Name))
        return false
    end

    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    -- ワープ先の座標を決定 (常に大陸の最初の島を参照するように統一)
    local targetX, targetZ, baseY, hillAmplitude

    if isContinent(zoneName) then
        -- 大陸の場合（Townも含む）
        local continent = Continents[zoneName]
        local firstIslandName = continent.islands[1]
        local firstIsland = Islands[firstIslandName]

        if not firstIsland then
             warn(("[ZoneManager] 大陸 '%s' の最初の島 '%s' が見つかりません。"):format(zoneName, firstIslandName))
             return false
        end

        targetX = firstIsland.centerX
        targetZ = firstIsland.centerZ
        baseY = firstIsland.baseY
        hillAmplitude = firstIsland.hillAmplitude or 20
    else
        -- ★修正: 島単独でのワープはエラーとする
        warn(("[ZoneManager] ゾーン '%s' は大陸ではありません。ワープできません。"):format(zoneName))
        return false
    end

    -- 十分に高い位置からレイキャスト
    local FieldGen = require(ReplicatedStorage:WaitForChild("FieldGen"))
    local rayStartY = baseY + hillAmplitude + 100
    local groundY = FieldGen.raycastGroundY(targetX, targetZ, rayStartY)

    local spawnY
    if groundY then
        spawnY = groundY + 5
        print(("[ZoneManager] 地面検出成功: Y=%.1f"):format(groundY))
    else
        -- 安全な高度：baseY + hillAmplitude * 0.6 + 10 に固定
        spawnY = baseY + (hillAmplitude * 0.6) + 10
        warn(("[ZoneManager] 地面検出失敗、予想高度使用: Y=%.1f"):format(spawnY))
    end

    hrp.CFrame = CFrame.new(targetX, spawnY, targetZ)

    updatePlayerZone(player, zoneName)

    print(("[ZoneManager] %s を %s にワープ完了 (%.1f, %.1f, %.1f)"):format(
        player.Name, zoneName, targetX, spawnY, targetZ
        ))
    return true
end

function ZoneManager.GetPlayerZone(player)
    return ZoneManager.PlayerZones[player]
end

-- プレイヤーが退出した時の処理 (省略)
Players.PlayerRemoving:Connect(function(player)
    local oldZone = ZoneManager.PlayerZones[player]
    if oldZone then
        print(("[ZoneManager] %s が退出しました。ゾーン: %s"):format(player.Name, oldZone))
        ZoneManager.PlayerZones[player] = nil
    end
end)

return ZoneManager