-- StarterPlayer/StarterPlayerScripts/FastTravelUI.client.lua
-- ファストトラベルUIシステム

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

print("[FastTravelUI] 初期化開始")

-- RemoteEvent取得
local FastTravelEvent = ReplicatedStorage:WaitForChild("FastTravelEvent", 10)
local GetContinentsEvent = ReplicatedStorage:WaitForChild("GetContinentsEvent", 10)

if not FastTravelEvent or not GetContinentsEvent then
	warn("[FastTravelUI] RemoteEventが見つかりません")
	return
end

-- UIコンテナ
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FastTravelUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
-- screenGui.ZIndex = 100
screenGui.Parent = playerGui

-- ワープボタン（ミニマップの上）
local warpButton = Instance.new("TextButton")
warpButton.Name = "WarpButton"
warpButton.Size = UDim2.new(0, 200, 0, 35) -- ミニマップと同じ横幅200、高さ35
warpButton.Position = UDim2.new(0, 20, 1, -300) -- ミニマップの上に配置
warpButton.BackgroundColor3 = Color3.fromRGB(50, 120, 200)
warpButton.BackgroundTransparency = 0.2
warpButton.BorderSizePixel = 2
warpButton.BorderColor3 = Color3.fromRGB(255, 255, 255)
warpButton.Text = "ワープ"
warpButton.TextColor3 = Color3.new(1, 1, 1)
warpButton.TextSize = 18
warpButton.Font = Enum.Font.SourceSansBold
warpButton.Parent = screenGui

local warpButtonCorner = Instance.new("UICorner")
warpButtonCorner.CornerRadius = UDim.new(0, 6)
warpButtonCorner.Parent = warpButton

-- モーダル背景
local modalBackground = Instance.new("Frame")
modalBackground.Name = "ModalBackground"
modalBackground.Size = UDim2.fromScale(1, 1)
modalBackground.Position = UDim2.fromScale(0, 0)
modalBackground.BackgroundColor3 = Color3.new(0, 0, 0)
modalBackground.BackgroundTransparency = 1
modalBackground.Visible = false
modalBackground.ZIndex = 101
modalBackground.Parent = screenGui

-- モーダルウィンドウ
local modalWindow = Instance.new("Frame")
modalWindow.Name = "ModalWindow"
modalWindow.Size = UDim2.new(0, 400, 0, 500)
modalWindow.Position = UDim2.new(0.5, -200, 0.5, -250)
modalWindow.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
modalWindow.BackgroundTransparency = 0.1
modalWindow.BorderSizePixel = 3
modalWindow.BorderColor3 = Color3.fromRGB(100, 150, 255)
modalWindow.ZIndex = 102
modalWindow.Parent = modalBackground

local modalCorner = Instance.new("UICorner")
modalCorner.CornerRadius = UDim.new(0, 12)
modalCorner.Parent = modalWindow

-- タイトル
local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, 0, 0, 50)
titleLabel.Position = UDim2.new(0, 0, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "ワープ先を選択"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextSize = 24
titleLabel.Font = Enum.Font.GothamBold
titleLabel.ZIndex = 103
titleLabel.Parent = modalWindow

-- 閉じるボタン
local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Size = UDim2.new(0, 40, 0, 40)
closeButton.Position = UDim2.new(1, -50, 0, 5)
closeButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeButton.BackgroundTransparency = 0.3
closeButton.BorderSizePixel = 0
closeButton.Text = "✕"
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.TextSize = 24
closeButton.Font = Enum.Font.SourceSansBold
closeButton.ZIndex = 103
closeButton.Parent = modalWindow

local closeButtonCorner = Instance.new("UICorner")
closeButtonCorner.CornerRadius = UDim.new(0, 8)
closeButtonCorner.Parent = closeButton

-- スクロールフレーム（大陸一覧）
local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Name = "ContinentsList"
scrollFrame.Size = UDim2.new(1, -40, 1, -100)
scrollFrame.Position = UDim2.new(0, 20, 0, 70)
scrollFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
scrollFrame.BackgroundTransparency = 0.5
scrollFrame.BorderSizePixel = 0
scrollFrame.ScrollBarThickness = 8
scrollFrame.ZIndex = 102
scrollFrame.Parent = modalWindow

local scrollCorner = Instance.new("UICorner")
scrollCorner.CornerRadius = UDim.new(0, 8)
scrollCorner.Parent = scrollFrame

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 10)
listLayout.Parent = scrollFrame

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 10)
listPadding.PaddingBottom = UDim.new(0, 10)
listPadding.PaddingLeft = UDim.new(0, 10)
listPadding.PaddingRight = UDim.new(0, 10)
listPadding.Parent = scrollFrame

-- モーダルを開く
local function openModal()
	print("[FastTravelUI] モーダルを開く")

	-- 大陸一覧を取得
	local success, continents = pcall(function()
		return GetContinentsEvent:InvokeServer()
	end)

	if not success or not continents then
		warn("[FastTravelUI] 大陸一覧の取得に失敗しました")
		return
	end

	-- 既存のボタンをクリア
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	-- 大陸ボタンを作成
	for i, continent in ipairs(continents) do
		local button = Instance.new("TextButton")
		button.Name = continent.name
		button.Size = UDim2.new(1, -20, 0, 60)
		button.BackgroundColor3 = Color3.fromRGB(60, 100, 180)
		button.BackgroundTransparency = 0.2
		button.BorderSizePixel = 0
		button.Text = continent.displayName
		button.TextColor3 = Color3.new(1, 1, 1)
		button.TextSize = 20
		button.Font = Enum.Font.SourceSansBold
		button.LayoutOrder = i
		button.ZIndex = 103
		button.Parent = scrollFrame

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 8)
		buttonCorner.Parent = button

		-- ホバーエフェクト
		button.MouseEnter:Connect(function()
			TweenService:Create(button, TweenInfo.new(0.2), {
				BackgroundTransparency = 0
			}):Play()
		end)

		button.MouseLeave:Connect(function()
			TweenService:Create(button, TweenInfo.new(0.2), {
				BackgroundTransparency = 0.2
			}):Play()
		end)

		-- クリックイベント
		button.MouseButton1Click:Connect(function()
			print(("[FastTravelUI] %s へワープ要求"):format(continent.name))
			FastTravelEvent:FireServer(continent.name)
			closeModal()
		end)
	end

	-- スクロールフレームのサイズ調整
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 20)

	-- モーダル表示
	modalBackground.Visible = true
	modalBackground.BackgroundTransparency = 0.5

	-- フェードイン
	TweenService:Create(modalBackground, TweenInfo.new(0.3), {
		BackgroundTransparency = 0.3
	}):Play()
end

-- モーダルを閉じる
function closeModal()
	print("[FastTravelUI] モーダルを閉じる")

	TweenService:Create(modalBackground, TweenInfo.new(0.3), {
		BackgroundTransparency = 1
	}):Play()

	task.wait(0.3)
	modalBackground.Visible = false
end

-- イベント接続
warpButton.MouseButton1Click:Connect(openModal)
closeButton.MouseButton1Click:Connect(closeModal)

-- 背景クリックで閉じる
modalBackground.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- モーダルウィンドウ外をクリックした場合
		local mousePos = input.Position
		local windowPos = modalWindow.AbsolutePosition
		local windowSize = modalWindow.AbsoluteSize

		if mousePos.X < windowPos.X or mousePos.X > windowPos.X + windowSize.X or
		   mousePos.Y < windowPos.Y or mousePos.Y > windowPos.Y + windowSize.Y then
			closeModal()
		end
	end
end)

print("[FastTravelUI] 初期化完了")