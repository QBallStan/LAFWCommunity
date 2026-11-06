# LAFW Community

The Love At First Wipe community addon for **World of Warcraft: Forever**.

Our community is a Blizzard Group, so both factions and every server can be in it. Blizzard Groups show everyone by BattleTag; this addon shows the name each member chose instead, and a few things that make the group feel more like a guild.

## What it does

- **Your chosen name instead of your BattleTag**, in the group chat, the Communities member list and the LAFW tab. The name is your **member note** in the group, so everyone with the addon sees it, whatever their server or faction.
- **Battle.net friends** who haven't set a name show by the character they're playing.
- **Login and logout alerts** in chat, like guild members': "Pallydude has come online."
- **The LAFW tab** in the Communities window: everyone's name and status (online, away, busy, on the Battle.net app, offline). For your Battle.net friends also what they're playing and where, and right-click to invite them.
- **Who's online** when you hover the minimap button.
- **`/l` talks in the group**, like `/p` for party. The group chat is added to your General chat tab the first time; remove it there if you prefer (right-click the tab > Settings > Channels).
- **Its own chat color**, picked so it doesn't look like whispers or any other chat. Change it in the settings.

## Install

1. Download the newest `LAFWCommunity-…-forever.zip` from [Releases](https://github.com/QBallStan/LAFWCommunity/releases) (not the green "Code" button).
2. Unzip it into `World of Warcraft\_forever_\Interface\AddOns\`, so you end up with `AddOns\LAFWCommunity\LAFWCommunity.toc`.
3. Restart the game.

To update, do the same with the newest release: replace the old `LAFWCommunity` folder.

## Set your name (once)

1. Click the **book button on your minimap**. Under *Your name in the group*, type the name you want (your main's name is a good choice) and press **Ctrl+C**.
2. In the Communities window, right-click **your own name** in the member list > **Set Note**, paste with **Ctrl+V** and accept.

That's it: everyone running the addon now sees you by that name. The game doesn't let addons set the note for you, which is why it's a copy and paste.

Right-click the minimap button to open the roster.

## Commands

You shouldn't need them, but:
- `/lafw`: the roster. `/lafw settings`: the settings window.
- `/lafw test`: a report for troubleshooting. Run it, then `/reload`, and send the result to whoever maintains the addon.
