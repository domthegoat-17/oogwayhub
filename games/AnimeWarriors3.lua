local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

local TELEPORT_RANGE = 6
local SCAN_THRESHOLD = 200
local TELEPORT_DETECT = 50
local MAX_DUMMY_HP = 1e8       -- skip invincible/infinite-HP targets like DPS dummies
local STUCK_TIMEOUT = 8        -- seconds on the same target before blacklisting it
local BLACKLIST_DURATION = 30  -- seconds a stuck target stays blacklisted

local autoFarm = false
local gauntletFarm = false
local selectedEnemy = nil
local selectedBounds = nil
local selectedWorld = nil
local currentWorld = nil
local ScannedEnemies = {}
local ScannedUUIDs = {}
local lastScanPos = nil
local gauntletBlacklist = {}   -- { [obj] = os.clock() expiry }
local gauntletLastTarget = nil
local gauntletStuckTime = 0
local idVisible = false

local Worlds = {
    ["Rain Village"] = {
        ["Spirit"]        = 4,
        ["Instinct"]      = 5.4,
        ["Enlightenment"] = 7,
        ["Demon"]         = 9,
        ["Paper Angel"]   = 18,
        ["Deva"]          = 24,
    },
    ["Future City"] = {
        ["Cel Jr."]     = "2b5b33dd-69a2-4ab0-926c-76cafa855c19",
        ["Android 19"]  = "90cf9d6e-bfa9-4dfe-a2b8-7aa4cdcadb73",
        ["Android 20"]  = "21f84a85-3e33-46ca-949d-e69b06dc7d4f",
        ["Android 18"]  = "53b3c930-cafd-490c-82ad-dfd8f84082c8",
        ["Android 17"]  = "f849d5b6-02ce-41f4-ae51-c349e8ffa4e3",
        ["Cel (Prime)"] = "a388224a-7aa9-438e-94c6-6391a0045388",
    },
    ["Sand Village"] = {},
    ["Sky Island"]   = {},
    ["Planet Nemak"] = {},
}

local function isUUID(name)
    return string.match(name, "^%x+%-%x+%-%x+%-%x+%-%x+$") ~= nil
end

-- Normalise a Worlds entry (number OR array of numbers) into a flat array.
-- Allows entries like {5.0, 8.8} to group size-variant enemies (Giant, Tiny, etc.)
-- under one name without changing how single-value entries work.
local function toBoundsArray(v)
    if type(v) == "number" then return {v} end
    if type(v) == "table"  then return v   end
    return {}
end

local function boundsMatches(b, target)
    for _, v in ipairs(toBoundsArray(target)) do
        if math.abs(b - v) < 1 then return true end
    end
    return false
end

-- markerText patterns per world for waystone NPC detection
local WorldMarkers = {
    ["Rain Village"] = { "Rain", "Rosha" },
    ["Future City"]  = { "Future", "Trunko" },
    ["Sand Village"] = { "Sand" },
    ["Sky Island"]   = { "Sky" },
    ["Planet Nemak"] = { "Nemak" },
}

local function isKnownBounds(b)
    for _, enemies in pairs(Worlds) do
        for _, entry in pairs(enemies) do
            if type(entry) ~= "string" and boundsMatches(b, entry) then return true end
        end
    end
    return false
end

local function isKnownUUID(name)
    for _, enemies in pairs(Worlds) do
        for _, entry in pairs(enemies) do
            if entry == name then return true end
        end
    end
    return false
end

local function getBoundsFirst(obj)
    local bounds = obj:GetAttribute("bounds")
    if not bounds then return 0 end
    return tonumber(tostring(bounds):match("^([%d%.]+)")) or 0
end

local function enemyMatches(obj, target)
    if type(target) == "string" then return obj.Name == target end
    return boundsMatches(getBoundsFirst(obj), target)
end

local function isEnemyModel(obj)
    if not obj:IsA("Model") then return false end
    return getBoundsFirst(obj) > 0
end

