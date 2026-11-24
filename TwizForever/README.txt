TwizForever 1.2.0 - one menu for all the Twiz addons
=====================================================

/twiz (or click the gear on the minimap) opens a window listing every Twiz
addon: TwizAH, TwizQuest, TwizCraft, TwizChef, TwizBuff, TwizHeal, TwizHunt,
TwizOpen and TwizErrors.

Left: each addon with its icon and state - on (with its version), off,
"on/off after reload", or not installed.

Right, for the addon you click:
  - what it does and its slash command
  - "Addon on (this character)" - turn the whole addon on or off. Takes
    effect after Reload UI (button at the bottom right).
  - Settings - its main on/off options as checkboxes. They're read from the
    addon's own saved settings and changed through its own slash command,
    so it reacts right away (exactly as if you'd typed the command).
  - Actions - one-click buttons: open its window, scan, share, report...

Esc closes the window. Drag the minimap gear around the minimap to move it.

Commands
  /twiz            open / close the menu
  /twiz minimap    show / hide the minimap button

1.1.0: each addon's row shows how many Lua errors it threw this session (from
TwizErrors' error catcher), plus the new settings: TwizQuest keyboard dialogue
and flight timer, TwizErrors error catching, and a "Caught errors" button.

1.2.0: TwizHunt added; TwizQuest's minimap line, trainer stops and hearth info.
