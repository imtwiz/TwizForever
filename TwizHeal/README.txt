TwizHeal 1.7.0 - one hotkey heals whoever needs it most

Priests, druids, paladins and shamans.

WHO GETS HEALED
  You and your party (or raid). Among everyone missing enough health to be
  worth a heal (below 90%, or missing more than your smallest heal):
    1. tanks, 2. healers, 3. damage dealers - lowest health first in each.
  Anyone in danger (30% or less) is healed first, whatever their role.
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

WHICH SPELL - THE RULES (new in 1.4.0, no Shift/Ctrl)
  One key, no modifiers. TwizHeal decides:
  Out of combat (it rewrites the key as you move, hover and target):
    - you're moving                     -> your HoT (Rejuvenation, Renew):
                                           it's instant, so it casts on the run
    - they're under half health         -> a real heal sized to the gap
                                           (Regrowth if it isn't on them,
                                           else Healing Touch / Heal)
    - topping off, no HoT of yours on   -> your HoT (cheap, ticks while
      them                                 everyone drinks)
    - topping off, your HoT already on  -> the smallest direct heal that
                                           covers what's missing
  In combat the game locks the key and doesn't tell macros whether you're
  moving, so it's one fixed rule:
    - standing -> your fast heal (Regrowth, Flash Heal, Flash of Light...)
    - moving   -> the fast heal can't start, so your HoT goes out instead
  /th test shows what the key will do and who it will heal.
  When the game hides health or buffs, the rules that need them are skipped
  (no endless re-casting of a HoT it can't see).

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
