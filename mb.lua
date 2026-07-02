-- ============================================================
-- Bee Suite: Unified GUI (rebindable keys + named walker configs)
-- ============================================================

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local HttpService = game:GetService("HttpService")
local VIM = game:GetService("VirtualInputManager")

-- Wait for player
local player = Players.LocalPlayer
while not player do
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    player = Players.LocalPlayer
end
local playerGui = player:WaitForChild("PlayerGui")
if not player.Character then player.CharacterAdded:Wait() end
task.wait(1)

-- ============================================================
-- CONFIGS (with save/load)
-- ============================================================
local CONFIG_FILE = "beesuite_cfg_" .. game.PlaceId .. ".json"
local WALKER_CONFIGS_FILE = "beesuite_walkercfgs_" .. game.PlaceId .. ".json"

local WalkerCfg = {
    SmoothFactor = 0.25,
    LookaheadDist = 6,
    ArriveDist = 4,
    WaypointTimeout = 8,
    DestJitter = 4,
    MicroJitter = 0.05,
    TickMin = 0.045,
    TickMax = 0.075,
    PauseBetweenMin = 0.2,
    PauseBetweenMax = 0.6,
    ShortPauseChance = 0.03,
    LongIdleChance = 0.01,
    RouteBreakMin = 2,
    RouteBreakMax = 5,
}

local UtilsCfg = { ResetInterval = 90 }

local Keybinds = {
    SetPoint = "K",
    ToggleWalk = "Q",
    DeleteAll = "L",
    ToggleESP = "F",
    ToggleReset = "R",
    ToggleHold = "M",
}

local function saveConfigs()
    local data = { walker = WalkerCfg, utils = UtilsCfg, keys = Keybinds }
    pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(data)) end)
end

local function loadConfigs()
    if isfile and isfile(CONFIG_FILE) then
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(CONFIG_FILE)) end)
        if ok and data then
            if data.walker then for k, v in pairs(data.walker) do WalkerCfg[k] = v end end
            if data.utils then for k, v in pairs(data.utils) do UtilsCfg[k] = v end end
            if data.keys then for k, v in pairs(data.keys) do Keybinds[k] = v end end
        end
    end
end
loadConfigs()

-- ============================================================
-- WALKER CONFIGS (named routes)
-- ============================================================
-- Structure: { ["Config Name"] = {points = {{x,y,z}, ...}, walker = {...settings...}}, ...}
local WalkerConfigs = {}
local currentConfigName = nil -- currently loaded config

local function saveWalkerConfigs()
    pcall(function() writefile(WALKER_CONFIGS_FILE, HttpService:JSONEncode(WalkerConfigs)) end)
end

local function loadWalkerConfigs()
    if isfile and isfile(WALKER_CONFIGS_FILE) then
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(WALKER_CONFIGS_FILE)) end)
        if ok and data then WalkerConfigs = data end
    end
end
loadWalkerConfigs()

-- ============================================================
-- SHARED: ControlModule hook
-- ============================================================
local PlayerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
local ControlModule = PlayerModule:GetControls()

local moveConn

local function StopMove()
    if moveConn then moveConn:Disconnect() moveConn = nil end
    local ac = ControlModule.activeController
    if ac then
        ac.moveVector = Vector3.new(0, 0, 0)
        ac.forwardValue = 0; ac.backwardValue = 0; ac.leftValue = 0; ac.rightValue = 0
    end
    ControlModule.inputMoveVector = Vector3.new(0, 0, 0)
end

player.CharacterAdded:Connect(function()
    task.wait(1)
    PlayerModule = require(player.PlayerScripts:WaitForChild("PlayerModule"))
    ControlModule = PlayerModule:GetControls()
end)

local function getRoot()
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

-- ============================================================
-- GUI
-- ============================================================
local gui = Instance.new("ScreenGui")
gui.Name = "BeeSuite"
gui.ResetOnSpawn = false
pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = playerGui end

local FULL_HEIGHT = 500
local MIN_HEIGHT = 32

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 320, 0, FULL_HEIGHT)
frame.Position = UDim2.new(0.02, 0, 0.12, 0)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
frame.BorderSizePixel = 0
frame.Active = true
frame.ClipsDescendants = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 32)
titleBar.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
titleBar.BorderSizePixel = 0
titleBar.Parent = frame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -35, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "🐝 Bee Suite"
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.Parent = titleBar

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 32, 1, 0)
minBtn.Position = UDim2.new(1, -32, 0, 0)
minBtn.BackgroundTransparency = 1
minBtn.Text = "—"
minBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 16
minBtn.Parent = titleBar

local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    frame.Size = UDim2.new(0, 320, 0, minimized and MIN_HEIGHT or FULL_HEIGHT)
    minBtn.Text = minimized and "+" or "—"
end)

local dragging, dragStart, startPos
titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true; dragStart = input.Position; startPos = frame.Position
    end
end)
UIS.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)
UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)

