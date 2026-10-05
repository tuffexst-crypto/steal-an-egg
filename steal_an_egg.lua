-- steal_an_egg.lua
-- target: Steal an Egg (Roblox Luau)
-- runtime: Luau / Universal Client Executor
-- architecture: automation, anti-detection neutralization, sleek obsidian UI

repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera")

-- =========================================================================
-- SECTION 1: ANTI-DETECTION & VERIFICATION WORKAROUNDS
-- =========================================================================

-- 1. Prevent Client-Side Kicks
if hookmetamethod then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if not checkcaller or not checkcaller() then
            if method == "Kick" and self == LocalPlayer then
                warn("[Protection] Suppressed client kick attempt")
                return nil
            end
        end
        return oldNamecall(self, ...)
    end)

    -- 2. Humanoid Metatable Spoofing (spoof WalkSpeed/JumpPower so server checks read 16/50)
    local oldIndex
    oldIndex = hookmetamethod(game, "__index", function(self, key)
        if not checkcaller or not checkcaller() then
            if typeof(self) == "Instance" and self:IsA("Humanoid") and self:IsDescendantOf(LocalPlayer.Character or Workspace) then
                if key == "WalkSpeed" then return 16 end
                if key == "JumpPower" then return 50 end
            end
        end
        return oldIndex(self, key)
    end)
end

-- 3. Neutralize Common Client Security Scripts
local function neutralizeClientDetectors()
    local targets = {
        LocalPlayer:FindFirstChildOfClass("PlayerScripts"),
        LocalPlayer.Character
    }
    for _, container in ipairs(targets) do
        if container then
            for _, scriptInstance in ipairs(container:GetDescendants()) do
                if scriptInstance:IsA("LocalScript") then
                    local name = scriptInstance.Name:lower()
                    if name:find("anti") or name:find("cheat") or name:find("exploit") or name:find("detect") or name:find("security") then
                        pcall(function()
                            scriptInstance.Disabled = true
                            warn("[Protection] Neutralized security script: " .. scriptInstance.Name)
                        end)
                    end
                end
            end
        end
    end
end
pcall(neutralizeClientDetectors)
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    pcall(neutralizeClientDetectors)
end)

-- 4. Anti-AFK Keepalive
pcall(function()
    LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
end)

-- =========================================================================
-- SECTION 2: CONFIGURATION & GLOBAL STATE
-- =========================================================================

local State = {
    AutoFarmWild = false,
    AutoStealEnemy = false,
    AutoDeposit = true,
    Method = "Tween", -- "Tween" or "Instant"
    TweenSpeed = 38,
    WalkSpeed = 16,
    JumpPower = 50,
    InfJump = false,
    Noclip = false,
    Fly = false,
    FlySpeed = 50,
    VisualOverlay = false,
    HomeBaseCFrame = nil,
    CollectedCount = 0,
    Status = "READY"
}

-- helper references
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

-- =========================================================================
-- SECTION 3: NEST & BASE IDENTIFICATION
-- =========================================================================

local function findHomeBase()
    if State.HomeBaseCFrame then
        return State.HomeBaseCFrame
    end

    -- scan structured base containers
    local potentialBases = {
        Workspace:FindFirstChild("Bases"),
        Workspace:FindFirstChild("Nests"),
        Workspace:FindFirstChild("Plots"),
        Workspace:FindFirstChild("Islands"),
        Workspace:FindFirstChild("Spawns")
    }

    for _, container in ipairs(potentialBases) do
        if container then
            for _, base in ipairs(container:GetChildren()) do
                local owner = base:FindFirstChild("Owner") or base:FindFirstChild("Player") or base:FindFirstChild("UserId")
                local isMine = false
                if owner then
                    if owner.Value == LocalPlayer or owner.Value == LocalPlayer.Name or owner.Value == LocalPlayer.UserId then
                        isMine = true
                    end
                end

                if isMine then
                    local nestPart = base:FindFirstChild("Nest") 
                        or base:FindFirstChild("Deposit") 
                        or base:FindFirstChild("Drop") 
                        or base:FindFirstChild("EggStorage")
                        or base:FindFirstChildWhichIsA("BasePart")
                    if nestPart then
                        State.HomeBaseCFrame = nestPart.CFrame + Vector3.new(0, 3, 0)
                        return State.HomeBaseCFrame
                    end
                end
            end
        end
    end

    -- fallback: player's spawn point
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("SpawnLocation") and obj.Enabled then
            State.HomeBaseCFrame = obj.CFrame + Vector3.new(0, 3, 0)
            return State.HomeBaseCFrame
        end
    end

    -- default to current root position
    local root = getRoot()
    if root then
        State.HomeBaseCFrame = root.CFrame
        return State.HomeBaseCFrame
    end

    return nil
