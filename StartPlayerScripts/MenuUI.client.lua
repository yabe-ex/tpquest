-- StarterPlayer/StarterPlayerScripts/MenuUI.client.lua
-- メニューシステム（ステータス、アイテム、スキル等）

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

print("[MenuUI] 初期化中...")

-- 状態管理
local currentModal = nil
local isInBattle = false

-- RemoteEvent取得
local RequestStatusEvent = ReplicatedStorage:WaitForChild("RequestStatus", 1)
local SaveGameEvent = ReplicatedStorage:WaitForChild("SaveGame", 1)
local SaveSuccessEvent = ReplicatedStorage:WaitForChild("SaveSuccess", 1)
local RequestLoadRespawnEvent = ReplicatedStorage:WaitForChild("RequestLoadRespawn", 1)


-- UIコンテナ
local menuGui = nil
local menuFrame = nil

-- プレイヤーステータスキャッシュ
local cachedStats = {
	Level = 1,
	MaxHP = 100,
	CurrentHP = 100,
	Speed = 10,
	Attack = 10,
	Defense = 10,
	Gold = 0,
	MonstersDefeated = 0
}

-- ステータス更新を受信 (既存ロジック)
local StatusUpdateEvent = ReplicatedStorage:FindFirstChild("StatusUpdate")
if StatusUpdateEvent then
	StatusUpdateEvent.OnClientEvent:Connect(function(hp, maxHP, level, exp, expToNext, gold)
		cachedStats.CurrentHP = hp or cachedStats.CurrentHP
		cachedStats.MaxHP = maxHP or cachedStats.MaxHP
		cachedStats.Level = level or cachedStats.Level
		cachedStats.Gold = gold or cachedStats.Gold
	end)
end

-- 戦歴更新を受信 (既存ロジック)
task.spawn(function()
	print("[MenuUI] StatsDetailイベント接続を開始...")

	local StatsDetailEvent = ReplicatedStorage:WaitForChild("StatsDetail", 5)
	if not StatsDetailEvent then
		warn("[MenuUI] StatsDetailイベントが見つかりません！")
		return
	end

	print("[MenuUI] StatsDetailイベントを発見しました")

	StatsDetailEvent.OnClientEvent:Connect(function(stats)
		print("[MenuUI] ========================================")
		print("[MenuUI] 🎯 StatsDetail受信イベント発火！")
		if stats then
			for key, value in pairs(stats) do
				cachedStats[key] = value
			end
			print("[MenuUI] ✅ キャッシュ更新完了")
		else
			warn("[MenuUI] ❌ statsがnilです！")
		end
		print("[MenuUI] ========================================")
	end)

	print("[MenuUI] StatsDetailイベント接続完了")
end)

-- バトル状態を監視 (既存ロジック)
local BattleStartEvent = ReplicatedStorage:FindFirstChild("BattleStart")
local BattleEndEvent = ReplicatedStorage:FindFirstChild("BattleEnd")

if BattleStartEvent then
	BattleStartEvent.OnClientEvent:Connect(function()
		isInBattle = true
		if menuFrame then
			for _, button in ipairs(menuFrame:GetChildren()) do
				if button:IsA("TextButton") then
					button.Active = false
					button.BackgroundTransparency = 0.7
					button.TextTransparency = 0.5
				end
			end
		end
		if currentModal then
			closeModal()
		end
	end)
end

if BattleEndEvent then
	BattleEndEvent.OnClientEvent:Connect(function()
		isInBattle = false
		if menuFrame then
			for _, button in ipairs(menuFrame:GetChildren()) do
				if button:IsA("TextButton") then
					button.Active = true
					button.BackgroundTransparency = 0.2
					button.TextTransparency = 0
				end
			end
		end
	end)
end