-- Picks the alive enemy matching targetBounds with the lowest MaxHealth (basic over boss).
-- Falls back to nearest distance when MaxHealth is unavailable.
local function getWeakestOfType(target)
    local char = player.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end
    local root = char.HumanoidRootPart
    local best, bestScore = nil, math.huge
    for _, obj in pairs(workspace:GetDescendants()) do
        if isEnemyModel(obj) then
            local dead = obj:GetAttribute("dead")
            local hrp = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChildOfClass("BasePart")
            if dead ~= true and hrp then
                if enemyMatches(obj, target) then
                    local humanoid = obj:FindFirstChildOfClass("Humanoid")
                    local score = humanoid and humanoid.MaxHealth
                        or (hrp.Position - root.Position).Magnitude
                    if score < bestScore then
                        best = obj
                        bestScore = score
                    end
                end
            end
        end
    end
    return best
end

local function getNearestAlive()
    local char = player.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end
    local root = char.HumanoidRootPart
    local nearest, nearestDist = nil, math.huge
    for _, obj in pairs(workspace:GetDescendants()) do
        if isEnemyModel(obj) and not gauntletBlacklist[obj] then
            local dead = obj:GetAttribute("dead")
            local hrp = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChildOfClass("BasePart")
            if dead ~= true and hrp then
                local humanoid = obj:FindFirstChildOfClass("Humanoid")
                if humanoid and humanoid.MaxHealth >= MAX_DUMMY_HP then continue end
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
    local foundUUIDs = {}
    for _, obj in pairs(workspace:GetDescendants()) do
        if isEnemyModel(obj) then
            local dead = obj:GetAttribute("dead")
            if dead ~= true then
                local b = getBoundsFirst(obj)
                local key = string.format("%.1f", b)
                found[key] = (found[key] or 0) + 1
                foundUUIDs[obj.Name] = true
            end
        end
    end
    ScannedEnemies = found
    ScannedUUIDs = foundUUIDs
    local char = player.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        lastScanPos = char.HumanoidRootPart.Position
    end
end

-- GUI
local guiParent
if typeof(gethui) == "function" then
    guiParent = gethui()
else
    local ok, cg = pcall(game.GetService, game, "CoreGui")
    guiParent = ok and cg or player.PlayerGui
end

local sg = Instance.new("ScreenGui")
sg.Name = "OogwayHub"
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent = guiParent

local main = Instance.new("Frame", sg)
main.Size = UDim2.new(0, 200, 0, 260)
main.Position = UDim2.new(0, 20, 0.3, 0)
main.BackgroundColor3 = Color3.fromRGB(10, 18, 10)
main.BorderSizePixel = 0
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)

local sidePanel = Instance.new("Frame", sg)
sidePanel.Size = UDim2.new(0, 160, 0, 0)
sidePanel.BackgroundColor3 = Color3.fromRGB(12, 22, 12)
sidePanel.BorderSizePixel = 0
sidePanel.ClipsDescendants = true
sidePanel.Visible = false
Instance.new("UICorner", sidePanel).CornerRadius = UDim.new(0, 8)
Instance.new("UIListLayout", sidePanel).SortOrder = Enum.SortOrder.LayoutOrder

-- Identifier overlay (bottom-left, toggled by ID button)
local idOverlay = Instance.new("Frame", sg)
idOverlay.Size = UDim2.new(0, 600, 0, 160)
idOverlay.Position = UDim2.new(0, 10, 1, -175)
idOverlay.BackgroundColor3 = Color3.fromRGB(8, 15, 8)
idOverlay.BackgroundTransparency = 0.1
idOverlay.BorderSizePixel = 0
idOverlay.Visible = false
Instance.new("UICorner", idOverlay).CornerRadius = UDim.new(0, 8)

local idHeader = Instance.new("TextLabel", idOverlay)
idHeader.Size = UDim2.new(1, -16, 0, 32)
idHeader.Position = UDim2.new(0, 12, 0, 8)
idHeader.BackgroundTransparency = 1
idHeader.TextColor3 = Color3.fromRGB(50, 255, 80)
idHeader.Font = Enum.Font.GothamBold
idHeader.TextSize = 18
idHeader.TextXAlignment = Enum.TextXAlignment.Left
idHeader.Text = "IDENTIFIER — nearest enemy"

