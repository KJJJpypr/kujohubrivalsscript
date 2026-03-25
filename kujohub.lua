-- ═══════════════════════════════════════
--   AUTO HARVEST  v1
--   死亡プレイヤーの位置へ移動してアイテム収穫
-- ═══════════════════════════════════════

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ─── 設定変数 ────────────────────────────────────
local harvestEnabled = true
local scanInterval   = 0.10   -- 死亡スキャン間隔 (秒)
local harvestRange   = 400    -- 収穫範囲 (スタッド)
local stayTime       = 0.5    -- 死亡地点に留まる時間 (秒)
local wanderRadius   = 5      -- ランダム移動の円半径 (スタッド)
local wanderInterval = 0.05   -- ランダム移動の間隔 (秒)
local returnPos      = nil    -- 収穫後に戻る座標 (Vector3)

-- ─── 内部状態 ────────────────────────────────────
local char, root, humanoid
local connections  = {}
local harvestBusy  = false
local hpCache      = {}   -- plr → lastHP
local scriptActive = true

-- ─── キャラ取得 ──────────────────────────────────
local function setup(c)
    char     = c
    root     = c:WaitForChild("HumanoidRootPart")
    humanoid = c:WaitForChild("Humanoid")
end
if player.Character then setup(player.Character) end
connections[#connections+1] =
    player.CharacterAdded:Connect(function(c)
        if scriptActive then setup(c) end
    end)

-- ═══════════════════════════════════════
--   UI
-- ═══════════════════════════════════════

local BG     = Color3.fromRGB(10, 11, 20)
local PANEL  = Color3.fromRGB(18, 20, 34)
local BORDER = Color3.fromRGB(42, 48, 80)
local ACCENT = Color3.fromRGB(100, 120, 255)
local GREEN  = Color3.fromRGB(50, 220, 130)
local RED    = Color3.fromRGB(255, 70, 85)
local TEXT   = Color3.fromRGB(220, 225, 255)
local DIM    = Color3.fromRGB(105, 115, 160)
local TRACK  = Color3.fromRGB(28, 32, 54)
local ORANGE = Color3.fromRGB(255, 160, 50)

local BASE_Z  = 100
local WIN_W   = 280
local TITLE_H = 42
local WIN_H   = 460

local function mkCorner(p,r)
    local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,r or 8) c.Parent=p
end
local function mkStroke(p,col,t)
    local s=Instance.new("UIStroke") s.Color=col or BORDER s.Thickness=t or 1 s.Parent=p
end

-- destroy old
local pg = player:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("_AH_GUI")
if old then old:Destroy() end

local SG = Instance.new("ScreenGui")
SG.Name           = "_AH_GUI"
SG.DisplayOrder   = 2147483647
SG.ZIndexBehavior = Enum.ZIndexBehavior.Global
SG.IgnoreGuiInset = true
SG.ResetOnSpawn   = false
SG.Parent         = pg

-- ── Main window ──
local Win = Instance.new("Frame")
Win.Size             = UDim2.new(0,WIN_W,0,WIN_H)
Win.Position         = UDim2.new(1,-WIN_W-20,0.5,-(WIN_H/2))
Win.BackgroundColor3 = BG
Win.BorderSizePixel  = 0
Win.ZIndex           = BASE_Z
Win.ClipsDescendants = false
Win.Parent           = SG
mkCorner(Win,10) mkStroke(Win,BORDER,1)

-- ── Title bar ──
local Title = Instance.new("Frame")
Title.Size             = UDim2.new(0,WIN_W,0,TITLE_H)
Title.BackgroundColor3 = PANEL
Title.BorderSizePixel  = 0
Title.ZIndex           = BASE_Z+1
Title.Parent           = Win
mkCorner(Title,10)

-- square bottom of title
local tf = Instance.new("Frame")
tf.Position=UDim2.new(0,0,1,-10) tf.Size=UDim2.new(1,0,0,10)
tf.BackgroundColor3=PANEL tf.BorderSizePixel=0 tf.ZIndex=BASE_Z+1 tf.Parent=Title

