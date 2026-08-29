--------------------------------------------------------------------
-- Minimal WoW client mock for busted tests.
--
-- M.New() builds a fresh "world" and installs the WoW API surface the
-- addon uses into _G. M.Boot() loads the addon files into the world
-- and fires ADDON_LOADED, mirroring the client's load sequence.
--
-- Frames mimic the client's semantics where the addon depends on
-- them: frames spawn shown, OnShow/OnHide fire only on transitions,
-- SetValue fires OnValueChanged, CheckButton Click toggles state.
--------------------------------------------------------------------

local M = {}

local newObject

local function attachMethods(w, obj, name)
    function obj:GetName() return name end
    function obj:GetParent() return self.__parent end
    function obj:SetParent(p)
        self.__parent = p
        if p and p.children then p.children[#p.children + 1] = self end
    end

    function obj:Show()
        if not self.state.shown then
            self.state.shown = true
            if self.scripts.OnShow then self.scripts.OnShow(self) end
        end
    end
    function obj:Hide()
        if self.state.shown then
            self.state.shown = false
            if self.scripts.OnHide then self.scripts.OnHide(self) end
        end
    end
    function obj:SetShown(v) if v then self:Show() else self:Hide() end end
    function obj:IsShown() return self.state.shown end

    function obj:SetAlpha(a) self.state.alpha = a end
    function obj:GetAlpha() return self.state.alpha end

    function obj:SetSize(width, height)
        self.state.width, self.state.height = width, height
    end
    function obj:SetWidth(width) self.state.width = width end
    function obj:SetHeight(height) self.state.height = height end
    function obj:GetWidth() return self.state.width or 0 end
    function obj:GetHeight() return self.state.height or 0 end

    function obj:SetPoint(point, relTo, relPoint, x, y)
        if type(relTo) == "number" or (relTo == nil and relPoint == nil) then
            -- short form: SetPoint(point [, x, y])
            x, y, relTo, relPoint = relTo, relPoint, nil, nil
        end
        self.state.points[#self.state.points + 1] =
            { point = point, relTo = relTo, relPoint = relPoint, x = x, y = y }
    end
    function obj:GetPoint(i)
        local p = self.state.points[i or 1]
        if not p then return nil end
        return p.point, p.relTo, p.relPoint, p.x, p.y
    end
    function obj:ClearAllPoints() self.state.points = {} end
    function obj:SetAllPoints(target) self.state.allPoints = target or self.__parent end

    function obj:SetScript(handler, fn) self.scripts[handler] = fn end
    function obj:GetScript(handler) return self.scripts[handler] end

    function obj:SetText(t) self.state.text = t end
    function obj:GetText() return self.state.text end
    function obj:SetChecked(v) self.state.checked = v and true or false end
    function obj:GetChecked() return self.state.checked end

    function obj:Click()
        if self.__kind == "CheckButton" then
            self.state.checked = not self.state.checked
        end
        if self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end
    end

    function obj:SetValue(v)
        self.state.value = v
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end
    end
    function obj:GetValue() return self.state.value end
    function obj:SetMinMaxValues(lo, hi) self.state.min, self.state.max = lo, hi end

    function obj:SetStatusBarColor(r, g, b, a) self.state.barColor = { r, g, b, a } end
    function obj:SetColorTexture(r, g, b, a) self.state.color = { r, g, b, a } end
    function obj:SetTextColor(r, g, b, a) self.state.textColor = { r, g, b, a } end
    function obj:SetFont(path, size, flags)
        self.state.font = { path = path, size = size, flags = flags }
    end

    function obj:GetFrameLevel() return self.state.frameLevel end
    function obj:SetFrameLevel(level) self.state.frameLevel = level end
    function obj:EnableMouse(v) self.state.mouseEnabled = v and true or false end

    function obj:RegisterEvent(event)
        w.eventTargets[event] = w.eventTargets[event] or {}
        table.insert(w.eventTargets[event], self)
    end
    function obj:RegisterUnitEvent(event) self:RegisterEvent(event) end

    function obj:CreateTexture(nm) return newObject(w, "Texture", self, nm) end
    function obj:CreateFontString(nm) return newObject(w, "FontString", self, nm) end
end

newObject = function(w, kind, parent, name)
    local obj = {
        __kind = kind,
        __name = name,
        __parent = parent,
        children = {},
        scripts = {},
        calls = {},
        state = { shown = true, alpha = 1, points = {}, frameLevel = 1, checked = false },
    }
    attachMethods(w, obj, name)

    -- Auto-stub anything else the addon calls (SetBackdrop, SetScale,
    -- RegisterForDrag, ...) while recording the call for debugging.
    setmetatable(obj, {
        __index = function(_, key)
            local fn = function(self, ...)
                self.calls[#self.calls + 1] = { method = key, n = select("#", ...), ... }
            end
            rawset(obj, key, fn)
            return fn
        end,
    })

    if parent and parent.children then
        parent.children[#parent.children + 1] = obj
    end
    w.everything[#w.everything + 1] = obj
    return obj
end

local function validateBarOptions(w, opts)
    if w.rejectAllBarOptions then error("rejected") end
    for k in pairs(opts) do
        if k ~= "maxApplications" and not w.acceptedBarOptions[k] then
            error("invalid application bar option: " .. tostring(k))
        end
    end
end

local function createFrame(w, frameType, name, parent)
    local f = newObject(w, frameType, parent, name)
    if name then
        _G[name] = f
        w.named[name] = f
    end
    if frameType == "AuraContainer" then
        f.SetUnit = function(self, unit) self.state.unit = unit end
        f.AddAuraSlot = function(self, _, filter, opts)
            w.slotAdds = w.slotAdds + 1
            w.lastSlotFilter = filter
            w.lastSlotOpts = opts
            local slot = newObject(w, "AuraSlot", self, nil)
            -- Real aura slot buttons take mouse input by default
            slot.state.mouseEnabled = true
            w.lastSlot = slot
            slot.SetApplicationBar = function(_, bar, barOpts)
                validateBarOptions(w, barOpts)
                w.lastBarOpts = barOpts
                w.lastBarWidget = bar
            end
            slot.SetApplicationCount = function(_, fs, countOpts)
                w.lastCountFS = fs
                w.lastCountOpts = countOpts
            end
            if opts and opts.initializeFrame then
                opts.initializeFrame(slot)
            end
            return slot
        end
    end
    return f
end

function M.New(opts)
    local w = {
        now = 100,             -- GetTime(); nonzero so throttles behave
        combat = false,
        specID = 62,           -- Arcane
        classToken = (opts and opts.class) or "MAGE",
        auras = {},            -- spellID -> aura data (GetPlayerAuraBySpellID)
        auraList = {},         -- index -> aura data (GetAuraDataByIndex)
        timers = {},
        printed = {},
        everything = {},
        named = {},
        eventTargets = {},
        acceptedBarOptions = (opts and opts.acceptedBarOptions) or { colorMap = true },
        rejectAllBarOptions = false,
        slotAdds = 0,
        pickerColor = { 1, 1, 1 },
        pickerAlpha = 1,
    }

    _G.wipe = function(t)
        for k in pairs(t) do t[k] = nil end
        return t
    end
    _G.tinsert = table.insert
    _G.unpack = _G.unpack or table.unpack

    _G.CreateFrame = function(ft, nm, parent, _) return createFrame(w, ft, nm, parent) end
    _G.UIParent = newObject(w, "Frame", nil, "UIParent")
    _G.UISpecialFrames = {}
    _G.SlashCmdList = {}
    _G.ArcaneSalvoTrackerDB = nil

    _G.GetTime = function() return w.now end
    _G.InCombatLockdown = function() return w.combat end
    _G.UnitAffectingCombat = function() return w.combat end
    _G.UnitClass = function()
        local token = w.classToken
        return token:sub(1, 1) .. token:sub(2):lower(), token
    end
    _G.UnitIsUnit = function(a, b) return a == b end
    _G.GetSpecialization = function() return 1 end
    _G.GetSpecializationInfo = function() return w.specID end

    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    _G.C_Timer = {
        After = function(delay, fn)
            w.timers[#w.timers + 1] = { delay = delay, fn = fn }
        end,
    }
    _G.C_Spell = { GetSpellTexture = function() return 134400 end }
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function(spellID) return w.auras[spellID] end,
        GetAuraDataByIndex = function(_, i, _) return w.auraList[i] end,
    }
    _G.C_AuraContainerUtil = {
        ProcessCustomAuraButtonApplicationBarOptions = function(barOpts)
            validateBarOptions(w, barOpts)
        end,
    }
    _G.ColorPickerFrame = {
        SetupColorPickerAndShow = function(_, info) w.pickerInfo = info end,
        GetColorRGB = function() return w.pickerColor[1], w.pickerColor[2], w.pickerColor[3] end,
        GetColorAlpha = function() return w.pickerAlpha end,
    }
    _G.LibStub = nil

    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        w.printed[#w.printed + 1] = table.concat(parts, " ")
    end

    ----------------------------------------------------------------
    -- Test helpers
    ----------------------------------------------------------------

    function w.Fire(event, ...)
        local targets = w.eventTargets[event]
        if not targets then return end
        for _, f in ipairs(targets) do
            local handler = f.scripts.OnEvent
            if handler then handler(f, event, ...) end
        end
    end

    function w.FlushTimers()
        local guard = 0
        while #w.timers > 0 and guard < 100 do
            guard = guard + 1
            local t = table.remove(w.timers, 1)
            t.fn()
        end
    end

    function w.FindByText(text)
        for _, f in ipairs(w.everything) do
            if f.state.text == text then return f end
        end
    end

    function w.FindSliderByLabel(label)
        for _, f in ipairs(w.everything) do
            if f.__kind == "FontString" and f.state.text == label then
                local holder = f.__parent
                if holder then
                    for _, child in ipairs(holder.children) do
                        if child.__kind == "Slider" then return child end
                    end
                end
            end
        end
    end

    function w.FramesOfKind(kind)
        local out = {}
        for _, f in ipairs(w.everything) do
            if f.__kind == kind then out[#out + 1] = f end
        end
        return out
    end

    function w.PrintedContains(fragment)
        for _, line in ipairs(w.printed) do
            if line:find(fragment, 1, true) then return true end
        end
        return false
    end

    return w
end

function M.LoadAddon(w)
    local ns = {}
    for _, file in ipairs({ "Core.lua", "Bar.lua", "Options.lua" }) do
        local chunk, err = loadfile(file)
        assert(chunk, err)
        chunk("ArcaneSalvoTracker", ns)
    end
    w.ns = ns
    return ns
end

function M.Boot(w, savedVars)
    _G.ArcaneSalvoTrackerDB = savedVars
    local ns = M.LoadAddon(w)
    w.Fire("ADDON_LOADED", "ArcaneSalvoTracker")
    return ns
end

return M