local idBoundsLabel = Instance.new("TextLabel", idOverlay)
idBoundsLabel.Size = UDim2.new(1, -16, 0, 30)
idBoundsLabel.Position = UDim2.new(0, 12, 0, 42)
idBoundsLabel.BackgroundTransparency = 1
idBoundsLabel.TextColor3 = Color3.new(1, 1, 1)
idBoundsLabel.Font = Enum.Font.Gotham
idBoundsLabel.TextSize = 18
idBoundsLabel.TextXAlignment = Enum.TextXAlignment.Left
idBoundsLabel.Text = "bounds:  —"

local idNameLabel = Instance.new("TextLabel", idOverlay)
idNameLabel.Size = UDim2.new(1, -16, 0, 30)
idNameLabel.Position = UDim2.new(0, 12, 0, 74)
idNameLabel.BackgroundTransparency = 1
idNameLabel.TextColor3 = Color3.new(1, 1, 1)
idNameLabel.Font = Enum.Font.Gotham
idNameLabel.TextSize = 18
idNameLabel.TextXAlignment = Enum.TextXAlignment.Left
idNameLabel.Text = "name:     —"

local idCountLabel = Instance.new("TextLabel", idOverlay)
idCountLabel.Size = UDim2.new(1, -16, 0, 30)
idCountLabel.Position = UDim2.new(0, 12, 0, 116)
idCountLabel.BackgroundTransparency = 1
idCountLabel.TextColor3 = Color3.fromRGB(220, 80, 80)
idCountLabel.Font = Enum.Font.Gotham
idCountLabel.TextSize = 18
idCountLabel.TextXAlignment = Enum.TextXAlignment.Left
idCountLabel.Text = "on map:  0"

local activeBtn = nil

