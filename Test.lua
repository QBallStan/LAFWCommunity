-------------------------------------------------------------------------------
-- /lafw test: what this client reports about Blizzard Groups, the name
-- swap and the character sharing. Printed in chat and kept in
-- LAFWCommunityDB.test (written to disk on /reload or logout).
-------------------------------------------------------------------------------
local _, A = ...

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end
local function Describe(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    if type(v) == "table" then return "<table>" end
    return tostring(v)
end
local function ClubTypeName(t)
    if Enum and Enum.ClubType then
        for k, v in pairs(Enum.ClubType) do if v == t then return k end end
    end
    return tostring(t)
end

function A:Test()
    local out = {}
    local function Say(line) out[#out + 1] = line; self:Message(line) end
    local version, build, _, interface = GetBuildInfo()
    local test = { at = time(), version = version, build = build, interface = interface,
        character = UnitName("player"), faction = UnitFactionGroup("player") }

    local selfID, selfTag = self.BN:Self()
    test.selfBattleTag = selfTag ~= nil
    test.selfAccountID = selfID ~= nil
    Say(("Client %s (%s), interface %s"):format(tostring(version), tostring(build), tostring(interface)))
    Say("Your BattleTag known to addons: " .. (selfTag and "yes" or "no"))
    test.selfTag, test.selfID = selfTag, selfID
    local cfg = self.BN:Settings()
    Say("Name swap: " .. (cfg.enabled and "on" or "|cffff6060off|r (type /lafw names to turn it on)"))

    local me = self.Me:Data()
    local mainKey = self.Me:MainKey()
    local mainChar = mainKey and me.chars[mainKey]
    test.main = mainChar and mainChar.name
    Say("Your main: " .. (mainChar and mainChar.name or "not set (minimap button)"))

    test.clubs = {}
    local clubs = Call(C_Club and C_Club.GetSubscribedClubs) or {}
    local anyBN = false
    for _, club in ipairs(clubs) do
        local entry = { name = Describe(club.name), clubType = ClubTypeName(club.clubType) }
        test.clubs[#test.clubs + 1] = entry
        if self.BN:IsBattleNetClub(club.clubId) then
            anyBN = true
            local members = Call(C_Club.GetClubMembers, club.clubId) or {}
            entry.memberCount = #members
            entry.members = {}
            local resolved = 0
            for i, memberId in ipairs(members) do
                local info = Call(C_Club.GetMemberInfo, club.clubId, memberId)
                if info and i <= 25 then
                    local m = { fields = {} }
                    for k, v in pairs(info) do m.fields[k] = Describe(v) end
                    local name, source, main = self.BN:Resolve(info.bnetAccountId, info.name, club.clubId, info)
                    m.shownAs, m.source = name and (main and (name .. " - " .. main) or name), source
                    if name then resolved = resolved + 1 end
                    entry.members[#entry.members + 1] = m
                end
            end
            entry.resolved = resolved
            Say(("Blizzard Group \"%s\": %d members, %d shown by character"):format(
                tostring(entry.name), #members, resolved))
            -- Which member fields this client fills in, from the first member.
            local first = entry.members[1]
            if first then
                local keys = {}
                for k in pairs(first.fields) do keys[#keys + 1] = k end
                table.sort(keys)
                Say("  Member fields: " .. table.concat(keys, ", "))
            end
            for _, m in ipairs(entry.members) do
                Say(("  %s%s -> %s%s"):format(tostring(m.fields.memberNote and ("note: " .. m.fields.memberNote) or m.fields.name), m.fields.isSelf == "true" and " (you)" or "",
                    m.shownAs or "BattleTag kept", m.source and (" (" .. m.source .. ")") or ""))
            end
        end
    end
    if not anyBN then Say("No Blizzard Group found among your communities.") end

    -- What the game reports for a friend in game (family name field?).
    local count = Call(BNGetNumFriends) or 0
    for i = 1, count do
        local info = Call(C_BattleNet and C_BattleNet.GetFriendAccountInfo, i)
        local game = info and info.gameAccountInfo
        if type(game) == "table" and game.characterName then
            local keys = {}
            for k, v in pairs(game) do keys[#keys + 1] = k .. "=" .. (Describe(v) or "nil") end
            table.sort(keys)
            test.friendGameFields = keys
            local names = {}
            for _, k in ipairs(keys) do if k:lower():find("name") then names[#names + 1] = k end end
            Say("Friend in game, name fields: " .. table.concat(names, ", "))
            break
        end
    end
    Say("You show as: " .. tostring(self.BN:Shown(self.BN.PlayerName())))

    -- Is there any way to list your account's characters? Look for
    -- functions whose names suggest it.
    local found = {}
    local function Scan(tbl, prefix)
        for k, v in pairs(tbl) do
            if type(k) == "string" and type(v) == "function" then
                local l = k:lower()
                if (l:find("account") and l:find("character")) or l:find("characterlist")
                    or l:find("warbandcharacter") or l:find("alts") then
                    found[#found + 1] = prefix .. k
                end
            end
        end
    end
    Scan(_G, "")
    for name, ns in pairs(_G) do
        if type(name) == "string" and name:find("^C_") and type(ns) == "table" then Scan(ns, name .. ".") end
    end
    table.sort(found)
    test.accountCharacterAPIs = found
    Say("Account character APIs: " .. (#found > 0 and table.concat(found, ", ") or "none found"))

    local s = self.BN.stats
    test.hooks = { bn = self.BN.hookedBN or false, player = self.BN.hookedPlayer or false,
        bnLinkCalls = s.bnLinkCalls, playerLinkCalls = s.playerLinkCalls, renamed = s.renamed, kept = s.kept }
    Say(("Member list: %s; %d rows renamed, layout %s"):format(self.BN.memberListHooked and "hooked"
        or (CommunitiesFrame and "not hooked" or "not loaded yet (open the Communities window, then test)"), s.memberRows,
        (s.relaid or 0) > 0 and "redone by Blizzard" or ((s.resized or 0) > 0 and "resized by the addon" or "untouched")))
    test.hooks_memberList = self.BN.memberListHooked or false
    Say(("Chat name hook: %s; used %d times, %d renamed"):format(
        self.BN.hookedBN and "installed" or "missing", s.bnLinkCalls + s.playerLinkCalls, s.renamed))
    test.lastChat = self.BN.lastChat
    if self.BN.lastChat then
        Say(("Last group message: %d seen, sender ID %s"):format(self.BN.lastChat.count,
            self.BN.lastChat.bnSenderID and "present" or "missing"))
    else
        Say("No group chat message seen since login: send one, then test again.")
    end

    local y = self.Sync.stats
    local factions = {}
    for f, n in pairs(y.byFaction) do factions[#factions + 1] = f .. " " .. n end
    test.sync = { channel = self.Sync:ChannelId() ~= nil, sent = y.sent, heard = y.heard,
        rejected = y.rejected, byFaction = y.byFaction, lastSendError = y.lastSendError }
    Say(("Sharing channel: %s; sent %d, heard %d%s%s"):format(
        self.Sync:ChannelId() and "joined" or "|cffff6060not joined|r", y.sent, y.heard,
        #factions > 0 and (" (" .. table.concat(factions, ", ") .. ")") or "",
        (y.failed or 0) > 0 and (" |cffff6060- %d refused (%s)|r"):format(y.failed, tostring(y.lastSendError)) or ""))
    -- Members whose addon we've heard, and which group member each is.
    local mine = self.Sync:MyMemberships()
    Say("You in your groups: " .. (mine ~= "" and mine or "|cffff6060not found|r"))
    local n = 0
    for key, p in pairs(self.db.peers or {}) do
        n = n + 1
        local clubs = {}
        for club, member in pairs(p.clubs or {}) do clubs[#clubs + 1] = club .. ":" .. member end
        Say(("  heard%s: %s (%s)%s%s"):format(p.source == "data" and " in LAFW data" or "", tostring(p.char), tostring(p.faction or "?"),
            #clubs > 0 and (", member " .. table.concat(clubs, ",")) or ", |cffff6060no group info (older version)|r",
            self.Sync:InForever(key) and ", in Forever now" or ""))
    end
    if n == 0 then Say("  no other member's addon heard yet") end
    -- The LAFW data channel (Data.lua).
    local D = self.Data
    local ds = D.stats
    if not D then
    elseif not D.clubId then
        Say("|cffff6060LAFW data channel: not found|r (the group owner adds a channel named \"LAFW data\")")
    else
        local filter = D:Filter()
        local fname = tostring(filter)
        if Enum and Enum.ClubStreamNotificationFilter then
            for k, v in pairs(Enum.ClubStreamNotificationFilter) do if v == filter then fname = k end end
        end
        Say(("LAFW data channel: found in \"%s\"; subscribed %s; notifications %s; history %s (%d lines, %d yours)"):format(
            tostring(D.clubName), tostring(D.subscribed), fname,
            D.historyRead and (D.historyTimedOut and "none came" or "read") or "waiting", ds.history, ds.own))
        local blocked = D.blocked or (self.db.data and self.db.data.blocked and self.db.data.blocked.what)
        Say(("  posted %d line(s), removed %d old; %s%s"):format(ds.sent, ds.removed,
            #D.queue > 0 and ("|cffffd100" .. #D.queue .. " waiting for a key press|r") or "nothing waiting",
            blocked and (" |cffff6060- the game blocked " .. tostring(blocked) .. "|r") or ""))
        local factions = {}
        for f, n in pairs(ds.byFaction) do factions[#factions + 1] = f .. " " .. n end
        Say(("  heard %d member line(s)%s, %d rejected; answered %d hello(s)"):format(ds.heard,
            #factions > 0 and (" (" .. table.concat(factions, ", ") .. ")") or "", ds.rejected, ds.replies or 0))
        test.data = { found = true, subscribed = D.subscribed, filter = fname, history = ds.history, own = ds.own,
            sent = ds.sent, removed = ds.removed, heard = ds.heard, byFaction = ds.byFaction, blocked = blocked,
            waiting = #D.queue, timedOut = D.historyTimedOut }
    end
    local want, have = self.Notes:Suggested(), self.Notes:Current()
    Say(("Your member note: %s%s"):format(have and ('"' .. have .. '"') or "none",
        want and (have == want and " (as it should be)" or (' |cffffd100- should be "' .. want .. '"|r')) or " (pick your main first)"))

    local CC = self.CommunityChat
    local number = CC:ChannelNumber(false)
    test.chat = CC.stats
    Say(("Community chat: %s, channel %s; General tab %s%s; /l %s, used %d"):format(
        tostring(CC:ClubName() or "none"), tostring(number or "not joined"),
        CC.stats.added == true and "added" or (CC.stats.added == false and "|cffff6060not added|r" or "not tried yet"),
        CC.stats.addedVia and (" (" .. CC.stats.addedVia .. ")") or "",
        CC.stats.slashTaken and "|cffff6060also claimed by another addon|r" or "ready", CC.stats.switched + CC.stats.slashSends))

    test.lines = out
    self.db.test = test
    Say("Saved. Type /reload so it's written to disk.")
end
