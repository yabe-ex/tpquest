-- ServerScriptService/WarpPortal.server.lua
-- ワープ中のバトル開始を防止する修正版

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ZoneManager = require(script.Parent.ZoneManager)
local BattleSystem = require(script.Parent.BattleSystem)

print("[WarpPortal] 初期化開始")

local warpEvent = ReplicatedStorage:FindFirstChild("WarpEvent")
if not warpEvent then
	warpEvent = Instance.new("RemoteEvent")
	warpEvent.Name = "WarpEvent"
	warpEvent.Parent = ReplicatedStorage
end

local warpingPlayers = {}
local activePortals = {}

local IslandsRegistry = require(ReplicatedStorage.Islands.Registry)
local ContinentsRegistry = require(ReplicatedStorage.Continents.Registry)

local Islands = {}
for _, island in ipairs(IslandsRegistry) do
	Islands[island.name] = island
end

local Continents = {}
for _, continent in ipairs(ContinentsRegistry) do
	Continents[continent.name] = continent
end

local function resolveTemplate(pathArray: {string}): Model?
	local node: Instance = game
	for _, seg in ipairs(pathArray) do
		node = node:FindFirstChild(seg)
		if not node then return nil end
	end
	return (node and node:IsA("Model")) and node or nil
end

local function ensureHRP(model: Model): BasePart?
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		if not model.PrimaryPart then model.PrimaryPart = hrp end
		return hrp
	end
	return nil
end

local function attachLabel(model: Model, maxDist: number)
	local hrp = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local _, bboxSize = model:GetBoundingBox()
	local labelOffset = math.min(bboxSize.Y * 0.5 + 2, 15)

	local gui = Instance.new("BillboardGui")
	gui.Name = "DebugInfo"
	gui.Adornee = hrp
	gui.AlwaysOnTop = true
	gui.Size = UDim2.new(0, 150, 0, 50)
	gui.StudsOffset = Vector3.new(0, labelOffset, 0)
	gui.MaxDistance = maxDist
	gui.Parent = hrp

	local lb = Instance.new("TextLabel")
	lb.Name = "InfoText"
	lb.BackgroundTransparency = 1
	lb.TextScaled = true
	lb.Font = Enum.Font.GothamBold
	lb.TextColor3 = Color3.new(1, 1, 1)
	lb.TextStrokeTransparency = 0.5
	lb.Size = UDim2.fromScale(1, 1)
	lb.Text = "Ready"
	lb.Parent = gui
end

local function placeOnGround(model: Model, x: number, z: number)
	local hrp = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		warn("[MonsterSpawner] HumanoidRootPart が見つかりません: " .. model.Name)
		return
	end

	local groundY = FieldGen.raycastGroundY(x, z, 100)
		or FieldGen.raycastGroundY(x, z, 200)
		or FieldGen.raycastGroundY(x, z, 50)
		or 10

	local _, yaw = hrp.CFrame:ToOrientation()
	model:PivotTo(CFrame.new(x, groundY + 20, z) * CFrame.Angles(0, yaw, 0))

	local bboxCFrame, bboxSize = model:GetBoundingBox()
	local bottomY = bboxCFrame.Position.Y - (bboxSize.Y * 0.5)
	local offset = hrp.Position.Y - bottomY

	model:PivotTo(CFrame.new(x, groundY + offset, z) * CFrame.Angles(0, yaw, 0))
end

local function nearestPlayer(position: Vector3)
	local best, bestDist = nil, math.huge
	for _, pl in ipairs(Players:GetPlayers()) do
		local ch = pl.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (position - hrp.Position).Magnitude
			if d < bestDist then
				best, bestDist = pl, d
			end
		end
	end
	return best, bestDist
end

