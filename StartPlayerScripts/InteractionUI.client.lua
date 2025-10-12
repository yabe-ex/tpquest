-- StarterPlayer/StarterPlayerScripts/InteractionUI.client.lua
-- インタラクション検出とUIボタン表示

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

print("[InteractionUI] 初期化開始")

-- RemoteEvent取得
local InteractEvent = ReplicatedStorage:WaitForChild("InteractEvent", 10)
if not InteractEvent then
	warn("[InteractionUI] InteractEventが見つかりません")
	return
end

-- 現在のインタラクション対象
local currentTarget = nil
local currentButton = nil

-- インタラクション済みのオブジェクトを記録
local interactedObjects = {}

-- インタラクションボタンUI作成
local function createInteractionButton(targetObject, actionText, key)
	-- 既存のボタンを削除
	if currentButton then
		currentButton:Destroy()
		currentButton = nil
	end

	-- BillboardGuiを作成
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "InteractionPrompt"
	billboard.Adornee = targetObject
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = targetObject

	-- 背景フレーム
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 0.5
	frame.BorderSizePixel = 0
	frame.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	-- ボタン
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0.9, 0, 0.7, 0)
	button.Position = UDim2.new(0.05, 0, 0.15, 0)
	button.BackgroundColor3 = Color3.fromRGB(255, 200, 100)
	button.BackgroundTransparency = 0.3
	button.BorderSizePixel = 0
	button.Text = string.format("%s [%s]", actionText, key)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextSize = 18
	button.Font = Enum.Font.SourceSansBold
	button.Active = true
	button.AutoButtonColor = true
	button.Parent = frame

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 6)
	buttonCorner.Parent = button

	-- ボタンクリック
	button.MouseButton1Click:Connect(function()
		print("[InteractionUI DEBUG] ===== ボタンクリックイベント発火 =====")
		print(("[InteractionUI] ボタンクリック: %s"):format(targetObject.Name))

		-- インタラクション済みに記録
		interactedObjects[targetObject] = true

		-- サーバーに送信
		InteractEvent:FireServer(targetObject)

		-- 即座にボタンを削除
		if currentButton then
			currentButton:Destroy()
			currentButton = nil
		end
		currentTarget = nil
	end)

	-- 【追加】ボタンのホバー検出テスト
	button.MouseEnter:Connect(function()
		print("[InteractionUI DEBUG] マウスがボタンに入った")
	end)

	button.MouseLeave:Connect(function()
		print("[InteractionUI DEBUG] マウスがボタンから出た")
	end)

	print("[InteractionUI] 初期化完了")

	currentButton = billboard
	return billboard
end

-- インタラクション可能なオブジェクトを検出
local function findNearestInteractable()
	local character = player.Character
	if not character then return nil end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	local nearestObject = nil
	local nearestDistance = math.huge

	-- workspace内の全オブジェクトをチェック
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") and obj:GetAttribute("HasInteraction") then
			-- インタラクション済みならスキップ
			if interactedObjects[obj] then
				continue
			end

			local distance = (hrp.Position - obj.Position).Magnitude
			local range = obj:GetAttribute("InteractionRange") or 8

			if distance <= range and distance < nearestDistance then
				nearestObject = obj
				nearestDistance = distance
			end
		end
	end

	return nearestObject
end

-- メインループ
RunService.Heartbeat:Connect(function()
	local nearest = findNearestInteractable()

	-- 対象が変わった場合
	if nearest ~= currentTarget then
		-- 古いボタンを削除
		if currentButton then
			currentButton:Destroy()
			currentButton = nil
		end

		currentTarget = nearest

		-- 新しいボタンを作成
		if nearest then
			local action = nearest:GetAttribute("InteractionAction") or "調べる"
			local key = nearest:GetAttribute("InteractionKey") or "E"
			createInteractionButton(nearest, action, key)

			print(("[InteractionUI] インタラクション可能: %s"):format(action))
		end
	end
end)

-- キー入力
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if currentTarget and input.KeyCode == Enum.KeyCode.E then
		local action = currentTarget:GetAttribute("InteractionAction") or "調べる"
		print(("[InteractionUI] Eキー押下: %s"):format(action))

		-- インタラクション済みに記録
		interactedObjects[currentTarget] = true

		-- サーバーに送信
		InteractEvent:FireServer(currentTarget)

		-- 即座にボタンを削除
		if currentButton then
			currentButton:Destroy()
			currentButton = nil
		end
		currentTarget = nil
	end
end)

