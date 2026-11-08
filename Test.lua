-------------------------------------------------------------------------------
-- /lafw test: what the addon sees in your Blizzard Group. Printed in chat
-- and kept in LAFWCommunityDB.test (written to disk on /reload or logout).
-------------------------------------------------------------------------------
local _, A = ...

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end
local function Describe(v)
    if v == nil then return "nil" end
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    return tostring(v)
end

function A:Test()
    local out = {}
    local function Say(line) out[#out + 1] = line; self:Message(line) end
    local version, build, _, interface = GetBuildInfo()
    local cfg = self.BN:Settings()
    Say(("Client %s (%s), interface %s; addon %s"):format(tostring(version), tostring(build), tostring(interface),
        tostring(C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("LAFWCommunity", "Version") or "?")))
    Say("Names: " .. (cfg.enabled and "on" or "|cffff6060off|r") .. (cfg.showTag and ", with BattleTags" or "")
        .. (cfg.firstOnly and ", first names for characters" or ""))

    local id = self.Settings:GroupId()
    if not id then Say("|cffff6060No Blizzard Group found.|r") end
    local test = { at = time(), version = version, build = build, members = {} }
    if id then
        local named, total = 0, 0
        for _, memberId in ipairs(Call(C_Club.GetClubMembers, id) or {}) do
            local info = Call(C_Club.GetMemberInfo, id, memberId)
            if type(info) == "table" then
                total = total + 1
                local shown, source = self.BN:Resolve(info.bnetAccountId, info.name, id, info)
                if shown then named = named + 1 end
                local line = ("  %s%s: %s%s, %s"):format(tostring(info.name), info.isSelf == true and " (you)" or "",
                    shown and ('"' .. shown .. '"') or "BattleTag kept", source and (" (" .. source .. ")") or "",
                    self.Presence.StatusText(info.presence))
                Say(line)
                test.members[#test.members + 1] = { shown = shown, source = source,
                    presence = Describe(info.presence), self = info.isSelf == true }
            end
        end
        Say(("Group: %d members, %d shown by character"):format(total, named))
    end
    Say(("Characters remembered for %d player(s)"):format(self.Seen:Count()))

    local P = self.Presence
    Say(("Alerts: %s; status updates %d, alerts shown %d, subscribed %d time(s)"):format(
        self.db.alerts == false and "off" or "on", P.stats.updates, P.stats.alerts, P.stats.subscribed))
    local s = self.BN.stats
    Say(("Member list: %s, %d rows renamed; chat names: %d of %d renamed"):format(
        self.BN.memberListHooked and "hooked" or (CommunitiesFrame and "not hooked" or "not loaded yet"),
        s.memberRows, s.renamed, s.bnLinkCalls + s.playerLinkCalls))
    local CC = self.CommunityChat
    Say(("Community chat: %s, channel %s; /l %s"):format(tostring(CC:ClubName() or "none"),
        tostring(CC:ChannelNumber(false) or "not joined"), CC.stats.slashTaken and "|cffff6060also claimed by another addon|r" or "ready"))
    test.lines = out
    self.db.test = test
    Say("Saved. Type /reload so it's written to disk.")
end