-- モーダルウィンドウを閉じる (既存ロジック)
function closeModal()
    if not currentModal then return end -- 防御的な早期終了

    local modalToDestroy = currentModal
    currentModal = nil -- ★即座にnilに設定し、他の処理による競合を防止

	if modalToDestroy then
		local background = modalToDestroy:FindFirstChild("Background")
		if background then
			local tween = TweenService:Create(background, TweenInfo.new(0.2), {
				BackgroundTransparency = 1
			})
			tween:Play()
		end

		local panel = modalToDestroy:FindFirstChild("Panel")
		if panel then
			local tween = TweenService:Create(panel, TweenInfo.new(0.2), {
				BackgroundTransparency = 1
			})
			tween:Play()

			for _, child in ipairs(panel:GetDescendants()) do
				if child:IsA("TextLabel") or child:IsA("TextButton") then
					TweenService:Create(child, TweenInfo.new(0.2), {
						TextTransparency = 1
					}):Play()
				end
			end
		end

		task.wait(0.2)
		modalToDestroy:Destroy() -- ★ローカル参照を使用
	end
end

-- モーダルウィンドウを作成 (既存ロジック)
local function createModal(title, contentBuilder)
	if currentModal then
		closeModal()
	end

	local modal = Instance.new("ScreenGui")
	modal.Name = "ModalUI"
	modal.ResetOnSpawn = false
	modal.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	modal.Parent = playerGui

	-- 背景（暗転）
	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.new(0, 0, 0)
	background.BackgroundTransparency = 1
	background.BorderSizePixel = 0
	background.ZIndex = 50
	background.Parent = modal

	TweenService:Create(background, TweenInfo.new(0.2), {
		BackgroundTransparency = 0.5
	}):Play()

	-- パネル
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.new(0, 500, 0, 400)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.ZIndex = 51
	panel.Parent = modal

	TweenService:Create(panel, TweenInfo.new(0.2), {
		BackgroundTransparency = 0.1
	}):Play()

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	-- タイトル
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -20, 0, 40)
	titleLabel.Position = UDim2.new(0, 10, 0, 10)
	titleLabel.BackgroundTransparency = 1
	titleLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	titleLabel.TextStrokeTransparency = 0.5
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 24
	titleLabel.Text = title
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTransparency = 1
	titleLabel.ZIndex = 52
	titleLabel.Parent = panel

	TweenService:Create(titleLabel, TweenInfo.new(0.2), {
		TextTransparency = 0,
		TextStrokeTransparency = 0.5
	}):Play()

	-- 閉じるボタン
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.new(0, 40, 0, 40)
	closeButton.Position = UDim2.new(1, -50, 0, 10)
	closeButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeButton.BackgroundTransparency = 1
	closeButton.BorderSizePixel = 0
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 24
	closeButton.Text = "✕"
	closeButton.TextColor3 = Color3.new(1, 1, 1)
	closeButton.TextTransparency = 1
	closeButton.ZIndex = 52
	closeButton.Parent = panel

	TweenService:Create(closeButton, TweenInfo.new(0.2), {
		BackgroundTransparency = 0.2,
		TextTransparency = 0
	}):Play()

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeButton

	closeButton.MouseButton1Click:Connect(function()
		closeModal()
	end)

	closeButton.MouseEnter:Connect(function()
		closeButton.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
	end)
	closeButton.MouseLeave:Connect(function()
		closeButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	end)

	-- コンテンツエリア
	local contentFrame = Instance.new("Frame")
	contentFrame.Name = "Content"
	contentFrame.Size = UDim2.new(1, -20, 1, -70)
	contentFrame.Position = UDim2.new(0, 10, 0, 60)
	contentFrame.BackgroundTransparency = 1
	contentFrame.ZIndex = 52
	contentFrame.Parent = panel

	if contentBuilder then
		contentBuilder(contentFrame)
	end

	background.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			closeModal()
		end
	end)

	currentModal = modal
	return modal
end

