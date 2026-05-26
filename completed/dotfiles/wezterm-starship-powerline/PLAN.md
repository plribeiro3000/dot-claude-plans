# Plan: WezTerm Starship Powerline

## Overview

**Feature:** wezterm-starship-powerline
**Type:** Single-project (dotfiles)
**Status:** ✅ COMPLETED

## Problem

Powerline arrows were displaying as **square boxes** (□) instead of triangular arrows () in the Starship prompt on WezTerm terminal.

## Solution

### Root Cause Analysis

The problem was **NOT** the font configuration. The actual issue was that the `starship.toml` file contained **empty brackets `[]`** instead of the Powerline Unicode character (U+E0B0).

**Technical Evidence:**
- Hex dump showed bytes `5b5d` (ASCII for "[]") instead of `ee82b0` (UTF-8 for U+E0B0)
- The Read tool displayed `` but they were actually empty brackets
- Test with `echo -e "\ue0b0"` worked correctly, proving the font was fine

### Failed Attempts

| Attempt | Change | Result |
|---------|--------|--------|
| 1 | Changed font to `FiraCode Nerd Font Mono` | Did not fix |
| 2 | Configured `font_with_fallback` with multiple fonts | Did not fix |
| 3 | Changed to `MesloLGS Nerd Font` | Did not fix |
| 4 | Changed to `MesloLGS Nerd Font Mono` | Did not fix |

All font changes failed because the problem was in the starship.toml file, not the font.

### Solution

Rewrite the `starship.toml` file using Python to ensure correct UTF-8 bytes:

```python
arrow = '\uE0B0'  # U+E0B0 = Powerline arrow
# Write file with f-string interpolation
```

**Verification:** Hex dump must show `ee82b0` bytes (correct UTF-8 encoding for U+E0B0).

## Final Configuration

### WezTerm (`~/.wezterm.lua`)

```lua
-- Font - MesloLGS Nerd Font Mono for Powerline compatibility
config.font = wezterm.font_with_fallback({
  { family = 'MesloLGS Nerd Font Mono', weight = 'Regular' },
  { family = 'MesloLGS Nerd Font', weight = 'Regular' },
  'Symbols Nerd Font Mono',
  'Apple Color Emoji',
})
config.font_size = 12.0

-- Enable proper Unicode and glyph rendering
config.allow_square_glyphs_to_overflow_width = "Always"
config.custom_block_glyphs = true
config.front_end = "WebGpu"

-- Tab bar - Always show tabs (DO NOT CHANGE)
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = false
config.use_fancy_tab_bar = true
config.tab_bar_at_bottom = false
```

### Starship (`~/.config/starship.toml`)

```toml
format = """
$directory\
[](fg:#DA627D bg:#FCA17D)\
$git_branch\
[](fg:#FCA17D bg:#86BBD8)\
$nodejs\
[](fg:#86BBD8 bg:#06969A)\
$ruby\
[ ](fg:#06969A)\
$line_break\
$character"""

[directory]
style = "bg:#DA627D fg:#ffffff"
format = "[ 📁 $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

[git_branch]
symbol = " "
style = "bg:#FCA17D fg:#000000"
format = "[ $symbol$branch ]($style)"

[nodejs]
symbol = " "
style = "bg:#86BBD8 fg:#000000"
format = "[ $symbol$version ]($style)"
detect_files = ["package.json", ".node-version", ".nvmrc"]
detect_folders = ["node_modules"]

[ruby]
symbol = " "
style = "bg:#06969A fg:#ffffff"
format = "[ $symbol$version ]($style)"
detect_files = ["Gemfile", ".ruby-version", ".rvmrc"]

[line_break]
disabled = false

[character]
success_symbol = "[➜](bold green)"
error_symbol = "[➜](bold red)"
```

### Block Colors

| Block | Color | Hex |
|-------|-------|-----|
| Directory | Pink | #DA627D |
| Git | Orange | #FCA17D |
| Node.js | Light Blue | #86BBD8 |
| Ruby | Teal | #06969A |

## Fix History

### Fix #1 - 2025-11-18 (Session 2)

- **Problem:** Empty brackets in starship.toml
- **Solution:** Rewrote file with Python using `'\uE0B0'`
- **Result:** Arrows appeared correctly

### Fix #2 - 2025-11-18 (Session 3)

- **Problem:** User requested simplification
- **Changes:**
  - Removed initial arrow (pointless)
  - Removed time block
  - Removed Docker and Username blocks
  - Added icons to identify each block
- **Result:** Cleaner configuration with only Directory, Git, Node.js, Ruby

### Fix #3 - 2026-01-04

- **Problem:** Arrows showing as boxes again
- **Cause:** Same root cause - file was edited and Unicode characters were corrupted back to empty brackets `[]`
- **Diagnosis:** Hex dump showed `5b5d` instead of `ee82b0`
- **Solution:** Rewrote file again using Python with `'\uE0B0'`
- **Verification:** Hex dump confirmed correct bytes
- **Result:** Arrows working correctly

## Key Learnings

1. **The problem is never the font** - if `echo -e "\ue0b0"` works, font is fine
2. **Unicode characters get corrupted** when files are edited/saved by text editors
3. **Always use programmatic methods** (Python, printf) to write special Unicode characters
4. **Verify with hex dump** - never trust visual representation in editors
5. **Keep this context** - the problem will likely recur if the file is edited manually

## Debug Commands

```bash
# Test Powerline character rendering
echo -e "Teste Powerline: \ue0b0 \ue0b2"

# Verify bytes in starship.toml (should show ee82b0, NOT 5b5d)
xxd ~/.config/starship.toml | grep -E "ee82b0|5b5d"

# Check installed fonts
fc-list | grep -i "nerd"

# Reload shell after changes
exec zsh
```

## Constraints

- **DO NOT break WezTerm tabs** - tab configuration must remain unchanged
- **DO NOT add extra blocks** - keep only Directory, Git, Node.js, Ruby
- **DO NOT edit starship.toml manually** - always use Python to preserve Unicode

## Files

| File | Purpose |
|------|---------|
| `~/.wezterm.lua` | WezTerm terminal configuration |
| `~/.config/starship.toml` | Starship prompt configuration |

## Completed

- ✅ WezTerm configured with proper font fallback
- ✅ Starship configured with Powerline arrows
- ✅ All blocks displaying correctly with icons
- ✅ Tab navigation working
