-- StarterPlayer/StarterPlayerScripts/BattleUI.client.lua
-- タイピングバトルUI制御（クライアント側）
local Logger = require(game.ReplicatedStorage.Util.Logger)
local log = Logger.get("BattleUI") -- ファイル名などをタグに

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local ContextActionService = game:GetService("ContextActionService")
local LocalizationService = game:GetService("LocalizationService")

local Sounds = ReplicatedStorage:WaitForChild("Sounds", 10)
local TypingCorrectSound = Sounds and Sounds:WaitForChild("TypingCorrect", 5)
local TypingErrorSound = Sounds and Sounds:WaitForChild("TypingError", 5)
local EnemyHitSound = Sounds and Sounds:WaitForChild("EnemyHit", 5)
if not EnemyHitSound then
	warn("[BattleUI] EnemyHit 効果音が見つかりません (WaitForChild タイムアウト)")
end

-- RemoteEventsを待機
local BattleStartEvent = ReplicatedStorage:WaitForChild("BattleStart", 30)
local BattleEndEvent = ReplicatedStorage:WaitForChild("BattleEnd", 30)
local BattleDamageEvent = ReplicatedStorage:WaitForChild("BattleDamage", 30)
local EnemyAttackCycleStartEvent = ReplicatedStorage:WaitForChild("EnemyAttackCycleStart", 30)

local pendingEnemyCycle = nil

-- 効果音の取りこぼしを戦闘開始時に再解決する保険
if not resolveSoundsIfNeeded then
	function resolveSoundsIfNeeded()
		local s = ReplicatedStorage:FindFirstChild("Sounds")
		if not s then return end
		if not TypingCorrectSound or not TypingCorrectSound.Parent then
			TypingCorrectSound = s:FindFirstChild("TypingCorrect")
		end
		if not TypingErrorSound or not TypingErrorSound.Parent then
			TypingErrorSound = s:FindFirstChild("TypingError")
		end
		if not EnemyHitSound or not EnemyHitSound.Parent then
			EnemyHitSound = s:FindFirstChild("EnemyHit")
		end
	end
end


local countdownFrame: Frame? = nil
local countdownLabel: TextLabel? = nil

local function runCountdown(seconds: number)
	if not countdownFrame or not countdownLabel then return end
	countdownFrame.Visible = true
	for n = seconds, 1, -1 do
		countdownLabel.Text = tostring(n)
		-- 簡単な演出
		countdownLabel.TextTransparency = 0
		game:GetService("TweenService")
			:Create(countdownLabel, TweenInfo.new(0.25), { TextTransparency = 0 })
			:Play()
		task.wait(1)
	end
	countdownFrame.Visible = false
end


local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local enemyProgContainer = nil
local enemyProgFill = nil
local enemyProgConn = nil

local pendingCyclePayload = nil       -- { intervalSec=..., startedAt=... }
local progressStartedOnce = false     -- 一度でも startEnemyProgress を呼んだか


-- === 攻撃プログレスの起動挙動 ===
local PROGRESS_COUNTDOWN_ON_START = false   -- trueで3,2,1のカウントダウン後に開始
local COUNTDOWN_SECONDS = 3
local DEFAULT_FIRST_INTERVAL = 4            -- サーバーが来るまでの仮インターバル(秒)

-- === 共通レイアウト定数（横幅を揃える） ===
local STACK_WIDTH = 700      -- 3つの横幅を統一（WordFrame の幅と同じ）
local WORD_H      = 150
local HP_BAR_H    = 40
local PROG_H      = 14
local STACK_PAD   = 10       -- 縦の隙間

local enemyProgConn = nil

local function stopEnemyProgress()
	if enemyProgConn then
		enemyProgConn:Disconnect()
		enemyProgConn = nil
	end
	if enemyProgFill then
		enemyProgFill.Size = UDim2.new(0, 0, 1, 0)
	end
	if enemyProgContainer then
		enemyProgContainer.Visible = false
	end
	print("[BattleUI] stopEnemyProgress: disconnected & hidden")
end

local function startEnemyProgress(durationSec: number, startedAtServer: number?)
	-- ここで必ずログ（早期returnの前に）
	print(("[BattleUI] startEnemyProgress ENTER (dur=%.2f, startedAtServer=%s)"):
		format(tonumber(durationSec) or -1, tostring(startedAtServer)))

	if not enemyProgContainer or not enemyProgFill then
		warn("[BattleUI] progress UI not ready; skip startEnemyProgress")
		return
	end

	enemyProgContainer.Visible = true
	enemyProgFill.Size = UDim2.new(0, 0, 1, 0)

	if enemyProgConn then
		enemyProgConn:Disconnect()
		enemyProgConn = nil
	end

	local startedAt = tonumber(startedAtServer) or tick()
	log.debugf("[BattleUI] startEnemyProgress invoked dur=%.2f startedAt=%.3f now=%.3f",
		durationSec, startedAt, tick())
	print(("[BattleUI] startEnemyProgress invoked dur=%.2f startedAt=%.3f now=%.3f"):
		format(durationSec, startedAt, tick()))
	enemyProgConn = game:GetService("RunService").RenderStepped:Connect(function()
		local estT = math.clamp((tick() - startedAt) / durationSec, 0, 1)
		enemyProgFill.Size = UDim2.new(estT, 0, 1, 0)
		-- デバッグ
		-- print(("[BattleUI] estT=%.3f (elapsed=%.3f)"):format(estT, tick()-startedAt))
		if estT >= 1 then
			enemyProgConn:Disconnect()
			enemyProgConn = nil
			print("[BattleUI] startEnemyProgress: completed and disconnected")
		end
	end)
