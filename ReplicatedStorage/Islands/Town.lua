-- ReplicatedStorage/Islands/Town.lua (内容を置き換え)
return {
    name = "StartTown", -- 島名を「StartTown」に戻す
    centerX = 0,
    centerZ = 0,
    sizeXZ = 400,
    baseY = 50, -- 安定化のため高さを維持
    thickness = 8,
    grid = 10,
    hillAmplitude = 3,
    hillScale = 80,
    seed = 77777,
    generateOcean = false,
    safeZone = true,
    baseMaterial = Enum.Material.Slate,
}