local function showSaveModal()
    if not SaveGameEvent or not SaveSuccessEvent then
        createModal("セーブエラー", function(content)
            local label = Instance.new("TextLabel")
            label.Size = UDim2.fromScale(1, 1)
            label.BackgroundTransparency = 1
            label.TextColor3 = Color3.fromRGB(255, 100, 100)
            label.TextStrokeTransparency = 0.7
            label.Font = Enum.Font.Gotham
            label.TextSize = 18
            label.Text = "セーブ機能がサーバーで初期化されていません。"
            label.Parent = content
        end)
        return
    end

    -- セーブイベントをサーバーに送信
    SaveGameEvent:FireServer()

    local connection = nil -- ★FIX 1: connectionをローカル宣言

    createModal("セーブ中", function(content)
        local label = Instance.new("TextLabel")
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextStrokeTransparency = 0.7
        label.Font = Enum.Font.Gotham
        label.TextSize = 18
        label.Text = "💾 セーブ中..."
        label.Parent = content
        -- ... (label setup)

        -- セーブ完了のフィードバックを待機
        connection = SaveSuccessEvent.OnClientEvent:Connect(function(success)
            if connection and connection.Connected then connection:Disconnect() end -- ★FIX 2: Disconnect前にnil/Connectedチェック

            if success then
                label.Text = "✅ セーブ完了！"
                label.TextColor3 = Color3.fromRGB(46, 204, 113)
            else
                label.Text = "❌ セーブ失敗..."
                label.TextColor3 = Color3.fromRGB(231, 76, 60)
            end
            task.wait(1.5)
            closeModal()
        end)

        -- モーダルが強制終了された場合、接続を解除
        -- 閉じるボタン（✕）のイベント接続を再利用
        local closeButton = content.Parent:FindFirstChild("CloseButton")
        if closeButton then
            closeButton.MouseButton1Click:Connect(function()
                if connection and connection.Connected then connection:Disconnect() end -- ★FIX 3: 終了ボタンもnil/Connectedチェック
                closeModal()
            end)
        end

        -- 背景クリック（強制終了）のイベント接続を再利用
        local background = content.Parent.Parent:FindFirstChild("Background")
        if background then
             background.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    if connection and connection.Connected then connection:Disconnect() end
                    closeModal()
                end
            end)
        end
    end)
end