-- divider
local div = Instance.new("Frame")
div.Position=UDim2.new(0,0,0,TITLE_H) div.Size=UDim2.new(1,0,0,1)
div.BackgroundColor3=BORDER div.BorderSizePixel=0 div.ZIndex=BASE_Z+2 div.Parent=Win

-- icon + title text
local icon = Instance.new("TextLabel")
icon.Position=UDim2.new(0,14,0,0) icon.Size=UDim2.new(0,22,0,TITLE_H)
icon.BackgroundTransparency=1 icon.Text="◈"
icon.TextColor3=ORANGE icon.Font=Enum.Font.GothamBold icon.TextSize=16
icon.ZIndex=BASE_Z+3 icon.Parent=Title

local titleLbl = Instance.new("TextLabel")
titleLbl.Position=UDim2.new(0,38,0,0) titleLbl.Size=UDim2.new(0,160,0,TITLE_H)
titleLbl.BackgroundTransparency=1 titleLbl.Text="AUTO HARVEST"
titleLbl.TextColor3=TEXT titleLbl.Font=Enum.Font.GothamBold titleLbl.TextSize=12
titleLbl.TextXAlignment=Enum.TextXAlignment.Left titleLbl.ZIndex=BASE_Z+3 titleLbl.Parent=Title

-- status badge
local statusBadge = Instance.new("Frame")
statusBadge.Position=UDim2.new(0,WIN_W-90,0.5,-11) statusBadge.Size=UDim2.new(0,52,0,22)
statusBadge.BackgroundColor3=TRACK statusBadge.BorderSizePixel=0 statusBadge.ZIndex=BASE_Z+3 statusBadge.Parent=Title
mkCorner(statusBadge,11)

local statusLbl = Instance.new("TextLabel")
statusLbl.Size=UDim2.new(1,0,1,0) statusLbl.BackgroundTransparency=1
statusLbl.Text="OFF" statusLbl.TextColor3=DIM
statusLbl.Font=Enum.Font.GothamBold statusLbl.TextSize=11
statusLbl.ZIndex=BASE_Z+4 statusLbl.Parent=statusBadge

-- close button
local CloseBtn = Instance.new("TextButton")
CloseBtn.Position=UDim2.new(0,WIN_W-32,0.5,-11) CloseBtn.Size=UDim2.new(0,24,0,22)
CloseBtn.BackgroundColor3=Color3.fromRGB(50,20,30) CloseBtn.Text="✕"
CloseBtn.TextColor3=RED CloseBtn.Font=Enum.Font.GothamBold CloseBtn.TextSize=12
CloseBtn.BorderSizePixel=0 CloseBtn.AutoButtonColor=false
CloseBtn.ZIndex=BASE_Z+4 CloseBtn.Parent=Title
mkCorner(CloseBtn,5)

-- ── Scroll body ──
local BodyClip = Instance.new("Frame")
BodyClip.Position=UDim2.new(0,0,0,TITLE_H+1) BodyClip.Size=UDim2.new(1,0,0,WIN_H-TITLE_H-1)
BodyClip.BackgroundTransparency=1 BodyClip.BorderSizePixel=0
BodyClip.ClipsDescendants=true BodyClip.ZIndex=BASE_Z BodyClip.Parent=Win

local Scroll = Instance.new("ScrollingFrame")
Scroll.Size=UDim2.new(1,0,1,0) Scroll.BackgroundTransparency=1
Scroll.BorderSizePixel=0 Scroll.ScrollBarThickness=3
Scroll.ScrollBarImageColor3=BORDER Scroll.ZIndex=BASE_Z Scroll.Parent=BodyClip

local PAD = 12
local CW  = WIN_W - PAD*2
local cy  = PAD

-- ── Builder helpers ──────────────────────────────

local function addSection(title)
    local lbl = Instance.new("TextLabel")
    lbl.Position=UDim2.new(0,PAD,0,cy) lbl.Size=UDim2.new(0,CW,0,16)
    lbl.BackgroundTransparency=1 lbl.Text="── "..title:upper().." ──"
    lbl.TextColor3=DIM lbl.Font=Enum.Font.GothamBold lbl.TextSize=10
    lbl.TextXAlignment=Enum.TextXAlignment.Left lbl.ZIndex=BASE_Z+2 lbl.Parent=Scroll
    cy = cy+16+6
