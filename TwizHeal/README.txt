TwizHeal 1.27.2 - one hotkey heals whoever needs it most

Priests, druids, paladins and shamans.

WHO GETS HEALED
  You and your party (or raid). Among everyone at 89% or less (/th
  threshold), the LOWEST health goes first (1.13.2) - counting the heals
  already ticking on them. Role only breaks near-ties (within 5%): tank,
  then healer, then damage dealer. Anyone in danger (30% or less) first.
  In combat the game hides health and locks the key, so no addon can pick
  the lowest by itself. TwizHeal shows you instead (1.14.0):
    - bars are colored by health even when it's hidden (the game turns it
      into a color): green, orange, red
    - a pulsing red "LOWEST >" frame marks the lowest bar when health can
      be read
  Hover the red / marked bar and press your key - that heals them.

NO HEALS ABOVE 90% IN COMBAT (1.17.0, whole bar clickable in 1.17.1)
  In combat the game hides health, so the key can't check 90% itself.
  Instead, each bar in the TwizHeal window gets an invisible mouse blocker
  in combat that the game sizes from the real health: it covers the whole
  bar when someone is at 90% or more, and nothing when they're under 90%.
  So in combat: hover or click anyone under 90% anywhere on their bar; bars
  at 90% or more can't be hovered or clicked, so they don't get healed.
  1.23.1: if your game doesn't offer the needed curve function, or it
  fails, nothing blocks the bars (the old fallback could cover every bar and
  swallow your clicks). /th guard turns the blocker off or on. /th debug
  says which mode you're in. After a fight where your presses healed
  nobody, TwizHeal prints one "last fight: ..." line - send it to Claude.
  1.24.0: the "heal whoever needs it most" key, with no bar hovered, follows
  the same rules as clicking a bar: out of combat the same rules pick the
  spell; in combat it runs the Regrowth -> Rejuvenation -> Healing Touch
  combo (and Read Leyline first when your mana was 75% or less at the pull)
  on whoever was lowest when the fight started. 1.24.1: it heals ONLY the
  lowest (or the TwizHeal bar you hover) with exactly the macro a click on
  their bar uses - your target and mouseover no longer take it over. To heal
  someone else, hover their bar (or Alt+click the game's party frames). The 90% blocker only exists on the bars - the key
  can't check health in combat, so point it with the bars when that matters.
  The instant and emergency keys are still manual overrides.
  Tanks are whoever has the tank role, whoever enemies are attacking, or
  warriors; healers are those with the healer role, or priests.

HOTS COUNT
  Healing still to come from your Rejuvenation / Regrowth on someone is
  taken off what they're missing, so nobody gets a big heal their HoT was
  about to cover. Heals are the smallest rank that covers the rest (/th
  ranks lists your heals with how much each one heals and costs).

DECURSE (1.25.0)
  Same rule as TwizBuff: when someone has a debuff you can remove (druid:
  curses with Remove Curse, poisons with Abolish / Cure Poison), a heal
  click on their bar - or the heal-the-lowest key - removes it first.
  Under 40% they get healed first. Abolish Poison already on them counts as
  handled. The heal-the-lowest key goes to someone with a removable debuff
  right after anyone in danger (30% or less).
  IN COMBAT (1.26.0) the game hides debuffs, so you pick, like the other
  hover keys: hover a bar and press the new "Decurse" key (Options >
  Keybindings > AddOns > TwizHeal). Druid: Remove Curse; hold Shift for
  Abolish Poison (Cure Poison before you learn it). Without a bar hovered
  it goes to your mouseover, then friendly target, then the lowest. Works
  out of combat too.

READ LEYLINE AT 75% MANA OR LESS (1.21.0, 75% since 1.22.1)
  Skyborne racial. Out of combat, when your mana is 75% or less and Read
  Leyline is off cooldown, the next press of your TwizHeal key (or a bar
  click) casts it instead of a heal: +50% health and mana regeneration for
  15 sec (double when Attuned at a ley line). The press after that heals as
  usual. Skipped while anyone is under 40% (they come first) and while
  you're moving (it has a 2 sec cast).
  NOT IN COMBAT (removed in 1.27.1): with Read Leyline on cooldown, its
  failed cast used up the whole press, so heal clicks in a fight cast
  nothing. In a fight, cast Read Leyline from your action bar.

TRANQUILITY: 3 OR MORE UNDER 40% (1.20.0)
  Once you've learned Tranquility (druid, level 30):
    - out of combat, 3 or more of your group under 40% (in range) -> the main
      key channels Tranquility (not while moving: Rejuvenation instead).
    - in combat the game hides health, so TwizHeal can't count: when 3 or
      more bars show the red under-40% strip, press the new "Tranquility"
      key (Options > Keybindings > AddOns > TwizHeal), or click any bar with
      mouse button 5.
    - the full channel: every TwizHeal key and bar click does nothing while
      Tranquility is channeling, so mashing keys never cuts it short. Only
      moving or a silence ends it early.

NATURE'S SWIFTNESS UNDER 40% (1.19.0)
  Once you've learned Nature's Swiftness (Restoration talent):
    - out of combat, anyone under 40% -> Nature's Swiftness, then an instant
      Healing Touch (rank sized to what's missing) in ONE press of the main
      key. On cooldown -> the normal rules below.
    - in combat the game hides health, so: bars of anyone under 40% get a red
      strip along the bottom. Hover that bar and press the new
      "Nature's Swiftness + Healing Touch" key (Options > Keybindings >
      AddOns > TwizHeal), or click the bar with mouse button 4. It casts
      Nature's Swiftness then your biggest Healing Touch, instantly.
      If Nature's Swiftness is on cooldown, that press does nothing - use
      the emergency key instead.
  Until you learn it, the new key works like the emergency key. (The red
  strip shows once you know Nature's Swiftness or Tranquility.)

WHICH SPELL - THE RULES (1.16.0)
  The combo: REGROWTH, then REJUVENATION right after, then SWIFTMEND once
  they're at 90% or under. Out of combat (health and buffs readable):
    - above 89%, PRE-HoT (1.18) -> one Regrowth, then one Rejuvenation (your
                                   top ranks), so they're HoT'd before the pull;
                                   nothing more once both are on. With nobody
                                   hurt, the key pre-HoTs everyone in turn: tank,
                                   then healer, then damage. Out of combat only.
    - above 89%, both HoTs on   -> a small Healing Touch (1.23.0: no 89% limit
      (1.23.0)                     out of combat - a press always heals; rank 1
                                   at full health). Your threshold (/th
                                   threshold) now only decides who the key picks
                                   when you don't point it at anyone.
                                   1.20.1: works even when the game hides their
                                   health or other people's buffs (only YOUR
                                   HoTs are checked). /th prehot shows, for each
                                   person, what TwizHeal sees and what it'd cast.
    - your Regrowth on them,    -> Rejuvenation (instant)
      no Rejuvenation yet
    - your HoTs on them, 90% or -> Swiftmend, when it's off cooldown
      under
    - moving                    -> Rejuvenation (instant; the combo picks up)
    - nothing on them           -> Regrowth, the rank sized to the gap
    - combo done, Swiftmend on  -> Healing Touch, the rank that covers what's
      cooldown                     still missing after the ticks
    - health hidden by the game -> nothing (instant / emergency keys still cast)
  In combat the game locks the key and hides health from addons, so:
    - main key, on a -> Regrowth, Rejuvenation, Swiftmend (once learned),
      bar under 90%      then Healing Touch on the next presses. A different
                        target, or a new fight, starts over at Regrowth. New in 1.15.0: the Healing Touch
                        here is a SMALLER rank - about 20% of your group's
                        biggest health pool, never your top rank (health can't
                        be read in combat, so a top-rank heal would often be
                        wasted). Pick it yourself: /th combatrank 3. A press
                        that fails (e.g. moving) moves on to the next spell. Swiftmend stays on the emergency key in
                        combat - in a sequence, one on cooldown would stall it.
    - instant key    -> Rejuvenation (use while moving)
    - EMERGENCY key  -> Rejuvenation, then Swiftmend on the 2nd press (both
      (new)             instant). Without Swiftmend: Rejuvenation, then
                        Regrowth. Bind it: Options > Keybindings > AddOns >
                        TwizHeal > "Emergency". Middle-click a bar does the same.
  Swiftmend is a Restoration talent - until you have it, the emergency key
  uses Regrowth as the second spell.

WHICH RANK WENT OUT (1.14.1)
  Each heal you cast shows a line above the party window for a few
  seconds, e.g. "Healing Touch (Rank 3) -> Bob" (in the middle of the
  screen when the window is hidden). /th castinfo turns it off or on.

THE PARTY WINDOW (back in 1.5.0, shown by default)
  1.27.0: laid out as a CROSS -
                 [ tank ]
        [ dps ]  [ dps ]  [ dps ]
                 [healer]
  Roles come from the group's role setting (the role icons). If nobody has
  a role set: bar 1 (you) on top, bars 2/3/4 in the middle, bar 5 at the
  bottom. The window rearranges itself when roles change (out of combat -
  bars can't move in a fight). Drag the corner grip to resize: width sets
  each bar's width (all three columns), height sets the bar height.
  1.27.2: the window background is transparent - only the bars show, and
  the empty corners of the cross click straight through to the game.
  Hover a bar and press your TwizHeal key: it heals that person (in combat
  only if they're under 90% - see 1.17.1 above). Clicking a bar
  heals them too.
  No title bar - just the bars. Each bar has a thin row under it: mana
  (blue, shown even in cat/bear form) and energy/rage beside it.
  Each bar shows a role icon (tank / healer / dps) and a colored border
  when something bad is on them:
    purple  curse          green   poison        brown  disease
    blue    magic          white   rooted        yellow stunned/feared
    red     any other harmful effect
  Curses and poisons win when several are on someone (druids can remove
  those). Stuns and fears are only known for you; for others a root is
  recognized by its name (Entangling Roots, Frost Nova, nets, webs...).
  Incoming heals: a light green extension past the end of someone's
  health shows how far the heals on the way will fill them - your casts
  and everyone else's (the game's heal prediction). "+450" beside the
  percent is the amount. When the game sends no prediction, the rest of
  your own HoTs on them is shown instead. If the game hides the amount,
  the bar still shows it but the number is left out.
  Health is shown as exact numbers and percent: "1500 / 2000  75%".
  Shields (Power Word: Shield, Ice Barrier, Mana Shield...): a pale blue
  section after the incoming heals shows how much damage the shield will
  soak, the shield's icon and amount appear beside the health text, and the
  bar gets a soft blue glow while it's up.
  Your buffs on each person (Mark of the Wild, Thorns, Rejuvenation...)
  show as small icons in the top-right corner of their bar, with a sweep
  showing how much time is left.
  Text and icons scale with the bar and never overlap: on tall bars the
  buff icons sit on top with the numbers underneath; on short bars it's all
  one line. Long names are cut short, and when space is tight the health
  shows just the percent.
  Move: drag a bar. Resize: drag the grip in the bottom-right
  corner - width sets the bar width, height sets the bar height. Both are
  saved, and only work out of combat. /th window hides or shows it.

ON THE GAME'S PARTY AND RAID FRAMES
  TwizHeal also works on the normal party and raid frames:
    - Hover a party/raid frame and press your TwizHeal key (or the TwizBuff
      key).
    - Or Alt+click a frame: same rules, on that person. Plain clicks still
      target and open the menu as before.
    - /th clicks turns the Alt-click healing off or on.
  Works on the player, target, focus, party and raid frames, including raid
  frames the game creates later.

USE
  Bind a key: Options > Keybindings > AddOns > TwizHeal.
  The key heals whoever you hover, else your friendly target, else
  TwizHeal's pick (or the tank when health is hidden). Every heal needs a
  key press or click - no addon can cast on its own.

WHEN THE GAME HIDES HEALTH (WoW: Forever does)
  This client hides everyone's health from addons ("secret" values) - even
  out of combat. Addons may draw health bars from it but not compare it, so
  TwizHeal can't work out who is lowest by itself. Hover the lowest frame
  and press your key. The window says "health hidden - hover the lowest
  bar" in this mode.
  Druids: the key drops cat/bear/travel form first, since heals can't be
  cast in those forms.

WHEN A PRESS DOESN'T HEAL (new in 1.4.1)
  TwizHeal says why in chat, e.g. "couldn't heal Pharama Grade: Out of
  range." Faded party/raid frames mean that person is out of range.
  /th test shows exactly what the key will cast and on whom.
  /th quiet turns these messages off or on.
  Casts use the plain spell name (your best rank): this client silently
  ignores "/cast Healing Touch(Rank 3)". The rules still choose which
  spell - HoT, fast heal or direct heal.

COMMANDS (/th or /twizheal)
  /th window        show / hide TwizHeal's party window
  /th clicks        Alt-click healing on the game's party/raid frames
  /th danger 30     heal anyone at 30% or less first, whatever their role
  /th threshold 90  people below 90% are worth a heal
  /th ranks         list your heals
  /th debug         what TwizHeal can see (heals found, whether health is
                    hidden) - handy if the window looks empty