local function showLoadModal()

    createModal("ロード", function(content)
        local warningLabel = Instance.new("TextLabel")
        warningLabel.Size = UDim2.new(1, 0, 0, 60)
		warningLabel.Position = UDim2.new(0, 0, 0, 20)
		warningLabel.BackgroundTransparency = 1
		warningLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
		warningLabel.TextStrokeTransparency = 0.7
		warningLabel.Font = Enum.Font.Gotham
		warningLabel.TextSize = 18
		warningLabel.Text = "現在、ロードは再接続によって行われます。\nゲームを再起動しますか？"
		warningLabel.TextWrapped = true
		warningLabel.TextTransparency = 1
		warningLabel.ZIndex = 53
		warningLabel.Parent = content

        TweenService:Create(warningLabel, TweenInfo.new(0.2), {TextTransparency = 0, TextStrokeTransparency = 0.7}):Play()

        -- ロードボタン (サーバーにロード要求を送り、キックする)
        local loadButton = Instance.new("TextButton")
		loadButton.Size = UDim2.new(0, 150, 0, 50)
		loadButton.Position = UDim2.new(0.5, -160, 1, -70)
		loadButton.BackgroundColor3 = Color3.fromRGB(52, 152, 219)
		loadButton.BackgroundTransparency = 0.2
        loadButton.BorderSizePixel = 0
        loadButton.Font = Enum.Font.GothamBold
        loadButton.TextSize = 18
		loadButton.Text = "ゲームを再起動"
        loadButton.TextColor3 = Color3.new(1, 1, 1)
        loadButton.TextTransparency = 1
        loadButton.ZIndex = 53
        loadButton.Parent = content

        TweenService:Create(loadButton, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.1), {
			BackgroundTransparency = 0.2,
			TextTransparency = 0
		}):Play()

        local loadCorner = Instance.new("UICorner")
		loadCorner.CornerRadius = UDim.new(0, 8)
		loadCorner.Parent = loadButton

        -- ロード処理はキックを実行
        loadButton.MouseButton1Click:Connect(function()
            closeModal()

            -- ★修正ブロック開始: Studioと実環境で処理を分ける
            if game:GetService("RunService"):IsStudio() then
                if RequestLoadRespawnEvent then
                    -- Studioの場合、サーバーにリスポーンを要求
                    RequestLoadRespawnEvent:FireServer()
                    print("[MenuUI] Studioモード: サーバーにロードリスポーンを要求しました")
                else
                    warn("[MenuUI] RequestLoadRespawnEventが見つかりません！")
                end
            else
                -- 実際のゲームの場合、キックして再接続を促す
                player:Kick("セーブデータをロードするため再起動します")
            end
            -- ★修正ブロック終了
        end)

        -- キャンセルボタン (showLogoutから流用)
		local cancelButton = Instance.new("TextButton")
		cancelButton.Size = UDim2.new(0, 150, 0, 50)
		cancelButton.Position = UDim2.new(0.5, 10, 1, -70)
		cancelButton.BackgroundColor3 = Color3.fromRGB(149, 165, 166)
		cancelButton.BackgroundTransparency = 0.2
		cancelButton.BorderSizePixel = 0
		cancelButton.Font = Enum.Font.GothamBold
		cancelButton.TextSize = 18
		cancelButton.Text = "キャンセル"
		cancelButton.TextColor3 = Color3.new(1, 1, 1)
		cancelButton.TextTransparency = 1
		cancelButton.ZIndex = 53
		cancelButton.Parent = content

        TweenService:Create(cancelButton, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0,
        false, 0.15), {
			BackgroundTransparency = 0.2,
			TextTransparency = 0
		}):Play()

        local cancelCorner = Instance.new("UICorner")
		cancelCorner.CornerRadius = UDim.new(0, 8)
		cancelCorner.Parent = cancelButton

		cancelButton.MouseButton1Click:Connect(function()
			closeModal()
		end)

    end)
end

-- ★新規機能: 初期化処理
local function showResetModal()
    createModal("データ初期化", function(content)
        local warningLabel = Instance.new("TextLabel")
		warningLabel.Size = UDim2.new(1, 0, 0, 60)
		warningLabel.Position = UDim2.new(0, 0, 0, 20)
		warningLabel.BackgroundTransparency = 1
		warningLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		warningLabel.TextStrokeTransparency = 0.7
		warningLabel.Font = Enum.Font.Gotham
		warningLabel.TextSize = 18
		warningLabel.Text = "!! 警告 !!\nすべての進行状況を失います。本当に初期化しますか？"
		warningLabel.TextWrapped = true
		warningLabel.TextTransparency = 1
		warningLabel.ZIndex = 53
		warningLabel.Parent = content

		TweenService:Create(warningLabel, TweenInfo.new(0.2), {
			TextTransparency = 0,
			TextStrokeTransparency = 0.7
		}):Play()

		local resetButton = Instance.new("TextButton")
		resetButton.Size = UDim2.new(0, 150, 0, 50)
		resetButton.Position = UDim2.new(0.5, -160, 1, -70)
		resetButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
		resetButton.BackgroundTransparency = 0.2
        resetButton.BorderSizePixel = 0
        resetButton.Font = Enum.Font.GothamBold
        resetButton.TextSize = 18
		resetButton.Text = "初期化する"
		resetButton.TextColor3 = Color3.new(1, 1, 1)
		resetButton.TextTransparency = 1
		resetButton.ZIndex = 53
		resetButton.Parent = content

        local resetCorner = Instance.new("UICorner")
		resetCorner.CornerRadius = UDim.new(0, 8)
		resetCorner.Parent = resetButton

		TweenService:Create(resetButton, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.1), {
			BackgroundTransparency = 0.2,
			TextTransparency = 0
		}):Play()

		resetButton.MouseButton1Click:Connect(function()
			-- TODO: FireServer Reset Event
			player:Kick("データを初期化しました")
		end)

		local cancelButton = Instance.new("TextButton")
		cancelButton.Size = UDim2.new(0, 150, 0, 50)
		cancelButton.Position = UDim2.new(0.5, 10, 1, -70)
		cancelButton.BackgroundColor3 = Color3.fromRGB(149, 165, 166)
		cancelButton.BackgroundTransparency = 0.2
		cancelButton.BorderSizePixel = 0
		cancelButton.Font = Enum.Font.GothamBold
		cancelButton.TextSize = 18
		cancelButton.Text = "キャンセル"
		cancelButton.TextColor3 = Color3.new(1, 1, 1)
		cancelButton.TextTransparency = 1
		cancelButton.ZIndex = 53
		cancelButton.Parent = content

		TweenService:Create(cancelButton, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.15), {
			BackgroundTransparency = 0.2,
			TextTransparency = 0
		}):Play()

		local cancelCorner = Instance.new("UICorner")
		cancelCorner.CornerRadius = UDim.new(0, 8)
		cancelCorner.Parent = cancelButton

		cancelButton.MouseButton1Click:Connect(function()
			closeModal()
		end)
    end)