-- ============================================================
-- TAB SYSTEM
-- ============================================================
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -10, 0, 28)
tabBar.Position = UDim2.new(0, 5, 0, 36)
tabBar.BackgroundTransparency = 1
tabBar.Parent = frame

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 4)
tabLayout.Parent = tabBar

local tabPages = {}
local tabButtons = {}

local function switchTab(name)
    for n, page in pairs(tabPages) do page.Visible = (n == name) end
    for n, btn in pairs(tabButtons) do
        btn.BackgroundColor3 = (n == name) and Color3.fromRGB(60, 120, 200) or Color3.fromRGB(45, 45, 55)
    end
end

local function createTab(name, width)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, width or 65, 1, 0)
    btn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    btn.BorderSizePixel = 0
    btn.Text = name
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.Parent = tabBar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    local page = Instance.new("ScrollingFrame")
    page.Size = UDim2.new(1, -10, 1, -75)
    page.Position = UDim2.new(0, 5, 0, 70)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 4
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = false
    page.Parent = frame

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 4)
    layout.Parent = page

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 4)
    padding.PaddingBottom = UDim.new(0, 4)
    padding.Parent = page

    btn.MouseButton1Click:Connect(function() switchTab(name) end)
    tabPages[name] = page
    tabButtons[name] = btn
    return page
end

-- Widgets
local function makeLabel(parent, text, color)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 20)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = color or Color3.fromRGB(200, 200, 200)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = parent
    return lbl
end

local function makeButton(parent, text, color, onClick, height)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, height or 28)
    btn.BackgroundColor3 = color
    btn.BorderSizePixel = 0
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    if onClick then btn.MouseButton1Click:Connect(onClick) end
    return btn
end

local function makeSectionHeader(parent, text)
    local hdr = Instance.new("TextLabel")
    hdr.Size = UDim2.new(1, 0, 0, 24)
    hdr.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
    hdr.BorderSizePixel = 0
    hdr.Text = "  " .. text
    hdr.TextXAlignment = Enum.TextXAlignment.Left
    hdr.TextColor3 = Color3.fromRGB(255, 255, 255)
    hdr.Font = Enum.Font.GothamBold
    hdr.TextSize = 12
    hdr.Parent = parent
    Instance.new("UICorner", hdr).CornerRadius = UDim.new(0, 4)
    return hdr
end

local function makeConfigField(parent, labelText, cfgTable, cfgKey)
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 24)
    container.BackgroundTransparency = 1
    container.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.6, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = "  " .. labelText
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextColor3 = Color3.fromRGB(200, 200, 200)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 11
    lbl.Parent = container

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0.4, -5, 1, -4)
    box.Position = UDim2.new(0.6, 0, 0, 2)
    box.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    box.BorderSizePixel = 0
    box.Text = tostring(cfgTable[cfgKey])
    box.TextColor3 = Color3.fromRGB(255, 255, 255)
    box.Font = Enum.Font.Gotham
    box.TextSize = 11
    box.ClearTextOnFocus = false
    box.Parent = container
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)

    box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        if n then
            cfgTable[cfgKey] = n
            box.Text = tostring(n)
            saveConfigs()
        else
            box.Text = tostring(cfgTable[cfgKey])
        end
    end)
    return box
end

local waitingForKey = nil
local function makeKeybindRow(parent, labelText, keyName)
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 26)
    container.BackgroundTransparency = 1
    container.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.6, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = "  " .. labelText
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextColor3 = Color3.fromRGB(200, 200, 200)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 11
    lbl.Parent = container

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.4, -5, 1, -4)
    btn.Position = UDim2.new(0.6, 0, 0, 2)
    btn.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
    btn.BorderSizePixel = 0
    btn.Text = "[ " .. Keybinds[keyName] .. " ]"
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.Parent = container
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

    btn.MouseButton1Click:Connect(function()
        waitingForKey = { keyName = keyName, btn = btn }
        btn.Text = "[ Press key... ]"
        btn.BackgroundColor3 = Color3.fromRGB(200, 140, 40)
    end)
    return btn
end

UIS.InputBegan:Connect(function(input, gp)
    if waitingForKey and input.UserInputType == Enum.UserInputType.Keyboard then
        local keyStr = input.KeyCode.Name
        if keyStr and keyStr ~= "Unknown" then
            Keybinds[waitingForKey.keyName] = keyStr
            waitingForKey.btn.Text = "[ " .. keyStr .. " ]"
            waitingForKey.btn.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
            waitingForKey = nil
            saveConfigs()
        end
    end
end)

-- ============================================================
-- TAB: WALKER
-- ============================================================
local walkerTab = createTab("Walker")

local points = {}
local walking = false

local walkerStatus = makeLabel(walkerTab, "")
local currentCfgLabel = makeLabel(walkerTab, "Loaded config: <none>", Color3.fromRGB(180, 200, 255))

local setBtn = makeButton(walkerTab, "Set Point", Color3.fromRGB(60, 120, 200))
local walkBtn = makeButton(walkerTab, "Start Walking", Color3.fromRGB(60, 160, 80))
local delBtn = makeButton(walkerTab, "Delete All Points", Color3.fromRGB(190, 60, 60))

