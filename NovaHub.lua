--[[
    NovaHub  v1.0
    Auto code capture + redeemer with a brand new UI.

    Pages : Dashboard | Redeemer | Settings | Logs | About
    Keys  : RightShift = show / hide
    Stop  : getgenv().NovaHubStop()
]]

------------------------------------------------------------
-- SERVICES / ENV
------------------------------------------------------------
local cloneref = cloneref or function(x) return x end
local function svc(name) return cloneref(game:GetService(name)) end

local Players      = svc("Players")
local RS           = svc("ReplicatedStorage")
local RunService   = svc("RunService")
local UIS          = svc("UserInputService")
local TweenService = svc("TweenService")
local HttpService  = svc("HttpService")

local lp        = Players.LocalPlayer
local playerGui = lp:WaitForChild("PlayerGui")
local env       = (getgenv and getgenv()) or _G

local getConns  = getconnections or (debug and debug.getconnections)
local getUps    = (debug and debug.getupvalues) or getupvalues
local setUp     = (debug and debug.setupvalue) or setupvalue
local setclip   = setclipboard or toclipboard or (syn and syn.write_clipboard)

-- remove previous copies (including the old redeemer UIs)
if env.NovaHubStop then pcall(env.NovaHubStop) end
for _, name in ipairs({"NovaHub", "LevithonCodeRedeemer", "ACECodeSniperUI", "AutoTypeCodesUI"}) do
    pcall(function()
        local a = game:GetService("CoreGui"):FindFirstChild(name)
        if a then a:Destroy() end
    end)
    local b = playerGui:FindFirstChild(name)
    if b then b:Destroy() end
end

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------
local CONFIG_FILE = "novahub_config.json"
local cfg = {
    auto = true, autoSubmit = true, perCode = 3, retype = false,
    copy = false, sound = true, toasts = true, accent = 1,
}

pcall(function()
    if type(isfile) == "function" and type(readfile) == "function" and isfile(CONFIG_FILE) then
        local saved = HttpService:JSONDecode(readfile(CONFIG_FILE))
        if type(saved) == "table" then
            for k, v in pairs(saved) do
                if cfg[k] ~= nil and type(v) == type(cfg[k]) then cfg[k] = v end
            end
        end
    end
end)
cfg.perCode = math.max(1, math.floor(cfg.perCode))
cfg.accent  = math.clamp(math.floor(cfg.accent), 1, 5)

local function saveCfg()
    if type(writefile) ~= "function" then return end
    pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(cfg)) end)
end

------------------------------------------------------------
-- SHARED STATE
------------------------------------------------------------
local alive   = true
local conns   = {}
local ui      = {}      -- filled by the UI section
local engine  = {}      -- filled by the engine section
local stats   = {captured = 0, submitted = 0, failed = 0}
local state   = {last = "", hooked = false, start = os.clock()}

