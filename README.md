# LAFW Community

The Love At First Wipe community addon for **World of Warcraft: Forever**.

Our community is a Blizzard Group, so both factions can be in it. Blizzard Groups show everyone by BattleTag; this addon shows the characters people are actually playing, and a few more things that make the group feel like a guild.

## What it does

- **Character names instead of BattleTags** in the community chat, the Communities member list and the LAFW tab. Pick your main once, and your other characters show as "Alt - Main".
- **The LAFW tab** in the Communities window: each member's current character, their main, class and professions. Click a member to see their other characters, with their professions.
- **`/l` talks in the community**, like `/p` for party. The community chat is added to your General chat tab the first time; remove it there if you prefer (right-click the tab > Settings > Channels).
- **Its own chat color**, picked so it doesn't look like whispers or any other chat.

Names, professions and alts are shared between members who run the addon, so the more of us have it, the better it works. Your Battle.net friends' characters show even if they don't have it.

## Install

**With WowUp (recommended, updates by itself)**
1. Install [WowUp](https://wowup.io) and choose *World of Warcraft: Forever* at the top.
2. Go to **Get Addons** > **Install from URL**.
3. Paste `https://github.com/QBallStan/LAFWCommunity` and install.

**By hand**
1. Download the newest `LAFWCommunity-…-forever.zip` from [Releases](https://github.com/QBallStan/LAFWCommunity/releases) (not the green "Code" button).
2. Unzip it into `World of Warcraft\_forever_\Interface\AddOns\`, so you end up with `AddOns\LAFWCommunity\LAFWCommunity.toc`.
3. Restart the game.

## First time in game

Click the **book button on your minimap** (or the *My characters* button in the LAFW tab):
- under **Your main**, click *Set main* on your main. Every other character on the same server counts as its alt. A character shows up in the list once you've logged in on it with the addon;
- the other options are there too: first names only, show BattleTags, the community `/l` uses, the minimap button.

Right-click the minimap button to open the roster.

## Commands

You shouldn't need them, but:
- `/lafw`: the roster. `/lafw settings`: the settings window.
- `/lafw test`: a report for troubleshooting. Run it, then `/reload`, and send the result to whoever maintains the addon.

## For the maintainer

Every addon file sits at the top of this repository. To publish a version, bump `## Version` in `LAFWCommunity.toc` and push to `main`. The GitHub workflow then builds `LAFWCommunity-v<version>-forever.zip` (with the `LAFWCommunity` folder inside), tags the commit and publishes the release, which is what WowUp installs. It can also be run by hand from the Actions tab.