-- ==== NAMED CONFIGS SECTION ====
makeSectionHeader(walkerTab, "💾 Route Configs")

-- Input for new config name
local nameInputContainer = Instance.new("Frame")
nameInputContainer.Size = UDim2.new(1, 0, 0, 28)
nameInputContainer.BackgroundTransparency = 1
nameInputContainer.Parent = walkerTab

local nameInput = Instance.new("TextBox")
nameInput.Size = UDim2.new(0.65, -4, 1, 0)
nameInput.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
nameInput.BorderSizePixel = 0
nameInput.PlaceholderText = "Config name..."
nameInput.Text = ""
nameInput.TextColor3 = Color3.fromRGB(255, 255, 255)
nameInput.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
nameInput.Font = Enum.Font.Gotham
nameInput.TextSize = 12
nameInput.ClearTextOnFocus = false
nameInput.Parent = nameInputContainer
Instance.new("UICorner", nameInput).CornerRadius = UDim.new(0, 4)

local saveNewBtn = Instance.new("TextButton")
saveNewBtn.Size = UDim2.new(0.35, 0, 1, 0)
saveNewBtn.Position = UDim2.new(0.65, 4, 0, 0)
saveNewBtn.BackgroundColor3 = Color3.fromRGB(60, 160, 80)
saveNewBtn.BorderSizePixel = 0
saveNewBtn.Text = "Save New"
saveNewBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
saveNewBtn.Font = Enum.Font.GothamBold
saveNewBtn.TextSize = 11
saveNewBtn.Parent = nameInputContainer
Instance.new("UICorner", saveNewBtn).CornerRadius = UDim.new(0, 4)

-- Update current button (saves to current config name)
local updateBtn = makeButton(walkerTab, "Update Current Config", Color3.fromRGB(100, 140, 200), nil, 26)

-- Container for config list
local cfgListContainer = Instance.new("Frame")
cfgListContainer.Size = UDim2.new(1, 0, 0, 0)
cfgListContainer.AutomaticSize = Enum.AutomaticSize.Y
cfgListContainer.BackgroundTransparency = 1
cfgListContainer.Parent = walkerTab
local cfgListLayout = Instance.new("UIListLayout")
cfgListLayout.Padding = UDim.new(0, 3)
cfgListLayout.Parent = cfgListContainer

-- ==== MOVEMENT CONFIG ====
makeSectionHeader(walkerTab, "⚙ Movement Settings")
local cfgFields = {}
cfgFields.SmoothFactor = makeConfigField(walkerTab, "Smooth Factor", WalkerCfg, "SmoothFactor")
cfgFields.LookaheadDist = makeConfigField(walkerTab, "Lookahead Dist", WalkerCfg, "LookaheadDist")
cfgFields.ArriveDist = makeConfigField(walkerTab, "Arrive Dist", WalkerCfg, "ArriveDist")
cfgFields.WaypointTimeout = makeConfigField(walkerTab, "Waypoint Timeout", WalkerCfg, "WaypointTimeout")
cfgFields.DestJitter = makeConfigField(walkerTab, "Dest Jitter (studs)", WalkerCfg, "DestJitter")
cfgFields.MicroJitter = makeConfigField(walkerTab, "Micro Jitter", WalkerCfg, "MicroJitter")
cfgFields.TickMin = makeConfigField(walkerTab, "Tick Min (s)", WalkerCfg, "TickMin")
cfgFields.TickMax = makeConfigField(walkerTab, "Tick Max (s)", WalkerCfg, "TickMax")
cfgFields.PauseBetweenMin = makeConfigField(walkerTab, "Pause Min (s)", WalkerCfg, "PauseBetweenMin")
cfgFields.PauseBetweenMax = makeConfigField(walkerTab, "Pause Max (s)", WalkerCfg, "PauseBetweenMax")
cfgFields.ShortPauseChance = makeConfigField(walkerTab, "Short Pause %", WalkerCfg, "ShortPauseChance")
cfgFields.LongIdleChance = makeConfigField(walkerTab, "Long Idle %", WalkerCfg, "LongIdleChance")
cfgFields.RouteBreakMin = makeConfigField(walkerTab, "Route Break Min", WalkerCfg, "RouteBreakMin")
cfgFields.RouteBreakMax = makeConfigField(walkerTab, "Route Break Max", WalkerCfg, "RouteBreakMax")

local function refreshCfgFields()
    for k, box in pairs(cfgFields) do
        box.Text = tostring(WalkerCfg[k])
    end
end

-- ==== POINT LIST ====
makeSectionHeader(walkerTab, "📍 Saved Points")
local listContainer = Instance.new("Frame")
listContainer.Size = UDim2.new(1, 0, 0, 0)
listContainer.AutomaticSize = Enum.AutomaticSize.Y
listContainer.BackgroundTransparency = 1
listContainer.Parent = walkerTab
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 3)
listLayout.Parent = listContainer