end


-- ステータス画面 (既存ロジック)
local function showStatus()
	createModal("ステータス", function(content)
		local stats = {
			{"レベル", cachedStats.Level},
			{"最大HP", cachedStats.MaxHP},
			{"攻撃力", cachedStats.Attack},
			{"防御力", cachedStats.Defense},
			{"素早さ", cachedStats.Speed},
		}

		for i, stat in ipairs(stats) do
			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, 0, 0, 40)
			label.Position = UDim2.new(0, 0, 0, (i - 1) * 50)
			label.BackgroundTransparency = 1
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.TextStrokeTransparency = 0.7
			label.Font = Enum.Font.Gotham
			label.TextSize = 20
			label.Text = string.format("%s: %d", stat[1], stat[2])
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextTransparency = 1
			label.ZIndex = 53
			label.Parent = content

			TweenService:Create(label, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, i * 0.05), {
				TextTransparency = 0,
				TextStrokeTransparency = 0.7
			}):Play()
		end
	end)
end

-- アイテム画面 (既存ロジック)
local function showItems()
	createModal("アイテム", function(content)
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Size = UDim2.fromScale(1, 1)
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		emptyLabel.TextStrokeTransparency = 0.7
		emptyLabel.Font = Enum.Font.Gotham
		emptyLabel.TextSize = 18
		emptyLabel.Text = "アイテムがありません"
		emptyLabel.TextTransparency = 1
		emptyLabel.ZIndex = 53
		emptyLabel.Parent = content

		TweenService:Create(emptyLabel, TweenInfo.new(0.2), {
			TextTransparency = 0,
			TextStrokeTransparency = 0.7
		}):Play()
	end)
end

-- スキル画面 (既存ロジック)
local function showSkills()
	createModal("スキル", function(content)
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Size = UDim2.fromScale(1, 1)
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		emptyLabel.TextStrokeTransparency = 0.7
		emptyLabel.Font = Enum.Font.Gotham
		emptyLabel.TextSize = 18
		emptyLabel.Text = "習得済みスキルなし"
		emptyLabel.TextTransparency = 1
		emptyLabel.ZIndex = 53
		emptyLabel.Parent = content

		TweenService:Create(emptyLabel, TweenInfo.new(0.2), {
			TextTransparency = 0,
			TextStrokeTransparency = 0.7
		}):Play()
	end)
end