end

-- scan other player nests
local function getEnemyNests()
    local enemyNests = {}
    local containers = {
        Workspace:FindFirstChild("Bases"),
        Workspace:FindFirstChild("Nests"),
        Workspace:FindFirstChild("Plots"),
        Workspace:FindFirstChild("Islands")
    }

    local myBase = findHomeBase()

    for _, container in ipairs(containers) do
        if container then
            for _, base in ipairs(container:GetChildren()) do
                local owner = base:FindFirstChild("Owner") or base:FindFirstChild("Player")
                local isMine = false
                if owner and (owner.Value == LocalPlayer or owner.Value == LocalPlayer.Name) then
                    isMine = true
                end

                if not isMine then
                    local nestPart = base:FindFirstChild("Nest") 
                        or base:FindFirstChild("EggStorage") 
                        or base:FindFirstChild("Deposit") 
                        or base:FindFirstChildWhichIsA("BasePart")

                    local eggsInNest = {}
                    for _, item in ipairs(base:GetDescendants()) do
                        if item.Name:lower():find("egg") and (item:IsA("BasePart") or item:IsA("Model")) then
                            local part = item:IsA("BasePart") and item or item:FindFirstChildWhichIsA("BasePart")
                            if part then
                                table.insert(eggsInNest, {Instance = item, Part = part})
                            end
                        end
                    end

                    if nestPart or #eggsInNest > 0 then
                        table.insert(enemyNests, {
                            Base = base,
                            Part = nestPart or (eggsInNest[1] and eggsInNest[1].Part),
                            Eggs = eggsInNest,
                            Count = #eggsInNest
                        })
                    end
                end
            end
        end
    end

    return enemyNests
end

-- =========================================================================
-- SECTION 4: AGGRESSIVE EGG DETECTION & COLLECTION PIPELINE
-- =========================================================================

-- checks whether an instance belongs to local character or a player
local function isCharacterObject(inst)
    if not inst then return true end
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character and inst:IsDescendantOf(player.Character) then
            return true
        end
    end
    return false
end

-- deep scan for collectible eggs anywhere in workspace
local function getEggs()
    local results = {}
    local root = getRoot()
    local origin = root and root.Position or Vector3.zero
    local homeCFrame = State.HomeBaseCFrame or findHomeBase()
    local homePos = homeCFrame and homeCFrame.Position or Vector3.new(99999, 99999, 99999)

    -- 1. Scan candidate folders first for fast lookups
    local searchContainers = {
        Workspace:FindFirstChild("Eggs"),
        Workspace:FindFirstChild("SpawnedEggs"),
        Workspace:FindFirstChild("WildEggs"),
        Workspace:FindFirstChild("EggSpawns"),
        Workspace:FindFirstChild("Map"),
        Workspace:FindFirstChild("Debris"),
        Workspace
    }

    local visited = {}

    local function evaluateCandidate(item)
        if not item or visited[item] then return end
        visited[item] = true

        if isCharacterObject(item) then return end

        local name = item.Name:lower()
        if name:find("egg") or name:find("crystal") or name:find("relic") then
            local primaryPart = nil
            if item:IsA("BasePart") then
                primaryPart = item
            elseif item:IsA("Model") then
                primaryPart = item.PrimaryPart or item:FindFirstChild("Handle") or item:FindFirstChildWhichIsA("BasePart")
            end

            if primaryPart and primaryPart:IsA("BasePart") then
                -- check distance from home base to filter out already-deposited eggs
                local distFromHome = (primaryPart.Position - homePos).Magnitude
                if distFromHome > 15 then
                    local dist = (primaryPart.Position - origin).Magnitude
                    table.insert(results, {
                        Instance = item,
                        Part = primaryPart,
                        Distance = dist
                    })
                end
            end
        end
    end

    -- scan folders
    for _, container in ipairs(searchContainers) do
        if container and container ~= Workspace then
            for _, child in ipairs(container:GetDescendants()) do
                evaluateCandidate(child)
            end
        end
    end

    -- scan top-level children of Workspace if searchContainers yielded low count
    if #results == 0 then
        for _, child in ipairs(Workspace:GetChildren()) do
            evaluateCandidate(child)
        end
    end

    -- sort nearest first
    table.sort(results, function(a, b)
        return a.Distance < b.Distance
    end)

    return results
