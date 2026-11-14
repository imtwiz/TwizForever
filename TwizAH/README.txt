TwizAH - Auction House profit planner for WoW: Forever
===========================================================

INSTALL
  Unzip so the folder sits at  Interface\AddOns\TwizAH  inside your
  WoW Forever game folder. Fully restart the game (not just /reload) the
  first time. If it doesn't appear in the AddOns list, tick
  "Load out of date AddOns".

USE
  Open the Auction House. The TwizAH panel docks to its right and
  researches everything in your bags that can be auctioned.

  Briefing tab (opens first; /dw shows it anywhere, not just at the AH)
    A short plain-English rundown: how fresh your price data is, market
    trends, what your bags are worth on the AH vs a vendor, what to post and
    the deposits you'll put up, the best below-vendor buy, the best flip, and
    your session gold.

  Movers tab
    Items whose median price moved 10%+ since the previous day you did a
    full scan. Needs full scans on two different days.

  Session tab
    Gold change and gold per hour since login, auctions posted, and deposits paid.

  My Bags tab
    For each item: the price to post at (always 1 copper under the cheapest
    Buyout so you're first in line; if the cheapest listing is already
    yours, it matches it), how many sell per day, the best listing
    time, the deposit, the expected take-home, what a vendor pays, and a
    verdict:
      Post      - the AH beats the vendor by at least your minimum gain
      Marginal  - the AH wins, but not by enough to be worth the bother
      Vendor    - after the 5% cut and the deposits you'd likely lose, vendor it
      No comp.  - nobody is selling it; set your own price
    Hover a row for the full breakdown. Double-click a row, or use
    "Post Next Best", to list it (one click = one post; the game requires that).

  Deals tab - everything on the AH worth turning a profit
    "Full AH Scan" downloads every listing (allowed once every 15 minutes).
    Four kinds of opportunity, ranked by expected profit:
      To vendor   - listed below what a vendor pays. Buy, vendor, no risk.
      Flip        - cheap listings well under the next seller's price. Buy them
                    and relist 1c under that seller.
      Dip         - well below its usual price over the last few days (needs
                    3+ days of scans). Speculative.
      From vendor - a merchant sells it for less than the AH pays. Prices are
                    learned whenever you open a merchant.
    Buy amounts are sized to what the learned sell rate says will sell in
    about 48h (capped at 20 until rates are learned). Profit is after the
    cut and expected deposit losses. Your own listings are never counted.
    Hover a deal for the plan; click to search the AH for it.
    Hide small stuff with /dw minprofit 10s and /dw minroi 10 (defaults: 5s profit, 10% ROI).

  Filters (top of the Deals tab)
    All / Mats / Gems / Cloth / Metal / Herbs / Leather / Enchant / Elemental /
    Cooking / Gear. "Mats" = every crafting material category together.
    Quick flips: only deals that turn around fast - vendor flips (instant) or
    relists the learned sell rate says will sell out within about 24 hours.
    Hover a deal to see "Expected to sell out in ~X h". Filters apply to
    Low Bids too. Slash: /dw filter cloth, /dw quick on.

  Low Bids (button on the Deals tab)
    Gear and other non-commodity auctions whose next bid is at most 35% of
    what the item is worth to you (vendor value, or what you'd net relisting
    it after the cut and deposit risk). Each is rated:
      Safe    - even selling it to a vendor beats the bid
      High    - sell speed is learned and it moves fast enough to relist
      Unknown - hidden by default (/dw bidunknown on to show)
    You only win if you're the top bidder when it ends, so bids with little
    time left are the best snipes. Click one to find it in the Buy tab.
    /dw bidpct 35 changes how low "extremely low" is.

  Auto-vendor
    When you open any merchant, items a vendor pays more for than you'd net
    on the AH are sold automatically. Safety rules:
      - only with an AH price from the last 30 minutes (from opening the AH
        or a full scan). Older data = it skips and tells you to scan first
      - never soulbound items (nothing to compare on the AH)
      - at most 12 per visit, because the merchant's Buyback tab holds 12;
        anything sold by mistake can be bought back
      - hold Shift while opening the merchant to skip it once
      - /dw autovendor off to turn it off

  Tooltips
    Item tooltips show the last seen AH low, what you'd net after the cut,
    the market median, how many sell a day (and the chance for 2h/8h/24h),
    and how your own auctions of it have done.