-- 【修正】ポータルタッチ時、即座にワープ中フラグを設定
local function createPortal(config, fromZone)
	local zoneConfig = Islands[fromZone]
	if not zoneConfig then
		warn(("[WarpPortal] ゾーン '%s' の設定が見つかりません"):format(fromZone))
		return nil
	end

	local portalX = zoneConfig.centerX + (config.offsetX or 0)
	local portalZ = zoneConfig.centerZ + (config.offsetZ or 0)

	local FieldGen = require(ReplicatedStorage:WaitForChild("FieldGen"))
	local groundY = nil
	local maxRetries = 2

	for attempt = 1, maxRetries do
		groundY = FieldGen.raycastGroundY(portalX, portalZ, zoneConfig.baseY + 100)
		if groundY then break end
		task.wait(0.05)
	end

	local portalY
	if groundY then
		portalY = groundY + 1
	else
		local estimatedHeight = zoneConfig.baseY + ((zoneConfig.hillAmplitude or 20) * 0.5)
		portalY = estimatedHeight
	end

	local portalPosition = Vector3.new(portalX, portalY, portalZ)

	local portal = Instance.new("Part")
	portal.Name = config.name
	portal.Size = config.size or Vector3.new(8, 12, 8)
	portal.Position = portalPosition
	portal.Anchored = true
	portal.CanCollide = false
	portal.Transparency = 0.3
	portal.Color = config.color or Color3.fromRGB(255, 255, 255)
	portal.Material = Enum.Material.Neon

	portal:SetAttribute("FromZone", fromZone)
	portal:SetAttribute("ToZone", config.toZone)

	local bodyAngularVelocity = Instance.new("BodyAngularVelocity")
	bodyAngularVelocity.AngularVelocity = Vector3.new(0, 2, 0)
	bodyAngularVelocity.MaxTorque = Vector3.new(0, math.huge, 0)
	bodyAngularVelocity.P = 1000
	bodyAngularVelocity.Parent = portal

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PortalLabel"
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 7, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = portal

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = config.label or ("→ " .. config.toZone)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.SourceSansBold
	label.TextStrokeTransparency = 0.5
	label.Parent = billboard

	local worldFolder = workspace:FindFirstChild("World")
	if not worldFolder then
		worldFolder = Instance.new("Folder")
		worldFolder.Name = "World"
		worldFolder.Parent = workspace
	end

	portal.Parent = worldFolder

	task.spawn(function()
		task.wait(0.05)

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = {workspace.Terrain}

		local rayOrigin = portal.Position
		local rayDirection = Vector3.new(0, -200, 0)
		local rayResult = workspace:Raycast(rayOrigin, rayDirection, params)

		if rayResult and portal.Parent then
			local adjustedY = rayResult.Position.Y + (portal.Size.Y / 2) + 0.5
			portal.Position = Vector3.new(portal.Position.X, adjustedY, portal.Position.Z)
		end
	end)

	-- 【重要】ポータルタッチ処理
	portal.Touched:Connect(function(hit)
		local character = hit.Parent
		if not character then return end

		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end

		-- 【修正1】ワープ中チェック
		if warpingPlayers[player.UserId] then
			return
		end

		-- 【修正2】バトル中チェック
		if BattleSystem and BattleSystem.isInBattle and BattleSystem.isInBattle(player) then
			return
		end

		local actualFromZone = portal:GetAttribute("FromZone")
		local currentZone = ZoneManager.GetPlayerZone(player)

		if currentZone ~= actualFromZone then
			if not currentZone then
				ZoneManager.PlayerZones[player] = actualFromZone
			else
				return
			end
		end

		print(("[WarpPortal] %s が %s に入りました"):format(player.Name, config.name))

		-- 【修正3】即座にワープ中フラグを設定（最優先）
		warpingPlayers[player.UserId] = true
		character:SetAttribute("IsWarping", true)

		-- 【修正4-改3】キャラクターを即座に透明化（上空移動なし）
		local originalTransparencies = {}
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				originalTransparencies[part] = part.Transparency
				part.Transparency = 1
			elseif part:IsA("Decal") or part:IsA("Texture") then
				originalTransparencies[part] = part.Transparency
				part.Transparency = 1
			end
		end

		-- 画面を暗転
		warpEvent:FireClient(player, "StartLoading", config.toZone)
		task.wait(0.5)

		-- バトルシステムリセット
		if BattleSystem and BattleSystem.resetAllBattles then
			BattleSystem.resetAllBattles()
		end

		destroyPortalsForZone(actualFromZone)

		-- 前のゾーンのモンスターを削除
		if actualFromZone ~= "StartTown" and _G.DespawnMonstersForZone then
			_G.DespawnMonstersForZone(actualFromZone)
		end

		-- ゾーン切り替え
		local success = ZoneManager.WarpPlayerToZone(player, config.toZone)

		if success then
			-- 透明度を元に戻す
			for part, transparency in pairs(originalTransparencies) do
				if part and part.Parent then
					part.Transparency = transparency
				end
			end

			-- 新しいゾーンのポータルを作成
			createPortalsForZone(config.toZone)

			-- 新しいゾーンのモンスターをスポーン
			if config.toZone ~= "StartTown" and _G.SpawnMonstersForZone then
				_G.SpawnMonstersForZone(config.toZone)
			end

			task.wait(0.5)
			warpEvent:FireClient(player, "EndLoading")
		else
			warn(("[WarpPortal] %s のワープに失敗"):format(player.Name))
			warpEvent:FireClient(player, "EndLoading")
		end

		-- 【修正5】ワープ中フラグを解除
		task.wait(1)  -- 追加の安全マージン
		warpingPlayers[player.UserId] = nil
		if character and character.Parent then
			character:SetAttribute("IsWarping", false)
		end
	end)

	return portal
