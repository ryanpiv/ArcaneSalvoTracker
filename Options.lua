local ADDON, ns = ...

--------------------------------------------------------------------
-- Arcane Salvo Tracker — Options
-- Standalone draggable, scrollable config window (/ast).
-- Widgets are hand-built rather than templated where Blizzard's
-- templates have churned between patches (sliders, dropdowns).
--------------------------------------------------------------------

local db
local frame, scrollChild
local fontPicker
local refreshers = {}     -- closures that push db values into widgets

local PANEL_W, PANEL_H = 400, 620
local CONTENT_W = PANEL_W - 60
local cursorY = -8        -- running y offset inside the scroll child

local function RefreshControls()
    for _, fn in ipairs(refreshers) do fn() end
end

--------------------------------------------------------------------
-- Change plumbing
--------------------------------------------------------------------

-- Cheap visual changes (geometry, fonts, toggles).
local function Refresh()
    ns.Refresh()
end

-- Changes baked into the client-side color map (colors, breakpoint,
-- max stacks) need the aura container rebuilt; Bar.lua debounces and
-- queues this if the player is in combat.
local function RefreshAndRebuild()
    ns.Refresh()
    ns.RequestRebuild()
end

--------------------------------------------------------------------
-- Widget factories
--------------------------------------------------------------------

local function Place(widget, height, gap)
    widget:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 8, cursorY)
    cursorY = cursorY - height - (gap or 6)
end

local function MakeHeader(text)
    local fs = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetText(text)
    fs:SetTextColor(0.8, 0.55, 1)
    Place(fs, 18, 6)
    return fs
end