end

-- メインON/OFFトグル（大き目）
local function addMainToggle(label, initVal, callback)
    local H = 44
    local row = Instance.new("Frame")
    row.Position=UDim2.new(0,PAD,0,cy) row.Size=UDim2.new(0,CW,0,H)
    row.BackgroundColor3=PANEL row.BorderSizePixel=0 row.ZIndex=BASE_Z+2 row.Parent=Scroll
    mkCorner(row,9) mkStroke(row,BORDER,1)

    local lbl = Instance.new("TextLabel")
    lbl.Position=UDim2.new(0,14,0,0) lbl.Size=UDim2.new(0,CW-70,0,H)
    lbl.BackgroundTransparency=1 lbl.Text=label
    lbl.TextColor3=TEXT lbl.Font=Enum.Font.GothamBold lbl.TextSize=13
    lbl.TextXAlignment=Enum.TextXAlignment.Left lbl.ZIndex=BASE_Z+3 lbl.Parent=row

    -- pill track
    local track = Instance.new("Frame")
    track.Position=UDim2.new(0,CW-52,0.5,-11) track.Size=UDim2.new(0,44,0,22)
    track.BackgroundColor3=initVal and GREEN or TRACK
    track.BorderSizePixel=0 track.ZIndex=BASE_Z+3 track.Parent=row
    mkCorner(track,11)

    local thumb = Instance.new("Frame")
    thumb.Position=UDim2.new(0,initVal and 22 or 2,0.5,-9) thumb.Size=UDim2.new(0,18,0,18)
    thumb.BackgroundColor3=Color3.fromRGB(255,255,255) thumb.BorderSizePixel=0
    thumb.ZIndex=BASE_Z+4 thumb.Parent=track
    mkCorner(thumb,9)

    local state = initVal
    local btn = Instance.new("TextButton")
    btn.Size=UDim2.new(1,0,1,0) btn.BackgroundTransparency=1 btn.Text=""
    btn.ZIndex=BASE_Z+5 btn.Parent=row
    btn.MouseButton1Click:Connect(function()
        state = not state
        TweenService:Create(track,TweenInfo.new(0.15),{
            BackgroundColor3=state and GREEN or TRACK}):Play()
        TweenService:Create(thumb,TweenInfo.new(0.15),{
            Position=UDim2.new(0,state and 22 or 2,0.5,-9)}):Play()
        if callback then callback(state) end
    end)

    cy = cy+H+6
    return function(v)
        state=v
        TweenService:Create(track,TweenInfo.new(0.15),{
            BackgroundColor3=v and GREEN or TRACK}):Play()
        TweenService:Create(thumb,TweenInfo.new(0.15),{
            Position=UDim2.new(0,v and 22 or 2,0.5,-9)}):Play()
    end
end

