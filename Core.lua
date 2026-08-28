local ADDON, ns = ...

--------------------------------------------------------------------
-- Arcane Salvo Tracker — Core
-- Saved variables, defaults, event handling, spec gating, /ast.
--
-- Hard constraint driving the whole design: in WoW 12.x, aura stack
-- counts are SECRET while in combat. The bar itself is therefore
-- client-rendered through the AuraContainer API (see Bar.lua); this
-- file only does bookkeeping that is safe out of combat.
--------------------------------------------------------------------

ns.ADDON = ADDON

-- Known Arcane Salvo aura spell IDs; may drift between patches, so
-- Bar.lua feeds all of them to the container until one is confirmed,
-- and Resolve() below locks one in when the aura is readable.
ns.SALVO_CANDIDATES = { 384452, 384455 }
ns.SALVO_NAME = "arcane salvo"
ns.ARCANE_SPEC_ID = 62

ns.presets = {
    sunfury      = { maxStacks = 25, breakpoint = 12 },
    spellslinger = { maxStacks = 20, breakpoint = 15 },
}

ns.defaults = {
    locked = false,
    width = 260,
    height = 24,
    scale = 1.0,

    breakpoint = 12,
    maxStacks = 25,
    secondMarker = 0,          -- 0 = disabled

    showIcon = true,
    showLabel = true,
    showMarkerNumbers = true,
    combatOnly = false,
    hoverReveal = false,
    allSpecs = false,

    fontName = "Friz Quadrata TT",
    fontSize = 13,
    fontOutline = true,

    colors = {
        normal     = { 0.58, 0.15, 0.78, 1.00 },
        breakpoint = { 0.82, 0.16, 0.62, 1.00 },
        max        = { 0.98, 0.12, 0.38, 1.00 },
        background = { 0.05, 0.05, 0.08, 0.72 },
        text       = { 1.00, 1.00, 1.00, 1.00 },
        tick       = { 1.00, 0.90, 0.60, 0.95 },
    },

    point = { "CENTER", "CENTER", 0, -180 },
    spellID = nil,             -- resolved at runtime or via /ast id
}

local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end
ns.CopyDefaults = CopyDefaults

function ns.Print(msg, ...)
    if select("#", ...) > 0 then msg = msg:format(...) end
    print("|cffcc66ffArcane Salvo Tracker:|r " .. msg)
end

--------------------------------------------------------------------
-- Secret-value helpers
--------------------------------------------------------------------

-- Secret numbers report type() == "number" but any comparison throws.
function ns.Readable(v)
    if type(v) ~= "number" then return false end
    return (pcall(function() return v < 0 end))
end

-- Returns a table when the aura is up and readable, false when it is
-- confirmed absent, nil when the data is secret or unavailable.
function ns.ReadAura(spellID)
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if not get or not spellID then return nil end
    local ok, aura = pcall(get, spellID)
    if not ok then
        -- Some builds take (unit, spellID) instead of (spellID)
        ok, aura = pcall(get, "player", spellID)
        if not ok then return nil end
    end
    if not aura then return false end
    return aura
end

--------------------------------------------------------------------
-- Spell ID resolution (out of combat only)
--------------------------------------------------------------------

local resolveTries, lastResolve = 0, 0

local function ScanByName()
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not get then return nil end
    for i = 1, 80 do
        local ok, aura = pcall(get, "player", i, "HELPFUL")
        if not ok or not aura then return nil end
        local okRead, name, id = pcall(function()
            return aura.name and aura.name:lower(), aura.spellId
        end)
        if okRead and name == ns.SALVO_NAME and type(id) == "number" and ns.Readable(id) then
            return id
        end
    end
    return nil
end

function ns.Resolve(force)
    local db = ns.db
    if not db or db.spellID then return end
    if UnitAffectingCombat("player") then return end
    if not force then
        if resolveTries >= 40 then return end
        local now = GetTime()
        if now - lastResolve < 2 then return end
        lastResolve, resolveTries = now, resolveTries + 1
    end

    for _, id in ipairs(ns.SALVO_CANDIDATES) do
        if ns.ReadAura(id) then
            db.spellID = id
            ns.Print("Arcane Salvo resolved to spell ID %d.", id)
            if ns.RequestRebuild then ns.RequestRebuild() end
            return
        end
    end

    local id = ScanByName()
    if id then
        db.spellID = id
        ns.Print("Arcane Salvo resolved by name to spell ID %d.", id)
        if ns.RequestRebuild then ns.RequestRebuild() end
    end
