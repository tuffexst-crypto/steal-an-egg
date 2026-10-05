-- steal_an_egg.lua
-- target: Steal an Egg (Roblox Luau)
-- runtime: Luau / Universal Client Executor
-- theme: Minimalist Pitch Black & Neutral Gray (Zero Emojis, Clean Typography)

if not game:IsLoaded() then
    pcall(function() game.Loaded:Wait() end)
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait(0.1)
    LocalPlayer = Players.LocalPlayer
end

local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera")

-- configuration state
local State = {
    AutoFarmWild = false,
    AutoStealEnemy = false,
    AutoDeposit = false,
    TweenSpeed = 35,
    WalkSpeed = 16,
    JumpPower = 50,
    InfJump = false,
    Noclip = false,
    Fly = false,
    FlySpeed = 50,
    VisualOverlay = false,
    HomeBaseCFrame = nil
}

-- anti-afk controller keepalive
pcall(function()
    LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
end)

-- character references
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

-- base locator
local function findHomeBase()
    if State.HomeBaseCFrame then
        return State.HomeBaseCFrame
    end

    local candidateFolders = {
        Workspace:FindFirstChild("Bases"),
        Workspace:FindFirstChild("Nests"),
        Workspace:FindFirstChild("Plots"),
        Workspace:FindFirstChild("Islands")
    }

    for _, folder in ipairs(candidateFolders) do
        if folder then
            for _, base in ipairs(folder:GetChildren()) do
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
    end

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

-- safe tween navigation
local currentTween = nil
local function tweenTo(targetCFrame, speedOverride)
    local root = getRoot()
    if not root then return false end

    local speed = speedOverride or State.TweenSpeed
    local distance = (root.Position - targetCFrame.Position).Magnitude
    local duration = math.clamp(distance / speed, 0.15, 15)

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

-- interaction handler
local function interactWith(instance)
    if not instance then return end

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

    local root = getRoot()
    local touch = instance:FindFirstChildWhichIsA("TouchTransmitter", true)
    if touch and root then
        local targetPart = touch.Parent
        if targetPart and targetPart:IsA("BasePart") then
            if firetouchinterest then
                firetouchinterest(root, targetPart, 0)
                task.wait(0.04)
                firetouchinterest(root, targetPart, 1)
            end
        end
    end

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

-- collect wild eggs
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
                        local inBase = false
                        local parent = item.Parent
                        while parent and parent ~= Workspace do
                            local pName = parent.Name:lower()
                            if pName:find("base") or pName:find("nest") or pName:find("plot") then
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

-- scan opposing nests
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

-- auto farm thread
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

-- auto steal thread
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
                        task.wait(0.12)
                    end
                    interactWith(targetNest.Part)
                    task.wait(0.25)

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