-- 戦歴画面 (既存ロジック)
local function showRecords()
	createModal("戦歴", function(content)
		print("[MenuUI] ========================================")
		print("[MenuUI] 戦歴画面を開きました")
		print("[MenuUI] キャッシュされた値:", cachedStats.MonstersDefeated or 0)

		-- ラベルを先に作成
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, 40)
		label.Position = UDim2.new(0, 0, 0, 0)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextStrokeTransparency = 0.7
		label.Font = Enum.Font.Gotham
		label.TextSize = 20
		label.Text = string.format("倒したモンスター数: %d (取得中...)", cachedStats.MonstersDefeated or 0)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTransparency = 1
		label.ZIndex = 53
		label.Parent = content

		TweenService:Create(label, TweenInfo.new(0.2), {
			TextTransparency = 0,
			TextStrokeTransparency = 0.7
		}):Play()

		-- サーバーに最新の戦歴をリクエスト
		local RequestStatsDetailEvent = ReplicatedStorage:FindFirstChild("RequestStatsDetail")
		if RequestStatsDetailEvent then
			print("[MenuUI] サーバーに詳細ステータスをリクエスト中...")
			RequestStatsDetailEvent:FireServer()

			-- 0.5秒後にラベルを更新（サーバーからのレスポンスを待つ）
			task.delay(0.5, function()
				if label and label.Parent then
					label.Text = string.format("倒したモンスター数: %d", cachedStats.MonstersDefeated or 0)
					print("[MenuUI] ラベル更新: MonstersDefeated =", cachedStats.MonstersDefeated)
				end
			end)
		else
			warn("[MenuUI] RequestStatsDetailEventが見つかりません")
		end

		print("[MenuUI] ========================================")
	end)
end

-- 設定画面 (既存ロジック)
local function showSettings()
	createModal("設定", function(content)
		local bgmLabel = Instance.new("TextLabel")
		bgmLabel.Size = UDim2.new(1, 0, 0, 30)
		bgmLabel.Position = UDim2.new(0, 0, 0, 20)
		bgmLabel.BackgroundTransparency = 1
		bgmLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		bgmLabel.TextStrokeTransparency = 0.7
		bgmLabel.Font = Enum.Font.Gotham
		bgmLabel.TextSize = 18
		bgmLabel.Text = "BGM音量（未実装）"
		bgmLabel.TextXAlignment = Enum.TextXAlignment.Left
		bgmLabel.TextTransparency = 1
		bgmLabel.ZIndex = 53
		bgmLabel.Parent = content

		TweenService:Create(bgmLabel, TweenInfo.new(0.2), {
			TextTransparency = 0,
			TextStrokeTransparency = 0.7
		}):Play()

		local seLabel = Instance.new("TextLabel")
		seLabel.Size = UDim2.new(1, 0, 0, 30)
		seLabel.Position = UDim2.new(0, 0, 0, 80)
		seLabel.BackgroundTransparency = 1
		seLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		seLabel.TextStrokeTransparency = 0.7
		seLabel.Font = Enum.Font.Gotham
		seLabel.TextSize = 18
		seLabel.Text = "SE音量（未実装）"
		seLabel.TextXAlignment = Enum.TextXAlignment.Left
		seLabel.TextTransparency = 1
		seLabel.ZIndex = 53
		seLabel.Parent = content

		TweenService:Create(seLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.05), {
			TextTransparency = 0,
			TextStrokeTransparency = 0.7
		}):Play()
	end)
end

