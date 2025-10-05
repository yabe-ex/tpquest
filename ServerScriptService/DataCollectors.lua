-- ServerScriptService/DataCollectors.lua
-- セーブ/ロードに必要なデータを収集・適用するモジュール

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local DataCollectors = {}

-- プレイヤーの状態を収集
function DataCollectors.collectPlayerState(player: Player, playerStats)
    local character = player.Character or player.CharacterAdded:Wait()
    local hrp = character:WaitForChild("HumanoidRootPart", 5)

    local zoneManager = require(script.Parent.ZoneManager)
    local currentZone = zoneManager.GetPlayerZone(player)

    local playerState = {
        -- ステータス (PlayerStatsから取得)
        Stats = {
            Level = playerStats.Level,
            Experience = playerStats.Experience,
            Gold = playerStats.Gold,
            CurrentHP = playerStats.CurrentHP,
        },
        -- 位置情報
        Location = {
            ZoneName = currentZone or "ContinentTown", -- デフォルトはタウン
            X = hrp and hrp.Position.X or 0,
            Y = hrp and hrp.Position.Y or 50, -- Yは地形から少し上の位置
            Z = hrp and hrp.Position.Z or 0,
        },
    }

    return playerState
end

-- ワールドの状態（モンスターなど）を収集
function DataCollectors.collectFieldState(zoneName)
    local fieldState = {
        Monsters = {}
    }

    -- 現在のアクティブなモンスターを検索し、状態を保存
    local monstersInZone = {}

    -- MonsterSpawnerの内部構造に依存しない汎用的な方法でモンスターを検索
    for _, model in ipairs(Workspace:GetChildren()) do
        if model:IsA("Model") and model:GetAttribute("IsEnemy") and model:GetAttribute("SpawnZone") == zoneName then
            local monsterHrp = model:FindFirstChild("HumanoidRootPart")
            local monsterHumanoid = model:FindFirstChildOfClass("Humanoid")

            if monsterHrp and monsterHumanoid and monsterHumanoid.Health > 0 then
                local monsterKind = model:GetAttribute("MonsterKind")
                local monsterHP = monsterHumanoid.Health

                table.insert(fieldState.Monsters, {
                    Kind = monsterKind,
                    HP = monsterHP,
                    X = monsterHrp.Position.X,
                    Y = monsterHrp.Position.Y,
                    Z = monsterHrp.Position.Z,
                })
            end
        end
    end

    return fieldState
end

-- ワールドの状態を復元 (ロード時に使用)
function DataCollectors.restoreFieldState(player: Player, fieldState: table)
    -- この機能は、MonsterSpawnerモジュールに依存するため、後でMonsterSpawner.server.luaを修正して実装します。
    warn("[DataCollectors] restoreFieldState はまだ実装されていません。")
end

-- 総合セーブデータを作成
function DataCollectors.createSaveData(player: Player, playerStats)
    local currentZone = (require(script.Parent.ZoneManager)).GetPlayerZone(player)

    local saveData = {
        PlayerState = DataCollectors.collectPlayerState(player, playerStats),
        -- Townはセーブ対象外 (モンスターがいないため)
        FieldState = currentZone ~= "ContinentTown" and DataCollectors.collectFieldState(currentZone) or nil,
        SaveTime = os.time(),
    }

    return saveData
end

return DataCollectors