end

--------------------------------------------------------------------
-- Spec gating
--------------------------------------------------------------------

function ns.IsRelevantSpec()
    if not ns.isMage then return false end
    if ns.db and ns.db.allSpecs then return true end
    if not GetSpecialization then return true end
    local idx = GetSpecialization()
    if not idx then return true end
    local id = GetSpecializationInfo and GetSpecializationInfo(idx)
    return not id or id == ns.ARCANE_SPEC_ID
end

--------------------------------------------------------------------
-- Events
--------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")

ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        ArcaneSalvoTrackerDB = ArcaneSalvoTrackerDB or {}
        ns.db = ArcaneSalvoTrackerDB
        CopyDefaults(ns.db, ns.defaults)
        local _, class = UnitClass("player")
        ns.isMage = (class == "MAGE")
        if ns.isMage then
            ns.InitBar()
            ev:RegisterUnitEvent("UNIT_AURA", "player")
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        if not ns.isMage then return end
        -- Container (re)build after loading screens; aura data needs a
        -- moment to settle before resolution attempts are useful.
        C_Timer.After(1, function()
            ns.Resolve()
            ns.BuildContainer()
            ns.Refresh()
        end)

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if arg1 == nil or UnitIsUnit(arg1, "player") then
            ns.UpdateVisibility()
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.UpdateMouse()
        ns.UpdateVisibility()

    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.tempShow = false
        if ns.pendingRebuild then
            ns.pendingRebuild = false
            ns.BuildContainer()
            ns.Refresh()
        end
        ns.UpdateMouse()
        ns.UpdateVisibility()

    elseif event == "UNIT_AURA" then
        if ns.db and not ns.db.spellID then
            ns.Resolve()
        end
    end
end)

--------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------

SLASH_ARCANESALVOTRACKER1 = "/ast"
SLASH_ARCANESALVOTRACKER2 = "/arcanesalvotracker"

SlashCmdList.ARCANESALVOTRACKER = function(msg)
    if not ns.db then return end
    if not ns.isMage then
        ns.Print("This addon only functions on mages.")
        return
    end

    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")

    if cmd == "" then
        ns.ToggleOptions()

    elseif cmd == "lock" then
        ns.db.locked = not ns.db.locked
        ns.Print(ns.db.locked and "Bar locked." or "Bar unlocked — drag to move.")
        ns.UpdateMouse()

    elseif cmd == "reset" then
        ns.db.point = { unpack(ns.defaults.point) }
        ns.Refresh()
        ns.Print("Position reset.")

    elseif cmd == "show" then
        ns.tempShow = true
        ns.UpdateVisibility()
        ns.Print("Bar shown until you enter combat.")

    elseif cmd == "id" then
        local id = tonumber(rest)
        if id then
            ns.db.spellID = id
            ns.Print("Spell ID override set to %d.", id)
            ns.RequestRebuild()
        else
            ns.db.spellID = nil
            resolveTries = 0
            ns.Print("Spell ID override cleared; will auto-resolve.")
            ns.Resolve(true)
            ns.RequestRebuild()
        end

    elseif cmd == "status" then
        ns.Print("Spell ID: %s | color mode: %s | spec ok: %s | locked: %s",
            tostring(ns.db.spellID or "unresolved (candidates: " .. table.concat(ns.SALVO_CANDIDATES, ", ") .. ")"),
            tostring(ns.barColorMode or "not built"),
            tostring(ns.IsRelevantSpec()),
            tostring(ns.db.locked))
        if ns.errors and #ns.errors > 0 then
            for _, e in ipairs(ns.errors) do ns.Print("  error: " .. e) end
        else
            ns.Print("  no errors recorded.")
        end

    else
        ns.Print("Commands: /ast (options), lock, reset, show, id <spellID|clear>, status")
    end
end
