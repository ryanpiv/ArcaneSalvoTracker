local _, ns = ...

--------------------------------------------------------------------
-- Arcane Salvo Tracker — Bar
--
-- The bar is built on the AuraContainer API: the addon supplies a
-- StatusBar and a FontString, and the game client fills in the live
-- aura data. That is the only way the bar can update while stack
-- counts are secret in combat — which also means color-by-stack has
-- to be handed to the client up front as a color map rather than
-- computed by the addon.
--------------------------------------------------------------------

local db

local root, bg, overlay, container
local iconTex, labelFS
local slotFrame
local slotWidgets = {}          -- widgets created inside the aura slot
local marks = {}                -- breakpoint/second-marker/cap widgets
local previewBar, previewFS

ns.errors = {}
local function log(fmt, ...)
    ns.errors[#ns.errors + 1] = select("#", ...) > 0 and fmt:format(...) or fmt
end

local FALLBACK_ICON = "Interface\\Icons\\inv12_ability_mage_arcanesalvo"

--------------------------------------------------------------------
-- Fonts (LibSharedMedia when present, WoW built-ins otherwise)
--------------------------------------------------------------------

local BUILTIN_FONTS = {
    ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
    ["Arial Narrow"]     = "Fonts\\ARIALN.TTF",
    ["Skurri"]           = "Fonts\\skurri.ttf",
    ["Morpheus"]         = "Fonts\\MORPHEUS.ttf",
}

local function LSM()
    return LibStub and LibStub.GetLibrary
        and LibStub:GetLibrary("LibSharedMedia-3.0", true) or nil
end

function ns.GetFontList()
    local lsm = LSM()
    if lsm then
        local names = {}
        for _, name in ipairs(lsm:List("font")) do names[#names + 1] = name end
        table.sort(names)
        return names
    end
    local names = {}
    for name in pairs(BUILTIN_FONTS) do names[#names + 1] = name end
    table.sort(names)
    return names
end

function ns.ResolveFont(name)
    local lsm = LSM()
    local path = lsm and lsm:Fetch("font", name, true)
    return path or BUILTIN_FONTS[name] or BUILTIN_FONTS["Friz Quadrata TT"]
end

local function ApplyFont(fs, sizeDelta)
    fs:SetFont(ns.ResolveFont(db.fontName),
        math.max(6, db.fontSize + (sizeDelta or 0)),
        db.fontOutline and "OUTLINE" or "")
end

--------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------

local function ColorOf(key)
    local c = db.colors[key]
    return c[1], c[2], c[3], c[4] or 1
end

-- Preview-side color logic; the in-combat equivalent lives in the
-- colorMap handed to the client.
local function ColorForStacks(n)
    if n >= db.maxStacks then return db.colors.max end
    if db.breakpoint > 0 and n >= db.breakpoint then return db.colors.breakpoint end
    return db.colors.normal
end

local function SpellIconTexture()
    local id = db.spellID or ns.SALVO_CANDIDATES[1]
    local tex
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, result = pcall(C_Spell.GetSpellTexture, id)
        if ok then tex = result end
    end
    return tex or FALLBACK_ICON
end

local function InCombat()
    return InCombatLockdown() or UnitAffectingCombat("player")
end

--------------------------------------------------------------------
-- AuraContainer: color map + slot initialization
--------------------------------------------------------------------

local function BuildColorMap()
    local map, stops = {}, {}
    local function add(at, c)
        local color = CreateColor(c[1], c[2], c[3], c[4] or 1)
        map[at] = color
        stops[#stops + 1] = { applications = at, color = color }
    end
    add(1, db.colors.normal)
    if db.breakpoint > 1 and db.breakpoint < db.maxStacks then
        add(db.breakpoint, db.colors.breakpoint)
    end
    if db.maxStacks > 1 then
        add(db.maxStacks, db.colors.max)
    end
    return map, stops
end

local function ApplyApplicationBar(btn, bar)
    local map, stops = BuildColorMap()
    -- SetApplicationBar's color options are undocumented; try the
    -- likeliest forms in order and keep whichever the client accepts.
    local attempts = {
        { "colorMap",   { maxApplications = db.maxStacks, colorMap = map } },
        { "colorCurve", { maxApplications = db.maxStacks, colorCurve = stops } },
        { "colors",     { maxApplications = db.maxStacks, colors = map } },
        { "plain",      { maxApplications = db.maxStacks } },
    }
    local util = C_AuraContainerUtil
    for _, attempt in ipairs(attempts) do
        local mode, opts = attempt[1], attempt[2]
        local valid = true
        if util and type(util.ProcessCustomAuraButtonApplicationBarOptions) == "function" then
            valid = pcall(util.ProcessCustomAuraButtonApplicationBarOptions, opts)
        end
        if valid and pcall(btn.SetApplicationBar, btn, bar, opts) then
            ns.barColorMode = mode
            return true
        end
    end
    ns.barColorMode = "failed"
    log("SetApplicationBar rejected every option form")
    return false
end

-- Aura buttons take mouse input by default (the client wires them for
-- tooltips), and the slot covers the whole bar — which would swallow
-- the drag and right-click meant for the movable root underneath.
-- The bar needs no tooltip, so make the slot fully click-through.
local function MakeClickThrough(frame)
    pcall(frame.EnableMouse, frame, false)
    pcall(frame.SetMouseClickEnabled, frame, false)
    pcall(frame.SetMouseMotionEnabled, frame, false)
end

local function InitSalvoSlot(btn)
    btn:SetSize(db.width, db.height)
    MakeClickThrough(btn)

    local bar = CreateFrame("StatusBar", nil, btn)
    bar:SetAllPoints(btn)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetColorTexture(1, 1, 1, 1)
    bar:SetStatusBarTexture(fill)
    -- Baseline color in case no color map form is accepted.
    bar:SetStatusBarColor(ColorOf("normal"))

    ApplyApplicationBar(btn, bar)

    local count = btn:CreateFontString(nil, "OVERLAY")
    ApplyFont(count)
    count:SetPoint("CENTER", btn, "CENTER", 0, 0)
    count:SetTextColor(ColorOf("text"))
    if not pcall(btn.SetApplicationCount, btn, count, {}) then
        log("SetApplicationCount rejected")
    end

    slotWidgets.btn, slotWidgets.bar, slotWidgets.count = btn, bar, count
end

-- The container decides slot parentage internally; if the slot did
-- not end up under our (scaled) root, mirror the scale onto it.
local function IsDescendantOf(frame, ancestor)
    local p = frame and frame:GetParent()
    while p do
        if p == ancestor then return true end
        p = p:GetParent()
    end
    return false
end

local function ApplySlotScale()
    if not slotFrame then return end
    pcall(function()
        slotFrame:SetScale(IsDescendantOf(slotFrame, root) and 1 or (db.scale or 1))
    end)
end

function ns.BuildContainer()
    if not root then return end
    if InCombat() then
        ns.pendingRebuild = true
        return
    end

    if container then
        container:Hide()
        container:SetParent(nil)
        container = nil
        slotFrame = nil
        wipe(slotWidgets)
    end
    wipe(ns.errors)
    ns.barColorMode = nil

    local ok, c = pcall(CreateFrame, "AuraContainer", nil, root, "CustomAuraContainerTemplate")
    if not ok or not c then
        log("AuraContainer creation failed: %s", tostring(c))
        return
    end
    container = c
    container:SetSize(1, 1)
    container:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
    if not pcall(container.SetUnit, container, "player") then
        log("AuraContainer SetUnit failed")
    end

    -- A single-ID filter is the only form confirmed to work against the
    -- live client; multi-ID tables are unverified. Resolve() corrects
    -- db.spellID if the primary candidate is ever wrong.
    local include = { [db.spellID or ns.SALVO_CANDIDATES[1]] = true }

    local okAdd, slot = pcall(container.AddAuraSlot, container, "salvo", "HELPFUL|PLAYER", {
        candidateFilters = { includeSpellIDs = include },
        initializeFrame  = InitSalvoSlot,
    })
    if not okAdd or type(slot) ~= "table" or not slot.SetPoint then
        log("AddAuraSlot failed: %s", tostring(slot))
        return
    end
    slotFrame = slot
    pcall(function()
        slot:ClearAllPoints()
        slot:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
    end)
    MakeClickThrough(slot)
    MakeClickThrough(container)
    ApplySlotScale()

    -- Stacking order: client fill < preview < overlay (icon/label/ticks)
    overlay:SetFrameLevel(container:GetFrameLevel() + 10)
    if previewBar then
        previewBar:SetFrameLevel(container:GetFrameLevel() + 9)
    end
end

-- Debounced rebuild for slider-driven changes; queued while in combat.
local rebuildQueued = false
function ns.RequestRebuild()
    if rebuildQueued then return end
    rebuildQueued = true
    C_Timer.After(0.25, function()
        rebuildQueued = false
        ns.BuildContainer()
        ns.Refresh()
    end)
end

--------------------------------------------------------------------
-- Marker ticks (breakpoint, optional second marker, cap number)
--------------------------------------------------------------------

local function GetMark(i)
    local m = marks[i]
    if not m then
        m = {}
        m.tick = overlay:CreateTexture(nil, "OVERLAY")
        m.num = overlay:CreateFontString(nil, "OVERLAY")
        marks[i] = m
    end
    return m
end

local function DrawMarks()
    for _, m in ipairs(marks) do
        m.tick:Hide()
        m.num:Hide()
    end
    if db.maxStacks <= 0 then return end

    local defs = {}
    if db.breakpoint > 0 and db.breakpoint < db.maxStacks then
        defs[#defs + 1] = { at = db.breakpoint, tick = true }
    end
    if db.secondMarker > 0 and db.secondMarker < db.maxStacks
        and db.secondMarker ~= db.breakpoint then
        defs[#defs + 1] = { at = db.secondMarker, tick = true }
    end
    -- Cap count sits above the right edge, no tick needed there.
    defs[#defs + 1] = { at = db.maxStacks, tick = false }

    for i, def in ipairs(defs) do
        local m = GetMark(i)
        local x = db.width * (def.at / db.maxStacks)
        if def.tick then
            m.tick:SetColorTexture(ColorOf("tick"))
            m.tick:SetSize(2, db.height)
            m.tick:ClearAllPoints()
            m.tick:SetPoint("CENTER", root, "LEFT", x, 0)
            m.tick:Show()
        end
        if db.showMarkerNumbers then
            ApplyFont(m.num, -2)
            m.num:SetTextColor(ColorOf("tick"))
            m.num:SetText(def.at)
            m.num:ClearAllPoints()
            m.num:SetPoint("BOTTOM", root, "TOPLEFT", math.min(x, db.width - 6), 1)
            m.num:Show()
        end
    end
end

--------------------------------------------------------------------
-- Preview (options window open: simulate a stack count, since the
-- real aura bar is empty out of combat)
--------------------------------------------------------------------

function ns.SetPreviewStacks(n)
    ns.previewStacks = n
    ns.UpdatePreview()
end

function ns.UpdatePreview()
    if not root then return end
    local n = ns.previewStacks
    if not n or n <= 0 then
        if previewBar then previewBar:Hide() end
        return
    end
    if not previewBar then
        previewBar = CreateFrame("StatusBar", nil, root)
        local fill = previewBar:CreateTexture(nil, "ARTWORK")
        fill:SetColorTexture(1, 1, 1, 1)
        previewBar:SetStatusBarTexture(fill)
        previewFS = previewBar:CreateFontString(nil, "OVERLAY")
        previewFS:SetPoint("CENTER")
        if container then
            previewBar:SetFrameLevel(container:GetFrameLevel() + 9)
        end
    end
    n = math.min(n, db.maxStacks)
    previewBar:SetAllPoints(root)
    previewBar:SetMinMaxValues(0, db.maxStacks)
    previewBar:SetValue(n)
    local c = ColorForStacks(n)
    previewBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    ApplyFont(previewFS)
    previewFS:SetTextColor(ColorOf("text"))
    previewFS:SetText(n)
    previewBar:Show()
end

--------------------------------------------------------------------
-- Visibility and mouse
--------------------------------------------------------------------

function ns.UpdateVisibility()
    if not root then return end
    if not ns.IsRelevantSpec() then
        root:Hide()
        return
    end
    local reveal = (not db.combatOnly) or InCombat() or ns.tempShow or ns.optionsOpen
    if reveal then
        root:SetAlpha(1)
        root:Show()
    elseif db.hoverReveal then
        root:SetAlpha(ns.hovering and 1 or 0)
        root:Show()
    else
        root:Hide()
    end
end

function ns.UpdateMouse()
    if not root then return end
    if InCombat() then
        -- Click-through in combat, always.
        root:EnableMouse(false)
        return
    end
    local wantMouse = (not db.locked) or ns.tempShow or ns.optionsOpen
        or (db.combatOnly and db.hoverReveal)
    root:EnableMouse(wantMouse)
end

--------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------

function ns.ApplyLayout()
    if not root then return end

    root:SetSize(db.width, db.height)
    root:SetScale(db.scale or 1)
    local p = db.point
    root:ClearAllPoints()
    root:SetPoint(p[1], UIParent, p[2], p[3], p[4])

    bg:SetColorTexture(ColorOf("background"))

    local inset = math.max(2, math.floor(db.height * 0.12))
    iconTex:SetShown(db.showIcon)
    iconTex:SetTexture(SpellIconTexture())
    iconTex:SetSize(db.height - inset * 2, db.height - inset * 2)
    iconTex:ClearAllPoints()
    iconTex:SetPoint("LEFT", root, "LEFT", inset, 0)

    labelFS:SetShown(db.showLabel)
    ApplyFont(labelFS, -1)
    labelFS:SetTextColor(ColorOf("text"))
    labelFS:ClearAllPoints()
    labelFS:SetPoint("LEFT", root, "LEFT",
        (db.showIcon and (db.height - inset) or inset) + 4, 0)

    -- Live-resize the client-rendered slot; colors need a rebuild but
    -- geometry and fonts do not.
    if slotWidgets.btn then
        pcall(slotWidgets.btn.SetSize, slotWidgets.btn, db.width, db.height)
    end
    if slotFrame and slotFrame ~= slotWidgets.btn then
        pcall(slotFrame.SetSize, slotFrame, db.width, db.height)
    end
    if slotWidgets.count then
        ApplyFont(slotWidgets.count)
        slotWidgets.count:SetTextColor(ColorOf("text"))
    end
    ApplySlotScale()
end

function ns.Refresh()
    if not root then return end
    ns.ApplyLayout()
    DrawMarks()
    ns.UpdatePreview()
    ns.UpdateVisibility()
    ns.UpdateMouse()
end

--------------------------------------------------------------------
-- Root frame construction
--------------------------------------------------------------------

function ns.InitBar()
    if root then return end
    db = ns.db

    root = CreateFrame("Frame", "ArcaneSalvoTrackerBar", UIParent)
    -- Above the default HUD strata: Blizzard's Cooldown Manager viewers
    -- are mouse-interactive across their whole region, and if one
    -- overlaps the bar it would swallow every drag aimed at it. Safe in
    -- combat because the bar goes fully click-through there anyway.
    root:SetFrameStrata("HIGH")
    root:SetClampedToScreen(true)
    root:SetMovable(true)
    root:RegisterForDrag("LeftButton")

    bg = root:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(root)

    overlay = CreateFrame("Frame", nil, root)
    overlay:SetAllPoints(root)

    iconTex = overlay:CreateTexture(nil, "OVERLAY")
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    labelFS = overlay:CreateFontString(nil, "OVERLAY")
    labelFS:SetText("Arcane Salvo")

    root:SetScript("OnDragStart", function(self)
        if not db.locked and not InCombat() then
            self:StartMoving()
        end
    end)
    root:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Normalize to a CENTER anchor so the options window's X/Y
        -- sliders always reflect the live position.
        local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local fx, fy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if fx and ux then
            db.point = { "CENTER", "CENTER", fx * scale - ux, fy * scale - uy }
        end
        ns.Refresh()
        if ns.RefreshOptionControls then ns.RefreshOptionControls() end
    end)
    root:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and not InCombat() then
            ns.ToggleOptions()
        end
    end)
    root:SetScript("OnEnter", function()
        ns.hovering = true
        ns.UpdateVisibility()
    end)
    root:SetScript("OnLeave", function()
        ns.hovering = false
        ns.UpdateVisibility()
    end)

    ns.Refresh()
end