-- Drag
local dragging = false
local dragPrev = nil
main.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragPrev = Vector2.new(input.Position.X, input.Position.Y)
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
                dragPrev = nil
            end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and dragPrev and input.UserInputType == Enum.UserInputType.MouseMovement then
        local dx = input.Position.X - dragPrev.X
        local dy = input.Position.Y - dragPrev.Y
        dragPrev = Vector2.new(input.Position.X, input.Position.Y)
        main.Position = UDim2.new(
            main.Position.X.Scale, main.Position.X.Offset + dx,
            main.Position.Y.Scale, main.Position.Y.Offset + dy
        )
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
titleBar.BackgroundColor3 = Color3.fromRGB(5, 10, 5)
titleBar.BorderSizePixel = 0
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel", titleBar)
title.Size = UDim2.new(1, -76, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "OogwayHub 2"

local idBtn = Instance.new("TextButton", titleBar)
idBtn.Size = UDim2.new(0, 26, 0, 22)
idBtn.Position = UDim2.new(1, -62, 0, 5)
idBtn.BackgroundColor3 = Color3.fromRGB(20, 140, 20)
idBtn.TextColor3 = Color3.new(1, 1, 1)
idBtn.Font = Enum.Font.GothamBold
idBtn.TextSize = 11
idBtn.Text = "ID"
idBtn.BorderSizePixel = 0
Instance.new("UICorner", idBtn).CornerRadius = UDim.new(0, 4)

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
farmTabBtn.BackgroundColor3 = Color3.fromRGB(30, 180, 30)
farmTabBtn.TextColor3 = Color3.new(1, 1, 1)
farmTabBtn.Font = Enum.Font.GothamBold
farmTabBtn.TextSize = 12
farmTabBtn.Text = "FARM"
farmTabBtn.BorderSizePixel = 0

local gauntletTabBtn = Instance.new("TextButton", main)
gauntletTabBtn.Size = UDim2.new(0.5, 0, 0, 30)
gauntletTabBtn.Position = UDim2.new(0.5, 0, 0, 32)
gauntletTabBtn.BackgroundColor3 = Color3.fromRGB(18, 35, 18)
gauntletTabBtn.TextColor3 = Color3.new(1, 1, 1)
gauntletTabBtn.Font = Enum.Font.GothamBold
gauntletTabBtn.TextSize = 12
gauntletTabBtn.Text = "GAUNTLET"
gauntletTabBtn.BorderSizePixel = 0

local tabDiv = Instance.new("Frame", main)
tabDiv.Size = UDim2.new(1, 0, 0, 1)
tabDiv.Position = UDim2.new(0, 0, 0, 62)
tabDiv.BackgroundColor3 = Color3.fromRGB(14, 28, 14)
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
    btn.BackgroundColor3 = Color3.fromRGB(18, 35, 18)
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
    arrow.TextColor3 = Color3.fromRGB(80, 180, 80)
    arrow.Font = Enum.Font.GothamBold
    arrow.TextSize = 12
    arrow.Text = "▶"
    return btn
end

local function makeSideItem(text, onClick)
    local btn = Instance.new("TextButton", sidePanel)
    btn.Size = UDim2.new(1, 0, 0, 32)
    btn.BackgroundColor3 = Color3.fromRGB(18, 35, 18)
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
        activeBtn.BackgroundColor3 = Color3.fromRGB(18, 35, 18)
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
    btn.BackgroundColor3 = Color3.fromRGB(30, 180, 30)
    local arrow = btn:FindFirstChild("Arrow")
    if arrow then arrow.Text = "▼" end
end

-- Farm tab content
local worldLabel = Instance.new("TextLabel", farmContent)
worldLabel.Size = UDim2.new(1, -20, 0, 18)
worldLabel.Position = UDim2.new(0, 10, 0, 8)
worldLabel.BackgroundTransparency = 1
worldLabel.TextColor3 = Color3.fromRGB(80, 180, 80)
worldLabel.Font = Enum.Font.Gotham
worldLabel.TextSize = 10
worldLabel.TextXAlignment = Enum.TextXAlignment.Left
worldLabel.Text = "WORLD"

local worldBtn = makeMainBtn(farmContent, "Select World", 26)

local enemyLabel = Instance.new("TextLabel", farmContent)
enemyLabel.Size = UDim2.new(1, -20, 0, 18)
enemyLabel.Position = UDim2.new(0, 10, 0, 66)
enemyLabel.BackgroundTransparency = 1
enemyLabel.TextColor3 = Color3.fromRGB(80, 180, 80)
enemyLabel.Font = Enum.Font.Gotham
enemyLabel.TextSize = 10
enemyLabel.TextXAlignment = Enum.TextXAlignment.Left
enemyLabel.Text = "ENEMY"

local enemyBtn = makeMainBtn(farmContent, "Select Enemy", 84)

local farmBtn = Instance.new("TextButton", farmContent)
farmBtn.Size = UDim2.new(1, -20, 0, 34)
farmBtn.Position = UDim2.new(0, 10, 0, 128)
farmBtn.BackgroundColor3 = Color3.fromRGB(14, 28, 14)
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
gauntletInfo.TextColor3 = Color3.fromRGB(80, 180, 80)
gauntletInfo.Font = Enum.Font.Gotham
gauntletInfo.TextSize = 11
gauntletInfo.TextXAlignment = Enum.TextXAlignment.Left
gauntletInfo.TextWrapped = true
gauntletInfo.Text = "Targets all alive enemies.\nNo selection needed.\nGood for Gauntlet floors."

local gauntletBtn = Instance.new("TextButton", gauntletContent)
gauntletBtn.Size = UDim2.new(1, -20, 0, 34)
gauntletBtn.Position = UDim2.new(0, 10, 0, 78)
gauntletBtn.BackgroundColor3 = Color3.fromRGB(14, 28, 14)
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
    farmTabBtn.BackgroundColor3 = tab == "farm" and Color3.fromRGB(30, 180, 30) or Color3.fromRGB(18, 35, 18)
    gauntletTabBtn.BackgroundColor3 = tab == "gauntlet" and Color3.fromRGB(30, 180, 30) or Color3.fromRGB(18, 35, 18)
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
                ScannedEnemies = {}
                lastScanPos = nil
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
            for _, entry in pairs(Worlds[selectedWorld]) do
                for _, v in ipairs(toBoundsArray(entry)) do
                    mappedBounds[string.format("%.1f", v)] = true
                end
            end
        end

        -- Group unknown enemies by model name (UUID) so size variants (Giant/Tiny) collapse into one entry
        local nameGroups = {}
        for _, obj in pairs(workspace:GetDescendants()) do
            if isEnemyModel(obj) and obj:GetAttribute("dead") ~= true then
                local b = getBoundsFirst(obj)
                local key = string.format("%.1f", b)
                local n = obj.Name
                if not mappedBounds[key] and not isKnownBounds(b) and not isKnownUUID(n) then
                    if not nameGroups[n] then
                        nameGroups[n] = { boundsSet = {}, boundsArr = {}, count = 0 }
                    end
                    nameGroups[n].count += 1
                    if not nameGroups[n].boundsSet[key] then
                        nameGroups[n].boundsSet[key] = true
                        table.insert(nameGroups[n].boundsArr, b)
                    end
                end
            end
        end

        for _, group in pairs(nameGroups) do
            hasItems = true
            local parts = {}
            for _, v in ipairs(group.boundsArr) do
                table.insert(parts, string.format("%.1f", v))
            end
            local label = "? b=" .. table.concat(parts, "/") .. " x" .. group.count
            local boundsCapture = group.boundsArr
            makeSideItem(label, function()
                selectedEnemy = label
                selectedBounds = #boundsCapture == 1 and boundsCapture[1] or boundsCapture
                enemyBtn.Text = label
                closeSide()
            end)
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
        gauntletBtn.BackgroundColor3 = Color3.fromRGB(14, 28, 14)
        gauntletBtn.Text = "Gauntlet: OFF"
    end
    farmBtn.BackgroundColor3 = autoFarm and Color3.fromRGB(50, 200, 50) or Color3.fromRGB(14, 28, 14)
    farmBtn.Text = autoFarm and "Auto Farm: ON" or "Auto Farm: OFF"
end)

