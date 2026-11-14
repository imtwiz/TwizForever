-- TwizCraft: buying on the AH moves the item from "to buy" to "in the mailbox"
local REPO = REPO
SIM.items[2589] = { name = "Linen Cloth", vendor = 13, classID = 7 }
local NS = SIM.LoadAddon(REPO .. "/TwizCraft", "TwizCraft")
SIM.Fire("ADDON_LOADED", "TwizCraft"); SIM.Fire("PLAYER_LOGIN"); SIM.Advance(2)
local replans = 0
local orig = NS.Replan
NS.Replan = function(...) replans = replans + 1 if orig then return orig(...) end end
-- pretend TwizCraft's AH button is mid-purchase of 20 Linen Cloth
NS.ah.state, NS.ah.item = "buying", { id = 2589, buy = 20 }
SIM.Fire("COMMODITY_PURCHASE_SUCCEEDED"); SIM.Advance(0.5)
SIM.log[#SIM.log + 1] = ("after purchase: mailbox has %d, owned %d, replans %d"):format(NS.MailCount(2589), NS.Owned(2589), replans)
SIM.Advance(4)
SIM.log[#SIM.log + 1] = ("3s later (still in mail): mailbox %d"):format(NS.MailCount(2589))
-- open the mailbox: the real inbox says 20 linen + 5 wool from an alt
SIM.items[2592] = { name = "Wool Cloth", vendor = 33, classID = 7 }
SIM.mail = { { sender = "Auction House", subject = "Auction won: Linen Cloth", items = { { id = 2589, count = 20 } } },
             { sender = "Twizalt", subject = "mats", items = { { id = 2592, count = 5 } } } }
MailFrame.__shown = true; SIM.Fire("MAIL_SHOW"); SIM.Advance(1)
SIM.log[#SIM.log + 1] = ("inbox scanned: linen %d, wool %d"):format(NS.MailCount(2589), NS.MailCount(2592))
-- take the linen
AutoLootMailItem(1); SIM.Advance(1)
SIM.log[#SIM.log + 1] = ("after taking linen: mailbox linen %d, bags linen %d"):format(NS.MailCount(2589), NS.BagCount(2589))
MailFrame.__shown = false; SIM.Fire("MAIL_CLOSED")
-- a purchase that goes straight to bags isn't double counted
NS.ah.state, NS.ah.item = "buying", { id = 2592, buy = 10 }
SIM.Fire("COMMODITY_PURCHASE_SUCCEEDED"); SIM.PutInBags(2592, 10); SIM.Advance(4)
SIM.log[#SIM.log + 1] = ("bought 10 wool straight to bags: mailbox wool %d (5 from the alt)"):format(NS.MailCount(2592))
