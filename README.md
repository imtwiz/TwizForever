# TwizForever - WoW: Forever addons

Custom addons for World of Warcraft: Forever (interface 16001), written by Alan Sherbourne.

| Addon | What it does | Version |
|---|---|---|
| **TwizAH** | Auction House profit tool: what to post, for how long and at what price (deposits, AH cut and learned sell speed included), when to vendor instead, deals, low bids, market movers, smelt-or-sell ore, craft-or-sell for every profession, Buy All Supplies for profitable crafts, cheapest missing recipes with Buy All and a max spend, undercut watch with cancel-and-repost, and one-click AH mail collection. | 2.4.9 |
| **TwizQuest** | Plans which quests to do and in what order for the most XP per hour from where you stand, using Questie's database. Learns your kill speed, rest time, travel speed and real XP rates; counts quest items in your bank; plans around rested XP, groups, sell & repair stops; target key; log cleanup. | 1.12.0 |
| **TwizCraft** | Cheapest path to level each profession: recipe per skill range, how many, shopping list, cheapest shopping route, buy from vendors/AH, craft straight from the window, and tracks AH purchases waiting in your mailbox. Learns your real skill-up odds. | 1.13.1 |
| **TwizChef** | Remembers your cooking recipes and, at a vendor, buys the missing ingredients for the best recipes your bag ingredients can make (highest level, buff suited to your class/spec); one-key eat/drink and cook, drink restock, Well Fed reminder. | 2.0.1 |
| **TwizOpen** | Opens chests, boxes, gifts, clams and other containers in your bags automatically - never in combat, while looting, or at a vendor/bank/mail/trade/AH. | 1.0.0 |

## Install

Copy the addon folders you want into your game's `Interface/AddOns` folder, e.g.

- Windows: `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\`
- Linux (Lutris/Wine): `~/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/`

Fully restart the game (not just `/reload`) the first time.

## Requirements

- **TwizQuest** needs **Questie** (quest database) and **TomTom** (waypoint arrow).
- **TwizCraft** needs **TomTom** (waypoint arrow for shopping and mailbox stops).
- **TwizCraft** uses **AtlasLoot Classic** for skill-up colors, **TwizAH** for AH prices and **TwizQuest** for vendor/bank locations (all optional, but it's much better with them).
- **TwizAH**'s Craft tab reads recipes recorded by **TwizCraft** and **TwizChef**.

## Commands

| Addon | Slash command | Help |
|---|---|---|
| TwizAH | `/dw` | `/dw help` |
| TwizQuest | `/tq` | `/tq help` |
| TwizCraft | `/tc` | `/tc help` |
| TwizChef | `/chef` | `/chef help` |
| TwizOpen | `/ao` | `/ao help` |

Each addon folder has its own `README.txt` with details.

## Testing

`tools/wowsim` runs the addons in a simulated WoW client (LuaJIT, Lua 5.1) so bugs show up before you log in: `python3 tools/wowsim/run.py --all`. See its README.