-- Gauntlet Farm toggle
gauntletBtn.MouseButton1Click:Connect(function()
    gauntletFarm = not gauntletFarm
    if gauntletFarm then
        autoFarm = false
        farmBtn.BackgroundColor3 = Color3.fromRGB(14, 28, 14)
        farmBtn.Text = "Auto Farm: OFF"
    end
    gauntletBtn.BackgroundColor3 = gauntletFarm and Color3.fromRGB(50, 200, 50) or Color3.fromRGB(14, 28, 14)
    gauntletBtn.Text = gauntletFarm and "Gauntlet: ON" or "Gauntlet: OFF"
end)

local function detectCurrentWorld()
    for _, obj in pairs(workspace:GetDescendants()) do
        local markerText = obj:GetAttribute("markerText")
        if markerText then
            markerText = tostring(markerText)
            for worldName, patterns in pairs(WorldMarkers) do
                for _, pattern in ipairs(patterns) do
                    if string.find(markerText, pattern, 1, true) then
                        currentWorld = worldName
                        return
                    end
                end
            end
        end
        if obj.Name == "RoshaWaystone" then
            currentWorld = "Rain Village"
            return
        end
    end
    currentWorld = nil
end

local function detectWorld()
    local bestWorld, bestScore = nil, 0
    for worldName, enemies in pairs(Worlds) do
        if next(enemies) then
            local score = 0
            for _, entry in pairs(enemies) do
                local matched = false
                if type(entry) == "string" then
                    matched = ScannedUUIDs[entry] == true
                else
                    for _, knownB in ipairs(toBoundsArray(entry)) do
                        for key in pairs(ScannedEnemies) do
                            if math.abs((tonumber(key) or 0) - knownB) <= 1 then
                                matched = true
                                break
                            end
                        end
                        if matched then break end
                    end
                end
                if matched then score += 1 end
            end
            if score > bestScore then
                bestScore = score
                bestWorld = worldName
            end
        end
    end
    if bestWorld and bestScore >= 2 then
        selectedWorld = bestWorld
        worldBtn.Text = bestWorld
    end