end

function createPortalsForZone(zoneName)
	if activePortals[zoneName] then
		print(("[WarpPortal] %s のポータルは既に存在します"):format(zoneName))
		return
	end

	activePortals[zoneName] = {}

	if zoneName == "StartTown" then
		print(("[WarpPortal] %s のポータルを並列生成中..."):format(zoneName))

		local townPortalConfigs = {
			-- {name = "Town_to_ContinentA", toZone = "ContinentA", offsetX = 50, offsetZ = 0, size = Vector3.new(8, 12, 8), color = Color3.fromRGB(100, 255, 100), label = "→ Grassland"},
			-- {name = "Town_to_ContinentB", toZone = "ContinentB", offsetX = -50, offsetZ = 0, size = Vector3.new(8, 12, 8), color = Color3.fromRGB(150, 150, 255), label = "→ Wilderness"},
			-- {name = "Town_to_ContinentT", toZone = "ContinentT", offsetX = 0, offsetZ = 50, size = Vector3.new(8, 12, 8), color = Color3.fromRGB(255, 255, 100), label = "→ T-Continent"},
			{name = "Town_to_Hokkaido", toZone = "ContinentHokkaido", offsetX = 0, offsetZ = -50, size = Vector3.new(8, 12, 8), color = Color3.fromRGB(200, 200, 255), label = "→ Hokkaido"},
		}

		for _, config in ipairs(townPortalConfigs) do
			task.spawn(function()
				local portal = createPortal(config, zoneName)
				if portal then
					table.insert(activePortals[zoneName], portal)
					print(("[WarpPortal] ポータル作成: %s"):format(config.name))
				end
			end)
		end
		return
	end

	local continent = Continents[zoneName]
	if continent and continent.portals then
		print(("[WarpPortal] %s のポータルを並列生成中..."):format(zoneName))

		for _, portalConfig in ipairs(continent.portals) do
			task.spawn(function()
				local islandName = portalConfig.islandName
				if not Islands[islandName] then
					warn(("[WarpPortal] 島 '%s' が見つかりません"):format(islandName))
				else
					local portal = createPortal(portalConfig, islandName)
					if portal then
						portal:SetAttribute("FromZone", zoneName)
						table.insert(activePortals[zoneName], portal)
						print(("[WarpPortal] ポータル作成: %s (配置: %s)"):format(portalConfig.name, islandName))
					end
				end
			end)
		end
	else
		print(("[WarpPortal] %s のポータル設定が見つかりません"):format(zoneName))
	end
end

function destroyPortalsForZone(zoneName)
	if not activePortals[zoneName] then return end

	for _, portal in ipairs(activePortals[zoneName]) do
		if portal and portal.Parent then
			portal:Destroy()
		end
	end

	activePortals[zoneName] = nil
	print(("[WarpPortal] %s のポータルを削除しました"):format(zoneName))
end

task.spawn(function()
	local maxWait = 10
	local waited = 0

	while not _G.SpawnMonstersForZone and waited < maxWait do
		task.wait(0.5)
		waited = waited + 0.5
	end

	if _G.SpawnMonstersForZone then
		print("[WarpPortal] MonsterSpawner関数検出成功")
	else
		warn("[WarpPortal] MonsterSpawner関数が見つかりません")
	end
end)

task.wait(0.3)
createPortalsForZone("StartTown")

Players.PlayerRemoving:Connect(function(player)
	warpingPlayers[player.UserId] = nil
	ZoneManager.PlayerZones[player] = nil
end)

_G.CreatePortalsForZone = createPortalsForZone
_G.DestroyPortalsForZone = destroyPortalsForZone

print("[WarpPortal] 初期化完了")