-- ==== FUNCTIONS ====
local function updateWalkerStatus()
    walkerStatus.Text = "Points: " .. #points .. "  |  Walking: " .. (walking and "ON" or "OFF")
    walkerStatus.TextColor3 = walking and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(180, 180, 180)
end

local function updateCurrentCfgLabel()
    currentCfgLabel.Text = "Loaded config: " .. (currentConfigName or "<none>")
end

local refreshList
local function deletePoint(index)
    table.remove(points, index)
    refreshList()
    updateWalkerStatus()
end

refreshList = function()
    for _, c in pairs(listContainer:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    for i, p in ipairs(points) do
        local entry = Instance.new("Frame")
        entry.Size = UDim2.new(1, 0, 0, 22)
        entry.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
        entry.BorderSizePixel = 0
        entry.Parent = listContainer
        Instance.new("UICorner", entry).CornerRadius = UDim.new(0, 4)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -28, 1, 0)
        lbl.Position = UDim2.new(0, 6, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = string.format("#%d (%.0f, %.0f, %.0f)", i, p.X, p.Y, p.Z)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 10
        lbl.Parent = entry

        local dbtn = Instance.new("TextButton")
        dbtn.Size = UDim2.new(0, 20, 0, 18)
        dbtn.Position = UDim2.new(1, -22, 0, 2)
        dbtn.BackgroundColor3 = Color3.fromRGB(190, 60, 60)
        dbtn.BorderSizePixel = 0
        dbtn.Text = "X"
        dbtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        dbtn.Font = Enum.Font.GothamBold
        dbtn.TextSize = 10
        dbtn.Parent = entry
        Instance.new("UICorner", dbtn).CornerRadius = UDim.new(0, 3)
        dbtn.MouseButton1Click:Connect(function() deletePoint(i) end)
    end
end

-- ==== CONFIG MANAGEMENT ====
local refreshCfgList

local function saveConfigAs(name)
    if not name or name == "" then return end
    -- Snapshot points + walker settings
    local pointsData = {}
    for _, p in ipairs(points) do table.insert(pointsData, {p.X, p.Y, p.Z}) end
    local walkerSnap = {}
    for k, v in pairs(WalkerCfg) do walkerSnap[k] = v end

    WalkerConfigs[name] = { points = pointsData, walker = walkerSnap }
    currentConfigName = name
    saveWalkerConfigs()
    refreshCfgList()
    updateCurrentCfgLabel()
    print("[BeeSuite] Saved config: " .. name)
end

local function loadConfig(name)
    local cfg = WalkerConfigs[name]
    if not cfg then return end
    -- Load points
    points = {}
    for _, v in ipairs(cfg.points or {}) do
        table.insert(points, Vector3.new(v[1], v[2], v[3]))
    end
    -- Load walker settings
    if cfg.walker then
        for k, v in pairs(cfg.walker) do WalkerCfg[k] = v end
        refreshCfgFields()
    end
    currentConfigName = name
    refreshList()
    updateWalkerStatus()
    updateCurrentCfgLabel()
    print("[BeeSuite] Loaded config: " .. name)
end

local function deleteConfig(name)
    WalkerConfigs[name] = nil
    if currentConfigName == name then currentConfigName = nil end
    saveWalkerConfigs()
    refreshCfgList()
    updateCurrentCfgLabel()
end

local function renameConfig(oldName, newName)
    if not newName or newName == "" or oldName == newName then return end
    if WalkerConfigs[newName] then return end -- name taken
    WalkerConfigs[newName] = WalkerConfigs[oldName]
    WalkerConfigs[oldName] = nil
    if currentConfigName == oldName then currentConfigName = newName end
    saveWalkerConfigs()
    refreshCfgList()
    updateCurrentCfgLabel()
end

refreshCfgList = function()
    for _, c in pairs(cfgListContainer:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    
    -- Sort names alphabetically
    local names = {}
    for k in pairs(WalkerConfigs) do table.insert(names, k) end
    table.sort(names)
    
    if #names == 0 then
        local empty = Instance.new("TextLabel")
        empty.Size = UDim2.new(1, 0, 0, 22)
        empty.BackgroundTransparency = 1
        empty.Text = "  No saved configs yet."
        empty.TextXAlignment = Enum.TextXAlignment.Left
        empty.TextColor3 = Color3.fromRGB(140, 140, 140)
        empty.Font = Enum.Font.Gotham
        empty.TextSize = 11
        empty.Parent = cfgListContainer
        return
    end
    
    for _, name in ipairs(names) do
        local cfg = WalkerConfigs[name]
        local pointCount = cfg.points and #cfg.points or 0
        
        local entry = Instance.new("Frame")
        entry.Size = UDim2.new(1, 0, 0, 26)
        entry.BackgroundColor3 = (name == currentConfigName) and Color3.fromRGB(50, 80, 110) or Color3.fromRGB(40, 40, 48)
        entry.BorderSizePixel = 0
        entry.Parent = cfgListContainer
        Instance.new("UICorner", entry).CornerRadius = UDim.new(0, 4)

        -- Name (also a rename input on double-click? for now use textbox)
        local nameBox = Instance.new("TextBox")
        nameBox.Size = UDim2.new(1, -160, 1, 0)
        nameBox.Position = UDim2.new(0, 6, 0, 0)
        nameBox.BackgroundTransparency = 1
        nameBox.Text = name .. "  (" .. pointCount .. " pts)"
        nameBox.TextXAlignment = Enum.TextXAlignment.Left
        nameBox.TextColor3 = Color3.fromRGB(220, 220, 220)
        nameBox.Font = Enum.Font.Gotham
        nameBox.TextSize = 11
        nameBox.ClearTextOnFocus = true
        nameBox.Parent = entry

        nameBox.Focused:Connect(function()
            nameBox.Text = name -- show pure name when editing
        end)
        nameBox.FocusLost:Connect(function(enter)
            if enter then
                renameConfig(name, nameBox.Text)
            else
                nameBox.Text = name .. "  (" .. pointCount .. " pts)"
            end
        end)

        local loadBtn = Instance.new("TextButton")
        loadBtn.Size = UDim2.new(0, 45, 0, 20)
        loadBtn.Position = UDim2.new(1, -152, 0, 3)
        loadBtn.BackgroundColor3 = Color3.fromRGB(60, 160, 80)
        loadBtn.BorderSizePixel = 0
        loadBtn.Text = "Load"
        loadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        loadBtn.Font = Enum.Font.GothamBold
        loadBtn.TextSize = 10
        loadBtn.Parent = entry
        Instance.new("UICorner", loadBtn).CornerRadius = UDim.new(0, 3)
        loadBtn.MouseButton1Click:Connect(function() loadConfig(name) end)

        local saveBtn = Instance.new("TextButton")
        saveBtn.Size = UDim2.new(0, 45, 0, 20)
        saveBtn.Position = UDim2.new(1, -103, 0, 3)
        saveBtn.BackgroundColor3 = Color3.fromRGB(100, 140, 200)
        saveBtn.BorderSizePixel = 0
        saveBtn.Text = "Save"
        saveBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        saveBtn.Font = Enum.Font.GothamBold
        saveBtn.TextSize = 10
        saveBtn.Parent = entry
        Instance.new("UICorner", saveBtn).CornerRadius = UDim.new(0, 3)
        saveBtn.MouseButton1Click:Connect(function() saveConfigAs(name) end)

        local delBtn = Instance.new("TextButton")
        delBtn.Size = UDim2.new(0, 45, 0, 20)
        delBtn.Position = UDim2.new(1, -54, 0, 3)
        delBtn.BackgroundColor3 = Color3.fromRGB(190, 60, 60)
        delBtn.BorderSizePixel = 0
        delBtn.Text = "Delete"
        delBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        delBtn.Font = Enum.Font.GothamBold
        delBtn.TextSize = 10
        delBtn.Parent = entry
        Instance.new("UICorner", delBtn).CornerRadius = UDim.new(0, 3)
        delBtn.MouseButton1Click:Connect(function() deleteConfig(name) end)
    end
end

-- Save New button
saveNewBtn.MouseButton1Click:Connect(function()
    local n = nameInput.Text
    if n and n ~= "" then
        saveConfigAs(n)
        nameInput.Text = ""
    end
end)

-- Update Current button
updateBtn.MouseButton1Click:Connect(function()
    if currentConfigName then
        saveConfigAs(currentConfigName)
    else
        print("[BeeSuite] No config loaded — use 'Save New' with a name first.")
    end
end)

-- ==== WALKING FUNCTIONS ====
local function walkTo(destination)
    local root = getRoot()
    if not root then return end

    local destJitter = Vector3.new(
        (math.random() - 0.5) * WalkerCfg.DestJitter, 0,
        (math.random() - 0.5) * WalkerCfg.DestJitter
    )
    local jitteredDest = destination + destJitter

    local path = PathfindingService:CreatePath({AgentRadius = 2, AgentHeight = 5, AgentCanJump = true})
    local ok = pcall(function() path:ComputeAsync(root.Position, jitteredDest) end)
    local waypoints
    if ok and path.Status == Enum.PathStatus.Success then
        waypoints = path:GetWaypoints()
    else
        waypoints = { { Position = jitteredDest, Action = Enum.PathWaypointAction.Walk } }
    end

    local hum = player.Character and player.Character:FindFirstChild("Humanoid")
    if hum then hum.AutoRotate = true end

    local smoothed = Vector3.new(0, 0, 0)

    for i, wp in ipairs(waypoints) do
        if not walking then break end
        if wp.Action == Enum.PathWaypointAction.Jump and hum then hum.Jump = true end
        local nextWp = waypoints[i + 1]
        local start = tick()

        while walking do
            root = getRoot()
            if not root then break end
            local delta = wp.Position - root.Position
            local flat = Vector3.new(delta.X, 0, delta.Z)
            local d = flat.Magnitude
            if d < WalkerCfg.ArriveDist then break end
            if tick() - start > WalkerCfg.WaypointTimeout then break end
            local dir = flat.Unit
            if nextWp and d < WalkerCfg.LookaheadDist then
                local nd = nextWp.Position - root.Position
                local nf = Vector3.new(nd.X, 0, nd.Z)
                if nf.Magnitude > 0 then
                    local b = 1 - (d / WalkerCfg.LookaheadDist)
                    dir = (dir:Lerp(nf.Unit, b * 0.7)).Unit
                end
            end
            local mj = WalkerCfg.MicroJitter
            local jitter = Vector3.new((math.random() - 0.5) * mj, 0, (math.random() - 0.5) * mj)
            dir = (dir + jitter).Unit

            if smoothed.Magnitude > 0 then smoothed = smoothed:Lerp(dir, WalkerCfg.SmoothFactor)
            else smoothed = dir end

            local ac = ControlModule.activeController
            if ac then
                ac.moveVector = smoothed
                ac.forwardValue = 0; ac.backwardValue = 0; ac.leftValue = 0; ac.rightValue = 0
                ac.moveVectorIsCameraRelative = false
            end
            ControlModule.inputMoveVector = smoothed
            task.wait(WalkerCfg.TickMin + math.random() * (WalkerCfg.TickMax - WalkerCfg.TickMin))
        end
    end
    StopMove()
end

local function setPoint()
    local root = getRoot()
    if root then
        table.insert(points, root.Position)
        refreshList()
        updateWalkerStatus()
    end
end

local function toggleWalk()
    walking = not walking
    walkBtn.Text = walking and "Stop Walking" or "Start Walking"
    walkBtn.BackgroundColor3 = walking and Color3.fromRGB(200, 140, 40) or Color3.fromRGB(60, 160, 80)
    if not walking then StopMove() end
    updateWalkerStatus()
end

local function deleteAllPoints()
    points = {}
    walking = false
    StopMove()
    walkBtn.Text = "Start Walking"
    walkBtn.BackgroundColor3 = Color3.fromRGB(60, 160, 80)
    refreshList()
    updateWalkerStatus()
end

setBtn.MouseButton1Click:Connect(setPoint)
walkBtn.MouseButton1Click:Connect(toggleWalk)
delBtn.MouseButton1Click:Connect(deleteAllPoints)

task.spawn(function()
    while true do
        if walking and #points > 0 then
            for _, p in ipairs(points) do
                if not walking then break end
                walkTo(p)
                task.wait(WalkerCfg.PauseBetweenMin + math.random() * (WalkerCfg.PauseBetweenMax - WalkerCfg.PauseBetweenMin))
                if math.random() < WalkerCfg.ShortPauseChance then task.wait(2 + math.random() * 4) end
                if math.random() < WalkerCfg.LongIdleChance then task.wait(10 + math.random() * 15) end
            end
            if walking then
                task.wait(WalkerCfg.RouteBreakMin + math.random() * (WalkerCfg.RouteBreakMax - WalkerCfg.RouteBreakMin))
            end
        else
            task.wait(0.2)
        end
        task.wait()
    end
end)

-- ============================================================
-- TAB: STARFLOWER
-- ============================================================
local sfTab = createTab("Starflower")

local StarflowerTypes = {
    ["Basic"] = Color3.fromRGB(200, 200, 200),
    ["Rare"] = Color3.fromRGB(0, 170, 255),
    ["Epic"] = Color3.fromRGB(170, 0, 255),
    ["Legendary"] = Color3.fromRGB(255, 170, 0),
    ["Mythic"] = Color3.fromRGB(255, 0, 100),
    ["Lunar"] = Color3.fromRGB(0, 255, 200),
}
local STARFLOWER_LIFETIME = 300
local ESP_MAX_DISTANCE = 1000
local ESPEnabled = true
local Highlights = {}
local Billboards = {}
local TrackedStarflowers = {}
local SpawnTimes = {}

local sfStatus = makeLabel(sfTab, "ESP: ON")
sfStatus.TextColor3 = Color3.fromRGB(100, 255, 100)
local sfBtn = makeButton(sfTab, "Toggle ESP", Color3.fromRGB(60, 160, 80))

makeSectionHeader(sfTab, "⭐ Spawn Log")
local sfLogContainer = Instance.new("Frame")
sfLogContainer.Size = UDim2.new(1, 0, 0, 0)
sfLogContainer.AutomaticSize = Enum.AutomaticSize.Y
sfLogContainer.BackgroundTransparency = 1
sfLogContainer.Parent = sfTab
local sfLogLayout = Instance.new("UIListLayout")
sfLogLayout.Padding = UDim.new(0, 3)
sfLogLayout.Parent = sfLogContainer

local function GetFieldName(part)
    local current = part.Parent
    while current and current ~= workspace do
        if current.Name and current.Name:lower():find("field") then return current.Name end
        current = current.Parent
    end
    return "Unknown Field"
end

local function AddToSFLog(typeName, fieldName)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 20)
    lbl.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
    lbl.BorderSizePixel = 0
    lbl.Text = "  " .. typeName .. " | " .. fieldName
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextColor3 = StarflowerTypes[typeName] or Color3.fromRGB(0, 255, 150)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 11
    lbl.Parent = sfLogContainer
    Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 4)
    task.delay(30, function() if lbl and lbl.Parent then lbl:Destroy() end end)
