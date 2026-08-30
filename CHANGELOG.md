# Changelog

## 0.1.0

Initial release.

- Arcane Salvo stack bar rendered through the AuraContainer API, so it keeps
  updating while aura data is secret in combat
- Stack count displayed inside the bar
- Bar color changes at the breakpoint (default 12) and again at max stacks
- Breakpoint marker tick with numeric labels, plus an optional second marker
- Hero tree presets: Sunfury (cap 25 / breakpoint 12), Spellslinger (cap 20 /
  breakpoint 15)
- Standalone options window (`/ast`) with live preview, size/scale sliders,
  color pickers, font controls (LibSharedMedia-aware), and visibility options
- Combat-safe: settings that rebuild the bar are queued until combat ends
