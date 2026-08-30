# MiniPressRelease - bot reference

## What it does

MiniPressRelease makes key presses and mouse clicks trigger action bar abilities on both
key/button DOWN and UP (release), instead of only on down. This gives two chances for an
ability to land, which matters when spamming abilities like Kick, Sap, Shadow Word: Death,
Execute, or anything pressed while crowd controlled: if the CC ends between your key-down
and key-up, the release press still fires. Credit for the idea goes to XyzKang.

## Facts

| Item | Value |
|---|---|
| Version | 2.7.7 |
| Interface versions (.toc) | 120100, 50504, 40402, 38002, 38000, 30405, 20506, 11509 (spans retail 12.1, Mists Classic 5.5.x, Cata Classic 4.4.x, Wrath 3.4.x, TBC 2.5.6, Classic Era 1.15.x) |
| Saved variables | MiniPressReleaseCharDB, per character (settings are NOT shared across characters) |
| Slash commands | /minipressrelease, /minipr, /mpr (all open the settings panel) |
| Settings location | Game Menu -> Options -> AddOns -> MiniPressRelease |
| Optional dependency | Bartender4 |
| Support | Discord: https://discord.gg/UruPTPHHxK |

## Features

### Keyboard mode (setting "Keyboard Enabled", default ON)

- Scans every key binding and rebinds each bound key to a secure proxy button that
  clicks the real action button on both key-down and key-up.
- Covers Blizzard action bars: ActionButton (main bar), MultiBarBottomLeft,
  MultiBarBottomRight, MultiBarRight, MultiBarLeft, MultiBar5, MultiBar6, MultiBar7.
- Also covers addon action buttons: any binding whose command is a "CLICK FrameName:button"
  binding is proxied the same way. This is how Bartender4 and ElvUI bars are supported in
  keyboard mode.
- The real button shows its pushed (pressed-in) visual while the key is held.
- Vehicle / override bar (e.g. vehicles, possess, some world quests): a secure state driver
  swaps bindings for ActionButton1-6 to the matching OverrideActionBarButton1-6. On the
  override/vehicle bar the double-press (down+up) behaviour is intentionally disabled; keys
  still work but fire on key-down only (changed in 2.6.0).
- Housing (Midnight house editor): while the house editor is active, all of the addon's
  key bindings are suppressed to avoid conflicts. They come back when the editor closes.
- Bindings are rebuilt on login, whenever key bindings change, and when the house editor
  opens or closes. Rebuilds never run during combat.

### Mouse mode (setting "Mouse Enabled", default OFF)

- Places an invisible secure overlay on top of each Blizzard action button (buttons 1-12
  on all 8 Blizzard bars) so mouse clicks fire the action on both mouse-down and mouse-up.
- Overlays still show the ability tooltip and hover highlight of the button underneath.
- While the cursor is holding a spell/item/macro (dragging something), overlays are
  temporarily disabled so you can drop things onto the action bars normally.
- Does NOT work with Bartender4. If Bartender4 is loaded: the setting is forced off at
  login, and trying to enable it shows a dialog: "Sorry, mouse mode doesn't work with
  Bartender."

### Include / Exclude filters

Limit which keys get the down+up behaviour, through one "Filter Mode" dropdown with three
values:

- "Off": every bound key gets the behaviour.
- "Include Mode": ONLY keys in the inclusion list get down+up behaviour.
- "Exclude Mode": ALL keys get it EXCEPT those in the exclusion list.

The dropdown is stored as the two booleans below. Only one is ever true at once.

Adding a key: with Include Mode or Exclude Mode chosen, click the box labelled "Click then
press a key", press the key (or click a non-left mouse button in the box), then click
"Add". Held CTRL/ALT/SHIFT modifiers are recorded as prefixes, e.g. "CTRL-SHIFT-F". Pure
modifier presses, Enter and Backspace cannot be captured. Each added key is drawn as a
chip. Every chip in a list is drawn at the same width, set by the longest key in it. Click
the red cross on a chip to remove it.

In mouse mode, a button's overlay is active if the button has no key bound at all, or if
any of its bound keys passes the filter.

## Settings reference

All settings are per character.

| UI label | Default | Effect |
|---|---|---|
| Keyboard Enabled | ON | Enables the keyboard down+up behaviour |
| Mouse Enabled | OFF | Enables the mouse click down+up overlays (Blizzard bars only) |
| Filter Mode | Off | Off / Include Mode / Exclude Mode, stored as the two booleans below |
| Inclusions list | empty | Keys used by Include Mode |
| Exclusions list | empty | Keys used by Exclude Mode |

## Combat restrictions

Secure bindings cannot change during combat. Toggling Keyboard/Mouse Enabled in combat is
blocked with the chat message "Can't do that during combat." Filter list edits made in
combat are saved but not applied until the next rebuild out of combat (change a setting
again, change any key binding, or reload). On Midnight (12.x) clients the settings panel
itself cannot be opened during combat.

## Troubleshooting by symptom

- "My ability fires twice / I hear the cast sound twice": expected; the action triggers on
  both press and release. Use Include/Exclude Mode to limit which keys do this.
- "I can't turn on Mouse Enabled": Bartender4 is loaded; mouse mode is incompatible with
  it and is blocked. Keyboard mode still works with Bartender.
- "Nothing changes when I toggle settings": you are probably in combat; look for the
  "Can't do that during combat." message and retry out of combat.
- "It stopped working in the house editor": intentional; bindings are suppressed while the
  housing editor is active and restored when it closes.
- "Double press doesn't happen on my vehicle bar": intentional since 2.6.0; override and
  vehicle bars fire on key-down only.
- "A key I added to the list isn't being included/excluded": check the "Filter Mode"
  dropdown is set to the matching mode; the lists only apply while their mode is chosen.
  Keys are stored with modifiers, so "F" and "SHIFT-F" are different entries.
- "Mouse clicks on my Bartender/ElvUI buttons don't double-fire": mouse mode only covers
  Blizzard action buttons. Keyboard mode covers addon bars via their key bindings.
- "I can't drop a dragged spell onto my bars with mouse mode on": should work; overlays
  disable themselves while the cursor holds a spell/item/macro. If it misbehaves, report
  it on Discord.
- "Settings differ between my characters": settings are saved per character by design.
