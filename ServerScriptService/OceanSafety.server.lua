-- ServerScriptService/OceanSafety.server.lua
-- 海に落ちた時の処理

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 設定
local WATER_LEVEL = -25  -- この高さより下に落ちたら処理
local CHECK_INTERVAL = 0.5  -- チェック間隔（秒）

-- 島の中心（プレイヤーのリスポーン位置）
local Islands = require(ReplicatedStorage.Islands.Registry)
local firstIsland = Islands[1]
local SPAWN_X = firstIsland.centerX
local SPAWN_Z = firstIsland.centerZ
local SPAWN_Y = firstIsland.baseY + 25  -- 島の上空

print("[OceanSafety] 初期化完了")

-- プレイヤーの監視
local function monitorPlayer(player)
	player.CharacterAdded:Connect(function(character)
		local hrp = character:WaitForChild("HumanoidRootPart")
		local humanoid = character:WaitForChild("Humanoid")

		local lastCheck = 0

		RunService.Heartbeat:Connect(function()
			if not character.Parent or not hrp.Parent then return end

			local now = os.clock()
			if now - lastCheck < CHECK_INTERVAL then return end
			lastCheck = now

			-- 水面より下に落ちたかチェック
			if hrp.Position.Y < WATER_LEVEL then
				print(("[OceanSafety] %s が海に落ちました。リスポーン中..."):format(player.Name))

				-- 速度をゼロに
				hrp.AssemblyLinearVelocity = Vector3.zero
				hrp.AssemblyAngularVelocity = Vector3.zero

				-- 島の中心に戻す
				hrp.CFrame = CFrame.new(SPAWN_X, SPAWN_Y, SPAWN_Z)

				-- 体力を少し減らす（ペナルティ）
				if humanoid.Health > 10 then
					humanoid.Health = humanoid.Health - 10
				end
			end
		end)
	end)
end

-- 既存プレイヤーと新規プレイヤーに適用
for _, player in ipairs(Players:GetPlayers()) do
	monitorPlayer(player)
end
Players.PlayerAdded:Connect(monitorPlayer)

-- モンスターの監視
RunService.Heartbeat:Connect(function()
	for _, model in ipairs(workspace:GetChildren()) do
		if model:IsA("Model") and model:GetAttribute("IsEnemy") then
			local hrp = model:FindFirstChild("HumanoidRootPart")

			if hrp and hrp.Position.Y < WATER_LEVEL then
				-- print(("[OceanSafety] %s が海に落ちました。消去中..."):format(model.Name))
				model:Destroy()
			end
		end
	end
end)