local function keep(conn) conns[#conns + 1] = conn return conn end

------------------------------------------------------------
-- THEME + HELPERS
------------------------------------------------------------
local C = {
    bg     = Color3.fromRGB(8, 8, 10),
    panel  = Color3.fromRGB(13, 13, 16),
    card   = Color3.fromRGB(20, 20, 25),
    hover  = Color3.fromRGB(32, 32, 39),
    stroke = Color3.fromRGB(40, 40, 48),
    text   = Color3.fromRGB(245, 245, 248),
    sub    = Color3.fromRGB(140, 140, 152),
    ok     = Color3.fromRGB(90, 220, 130),
    warn   = Color3.fromRGB(255, 190, 80),
    err    = Color3.fromRGB(255, 90, 90),
    dark   = Color3.fromRGB(10, 10, 12),
}

local THEMES = {
    {"Violet",  Color3.fromRGB(150, 110, 255)},
    {"Cyan",    Color3.fromRGB(70, 210, 255)},
    {"Emerald", Color3.fromRGB(60, 220, 140)},
    {"Rose",    Color3.fromRGB(255, 90, 140)},
    {"Amber",   Color3.fromRGB(255, 185, 60)},
}
local accent = THEMES[cfg.accent][2]

local accentObjs, gradObjs, toggleRenders = {}, {}, {}

local function make(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end
local function round(p, r) return make("UICorner", {CornerRadius = UDim.new(0, r or 8)}, p) end
local function outline(p, col, th, tr)
    return make("UIStroke", {Color = col or C.stroke, Thickness = th or 1, Transparency = tr or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, p)
end
local function tw(o, props, t)
    TweenService:Create(o, TweenInfo.new(t or 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end
local function reg(inst, prop) accentObjs[#accentObjs + 1] = {inst, prop}; inst[prop] = accent; return inst end
local function gradSeq(c)
    return ColorSequence.new({
        ColorSequenceKeypoint.new(0, c),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(28, 28, 34)),
        ColorSequenceKeypoint.new(1, c),
    })
end
local function regGrad(g) gradObjs[#gradObjs + 1] = g; g.Color = gradSeq(accent); return g end
local function label(parent, text, size, font, color, pos, sz, align)
    return make("TextLabel", {
        BackgroundTransparency = 1, Text = text, TextSize = size, Font = font, TextColor3 = color,
        Position = pos or UDim2.new(), Size = sz or UDim2.new(1, 0, 1, 0),
        TextXAlignment = align or Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
    }, parent)
end
local function button(parent, text, size, pos, primary)
    local b = make("TextButton", {
        Size = size, Position = pos or UDim2.new(), Text = text, Font = Enum.Font.GothamBold, TextSize = 12,
        AutoButtonColor = false, BorderSizePixel = 0,
        BackgroundColor3 = primary and accent or C.hover,
        TextColor3 = primary and C.dark or C.text,
    }, parent)
    round(b, 7)
    if primary then reg(b, "BackgroundColor3") end
    b.MouseEnter:Connect(function()
        tw(b, {BackgroundColor3 = primary and accent:Lerp(Color3.new(1, 1, 1), 0.2) or C.stroke})
    end)
    b.MouseLeave:Connect(function()
        tw(b, {BackgroundColor3 = primary and accent or C.hover})
    end)
    return b
end
local function copyText(text)
    if setclip and text and text ~= "" then pcall(setclip, text) return true end
    return false
end

------------------------------------------------------------
-- UI : WINDOW
------------------------------------------------------------
local gui = make("ScreenGui", {Name = "NovaHub", ResetOnSpawn = false, IgnoreGuiInset = true,
    DisplayOrder = 999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
if not pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end) or not gui.Parent then
    gui.Parent = playerGui
end

local W, H = 560, 315 -- 16:9
local main = make("Frame", {Name = "Window", Size = UDim2.fromOffset(W, H), Position = UDim2.new(0.5, -W / 2, 0.5, -H / 2),
    BackgroundColor3 = C.bg, BorderSizePixel = 0, ClipsDescendants = true, Active = true}, gui)
round(main, 14)
local mainStroke = outline(main, accent, 1.6, 0.15)
local mainGrad = regGrad(make("UIGradient", {Rotation = 0}, mainStroke))

-- drag bar (whole top strip)
local dragBar = make("Frame", {Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1}, main)

-- sidebar
local side = make("Frame", {Size = UDim2.new(0, 132, 1, 0), BackgroundColor3 = C.panel, BorderSizePixel = 0}, main)
make("Frame", {Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(1, -1, 0, 0), BackgroundColor3 = C.stroke,
    BorderSizePixel = 0}, side)

label(side, "NovaHub", 20, Enum.Font.GothamBlack, C.text, UDim2.fromOffset(16, 10), UDim2.new(1, -20, 0, 24))
label(side, "CODE SNIPER  •  v1.0", 8, Enum.Font.GothamBold, C.sub, UDim2.fromOffset(16, 33), UDim2.new(1, -20, 0, 12))
local logoBar = make("Frame", {Size = UDim2.fromOffset(28, 3), Position = UDim2.fromOffset(16, 52), BorderSizePixel = 0}, side)
round(logoBar, 2); reg(logoBar, "BackgroundColor3")

local navHolder = make("Frame", {Size = UDim2.new(1, -16, 0, 170), Position = UDim2.fromOffset(8, 66),
    BackgroundTransparency = 1}, side)
make("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, navHolder)

-- status pill (bottom of sidebar)
local pill = make("Frame", {Size = UDim2.new(1, -16, 0, 30), Position = UDim2.new(0, 8, 1, -38), BackgroundColor3 = C.card}, side)
round(pill, 8)
local pillDot = make("Frame", {Size = UDim2.fromOffset(8, 8), Position = UDim2.new(0, 10, 0.5, -4),
    BackgroundColor3 = C.sub, BorderSizePixel = 0}, pill)
round(pillDot, 4)
local pillText = label(pill, "Starting...", 10, Enum.Font.GothamMedium, C.text,
    UDim2.fromOffset(24, 0), UDim2.new(1, -28, 1, 0))

-- header buttons
local pageTitle = label(main, "Dashboard", 15, Enum.Font.GothamBold, C.text, UDim2.fromOffset(148, 0), UDim2.new(1, -230, 0, 40))
local minBtn   = button(main, "–", UDim2.fromOffset(26, 26), UDim2.new(1, -66, 0, 7))
local closeBtn = button(main, "×", UDim2.fromOffset(26, 26), UDim2.new(1, -36, 0, 7))
minBtn.TextSize, closeBtn.TextSize = 16, 16
closeBtn.MouseEnter:Connect(function() tw(closeBtn, {BackgroundColor3 = Color3.fromRGB(200, 50, 60)}) end)

local holder = make("Frame", {Size = UDim2.new(1, -152, 1, -52), Position = UDim2.fromOffset(142, 44), BackgroundTransparency = 1}, main)

-- pages + navigation
local pages, navBtns = {}, {}
local function newPage(name, scrolling)
    local p
    if scrolling then
        p = make("ScrollingFrame", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
            ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Visible = false}, holder)
        reg(p, "ScrollBarImageColor3")
    else
        p = make("Frame", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false}, holder)
    end
    pages[name] = p
    return p
end
local function showPage(name)
    for n, p in pairs(pages) do p.Visible = (n == name) end
    for n, b in pairs(navBtns) do
        local on = (n == name)
        tw(b.btn, {BackgroundColor3 = on and C.card or C.panel})
        tw(b.lbl, {TextColor3 = on and C.text or C.sub})
        tw(b.bar, {BackgroundTransparency = on and 0 or 1})
    end
    pageTitle.Text = name
end
local function addNav(name, order)
    local btn = make("TextButton", {Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = C.panel, Text = "",
        AutoButtonColor = false, BorderSizePixel = 0, LayoutOrder = order}, navHolder)
    round(btn, 7)
    local bar = make("Frame", {Size = UDim2.new(0, 3, 0.55, 0), Position = UDim2.new(0, 0, 0.225, 0),
        BorderSizePixel = 0, BackgroundTransparency = 1}, btn)
    round(bar, 2); reg(bar, "BackgroundColor3")
    local lbl = label(btn, name, 12, Enum.Font.GothamMedium, C.sub, UDim2.fromOffset(14, 0), UDim2.new(1, -16, 1, 0))
    btn.MouseEnter:Connect(function() if pageTitle.Text ~= name then tw(btn, {BackgroundColor3 = C.card}) end end)
    btn.MouseLeave:Connect(function() if pageTitle.Text ~= name then tw(btn, {BackgroundColor3 = C.panel}) end end)
    btn.MouseButton1Click:Connect(function() showPage(name) end)
    navBtns[name] = {btn = btn, lbl = lbl, bar = bar}
end

------------------------------------------------------------
-- UI : COMPONENTS
------------------------------------------------------------
local function makeToggle(parent, title, sub, initial, cb, order, height)
    local row = make("Frame", {Size = UDim2.new(1, -6, 0, height or 42), BackgroundColor3 = C.card, LayoutOrder = order}, parent)
    round(row, 9)
    label(row, title, 12, Enum.Font.GothamBold, C.text, UDim2.fromOffset(12, sub and 6 or 0),
        UDim2.new(1, -70, 0, sub and 16 or (height or 42)))
    if sub then label(row, sub, 10, Enum.Font.Gotham, C.sub, UDim2.fromOffset(12, 22), UDim2.new(1, -70, 0, 14)) end
    local track = make("TextButton", {Size = UDim2.fromOffset(38, 20), Position = UDim2.new(1, -50, 0.5, -10), Text = "",
        AutoButtonColor = false, BorderSizePixel = 0, BackgroundColor3 = C.hover}, row)
    round(track, 10)
    local pin = make("Frame", {Size = UDim2.fromOffset(14, 14), BorderSizePixel = 0, BackgroundColor3 = C.sub,
        Position = UDim2.new(0, 3, 0.5, -7)}, track)
    round(pin, 7)
    local on = initial
    local function render()
        tw(track, {BackgroundColor3 = on and accent or C.hover})
        tw(pin, {Position = on and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7),
            BackgroundColor3 = on and Color3.new(1, 1, 1) or C.sub})
    end
    render()
    toggleRenders[#toggleRenders + 1] = render
    track.MouseButton1Click:Connect(function() on = not on; render(); cb(on) end)
    return function(v) on = v; render() end
end

local function setAccent(i)
    cfg.accent = i
    accent = THEMES[i][2]
    for _, e in ipairs(accentObjs) do
        if e[1] and e[1].Parent then tw(e[1], {[e[2]] = accent}, 0.25) end
    end
    for _, g in ipairs(gradObjs) do g.Color = gradSeq(accent) end
    for _, r in ipairs(toggleRenders) do r() end
    saveCfg()
end

-- toasts (live outside the window so they work while minimized)
local toastHolder = make("Frame", {Size = UDim2.fromOffset(240, 200), AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -16, 1, -16), BackgroundTransparency = 1}, gui)
make("UIListLayout", {Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Bottom,
    HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder}, toastHolder)
local toastId = 0
function ui.toast(msg, col)
    if not cfg.toasts or not alive then return end
    toastId += 1
    local f = make("Frame", {Size = UDim2.fromOffset(230, 34), BackgroundColor3 = C.panel, LayoutOrder = toastId}, toastHolder)
    round(f, 9)
    local s = outline(f, col or accent, 1.2, 0.3)
    local bar = make("Frame", {Size = UDim2.new(0, 3, 0.6, 0), Position = UDim2.new(0, 6, 0.2, 0),
        BackgroundColor3 = col or accent, BorderSizePixel = 0}, f)
    round(bar, 2)
    local t = label(f, msg, 11, Enum.Font.GothamMedium, C.text, UDim2.fromOffset(18, 0), UDim2.new(1, -24, 1, 0))
    task.delay(2.6, function()
        if not f.Parent then return end
        tw(f, {BackgroundTransparency = 1}, 0.35); tw(t, {TextTransparency = 1}, 0.35)
        tw(s, {Transparency = 1}, 0.35); tw(bar, {BackgroundTransparency = 1}, 0.35)
        task.wait(0.4)
        f:Destroy()
    end)
end

------------------------------------------------------------
-- UI : DASHBOARD
------------------------------------------------------------
addNav("Dashboard", 1); addNav("Redeemer", 2); addNav("Settings", 3); addNav("Logs", 4); addNav("About", 5)

local dash = newPage("Dashboard")
make("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, dash)

local setMasterToggle = makeToggle(dash, "Auto Code Sniper", "Grabs codes from game alerts and submits them", cfg.auto,
    function(v) cfg.auto = v; saveCfg(); ui.refreshStatus(); ui.toast(v and "Sniper enabled" or "Sniper paused", v and C.ok or C.warn) end, 1, 56)

local statsRow = make("Frame", {Size = UDim2.new(1, -6, 0, 54), BackgroundTransparency = 1, LayoutOrder = 2}, dash)
make("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder}, statsRow)
local function statCard(title, order)
    local f = make("Frame", {Size = UDim2.new(0.25, -4.5, 1, 0), BackgroundColor3 = C.card, LayoutOrder = order}, statsRow)
    round(f, 9)
    local v = label(f, "0", 19, Enum.Font.GothamBlack, C.text, UDim2.fromOffset(10, 6), UDim2.new(1, -14, 0, 26))
    label(f, title, 9, Enum.Font.GothamBold, C.sub, UDim2.fromOffset(10, 34), UDim2.new(1, -14, 0, 14))
    return v
end
local capLbl, subLbl, failLbl, timeLbl = statCard("CAPTURED", 1), statCard("SUBMITTED", 2), statCard("FAILED", 3), statCard("UPTIME", 4)

local lastCard = make("Frame", {Size = UDim2.new(1, -6, 0, 64), BackgroundColor3 = C.card, LayoutOrder = 3}, dash)
round(lastCard, 9)
label(lastCard, "LAST CODE", 9, Enum.Font.GothamBold, C.sub, UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 12))
local lastLbl = label(lastCard, "—", 18, Enum.Font.Code, accent, UDim2.fromOffset(12, 24), UDim2.new(1, -150, 0, 30))
reg(lastLbl, "TextColor3")
local copyLastBtn   = button(lastCard, "Copy", UDim2.fromOffset(58, 28), UDim2.new(1, -134, 0.5, -14))
local redeemLastBtn = button(lastCard, "Redeem", UDim2.fromOffset(62, 28), UDim2.new(1, -70, 0.5, -14), true)

local tip = make("Frame", {Size = UDim2.new(1, -6, 0, 48), BackgroundColor3 = C.card, LayoutOrder = 4}, dash)
round(tip, 9)
local tipLbl = label(tip, "TIP: Click the game's code box once so NovaHub knows where to paste. Press RightShift to hide this window.",
    10, Enum.Font.Gotham, C.sub, UDim2.fromOffset(12, 0), UDim2.new(1, -24, 1, 0))
tipLbl.TextWrapped = true; tipLbl.TextTruncate = Enum.TextTruncate.None

function ui.refresh()
    capLbl.Text, subLbl.Text, failLbl.Text = tostring(stats.captured), tostring(stats.submitted), tostring(stats.failed)
    lastLbl.Text = state.last ~= "" and state.last or "—"
end
function ui.refreshStatus()
    local text, col
    if not cfg.auto then text, col = "Paused", C.warn
    elseif state.hooked then text, col = "Sniper active", C.ok
    else text, col = "Manual mode", C.warn end
    pillText.Text = text
    tw(pillDot, {BackgroundColor3 = col})
end

copyLastBtn.MouseButton1Click:Connect(function()
    if state.last ~= "" and copyText(state.last) then ui.toast("Copied " .. state.last, C.ok)
    else ui.toast("Nothing to copy", C.warn) end
end)
redeemLastBtn.MouseButton1Click:Connect(function()
    if state.last == "" then ui.toast("No code yet", C.warn) return end
    task.spawn(engine.redeem, state.last)
end)

------------------------------------------------------------
-- UI : REDEEMER (manual + history)
------------------------------------------------------------
local redeemPage = newPage("Redeemer")
local codeBox = make("TextBox", {Size = UDim2.new(1, -92, 0, 34), BackgroundColor3 = C.card, Text = "", PlaceholderText = "Enter a code...",
    PlaceholderColor3 = C.sub, TextColor3 = C.text, Font = Enum.Font.Code, TextSize = 13, ClearTextOnFocus = false,
    TextXAlignment = Enum.TextXAlignment.Left, BorderSizePixel = 0}, redeemPage)
round(codeBox, 8); outline(codeBox, C.stroke, 1)
make("UIPadding", {PaddingLeft = UDim.new(0, 12)}, codeBox)
local manualBtn = button(redeemPage, "Redeem", UDim2.fromOffset(84, 34), UDim2.new(1, -84, 0, 0), true)

label(redeemPage, "HISTORY", 9, Enum.Font.GothamBold, C.sub, UDim2.fromOffset(2, 42), UDim2.new(1, 0, 0, 14))
local histScroll = make("ScrollingFrame", {Size = UDim2.new(1, 0, 1, -62), Position = UDim2.fromOffset(0, 60),
    BackgroundColor3 = C.panel, BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y}, redeemPage)
round(histScroll, 9); outline(histScroll, C.stroke, 1); reg(histScroll, "ScrollBarImageColor3")
make("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, histScroll)
make("UIPadding", {PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 8)}, histScroll)

local statusColors = {Pending = C.sub, Sent = C.ok, Failed = C.err, Rejected = C.err}
local histCount = 0
local histRows = {}
function ui.addHistory(code, status)
    histCount += 1
    local row = make("Frame", {Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = C.card, LayoutOrder = -histCount}, histScroll)
    round(row, 7)
    label(row, code, 12, Enum.Font.Code, C.text, UDim2.fromOffset(10, 0), UDim2.new(1, -150, 1, 0))
    local st = label(row, status, 10, Enum.Font.GothamBold, statusColors[status] or C.sub, UDim2.new(1, -138, 0, 0),
        UDim2.fromOffset(60, 28), Enum.TextXAlignment.Right)
    local again = button(row, "Again", UDim2.fromOffset(50, 20), UDim2.new(1, -62, 0.5, -10))
    again.TextSize = 10
    again.MouseButton1Click:Connect(function() task.spawn(engine.redeem, code) end)
    histRows[#histRows + 1] = row
    if #histRows > 60 then table.remove(histRows, 1):Destroy() end
    return {set = function(s) st.Text = s; st.TextColor3 = statusColors[s] or C.sub end}
end

manualBtn.MouseButton1Click:Connect(function()
    local t = codeBox.Text:gsub("%s", "")
    if t == "" then ui.toast("Type a code first", C.warn) return end
    state.last = t; ui.refresh()
    task.spawn(engine.redeem, t)
end)

------------------------------------------------------------
-- UI : SETTINGS
------------------------------------------------------------
local settings = newPage("Settings", true)
make("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, settings)
make("UIPadding", {PaddingRight = UDim.new(0, 6)}, settings)

makeToggle(settings, "Auto Submit", "Press submit once enough pieces are collected", cfg.autoSubmit,
    function(v) cfg.autoSubmit = v; saveCfg() end, 1)
makeToggle(settings, "Retype Invalid", "Re-paste the code if the game rejects it", cfg.retype,
    function(v) cfg.retype = v; saveCfg() end, 2)
makeToggle(settings, "Auto Copy", "Copy every captured code to your clipboard", cfg.copy,
    function(v) cfg.copy = v; saveCfg() end, 3)
makeToggle(settings, "Sound Alert", "Play a sound when a code is captured", cfg.sound,
    function(v) cfg.sound = v; saveCfg() end, 4)
makeToggle(settings, "Toast Alerts", "Small pop-ups for captures and results", cfg.toasts,
    function(v) cfg.toasts = v; saveCfg() end, 5)

-- stepper : submit after N pieces
local stepRow = make("Frame", {Size = UDim2.new(1, -6, 0, 42), BackgroundColor3 = C.card, LayoutOrder = 6}, settings)
round(stepRow, 9)
label(stepRow, "Submit After", 12, Enum.Font.GothamBold, C.text, UDim2.fromOffset(12, 6), UDim2.new(1, -120, 0, 16))
label(stepRow, "Pieces collected before submitting", 10, Enum.Font.Gotham, C.sub, UDim2.fromOffset(12, 22), UDim2.new(1, -120, 0, 14))
local minus = button(stepRow, "-", UDim2.fromOffset(24, 24), UDim2.new(1, -96, 0.5, -12))
local plus  = button(stepRow, "+", UDim2.fromOffset(24, 24), UDim2.new(1, -36, 0.5, -12))
local stepVal = label(stepRow, tostring(cfg.perCode), 13, Enum.Font.GothamBold, C.text, UDim2.new(1, -72, 0, 0),
    UDim2.fromOffset(36, 42), Enum.TextXAlignment.Center)
minus.MouseButton1Click:Connect(function() cfg.perCode = math.max(1, cfg.perCode - 1); stepVal.Text = tostring(cfg.perCode); saveCfg() end)
plus.MouseButton1Click:Connect(function() cfg.perCode += 1; stepVal.Text = tostring(cfg.perCode); saveCfg() end)

-- accent colors
local accRow = make("Frame", {Size = UDim2.new(1, -6, 0, 42), BackgroundColor3 = C.card, LayoutOrder = 7}, settings)
round(accRow, 9)
label(accRow, "Accent Color", 12, Enum.Font.GothamBold, C.text, UDim2.fromOffset(12, 0), UDim2.new(0.4, 0, 1, 0))
local swatches = make("Frame", {Size = UDim2.new(0, 150, 1, 0), Position = UDim2.new(1, -158, 0, 0), BackgroundTransparency = 1}, accRow)
make("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
    HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center}, swatches)
local swatchBtns = {}
local function markSwatch()
    for i, s in ipairs(swatchBtns) do s.stroke.Transparency = (i == cfg.accent) and 0 or 1 end
end
for i, t in ipairs(THEMES) do
    local s = make("TextButton", {Size = UDim2.fromOffset(20, 20), BackgroundColor3 = t[2], Text = "", AutoButtonColor = false,
        BorderSizePixel = 0, LayoutOrder = i}, swatches)
    round(s, 10)
    swatchBtns[i] = {btn = s, stroke = outline(s, Color3.new(1, 1, 1), 2, 1)}
    s.MouseButton1Click:Connect(function() setAccent(i); markSwatch() end)
end
markSwatch()

------------------------------------------------------------
-- UI : LOGS
------------------------------------------------------------
local logPage = newPage("Logs")
local logScroll = make("ScrollingFrame", {Size = UDim2.new(1, 0, 1, -38), BackgroundColor3 = C.panel, BorderSizePixel = 0,
    ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y}, logPage)
round(logScroll, 9); outline(logScroll, C.stroke, 1); reg(logScroll, "ScrollBarImageColor3")
local logLayout = make("UIListLayout", {Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder}, logScroll)
make("UIPadding", {PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8)}, logScroll)
local clearBtn   = button(logPage, "Clear", UDim2.new(0.5, -3, 0, 30), UDim2.new(0, 0, 1, -30))
local copyLogBtn = button(logPage, "Copy Logs", UDim2.new(0.5, -3, 0, 30), UDim2.new(0.5, 3, 1, -30), true)

local logKinds = {info = C.sub, ok = C.ok, warn = C.warn, err = C.err}
local logLines, logLabels, lastLog, logN = {}, {}, nil, 0
function ui.log(msg, kind)
    if msg == lastLog then return end
    lastLog = msg
    logN += 1
    local line = "[" .. os.date("%H:%M:%S") .. "] " .. msg
    logLines[#logLines + 1] = line
    local l = label(logScroll, line, 11, Enum.Font.Code, logKinds[kind or "info"], nil, UDim2.new(1, 0, 0, 0))
    l.AutomaticSize = Enum.AutomaticSize.Y; l.TextWrapped = true; l.TextTruncate = Enum.TextTruncate.None
    l.LayoutOrder = logN
    logLabels[#logLabels + 1] = l
    if #logLabels > 200 then table.remove(logLabels, 1):Destroy(); table.remove(logLines, 1) end
    task.defer(function() logScroll.CanvasPosition = Vector2.new(0, logLayout.AbsoluteContentSize.Y) end)
end
clearBtn.MouseButton1Click:Connect(function()
    for _, l in ipairs(logLabels) do l:Destroy() end
    logLabels, logLines, lastLog = {}, {}, nil
end)
copyLogBtn.MouseButton1Click:Connect(function()
    ui.toast(copyText(table.concat(logLines, "\n")) and "Logs copied" or "Clipboard not supported", C.ok)
end)

------------------------------------------------------------
-- UI : ABOUT
------------------------------------------------------------
local about = newPage("About")
local aboutCard = make("Frame", {Size = UDim2.new(1, -6, 1, 0), BackgroundColor3 = C.card}, about)
round(aboutCard, 9)
local aboutText = label(aboutCard,
    "NovaHub v1.0\n\nHOW TO USE?\n1. Turn on Auto Code Sniper (Dashboard).\n2. Click the game's code box once.\n3. NovaHub grabs codes from game alerts and submits them for you.\n\nNo remote found? Use the Redeemer tab to submit codes by hand.\n\nRightShift = show / hide     getgenv().NovaHubStop() = unload",
    11, Enum.Font.Gotham, C.sub, UDim2.fromOffset(14, 10), UDim2.new(1, -28, 1, -20))
aboutText.TextWrapped = true; aboutText.TextYAlignment = Enum.TextYAlignment.Top; aboutText.TextTruncate = Enum.TextTruncate.None

------------------------------------------------------------
-- UI : WINDOW BEHAVIOUR (drag / minimize / close / hotkey)
------------------------------------------------------------
do
    local dragging, dragStart, startPos, dragInput
    dragBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, input.Position, main.Position
            input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
        end
    end)
    dragBar.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
    end)
    keep(UIS.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local d = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
end

local orb = make("TextButton", {Size = UDim2.fromOffset(46, 46), BackgroundColor3 = accent, Text = "N", Font = Enum.Font.GothamBlack,
    TextSize = 20, TextColor3 = C.dark, AutoButtonColor = false, Visible = false, BorderSizePixel = 0}, gui)
round(orb, 23); reg(orb, "BackgroundColor3")

local isOpen = true
local function setOpen(open)
    if open == isOpen then return end
    isOpen = open
    if open then
        orb.Visible = false
        main.Size = UDim2.fromOffset(W, 0); main.Visible = true
        tw(main, {Size = UDim2.fromOffset(W, H)}, 0.25)
    else
        orb.Position = UDim2.fromOffset(main.AbsolutePosition.X, main.AbsolutePosition.Y)
        main.Visible = false; orb.Visible = true
    end
end
minBtn.MouseButton1Click:Connect(function() setOpen(false) end)
closeBtn.MouseButton1Click:Connect(function()
    tw(main, {Size = UDim2.fromOffset(W, 0)}, 0.2)
    task.wait(0.22)
    if env.NovaHubStop then env.NovaHubStop() end
end)
orb.MouseButton1Click:Connect(function() setOpen(true) end)
keep(UIS.InputBegan:Connect(function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.RightShift then setOpen(not isOpen) end
end))

------------------------------------------------------------
-- ENGINE : helpers
------------------------------------------------------------
local function isOwn(x)
    local y = x
    for _ = 1, 12 do
        if not y then break end
        if y.Name == "NovaHub" then return true end
        y = y.Parent
    end
    return false
end

local function isShown(x)
    local y = x
    while y do
        if y:IsA("GuiObject") and not y.Visible then return false end
        if y:IsA("ScreenGui") then return y.Enabled end
        y = y.Parent
    end
    return true
end

local function collectBoxes(pg)
    local r = {}
    for _, g in ipairs(pg:GetChildren()) do
        if g:IsA("ScreenGui") and g.Enabled and not isOwn(g) then
            for _, d in ipairs(g:GetDescendants()) do
                if d:IsA("TextBox") and not isOwn(d) then r[#r + 1] = d end
            end
        end
    end
    return r
end

local function collectCodeButtons(pg)
    local r = {}
    for _, g in ipairs(pg:GetChildren()) do
        if g:IsA("ScreenGui") and g.Enabled and not isOwn(g) then
            for _, d in ipairs(g:GetDescendants()) do
                if (d:IsA("TextButton") or d:IsA("ImageButton")) and not isOwn(d) then
                    local n = d.Name:lower()
                    local pn = (d.Parent and d.Parent.Name or ""):lower()
                    if (n:find("code") or n:find("redeem") or pn:find("code") or pn:find("redeem")) and isShown(d) then
                        r[#r + 1] = d
                    end
                end
            end
        end
    end
    return r
end

local function findCodeBox()
    for _, b in ipairs(collectBoxes(playerGui)) do
        if isShown(b) then return b end
    end
    return nil
end

local function pressButton(b)
    if not b then return false end
    local fns = {}
    if typeof(firesignal) == "function" then
        fns[#fns + 1] = function() firesignal(b.MouseButton1Click) end
        fns[#fns + 1] = function() firesignal(b.Activated) end
    end
    if typeof(getConns) == "function" then
        fns[#fns + 1] = function()
            for _, sig in ipairs({b.MouseButton1Click, b.Activated}) do
                local ok, cs = pcall(getConns, sig)
                if ok and type(cs) == "table" then
                    for _, c in ipairs(cs) do pcall(function() c:Fire() end) end
                end
            end
        end
    end
    if typeof(fireclick) == "function" then fns[#fns + 1] = function() fireclick(b) end end
    local any = false
    for _, f in ipairs(fns) do
        local ok = pcall(f)
        any = any or ok
    end
    return any
end

local function fireFocusLost(box)
    if not box then return false end
    local any = false
    if typeof(firesignal) == "function" then
        local ok = pcall(firesignal, box.FocusLost, true)
        any = any or ok
    end
    if typeof(getConns) == "function" then
        local ok, cs = pcall(getConns, box.FocusLost)
        if ok and type(cs) == "table" then
            for _, c in ipairs(cs) do
                local f
                pcall(function() f = c.Function end)
                if f and typeof(getUps) == "function" and typeof(setUp) == "function" then
                    local uok, ups = pcall(getUps, f)
                    if uok and type(ups) == "table" then
                        for i, v in pairs(ups) do
                            if v == true then pcall(setUp, f, i, false) end
                        end
                    end
                end
                local fok = pcall(function() if c.Enabled ~= false then c:Fire(true) end end)
                any = any or fok
            end
        end
    end
    return any
end

local SUBMIT_WORDS = {"submit", "redeem", "claim", "confirm", "enter", "send", "apply", "ok", "use", "go", "check"}

local function submitCode(code)
    local pg = playerGui
    -- path 1 : PlayerGui.Codes
    local cg = pg:FindFirstChild("Codes")
    if cg then
        if cg:IsA("ScreenGui") then cg.Enabled = true end
        local cf = cg:FindFirstChild("Codes") or cg
        if cf:IsA("GuiObject") then cf.Visible = true end
        local cur = cf
        while cur and cur ~= cg do
            if cur:IsA("GuiObject") then cur.Visible = true end
            cur = cur.Parent
        end
        local box, btn
        for _, d in ipairs(cf:GetDescendants()) do
            if d:IsA("TextBox") and not isOwn(d) then box = d break end
        end
        for _, d in ipairs(cf:GetDescendants()) do
            if (d:IsA("TextButton") or d:IsA("ImageButton")) and not isOwn(d) then
                local n, t = d.Name:lower(), ""
                pcall(function() t = d.Text:lower() end)
                if n:find("submit") or t:find("submit") or n:find("redeem") or t:find("redeem")
                    or n:find("claim") or t:find("confirm") or n:find("enter") then btn = d break end
            end
        end
        if not btn then
            for _, d in ipairs(cf:GetDescendants()) do
                if (d:IsA("TextButton") or d:IsA("ImageButton")) and not isOwn(d) then
                    local n = d.Name:lower()
                    if not n:find("close") and n ~= "x" and not n:find("toggle") then btn = d break end
                end
            end
        end
        if box then
            pcall(function() box.Text = code end)
            task.wait(0.05)
            if btn then pressButton(btn) end
            fireFocusLost(box)
            return true, "Codes menu"
        end
    end

    -- path 2 : open the code UI, then search dynamically
    for _, b in ipairs(collectCodeButtons(pg)) do pressButton(b); task.wait(0.05) end
    task.wait(0.2)
    local box
    local deadline = os.clock() + 2
    while os.clock() < deadline and not box do
        local all = collectBoxes(pg)
        for _, d in ipairs(all) do
            if isShown(d) then
                local n = d.Name:lower()
                local pn = (d.Parent and d.Parent.Name or ""):lower()
                if n:find("code") or pn:find("code") or n:find("redeem") or pn:find("redeem")
                    or n:find("input") or pn:find("textbox") or n:find("enter") then box = d break end
            end
        end
        if not box then
            for _, d in ipairs(all) do if isShown(d) then box = d break end end
        end
        if not box then task.wait(0.1) end
    end
    if not box then return false, "no code box visible" end
    pcall(function() box.Text = code end)
    task.wait(0.05)
    local btn
    local p = box.Parent
    for _ = 1, 8 do
        if not p or btn then break end
        for _, d in ipairs(p:GetDescendants()) do
            if (d:IsA("TextButton") or d:IsA("ImageButton")) and not isOwn(d) and d ~= box then
                local n, t = d.Name:lower(), ""
                pcall(function() t = d.Text:lower() end)
                for _, w in ipairs(SUBMIT_WORDS) do
                    if (n:find(w) or t:find(w)) and isShown(d) then btn = d break end
                end
                if btn then break end
            end
        end
        p = p.Parent
    end
    if btn then pressButton(btn) end
    fireFocusLost(box)
    return true, "dynamic search"
end

------------------------------------------------------------
-- ENGINE : tracking, retype, capture
------------------------------------------------------------
local track   = {box = nil, c1 = nil, c2 = nil, text = ""}
local pieces  = {}
local pending = nil -- {text, box, expires, entry}
local recent  = {}

local REJECT = {"invalid code", "code is invalid", "expired", "already redeemed", "already used",
    "doesn't exist", "does not exist", "not found", "rejected"}

local function untrack()
    if track.c1 then pcall(function() track.c1:Disconnect() end) end
    if track.c2 then pcall(function() track.c2:Disconnect() end) end
    track.box, track.c1, track.c2 = nil, nil, nil
end

local function trackBox(box)
    if not box or track.box == box then return end
    untrack()
    track.box = box
    if box.Text ~= "" then track.text = box.Text end
    track.c1 = box:GetPropertyChangedSignal("Text"):Connect(function()
        if box.Text == "" then pieces = {} else track.text = box.Text end
    end)
    track.c2 = box.AncestryChanged:Connect(function(_, parent)
        if not parent then pieces = {}; untrack() end
    end)
end

local function repaste(box, text)
    if not text or text == "" then return false end
    RunService.Heartbeat:Wait()
    local cb = findCodeBox() or box
    if not cb or not isShown(cb) then return false end
    local ok = pcall(function() cb.Text = text end)
    if ok then trackBox(cb) end
    return ok
end

local function onTextSeen(text, obj)
    if not alive or not pending then return end
    if os.clock() > pending.expires then pending = nil return end
    if obj and isOwn(obj) then return end
    local l = tostring(text or ""):lower()
    local rejected = false
    for _, p in ipairs(REJECT) do
        if l:find(p, 1, true) then rejected = true break end
    end
    if not rejected then return end
    local p = pending
    pending = nil
    stats.failed += 1
    if p.entry then p.entry.set("Rejected") end
    ui.refresh()
    ui.log("Rejected: " .. p.text, "warn")
    ui.toast("Rejected: " .. p.text, C.err)
    if cfg.retype and repaste(p.box, p.text) then ui.log("Re-pasted: " .. p.text, "info") end
end

function engine.redeem(code)
    if not code or code == "" then return end
    local entry = ui.addHistory(code, "Pending")
    local ok, msg = submitCode(code)
    if ok then
        stats.submitted += 1
        entry.set("Sent")
        pending = {text = code, box = findCodeBox(), expires = os.clock() + 8, entry = entry}
        ui.log("Submitted " .. code .. " (" .. msg .. ")", "ok")
        ui.toast("Submitted " .. code, C.ok)
    else
        stats.failed += 1
        entry.set("Failed")
        local rs = cfg.retype and repaste(findCodeBox(), code)
        ui.log("Failed: " .. tostring(msg) .. (rs and " (re-pasted)" or ""), "err")
        ui.toast("Failed: " .. tostring(msg), C.err)
    end
    ui.refresh()
end

local sound
pcall(function()
    sound = make("Sound", {SoundId = "rbxassetid://4590657391", Volume = 0.6}, gui)
end)

local function handleCaptured(code)
    if not cfg.auto then return end
    if track.box and not isShown(track.box) then pieces = {}; untrack() end

    stats.captured += 1
    pieces[#pieces + 1] = code
    local combined = table.concat(pieces)
    local n = #pieces
    state.last = combined

    local box = findCodeBox()
    if box then
        trackBox(box)
        box.Text = combined
        if UIS:GetFocusedTextBox() == box then
            pcall(function() local c = #combined + 1; box.CursorPosition = c; box.SelectionStart = c end)
        end
    else
        ui.log("Captured; open the game's code UI", "warn")
    end

    ui.log(("Captured %s  (%d/%d)"):format(code, n, cfg.perCode), "ok")
    ui.toast("Captured: " .. code)
    if cfg.copy then copyText(combined) end
    if cfg.sound and sound then pcall(function() sound:Play() end) end
    ui.refresh()

    if n >= cfg.perCode then
        pieces = {}
        if cfg.autoSubmit then task.spawn(engine.redeem, combined) end
    end
end

local function onNotification(...)
    if not alive or not cfg.auto then return end
    local raw = ...
    local text = tostring(raw or "")
    text = text:gsub("<[^>]->", "")
    text = text:match("^%s*(.-)%s*$") or ""
    if text == "" or text:find("%s") then return end
    local code = text:match("[%w_]+")
    if not code or recent[code] then return end
    recent[code] = true
    task.delay(1.25, function() recent[code] = nil end)
    handleCaptured(code)
end

------------------------------------------------------------
-- ENGINE : hooks
------------------------------------------------------------
keep(UIS.TextBoxFocused:Connect(function(box)
    if isOwn(box) or box ~= findCodeBox() then return end
    trackBox(box)
    if cfg.auto then ui.log("Code box linked", "info") end
end))

keep(UIS.TextBoxFocusReleased:Connect(function(box)
    if isOwn(box) then return end
    local cb = findCodeBox()
    if box ~= cb and box ~= track.box then return end
    if cfg.retype then
        local text = box.Text ~= "" and box.Text or track.text
        if text ~= "" and not (pending and os.clock() <= pending.expires) then
            pending = {text = text, box = box, expires = os.clock() + 8}
        end
    end
end))

local function watchText(obj)
    if not (obj:IsA("TextLabel") or obj:IsA("TextButton")) or isOwn(obj) then return end
    onTextSeen(obj.Text, obj)
    obj:GetPropertyChangedSignal("Text"):Connect(function() onTextSeen(obj.Text, obj) end)
end
for _, obj in ipairs(playerGui:GetDescendants()) do watchText(obj) end
keep(playerGui.DescendantAdded:Connect(function(obj) task.wait(0.04) watchText(obj) end))

-- find the game's notification remote (runs in its own thread so the UI never waits)
task.spawn(function()
    local remote = env.PhiNotifyRemote
    if not remote then
        local packages = RS:WaitForChild("Packages", 10)
        local net = packages and packages:WaitForChild("Net", 10)
        local info = (debug and debug.getinfo) or getinfo
        if net and info and getConns then
            for _, d in ipairs(net:GetDescendants()) do
                if d:IsA("RemoteEvent") then
                    local ok, cs = pcall(getConns, d.OnClientEvent)
                    if ok and type(cs) == "table" then
                        for _, c in ipairs(cs) do
                            local fok, fn = pcall(function() return c.Function end)
                            if fok and type(fn) == "function" then
                                local iok, inf = pcall(info, fn)
                                if iok and tostring(inf.short_src or inf.source or ""):find("NotificationController", 1, true) then
                                    remote = d
                                    break
                                end
                            end
                        end
                    end
                end
                if remote then break end
            end
        end
    end
    if not alive then return end
    if remote then
        state.hooked = true
        if env.NovaHubNotifyConn then pcall(function() env.NovaHubNotifyConn:Disconnect() end) end
        env.NovaHubNotifyConn = keep(remote.OnClientEvent:Connect(function(...) pcall(onNotification, ...) end))
        ui.log("Notification remote hooked", "ok")
        ui.toast("NovaHub ready", C.ok)
    else
        ui.log("No notification remote found - use the Redeemer tab", "warn")
        ui.toast("Manual mode (no remote found)", C.warn)
    end
    ui.refreshStatus()
end)

-- animation + uptime
local acc = 0
keep(RunService.Heartbeat:Connect(function(dt)
    for _, g in ipairs(gradObjs) do g.Rotation = (g.Rotation + 60 * dt) % 360 end
    acc += dt
    if acc >= 1 then
        acc = 0
        local s = math.floor(os.clock() - state.start)
        local h, m = math.floor(s / 3600), math.floor(s / 60) % 60
        timeLbl.Text = h > 0 and string.format("%d:%02d:%02d", h, m, s % 60) or string.format("%02d:%02d", m, s % 60)
    end
end))

------------------------------------------------------------
-- START / STOP
------------------------------------------------------------
env.NovaHubStop = function()
    alive = false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    untrack()
    if gui then gui:Destroy() end
    env.NovaHubStop = nil
end

showPage("Dashboard")
ui.refresh()
ui.refreshStatus()
ui.log("NovaHub loaded", "ok")
ui.toast("NovaHub loaded", accent)
main.Size = UDim2.fromOffset(W, 0)
tw(main, {Size = UDim2.fromOffset(W, H)}, 0.35)