local function addSlider(label, minV, maxV, initV, fmtFn, callback)
    local H = 54
    local row = Instance.new("Frame")
    row.Position=UDim2.new(0,PAD,0,cy) row.Size=UDim2.new(0,CW,0,H)
    row.BackgroundColor3=PANEL row.BorderSizePixel=0 row.ZIndex=BASE_Z+2 row.Parent=Scroll
    mkCorner(row,7) mkStroke(row,BORDER,1)

    local lbl = Instance.new("TextLabel")
    lbl.Position=UDim2.new(0,12,0,6) lbl.Size=UDim2.new(0,CW-80,0,18)
    lbl.BackgroundTransparency=1 lbl.Text=label
    lbl.TextColor3=TEXT lbl.Font=Enum.Font.Gotham lbl.TextSize=12
    lbl.TextXAlignment=Enum.TextXAlignment.Left lbl.ZIndex=BASE_Z+3 lbl.Parent=row

    local valLbl = Instance.new("TextLabel")
    valLbl.Position=UDim2.new(0,CW-72,0,6) valLbl.Size=UDim2.new(0,60,0,18)
    valLbl.BackgroundTransparency=1 valLbl.Text=fmtFn(initV)
    valLbl.TextColor3=ACCENT valLbl.Font=Enum.Font.GothamBold valLbl.TextSize=11
    valLbl.TextXAlignment=Enum.TextXAlignment.Right valLbl.ZIndex=BASE_Z+3 valLbl.Parent=row

    local TRACK_W = CW-24
    local trackBG = Instance.new("Frame")
    trackBG.Position=UDim2.new(0,12,0,H-18) trackBG.Size=UDim2.new(0,TRACK_W,0,5)
    trackBG.BackgroundColor3=TRACK trackBG.BorderSizePixel=0 trackBG.ZIndex=BASE_Z+3 trackBG.Parent=row
    mkCorner(trackBG,3)

    local ratio0 = (initV-minV)/(maxV-minV)
    local fill = Instance.new("Frame")
    fill.Size=UDim2.new(ratio0,0,1,0) fill.BackgroundColor3=ACCENT
    fill.BorderSizePixel=0 fill.ZIndex=BASE_Z+4 fill.Parent=trackBG
    mkCorner(fill,3)

    local knob = Instance.new("Frame")
    knob.Position=UDim2.new(0,math.floor(ratio0*TRACK_W)-6,0.5,-6) knob.Size=UDim2.new(0,12,0,12)
    knob.BackgroundColor3=Color3.fromRGB(255,255,255) knob.BorderSizePixel=0
    knob.ZIndex=BASE_Z+5 knob.Parent=trackBG
    mkCorner(knob,6)

    local value = initV
    local function setVal(v)
        v = math.clamp(v, minV, maxV)
        -- round to 2 decimal places
        v = math.floor(v*100+0.5)/100
        value = v
        local r = (v-minV)/(maxV-minV)
        fill.Size = UDim2.new(r,0,1,0)
        knob.Position = UDim2.new(0,math.floor(r*TRACK_W)-6,0.5,-6)
        valLbl.Text = fmtFn(v)
        if callback then callback(v) end
    end

    local drag = false
    local hitbox = Instance.new("TextButton")
    hitbox.Size=UDim2.new(1,0,1,0) hitbox.BackgroundTransparency=1 hitbox.Text=""
    hitbox.ZIndex=BASE_Z+6 hitbox.Parent=trackBG
    hitbox.InputBegan:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.MouseButton1 then drag=true end
    end)
    UIS.InputChanged:Connect(function(inp)
        if drag and inp.UserInputType==Enum.UserInputType.MouseMovement then
            local abs = trackBG.AbsolutePosition
            local rel = math.clamp(inp.Position.X - abs.X, 0, TRACK_W)
            setVal(minV + (rel/TRACK_W)*(maxV-minV))
        end
    end)
    UIS.InputEnded:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end
    end)

    cy = cy+H+5
end

-- ─── UI コンテンツ ────────────────────────────────

addSection("Auto Harvest")

-- メイントグル
local setToggleState = addMainToggle("Harvest", harvestEnabled, function(v)
    harvestEnabled = v
    statusLbl.Text  = v and "ON"  or "OFF"
    statusLbl.TextColor3 = v and GREEN or DIM
    TweenService:Create(statusBadge,TweenInfo.new(0.15),{
        BackgroundColor3 = v and Color3.fromRGB(15,45,25) or TRACK
    }):Play()
end)

cy = cy + 4

addSection("Settings")

addSlider("スキャン間隔", 0.01, 0.1, scanInterval,
    function(v) return string.format("%.2fs",v) end,
    function(v) scanInterval = v end)

addSlider("収穫範囲", 50, 600, harvestRange,
    function(v) return math.floor(v).." st" end,
    function(v) harvestRange = v end)

addSlider("留まる時間", 0.1, 0.5, stayTime,
    function(v) return string.format("%.2fs",v) end,
    function(v) stayTime = v end)

addSlider("ランダム移動半径", 0, 7, wanderRadius,
    function(v) return string.format("%.1fst",v) end,
    function(v) wanderRadius = v end)

addSlider("移動間隔", 0.01, 0.1, wanderInterval,
    function(v) return string.format("%.2fs",v) end,
    function(v) wanderInterval = v end)