end

local function FormatTime(s)
    if s <= 0 then return "Expired" end
    return string.format("%d:%02d", math.floor(s / 60), math.floor(s % 60))
end

local function CreateESP(model)
    if Highlights[model] then return end
    local color = StarflowerTypes[model.Name] or Color3.fromRGB(0, 255, 150)
    local hl = Instance.new("Highlight")
    hl.Adornee = model
    hl.FillColor = color
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = 0.4
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = model
    Highlights[model] = hl

    local part = model:FindFirstChildWhichIsA("BasePart", true)
    if not part then return end

    local bb = Instance.new("BillboardGui")
    bb.Adornee = part
    bb.Size = UDim2.new(0, 180, 0, 50)
    bb.StudsOffset = Vector3.new(0, 4, 0)
    bb.AlwaysOnTop = true
    bb.MaxDistance = ESP_MAX_DISTANCE
    bb.Parent = model

    local nameLbl = Instance.new("TextLabel")
    nameLbl.Size = UDim2.new(1, 0, 0.5, 0)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text = model.Name .. " Starflower"
    nameLbl.TextColor3 = color
    nameLbl.TextStrokeTransparency = 0
    nameLbl.Font = Enum.Font.GothamBold
    nameLbl.TextSize = 18
    nameLbl.Parent = bb

    local timer = Instance.new("TextLabel")
    timer.Name = "Timer"
    timer.Size = UDim2.new(1, 0, 0.5, 0)
    timer.Position = UDim2.new(0, 0, 0.5, 0)
    timer.BackgroundTransparency = 1
    timer.Text = "..."
    timer.TextColor3 = Color3.fromRGB(255, 255, 255)
    timer.TextStrokeTransparency = 0
    timer.Font = Enum.Font.Gotham
    timer.TextSize = 16
    timer.Parent = bb

    Billboards[model] = bb