end

local function applyEnemyCycle(payload)
	if not payload then return end
	local duration = tonumber(payload.intervalSec) or DEFAULT_FIRST_INTERVAL
	local startedAt = tonumber(payload.startedAt)

	print(("[BattleUI] sync interval=%.2f startedAt=%.3f"):format(duration, startedAt or -1))
	startEnemyProgress(duration, startedAt)
end



-- 入力制御（カウントダウン中はタイピング無効）
local TypingEnabled = true

print("[BattleUI] クライアント起動中...")

-- ユーザーのロケールを取得
local userLocale = string.lower(LocalizationService.RobloxLocaleId)
local localeCode = string.match(userLocale, "^(%a+)") or "en"  -- "ja-jp" → "ja"

-- 【開発用】強制的に日本語表示（本番では削除可能）
local FORCE_LOCALE = "ja"  -- ここを変更すると表示言語が変わる（nil で自動検出）
if FORCE_LOCALE then
	localeCode = FORCE_LOCALE
	print(("[BattleUI] 言語を強制設定: %s"):format(localeCode))
end

print(("[BattleUI] ユーザーロケール: %s → 表示言語: %s"):format(userLocale, localeCode))


local RunService = game:GetService("RunService")

-- サイクルの再同期要求イベント
local RequestEnemyCycleSyncEvent = ReplicatedStorage:WaitForChild("RequestEnemyCycleSync", 10)

-- 最後にサイクル同期を受信した時刻（sec）
local lastCycleAt = 0

-- サーバーに再同期を要求
local function requestEnemyCycleSync(reason: string?)
	if not inBattle then return end
	if not RequestEnemyCycleSyncEvent then return end
	-- デバッグ（必要なら）
	-- print(("[BattleUI] request sync (%s)"):format(reason or ""))
	RequestEnemyCycleSyncEvent:FireServer()
end

if not BattleStartEvent or not BattleEndEvent or not BattleDamageEvent then
    warn("[BattleUI] RemoteEventの取得に失敗しました")
    return
end

if not BattleStartEvent or not BattleEndEvent or not BattleDamageEvent then
	warn("[BattleUI] RemoteEventの取得に失敗しました")
	return
end

-- 単語リストを読み込み
local TypingWords = require(ReplicatedStorage:WaitForChild("TypingWords"))

-- デバッグ：単語リストの内容を確認
print("[BattleUI DEBUG] TypingWords.level_1[1]:")
if TypingWords.level_1 and TypingWords.level_1[1] then
	local firstWord = TypingWords.level_1[1]
	print("  Type:", type(firstWord))
	if type(firstWord) == "table" then
		print("  word:", firstWord.word)
		print("  ja:", firstWord.ja)
	else
		print("  Value:", firstWord)
	end
end

print("[BattleUI] RemoteEvents取得完了")

-- 状態
local inBattle = false
local currentWord = ""
local currentWordData = nil  -- 翻訳データを含む単語情報
local lastWord = nil  -- 前回の単語（連続回避用）
local currentIndex = 1
local typingLevels = {}
local currentBattleTimeout = nil
local monsterHP = 0
local monsterMaxHP = 0
local playerHP = 0  -- プレイヤーの現在HP
local playerMaxHP = 0  -- プレイヤーの最大HP
local damagePerKey = 1

-- カメラ設定保存用
local originalCameraMaxZoom = nil
local originalCameraMinZoom = nil

-- UI要素
local battleGui = nil
local darkenFrame = nil
local wordFrame = nil
local wordLabel = nil
local translationLabel = nil  -- 翻訳表示用
local hpBarBackground = nil
local hpBarFill = nil
local hpLabel = nil

-- システムキーをブロックする関数
local function blockSystemKeys()
	-- カメラズームを完全に固定
	originalCameraMaxZoom = player.CameraMaxZoomDistance
	originalCameraMinZoom = player.CameraMinZoomDistance

	-- 現在のズーム距離を取得して固定
	local camera = workspace.CurrentCamera
	local currentZoom = (camera.CFrame.Position - player.Character.HumanoidRootPart.Position).Magnitude
	player.CameraMaxZoomDistance = currentZoom
	player.CameraMinZoomDistance = currentZoom

	print(("[BattleUI] カメラを固定しました (距離: %.1f)"):format(currentZoom))
end

-- ブロック解除
local function unblockSystemKeys()
	-- カメラズームを復元
	if originalCameraMaxZoom and originalCameraMinZoom then
		player.CameraMaxZoomDistance = originalCameraMaxZoom
		player.CameraMinZoomDistance = originalCameraMinZoom
		print("[BattleUI] カメラ設定を復元しました")
	end
end

-- 【forward declaration】
local onBattleEnd
local updateDisplay
local setNextWord
local startEnemyProgress
local stopEnemyProgress
local playHitFlash

-- HPバーの色を取得（HP割合に応じて変化）
local function getHPColor(hpPercent)
	if hpPercent > 0.6 then
		-- 緑
		return Color3.fromRGB(46, 204, 113)
	elseif hpPercent > 0.3 then
		-- 黄色
		return Color3.fromRGB(241, 196, 15)
	else
		-- 赤
		return Color3.fromRGB(231, 76, 60)
	end