-- ログアウト確認 (showSystemに統合されるため、ここでは非公開の関数として残す)
local function showLogoutInner()
    createModal("ログアウト", function(content)
		local warningLabel = Instance.new("TextLabel")
		warningLabel.Size = UDim2.new(1, 0, 0, 60)
		warningLabel.Position = UDim2.new(0, 0, 0, 20)
		warningLabel.BackgroundTransparency = 1
		warningLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
		warningLabel.TextStrokeTransparency = 0.7
		warningLabel.Font = Enum.Font.Gotham
		warningLabel.TextSize = 18
		warningLabel.Text = "本当にログアウトしますか？\n\n※ 現在、進行状況は保存されません"
		warningLabel.TextWrapped = true
		warningLabel.TextTransparency = 1
		warningLabel.ZIndex = 53
		warningLabel.Parent = content

		TweenService:Create(warningLabel, TweenInfo.new(0.2), {
			TextTransparency = 0,
			TextStrokeTransparency = 0.7
		}):Play()

		local logoutButton = Instance.new("TextButton")
		logoutButton.Size = UDim2.new(0, 150, 0, 50)
		logoutButton.Position = UDim2.new(0.5, -160, 1, -70)
		logoutButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
		logoutButton.BackgroundTransparency = 0.2
		logoutButton.BorderSizePixel = 0
		logoutButton.Font = Enum.Font.GothamBold
		logoutButton.TextSize = 18
		logoutButton.Text = "ログアウト"
		logoutButton.TextColor3 = Color3.new(1, 1, 1)
		logoutButton.TextTransparency = 1
		logoutButton.ZIndex = 53
		logoutButton.Parent = content

		TweenService:Create(logoutButton, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.1), {
			BackgroundTransparency = 0.2,
			TextTransparency = 0
		}):Play()

		local logoutCorner = Instance.new("UICorner")
		logoutCorner.CornerRadius = UDim.new(0, 8)
		logoutCorner.Parent = logoutButton

		logoutButton.MouseButton1Click:Connect(function()
			player:Kick("ログアウトしました")
		end)

		local cancelButton = Instance.new("TextButton")
		cancelButton.Size = UDim2.new(0, 150, 0, 50)
		cancelButton.Position = UDim2.new(0.5, 10, 1, -70)
		cancelButton.BackgroundColor3 = Color3.fromRGB(149, 165, 166)
		cancelButton.BackgroundTransparency = 0.2
		cancelButton.BorderSizePixel = 0
		cancelButton.Font = Enum.Font.GothamBold
		cancelButton.TextSize = 18
		cancelButton.Text = "キャンセル"
		cancelButton.TextColor3 = Color3.new(1, 1, 1)
		cancelButton.TextTransparency = 1
		cancelButton.ZIndex = 53
		cancelButton.Parent = content

		TweenService:Create(cancelButton, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.15), {
			BackgroundTransparency = 0.2,
			TextTransparency = 0
		}):Play()

		local cancelCorner = Instance.new("UICorner")
		cancelCorner.CornerRadius = UDim.new(0, 8)
		cancelCorner.Parent = cancelButton

		cancelButton.MouseButton1Click:Connect(function()
			closeModal()
		end)
	end)
end