end

local function RemoveESP(model)
    if Highlights[model] then Highlights[model]:Destroy() Highlights[model] = nil end
    if Billboards[model] then Billboards[model]:Destroy() Billboards[model] = nil end
end

local function ProcessStarflower(model)
    if not model or not model:IsA("Model") then return end
    if not StarflowerTypes[model.Name] then return end
    if TrackedStarflowers[model] then return end
    TrackedStarflowers[model] = true
    SpawnTimes[model] = tick()
    task.wait(0.2)
    if not model.Parent then return end
    local part = model:FindFirstChildWhichIsA("BasePart", true)
    if not part then return end
    AddToSFLog(model.Name, GetFieldName(part))
    if ESPEnabled then CreateESP(model) end
    model.AncestryChanged:Connect(function(_, parent)
        if not parent then
            RemoveESP(model)
            TrackedStarflowers[model] = nil
            SpawnTimes[model] = nil
        end
    end)
end

local function toggleESP()
    ESPEnabled = not ESPEnabled
    sfStatus.Text = ESPEnabled and "ESP: ON" or "ESP: OFF"
    sfStatus.TextColor3 = ESPEnabled and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(180, 180, 180)
    sfBtn.BackgroundColor3 = ESPEnabled and Color3.fromRGB(60, 160, 80) or Color3.fromRGB(120, 120, 120)
    if ESPEnabled then
        for m in pairs(TrackedStarflowers) do if m and m.Parent then CreateESP(m) end end
    else
        for m in pairs(Highlights) do RemoveESP(m) end
    end
