TwizOpen 1.0.0 - auto-opens containers in your bags

Opens anything with "<Right Click to Open>" or that the game marks as
lootable: chests, boxes, crates, gifts, presents, clams, shells, bags of
loot, etc. One at a time, with a short pause between each.

It will NOT open:
  - locked lockboxes (once a rogue picks it, it opens)
  - items you don't meet the level/skill requirement for
  - anything while you're in combat, dead, casting, looting, holding an
    item on the cursor, or have a vendor, bank, mailbox, trade window,
    Auction House or guild bank open
  - anything when your bags have fewer free slots than you set (default 1)
If something still fails to open twice, it's skipped until /reload.

Commands (/ao or /autoopen):
  /ao                 turn on/off
  /ao status          settings, and how many items are waiting
  /ao ignore [item]   never open it (shift-click the item into chat)
  /ao unignore [item] allow it again
  /ao ignored         list ignored items
  /ao quiet           toggle the "opened ..." chat messages
  /ao free N          keep N bag slots free before opening
  /ao retry           retry items skipped this session