end

-- 表示を更新
updateDisplay = function()
	if not wordLabel then return end

	-- 入力済み文字を緑、未入力を白で表示
	local typedPart = string.sub(currentWord, 1, currentIndex - 1)
	local remainingPart = string.sub(currentWord, currentIndex)

	wordLabel.Text = string.format('<font color="#00FF00">%s</font>%s', typedPart, remainingPart)

	-- 敵HPバー更新
	if hpBarFill and hpLabel then
		local hpPercent = monsterHP / monsterMaxHP

		-- バーの長さをアニメーション
		local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(hpBarFill, tweenInfo, {
			Size = UDim2.new(hpPercent, 0, 1, 0)
		})
		tween:Play()

		-- 色を変更
		hpBarFill.BackgroundColor3 = getHPColor(hpPercent)

		-- テキスト更新
		hpLabel.Text = string.format("Enemy HP: %d / %d", monsterHP, monsterMaxHP)
	end
end

-- 単語を選択する関数
local function selectWord()
	if #typingLevels == 0 then
		-- デフォルト：level_1のみ
		typingLevels = {{level = "level_1", weight = 100}}
	end

	-- 重み付きランダム選択
	local totalWeight = 0
	for _, config in ipairs(typingLevels) do
		totalWeight = totalWeight + config.weight
	end

	local randomValue = math.random(1, totalWeight)
	local cumulativeWeight = 0
	local selectedLevel = "level_1"

	for _, config in ipairs(typingLevels) do
		cumulativeWeight = cumulativeWeight + config.weight
		if randomValue <= cumulativeWeight then
			selectedLevel = config.level
			break
		end
	end

	-- 選択されたレベルから単語を取得
	local wordList = TypingWords[selectedLevel]
	if wordList and #wordList > 0 then
		-- 前回と同じ単語を避ける（最大5回まで再抽選）
		local wordData = nil
		local attempts = 0

		repeat
			wordData = wordList[math.random(1, #wordList)]
			attempts = attempts + 1

			-- 新形式（テーブル）か旧形式（文字列）か判定
			local currentWordStr = type(wordData) == "table" and wordData.word or wordData

			-- 前回と違う単語が出たら、または5回試したらループ終了
			if currentWordStr ~= lastWord or attempts >= 5 or #wordList == 1 then
				break
			end
		until false

		-- 新形式（テーブル）か旧形式（文字列）か判定
		if type(wordData) == "table" then
			return wordData
		else
			-- 旧形式の場合は互換性のためテーブルに変換
			return {word = wordData}
		end
	else
		return {word = "apple", ja = "りんご"}  -- フォールバック
	end
end

-- 次の単語を設定
setNextWord = function()
	currentWordData = selectWord()
	currentWord = currentWordData.word
	currentIndex = 1

	-- 今回の単語を記憶（次回の連続回避用）
	lastWord = currentWord

	print(("[BattleUI DEBUG] currentWordData:"):format())
	print(currentWordData)
	print(("[BattleUI DEBUG] localeCode: %s"):format(localeCode))

	-- 翻訳を表示（フォールバック付き）
	if translationLabel then
		-- 優先順位：指定言語 → 日本語 → スペイン語 → フランス語 → 空
		local translation = currentWordData[localeCode]
			or currentWordData.ja
			or currentWordData.es
			or currentWordData.fr
			or ""

		translationLabel.Text = translation
		translationLabel.Visible = translation ~= ""
		print(("[BattleUI DEBUG] translation: %s"):format(translation))
	else
		warn("[BattleUI DEBUG] translationLabel が nil です！")
	end

	updateDisplay()
	print(("[BattleUI] 次の単語: %s (%s)"):format(currentWord, currentWordData[localeCode] or currentWordData.ja or ""))
end

-- UI作成
local function createBattleUI()
	battleGui = Instance.new("ScreenGui")
	battleGui.Name = "BattleUI"
	battleGui.ResetOnSpawn = false
	battleGui.Enabled = false
	battleGui.Parent = playerGui

	-- 中央の縦スタック（幅を統一）
	local centerStack = Instance.new("Frame")
	centerStack.Name = "CenterStack"
	centerStack.AnchorPoint = Vector2.new(0.5, 0.5)
	centerStack.Position = UDim2.new(0.5, 0, 0.5, 0)
	centerStack.Size = UDim2.new(0, STACK_WIDTH, 0, WORD_H + HP_BAR_H + PROG_H + (STACK_PAD * 2))
	centerStack.BackgroundTransparency = 1
	centerStack.BorderSizePixel = 0
	centerStack.ZIndex = 1
	centerStack.Parent = battleGui

	local stackLayout = Instance.new("UIListLayout")
	stackLayout.FillDirection = Enum.FillDirection.Vertical
	stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	stackLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	stackLayout.Padding = UDim.new(0, STACK_PAD)
	stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
	stackLayout.Parent = centerStack

	-- 暗転用フレーム
	darkenFrame = Instance.new("Frame")
	darkenFrame.Name = "DarkenFrame"
	darkenFrame.Size = UDim2.fromScale(1, 1)
	darkenFrame.Position = UDim2.fromScale(0, 0)
	darkenFrame.BackgroundColor3 = Color3.new(0, 0, 0)
	darkenFrame.BackgroundTransparency = 1
	darkenFrame.BorderSizePixel = 0
	darkenFrame.ZIndex = 1
	darkenFrame.Parent = battleGui

	-- 敵HPバー背景
	hpBarBackground = Instance.new("Frame")
	hpBarBackground.Name = "HPBarBackground"
	hpBarBackground.Size = UDim2.new(1, 0, 0, HP_BAR_H)
	hpBarBackground.Position = UDim2.new(0.5, -250, 0.25, 0)
	hpBarBackground.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
	hpBarBackground.BorderSizePixel = 0
	hpBarBackground.ZIndex = 2
	hpBarBackground.Parent = centerStack

	-- HPバー背景の角を丸くする
	local hpBarCorner = Instance.new("UICorner")
	hpBarCorner.CornerRadius = UDim.new(0, 8)
	hpBarCorner.Parent = hpBarBackground

	-- HPバー（塗りつぶし部分）
	hpBarFill = Instance.new("Frame")
	hpBarFill.Name = "HPBarFill"
	hpBarFill.Size = UDim2.new(1, 0, 1, 0)
	hpBarFill.Position = UDim2.new(0, 0, 0, 0)
	hpBarFill.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
	hpBarFill.BorderSizePixel = 0
	hpBarFill.ZIndex = 3
	hpBarFill.Parent = hpBarBackground

	-- HPバーの角を丸くする
	local hpFillCorner = Instance.new("UICorner")
	hpFillCorner.CornerRadius = UDim.new(0, 8)
	hpFillCorner.Parent = hpBarFill

	-- HPテキスト（バーの上に表示）
	hpLabel = Instance.new("TextLabel")
	hpLabel.Name = "HPLabel"
	hpLabel.Size = UDim2.new(1, 0, 1, 0)
	hpLabel.Position = UDim2.new(0, 0, 0, 0)
	hpLabel.BackgroundTransparency = 1
	hpLabel.TextColor3 = Color3.new(1, 1, 1)
	hpLabel.TextStrokeTransparency = 0.5
	hpLabel.Font = Enum.Font.GothamBold
	hpLabel.TextSize = 20
	hpLabel.Text = "HP: 10 / 10"
	hpLabel.ZIndex = 4
	hpLabel.Parent = hpBarBackground

	-- 単語表示用フレーム（枠）
	wordFrame = Instance.new("Frame")
	wordFrame.Name = "WordFrame"
	wordFrame.Size = UDim2.new(1, 0, 0, WORD_H)
	wordFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	wordFrame.BorderSizePixel = 3
	wordFrame.BorderColor3 = Color3.fromRGB(100, 200, 255)
	wordFrame.ZIndex = 2
	wordFrame.Parent = centerStack

	-- 枠の角を丸くする
	local wordFrameCorner = Instance.new("UICorner")
	wordFrameCorner.CornerRadius = UDim.new(0, 12)
	wordFrameCorner.Parent = wordFrame

	-- 枠に光るエフェクト（UIStroke）
	local wordFrameStroke = Instance.new("UIStroke")
	wordFrameStroke.Color = Color3.fromRGB(100, 200, 255)
	wordFrameStroke.Thickness = 3
	wordFrameStroke.Transparency = 0
	wordFrameStroke.Parent = wordFrame

	-- 単語表示（RichText対応）
	wordLabel = Instance.new("TextLabel")
	wordLabel.Name = "WordLabel"
	wordLabel.Size = UDim2.new(1, -40, 0.6, 0)
	wordLabel.Position = UDim2.new(0, 20, 0, 10)
	wordLabel.BackgroundTransparency = 1
	wordLabel.TextColor3 = Color3.new(1, 1, 1)
	wordLabel.TextStrokeTransparency = 0
	wordLabel.Font = Enum.Font.GothamBold
	wordLabel.TextSize = 60
	wordLabel.Text = "apple"
	wordLabel.RichText = true
	wordLabel.ZIndex = 3
	wordLabel.Parent = wordFrame

	-- 翻訳表示（単語の下）
	translationLabel = Instance.new("TextLabel")
	translationLabel.Name = "TranslationLabel"
	translationLabel.Size = UDim2.new(1, -40, 0.35, 0)
	translationLabel.Position = UDim2.new(0, 20, 0.65, 0)
	translationLabel.BackgroundTransparency = 1
	translationLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
	translationLabel.TextStrokeTransparency = 0.3
	translationLabel.Font = Enum.Font.Gotham
	translationLabel.TextSize = 28
	translationLabel.Text = "テスト"  -- デバッグ用の初期値
	translationLabel.TextYAlignment = Enum.TextYAlignment.Top
	translationLabel.Visible = true
	translationLabel.ZIndex = 3
	translationLabel.Parent = wordFrame

	print("[BattleUI DEBUG] translationLabel 作成完了")

	-- === Enemy Attack Progress ===
	enemyProgContainer = Instance.new("Frame")
	enemyProgContainer.Name = "EnemyAttackProgress"
	enemyProgContainer.AnchorPoint = Vector2.new(0.5, 1)
	enemyProgContainer.Size = UDim2.new(1, 0, 0, PROG_H)
	enemyProgContainer.Position = UDim2.new(0.5, 0, 0.98, 0)
	enemyProgContainer.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
	enemyProgContainer.BorderSizePixel = 0
	enemyProgContainer.Visible = false
	enemyProgContainer.ZIndex = 5
	enemyProgContainer.Parent = centerStack

	local enemyProgCorner = Instance.new("UICorner")
	enemyProgCorner.CornerRadius = UDim.new(0, 7)
	enemyProgCorner.Parent = enemyProgContainer

	enemyProgFill = Instance.new("Frame")
	enemyProgFill.Name = "Fill"
	enemyProgFill.Size = UDim2.new(0, 0, 1, 0)
	enemyProgFill.Position = UDim2.new(0, 0, 0, 0)
	enemyProgFill.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
	enemyProgFill.BorderSizePixel = 0
	enemyProgFill.ZIndex = 6
	enemyProgFill.Parent = enemyProgContainer

	local enemyProgFillCorner = Instance.new("UICorner")
	enemyProgFillCorner.CornerRadius = UDim.new(0, 7)
	enemyProgFillCorner.Parent = enemyProgFill

	-- === Countdown overlay ===
	countdownFrame = Instance.new("Frame")
	countdownFrame.Name = "Countdown"
	countdownFrame.BackgroundTransparency = 1
	countdownFrame.Size = UDim2.new(1, 0, 1, 0)
	countdownFrame.Visible = false
	countdownFrame.ZIndex = 20
	countdownFrame.Parent = battleGui

	countdownLabel = Instance.new("TextLabel")
	countdownLabel.Size = UDim2.new(1, 0, 1, 0)
	countdownLabel.BackgroundTransparency = 1
	countdownLabel.Font = Enum.Font.GothamBlack
	countdownLabel.TextScaled = true
	countdownLabel.TextColor3 = Color3.fromRGB(255,255,255)
	countdownLabel.TextStrokeTransparency = 0.2
	countdownLabel.ZIndex = 21
	countdownLabel.Parent = countdownFrame

	print("[BattleUI] UI作成完了")
end

-- === 攻撃プログレス開始（0→満了）===
startEnemyProgress = function(durationSec: number, startedAt: number?)
    if not enemyProgContainer or not enemyProgFill then return end

    -- 旧ループ停止
    if enemyProgConn then
        enemyProgConn:Disconnect()
        enemyProgConn = nil
    end

    enemyProgContainer.Visible = true

    -- サーバー基準 startedAt がある場合は進捗を補正
    local now = os.clock()
    local elapsed = 0
    if startedAt and type(startedAt) == "number" then
        elapsed = math.max(0, now - startedAt)
    end
    local startTime = now - elapsed

    enemyProgConn = game:GetService("RunService").RenderStepped:Connect(function()
        local t = math.clamp((os.clock() - startTime) / durationSec, 0, 1)
        enemyProgFill.Size = UDim2.new(t, 0, 1, 0)
        if t >= 1 then
            enemyProgConn:Disconnect()
            enemyProgConn = nil
        end
    end)
end

-- === 攻撃プログレス停止 ===
stopEnemyProgress = function()
    if enemyProgConn then
        enemyProgConn:Disconnect()
        enemyProgConn = nil
    end
    if enemyProgContainer and enemyProgFill then
        enemyProgContainer.Visible = false
        enemyProgFill.Size = UDim2.new(0, 0, 1, 0)
    end
end

-- === 被弾エフェクト（タイプミス／敵ターン共通）===
playHitFlash = function()
    if not wordFrame then return end

    -- 枠線キャッシュ
    local frameStroke = wordFrame:FindFirstChildOfClass("UIStroke")

    -- 赤く点滅
    wordFrame.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    wordFrame.BackgroundTransparency = 0.3
    if frameStroke then
        frameStroke.Color = Color3.fromRGB(255, 50, 50)
    end

    TweenService:Create(wordFrame, TweenInfo.new(0.3), {
        BackgroundColor3 = Color3.fromRGB(30, 30, 40),
        BackgroundTransparency = 0.2
    }):Play()

    if frameStroke then
        TweenService:Create(frameStroke, TweenInfo.new(0.3), {
            Color = Color3.fromRGB(100, 200, 255)
        }):Play()
    end
end


if not TypingCorrectSound then
	warn("[BattleUI] TypingCorrect効果音が見つかりません (WaitForChild タイムアウト)")
end
if not TypingErrorSound then
	warn("[BattleUI] TypingError効果音が見つかりません (WaitForChild タイムアウト)")
end

-- バトル開始処理（省略なし・整備版）
local function onBattleStart(monsterName, hp, maxHP, damage, levels, pHP, pMaxHP)
	print("[BattleUI] === onBattleStart呼び出し ===")

	-- nil チェックとデフォルト値
	monsterName = monsterName or "Unknown"
	hp = hp or 10
	maxHP = maxHP or 10
	damage = damage or 1
	levels = levels or {{level = "level_1", weight = 100}}
	pHP = pHP or 100
	pMaxHP = pMaxHP or 100

	print(("[BattleUI] バトル開始: vs %s (敵HP: %d, プレイヤーHP: %d/%d, Damage: %d)"):format(
		monsterName, hp, pHP, pMaxHP, damage
	))

	-- すでに戦闘中なら無視
	if inBattle then
		print("[BattleUI DEBUG] すでに戦闘中")
		return
	end

	-- 状態セット
	inBattle = true
	monsterHP = hp
	monsterMaxHP = maxHP
	playerHP = pHP
	playerMaxHP = pMaxHP
	damagePerKey = damage
	typingLevels = levels

	-- カメラ・入力ブロック
	blockSystemKeys()
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
			humanoid.JumpHeight = 0
		end
	end

	-- RobloxのUIを無効化
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)
	end)

	-- UI表示
	print("[BattleUI] UIを表示")
	battleGui.Enabled = true

	-- ★ プログレス初期化（確実に1本化）
	if stopEnemyProgress then
		stopEnemyProgress()
	else
		-- フォールバック：接続解除＆非表示
		if enemyProgConn then enemyProgConn:Disconnect() enemyProgConn = nil end
		if enemyProgContainer then enemyProgContainer.Visible = false end
	end
	if enemyProgContainer and enemyProgFill then
		enemyProgContainer.Visible = true
		enemyProgFill.Size = UDim2.new(0, 0, 1, 0)
	end

	-- 効果音の取りこぼし保険
	if resolveSoundsIfNeeded then
		resolveSoundsIfNeeded()
	end

	-- カウントダウン有無に応じて入力制御
	TypingEnabled = not PROGRESS_COUNTDOWN_ON_START

	-- 背景の暗転
	if darkenFrame then
		darkenFrame.BackgroundTransparency = 0.4
	end

	-- ラベルなどリセット
	if wordLabel then
		wordLabel.RichText = true
		wordLabel.TextColor3 = Color3.new(1, 1, 1)
		wordLabel.Text = ""
		wordLabel.TextTransparency = 0
		wordLabel.TextStrokeTransparency = 0
	end
	if translationLabel then
		translationLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
		translationLabel.Text = ""
		translationLabel.Visible = true
		translationLabel.TextTransparency = 0
		translationLabel.TextStrokeTransparency = 0.3
	end
	if hpLabel then
		hpLabel.TextColor3 = Color3.new(1, 1, 1)
		hpLabel.Text = ""
		hpLabel.TextTransparency = 0
		hpLabel.TextStrokeTransparency = 0.5
	end
	if hpBarFill then
		hpBarFill.Size = UDim2.new(1, 0, 1, 0)
		hpBarFill.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
		hpBarFill.BackgroundTransparency = 0
	end
	if hpBarBackground then
		hpBarBackground.BackgroundTransparency = 0
	end
	if playerHPBarFill then
		playerHPBarFill.Size = UDim2.new(1, 0, 1, 0)
		playerHPBarFill.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
	end
	if wordFrame then
		wordFrame.BorderColor3 = Color3.fromRGB(100, 200, 255)
		wordFrame.BackgroundTransparency = 0.2
		local frameStroke = wordFrame:FindFirstChildOfClass("UIStroke")
		if frameStroke then
			frameStroke.Color = Color3.fromRGB(100, 200, 255)
			frameStroke.Transparency = 0
		end
	end

	-- 最初の単語を設定（※ カウントダウンONのときは後で出す）
	local function setFirstWordNow()
		if type(setNextWord) == "function" then
			setNextWord()
		else
			warn("[BattleUI] setNextWord が未定義です")
		end
	end

	-- カウントダウン動作
	if PROGRESS_COUNTDOWN_ON_START then
		-- カウントダウン表示
		if type(runCountdown) == "function" then
			if countdownFrame then countdownFrame.Visible = true end
			runCountdown(COUNTDOWN_SECONDS or 3)
			if countdownFrame then countdownFrame.Visible = false end
		end
		-- 入力解禁＆単語表示
		TypingEnabled = true
		setFirstWordNow()
		-- ★ 初回プログレスはここでは回さない（サーバからの EnemyAttackCycleStart を待つ）
	else
		-- カウントダウン無し：即座に単語表示
		setFirstWordNow()
		-- ★ 初回プログレスは「仮速度」で回さない（サーバ通知で正しい速度・開始時刻に同期）
		-- ※ 以前の不具合（初回だけ途中で被弾）を避けるため、ここは何もしない
	end

	-- 戦闘タイムアウト（お守り）
	-- if currentBattleTimeout then
	-- 	task.cancel(currentBattleTimeout)
	-- 	currentBattleTimeout = nil
	-- end
	-- currentBattleTimeout = task.delay(30, function()
	-- 	if inBattle then
	-- 		warn("[BattleUI] バトルタイムアウト！強制終了します")
	-- 		if onBattleEnd then
	-- 			onBattleEnd(false)
	-- 		end
	-- 	end
	-- end)

	-- ★ 初回サイクル・ウォッチドッグ：0.35秒待っても同期が来なければ要求
	task.delay(0.35, function()
		if inBattle and (os.clock() - lastCycleAt) > 0.30 then
			requestEnemyCycleSync("first-cycle watchdog")
		end
	end)

	print("[BattleUI] === バトル開始処理完了 ===")