-- ★新規機能: システムメニュー (2x2グリッド)
local function showSystem()
	createModal("システム", function(content)
        -- コンテンツフレームを基準に、2x2グリッドを中央に配置
        local systemFrame = Instance.new("Frame")
        systemFrame.Size = UDim2.new(1, 0, 1, 0)
        systemFrame.BackgroundTransparency = 1
        systemFrame.Parent = content

        local systemButtons = {
            {name = "セーブ", func = showSaveModal, row = 0, col = 0, color = Color3.fromRGB(46, 204, 113)}, -- 緑
            {name = "ロード", func = showLoadModal, row = 0, col = 1, color = Color3.fromRGB(52, 152, 219)}, -- 青
            {name = "初期化", func = showResetModal, row = 1, col = 0, color = Color3.fromRGB(231, 76, 60)}, -- 赤
            {name = "ログアウト", func = showLogoutInner, row = 1, col = 1, color = Color3.fromRGB(149, 165, 166)}, -- 灰色
        }

        local buttonWidth = 160
        local buttonHeight = 65
        local spacing = 15

        local totalWidth = buttonWidth * 2 + spacing
        local totalHeight = buttonHeight * 2 + spacing

        for _, btnData in ipairs(systemButtons) do
            local button = Instance.new("TextButton")
            button.Name = btnData.name .. "Button"
            button.Size = UDim2.new(0, buttonWidth, 0, buttonHeight)

            -- グリッドの中心に配置するためのオフセット計算（手動調整が容易なようにAnchorPointを使用しない）
            local gridX = btnData.col * (buttonWidth + spacing)
            local gridY = btnData.row * (buttonHeight + spacing)

            -- AbsoluteSizeは実行時にしか確定しないため、AnchorPoint 0.5で相対位置を計算
            button.Position = UDim2.new(0.5, gridX - totalWidth / 2, 0.5, gridY - totalHeight / 2)

            button.BackgroundColor3 = btnData.color
            button.BackgroundTransparency = 0.2
            button.BorderSizePixel = 0
            button.Font = Enum.Font.GothamBold
            button.TextSize = 18
            button.Text = btnData.name
            button.TextColor3 = Color3.new(1, 1, 1)
            button.TextStrokeTransparency = 0.7
            button.ZIndex = 53
            button.Parent = systemFrame

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 8)
            corner.Parent = button

            button.MouseButton1Click:Connect(function()
                if not isInBattle then
                    -- Systemモーダルを閉じてから、次のモーダルまたはアクションを実行
                    -- showLogoutInnerは内部でcloseModalを呼ばないため、ここでcloseModalする
                    if btnData.name ~= "ログアウト" and btnData.name ~= "初期化" then
                        closeModal()
                    end
                    btnData.func()
                end
            end)

            button.MouseEnter:Connect(function()
                if not isInBattle then
                    button.BackgroundColor3 = btnData.color:Lerp(Color3.new(1,1,1), 0.3)
                end
            end)
            button.MouseLeave:Connect(function()
                button.BackgroundColor3 = btnData.color
            end)
        end
	end)
end


-- メニューUI作成
local function createMenuUI()
	menuGui = Instance.new("ScreenGui")
	menuGui.Name = "MenuUI"
	menuGui.ResetOnSpawn = false
	menuGui.Parent = playerGui

	menuFrame = Instance.new("Frame")
	menuFrame.Name = "MenuFrame"
	menuFrame.Size = UDim2.new(0, 250, 0, 120)
	menuFrame.Position = UDim2.new(1, -270, 1, -270)
	menuFrame.BackgroundTransparency = 1
	menuFrame.Parent = menuGui

	local menuButtons = {
		{name = "ステータス", func = showStatus, row = 0, col = 0},
		{name = "アイテム", func = showItems, row = 0, col = 1},
		{name = "スキル", func = showSkills, row = 0, col = 2},
		{name = "戦歴", func = showRecords, row = 1, col = 0},
		{name = "設定", func = showSettings, row = 1, col = 1},
		{name = "システム", func = showSystem, row = 1, col = 2}, -- ★修正: ログアウトをシステムに置き換え
	}

	local buttonWidth = 80
	local buttonHeight = 50
	local spacing = 5

	for _, btnData in ipairs(menuButtons) do
		local button = Instance.new("TextButton")
		button.Name = btnData.name .. "Button"
		button.Size = UDim2.new(0, buttonWidth, 0, buttonHeight)
		button.Position = UDim2.new(0, btnData.col * (buttonWidth + spacing), 0, btnData.row * (buttonHeight + spacing))
		button.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
		button.BackgroundTransparency = 0.2
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamBold
		button.TextSize = 14
		button.Text = btnData.name
		button.TextColor3 = Color3.new(1, 1, 1)
		button.TextStrokeTransparency = 0.7
		button.Parent = menuFrame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = button

		button.MouseButton1Click:Connect(function()
			if not isInBattle then
				btnData.func()
			end
		end)

		button.MouseEnter:Connect(function()
			if not isInBattle then
				button.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
			end
		end)
		button.MouseLeave:Connect(function()
			button.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
		end)
	end

	print("[MenuUI] メニューUI作成完了")
end

createMenuUI()

if RequestStatusEvent then
	task.wait(1)
	RequestStatusEvent:FireServer()
end

print("[MenuUI] 初期化完了")