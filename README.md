# LAFW Community

The Love At First Wipe community addon for **World of Warcraft: Forever**.

Our community is a Blizzard Group, so both factions can be in it. Blizzard Groups show everyone by BattleTag; this addon shows the characters people are actually playing, and a few more things that make the group feel like a guild.

## What it does

- **Character names instead of BattleTags** in the community chat, the Communities member list and the LAFW tab. Pick your main once, and your other characters show as "Alt - Main".
- **The LAFW tab** in the Communities window: each member's current character, whether it's their main or an alt, its class and professions. Click a member to see their other characters.
- **`/l` talks in the community**, like `/p` for party. The community chat is added to your General chat tab the first time; remove it there if you prefer (right-click the tab > Settings > Channels).
- **Its own chat color**, picked so it doesn't look like whispers or any other chat.

Names, mains, alts, levels and professions are shared through a channel in the group called **LAFW data**, so every member who runs the addon sees everyone else's, whatever their server or faction. You never have to look at it: the addon keeps it out of your chat, turns its notifications off and marks it read. It only shows if you pick it in the Communities window. The addon posts there when you log in on a different character, change your main, level up or skill up (those at most every 10 minutes), right after your next key press or click (the game only lets addons post in a group then). *Share now* in the settings window posts right away. Your Battle.net friends' characters show even if they don't run the addon.

## Install

1. Download the newest `LAFWCommunity-…-forever.zip` from [Releases](https://github.com/QBallStan/LAFWCommunity/releases) (not the green "Code" button).
2. Unzip it into `World of Warcraft\_forever_\Interface\AddOns\`, so you end up with `AddOns\LAFWCommunity\LAFWCommunity.toc`.
3. Restart the game.

To update, do the same with the newest release: replace the old `LAFWCommunity` folder.

## First time in game

Click the **book button on your minimap** (or the *My characters* button in the LAFW tab):
- under **Your main**, click *Set main* on your main. Every other character on the same server counts as its alt. A character shows up in the list once you've logged in on it with the addon;
- the other options are there too: first names only, show BattleTags, the community `/l` uses, the minimap button.

Right-click the minimap button to open the roster.

## For the group owner

Add the channel once: in the Communities window, open the channel list at the top of the chat ("General") > **Create Channel**, name it `LAFW data`, and leave "Leaders and moderators only" unticked.

## Commands

You shouldn't need them, but:
- `/lafw`: the roster. `/lafw settings`: the settings window.
- `/lafw test`: a report for troubleshooting. Run it, then `/reload`, and send the result to whoever maintains the addon.