cy = cy + 8

-- ── 帰還地点 セクション ──────────────────────────
addSection("帰還地点")

-- 座標表示ラベル行
local coordRow = Instance.new("Frame")
coordRow.Position=UDim2.new(0,PAD,0,cy) coordRow.Size=UDim2.new(0,CW,0,36)
coordRow.BackgroundColor3=PANEL coordRow.BorderSizePixel=0
coordRow.ZIndex=BASE_Z+2 coordRow.Parent=Scroll
mkCorner(coordRow,7) mkStroke(coordRow,BORDER,1)

local coordLbl = Instance.new("TextLabel")
coordLbl.Position=UDim2.new(0,12,0,0) coordLbl.Size=UDim2.new(1,-16,1,0)
coordLbl.BackgroundTransparency=1 coordLbl.Text="未設定"
coordLbl.TextColor3=DIM coordLbl.Font=Enum.Font.Gotham coordLbl.TextSize=11
coordLbl.TextXAlignment=Enum.TextXAlignment.Left
coordLbl.ZIndex=BASE_Z+3 coordLbl.Parent=coordRow
cy = cy + 36 + 5

-- 指定ボタン / クリアボタン 横並び
local BH2 = 32
local BW2 = (CW - 6) / 2

-- 指定ボタン
local setBtn = Instance.new("TextButton")
setBtn.Position=UDim2.new(0,PAD,0,cy) setBtn.Size=UDim2.new(0,BW2,0,BH2)
setBtn.BackgroundColor3=Color3.fromRGB(30,55,120) setBtn.Text="📍 ここを指定"
setBtn.TextColor3=Color3.fromRGB(140,170,255) setBtn.Font=Enum.Font.GothamBold
setBtn.TextSize=12 setBtn.BorderSizePixel=0 setBtn.AutoButtonColor=false
setBtn.ZIndex=BASE_Z+3 setBtn.Parent=Scroll
mkCorner(setBtn,7) mkStroke(setBtn,Color3.fromRGB(60,90,180),1)

-- クリアボタン
local clrBtn = Instance.new("TextButton")
clrBtn.Position=UDim2.new(0,PAD+BW2+6,0,cy) clrBtn.Size=UDim2.new(0,BW2,0,BH2)
clrBtn.BackgroundColor3=Color3.fromRGB(50,20,25) clrBtn.Text="✕ クリア"
clrBtn.TextColor3=RED clrBtn.Font=Enum.Font.GothamBold
clrBtn.TextSize=12 clrBtn.BorderSizePixel=0 clrBtn.AutoButtonColor=false
clrBtn.ZIndex=BASE_Z+3 clrBtn.Parent=Scroll
mkCorner(clrBtn,7) mkStroke(clrBtn,Color3.fromRGB(100,40,50),1)

setBtn.MouseButton1Click:Connect(function()
    if not root then return end
    returnPos = root.Position
    coordLbl.Text = string.format("X:%.1f  Y:%.1f  Z:%.1f",
        returnPos.X, returnPos.Y, returnPos.Z)
    coordLbl.TextColor3 = GREEN
    -- ボタンを一瞬光らせる
    TweenService:Create(setBtn,TweenInfo.new(0.1),{
        BackgroundColor3=Color3.fromRGB(50,100,220)}):Play()
    task.delay(0.15, function()
        TweenService:Create(setBtn,TweenInfo.new(0.2),{
            BackgroundColor3=Color3.fromRGB(30,55,120)}):Play()
    end)
end)

clrBtn.MouseButton1Click:Connect(function()
    returnPos = nil
    coordLbl.Text = "未設定"
    coordLbl.TextColor3 = DIM
end)

cy = cy + BH2 + 12
Scroll.CanvasSize = UDim2.new(0,0,0,cy)

-- ─── Drag ────────────────────────────────────────
local dragging, dragStart, startPos
Title.InputBegan:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1 or
       inp.UserInputType==Enum.UserInputType.Touch then
        dragging=true; dragStart=inp.Position; startPos=Win.Position
    end
