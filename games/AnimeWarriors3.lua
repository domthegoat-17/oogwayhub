local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

local TELEPORT_RANGE = 6
local SCAN_THRESHOLD = 200
local TELEPORT_DETECT = 50

local autoFarm = false
local gauntletFarm = false
local selectedEnemy = nil
local selectedBounds = nil
local selectedWorld = nil
local ScannedEnemies = {}
local lastScanPos = nil

local Worlds = {
    ["Rain Village"] = {
        ["Spirit"]        = 4,
        ["Instinct"]      = 5.4,
        ["Enlightenment"] = 7,
        ["Demon"]         = 9,
        ["Paper Angel"]   = 18,
        ["Deva"]          = 24,
    },
    ["Future City"]  = {},
    ["Sand Village"] = {},
    ["Sky Island"]   = {},
    ["Planet Nemak"] = {},
}

local function isUUID(name)
    return string.match(name, "^%x+%-%x+%-%x+%-%x+%-%x+$") ~= nil
end

local function getBoundsFirst(obj)
    local bounds = obj:GetAttribute("bounds")
    if not bounds then return 0 end
    return tonumber(tostring(bounds):match("^([%d%.]+)")) or 0
end

local function getNearestOfType(targetBounds)
    local char = player.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end
    local root = char.HumanoidRootPart
    local nearest, nearestDist = nil, math.huge
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and isUUID(obj.Name) then
            local dead = obj:GetAttribute("dead")
            local hrp = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChildOfClass("BasePart")
            if dead == false and hrp then
                local b = getBoundsFirst(obj)
                if math.abs(b - targetBounds) < 1 then
                    local dist = (hrp.Position - root.Position).Magnitude
                    if dist < nearestDist then
                        nearest = obj
                        nearestDist = dist
                    end
                end
            end
        end
    end
    return nearest
end

local function getNearestAlive()
    local char = player.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end
    local root = char.HumanoidRootPart
    local nearest, nearestDist = nil, math.huge
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and isUUID(obj.Name) then
            local dead = obj:GetAttribute("dead")
            local hrp = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChildOfClass("BasePart")
            if dead == false and hrp then
                local dist = (hrp.Position - root.Position).Magnitude
                if dist < nearestDist then
                    nearest = obj
                    nearestDist = dist
                end
            end
        end
    end
    return nearest
end

local function scanWorkspace()
    local found = {}
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and isUUID(obj.Name) then
            local dead = obj:GetAttribute("dead")
            if dead ~= true then
                local b = getBoundsFirst(obj)
                if b > 0 then
                    local key = string.format("%.1f", b)
                    found[key] = (found[key] or 0) + 1
                end
            end
        end
    end
    ScannedEnemies = found
    local char = player.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        lastScanPos = char.HumanoidRootPart.Position
    end
end

-- GUI
local sg = Instance.new("ScreenGui", player.PlayerGui)
sg.Name = "OogwayHub"

local main = Instance.new("Frame", sg)
main.Size = UDim2.new(0, 200, 0, 260)
main.Position = UDim2.new(0, 20, 0.3, 0)
main.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
main.BorderSizePixel = 0
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)

local sidePanel = Instance.new("Frame", sg)
sidePanel.Size = UDim2.new(0, 160, 0, 0)
sidePanel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
sidePanel.BorderSizePixel = 0
sidePanel.ClipsDescendants = true
sidePanel.Visible = false
Instance.new("UICorner", sidePanel).CornerRadius = UDim.new(0, 8)
Instance.new("UIListLayout", sidePanel).SortOrder = Enum.SortOrder.LayoutOrder

local activeBtn = nil

-- Drag
local dragging, dragStart, startPos
main.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(0, startPos.X.Offset + delta.X, 0, startPos.Y.Offset + delta.Y)
        if sidePanel.Visible and activeBtn then
            local absPos = activeBtn.AbsolutePosition
            local absSize = activeBtn.AbsoluteSize
            sidePanel.Position = UDim2.new(0, absPos.X + absSize.X + 8, 0, absPos.Y)
        end
    end
end)