end

-- Scan monitor (triggers on join, distance travel, and teleport detection)
task.spawn(function()
    local lastPos = nil
    while true do
        task.wait(2)
        local char = player.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            local pos = char.HumanoidRootPart.Position
            local shouldScan = false
            if lastPos then
                local delta = (pos - lastPos).Magnitude
                local scanDist = lastScanPos and (pos - lastScanPos).Magnitude or math.huge
                if delta > TELEPORT_DETECT or scanDist > SCAN_THRESHOLD then
                    shouldScan = true
                end
            else
                shouldScan = true
            end
            if shouldScan then
                scanWorkspace()
                detectCurrentWorld()
                if not selectedWorld then
                    detectWorld()
                end
            end
            lastPos = pos
        end
    end
end)

-- Re-detect world on character respawn
local function onCharacterAdded()
    task.wait(3)
    detectCurrentWorld()
end
player.CharacterAdded:Connect(onCharacterAdded)

-- Farm loop
task.spawn(function()
    while true do
        task.wait(0.1)
        local char = player.Character
        if not char or not char:FindFirstChild("HumanoidRootPart") then continue end
        local enemy = nil
        if gauntletFarm then
            -- Expire blacklist entries
            local now = os.clock()
            for obj, expiry in pairs(gauntletBlacklist) do
                if now >= expiry then gauntletBlacklist[obj] = nil end
            end
            enemy = getNearestAlive()
            if enemy then
                if enemy == gauntletLastTarget then
                    gauntletStuckTime += 0.1
                    if gauntletStuckTime >= STUCK_TIMEOUT then
                        gauntletBlacklist[enemy] = os.clock() + BLACKLIST_DURATION
                        gauntletLastTarget = nil
                        gauntletStuckTime = 0
                        enemy = nil
                    end
                else
                    gauntletLastTarget = enemy
                    gauntletStuckTime = 0
                end
            else
                gauntletLastTarget = nil
                gauntletStuckTime = 0
            end
        elseif autoFarm and selectedBounds then
            local worldOk = currentWorld == nil or currentWorld == selectedWorld
            if worldOk then
                enemy = getWeakestOfType(selectedBounds)
            end
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

-- ID button toggle
idBtn.MouseButton1Click:Connect(function()
    idVisible = not idVisible
    idOverlay.Visible = idVisible
    idBtn.BackgroundColor3 = idVisible
        and Color3.fromRGB(50, 220, 50)
        or  Color3.fromRGB(20, 140, 20)
end)

-- Identifier overlay update loop
task.spawn(function()
    while true do
        task.wait(0.25)
        if not idVisible then continue end
        local char = player.Character
        if not char or not char:FindFirstChild("HumanoidRootPart") then continue end
        local root = char.HumanoidRootPart

        local nearest, nearestDist = nil, math.huge
        for _, obj in pairs(workspace:GetDescendants()) do
            if isEnemyModel(obj) then
                local dead = obj:GetAttribute("dead")
                local hrp = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChildOfClass("BasePart")
                if dead ~= true and hrp then
                    local dist = (hrp.Position - root.Position).Magnitude
                    if dist < nearestDist then
                        nearest = obj
                        nearestDist = dist
                    end
                end
            end
        end

        if nearest then
            local b = getBoundsFirst(nearest)
            local nameStr = nearest.Name
            local count = 0
            for _, obj in pairs(workspace:GetDescendants()) do
                if isEnemyModel(obj) and math.abs(getBoundsFirst(obj) - b) < 1 then
                    count += 1
                end
            end
            idBoundsLabel.Text = "bounds:  " .. string.format("%.1f", b)
            idNameLabel.Text   = "name:     " .. nameStr
            idCountLabel.Text  = "on map:  " .. count
        else
            idBoundsLabel.Text = "bounds:  —"
            idNameLabel.Text   = "name:     —"
            idCountLabel.Text  = "on map:  0"
        end
    end
end)