end)
UIS.InputChanged:Connect(function(inp)
    if dragging and (inp.UserInputType==Enum.UserInputType.MouseMovement or
                     inp.UserInputType==Enum.UserInputType.Touch) then
        local d = inp.Position - dragStart
        Win.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset+d.X,
            startPos.Y.Scale, startPos.Y.Offset+d.Y)
    end
end)
UIS.InputEnded:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1 or
       inp.UserInputType==Enum.UserInputType.Touch then
        dragging=false
    end
end)

-- ─── Close ───────────────────────────────────────
CloseBtn.MouseButton1Click:Connect(function()
    scriptActive   = false
    harvestEnabled = false
    for _,c in pairs(connections) do pcall(function() c:Disconnect() end) end
    SG:Destroy()
end)

-- RShift でミニマイズ
local minimized = false
UIS.InputBegan:Connect(function(inp, gpe)
    if inp.KeyCode == Enum.KeyCode.RightShift then
        minimized = not minimized
        TweenService:Create(Win, TweenInfo.new(0.18,Enum.EasingStyle.Quart), {
            Size = minimized and UDim2.new(0,WIN_W,0,TITLE_H) or UDim2.new(0,WIN_W,0,WIN_H)
        }):Play()
        BodyClip.Visible = not minimized
    end
end)

-- ═══════════════════════════════════════
--   HARVEST LOGIC
-- ═══════════════════════════════════════

local scanTimer    = 0
local wanderTimer  = 0
local harvestActive= false   -- 収穫動作中か
local baseCF       = nil     -- 死亡地点のCFrame

-- 収穫コルーチン: baseCFを中心にwanderRadius内をランダム移動してstayTime秒後に終了
local function doHarvest(deathCF)
    if harvestActive then return end
    harvestActive = true
    baseCF = deathCF

    local elapsed   = 0
    local wTimer    = 0

    -- 最初に死亡地点へ瞬間移動
    if root then root.CFrame = baseCF end

    local conn
    conn = RunService.Heartbeat:Connect(function(dt)
        if not scriptActive or not harvestEnabled or not root then
            harvestActive = false
            conn:Disconnect()
            return
        end

        elapsed = elapsed + dt
        if elapsed >= stayTime then
            harvestActive = false
            conn:Disconnect()
            -- 帰還地点が設定されていれば戻る
            if returnPos and root then
                root.CFrame = CFrame.new(returnPos)
            end
            return
        end

        wTimer = wTimer + dt
        if wTimer >= wanderInterval then
            wTimer = 0
            -- baseCFを中心に半径wanderRadius以内のランダム点へ移動
            local r   = math.random() * wanderRadius
            local ang = math.random() * math.pi * 2
            local dx  = math.cos(ang) * r
            local dz  = math.sin(ang) * r
            local newPos = baseCF.Position + Vector3.new(dx, 0, dz)
            root.CFrame = CFrame.new(newPos) *
                CFrame.fromEulerAnglesYXZ(0, baseCF:ToEulerAnglesYXZ(), 0)
        end
    end)
end

-- メインスキャンループ
connections[#connections+1] = RunService.Heartbeat:Connect(function(dt)
    if not scriptActive or not harvestEnabled or not root then return end
    if harvestActive then return end   -- 収穫中はスキャンしない

    scanTimer = scanTimer + dt
    if scanTimer < scanInterval then return end
    scanTimer = 0

    for _, plr in pairs(Players:GetPlayers()) do
        if plr == player then continue end
        local c   = plr.Character
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        local hrp = c and c:FindFirstChild("HumanoidRootPart")

        if not hum or not hrp then
            hpCache[plr] = nil
            continue
        end

        local prev = hpCache[plr]
        local cur  = hum.Health
        hpCache[plr] = cur

        -- 前回HP>0 → 今回HP=0 の瞬間を検知
        if prev and prev > 0 and cur <= 0 then
            local dist = (hrp.Position - root.Position).Magnitude
            if dist <= harvestRange then
                task.spawn(doHarvest, hrp.CFrame)
            end
        end

        if not plr.Parent then hpCache[plr] = nil end
    end
end)