WHAT'S NEW IN 2.3.0
- Post All button (My Bags): works down everything worth posting - the best
  items first, then marginal ones that still turn a profit. The game allows one
  post per click, so keep clicking or bind "Post All" in Options > Keybindings >
  AddOns and tap it. /dw postall does the same. Items better vendored, quest
  items and items with no AH price are skipped.
- Profession tools: one of each kind is always kept (your best one - soulbound
  or equipped counts first; a Gnomish Army Knife covers several kinds). Spare
  copies can be sold. Added Flint and Tinder, Thieves' Tools and Salt Shaker.
  Tools are still never bought from the AH.

WHAT'S NEW IN 2.2.2
- Page buttons: when a list (My Bags, Deals, Movers...) has more items than fit
  in the window, "< Prev  Page 1/3  Next >" appears at the bottom right.
  The mouse wheel still scrolls too.

WHAT'S NEW IN 2.2
  - Auction lengths fixed: Forever auctions are 2h / 8h / 24h (not 12/24/48).
    Listing times, sell chances and labels now match the game.
  - Full scans no longer fail silently: if the AH doesn't answer within a
    minute you can retry right away, and closing the AH mid-scan throws the
    partial scan away instead of saving half the market.
  - Sell rates: time-left aware and repost-aware (see below). Demand learned
    by older versions was halved once, since it was counted too generously.
  - My Auctions tab: every auction you have up, the cheapest other seller,
    how many cheaper units are ahead of yours, and "Cancel Undercut" for the
    ones worth reposting (not if it ends within 30 minutes, has bids, or the
    repost wouldn't clear its new deposit 5x).
  - Collect AH Mail button on the mailbox: takes gold from sales and items
    from expired/cancelled auctions. Never touches player mail or COD.
  - Your sales are now actually learned (from AH mail and your auctions list).
  - Auto-vendor never sells: anything you bought in the last 2 hours,
    materials for profitable crafts, TwizCraft's current plan, or TwizChef
    ingredients (on top of quest items, tools and /dw exclude).
  - Low Bids show when each auction ends; ones ending soonest come first.
  - Deals tab explains an empty list when a filter is hiding everything.
  - Faster and lighter: redraws are batched, the Craft list is cached, and
    saved data is stored compactly (about half the size, loads faster).

  My Auctions tab
    Opens on its own when you visit the AH. Status per auction: Cheapest,
    Undercut (with how many cheaper units are ahead of you), Has bids (can't
    be cancelled) or Sold. "Cancel Undercut" cancels the next one worth it -
    one per click, the game requires it. The item comes back by mail; collect
    it and repost from My Bags. Key binding available.

  Collect AH Mail (button under the mailbox)
    One click takes everything from Auction House mail, one mail at a time.
    Stops if your bags fill up.

HOW SELL RATES ARE LEARNED
  Every full scan is compared with the previous one (if they're 15 min to
  6 hours apart). Units that disappeared from near the cheapest price count
  as bought - except listings whose time could have run out in between
  (each listing's time left is recorded), and new listings that show up
  below the old cheapest are treated as probable cancel-and-reposts and half
  their amount is taken off. Forever's scan doesn't name sellers, so this
  errs on the low side on purpose: deposits only get risked on things that
  really sell. It also counts how often someone lists below the cheapest
  price. From that:
    time you stay cheapest  = how long until you're likely undercut
    sell chance             = expected share of your stack bought in that time
  Your own results are blended in per item. They're learned from AH mail
  ("Auction successful" / "Auction expired"), from your owned-auctions list
  and from the "A buyer has been found..." chat message - each sale counted
  once. Once you have 8+ results for a listing length they also replace the
  starting guesses. Older scans fade out, so the rates follow the market.
  Full scans run automatically when you open the AH and every 15 minutes
  while it's open (/dw autofull off to stop).

HOW THE MATH WORKS
  The deposit comes back when an item sells and is lost when it expires.
  If an undercut listing sells with chance p per listing period, and you
  relist until it does, you lose on average  deposit x (1-p)/p  along the way.
    Expected = price x qty x (1 - cut)  -  deposit x (1-p)/p
  This is worked out for Forever's 2h, 8h and 24h auctions; the best one is
  chosen (counting every extra relist as a small cost in your time, so tiny
  deposits don't push everything to 2h) and then compared with the
  guaranteed vendor price. Deposits come straight from the
  game, so changes Blizzard makes to deposit rules are picked up automatically.

EXCLUDED ITEMS
  Profession tools (Mining Pick, Blacksmith Hammer, Skinning Knife, fishing
  poles, runed enchanting rods, Arclight Spanner, etc.) are never bought,
  bid on, suggested for posting, or auto-vendored.
  Items an active quest in your quest log needs (e.g. "Linen Cloth: 3/10"),
  including finished-but-not-turned-in quests, are never suggested for
  posting or auto-vendored. Buying them in Deals is still allowed.
  /dw exclude [shift-click item]   add your own
  /dw include [shift-click item]   undo (also overrides the built-in list)

SETTINGS (slash commands)
  /dw                      toggle the panel
  /dw scan | fullscan      rescan bags / full AH scan
  /dw cut 5                AH cut in percent
  /dw rates 30 55 75       starting guesses for 2h/8h/24h, used only until rates are learned
  /dw autofull on|off      automatic full scans at the AH
  /dw auctions             My Auctions tab; /dw cancel = cancel next undercut (bindable)
  /dw mail                 collect gold and items from AH mail
  /dw mingain 5s           how much the AH must beat the vendor by
  /dw threshold 60         Deals: % of median that counts as underpriced
  /dw autoscan on|off      scan bags automatically when the AH opens
  /dw autovendor on|off    auto-sell to merchants when the vendor pays more
  /dw minprofit 10s        hide deals making less
  /dw minroi 10            hide deals returning less than 10%
  /dw tooltip on|off
  /dw settings             show current settings


  Smelt tab (new in 1.7)
    For every ore in your bags: is it worth more to smelt it into bars, or
    sell the ore? Both sides are valued the TwizAH way - lowest AH
    price minus 1c, the AH cut, deposits you'd likely lose for how fast
    each one sells, or the vendor price if that's higher. Leftover ore
    from 2-ore smelts is counted as ore.
      Smelt     - bars pay at least your minimum gain more (/dw mingain)
      Sell ore  - the ore pays more
      Either    - within your minimum gain: sell the ore, save the time
      Smelt*    - bars pay more, but you can't smelt it (skill/recipe)
    Bar prices are looked up automatically with your bag scan when you
    open the AH. Open your Mining window once so it uses the exact
    recipes you know. Ore tooltips show the answer too.
    /dw smelt prints the list in chat.

  Craft tab (new in 2.0)
    Every recipe you know, all professions (recipes come from TwizCraft -
    open each profession window once - and TwizChef for cooking):
      From your bags: craft with the materials you have and sell the
      result, or sell the materials as they are? Vendor supplies (thread,
      spices, vials) are counted at their price.
        Craft      - crafting pays at least your minimum gain more
        Sell mats  - the materials are worth more as they are
        Either     - within your minimum gain
      Buy & craft: buying every material at the cheapest price (AH or
      vendor) and selling the result still makes a profit. "How many" is
      sized to what sells in about 2 days once sell speed is learned.
    Products are priced during your bag scan; a full scan prices the rest.
    /dw craft prints the list in chat. Click a row to search the AH.

  Buy All Supplies (Craft tab, new in 2.1)
    Totals what every Craft and Buy & craft row needs, subtracts what's in
    your bags and bank, and buys the rest from wherever it's cheapest:
      AH: click "Buy All Supplies" - first click gets the price, second
      confirms (the game requires both), then it moves to the next reagent.
      A red price means over 1.5x its usual market price; Cancel skips it.
      Vendor: a "Buy Craft Supplies" button appears on the merchant window
      for thread, vials, flux, spices, etc. that the merchant sells.
    Key binding: Options > Keybindings > AddOns > TwizAH > Buy All
    Supplies. Macro: /dw buysupplies.
