-------------------------------------------------------------------------------
-- Who's online in the group: login and logout lines in chat (like guild
-- members' notices), and the list behind the minimap button's tooltip.
--
-- The game tells addons each member's status (online, away, busy, on the
-- Battle.net mobile app, offline) for one group at a time, and the
-- Communities window takes that over while it's open: the addon asks again
-- for its group when the window closes. Members' notes changing (new names)
-- also land here.
-------------------------------------------------------------------------------
local _, A = ...
local P = {}
A.Presence = P

P.state = {}          -- [memberId] = presence, as last seen
P.stats = { alerts = 0, updates = 0, subscribed = 0 }
local QUIET = 15      -- seconds after (re)subscribing when changes are only noted

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end
local function Secret(v) return issecretvalue and v ~= nil and issecretvalue(v) end

local function Presence() return Enum and Enum.ClubMemberPresence or {} end
function P.IsOnline(presence)
    local e = Presence()
    return presence ~= nil and presence ~= e.Offline and presence ~= e.Unknown
end
function P.StatusText(presence)
    local e = Presence()
    if presence == e.Away then return "Away" end
    if presence == e.Busy then return "Busy" end
    if presence == e.OnlineMobile then return "On the Battle.net app" end
    if presence == e.Offline then return "Offline" end
    if presence == e.Online then return "Online" end
    return "Unknown"
end

function P:GroupId() return A.Settings and A.Settings:GroupId() end

-- Ask the game for the group's statuses, and note them without alerts.
function P:Subscribe()
    local id = self:GroupId()
    if not id then return end
    self.clubId = id
    Call(C_Club.SetClubPresenceSubscription, id)
    self.stats.subscribed = self.stats.subscribed + 1
    self.quietUntil = GetTime() + QUIET
    self:Snapshot(false)
end

-- Compare every member's status with the last one seen. With alert, a
-- member coming online or going offline gets a line in chat.
function P:Snapshot(alert)
    local id = self.clubId
    if not id then return end
    for _, memberId in ipairs(Call(C_Club.GetClubMembers, id) or {}) do
        local info = Call(C_Club.GetMemberInfo, id, memberId)
        if type(info) == "table" and not Secret(info.presence) then self:Saw(info, info.presence, alert) end
    end
end

function P:Saw(info, presence, alert)
    local memberId = info.memberId
    if memberId == nil or Secret(memberId) then return end
    local before = self.state[memberId]
    self.state[memberId] = presence
    if before == nil or info.isSelf == true then return end
    local was, now = P.IsOnline(before), P.IsOnline(presence)
    if was == now then return end
    if not alert or A.db.alerts == false or (self.quietUntil and GetTime() < self.quietUntil) then return end
    local name = A.BN:NameFor(info.bnetAccountId, info.name, self.clubId, info) or info.name or "?"
    local c = A.CommunityColor and A:CommunityColor() or { 1, 1, 0 }
    DEFAULT_CHAT_FRAME:AddMessage(("%s has %s."):format(name, now and "come online" or "gone offline"), c[1], c[2], c[3])
    self.stats.alerts = self.stats.alerts + 1
    if A.window and A.window:IsShown() then A:NamesChanged() end
end

-- Online members, for the minimap tooltip: { name, status } sorted by name.
function P:Online()
    local id = self:GroupId()
    local list = {}
    if not id then return list end
    for _, memberId in ipairs(Call(C_Club.GetClubMembers, id) or {}) do
        local info = Call(C_Club.GetMemberInfo, id, memberId)
        if type(info) == "table" and not Secret(info.presence) and P.IsOnline(info.presence) then
            list[#list + 1] = { name = A.BN:NameFor(info.bnetAccountId, info.name, id, info) or info.name or "?",
                status = P.StatusText(info.presence), presence = info.presence, isSelf = info.isSelf == true }
        end
    end
    table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return list
end

-- The Communities window takes the status subscription while it's open and
-- drops it when it closes: take it back then.
local hooked
local function HookCommunities()
    if hooked or not CommunitiesFrame then return end
    hooked = true
    CommunitiesFrame:HookScript("OnHide", function() C_Timer.After(1, function() P:Subscribe() end) end)
end

-- 0.10-0.13 kept a "LAFW data" channel in the main chat window and filtered
-- its lines out; without that filter they'd show. Take it out of the chat
-- windows once.
local function ForgetDataChannel()
    if A.db.dataChannelRemoved then return end
    A.db.dataChannelRemoved = true
    for _, club in ipairs(A:Communities()) do
        for _, st in ipairs(Call(C_Club.GetStreams, club.clubId) or {}) do
            local name = type(st.name) == "string" and not Secret(st.name) and st.name:lower():match("^%s*(.-)%s*$")
            if name == "lafw data" then
                for i = 1, (NUM_CHAT_WINDOWS or 10) do
                    local frame = _G["ChatFrame" .. i]
                    if frame and ChatFrameUtil and ChatFrameUtil.RemoveCommunitiesChannel then
                        pcall(ChatFrameUtil.RemoveCommunitiesChannel, frame, club.clubId, st.streamId, true)
                    end
                end
            end
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("CLUB_MEMBER_PRESENCE_UPDATED")
events:RegisterEvent("CLUB_MEMBER_UPDATED")
events:RegisterEvent("CLUB_MEMBERS_UPDATED")
events:RegisterEvent("CLUB_MEMBER_ADDED")
events:RegisterEvent("CLUB_MEMBER_REMOVED")
events:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if not A.db then return end
    if event == "PLAYER_LOGIN" then
        C_Timer.After(5, function() P:Subscribe(); HookCommunities() end)
        C_Timer.After(10, function() pcall(ForgetDataChannel) end)
        -- In case statuses change without the game saying so.
        C_Timer.NewTicker(60, function() pcall(P.Snapshot, P, true) end)
    elseif event == "ADDON_LOADED" then
        if a1 == "Blizzard_Communities" then HookCommunities() end
    elseif event == "CLUB_MEMBER_PRESENCE_UPDATED" then
        P.stats.updates = P.stats.updates + 1
        if a1 == P.clubId and not Secret(a3) then
            local info = Call(C_Club.GetMemberInfo, a1, a2)
            if type(info) == "table" then pcall(P.Saw, P, info, a3, true) end
        end
    else
        -- A note changed (someone's name), or members came or went.
        A:NamesChanged()
        if A.Settings and A.Settings.window and A.Settings.window:IsShown() then pcall(A.Settings.Render, A.Settings) end
    end
end)