end


-- バトル終了処理
onBattleEnd = function(victory)
	print("[BattleUI] === バトル終了開始: " .. tostring(victory) .. " ===")

	-- 既にバトルが終了している場合はスキップ
	if not inBattle and not battleGui.Enabled then
		print("[BattleUI] 既にバトル終了済み")
		return
	end

	-- 【最優先】バトル状態を即座にクリア（キー入力を停止）
	inBattle = false
	currentWord = ""
	currentWordData = nil
	currentIndex = 1
	playerHP = 0
	playerMaxHP = 0

	-- タイムアウトをキャンセル
	if currentBattleTimeout then
		task.cancel(currentBattleTimeout)
		currentBattleTimeout = nil
	end

	-- 敵攻撃プログレスを停止＆隠す ← ココが「直後」
	stopEnemyProgress()

	-- 勝利時の処理
	if victory then
		-- システムキーのブロックを解除
		unblockSystemKeys()

		print("[BattleUI] Roblox UI再有効化")

		-- Roblox UIを再有効化
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, true)
		end)

		-- 勝利メッセージを表示
		if wordLabel then
			wordLabel.RichText = false
			wordLabel.Text = "VICTORY!"
			wordLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
			wordLabel.TextTransparency = 0
			wordLabel.TextStrokeTransparency = 0

			-- 0.5秒かけてフェードアウト
			TweenService:Create(wordLabel, TweenInfo.new(0.5), {
				TextTransparency = 1,
				TextStrokeTransparency = 1
			}):Play()
		end

		-- 翻訳ラベルを非表示
		if translationLabel then
			translationLabel.Visible = false
		end

		-- 枠を金色にしてフェードアウト
		if wordFrame then
			wordFrame.BorderColor3 = Color3.fromRGB(255, 215, 0)
			local frameStroke = wordFrame:FindFirstChildOfClass("UIStroke")
			if frameStroke then
				frameStroke.Color = Color3.fromRGB(255, 215, 0)
				TweenService:Create(frameStroke, TweenInfo.new(0.5), {
					Transparency = 1
				}):Play()
			end

			TweenService:Create(wordFrame, TweenInfo.new(0.5), {
				BackgroundTransparency = 1
			}):Play()
		end

		-- HPバーをフェードアウト
		if hpBarBackground then
			TweenService:Create(hpBarBackground, TweenInfo.new(0.5), {
				BackgroundTransparency = 1
			}):Play()
		end

		if hpBarFill then
			TweenService:Create(hpBarFill, TweenInfo.new(0.5), {
				BackgroundTransparency = 1
			}):Play()
		end

		if hpLabel then
			TweenService:Create(hpLabel, TweenInfo.new(0.5), {
				TextTransparency = 1,
				TextStrokeTransparency = 1
			}):Play()
		end

		-- プレイヤーの入力ブロックを解除
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = 16
				humanoid.JumpPower = 50
				humanoid.JumpHeight = 7.2
			end
		end

		-- 画面を明るく戻す
		TweenService:Create(darkenFrame, TweenInfo.new(0.5), {
			BackgroundTransparency = 1
		}):Play()

		-- UIを非表示にするための遅延実行（別スレッドで）
		task.spawn(function()
			task.wait(0.6)  -- アニメーション完了を待つ
			if not inBattle then  -- まだ次のバトルが始まっていないことを確認
				battleGui.Enabled = false

				-- プログレスバーを隠す＆進行ループ停止
				if enemyProgConn then
					enemyProgConn:Disconnect()
					enemyProgConn = nil
				end
				if enemyProgContainer then
					enemyProgContainer.Visible = false
				end

				-- 敵攻撃プログレスバーを非表示
				if enemyProgContainer then
					enemyProgContainer.Visible = false
				end
			end
		end)
	else
		-- 敗北時：UIを維持したまま死亡選択UIを待つ
		print("[BattleUI] 敗北 - UIを維持します")

		-- 敗北メッセージ
		if wordLabel then
			wordLabel.RichText = false
			wordLabel.Text = "DEFEAT..."
			wordLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		end

		-- 翻訳ラベルを非表示
		if translationLabel then
			translationLabel.Visible = false
		end

		-- 枠の色も変更
		if wordFrame then
			local frameStroke = wordFrame:FindFirstChildOfClass("UIStroke")
			if frameStroke then
				frameStroke.Color = Color3.fromRGB(255, 100, 100)
			end
		end

		-- システムキーのブロックとRoblox UIは維持
		-- プレイヤーの移動制限も維持
		-- 死亡選択UIで選んだ後に解除する
	end

	print("[BattleUI] === バトル終了完了 ===")