-- Title bar
local titleBar = Instance.new("Frame", main)
titleBar.Size = UDim2.new(1, 0, 0, 32)
titleBar.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
titleBar.BorderSizePixel = 0
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel", titleBar)
title.Size = UDim2.new(1, -40, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "OogwayHub"

local closeBtn = Instance.new("TextButton", titleBar)
closeBtn.Size = UDim2.new(0, 28, 0, 22)
closeBtn.Position = UDim2.new(1, -32, 0, 5)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
closeBtn.Text = "X"
closeBtn.BorderSizePixel = 0
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 4)
closeBtn.MouseButton1Click:Connect(function() sg:Destroy() end)

-- Tab bar
local farmTabBtn = Instance.new("TextButton", main)
farmTabBtn.Size = UDim2.new(0.5, 0, 0, 30)
farmTabBtn.Position = UDim2.new(0, 0, 0, 32)
farmTabBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
farmTabBtn.TextColor3 = Color3.new(1, 1, 1)
farmTabBtn.Font = Enum.Font.GothamBold
farmTabBtn.TextSize = 12
farmTabBtn.Text = "FARM"
farmTabBtn.BorderSizePixel = 0

local gauntletTabBtn = Instance.new("TextButton", main)
gauntletTabBtn.Size = UDim2.new(0.5, 0, 0, 30)
gauntletTabBtn.Position = UDim2.new(0.5, 0, 0, 32)
gauntletTabBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
gauntletTabBtn.TextColor3 = Color3.new(1, 1, 1)
gauntletTabBtn.Font = Enum.Font.GothamBold
gauntletTabBtn.TextSize = 12
gauntletTabBtn.Text = "GAUNTLET"
gauntletTabBtn.BorderSizePixel = 0

local tabDiv = Instance.new("Frame", main)
tabDiv.Size = UDim2.new(1, 0, 0, 1)
tabDiv.Position = UDim2.new(0, 0, 0, 62)
tabDiv.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
tabDiv.BorderSizePixel = 0

-- Tab content frames
local farmContent = Instance.new("Frame", main)
farmContent.Size = UDim2.new(1, 0, 1, -63)
farmContent.Position = UDim2.new(0, 0, 0, 63)
farmContent.BackgroundTransparency = 1
farmContent.Visible = true

local gauntletContent = Instance.new("Frame", main)
gauntletContent.Size = UDim2.new(1, 0, 1, -63)
gauntletContent.Position = UDim2.new(0, 0, 0, 63)
gauntletContent.BackgroundTransparency = 1
gauntletContent.Visible = false

-- Helpers
local function makeMainBtn(parent, text, y)
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(1, -20, 0, 30)
    btn.Position = UDim2.new(0, 10, 0, y)
    btn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 12
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.BorderSizePixel = 0
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    local arrow = Instance.new("TextLabel", btn)
    arrow.Name = "Arrow"
    arrow.Size = UDim2.new(0, 20, 1, 0)
    arrow.Position = UDim2.new(1, -22, 0, 0)
    arrow.BackgroundTransparency = 1
    arrow.TextColor3 = Color3.fromRGB(150, 150, 150)
    arrow.Font = Enum.Font.GothamBold
    arrow.TextSize = 12
    arrow.Text = "▶"
    return btn
end

local function makeSideItem(text, onClick)
    local btn = Instance.new("TextButton", sidePanel)
    btn.Size = UDim2.new(1, 0, 0, 32)
    btn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 12
    btn.Text = text
    btn.BorderSizePixel = 0
    btn.MouseButton1Click:Connect(onClick)
    return btn
end