end
sfBtn.MouseButton1Click:Connect(toggleESP)

RunService.Heartbeat:Connect(function()
    for model, bb in pairs(Billboards) do
        if model and model.Parent and bb and bb.Parent then
            local st = SpawnTimes[model]
            if st then
                local timeLeft = STARFLOWER_LIFETIME - (tick() - st)
                local t = bb:FindFirstChild("Timer")
                if t then
                    t.Text = "⏱ " .. FormatTime(timeLeft)
                    if timeLeft <= 30 then t.TextColor3 = Color3.fromRGB(255, 80, 80)
                    elseif timeLeft <= 60 then t.TextColor3 = Color3.fromRGB(255, 200, 50)
                    else t.TextColor3 = Color3.fromRGB(255, 255, 255) end
                end
            end
        end
    end
end)

task.spawn(function()
    local debris = workspace:FindFirstChild("Debris") or workspace:WaitForChild("Debris", 9e9)
    if not debris then return end
    local folder = debris:FindFirstChild("Starflowers") or debris:WaitForChild("Starflowers", 9e9)
    if not folder then return end
    for _, m in pairs(folder:GetChildren()) do task.spawn(ProcessStarflower, m) end
    folder.ChildAdded:Connect(function(m) task.spawn(ProcessStarflower, m) end)
    print("[Starflower ESP] Active.")
end)

