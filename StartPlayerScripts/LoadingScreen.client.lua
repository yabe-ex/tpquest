-- StarterPlayer/StarterPlayerScripts/LoadingScreen.client.lua
-- 初回ロード時のローディング画面

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

print("[LoadingScreen] 初期化中...")

-- ローディング画面のUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "InitialLoadingUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 1000 -- 最前面に表示
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "LoadingFrame"
frame.Size = UDim2.new(1, 0, 1, 0)
frame.BackgroundColor3 = Color3.new(0, 0, 0)
frame.BackgroundTransparency = 0
frame.Visible = true
frame.Parent = screenGui

local label = Instance.new("TextLabel")
label.Size = UDim2.new(0.6, 0, 0.2, 0)
label.Position = UDim2.new(0.2, 0, 0.4, 0)
label.BackgroundTransparency = 1
label.Text = "Loading..."
label.TextColor3 = Color3.new(1, 1, 1)
label.TextScaled = true
label.Font = Enum.Font.SourceSansBold
label.Parent = frame

-- ヒントテキスト（オプション）
local hintLabel = Instance.new("TextLabel")
hintLabel.Size = UDim2.new(0.8, 0, 0.1, 0)
hintLabel.Position = UDim2.new(0.1, 0, 0.6, 0)
hintLabel.BackgroundTransparency = 1
hintLabel.Text = "タイピングを練習してモンスターを倒そう！"
hintLabel.TextColor3 = Color3.new(0.8, 0.8, 0.8)
hintLabel.TextSize = 18
hintLabel.Font = Enum.Font.Gotham
hintLabel.Parent = frame

-- サーバーからの準備完了信号を待つ
local spawnReadyEvent = ReplicatedStorage:WaitForChild("SpawnReady", 10)

if spawnReadyEvent then
    spawnReadyEvent.OnClientEvent:Connect(function()
        print("[LoadingScreen] スポーン準備完了、フェードアウト開始")

        -- フェードアウトアニメーション
        local fadeOut = TweenService:Create(frame, TweenInfo.new(1, Enum.EasingStyle.Quad), {
            BackgroundTransparency = 1
        })

        local labelFadeOut = TweenService:Create(label, TweenInfo.new(1, Enum.EasingStyle.Quad), {
            TextTransparency = 1
        })

        local hintFadeOut = TweenService:Create(hintLabel, TweenInfo.new(1, Enum.EasingStyle.Quad), {
            TextTransparency = 1
        })

        fadeOut:Play()
        labelFadeOut:Play()
        hintFadeOut:Play()

        fadeOut.Completed:Connect(function()
            screenGui:Destroy()
            print("[LoadingScreen] ローディング画面を削除")
        end)
    end)
else
    warn("[LoadingScreen] SpawnReadyイベントが見つかりません")
    -- フォールバック：3秒後に自動で消す
    task.wait(3)
    screenGui:Destroy()
end

print("[LoadingScreen] 初期化完了")