# Arcane Salvo Tracker

A clean, highly configurable **Arcane Salvo** stack bar for Arcane Mages (WoW retail, 12.x
"Midnight"). One bar, no clutter:

- Stack count rendered **inside** the bar
- Bar **changes color** at your breakpoint and again at max stacks
- Movable **breakpoint marker** (default 12) plus an optional second marker
- Full **graphical options window** (`/ast`) with live preview — size, colors, fonts,
  markers, visibility, everything

## Why a special API?

In WoW 12.x, aura stack counts are **secret during combat** — addons cannot read them.
Arcane Salvo Tracker uses Blizzard's `AuraContainer` API: the addon supplies the bar and
text widgets, and the game client itself fills in the live stack data. Color-by-stack is
handed to the client as a color map, so the bar still changes color at your breakpoint and
at max stacks even mid-combat.

## Usage

- `/ast` — open the options window (or right-click the bar while unlocked)
- `/ast lock` — toggle bar lock (drag with left mouse while unlocked)
- `/ast reset` — reset bar position to center
- `/ast show` — temporarily show the bar (until combat ends) for positioning
- `/ast id <spellID>` — manually override the Arcane Salvo spell ID
- `/ast status` — diagnostics (resolved spell ID, color-map mode, errors)

## Options

Open with `/ast`. While the window is open, the bar shows an addon-drawn **preview** at a
simulated stack count (slider-driven), since the real aura bar is empty out of combat.

- **Size and position** — width, height, scale, lock, reset position
- **Stacks** — hero tree presets (**Sunfury**: cap 25 / breakpoint 12, **Spellslinger**:
  cap 20 / breakpoint 15), breakpoint, max stacks, optional second marker
- **Colors** — bar normal / at breakpoint / at max, background, stack text, marker ticks
- **Text** — font family (uses LibSharedMedia fonts when available, e.g. via ElvUI),
  font size, outline, show/hide label and marker numbers
- **Visibility** — show spell icon, combat-only mode, reveal-on-mouseover while hidden,
  show on all mage specs

Settings that require rebuilding the client-rendered bar are queued while you are in
combat and applied automatically when combat ends.

## Installation

**CurseForge / WowUp:** search for "Arcane Salvo Tracker" (once published).

**Manual:** copy (or clone) this folder into
`World of Warcraft/_retail_/Interface/AddOns/ArcaneSalvoTracker` so that
`ArcaneSalvoTracker.toc` sits directly inside it.

**Development (macOS):**

```bash
ln -s ~/Documents/Git/ArcaneSalvoTracker \
  "/Applications/World of Warcraft/_retail_/Interface/AddOns/ArcaneSalvoTracker"
```

Then `/reload` in game to pick up changes.

## Known limitations

- Because stack counts are secret in combat, the addon **cannot play sounds or flash**
  at thresholds during combat. The color stops and the breakpoint tick are the in-combat
  signals.
- The color-map options of `SetApplicationBar` are undocumented. The addon tries several
  option forms and uses the first the client accepts (`/ast status` shows which). In the
  worst case the in-combat bar renders in a single color.
- Arcane Salvo spell IDs may change between patches. The addon resolves the aura by ID
  candidates and falls back to matching by name out of combat; `/ast id <spellID>` is the
  manual escape hatch.

## License

MIT — see [LICENSE](LICENSE).