local function closeSide()
    sidePanel.Visible = false
    sidePanel.Size = UDim2.new(0, 160, 0, 0)
    for _, c in pairs(sidePanel:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    if activeBtn then
        activeBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        local arrow = activeBtn:FindFirstChild("Arrow")
        if arrow then arrow.Text = "▶" end
        activeBtn = nil
    end
end

local function openSide(btn, buildFn)
    if sidePanel.Visible and activeBtn == btn then
        closeSide()
        return
    end
    closeSide()
    buildFn()
    local count = 0
    for _, c in pairs(sidePanel:GetChildren()) do
        if c:IsA("TextButton") then count = count + 1 end
    end
    local absPos = btn.AbsolutePosition
    local absSize = btn.AbsoluteSize
    sidePanel.Size = UDim2.new(0, 160, 0, count * 32)
    sidePanel.Position = UDim2.new(0, absPos.X + absSize.X + 8, 0, absPos.Y)
    sidePanel.Visible = true
    activeBtn = btn
    btn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
    local arrow = btn:FindFirstChild("Arrow")
    if arrow then arrow.Text = "▼" end
end

-- Farm tab content
local worldLabel = Instance.new("TextLabel", farmContent)
worldLabel.Size = UDim2.new(1, -20, 0, 18)
worldLabel.Position = UDim2.new(0, 10, 0, 8)
worldLabel.BackgroundTransparency = 1
worldLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
worldLabel.Font = Enum.Font.Gotham
worldLabel.TextSize = 10
worldLabel.TextXAlignment = Enum.TextXAlignment.Left
worldLabel.Text = "WORLD"

local worldBtn = makeMainBtn(farmContent, "Select World", 26)

local enemyLabel = Instance.new("TextLabel", farmContent)
enemyLabel.Size = UDim2.new(1, -20, 0, 18)
enemyLabel.Position = UDim2.new(0, 10, 0, 66)
enemyLabel.BackgroundTransparency = 1
enemyLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
enemyLabel.Font = Enum.Font.Gotham
enemyLabel.TextSize = 10
enemyLabel.TextXAlignment = Enum.TextXAlignment.Left
enemyLabel.Text = "ENEMY"

local enemyBtn = makeMainBtn(farmContent, "Select Enemy", 84)

local farmBtn = Instance.new("TextButton", farmContent)
farmBtn.Size = UDim2.new(1, -20, 0, 34)
farmBtn.Position = UDim2.new(0, 10, 0, 128)
farmBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
farmBtn.TextColor3 = Color3.new(1, 1, 1)
farmBtn.Font = Enum.Font.GothamBold
farmBtn.TextSize = 13
farmBtn.Text = "Auto Farm: OFF"
farmBtn.BorderSizePixel = 0
Instance.new("UICorner", farmBtn).CornerRadius = UDim.new(0, 6)

-- Gauntlet tab content
local gauntletInfo = Instance.new("TextLabel", gauntletContent)
gauntletInfo.Size = UDim2.new(1, -20, 0, 60)
gauntletInfo.Position = UDim2.new(0, 10, 0, 8)
gauntletInfo.BackgroundTransparency = 1
gauntletInfo.TextColor3 = Color3.fromRGB(150, 150, 150)
gauntletInfo.Font = Enum.Font.Gotham
gauntletInfo.TextSize = 11
gauntletInfo.TextXAlignment = Enum.TextXAlignment.Left
gauntletInfo.TextWrapped = true
gauntletInfo.Text = "Targets all alive enemies.\nNo selection needed.\nGood for Gauntlet floors."

local gauntletBtn = Instance.new("TextButton", gauntletContent)
gauntletBtn.Size = UDim2.new(1, -20, 0, 34)
gauntletBtn.Position = UDim2.new(0, 10, 0, 78)
gauntletBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
gauntletBtn.TextColor3 = Color3.new(1, 1, 1)
gauntletBtn.Font = Enum.Font.GothamBold
gauntletBtn.TextSize = 13
gauntletBtn.Text = "Gauntlet: OFF"
gauntletBtn.BorderSizePixel = 0
Instance.new("UICorner", gauntletBtn).CornerRadius = UDim.new(0, 6)

-- Tab switching
local function showTab(tab)
    farmContent.Visible = (tab == "farm")
    gauntletContent.Visible = (tab == "gauntlet")
    farmTabBtn.BackgroundColor3 = tab == "farm" and Color3.fromRGB(60, 60, 80) or Color3.fromRGB(40, 40, 40)
    gauntletTabBtn.BackgroundColor3 = tab == "gauntlet" and Color3.fromRGB(60, 60, 80) or Color3.fromRGB(40, 40, 40)
    closeSide()
end

farmTabBtn.MouseButton1Click:Connect(function() showTab("farm") end)
gauntletTabBtn.MouseButton1Click:Connect(function() showTab("gauntlet") end)

-- World dropdown
worldBtn.MouseButton1Click:Connect(function()
    openSide(worldBtn, function()
        for worldName in pairs(Worlds) do
            makeSideItem(worldName, function()
                selectedWorld = worldName
                worldBtn.Text = worldName
                selectedEnemy = nil
                selectedBounds = nil
                enemyBtn.Text = "Select Enemy"
                closeSide()
            end)
        end
    end)
end)

-- Enemy dropdown (pre-mapped + scanned, no world required)
enemyBtn.MouseButton1Click:Connect(function()
    openSide(enemyBtn, function()
        local hasItems = false

        if selectedWorld and Worlds[selectedWorld] then
            for name, bounds in pairs(Worlds[selectedWorld]) do
                hasItems = true
                makeSideItem(name, function()
                    selectedEnemy = name
                    selectedBounds = bounds
                    enemyBtn.Text = name
                    closeSide()
                end)
            end
        end

        local mappedBounds = {}
        if selectedWorld and Worlds[selectedWorld] then
            for _, b in pairs(Worlds[selectedWorld]) do
                mappedBounds[string.format("%.1f", b)] = true
            end
        end

        for key, count in pairs(ScannedEnemies) do
            if not mappedBounds[key] then
                hasItems = true
                local label = "? b=" .. key .. " x" .. count
                local bval = tonumber(key)
                makeSideItem(label, function()
                    selectedEnemy = label
                    selectedBounds = bval
                    enemyBtn.Text = label
                    closeSide()
                end)
            end
        end

        if not hasItems then
            makeSideItem("No enemies found", function() closeSide() end)
        end
    end)
end)

-- Auto Farm toggle
farmBtn.MouseButton1Click:Connect(function()
    if not selectedBounds then return end
    autoFarm = not autoFarm
    if autoFarm then
        gauntletFarm = false
        gauntletBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        gauntletBtn.Text = "Gauntlet: OFF"
    end
    farmBtn.BackgroundColor3 = autoFarm and Color3.fromRGB(50, 200, 50) or Color3.fromRGB(50, 50, 50)
    farmBtn.Text = autoFarm and "Auto Farm: ON" or "Auto Farm: OFF"
end)

-- Gauntlet Farm toggle
gauntletBtn.MouseButton1Click:Connect(function()
    gauntletFarm = not gauntletFarm
    if gauntletFarm then
        autoFarm = false
        farmBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        farmBtn.Text = "Auto Farm: OFF"
    end
    gauntletBtn.BackgroundColor3 = gauntletFarm and Color3.fromRGB(50, 200, 50) or Color3.fromRGB(50, 50, 50)
    gauntletBtn.Text = gauntletFarm and "Gauntlet: ON" or "Gauntlet: OFF"
end)

-- Scan monitor (triggers on join, distance travel, and teleport detection)
task.spawn(function()
    local lastPos = nil
    while true do
        task.wait(2)
        local char = player.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            local pos = char.HumanoidRootPart.Position
            if lastPos then
                local delta = (pos - lastPos).Magnitude
                local scanDist = lastScanPos and (pos - lastScanPos).Magnitude or math.huge
                if delta > TELEPORT_DETECT or scanDist > SCAN_THRESHOLD then
                    scanWorkspace()
                end
            else
                scanWorkspace()
            end
            lastPos = pos
        end
    end
end)

-- Farm loop
task.spawn(function()
    while true do
        task.wait(0.1)
        local char = player.Character
        if not char or not char:FindFirstChild("HumanoidRootPart") then continue end
        local enemy = nil
        if gauntletFarm then
            enemy = getNearestAlive()
        elseif autoFarm and selectedBounds then
            enemy = getNearestOfType(selectedBounds)
        end
        if enemy then
            local hrp = enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChildOfClass("BasePart")
            if hrp then
                local dist = (char.HumanoidRootPart.Position - hrp.Position).Magnitude
                if dist > TELEPORT_RANGE then
                    char.HumanoidRootPart.CFrame = hrp.CFrame * CFrame.new(0, 0, 3)
                end
            end
        end
    end
end)
