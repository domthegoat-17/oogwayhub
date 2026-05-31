local Players = game:GetService("Players")
local player = Players.LocalPlayer
local autoFarm = false
local selectedEnemy = nil
local selectedBounds = nil
local TELEPORT_RANGE = 6

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

local sg = Instance.new("ScreenGui", player.PlayerGui)
sg.Name = "OogwayHub"

local main = Instance.new("Frame", sg)
main.Size = UDim2.new(0, 200, 0, 220)
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
game:GetService("UserInputService").InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        local newX = startPos.X.Offset + delta.X
        local newY = startPos.Y.Offset + delta.Y
        main.Position = UDim2.new(0, newX, 0, newY)
        if sidePanel.Visible and activeBtn then
            local absPos = activeBtn.AbsolutePosition
            local absSize = activeBtn.AbsoluteSize
            sidePanel.Position = UDim2.new(0, absPos.X + absSize.X + 8, 0, absPos.Y)
        end
    end
end)

-- Title
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

local function makeMainBtn(text, y)
    local btn = Instance.new("TextButton", main)
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

local activeBtn = nil

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

-- World
local worldLabel = Instance.new("TextLabel", main)
worldLabel.Size = UDim2.new(1, -20, 0, 18)
worldLabel.Position = UDim2.new(0, 10, 0, 38)
worldLabel.BackgroundTransparency = 1
worldLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
worldLabel.Font = Enum.Font.Gotham
worldLabel.TextSize = 10
worldLabel.TextXAlignment = Enum.TextXAlignment.Left
worldLabel.Text = "WORLD"

local worldBtn = makeMainBtn("Select World", 58)
local selectedWorld = nil

-- Enemy
local enemyLabel = Instance.new("TextLabel", main)
enemyLabel.Size = UDim2.new(1, -20, 0, 18)
enemyLabel.Position = UDim2.new(0, 10, 0, 98)
enemyLabel.BackgroundTransparency = 1
enemyLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
enemyLabel.Font = Enum.Font.Gotham
enemyLabel.TextSize = 10
enemyLabel.TextXAlignment = Enum.TextXAlignment.Left
enemyLabel.Text = "ENEMY"

local enemyBtn = makeMainBtn("Select Enemy", 118)

-- Farm
local farmBtn = Instance.new("TextButton", main)
farmBtn.Size = UDim2.new(1, -20, 0, 34)
farmBtn.Position = UDim2.new(0, 10, 0, 170)
farmBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
farmBtn.TextColor3 = Color3.new(1, 1, 1)
farmBtn.Font = Enum.Font.GothamBold
farmBtn.TextSize = 13
farmBtn.Text = "Auto Farm: OFF"
farmBtn.BorderSizePixel = 0
Instance.new("UICorner", farmBtn).CornerRadius = UDim.new(0, 6)

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

enemyBtn.MouseButton1Click:Connect(function()
    if not selectedWorld then return end
    openSide(enemyBtn, function()
        local enemies = Worlds[selectedWorld]
        if not enemies or not next(enemies) then
            makeSideItem("No data yet", function() closeSide() end)
            return
        end
        for name, bounds in pairs(enemies) do
            makeSideItem(name, function()
                selectedEnemy = name
                selectedBounds = bounds
                enemyBtn.Text = name
                closeSide()
            end)
        end
    end)
end)

farmBtn.MouseButton1Click:Connect(function()
    if not selectedBounds then return end
    autoFarm = not autoFarm
    farmBtn.BackgroundColor3 = autoFarm and Color3.fromRGB(50, 200, 50) or Color3.fromRGB(50, 50, 50)
    farmBtn.Text = autoFarm and "Auto Farm: ON" or "Auto Farm: OFF"
end)

task.spawn(function()
    while true do
        task.wait(0.1)
        if autoFarm and selectedBounds then
            local enemy = getNearestOfType(selectedBounds)
            local char = player.Character
            if enemy and char and char:FindFirstChild("HumanoidRootPart") then
                local hrp = enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChildOfClass("BasePart")
                if hrp then
                    local dist = (char.HumanoidRootPart.Position - hrp.Position).Magnitude
                    if dist > TELEPORT_RANGE then
                        char.HumanoidRootPart.CFrame = hrp.CFrame * CFrame.new(0, 0, 3)
                    end
                end
            end
        end
    end
end)