end

-- HP更新処理（敵）
local function onHPUpdate(newHP)
	monsterHP = newHP

	print(("[BattleUI] ========================================"):format())
	print(("[BattleUI] 敵HP更新"):format())
	print(("  新HP: %d"):format(newHP))
	print(("  最大HP: %d"):format(monsterMaxHP))
	print(("  HP割合: %.1f%%"):format((newHP / monsterMaxHP) * 100))
	print(("[BattleUI] ========================================"):format())

	updateDisplay()

	-- HPが0になったら勝利（サーバーからの通知も来るが念のため）
	if monsterHP <= 0 then
		print("[BattleUI] ⚠️ 敵HPが0になりました（クライアント側で検出）")
	end
end

-- HP更新処理（プレイヤー）
local function onPlayerHPUpdate(newHP, newMaxHP)
	playerHP = newHP
	playerMaxHP = newMaxHP or playerMaxHP
	updateDisplay()

	print(("[BattleUI] プレイヤーHP更新: %d / %d"):format(playerHP, playerMaxHP))

	-- HPが0になったら敗北（サーバーからの通知も来るが念のため）
	if playerHP <= 0 then
		print("[BattleUI] プレイヤーHPが0になりました")
	end
end

-- システムキーをブロックする入力処理（最優先）
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	-- バトル中にシステムキーが押された場合、先に処理して消費する
	if inBattle and input.UserInputType == Enum.UserInputType.Keyboard then
		local blockedKeys = {
			[Enum.KeyCode.I] = true,
			[Enum.KeyCode.O] = true,
			[Enum.KeyCode.Slash] = true,
			[Enum.KeyCode.Backquote] = true,
			[Enum.KeyCode.Tab] = true,
			[Enum.KeyCode.BackSlash] = true,
			[Enum.KeyCode.Equals] = true,
			[Enum.KeyCode.Minus] = true,
		}

		if blockedKeys[input.KeyCode] then
			-- このキーはタイピング処理に回す（ズームなどは発動させない）
			return
		end
	end
