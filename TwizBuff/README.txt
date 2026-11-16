TwizBuff 1.0.0 - cast the buffs your friends are missing

Shows who is missing the buffs your class can give, and casts the next one
with one click, key press or mouse-wheel notch.

WHO
  You, your party (or raid), and your target when it's a friendly player -
  so you can buff passers-by too.

WHAT
  Only spells you know:
    Druid    Mark of the Wild (Gift of the Wild for 3+ in your group)
             Thorns (off by default: /tb thorns)
    Priest   Power Word: Fortitude (Prayer of Fortitude), Divine Spirit
             (mana users), Shadow Protection (off by default: /tb shadow)
    Mage     Arcane Intellect (Arcane Brilliance) - mana users only
    Paladin  a Blessing: Kings if you have it, else Wisdom for mana users
             and Might for everyone else; anyone with a blessing is skipped
    Warrior  Battle Shout when you don't have it
  When 3 or more people in your group need the same buff and you know the
  group version and have its reagent, it casts that instead.

USE
  The window lists who needs what (out-of-range people are greyed out) and
  the gold button casts the next buff - your target first, then you, then
  everyone in range. The window hides itself when everyone is buffed.
  The game needs a real click/key/wheel notch for every cast, and the button
  can only be re-aimed out of combat.

  Bind a key: Options > Keybindings > AddOns > TwizBuff.

COMMANDS (/tb or /twizbuff)
  /tb               show / hide the window
  /tb wheel on|off  cast the next buff with the mouse wheel (out of combat,
                    only while someone is missing a buff)
  /tb auto          hide the window when everyone is buffed (on by default)
  /tb shadow        include Shadow Protection (priests)
  /tb thorns        include Thorns (druids)
  /tb group N       use the group version when N or more need it (default 3)