end

-- multi-vector interaction: prompts, clickdetectors, touch, physics touch, remotes
local function executeCollect(eggData)
    if not eggData or not eggData.Instance then return false end
    local inst = eggData.Instance
    local part = eggData.Part
    local root = getRoot()
    local char = getCharacter()
    if not root or not part then return false end

    -- Vector 1: ProximityPrompt
    local prompt = inst:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt and prompt.Enabled then
        if fireproximityprompt then
            fireproximityprompt(prompt)
        else
            prompt:InputHoldBegin()
            task.wait(prompt.HoldDuration)
            prompt:InputHoldEnd()
        end
    end

    -- Vector 2: ClickDetector
    local clicker = inst:FindFirstChildWhichIsA("ClickDetector", true)
    if clicker and fireclickdetector then
        fireclickdetector(clicker)
    end

    -- Vector 3: TouchTransmitter (engine level touch event)
    local touch = inst:FindFirstChildWhichIsA("TouchTransmitter", true)
    if touch and firetouchinterest then
        local targetPart = touch.Parent
        if targetPart and targetPart:IsA("BasePart") then
            firetouchinterest(root, targetPart, 0)
            task.wait(0.03)
            firetouchinterest(root, targetPart, 1)
        end
    end

    -- Vector 4: Physics contact simulation (physical overlap)
    if part and root then
        if firetouchinterest then
            firetouchinterest(root, part, 0)
            task.wait(0.03)
            firetouchinterest(root, part, 1)
        end
        -- apply micro velocity to force engine collision contact
        root.AssemblyLinearVelocity = Vector3.new(0.05, 0.05, 0.05)
    end

    -- Vector 5: Remote discovery
    for _, remoteContainer in ipairs({ReplicatedStorage, ReplicatedStorage:FindFirstChild("Remotes"), ReplicatedStorage:FindFirstChild("Events")}) do
        if remoteContainer then
            for _, r in ipairs(remoteContainer:GetChildren()) do
                local rName = r.Name:lower()
                if rName:find("egg") or rName:find("collect") or rName:find("grab") or rName:find("pickup") or rName:find("take") then
                    if r:IsA("RemoteEvent") then
                        pcall(function() r:FireServer(inst) end)
                        pcall(function() r:FireServer(part) end)
                    elseif r:IsA("RemoteFunction") then
                        pcall(function() r:InvokeServer(inst) end)
                    end
                end
            end
        end
    end

    return true
end

-- =========================================================================
-- SECTION 5: MOVEMENT PIPELINE (TWEEN & CONTROLLED TRANSIT)
-- =========================================================================

local currentTween = nil
local function transitTo(targetCFrame, customSpeed)
    local root = getRoot()
    if not root then return false end

    if State.Method == "Instant" then
        root.CFrame = targetCFrame
        task.wait(0.1)
        return true
    end

    local speed = customSpeed or State.TweenSpeed
    local distance = (root.Position - targetCFrame.Position).Magnitude
    local duration = math.clamp(distance / speed, 0.1, 10)

    if currentTween then
        currentTween:Cancel()
    end

    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
    currentTween = TweenService:Create(root, tweenInfo, {CFrame = targetCFrame})
    currentTween:Play()

    local finished = false
    local conn
    conn = currentTween.Completed:Connect(function()
        finished = true
        if conn then conn:Disconnect() end
    end)

    local start = tick()
    while not finished and (tick() - start) <= (duration + 0.3) do
        if not State.AutoFarmWild and not State.AutoStealEnemy then
            currentTween:Cancel()
            return false
        end
        RunService.Heartbeat:Wait()
    end

    return true
