-- steal_an_egg.lua
-- target: Steal an Egg (Roblox Luau)
-- runtime: Luau / Client Executor
-- architecture: automation & instrumentation module

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local PathfindingService = game:GetService("PathfindingService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- configuration state
local State = {
    AutoFarmWild = false,
    AutoStealEnemy = false,
    AutoDeposit = false,
    AutoUpgrade = false,
    FastCollect = false,
    TweenSpeed = 35,
    WalkSpeed = 16,
    JumpPower = 50,
    InfJump = false,
    Noclip = false,
    Fly = false,
    FlySpeed = 50,
    VisualOverlay = false,
    VisualPlayers = false,
    TargetEggType = "All", -- All, Golden, Rare, Normal
    HomeBaseCFrame = nil,
    SelectedEnemyBase = nil
}

-- anti-idle connection
LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- utility: safe character references
local function getCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function getRoot(char)
    char = char or getCharacter()
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
end

local function getHumanoid(char)
    char = char or getCharacter()
    return char and char:FindFirstChildOfClass("Humanoid")
end

-- determine player's home nest / base
local function findHomeBase()
    if State.HomeBaseCFrame then
        return State.HomeBaseCFrame
    end

    -- search common base structures
    local basesFolder = Workspace:FindFirstChild("Bases") or Workspace:FindFirstChild("Nests") or Workspace:FindFirstChild("Plots")
    if basesFolder then
        for _, base in ipairs(basesFolder:GetChildren()) do
            local ownerVal = base:FindFirstChild("Owner") or base:FindFirstChild("Player")
            if ownerVal and (ownerVal.Value == LocalPlayer or ownerVal.Value == LocalPlayer.Name) then
                local nestPart = base:FindFirstChild("Nest") or base:FindFirstChild("Deposit") or base:FindFirstChild("DropZone") or base:FindFirstChildWhichIsA("BasePart")
                if nestPart then
                    State.HomeBaseCFrame = nestPart.CFrame + Vector3.new(0, 3, 0)
                    return State.HomeBaseCFrame
                end
            end
        end
    end

    -- fallback: spawn point or current position if near spawn
    local spawnLocation = Workspace:FindFirstChildWhichIsA("SpawnLocation")
    if spawnLocation then
        State.HomeBaseCFrame = spawnLocation.CFrame + Vector3.new(0, 3, 0)
        return State.HomeBaseCFrame
    end

    local root = getRoot()
    if root then
        State.HomeBaseCFrame = root.CFrame
        return State.HomeBaseCFrame
    end

    return nil
end

-- safe movement via Tween to avoid anti-teleport checks
local currentTween = nil
local function tweenTo(targetCFrame, speedOverride)
    local root = getRoot()
    if not root then return false end

    local speed = speedOverride or State.TweenSpeed
    local distance = (root.Position - targetCFrame.Position).Magnitude
    local duration = math.clamp(distance / speed, 0.15, 12)

    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
    
    if currentTween then
        currentTween:Cancel()
    end

    currentTween = TweenService:Create(root, tweenInfo, {CFrame = targetCFrame})
    currentTween:Play()

    local completed = false
    local conn
    conn = currentTween.Completed:Connect(function()
        completed = true
        if conn then conn:Disconnect() end
    end)

    local startTime = tick()
    while not completed and (tick() - startTime) <= (duration + 0.5) do
        if not State.AutoFarmWild and not State.AutoStealEnemy then
            currentTween:Cancel()
            return false
        end
        RunService.Heartbeat:Wait()
    end

    return true
end

-- interaction helper (ProximityPrompts / TouchInterests / Remotes)
local function interactWith(instance)
    if not instance then return end

    -- proximity prompt trigger
    local prompt = instance:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt and prompt.Enabled then
        if fireproximityprompt then
            fireproximityprompt(prompt)
        else
            prompt:InputHoldBegin()
            task.wait(prompt.HoldDuration)
            prompt:InputHoldEnd()
        end
    end

    -- touch interest trigger
    local root = getRoot()
    local touch = instance:FindFirstChildWhichIsA("TouchTransmitter", true)
    if touch and root then
        local targetPart = touch.Parent
        if targetPart and targetPart:IsA("BasePart") then
            if firetouchinterest then
                firetouchinterest(root, targetPart, 0)
                task.wait(0.05)
                firetouchinterest(root, targetPart, 1)
            end
        end
    end

    -- direct remotes scan
    local remotes = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:FindFirstChild("Events")
    if remotes then
        local grabEvent = remotes:FindFirstChild("CollectEgg") or remotes:FindFirstChild("TakeEgg") or remotes:FindFirstChild("Grab")
        if grabEvent and grabEvent:IsA("RemoteEvent") then
            grabEvent:FireServer(instance)
        elseif grabEvent and grabEvent:IsA("RemoteFunction") then
            grabEvent:InvokeServer(instance)
        end
    end
end

-- scan workspace for collectible eggs
local function getWildEggs()
    local eggs = {}
    local eggContainers = {
        Workspace:FindFirstChild("Eggs"),
        Workspace:FindFirstChild("SpawnedEggs"),
        Workspace:FindFirstChild("WildEggs"),
        Workspace:FindFirstChild("Items"),
        Workspace
    }

    local root = getRoot()
    local myPos = root and root.Position or Vector3.zero

    for _, container in ipairs(eggContainers) do
        if container then
            for _, item in ipairs(container:GetChildren()) do
                local name = item.Name:lower()
                if name:find("egg") and not item:IsA("Player") then
                    local primaryPart = item:IsA("BasePart") and item or item:FindFirstChildWhichIsA("BasePart")
                    if primaryPart then
                        -- filter out eggs inside bases if only looking for wild
                        local inBase = false
                        local parent = item.Parent
                        while parent and parent ~= Workspace do
                            if parent.Name:lower():find("base") or parent.Name:lower():find("nest") then
                                inBase = true
                                break
                            end
                            parent = parent.Parent
                        end

                        if not inBase then
                            table.insert(eggs, {
                                Instance = item,
                                Part = primaryPart,
                                Distance = (primaryPart.Position - myPos).Magnitude
                            })
                        end
                    end
                end
            end
        end
    end

    table.sort(eggs, function(a, b)
        return a.Distance < b.Distance
    end)

    return eggs
end

-- scan other players' nests for eggs to steal
local function getEnemyNests()
    local enemyNests = {}
    local basesFolder = Workspace:FindFirstChild("Bases") or Workspace:FindFirstChild("Nests") or Workspace:FindFirstChild("Plots")
    
    if basesFolder then
        for _, base in ipairs(basesFolder:GetChildren()) do
            local ownerVal = base:FindFirstChild("Owner") or base:FindFirstChild("Player")
            local isOwner = false
            if ownerVal and (ownerVal.Value == LocalPlayer or ownerVal.Value == LocalPlayer.Name) then
                isOwner = true
            end

            if not isOwner then
                local nestPart = base:FindFirstChild("Nest") or base:FindFirstChild("EggStorage") or base:FindFirstChild("Eggs") or base:FindFirstChildWhichIsA("BasePart")
                local eggCount = 0
                local eggsInNest = {}

                for _, desc in ipairs(base:GetDescendants()) do
                    if desc.Name:lower():find("egg") and desc:IsA("BasePart") then
                        eggCount = eggCount + 1
                        table.insert(eggsInNest, desc)
                    end
                end

                if nestPart or #eggsInNest > 0 then
                    table.insert(enemyNests, {
                        Base = base,
                        Part = nestPart or eggsInNest[1],
                        EggCount = eggCount,
                        Eggs = eggsInNest
                    })
                end
            end
        end
    end

    return enemyNests
end

-- main auto farm loop
task.spawn(function()
    while true do
        if State.AutoFarmWild then
            local eggs = getWildEggs()
            if #eggs > 0 then
                local target = eggs[1]
                if target and target.Part then
                    local targetCFrame = target.Part.CFrame + Vector3.new(0, 2, 0)
                    local reached = tweenTo(targetCFrame)
                    if reached then
                        interactWith(target.Instance)
                        task.wait(0.2)

                        if State.AutoDeposit then
                            local home = findHomeBase()
                            if home then
                                tweenTo(home)
                                task.wait(0.3)
                            end
                        end
                    end
                end
            else
                task.wait(1)
            end
        end
        task.wait(0.1)
    end
end)

-- main auto steal loop
task.spawn(function()
    while true do
        if State.AutoStealEnemy then
            local enemyNests = getEnemyNests()
            local targetNest = nil

            for _, nest in ipairs(enemyNests) do
                if nest.EggCount > 0 then
                    targetNest = nest
                    break
                end
            end

            if not targetNest and #enemyNests > 0 then
                targetNest = enemyNests[1]
            end

            if targetNest and targetNest.Part then
                local targetCFrame = targetNest.Part.CFrame + Vector3.new(0, 3, 0)
                local reached = tweenTo(targetCFrame)
                if reached then
                    for _, egg in ipairs(targetNest.Eggs) do
                        interactWith(egg)
                        task.wait(0.15)
                    end
                    interactWith(targetNest.Part)
                    task.wait(0.3)

                    -- return immediately with stolen material
                    local home = findHomeBase()
                    if home then
                        tweenTo(home)
                        task.wait(0.3)
                    end
                end
            else
                task.wait(1.5)
            end
        end
        task.wait(0.1)
    end
end)

-- movement modifications & physics loop
RunService.Stepped:Connect(function()
    local char = LocalPlayer.Character
    if not char then return end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        if hum.WalkSpeed ~= State.WalkSpeed and State.WalkSpeed ~= 16 then
            hum.WalkSpeed = State.WalkSpeed
        end
        if hum.JumpPower ~= State.JumpPower and State.JumpPower ~= 50 then
            hum.JumpPower = State.JumpPower
        end
    end

    if State.Noclip then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
            end
        end
    end
end)

-- infinite jump implementation
UserInputService.JumpRequest:Connect(function()
    if State.InfJump then
        local hum = getHumanoid()
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

-- flight implementation
local flyBodyVelocity, flyBodyGyro
local function updateFly()
    local root = getRoot()
    if not root then return end

    if State.Fly then
        if not flyBodyVelocity then
            flyBodyVelocity = Instance.new("BodyVelocity")
            flyBodyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
            flyBodyVelocity.Velocity = Vector3.zero
            flyBodyVelocity.Parent = root
        end

        if not flyBodyGyro then
            flyBodyGyro = Instance.new("BodyGyro")
            flyBodyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
            flyBodyGyro.CFrame = root.CFrame
            flyBodyGyro.Parent = root
        end

        local moveDir = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + (Camera.CFrame.LookVector) end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - (Camera.CFrame.LookVector) end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - (Camera.CFrame.RightVector) end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + (Camera.CFrame.RightVector) end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then moveDir = moveDir - Vector3.new(0, 1, 0) end

        flyBodyVelocity.Velocity = moveDir * State.FlySpeed
        flyBodyGyro.CFrame = Camera.CFrame
    else
        if flyBodyVelocity then flyBodyVelocity:Destroy(); flyBodyVelocity = nil end
        if flyBodyGyro then flyBodyGyro:Destroy(); flyBodyGyro = nil end
    end
end

RunService.RenderStepped:Connect(function()
    if State.Fly then
        updateFly()
    end
end)

-- visual projection overlay (highlights / billboards)
local overlayFolder = Instance.new("Folder")
overlayFolder.Name = "MimiInstrumentationOverlay"
overlayFolder.Parent = Workspace

local function clearOverlays()
    overlayFolder:ClearAllChildren()
end

local function updateVisualOverlay()
    if not State.VisualOverlay then
        clearOverlays()
        return
    end

    -- highlight eggs
    local eggs = getWildEggs()
    for _, eggData in ipairs(eggs) do
        local part = eggData.Part
        if part and not part:FindFirstChild("OverlayHighlight") then
            local hl = Instance.new("Highlight")
            hl.Name = "OverlayHighlight"
            hl.FillColor = Color3.fromRGB(255, 215, 0)
            hl.OutlineColor = Color3.fromRGB(255, 255, 255)
            hl.FillTransparency = 0.5
            hl.OutlineTransparency = 0
            hl.Adornee = eggData.Instance
            hl.Parent = overlayFolder
        end
    end

    -- highlight enemy bases
    local enemyNests = getEnemyNests()
    for _, nestData in ipairs(enemyNests) do
        local base = nestData.Base
        if base and not base:FindFirstChild("OverlayNestHighlight") then
            local hl = Instance.new("Highlight")
            hl.Name = "OverlayNestHighlight"
            hl.FillColor = Color3.fromRGB(255, 60, 60)
            hl.OutlineColor = Color3.fromRGB(255, 100, 100)
            hl.FillTransparency = 0.6
            hl.OutlineTransparency = 0.2
            hl.Adornee = base
            hl.Parent = overlayFolder
        end
    end
end

task.spawn(function()
    while true do
        if State.VisualOverlay then
            pcall(updateVisualOverlay)
        end
        task.wait(2)
    end
end)

-- self-contained graphical interface (ScreenGui)
local function buildInterface()
    local parentGui = game:GetService("CoreGui")
    if not pcall(function() local _ = parentGui.Name end) then
        parentGui = LocalPlayer:WaitForChild("PlayerGui")
    end

    local existing = parentGui:FindFirstChild("StealAnEggInstrumentation")
    if existing then existing:Destroy() end

    local Screen = Instance.new("ScreenGui")
    Screen.Name = "StealAnEggInstrumentation"
    Screen.ResetOnSpawn = false
    Screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    Screen.Parent = parentGui

    -- main frame
    local Main = Instance.new("Frame")
    Main.Name = "Main"
    Main.Size = UDim2.new(0, 520, 0, 360)
    Main.Position = UDim2.new(0.5, -260, 0.5, -180)
    Main.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
    Main.BorderSizePixel = 0
    Main.Active = true
    Main.Draggable = true
    Main.Parent = Screen

    local MainCorner = Instance.new("UICorner")
    MainCorner.CornerRadius = UDim.new(0, 10)
    MainCorner.Parent = Main

    local MainStroke = Instance.new("UIStroke")
    MainStroke.Color = Color3.fromRGB(45, 50, 65)
    MainStroke.Thickness = 1.5
    MainStroke.Parent = Main

    -- top bar
    local TopBar = Instance.new("Frame")
    TopBar.Name = "TopBar"
    TopBar.Size = UDim2.new(1, 0, 0, 42)
    TopBar.BackgroundColor3 = Color3.fromRGB(15, 17, 22)
    TopBar.BorderSizePixel = 0
    TopBar.Parent = Main

    local TopCorner = Instance.new("UICorner")
    TopCorner.CornerRadius = UDim.new(0, 10)
    TopCorner.Parent = TopBar

    local Title = Instance.new("TextLabel")
    Title.Name = "Title"
    Title.Size = UDim2.new(1, -50, 1, 0)
    Title.Position = UDim2.new(0, 16, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Text = "STEAL AN EGG  ::  AUTOMATION SUITE"
    Title.TextColor3 = Color3.fromRGB(235, 238, 245)
    Title.Font = Enum.Font.GothamBold
    Title.TextSize = 14
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Parent = TopBar

    local CloseBtn = Instance.new("TextButton")
    CloseBtn.Name = "CloseBtn"
    CloseBtn.Size = UDim2.new(0, 30, 0, 30)
    CloseBtn.Position = UDim2.new(1, -36, 0, 6)
    CloseBtn.BackgroundColor3 = Color3.fromRGB(35, 38, 48)
    CloseBtn.Text = "X"
    CloseBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
    CloseBtn.Font = Enum.Font.GothamBold
    CloseBtn.TextSize = 13
    CloseBtn.Parent = TopBar

    local CloseCorner = Instance.new("UICorner")
    CloseCorner.CornerRadius = UDim.new(0, 6)
    CloseCorner.Parent = CloseBtn

    CloseBtn.MouseButton1Click:Connect(function()
        Screen:Destroy()
    end)

    -- tabs sidebar
    local Sidebar = Instance.new("Frame")
    Sidebar.Name = "Sidebar"
    Sidebar.Size = UDim2.new(0, 130, 1, -50)
    Sidebar.Position = UDim2.new(0, 8, 0, 46)
    Sidebar.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
    Sidebar.BorderSizePixel = 0
    Sidebar.Parent = Main

    local SideCorner = Instance.new("UICorner")
    SideCorner.CornerRadius = UDim.new(0, 8)
    SideCorner.Parent = Sidebar

    local ContentArea = Instance.new("Frame")
    ContentArea.Name = "ContentArea"
    ContentArea.Size = UDim2.new(1, -154, 1, -50)
    ContentArea.Position = UDim2.new(0, 146, 0, 46)
    ContentArea.BackgroundColor3 = Color3.fromRGB(24, 27, 35)
    ContentArea.BorderSizePixel = 0
    ContentArea.Parent = Main

    local ContentCorner = Instance.new("UICorner")
    ContentCorner.CornerRadius = UDim.new(0, 8)
    ContentCorner.Parent = ContentArea

    local Tabs = {"Automation", "Movement", "Visuals", "Teleports"}
    local TabPages = {}

    local function createToggle(parent, text, defaultVal, callback)
        local Frame = Instance.new("Frame")
        Frame.Size = UDim2.new(1, -20, 0, 36)
        Frame.BackgroundColor3 = Color3.fromRGB(32, 36, 48)
        Frame.BorderSizePixel = 0
        Frame.Parent = parent

        local FrameCorner = Instance.new("UICorner")
        FrameCorner.CornerRadius = UDim.new(0, 6)
        FrameCorner.Parent = Frame

        local Label = Instance.new("TextLabel")
        Label.Size = UDim2.new(1, -60, 1, 0)
        Label.Position = UDim2.new(0, 12, 0, 0)
        Label.BackgroundTransparency = 1
        Label.Text = text
        Label.TextColor3 = Color3.fromRGB(220, 225, 235)
        Label.Font = Enum.Font.GothamMedium
        Label.TextSize = 13
        Label.TextXAlignment = Enum.TextXAlignment.Left
        Label.Parent = Frame

        local ToggleBtn = Instance.new("TextButton")
        ToggleBtn.Size = UDim2.new(0, 44, 0, 22)
        ToggleBtn.Position = UDim2.new(1, -52, 0.5, -11)
        ToggleBtn.BackgroundColor3 = defaultVal and Color3.fromRGB(50, 190, 120) or Color3.fromRGB(55, 60, 75)
        ToggleBtn.Text = defaultVal and "ON" or "OFF"
        ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        ToggleBtn.Font = Enum.Font.GothamBold
        ToggleBtn.TextSize = 10
        ToggleBtn.Parent = Frame

        local BtnCorner = Instance.new("UICorner")
        BtnCorner.CornerRadius = UDim.new(0, 4)
        BtnCorner.Parent = ToggleBtn

        local active = defaultVal
        ToggleBtn.MouseButton1Click:Connect(function()
            active = not active
            ToggleBtn.Text = active and "ON" or "OFF"
            ToggleBtn.BackgroundColor3 = active and Color3.fromRGB(50, 190, 120) or Color3.fromRGB(55, 60, 75)
            callback(active)
        end)

        return Frame
    end

    local function createButton(parent, text, callback)
        local Btn = Instance.new("TextButton")
        Btn.Size = UDim2.new(1, -20, 0, 34)
        Btn.BackgroundColor3 = Color3.fromRGB(40, 85, 170)
        Btn.BorderSizePixel = 0
        Btn.Text = text
        Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        Btn.Font = Enum.Font.GothamBold
        Btn.TextSize = 12
        Btn.Parent = parent

        local Corner = Instance.new("UICorner")
        Corner.CornerRadius = UDim.new(0, 6)
        Corner.Parent = Btn

        Btn.MouseButton1Click:Connect(callback)
        return Btn
    end

    -- build tab frames
    for i, tabName in ipairs(Tabs) do
        local Page = Instance.new("ScrollingFrame")
        Page.Name = tabName .. "Page"
        Page.Size = UDim2.new(1, -12, 1, -12)
        Page.Position = UDim2.new(0, 6, 0, 6)
        Page.BackgroundTransparency = 1
        Page.BorderSizePixel = 0
        Page.ScrollBarThickness = 4
        Page.ScrollBarImageColor3 = Color3.fromRGB(60, 65, 80)
        Page.Visible = (i == 1)
        Page.Parent = ContentArea

        local ListLayout = Instance.new("UIListLayout")
        ListLayout.Padding = UDim.new(0, 8)
        ListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
        ListLayout.Parent = Page

        TabPages[tabName] = Page

        -- tab button in sidebar
        local TabBtn = Instance.new("TextButton")
        TabBtn.Name = tabName .. "Btn"
        TabBtn.Size = UDim2.new(1, -12, 0, 32)
        TabBtn.Position = UDim2.new(0, 6, 0, 8 + (i - 1) * 38)
        TabBtn.BackgroundColor3 = (i == 1) and Color3.fromRGB(38, 44, 58) or Color3.fromRGB(22, 25, 34)
        TabBtn.BorderSizePixel = 0
        TabBtn.Text = tabName
        TabBtn.TextColor3 = (i == 1) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 155, 170)
        TabBtn.Font = Enum.Font.GothamSemibold
        TabBtn.TextSize = 12
        TabBtn.Parent = Sidebar

        local TabBtnCorner = Instance.new("UICorner")
        TabBtnCorner.CornerRadius = UDim.new(0, 6)
        TabBtnCorner.Parent = TabBtn

        TabBtn.MouseButton1Click:Connect(function()
            for tName, pageFrame in pairs(TabPages) do
                pageFrame.Visible = (tName == tabName)
                local btn = Sidebar:FindFirstChild(tName .. "Btn")
                if btn then
                    btn.BackgroundColor3 = (tName == tabName) and Color3.fromRGB(38, 44, 58) or Color3.fromRGB(22, 25, 34)
                    btn.TextColor3 = (tName == tabName) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 155, 170)
                end
            end
        end)
    end

    -- automation tab items
    local autoPage = TabPages["Automation"]
    createToggle(autoPage, "Auto Farm (Wild Eggs)", State.AutoFarmWild, function(v) State.AutoFarmWild = v end)
    createToggle(autoPage, "Auto Steal (Enemy Nests)", State.AutoStealEnemy, function(v) State.AutoStealEnemy = v end)
    createToggle(autoPage, "Auto Return & Deposit", State.AutoDeposit, function(v) State.AutoDeposit = v end)
    createButton(autoPage, "Set Current Position as Home Base", function()
        local root = getRoot()
        if root then
            State.HomeBaseCFrame = root.CFrame
        end
    end)

    -- movement tab items
    local movePage = TabPages["Movement"]
    createToggle(movePage, "Noclip (Pass Walls)", State.Noclip, function(v) State.Noclip = v end)
    createToggle(movePage, "Fly Mode (WASD+Space)", State.Fly, function(v) State.Fly = v end)
    createToggle(movePage, "Infinite Jump", State.InfJump, function(v) State.InfJump = v end)
    createButton(movePage, "Speed: Fast (50)", function() State.WalkSpeed = 50 end)
    createButton(movePage, "Speed: Normal (16)", function() State.WalkSpeed = 16 end)
    createButton(movePage, "Tween Speed: Fast (60)", function() State.TweenSpeed = 60 end)
    createButton(movePage, "Tween Speed: Safe (35)", function() State.TweenSpeed = 35 end)

    -- visuals tab items
    local visPage = TabPages["Visuals"]
    createToggle(visPage, "Visual Projection Overlay (Eggs & Nests)", State.VisualOverlay, function(v)
        State.VisualOverlay = v
        if not v then clearOverlays() end
    end)

    -- teleports tab items
    local tpPage = TabPages["Teleports"]
    createButton(tpPage, "Teleport to Home Base", function()
        local home = findHomeBase()
        if home then
            local root = getRoot()
            if root then root.CFrame = home end
        end
    end)
    createButton(tpPage, "Teleport to Closest Egg", function()
        local eggs = getWildEggs()
        if #eggs > 0 and eggs[1].Part then
            local root = getRoot()
            if root then root.CFrame = eggs[1].Part.CFrame + Vector3.new(0, 3, 0) end
        end
    end)
    createButton(tpPage, "Teleport to Closest Enemy Nest", function()
        local nests = getEnemyNests()
        if #nests > 0 and nests[1].Part then
            local root = getRoot()
            if root then root.CFrame = nests[1].Part.CFrame + Vector3.new(0, 3, 0) end
        end
    end)

    return Screen
end

-- initialization
local success, err = pcall(buildInterface)
if not success then
    warn("[Instrumentation] Interface build error: " .. tostring(err))
end
