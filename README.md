# LAFW Community

The Love At First Wipe community addon for **World of Warcraft: Forever**.

Our community is a Blizzard Group, so both factions and every server can be in it. Blizzard Groups show everyone by BattleTag; this addon shows the character each member is playing instead, and a few things that make the group feel more like a guild.

## What it does

- **Character names instead of BattleTags**, in the group chat, the Communities member list and the LAFW tab. The game tells the addon which character every online member is playing, on any server or faction, and nobody needs to set anything up.
- **Offline members** show by the character you've seen them play the most, once you've seen them online since you logged in (the game gives no lasting way to tell members apart, so the addon recognizes people by their characters).
- **Their characters:** hover a member in the LAFW tab to see every character the addon has seen them play.
- **The LAFW tab** in the Communities window: everyone's character, class, level, zone, faction and status (online, away, busy, on the Battle.net app, in another game, offline), a faction filter, and right-click to whisper or invite someone of your faction, or send a Battle.net whisper to anyone.
- **Login and logout alerts** in chat, like guild members': "Pally Dude has come online."
- **Who's online** when you hover the minimap button.
- **`/l` talks in the group**, like `/p` for party. The group chat is added to your General chat tab the first time; remove it there if you prefer (right-click the tab > Settings > Channels).

The addon learns members' characters as it sees them, while you're both online, so their character lists fill up as you play.

## Install

1. Download the newest `LAFWCommunity-…-forever.zip` from [Releases](https://github.com/QBallStan/LAFWCommunity/releases) (not the green "Code" button).
2. Unzip it into `World of Warcraft\_forever_\Interface\AddOns\`, so you end up with `AddOns\LAFWCommunity\LAFWCommunity.toc`.
3. Restart the game.

To update, do the same with the newest release: replace the old `LAFWCommunity` folder.

## In game

Click the **book button on your minimap** for the settings (names, alerts, the minimap button, the group chat). Right-click it for the roster, or open the **LAFW** tab in the Communities window.

## Commands

You shouldn't need them, but:
- `/lafw`: the roster. `/lafw settings`: the settings window.
- `/lafw test`: a report for troubleshooting. Run it, then `/reload`, and send the result to whoever maintains the addon.
