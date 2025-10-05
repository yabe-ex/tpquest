-- ServerScriptService/DataStoreManager.lua
-- DataStoreの基本操作を管理するモジュール

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local DataStoreManager = {}

-- データのキーを定義
local PLAYER_DATA_STORE = DataStoreService:GetDataStore("TypingQuestPlayerSaveData_V1")
local SAVE_SUCCESS_EVENT = Instance.new("RemoteEvent")
SAVE_SUCCESS_EVENT.Name = "SaveSuccess"
SAVE_SUCCESS_EVENT.Parent = game:GetService("ReplicatedStorage")

-- データの保存 (非同期)
function DataStoreManager.SaveData(player: Player, data: table)
    local success, err = pcall(function()
        -- プレイヤーのUserIdをキーとして使用
        PLAYER_DATA_STORE:SetAsync(player.UserId, data)
    end)

    if success then
        print(("[DataStoreManager] %s のデータを保存しました。キー: %d"):format(player.Name, player.UserId))

        -- クライアントに保存成功を通知
        SAVE_SUCCESS_EVENT:FireClient(player, true)
    else
        warn(("[DataStoreManager] %s のデータ保存に失敗しました: %s"):format(player.Name, err))

        -- クライアントに保存失敗を通知
        SAVE_SUCCESS_EVENT:FireClient(player, false)
    end
    return success
end

-- データの読み込み (非同期)
function DataStoreManager.LoadData(player: Player)
    local data = nil
    local success, err = pcall(function()
        -- データの取得
        data = PLAYER_DATA_STORE:GetAsync(player.UserId)
    end)

    if success then
        print(("[DataStoreManager] %s のデータを読み込みました。"):format(player.Name))

        -- データがnilの場合、新規プレイヤーとして空のテーブルを返す
        return data or {}
    else
        warn(("[DataStoreManager] %s のデータ読み込みに失敗しました: %s"):format(player.Name, err))
        return {} -- 失敗した場合は空のデータを返し、ゲームを継続させる
    end
end

-- サーバーモジュールの初期化は不要なため省略

return DataStoreManager