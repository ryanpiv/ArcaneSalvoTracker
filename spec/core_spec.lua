local mock = require("spec.wow_mock")

describe("Core", function()
    local w, ns

    before_each(function()
        w = mock.New()
        ns = mock.Boot(w)
    end)

    describe("saved variables", function()
        it("merges defaults into an empty database", function()
            assert.equal(260, ns.db.width)
            assert.equal(24, ns.db.height)
            assert.equal(12, ns.db.breakpoint)
            assert.equal(25, ns.db.maxStacks)
            assert.same({ 0.98, 0.12, 0.38, 1.00 }, ns.db.colors.max)
        end)

        it("preserves existing user settings while filling gaps", function()
            local w2 = mock.New()
            local ns2 = mock.Boot(w2, {
                width = 300,
                colors = { normal = { 1, 0, 0, 1 } },
            })
            assert.equal(300, ns2.db.width)
            assert.same({ 1, 0, 0, 1 }, ns2.db.colors.normal)
            -- gaps filled from defaults
            assert.equal(24, ns2.db.height)
            assert.same({ 0.98, 0.12, 0.38, 1.00 }, ns2.db.colors.max)
        end)

        it("deep-merges without sharing table references with defaults", function()
            ns.db.colors.normal[1] = 0.11
            assert.equal(0.58, ns.defaults.colors.normal[1])
        end)
    end)

    describe("secret-value guards", function()
        it("treats plain numbers as readable", function()
            assert.is_true(ns.Readable(5))
            assert.is_true(ns.Readable(0))
        end)

        it("treats non-numbers as unreadable", function()
            assert.is_false(ns.Readable(nil))
            assert.is_false(ns.Readable("5"))
            assert.is_false(ns.Readable({}))
        end)

        it("ReadAura distinguishes absent (false) from present (table)", function()
            assert.is_false(ns.ReadAura(384452))
            w.auras[384452] = { name = "Arcane Salvo", applications = 5 }
            assert.is_table(ns.ReadAura(384452))
        end)
    end)

    describe("spell ID resolution", function()
        it("locks in a candidate ID when the aura is present", function()
            w.auras[384452] = { name = "Arcane Salvo", applications = 3 }
            w.Fire("PLAYER_ENTERING_WORLD")
            w.FlushTimers()
            assert.equal(384452, ns.db.spellID)
            assert.is_true(w.PrintedContains("resolved to spell ID 384452"))
        end)

        it("falls back to name-based scanning", function()
            w.auraList[1] = { name = "Some Other Buff", spellId = 1111 }
            w.auraList[2] = { name = "Arcane Salvo", spellId = 999999 }
            w.Fire("PLAYER_ENTERING_WORLD")
            w.FlushTimers()
            assert.equal(999999, ns.db.spellID)
        end)

        it("never resolves during combat (aura data is secret)", function()
            w.auras[384452] = { name = "Arcane Salvo", applications = 3 }
            w.combat = true
            ns.Resolve(true)
            assert.is_nil(ns.db.spellID)
        end)

        it("resolves on UNIT_AURA once out of combat", function()
            w.auras[384455] = { name = "Arcane Salvo", applications = 1 }
            w.Fire("UNIT_AURA", "player")
            assert.equal(384455, ns.db.spellID)
        end)
    end)

    describe("spec gating", function()
        it("is relevant on Arcane (spec 62)", function()
            assert.is_true(ns.IsRelevantSpec())
        end)

        it("is not relevant on other specs", function()
            w.specID = 63 -- Fire
            assert.is_false(ns.IsRelevantSpec())
        end)

        it("honors the all-specs override", function()
            w.specID = 63
            ns.db.allSpecs = true
            assert.is_true(ns.IsRelevantSpec())
        end)
    end)

    describe("/ast slash command", function()
        local function slash(msg)
            _G.SlashCmdList.ARCANESALVOTRACKER(msg)
        end

        it("is registered", function()
            assert.equal("/ast", _G.SLASH_ARCANESALVOTRACKER1)
            assert.is_function(_G.SlashCmdList.ARCANESALVOTRACKER)
        end)

        it("lock toggles the bar lock", function()
            slash("lock")
            assert.is_true(ns.db.locked)
            slash("lock")
            assert.is_false(ns.db.locked)
        end)

        it("reset restores the default position", function()
            ns.db.point = { "TOPLEFT", "TOPLEFT", 5, -5 }
            slash("reset")
            assert.same({ "CENTER", "CENTER", 0, -180 }, ns.db.point)
        end)

        it("id <n> sets a manual override, id clears it", function()
            slash("id 4242")
            assert.equal(4242, ns.db.spellID)
            slash("id")
            assert.is_nil(ns.db.spellID)
        end)

        it("status reports diagnostics without erroring", function()
            slash("status")
            assert.is_true(w.PrintedContains("color mode"))
        end)

        it("unknown subcommands print usage", function()
            slash("bogus")
            assert.is_true(w.PrintedContains("Commands:"))
        end)
    end)

    describe("non-mage characters", function()
        it("does not build the bar and gates the slash command", function()
            local w2 = mock.New({ class = "WARRIOR" })
            local ns2 = mock.Boot(w2)
            assert.is_false(ns2.isMage)
            assert.is_nil(w2.named["ArcaneSalvoTrackerBar"])
            _G.SlashCmdList.ARCANESALVOTRACKER("")
            assert.is_true(w2.PrintedContains("only functions on mages"))
        end)
    end)
end)
