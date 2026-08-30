local mock = require("spec.wow_mock")

describe("Bar", function()
    local w, ns, root

    local function boot(opts)
        w = mock.New(opts)
        ns = mock.Boot(w)
        w.Fire("PLAYER_ENTERING_WORLD")
        w.FlushTimers()
        root = w.named["ArcaneSalvoTrackerBar"]
    end

    before_each(function()
        boot()
    end)

    describe("aura container", function()
        it("builds a slot filtered to the primary candidate (single-ID filter)", function()
            assert.equal(1, w.slotAdds)
            assert.equal("HELPFUL|PLAYER", w.lastSlotFilter)
            local include = w.lastSlotOpts.candidateFilters.includeSpellIDs
            -- 1242974 is the live 12.1 Arcane Salvo ID
            assert.is_true(include[1242974])
            local count = 0
            for _ in pairs(include) do count = count + 1 end
            assert.equal(1, count)
        end)

        it("switches the filter to the resolved spell ID", function()
            ns.db.spellID = 384452
            ns.BuildContainer()
            local include = w.lastSlotOpts.candidateFilters.includeSpellIDs
            assert.is_true(include[384452])
            assert.is_nil(include[1242974])
        end)

        it("makes the slot click-through so drags reach the movable root", function()
            assert.is_false(w.lastSlot.state.mouseEnabled)
        end)

        it("anchors the stack count FontString centered inside the bar", function()
            assert.is_not_nil(w.lastCountFS)
            local p = w.lastCountFS.state.points[1]
            assert.equal("CENTER", p.point)
            assert.equal(13, w.lastCountFS.state.font.size)
        end)
    end)

    describe("color map", function()
        it("passes stops at 1, the breakpoint, and max stacks", function()
            assert.equal("colorMap", ns.barColorMode)
            assert.equal(25, w.lastBarOpts.maxApplications)
            local map = w.lastBarOpts.colorMap
            assert.equal(0.58, map[1].r)
            assert.equal(0.82, map[12].r)
            assert.equal(0.98, map[25].r)
        end)

        it("falls back to the next option form the client accepts", function()
            boot({ acceptedBarOptions = { colorCurve = true } })
            assert.equal("colorCurve", ns.barColorMode)
            assert.equal(3, #w.lastBarOpts.colorCurve)
        end)

        it("degrades to a plain bar when no color form is accepted", function()
            boot({ acceptedBarOptions = {} })
            assert.equal("plain", ns.barColorMode)
            assert.is_nil(w.lastBarOpts.colorMap)
        end)

        it("records failure when even the plain form is rejected", function()
            w.rejectAllBarOptions = true
            ns.BuildContainer()
            assert.equal("failed", ns.barColorMode)
            assert.is_true(#ns.errors > 0)
        end)

        it("rebuilds with new stops when the breakpoint changes", function()
            ns.db.breakpoint = 15
            ns.RequestRebuild()
            w.FlushTimers()
            local map = w.lastBarOpts.colorMap
            assert.is_nil(map[12])
            assert.equal(0.82, map[15].r)
        end)
    end)

    describe("combat safety", function()
        it("queues rebuilds while in combat and applies them on exit", function()
            local builds = w.slotAdds
            w.combat = true
            ns.RequestRebuild()
            w.FlushTimers()
            assert.equal(builds, w.slotAdds)
            assert.is_true(ns.pendingRebuild)

            w.combat = false
            w.Fire("PLAYER_REGEN_ENABLED")
            assert.equal(builds + 1, w.slotAdds)
            assert.is_false(ns.pendingRebuild)
        end)

        it("is click-through in combat even when unlocked", function()
            ns.db.locked = false
            w.combat = true
            ns.UpdateMouse()
            assert.is_false(root.state.mouseEnabled)
        end)
    end)

    describe("breakpoint marker", function()
        it("draws the tick at width * breakpoint / maxStacks", function()
            -- width 260, breakpoint 12, max 25 -> 124.8 from the left edge
            local found
            for _, f in ipairs(w.FramesOfKind("Texture")) do
                local p = f.state.points[1]
                if p and p.relPoint == "LEFT" and p.x and math.abs(p.x - 124.8) < 0.001 then
                    found = f
                end
            end
            assert.is_not_nil(found)
        end)

        it("labels the breakpoint and the cap", function()
            assert.is_not_nil(w.FindByText(12))
            assert.is_not_nil(w.FindByText(25))
        end)
    end)

    describe("positioning", function()
        it("sits above the default HUD strata so overlapping viewers cannot swallow drags", function()
            assert.equal("HIGH", root.state.strata)
        end)

        it("extends the clickable area above the bar as a grab strip", function()
            assert.same({ 0, 0, -16, 0 }, root.state.hitRectInsets)
        end)

        it("is mouse-enabled and movable at build time", function()
            assert.is_true(root.state.mouseEnabled)
            assert.is_true(root.state.movable)
        end)

        it("saves the raw anchor on drag stop, exactly like the original", function()
            root.state.points = {
                { point = "TOPLEFT", relTo = _G.UIParent, relPoint = "TOPLEFT", x = 50, y = -60 },
            }
            root.scripts.OnDragStop(root)
            assert.same({ "TOPLEFT", "TOPLEFT", 50, -60 }, ns.db.point)
        end)
    end)

    describe("visibility", function()
        it("hides on non-Arcane specs", function()
            w.specID = 63
            ns.UpdateVisibility()
            assert.is_false(root.state.shown)
        end)

        it("hides out of combat when combat-only is set", function()
            ns.db.combatOnly = true
            ns.UpdateVisibility()
            assert.is_false(root.state.shown)
            w.combat = true
            ns.UpdateVisibility()
            assert.is_true(root.state.shown)
        end)

        it("hover-reveal keeps the bar shown at zero alpha until hovered", function()
            ns.db.combatOnly = true
            ns.db.hoverReveal = true
            ns.UpdateVisibility()
            assert.is_true(root.state.shown)
            assert.equal(0, root.state.alpha)

            root.scripts.OnEnter(root)
            assert.equal(1, root.state.alpha)
            root.scripts.OnLeave(root)
            assert.equal(0, root.state.alpha)
        end)
    end)

    describe("preview", function()
        local function previewBar()
            for _, f in ipairs(w.FramesOfKind("StatusBar")) do
                if f.__parent == root then return f end
            end
        end

        it("simulates stacks with the same color logic as the color map", function()
            ns.SetPreviewStacks(5)
            local pv = previewBar()
            assert.is_not_nil(pv)
            assert.same({ 0.58, 0.15, 0.78, 1.00 }, pv.state.barColor)

            ns.SetPreviewStacks(12)
            assert.same({ 0.82, 0.16, 0.62, 1.00 }, pv.state.barColor)

            ns.SetPreviewStacks(25)
            assert.same({ 0.98, 0.12, 0.38, 1.00 }, pv.state.barColor)
        end)

        it("hides when the preview is cleared", function()
            ns.SetPreviewStacks(10)
            local pv = previewBar()
            ns.SetPreviewStacks(nil)
            assert.is_false(pv.state.shown)
        end)
    end)

    describe("fonts", function()
        it("lists the built-in fonts sorted when LibSharedMedia is absent", function()
            assert.same(
                { "Arial Narrow", "Friz Quadrata TT", "Morpheus", "Skurri" },
                ns.GetFontList())
        end)

        it("resolves known fonts and falls back for unknown ones", function()
            assert.equal("Fonts\\skurri.ttf", ns.ResolveFont("Skurri"))
            assert.equal("Fonts\\FRIZQT__.TTF", ns.ResolveFont("No Such Font"))
        end)
    end)
end)
