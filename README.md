# TwizForever - WoW: Forever addons

Custom addons for World of Warcraft: Forever (interface 16001), written by Alan Sherbourne.

| Addon | What it does | Version |
|---|---|---|
| **DepositWise** | Auction House profit tool: what to post, for how long and at what price (deposits, AH cut and learned sell speed included), when to vendor instead, deals, low bids, market movers, smelt-or-sell ore, craft-or-sell for every profession, and Buy All Supplies for profitable crafts. | 2.1.0 |
| **QuestRoute** | Plans which quests to do and in what order for the most XP per hour from where you stand, using Questie's database. Learns your kill speed, rest time, travel speed and real XP rates; counts quest items in your bank. | 1.3.1 |
| **CraftRoute** | Cheapest path to level each profession: recipe per skill range, how many, shopping list, cheapest shopping route, buy from vendors/AH, and craft straight from the window. Learns your real skill-up odds. | 1.4.0 |
| **AutoChef** | Remembers your cooking recipes and, at a vendor, buys the missing ingredients for the best recipes your bag ingredients can make (highest level, buff suited to your class/spec). | 1.0.0 |
| **AutoOpen** | Opens chests, boxes, gifts, clams and other containers in your bags automatically - never in combat, while looting, or at a vendor/bank/mail/trade/AH. | 1.0.0 |

## Install

Copy the addon folders you want into your game's `Interface/AddOns` folder, e.g.

- Windows: `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\`
- Linux (Lutris/Wine): `~/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/`

Fully restart the game (not just `/reload`) the first time.

## Requirements

- **QuestRoute** needs **Questie** (quest database). **TomTom** is optional for the arrow.
- **CraftRoute** uses **AtlasLoot Classic** for skill-up colors, **DepositWise** for AH prices and **QuestRoute** for vendor/bank locations (all optional, but it's much better with them).
- **DepositWise**'s Craft tab reads recipes recorded by **CraftRoute** and **AutoChef**.

## Commands

| Addon | Slash command | Help |
|---|---|---|
| DepositWise | `/dw` | `/dw help` |
| QuestRoute | `/qr` | `/qr help` |
| CraftRoute | `/cr` | `/cr help` |
| AutoChef | `/chef` | `/chef help` |
| AutoOpen | `/ao` | `/ao help` |

Each addon folder has its own `README.txt` with details.