-- ============================================================
-- TAB: UTILS
-- ============================================================
local utilTab = createTab("Utils")

local autoReset = false
local resetLabel = makeLabel(utilTab, "Auto Reset: OFF")
local resetBtn = makeButton(utilTab, "Toggle Auto Reset", Color3.fromRGB(190, 60, 60))

local function updateResetLabel()
    resetLabel.Text = "Auto Reset: " .. (autoReset and ("ON (every " .. UtilsCfg.ResetInterval .. "s)") or "OFF")
    resetLabel.TextColor3 = autoReset and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(180, 180, 180)
end

local function toggleReset()
    autoReset = not autoReset
    resetBtn.BackgroundColor3 = autoReset and Color3.fromRGB(200, 140, 40) or Color3.fromRGB(190, 60, 60)
    updateResetLabel()
end
resetBtn.MouseButton1Click:Connect(toggleReset)

makeConfigField(utilTab, "Reset Interval (s)", UtilsCfg, "ResetInterval")

task.spawn(function()
    local last = tick()
    while true do
        task.wait(1)
        if autoReset and tick() - last >= UtilsCfg.ResetInterval then
            last = tick()
            local char = player.Character
            if char then
                local hum = char:FindFirstChild("Humanoid")
                if hum then hum.Health = 0 end
            end
        elseif not autoReset then
            last = tick()
        end
    end
end)

local holdLeft = false
local holdLabel = makeLabel(utilTab, "Hold Left Click: OFF")
local holdBtn = makeButton(utilTab, "Toggle Hold Left", Color3.fromRGB(60, 120, 200))

local pressMethod = mouse1press
local releaseMethod = mouse1release

local function toggleHold()
    holdLeft = not holdLeft
    holdLabel.Text = "Hold Left Click: " .. (holdLeft and "ON" or "OFF")
    holdLabel.TextColor3 = holdLeft and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(180, 180, 180)
    holdBtn.BackgroundColor3 = holdLeft and Color3.fromRGB(200, 140, 40) or Color3.fromRGB(60, 120, 200)
    
    if pressMethod then
        if holdLeft then pressMethod() else releaseMethod() end
    else
        if not holdLeft then
            local c = workspace.CurrentCamera
            local center = Vector2.new(c.ViewportSize.X / 2, c.ViewportSize.Y / 2)
            VIM:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
        end
    end
end
holdBtn.MouseButton1Click:Connect(toggleHold)

if not pressMethod then
    task.spawn(function()
        while true do
            if holdLeft then
                local c = workspace.CurrentCamera
                local center = Vector2.new(c.ViewportSize.X / 2, c.ViewportSize.Y / 2)
                VIM:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
            end
            task.wait(0.05)
        end
    end)
end

-- ============================================================
-- TAB: KEYS
-- ============================================================
local keysTab = createTab("Keys")

local function buildKeysTab()
    for _, c in pairs(keysTab:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
    end
    makeSectionHeader(keysTab, "🎹 Keybinds")
    makeLabel(keysTab, "  Click a key button, then press new key")
    makeKeybindRow(keysTab, "Set Point", "SetPoint")
    makeKeybindRow(keysTab, "Toggle Walk", "ToggleWalk")
    makeKeybindRow(keysTab, "Delete All Points", "DeleteAll")
    makeKeybindRow(keysTab, "Toggle ESP", "ToggleESP")
    makeKeybindRow(keysTab, "Toggle Auto Reset", "ToggleReset")
    makeKeybindRow(keysTab, "Toggle Hold Click", "ToggleHold")
    makeButton(keysTab, "Reset to Defaults", Color3.fromRGB(140, 60, 60), function()
        Keybinds.SetPoint = "K"; Keybinds.ToggleWalk = "Q"; Keybinds.DeleteAll = "L"
        Keybinds.ToggleESP = "F"; Keybinds.ToggleReset = "R"; Keybinds.ToggleHold = "M"
        saveConfigs()
        buildKeysTab()
    end)
end
buildKeysTab()

-- ============================================================
-- KEYBINDS DISPATCH
-- ============================================================
UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if waitingForKey then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    local keyName = input.KeyCode.Name
    if keyName == Keybinds.SetPoint then setPoint()
    elseif keyName == Keybinds.ToggleWalk then toggleWalk()
    elseif keyName == Keybinds.DeleteAll then deleteAllPoints()
    elseif keyName == Keybinds.ToggleESP then toggleESP()
    elseif keyName == Keybinds.ToggleReset then toggleReset()
    elseif keyName == Keybinds.ToggleHold then toggleHold()
    end
end)

switchTab("Walker")
refreshList()
refreshCfgList()
updateWalkerStatus()
updateResetLabel()
updateCurrentCfgLabel()

print("[BeeSuite] Loaded. Check 'Walker' tab for route configs.")