end)

playHitFlash = function()
	if not wordFrame then return end
	local frameStroke = wordFrame:FindFirstChildOfClass("UIStroke")

	-- 赤く点滅
	wordFrame.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
	wordFrame.BackgroundTransparency = 0.3
	if frameStroke then
		frameStroke.Color = Color3.fromRGB(255, 50, 50)
	end

	TweenService:Create(wordFrame, TweenInfo.new(0.3), {
		BackgroundColor3 = Color3.fromRGB(30, 30, 40),
		BackgroundTransparency = 0.2,
	}):Play()

	if frameStroke then
		TweenService:Create(frameStroke, TweenInfo.new(0.3), {
			Color = Color3.fromRGB(100, 200, 255),
		}):Play()
	end
end


-- キー入力処理
local function onKeyPress(input, gameProcessed)
	if not inBattle then return end
	if not TypingEnabled then return end

	if input.UserInputType == Enum.UserInputType.Keyboard then
		local keyCode = input.KeyCode
		local keyString = UserInputService:GetStringForKeyCode(keyCode):lower()

		-- 英字のみ受け付け
		if #keyString == 1 and keyString:match("%a") then
			local expectedChar = string.sub(currentWord, currentIndex, currentIndex):lower()

			if keyString == expectedChar then
				-- 正解
				currentIndex = currentIndex + 1

				-- 正解音を再生
				if TypingCorrectSound then
					TypingCorrectSound:Play()
				end

				-- サーバーにダメージ通知
				BattleDamageEvent:FireServer(damagePerKey)

				-- 単語完成チェック
				if currentIndex > #currentWord then
					task.wait(0.3)
					if inBattle then
						setNextWord()
					end
				else
					updateDisplay()
				end
			else
				-- タイプミス
				if TypingErrorSound then
					TypingErrorSound:Play()
				end

				if playHitFlash then playHitFlash() end

				-- タイプミス時のダメージをサーバーに通知
				local TypingMistakeEvent = ReplicatedStorage:FindFirstChild("TypingMistake")
				if TypingMistakeEvent then
					TypingMistakeEvent:FireServer()
				end
			end
		end
	end
