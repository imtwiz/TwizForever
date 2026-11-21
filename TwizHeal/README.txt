TwizHeal 1.14.2 - one hotkey heals whoever needs it most

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
  Hover the red / marked bar and press your key - that heals them. Without
  a hover the key heals whoever was lowest when the fight started.
  Tanks are whoever has the tank role, whoever enemies are attacking, or
  warriors; healers are those with the healer role, or priests.

SMART HEALING WITH HOTS (new in 1.1.0)
  Your HoTs count: healing still to come from your Rejuvenation / Renew /
  Regrowth on someone is taken off what they're missing, so nobody gets a
  big heal their HoT was about to cover.
    - small damage and none of your HoTs on them -> Rejuvenation / Renew
      (the cheapest healing you have)
    - druids, medium damage and no Regrowth on them -> Regrowth (direct
      heal plus its own HoT)
    - a tank with no HoT of yours -> a HoT to keep them ticking, but only
      when nobody else needs healing
    - danger -> fast heal; big damage -> the direct heal sized to what's left
  The bars show your HoTs and seconds left (e.g. "Rejuv 9").

WHICH HEAL
  The smallest rank of your direct heal that covers what they're missing
  and that you have the mana for (Lesser Heal / Heal / Greater Heal,
  Healing Touch, Holy Light, Healing Wave). Someone in danger gets your fast
  heal (Flash Heal, Regrowth, Flash of Light, Lesser Healing Wave).
  /th ranks lists your heals with how much each one heals and costs.

WHICH SPELL - THE RULES (1.12.0)
  Out of combat TwizHeal reads how hurt they are and what's ticking on them,
  and DOWNRANKS (new in 1.13.0): it casts the smallest rank that still heals
  everything they're missing - e.g. Healing Touch rank 3 for a 155 HP gap
  instead of your top rank - to save mana. (Lower ranks are cast by spell
  ID through a hidden button, since "/cast Healing Touch(Rank 3)" does
  nothing on this client.) In combat it's always your top rank.
    - above 89%                -> no heal at all (change it: /th threshold 80)
    - health hidden by the game -> no heal either: it might be 95%. Your
                                  instant and emergency keys still cast.
    - under 31%                -> Swiftmend if your Rejuvenation or Regrowth is on
                                  them (an instant save). Swiftmend ready but
                                  nothing on them: Rejuvenation now, Swiftmend on
                                  the next press. No Swiftmend: Regrowth.
    - you're moving            -> Rejuvenation (instant)
    - your Regrowth already on -> Healing Touch, the rank that covers what's
      them                        still missing after Regrowth's ticks
    - big gap (under 60%, or   -> Regrowth (a big heal now plus a HoT); Healing
      more missing than one       Touch if your Regrowth is already ticking
      Rejuvenation heals)
    - small gap, no Rejuv on   -> Rejuvenation (cheap, heals over time)
    - small gap, Rejuv on      -> a small Healing Touch for what it won't cover
  In combat the game locks the key and hides health from addons, so:
    - main key       -> Regrowth, then Healing Touch on the next presses
                        (back to Regrowth after 12 s without a press)
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
  Hover a bar and press your TwizHeal key: it heals that person, in or out
  of combat. Clicking a bar heals them too.
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