end

-- deposit at base
local function executeDeposit()
    local home = findHomeBase()
    if not home then return end

    State.Status = "DEPOSITING"
    transitTo(home)
    task.wait(0.2)

    local root = getRoot()
    if root then
        -- trigger any touch transmitters at base
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("TouchTransmitter") then
                local p = obj.Parent
                if p and p:IsA("BasePart") and (p.Position - root.Position).Magnitude < 20 then
                    if firetouchinterest then
                        firetouchinterest(root, p, 0)
                        task.wait(0.02)
                        firetouchinterest(root, p, 1)
                    end
                end
            end
        end
    end

    -- fire deposit remotes if present
    for _, container in ipairs({ReplicatedStorage, ReplicatedStorage:FindFirstChild("Remotes"), ReplicatedStorage:FindFirstChild("Events")}) do
        if container then
            for _, r in ipairs(container:GetChildren()) do
                local name = r.Name:lower()
                if name:find("deposit") or name:find("drop") or name:find("store") or name:find("sell") then
                    if r:IsA("RemoteEvent") then
                        pcall(function() r:FireServer() end)
                    end
                end
            end
        end
    end

    task.wait(0.25)
    State.Status = "IDLE"
end

-- =========================================================================
-- SECTION 6: BACKGROUND ROUTINES (FARM & STEAL)
-- =========================================================================

-- Wild Egg Automation Routine
task.spawn(function()
    while true do
        if State.AutoFarmWild then
            local eggs = getEggs()
            if #eggs > 0 then
                local target = eggs[1]
                if target and target.Part and target.Part.Parent then
                    State.Status = "TRANSIT: EGG"
                    local targetPos = target.Part.CFrame + Vector3.new(0, 1.5, 0)
                    local reached = transitTo(targetPos)
                    if reached and target.Part and target.Part.Parent then
                        State.Status = "COLLECTING"
                        executeCollect(target)
                        State.CollectedCount = State.CollectedCount + 1
                        task.wait(0.18)

                        if State.AutoDeposit then
                            executeDeposit()
                        end
                    end
                end
            else
                State.Status = "SEARCHING"
                task.wait(0.8)
            end
        end
        task.wait(0.1)
    end
end)

-- Enemy Nest Steal Routine
task.spawn(function()
    while true do
        if State.AutoStealEnemy then
            local enemyNests = getEnemyNests()
            local chosen = nil

            for _, nest in ipairs(enemyNests) do
                if nest.Count > 0 then
                    chosen = nest
                    break
                end
            end

            if not chosen and #enemyNests > 0 then
                chosen = enemyNests[1]
            end

            if chosen and chosen.Part then
                State.Status = "INFILTRATING"
                local targetCFrame = chosen.Part.CFrame + Vector3.new(0, 2, 0)
                local reached = transitTo(targetCFrame)
                if reached then
                    State.Status = "STEALING"
                    for _, eggItem in ipairs(chosen.Eggs) do
                        executeCollect(eggItem)
                        task.wait(0.1)
                    end
                    executeCollect({Instance = chosen.Base, Part = chosen.Part})
                    task.wait(0.2)

                    if State.AutoDeposit then
                        executeDeposit()
                    end
                end
            else
                State.Status = "NO TARGET NESTS"
                task.wait(1.5)
            end
        end
        task.wait(0.1)
    end
end)

-- =========================================================================
-- SECTION 7: MOVEMENT MODIFICATIONS & ENGINE OVERLAYS
-- =========================================================================

-- Noclip & Speed modification
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

-- Infinite Jump
UserInputService.JumpRequest:Connect(function()
    if State.InfJump then
        local hum = getHumanoid()
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

-- Flight Mechanics
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
    if State.Fly then updateFly() end
end)