end

-- 初期化
createBattleUI()

print("[BattleUI] イベント接続中...")
BattleStartEvent.OnClientEvent:Connect(onBattleStart)
BattleEndEvent.OnClientEvent:Connect(onBattleEnd)

local EnemyDamageEvent = ReplicatedStorage:WaitForChild("EnemyDamage", 30)
EnemyDamageEvent.OnClientEvent:Connect(function(payload)
	-- バトル中だけ反応
	if not inBattle then return end

	-- 敵ターンの被弾エフェクト
	playHitFlash()

	-- 敵被弾SE
	if EnemyHitSound and EnemyHitSound.Play then
		EnemyHitSound:Play()
	end
end)

EnemyAttackCycleStartEvent.OnClientEvent:Connect(function(payload)
	-- まずは受信ログ（ここが出ないならサーバー送信側かイベント名ミス）
	print("[BattleUI] EnemyAttackCycleStart received")

	-- UI がまだなら一旦保存（inBattle判定で落とさない）
	if not battleGui or not battleGui.Enabled then
		pendingEnemyCycle = payload
		print("[BattleUI] stashed first cycle payload (UI not ready yet)")
		return
	end

	applyEnemyCycle(payload)
end)



-- HP更新イベント（敵）
local HPUpdateEvent = ReplicatedStorage:FindFirstChild("BattleHPUpdate")
if HPUpdateEvent then
	HPUpdateEvent.OnClientEvent:Connect(onHPUpdate)