-- physics and movement
RunService.Stepped:Connect(function()
    local char = LocalPlayer.Character
    if not char then return end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        if State.WalkSpeed ~= 16 and hum.WalkSpeed ~= State.WalkSpeed then
            hum.WalkSpeed = State.WalkSpeed
        end
        if State.JumpPower ~= 50 and hum.JumpPower ~= State.JumpPower then
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

-- infinite jump
UserInputService.JumpRequest:Connect(function()
    if State.InfJump then
        local hum = getHumanoid()
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

-- flight
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

-- visual projection overlay
local overlayFolder = Instance.new("Folder")
overlayFolder.Name = "MimiVisualOverlay"
overlayFolder.Parent = Workspace

local function clearOverlays()
    overlayFolder:ClearAllChildren()
end

local function updateVisualOverlay()
    if not State.VisualOverlay then
        clearOverlays()
        return
    end

    local eggs = getWildEggs()
    for _, eggData in ipairs(eggs) do
        local part = eggData.Part
        if part and not part:FindFirstChild("HighlightMarker") then
            local hl = Instance.new("Highlight")
            hl.Name = "HighlightMarker"
            hl.FillColor = Color3.fromRGB(240, 240, 240)
            hl.OutlineColor = Color3.fromRGB(80, 80, 80)
            hl.FillTransparency = 0.5
            hl.OutlineTransparency = 0
            hl.Adornee = eggData.Instance
            hl.Parent = overlayFolder
        end
    end

    local enemyNests = getEnemyNests()
    for _, nestData in ipairs(enemyNests) do
        local base = nestData.Base
        if base and not base:FindFirstChild("NestHighlightMarker") then
            local hl = Instance.new("Highlight")
            hl.Name = "NestHighlightMarker"
            hl.FillColor = Color3.fromRGB(160, 40, 40)
            hl.OutlineColor = Color3.fromRGB(220, 50, 50)
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

-- interface builder: monochrome pitch-black aesthetic (no emojis)
local function buildInterface()
    local parentGui = nil
    
    if gethui then
        local success, res = pcall(gethui)
        if success and res then parentGui = res end
    end
    
    if not parentGui then
        local success, cg = pcall(function() return game:GetService("CoreGui") end)
        if success and cg then parentGui = cg end
    end
    
    if not parentGui then
        parentGui = LocalPlayer:WaitForChild("PlayerGui")
    end

    -- cleanup prior instances
    for _, name in ipairs({"StealAnEggInstrumentation", "StealAnEggGUI", "StealEggMimi"}) do
        local old = parentGui:FindFirstChild(name)
        if old then pcall(function() old:Destroy() end) end
    end

    local Screen = Instance.new("ScreenGui")
    Screen.Name = "StealEggMimi"
    Screen.ResetOnSpawn = false
    Screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    Screen.DisplayOrder = 999
    
    if syn and syn.protect_gui then
        pcall(function() syn.protect_gui(Screen) end)
    end
    Screen.Parent = parentGui

    -- main container
    local Main = Instance.new("Frame")
    Main.Name = "MainFrame"
    Main.Size = UDim2.new(0, 480, 0, 320)
    Main.Position = UDim2.new(0.5, -240, 0.5, -160)
    Main.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
    Main.BorderSizePixel = 0
    Main.Active = true
    Main.ClipsDescendants = true
    Main.Parent = Screen

    local MainCorner = Instance.new("UICorner")
    MainCorner.CornerRadius = UDim.new(0, 4)
    MainCorner.Parent = Main

    local MainStroke = Instance.new("UIStroke")
    MainStroke.Color = Color3.fromRGB(32, 32, 36)
    MainStroke.Thickness = 1
    MainStroke.Parent = Main

    -- dragging logic
    local dragging, dragInput, dragStart, startPos
    local function updateDrag(input)
        local delta = input.Position - dragStart
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end

    -- header bar
    local TopBar = Instance.new("Frame")
    TopBar.Name = "TopBar"
    TopBar.Size = UDim2.new(1, 0, 0, 36)
    TopBar.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
    TopBar.BorderSizePixel = 0
    TopBar.Parent = Main

    local TopBorder = Instance.new("Frame")
    TopBorder.Size = UDim2.new(1, 0, 0, 1)
    TopBorder.Position = UDim2.new(0, 0, 1, -1)
    TopBorder.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
    TopBorder.BorderSizePixel = 0
    TopBorder.Parent = TopBar

    TopBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Main.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    TopBar.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            updateDrag(input)
        end
    end)

    local Title = Instance.new("TextLabel")
    Title.Name = "Title"
    Title.Size = UDim2.new(1, -60, 1, 0)
    Title.Position = UDim2.new(0, 14, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Text = "STEAL AN EGG // CONTROLLER"
    Title.TextColor3 = Color3.fromRGB(230, 230, 230)
    Title.Font = Enum.Font.GothamMedium
    Title.TextSize = 11
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Parent = TopBar

    local CloseBtn = Instance.new("TextButton")
    CloseBtn.Name = "CloseBtn"
    CloseBtn.Size = UDim2.new(0, 28, 0, 28)
    CloseBtn.Position = UDim2.new(1, -32, 0, 4)
    CloseBtn.BackgroundColor3 = Color3.fromRGB(16, 16, 18)
    CloseBtn.BorderSizePixel = 0
    CloseBtn.Text = "x"
    CloseBtn.TextColor3 = Color3.fromRGB(140, 140, 140)
    CloseBtn.Font = Enum.Font.GothamMedium
    CloseBtn.TextSize = 12
    CloseBtn.Parent = TopBar

    local CloseCorner = Instance.new("UICorner")
    CloseCorner.CornerRadius = UDim.new(0, 2)
    CloseCorner.Parent = CloseBtn

    CloseBtn.MouseButton1Click:Connect(function()
        Screen:Destroy()
    end)

    -- layout: sidebar & body
    local Sidebar = Instance.new("Frame")
    Sidebar.Name = "Sidebar"
    Sidebar.Size = UDim2.new(0, 120, 1, -36)
    Sidebar.Position = UDim2.new(0, 0, 0, 36)
    Sidebar.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
    Sidebar.BorderSizePixel = 0
    Sidebar.Parent = Main

    local SidebarBorder = Instance.new("Frame")
    SidebarBorder.Size = UDim2.new(0, 1, 1, 0)
    SidebarBorder.Position = UDim2.new(1, -1, 0, 0)
    SidebarBorder.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
    SidebarBorder.BorderSizePixel = 0
    SidebarBorder.Parent = Sidebar

    local ContentArea = Instance.new("Frame")
    ContentArea.Name = "ContentArea"
    ContentArea.Size = UDim2.new(1, -120, 1, -36)
    ContentArea.Position = UDim2.new(0, 120, 0, 36)
    ContentArea.BackgroundColor3 = Color3.fromRGB(6, 6, 8)
    ContentArea.BorderSizePixel = 0
    ContentArea.Parent = Main

    local Tabs = {"AUTOMATION", "MOVEMENT", "VISUALS", "TELEPORTS"}
    local TabPages = {}

    local function createToggle(parent, text, defaultVal, callback)
        local Frame = Instance.new("Frame")
        Frame.Size = UDim2.new(1, -16, 0, 32)
        Frame.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
        Frame.BorderSizePixel = 0
        Frame.Parent = parent

        local FCorner = Instance.new("UICorner")
        FCorner.CornerRadius = UDim.new(0, 2)
        FCorner.Parent = Frame

        local FStroke = Instance.new("UIStroke")
        FStroke.Color = Color3.fromRGB(24, 24, 28)
        FStroke.Thickness = 1
        FStroke.Parent = Frame

        local Label = Instance.new("TextLabel")
        Label.Size = UDim2.new(1, -64, 1, 0)
        Label.Position = UDim2.new(0, 10, 0, 0)
        Label.BackgroundTransparency = 1
        Label.Text = text
        Label.TextColor3 = Color3.fromRGB(200, 200, 200)
        Label.Font = Enum.Font.GothamMedium
        Label.TextSize = 11
        Label.TextXAlignment = Enum.TextXAlignment.Left
        Label.Parent = Frame

        local ToggleBtn = Instance.new("TextButton")
        ToggleBtn.Size = UDim2.new(0, 42, 0, 20)
        ToggleBtn.Position = UDim2.new(1, -48, 0.5, -10)
        ToggleBtn.BackgroundColor3 = defaultVal and Color3.fromRGB(230, 230, 230) or Color3.fromRGB(22, 22, 26)
        ToggleBtn.BorderSizePixel = 0
        ToggleBtn.Text = defaultVal and "ON" or "OFF"
        ToggleBtn.TextColor3 = defaultVal and Color3.fromRGB(10, 10, 10) or Color3.fromRGB(120, 120, 120)
        ToggleBtn.Font = Enum.Font.GothamBold
        ToggleBtn.TextSize = 9
        ToggleBtn.Parent = Frame

        local BtnCorner = Instance.new("UICorner")
        BtnCorner.CornerRadius = UDim.new(0, 2)
        BtnCorner.Parent = ToggleBtn

        local active = defaultVal
        ToggleBtn.MouseButton1Click:Connect(function()
            active = not active
            ToggleBtn.Text = active and "ON" or "OFF"
            ToggleBtn.BackgroundColor3 = active and Color3.fromRGB(230, 230, 230) or Color3.fromRGB(22, 22, 26)
            ToggleBtn.TextColor3 = active and Color3.fromRGB(10, 10, 10) or Color3.fromRGB(120, 120, 120)
            callback(active)
        end)

        return Frame
    end

    local function createButton(parent, text, callback)
        local Btn = Instance.new("TextButton")
        Btn.Size = UDim2.new(1, -16, 0, 30)
        Btn.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
        Btn.BorderSizePixel = 0
        Btn.Text = text
        Btn.TextColor3 = Color3.fromRGB(210, 210, 210)
        Btn.Font = Enum.Font.GothamMedium
        Btn.TextSize = 10
        Btn.Parent = parent

        local Corner = Instance.new("UICorner")
        Corner.CornerRadius = UDim.new(0, 2)
        Corner.Parent = Btn

        local Stroke = Instance.new("UIStroke")
        Stroke.Color = Color3.fromRGB(28, 28, 34)
        Stroke.Thickness = 1
        Stroke.Parent = Btn

        Btn.MouseButton1Click:Connect(callback)
        return Btn
    end

    -- build tabs
    for i, tabName in ipairs(Tabs) do
        local Page = Instance.new("ScrollingFrame")
        Page.Name = tabName .. "Page"
        Page.Size = UDim2.new(1, -16, 1, -16)
        Page.Position = UDim2.new(0, 8, 0, 8)
        Page.BackgroundTransparency = 1
        Page.BorderSizePixel = 0
        Page.ScrollBarThickness = 2
        Page.ScrollBarImageColor3 = Color3.fromRGB(40, 40, 44)
        Page.Visible = (i == 1)
        Page.Parent = ContentArea

        local ListLayout = Instance.new("UIListLayout")
        ListLayout.Padding = UDim.new(0, 6)
        ListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
        ListLayout.Parent = Page

        TabPages[tabName] = Page

        local TabBtn = Instance.new("TextButton")
        TabBtn.Name = tabName .. "Btn"
        TabBtn.Size = UDim2.new(1, -12, 0, 28)
        TabBtn.Position = UDim2.new(0, 6, 0, 8 + (i - 1) * 32)
        TabBtn.BackgroundColor3 = (i == 1) and Color3.fromRGB(18, 18, 22) or Color3.fromRGB(10, 10, 12)
        TabBtn.BorderSizePixel = 0
        TabBtn.Text = tabName
        TabBtn.TextColor3 = (i == 1) and Color3.fromRGB(240, 240, 240) or Color3.fromRGB(100, 100, 105)
        TabBtn.Font = Enum.Font.GothamMedium
        TabBtn.TextSize = 10
        TabBtn.Parent = Sidebar

        local TabCorner = Instance.new("UICorner")
        TabCorner.CornerRadius = UDim.new(0, 2)
        TabCorner.Parent = TabBtn

        TabBtn.MouseButton1Click:Connect(function()
            for tName, pageFrame in pairs(TabPages) do
                pageFrame.Visible = (tName == tabName)
                local btn = Sidebar:FindFirstChild(tName .. "Btn")
                if btn then
                    btn.BackgroundColor3 = (tName == tabName) and Color3.fromRGB(18, 18, 22) or Color3.fromRGB(10, 10, 12)
                    btn.TextColor3 = (tName == tabName) and Color3.fromRGB(240, 240, 240) or Color3.fromRGB(100, 100, 105)
                end
            end
        end)
    end

    -- automation controls
    local autoPage = TabPages["AUTOMATION"]
    createToggle(autoPage, "Auto Farm (Wild Eggs)", State.AutoFarmWild, function(v) State.AutoFarmWild = v end)
    createToggle(autoPage, "Auto Steal (Enemy Nests)", State.AutoStealEnemy, function(v) State.AutoStealEnemy = v end)
    createToggle(autoPage, "Auto Return & Deposit", State.AutoDeposit, function(v) State.AutoDeposit = v end)
    createButton(autoPage, "Set Current Position as Home Nest", function()
        local root = getRoot()
        if root then State.HomeBaseCFrame = root.CFrame end
    end)

    -- movement controls
    local movePage = TabPages["MOVEMENT"]
    createToggle(movePage, "Noclip", State.Noclip, function(v) State.Noclip = v end)
    createToggle(movePage, "Flight (WASD + Space/Shift)", State.Fly, function(v) State.Fly = v end)
    createToggle(movePage, "Infinite Jump", State.InfJump, function(v) State.InfJump = v end)
    createButton(movePage, "Speed: Normal (16)", function() State.WalkSpeed = 16 end)
    createButton(movePage, "Speed: Fast (45)", function() State.WalkSpeed = 45 end)
    createButton(movePage, "Tween Speed: Normal (35)", function() State.TweenSpeed = 35 end)
    createButton(movePage, "Tween Speed: Fast (65)", function() State.TweenSpeed = 65 end)

    -- visuals controls
    local visPage = TabPages["VISUALS"]
    createToggle(visPage, "Projection Overlay (Eggs & Enemy Nests)", State.VisualOverlay, function(v)
        State.VisualOverlay = v
        if not v then clearOverlays() end
    end)

    -- teleports controls
    local tpPage = TabPages["TELEPORTS"]
    createButton(tpPage, "Teleport to Home Nest", function()
        local home = findHomeBase()
        local root = getRoot()
        if home and root then root.CFrame = home end
    end)
    createButton(tpPage, "Teleport to Closest Egg", function()
        local eggs = getWildEggs()
        local root = getRoot()
        if #eggs > 0 and eggs[1].Part and root then
            root.CFrame = eggs[1].Part.CFrame + Vector3.new(0, 3, 0)
        end
    end)
    createButton(tpPage, "Teleport to Closest Enemy Nest", function()
        local nests = getEnemyNests()
        local root = getRoot()
        if #nests > 0 and nests[1].Part and root then
            root.CFrame = nests[1].Part.CFrame + Vector3.new(0, 3, 0)
        end
    end)

    -- toggle keybind (RightControl / RightShift)
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if not gameProcessed and (input.KeyCode == Enum.KeyCode.RightControl or input.KeyCode == Enum.KeyCode.RightShift) then
            Main.Visible = not Main.Visible
        end
    end)

    return Screen
end

-- execution bootstrap
local ok, result = pcall(buildInterface)
if not ok then
    warn("[Instrumentation] Interface build error: " .. tostring(result))
end
