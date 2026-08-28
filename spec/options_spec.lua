local mock = require("spec.wow_mock")

describe("Options", function()
    local w, ns, frame

    before_each(function()
        w = mock.New()
        ns = mock.Boot(w)
        w.Fire("PLAYER_ENTERING_WORLD")
        w.FlushTimers()
        ns.ToggleOptions()
        frame = w.named["ArcaneSalvoTrackerOptionsFrame"]
    end)

    describe("window lifecycle", function()
        it("opens with the preview active on the first toggle", function()
            assert.is_true(frame.state.shown)
            assert.is_true(ns.optionsOpen)
            assert.equal(ns.db.maxStacks, ns.previewStacks)
        end)

        it("closes and clears the preview on the second toggle", function()
            ns.ToggleOptions()
            assert.is_false(frame.state.shown)
            assert.is_false(ns.optionsOpen)
            assert.is_nil(ns.previewStacks)
        end)

        it("registers for Escape-key closing", function()
            local found = false
            for _, name in ipairs(_G.UISpecialFrames) do
                if name == "ArcaneSalvoTrackerOptionsFrame" then found = true end
            end
            assert.is_true(found)
        end)
    end)

    describe("controls write through to the database", function()
        it("width slider", function()
            local slider = w.FindSliderByLabel("Width")
            assert.is_not_nil(slider)
            slider:SetValue(400)
            assert.equal(400, ns.db.width)
        end)

        it("lock checkbox", function()
            local label = w.FindByText("Lock bar (drag with left mouse while unlocked)")
            assert.is_not_nil(label)
            label.__parent:Click()
            assert.is_true(ns.db.locked)
        end)

        it("hero tree preset buttons set cap and breakpoint together", function()
            w.FindByText("Spellslinger (20 / 15)"):Click()
            assert.equal(20, ns.db.maxStacks)
            assert.equal(15, ns.db.breakpoint)

            w.FindByText("Sunfury (25 / 12)"):Click()
            assert.equal(25, ns.db.maxStacks)
            assert.equal(12, ns.db.breakpoint)
        end)

        it("preset changes propagate into a rebuilt color map", function()
            w.FindByText("Spellslinger (20 / 15)"):Click()
            w.FlushTimers()
            assert.equal(20, w.lastBarOpts.maxApplications)
            assert.is_not_nil(w.lastBarOpts.colorMap[15])
        end)

        it("color swatches round-trip through the ColorPickerFrame", function()
            local swatch = w.FindByText("Bar color").__parent
            swatch:Click()
            assert.is_not_nil(w.pickerInfo)

            w.pickerColor = { 0.1, 0.2, 0.3 }
            w.pickerAlpha = 0.9
            w.pickerInfo.swatchFunc()
            assert.same({ 0.1, 0.2, 0.3, 0.9 }, ns.db.colors.normal)
        end)

        it("font picker rows select the clicked font", function()
            local fontBtn = w.FindByText("Friz Quadrata TT")
            assert.is_not_nil(fontBtn)
            fontBtn:Click()
            local row = w.FindByText("Skurri")
            assert.is_not_nil(row)
            row.__parent:Click()
            assert.equal("Skurri", ns.db.fontName)
        end)
    end)

    describe("restore defaults", function()
        it("resets settings but keeps the resolved spell ID", function()
            ns.db.width = 999
            ns.db.spellID = 4242
            w.FindByText("Restore defaults"):Click()
            assert.equal(260, ns.db.width)
            assert.equal(4242, ns.db.spellID)
        end)
    end)

    describe("bar integration", function()
        it("keeps the bar visible while the window is open even in combat-only mode", function()
            ns.db.combatOnly = true
            ns.UpdateVisibility()
            local root = w.named["ArcaneSalvoTrackerBar"]
            assert.is_true(root.state.shown)

            ns.ToggleOptions()
            ns.UpdateVisibility()
            assert.is_false(root.state.shown)
        end)
    end)
end)