end

-- HP更新イベント（プレイヤー）
local PlayerHPUpdateEvent = ReplicatedStorage:FindFirstChild("PlayerHPUpdate")

if PlayerHPUpdateEvent then
	PlayerHPUpdateEvent.OnClientEvent:Connect(onPlayerHPUpdate)
else
	warn("[BattleUI] PlayerHPUpdate イベントが見つかりません")
end

UserInputService.InputBegan:Connect(onKeyPress)

-- 緊急脱出用：Escキーで強制終了
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.Escape and battleGui.Enabled then
		warn("[BattleUI] Escキーで強制終了")

		-- システムキーのブロックを解除
		unblockSystemKeys()

		-- Roblox UIを再有効化
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, true)
		end)

		darkenFrame.BackgroundTransparency = 1
		battleGui.Enabled = false
		inBattle = false
		currentWord = ""
		currentWordData = nil
		currentIndex = 1
		playerHP = 0
		playerMaxHP = 0

		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = 16
				humanoid.JumpPower = 50
				humanoid.JumpHeight = 7.2
			end
		end
	end
end)

-- ★ フォーカス復帰で再同期
UserInputService.WindowFocused:Connect(function()
	if inBattle then
		requestEnemyCycleSync("window focused")
	end
end)

print("[BattleUI] クライアント初期化完了（タイピングモード）")