local function MakeSlider(label, minV, maxV, step, get, set, fmt)
    local holder = CreateFrame("Frame", nil, scrollChild)
    holder:SetSize(CONTENT_W, 32)

    local title = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT")
    title:SetText(label)
    local valText = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valText:SetPoint("TOPRIGHT")

    local slider = CreateFrame("Slider", nil, holder)
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("BOTTOMLEFT", 0, 2)
    slider:SetPoint("BOTTOMRIGHT", 0, 2)
    slider:SetHeight(14)
    slider:EnableMouse(true)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(3)
    track:SetColorTexture(1, 1, 1, 0.15)

    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(10, 14)
    thumb:SetColorTexture(0.8, 0.55, 1, 0.95)
    slider:SetThumbTexture(thumb)

    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    local function Display(v)
        valText:SetText(fmt and fmt:format(v) or tostring(math.floor(v + 0.5)))
    end

    local settingUp = false
    slider:SetScript("OnValueChanged", function(_, v)
        -- Snap to step to avoid float noise
        v = math.floor(v / step + 0.5) * step
        Display(v)
        if not settingUp then set(v) end
    end)

    refreshers[#refreshers + 1] = function()
        settingUp = true
        local v = get()
        slider:SetMinMaxValues(minV, maxV)
        slider:SetValue(v)
        Display(v)
        settingUp = false
    end

    Place(holder, 32, 10)
    return slider
end

local function MakeCheck(label, get, set)
    local cb = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    text:SetText(label)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
    end)
    refreshers[#refreshers + 1] = function()
        cb:SetChecked(get())
    end
    Place(cb, 22, 2)
    return cb
end

local function ShowColorPicker(get, set)
    local r, g, b, a = get()
    local function OnChange()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        local na = a
        if ColorPickerFrame.GetColorAlpha then
            na = ColorPickerFrame:GetColorAlpha()
        end
        set(nr, ng, nb, na)
    end
    local info = {
        r = r, g = g, b = b,
        opacity = a,
        hasOpacity = true,
        swatchFunc = OnChange,
        opacityFunc = OnChange,
        cancelFunc = function(prev)
            if prev then
                set(prev.r or r, prev.g or g, prev.b or b, prev.opacity or a)
            end
        end,
    }
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow(info)
    else
        -- Legacy path for older clients
        ColorPickerFrame.func = OnChange
        ColorPickerFrame.opacityFunc = OnChange
        ColorPickerFrame.cancelFunc = info.cancelFunc
        ColorPickerFrame.hasOpacity = true
        ColorPickerFrame.opacity = a
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Show()
    end
end

local function MakeSwatch(label, colorKey, needsRebuild)
    local btn = CreateFrame("Button", nil, scrollChild)
    btn:SetSize(CONTENT_W, 20)

    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetSize(18, 18)
    border:SetPoint("LEFT")
    border:SetColorTexture(0.9, 0.9, 0.9, 0.9)
    local box = btn:CreateTexture(nil, "ARTWORK")
    box:SetSize(14, 14)
    box:SetPoint("CENTER", border, "CENTER")

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", border, "RIGHT", 6, 0)
    text:SetText(label)

    local function Paint()
        local c = db.colors[colorKey]
        box:SetColorTexture(c[1], c[2], c[3], 1)
    end

    btn:SetScript("OnClick", function()
        ShowColorPicker(
            function()
                local c = db.colors[colorKey]
                return c[1], c[2], c[3], c[4] or 1
            end,
            function(r, g, b, a)
                db.colors[colorKey] = { r, g, b, a }
                Paint()
                if needsRebuild then RefreshAndRebuild() else Refresh() end
            end)
    end)

    refreshers[#refreshers + 1] = Paint
    Place(btn, 20, 4)
    return btn
end

local function MakeButton(label, width, onClick)
    local btn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    btn:SetSize(width, 22)
    btn:SetText(label)
    btn:SetScript("OnClick", onClick)
    return btn
end

--------------------------------------------------------------------
-- Font picker (self-contained scroll list; each row in its own font)
--------------------------------------------------------------------

local function BuildFontPicker(anchorBtn)
    fontPicker = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    fontPicker:SetFrameStrata("FULLSCREEN_DIALOG")
    fontPicker:SetSize(240, 220)
    fontPicker:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
    fontPicker:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 32, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })

    local scroll = CreateFrame("ScrollFrame", nil, fontPicker, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(200, 10)
    scroll:SetScrollChild(child)
    fontPicker.child = child
    fontPicker.rows = {}
end

local function PopulateFontPicker()
    local child = fontPicker.child
    local fonts = ns.GetFontList()
    local y = 0
    for i, name in ipairs(fonts) do
        local row = fontPicker.rows[i]
        if not row then
            row = CreateFrame("Button", nil, child)
            row:SetSize(200, 18)
            row.text = row:CreateFontString(nil, "OVERLAY")
            row.text:SetPoint("LEFT", 2, 0)
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(0.8, 0.55, 1, 0.2)
            fontPicker.rows[i] = row
        end
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
        row.text:SetFont(ns.ResolveFont(name), 12, "")
        row.text:SetText(name)
        row.text:SetTextColor(1, 1, 1)
        row:SetScript("OnClick", function()
            db.fontName = name
            fontPicker:Hide()
            RefreshControls()
            Refresh()
        end)
        row:Show()
        y = y - 18
    end
    for i = #fonts + 1, #fontPicker.rows do
        fontPicker.rows[i]:Hide()
    end
    child:SetHeight(-y)
end

--------------------------------------------------------------------
-- Window construction
--------------------------------------------------------------------

local function Build()
    frame = CreateFrame("Frame", "ArcaneSalvoTrackerOptionsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(PANEL_W, PANEL_H)
    frame:SetPoint("CENTER", UIParent, "CENTER", 240, 20)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    tinsert(UISpecialFrames, "ArcaneSalvoTrackerOptionsFrame")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Arcane Salvo Tracker")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -36)
    scroll:SetPoint("BOTTOMRIGHT", -30, 12)
    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(CONTENT_W + 16, 10)
    scroll:SetScrollChild(scrollChild)

    ----------------------------------------------------------------
    -- Live preview
    ----------------------------------------------------------------
    MakeHeader("Live preview")

    local note = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetWidth(CONTENT_W)
    note:SetJustifyH("LEFT")
    note:SetText("While this window is open, the bar shows a simulated stack count. The real bar only fills while the Arcane Salvo buff is active.")
    Place(note, 30, 8)

    ns.previewSetting = ns.previewSetting or 0
    MakeSlider("Preview stacks", 0, 40, 1,
        function() return ns.previewSetting end,
        function(v)
            ns.previewSetting = v
            if frame:IsShown() then ns.SetPreviewStacks(v) end
        end)

    ----------------------------------------------------------------
    -- Size and position
    ----------------------------------------------------------------
    MakeHeader("Size and position")

    MakeSlider("Width", 100, 600, 5,
        function() return db.width end,
        function(v) db.width = v; Refresh() end)
    MakeSlider("Height", 10, 60, 1,
        function() return db.height end,
        function(v) db.height = v; Refresh() end)
    MakeSlider("Scale", 0.5, 2, 0.05,
        function() return db.scale end,
        function(v) db.scale = v; Refresh() end, "%.2f")

    MakeCheck("Lock bar (drag with left mouse while unlocked)",
        function() return db.locked end,
        function(v) db.locked = v; ns.UpdateMouse() end)

    local resetBtn = MakeButton("Reset position", 120, function()
        db.point = { unpack(ns.defaults.point) }
        Refresh()
    end)
    Place(resetBtn, 22, 10)

    ----------------------------------------------------------------
    -- Stacks
    ----------------------------------------------------------------
    MakeHeader("Stacks")

    local presetRow = CreateFrame("Frame", nil, scrollChild)
    presetRow:SetSize(CONTENT_W, 22)
    local sunfury = CreateFrame("Button", nil, presetRow, "UIPanelButtonTemplate")
    sunfury:SetSize(160, 22)
    sunfury:SetPoint("LEFT")
    sunfury:SetText("Sunfury (25 / 12)")
    local slinger = CreateFrame("Button", nil, presetRow, "UIPanelButtonTemplate")
    slinger:SetSize(160, 22)
    slinger:SetPoint("LEFT", sunfury, "RIGHT", 8, 0)
    slinger:SetText("Spellslinger (20 / 15)")
    local function ApplyPreset(preset)
        db.maxStacks = preset.maxStacks
        db.breakpoint = preset.breakpoint
        RefreshControls()
        RefreshAndRebuild()
    end
    sunfury:SetScript("OnClick", function() ApplyPreset(ns.presets.sunfury) end)
    slinger:SetScript("OnClick", function() ApplyPreset(ns.presets.spellslinger) end)
    Place(presetRow, 22, 10)

    MakeSlider("Breakpoint marker", 0, 40, 1,
        function() return db.breakpoint end,
        function(v) db.breakpoint = v; RefreshAndRebuild() end)
    MakeSlider("Max stacks", 5, 40, 1,
        function() return db.maxStacks end,
        function(v) db.maxStacks = v; RefreshAndRebuild() end)
    MakeSlider("Second marker (0 = off)", 0, 40, 1,
        function() return db.secondMarker end,
        function(v) db.secondMarker = v; Refresh() end)

    ----------------------------------------------------------------
    -- Colors
    ----------------------------------------------------------------
    MakeHeader("Colors")

    MakeSwatch("Bar color", "normal", true)
    MakeSwatch("Bar at breakpoint", "breakpoint", true)
    MakeSwatch("Bar at max stacks", "max", true)
    MakeSwatch("Background", "background", false)
    MakeSwatch("Stack count text", "text", false)
    MakeSwatch("Marker ticks", "tick", false)

    ----------------------------------------------------------------
    -- Text
    ----------------------------------------------------------------
    MakeHeader("Text")

    local fontRow = CreateFrame("Frame", nil, scrollChild)
    fontRow:SetSize(CONTENT_W, 22)
    local fontLabel = fontRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fontLabel:SetPoint("LEFT")
    fontLabel:SetText("Font")
    local fontBtn = CreateFrame("Button", nil, fontRow, "UIPanelButtonTemplate")
    fontBtn:SetSize(220, 22)
    fontBtn:SetPoint("LEFT", fontLabel, "RIGHT", 12, 0)
    fontBtn:SetScript("OnClick", function(self)
        if not fontPicker then BuildFontPicker(self) end
        if fontPicker:IsShown() then
            fontPicker:Hide()
        else
            PopulateFontPicker()
            fontPicker:Show()
        end
    end)
    refreshers[#refreshers + 1] = function()
        fontBtn:SetText(db.fontName)
    end
    Place(fontRow, 22, 8)

    MakeSlider("Font size", 8, 24, 1,
        function() return db.fontSize end,
        function(v) db.fontSize = v; Refresh() end)

    MakeCheck("Font outline",
        function() return db.fontOutline end,
        function(v) db.fontOutline = v; Refresh() end)
    MakeCheck("Show \"Arcane Salvo\" label",
        function() return db.showLabel end,
        function(v) db.showLabel = v; Refresh() end)
    MakeCheck("Show marker numbers above the bar",
        function() return db.showMarkerNumbers end,
        function(v) db.showMarkerNumbers = v; Refresh() end)

    ----------------------------------------------------------------
    -- Visibility
    ----------------------------------------------------------------
    MakeHeader("Visibility")

    MakeCheck("Show spell icon",
        function() return db.showIcon end,
        function(v) db.showIcon = v; Refresh() end)
    MakeCheck("Only show in combat",
        function() return db.combatOnly end,
        function(v) db.combatOnly = v; Refresh() end)
    MakeCheck("Reveal on mouseover while hidden (out of combat)",
        function() return db.hoverReveal end,
        function(v) db.hoverReveal = v; Refresh() end)
    MakeCheck("Show on all mage specs",
        function() return db.allSpecs end,
        function(v) db.allSpecs = v; Refresh() end)

    ----------------------------------------------------------------
    -- Defaults
    ----------------------------------------------------------------
    cursorY = cursorY - 6
    local defaultsBtn = MakeButton("Restore defaults", 140, function()
        local keepID = db.spellID
        for k in pairs(db) do db[k] = nil end
        ns.CopyDefaults(db, ns.defaults)
        db.spellID = keepID
        RefreshControls()
        RefreshAndRebuild()
        ns.Print("Settings restored to defaults.")
    end)
    Place(defaultsBtn, 22, 12)

    scrollChild:SetHeight(-cursorY + 20)

    frame:SetScript("OnShow", function()
        ns.optionsOpen = true
        if ns.previewSetting == 0 then
            ns.previewSetting = db.maxStacks
        end
        RefreshControls()
        ns.SetPreviewStacks(ns.previewSetting)
        ns.UpdateVisibility()
        ns.UpdateMouse()
    end)
    frame:SetScript("OnHide", function()
        ns.optionsOpen = false
        if fontPicker then fontPicker:Hide() end
        ns.SetPreviewStacks(nil)
        ns.UpdateVisibility()
        ns.UpdateMouse()
    end)
end

function ns.ToggleOptions()
    if not ns.db or not ns.isMage then return end
    db = ns.db
    if not frame then Build() end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end
