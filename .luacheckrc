std = "lua51"
max_line_length = 120
self = false

exclude_files = {
    ".luarocks/**",
}

-- WoW API surface used by the addon
read_globals = {
    -- Lua extensions provided by the WoW client
    "wipe", "tinsert", "unpack",

    -- Frames and UI
    "CreateFrame", "UIParent", "ColorPickerFrame", "CreateColor",

    -- Game state
    "GetTime", "InCombatLockdown", "UnitAffectingCombat", "UnitClass",
    "UnitIsUnit", "GetSpecialization", "GetSpecializationInfo",

    -- Namespaced APIs
    "C_Timer", "C_Spell", "C_UnitAuras", "C_AuraContainerUtil", "C_AddOns",

    -- Libraries
    "LibStub",
}

globals = {
    "ArcaneSalvoTrackerDB",
    "SLASH_ARCANESALVOTRACKER1",
    "SLASH_ARCANESALVOTRACKER2",
    "SlashCmdList",
    "UISpecialFrames",
}

files["spec/**/*.lua"] = {
    -- "max" so the mock can shim table.unpack across Lua versions
    std = "max+busted",
    globals = { "_G" },
    max_line_length = false,
}