-- Visual Projection Overlay
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

    local eggs = getEggs()
    for _, eggData in ipairs(eggs) do
        local part = eggData.Part
        if part and not part:FindFirstChild("EggHighlight") then
            local hl = Instance.new("Highlight")
            hl.Name = "EggHighlight"
            hl.FillColor = Color3.fromRGB(255, 255, 255)
            hl.OutlineColor = Color3.fromRGB(90, 90, 90)
            hl.FillTransparency = 0.55
            hl.OutlineTransparency = 0.1
            hl.Adornee = eggData.Instance
            hl.Parent = overlayFolder
        end
    end

    local nests = getEnemyNests()
    for _, nestData in ipairs(nests) do
        local base = nestData.Base
        if base and not base:FindFirstChild("NestHighlight") then
            local hl = Instance.new("Highlight")
            hl.Name = "NestHighlight"
            hl.FillColor = Color3.fromRGB(180, 50, 50)
            hl.OutlineColor = Color3.fromRGB(240, 70, 70)
            hl.FillTransparency = 0.65
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

-- =========================================================================
-- SECTION 8: SLEEK OBSIDIAN USER INTERFACE (NO EMOJIS)
-- =========================================================================

local function buildInterface()
    local parentGui = nil
    if gethui then
        local ok, res = pcall(gethui)
        if ok and res then parentGui = res end
    end
    if not parentGui then
        local ok, cg = pcall(function() return game:GetService("CoreGui") end)
        if ok and cg then parentGui = cg end
    end
    if not parentGui then
        parentGui = LocalPlayer:WaitForChild("PlayerGui")
    end

    -- purge old instances
    for _, name in ipairs({"StealAnEggInstrumentation", "StealAnEggGUI", "StealEggMimi", "StealAnEggObsidian"}) do
        local old = parentGui:FindFirstChild(name)
        if old then pcall(function() old:Destroy() end) end
    end

    local Screen = Instance.new("ScreenGui")
    Screen.Name = "StealAnEggObsidian"
    Screen.ResetOnSpawn = false
    Screen.DisplayOrder = 999
    if syn and syn.protect_gui then
        pcall(function() syn.protect_gui(Screen) end)
    end
    Screen.Parent = parentGui

    -- main container: deep matte obsidian
    local Main = Instance.new("Frame")
    Main.Name = "MainFrame"
    Main.Size = UDim2.new(0, 520, 0, 360)
    Main.Position = UDim2.new(0.5, -260, 0.5, -180)
    Main.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
    Main.BorderSizePixel = 0
    Main.Active = true
    Main.ClipsDescendants = true
    Main.Parent = Screen

    local MainCorner = Instance.new("UICorner")
    MainCorner.CornerRadius = UDim.new(0, 6)
    MainCorner.Parent = Main

    local MainStroke = Instance.new("UIStroke")
    MainStroke.Color = Color3.fromRGB(36, 36, 42)
    MainStroke.Thickness = 1
    MainStroke.Parent = Main

    -- dragging logic
    local dragging, dragInput, dragStart, startPos
    local function updateDrag(input)
        local delta = input.Position - dragStart
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end

    -- top bar
    local TopBar = Instance.new("Frame")
    TopBar.Name = "TopBar"
    TopBar.Size = UDim2.new(1, 0, 0, 40)
    TopBar.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
    TopBar.BorderSizePixel = 0
    TopBar.Parent = Main

    local TopBorder = Instance.new("Frame")
    TopBorder.Size = UDim2.new(1, 0, 0, 1)
    TopBorder.Position = UDim2.new(0, 0, 1, -1)
    TopBorder.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
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
    Title.Size = UDim2.new(0, 240, 1, 0)
    Title.Position = UDim2.new(0, 16, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Text = "STEAL AN EGG  ::  SYSTEM"
    Title.TextColor3 = Color3.fromRGB(240, 240, 245)
    Title.Font = Enum.Font.GothamBold
    Title.TextSize = 12
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Parent = TopBar

    local CloseBtn = Instance.new("TextButton")
    CloseBtn.Name = "CloseBtn"
    CloseBtn.Size = UDim2.new(0, 28, 0, 28)
    CloseBtn.Position = UDim2.new(1, -34, 0, 6)
    CloseBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
    CloseBtn.BorderSizePixel = 0
    CloseBtn.Text = "x"
    CloseBtn.TextColor3 = Color3.fromRGB(150, 150, 160)
    CloseBtn.Font = Enum.Font.GothamMedium
    CloseBtn.TextSize = 12
    CloseBtn.Parent = TopBar

    local CloseCorner = Instance.new("UICorner")
    CloseCorner.CornerRadius = UDim.new(0, 4)
    CloseCorner.Parent = CloseBtn

    CloseBtn.MouseButton1Click:Connect(function()
        Screen:Destroy()
    end)

    -- status bar at bottom
    local StatusBar = Instance.new("Frame")
    StatusBar.Name = "StatusBar"
    StatusBar.Size = UDim2.new(1, 0, 0, 26)
    StatusBar.Position = UDim2.new(0, 0, 1, -26)
    StatusBar.BackgroundColor3 = Color3.fromRGB(12, 12, 15)
    StatusBar.BorderSizePixel = 0
    StatusBar.Parent = Main

    local StatusBorder = Instance.new("Frame")
    StatusBorder.Size = UDim2.new(1, 0, 0, 1)
    StatusBorder.Position = UDim2.new(0, 0, 0, 0)
    StatusBorder.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    StatusBorder.BorderSizePixel = 0
    StatusBorder.Parent = StatusBar

    local StatusText = Instance.new("TextLabel")
    StatusText.Name = "StatusText"
    StatusText.Size = UDim2.new(1, -24, 1, 0)
    StatusText.Position = UDim2.new(0, 12, 0, 0)
    StatusText.BackgroundTransparency = 1
    StatusText.Text = "STATUS: IDLE | COLLECTED: 0 | TOGGLE: RIGHT CTRL"
    StatusText.TextColor3 = Color3.fromRGB(130, 135, 145)
    StatusText.Font = Enum.Font.Gotham
    StatusText.TextSize = 10
    StatusText.TextXAlignment = Enum.TextXAlignment.Left
    StatusText.Parent = StatusBar

    -- dynamic status update loop
    task.spawn(function()
        while Screen.Parent do
            StatusText.Text = string.format("STATUS: %s | COLLECTED: %d | MODE: %s | KEY: RCTRL", State.Status, State.CollectedCount, State.Method)
            task.wait(0.2)
        end
    end)

    -- layout: sidebar & content
    local Sidebar = Instance.new("Frame")
    Sidebar.Name = "Sidebar"
    Sidebar.Size = UDim2.new(0, 130, 1, -66)
    Sidebar.Position = UDim2.new(0, 0, 0, 40)
    Sidebar.BackgroundColor3 = Color3.fromRGB(12, 12, 15)
    Sidebar.BorderSizePixel = 0
    Sidebar.Parent = Main

    local SidebarBorder = Instance.new("Frame")
    SidebarBorder.Size = UDim2.new(0, 1, 1, 0)
    SidebarBorder.Position = UDim2.new(1, -1, 0, 0)
    SidebarBorder.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
    SidebarBorder.BorderSizePixel = 0
    SidebarBorder.Parent = Sidebar

    local ContentArea = Instance.new("Frame")
    ContentArea.Name = "ContentArea"
    ContentArea.Size = UDim2.new(1, -130, 1, -66)
    ContentArea.Position = UDim2.new(0, 130, 0, 40)
    ContentArea.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
    ContentArea.BorderSizePixel = 0
    ContentArea.Parent = Main

    local Tabs = {"AUTOMATION", "MOVEMENT", "VISUALS", "TELEPORTS"}
    local TabPages = {}

    local function createToggle(parent, text, defaultVal, callback)
        local Frame = Instance.new("Frame")
        Frame.Size = UDim2.new(1, -20, 0, 36)
        Frame.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
        Frame.BorderSizePixel = 0
        Frame.Parent = parent

        local FCorner = Instance.new("UICorner")
        FCorner.CornerRadius = UDim.new(0, 4)
        FCorner.Parent = Frame

        local FStroke = Instance.new("UIStroke")
        FStroke.Color = Color3.fromRGB(28, 28, 34)
        FStroke.Thickness = 1
        FStroke.Parent = Frame

        local Label = Instance.new("TextLabel")
        Label.Size = UDim2.new(1, -70, 1, 0)
        Label.Position = UDim2.new(0, 12, 0, 0)
        Label.BackgroundTransparency = 1
        Label.Text = text
        Label.TextColor3 = Color3.fromRGB(215, 215, 225)
        Label.Font = Enum.Font.GothamMedium
        Label.TextSize = 11
        Label.TextXAlignment = Enum.TextXAlignment.Left
        Label.Parent = Frame

        local ToggleBtn = Instance.new("TextButton")
        ToggleBtn.Size = UDim2.new(0, 46, 0, 22)
        ToggleBtn.Position = UDim2.new(1, -54, 0.5, -11)
        ToggleBtn.BackgroundColor3 = defaultVal and Color3.fromRGB(240, 240, 245) or Color3.fromRGB(24, 24, 30)
        ToggleBtn.BorderSizePixel = 0
        ToggleBtn.Text = defaultVal and "ON" or "OFF"
        ToggleBtn.TextColor3 = defaultVal and Color3.fromRGB(10, 10, 12) or Color3.fromRGB(120, 120, 130)
        ToggleBtn.Font = Enum.Font.GothamBold
        ToggleBtn.TextSize = 9
        ToggleBtn.Parent = Frame

        local BtnCorner = Instance.new("UICorner")
        BtnCorner.CornerRadius = UDim.new(0, 3)
        BtnCorner.Parent = ToggleBtn

        local active = defaultVal
        ToggleBtn.MouseButton1Click:Connect(function()
            active = not active
            ToggleBtn.Text = active and "ON" or "OFF"
            ToggleBtn.BackgroundColor3 = active and Color3.fromRGB(240, 240, 245) or Color3.fromRGB(24, 24, 30)
            ToggleBtn.TextColor3 = active and Color3.fromRGB(10, 10, 12) or Color3.fromRGB(120, 120, 130)
            callback(active)
        end)

        return Frame
    end

    local function createButton(parent, text, callback)
        local Btn = Instance.new("TextButton")
        Btn.Size = UDim2.new(1, -20, 0, 32)
        Btn.BackgroundColor3 = Color3.fromRGB(18, 18, 23)
        Btn.BorderSizePixel = 0
        Btn.Text = text
        Btn.TextColor3 = Color3.fromRGB(220, 220, 230)
        Btn.Font = Enum.Font.GothamMedium
        Btn.TextSize = 11
        Btn.Parent = parent

        local Corner = Instance.new("UICorner")
        Corner.CornerRadius = UDim.new(0, 4)
        Corner.Parent = Btn

        local Stroke = Instance.new("UIStroke")
        Stroke.Color = Color3.fromRGB(32, 32, 38)
        Stroke.Thickness = 1
        Stroke.Parent = Btn

        Btn.MouseButton1Click:Connect(callback)
        return Btn
    end

    -- build tab frames
    for i, tabName in ipairs(Tabs) do
        local Page = Instance.new("ScrollingFrame")
        Page.Name = tabName .. "Page"
        Page.Size = UDim2.new(1, -16, 1, -16)
        Page.Position = UDim2.new(0, 8, 0, 8)
        Page.BackgroundTransparency = 1
        Page.BorderSizePixel = 0
        Page.ScrollBarThickness = 2
        Page.ScrollBarImageColor3 = Color3.fromRGB(45, 45, 52)
        Page.Visible = (i == 1)
        Page.Parent = ContentArea

        local ListLayout = Instance.new("UIListLayout")
        ListLayout.Padding = UDim.new(0, 7)
        ListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
        ListLayout.Parent = Page

        TabPages[tabName] = Page

        local TabBtn = Instance.new("TextButton")
        TabBtn.Name = tabName .. "Btn"
        TabBtn.Size = UDim2.new(1, -14, 0, 30)
        TabBtn.Position = UDim2.new(0, 7, 0, 10 + (i - 1) * 36)
        TabBtn.BackgroundColor3 = (i == 1) and Color3.fromRGB(22, 22, 28) or Color3.fromRGB(12, 12, 15)
        TabBtn.BorderSizePixel = 0
        TabBtn.Text = tabName
        TabBtn.TextColor3 = (i == 1) and Color3.fromRGB(245, 245, 250) or Color3.fromRGB(105, 105, 115)
        TabBtn.Font = Enum.Font.GothamMedium
        TabBtn.TextSize = 10
        TabBtn.Parent = Sidebar

        local TabCorner = Instance.new("UICorner")
        TabCorner.CornerRadius = UDim.new(0, 3)
        TabCorner.Parent = TabBtn

        TabBtn.MouseButton1Click:Connect(function()
            for tName, pageFrame in pairs(TabPages) do
                pageFrame.Visible = (tName == tabName)
                local btn = Sidebar:FindFirstChild(tName .. "Btn")
                if btn then
                    btn.BackgroundColor3 = (tName == tabName) and Color3.fromRGB(22, 22, 28) or Color3.fromRGB(12, 12, 15)
                    btn.TextColor3 = (tName == tabName) and Color3.fromRGB(245, 245, 250) or Color3.fromRGB(105, 105, 115)
                end
            end
        end)
    end

    -- AUTOMATION TAB
    local autoPage = TabPages["AUTOMATION"]
    createToggle(autoPage, "Auto Farm (Wild Eggs)", State.AutoFarmWild, function(v) State.AutoFarmWild = v end)
    createToggle(autoPage, "Auto Steal (Enemy Nests)", State.AutoStealEnemy, function(v) State.AutoStealEnemy = v end)
    createToggle(autoPage, "Auto Return & Deposit", State.AutoDeposit, function(v) State.AutoDeposit = v end)
    createToggle(autoPage, "Mode: Instant CFrame (Fast)", State.Method == "Instant", function(v)
        State.Method = v and "Instant" or "Tween"
    end)
    createButton(autoPage, "Force Collect Nearest Egg Now", function()
        local eggs = getEggs()
        if #eggs > 0 then
            executeCollect(eggs[1])
        end
    end)
    createButton(autoPage, "Set Current Position as Home Nest", function()
        local root = getRoot()
        if root then State.HomeBaseCFrame = root.CFrame end
    end)

    -- MOVEMENT TAB
    local movePage = TabPages["MOVEMENT"]
    createToggle(movePage, "Noclip (Phase Terrain & Walls)", State.Noclip, function(v) State.Noclip = v end)
    createToggle(movePage, "Flight Engine (WASD + Space/Shift)", State.Fly, function(v) State.Fly = v end)
    createToggle(movePage, "Infinite Jump Request", State.InfJump, function(v) State.InfJump = v end)
    createButton(movePage, "WalkSpeed: Fast (45)", function() State.WalkSpeed = 45 end)
    createButton(movePage, "WalkSpeed: Normal (16)", function() State.WalkSpeed = 16 end)
    createButton(movePage, "Tween Transit: Fast (65)", function() State.TweenSpeed = 65 end)
    createButton(movePage, "Tween Transit: Safe (38)", function() State.TweenSpeed = 38 end)

    -- VISUALS TAB
    local visPage = TabPages["VISUALS"]
    createToggle(visPage, "Visual Projection Overlay (Eggs & Enemy Nests)", State.VisualOverlay, function(v)
        State.VisualOverlay = v
        if not v then clearOverlays() end
    end)

    -- TELEPORTS TAB
    local tpPage = TabPages["TELEPORTS"]
    createButton(tpPage, "Teleport to Home Nest", function()
        local home = findHomeBase()
        local root = getRoot()
        if home and root then root.CFrame = home end
    end)
    createButton(tpPage, "Teleport to Closest Egg", function()
        local eggs = getEggs()
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

    -- Toggle visibility keybind (RightControl)
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if not gameProcessed and (input.KeyCode == Enum.KeyCode.RightControl or input.KeyCode == Enum.KeyCode.RightShift) then
            Main.Visible = not Main.Visible
        end
    end)

    return Screen
end

-- Initialize UI
local ok, err = pcall(buildInterface)
if not ok then
    warn("[Instrumentation] Failed to build interface: " .. tostring(err))
end
