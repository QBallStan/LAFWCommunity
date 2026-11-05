-------------------------------------------------------------------------------
-- Character sharing between LAFW Community users.
--
-- Each copy of the addon joins a hidden chat channel and announces
-- "BattleTag -> character" when you log in or change character, and answers
-- when someone new asks. That lets members who are not Battle.net friends
-- see each other's characters in the Blizzard Group.
--
-- Not known yet: whether Horde and Alliance land in the same channel on
-- Forever. /lafw test reports which factions have been heard.
-------------------------------------------------------------------------------
local _, A = ...
local Sync = {}
A.Sync = Sync

local PREFIX = "LAFW1"
local CHANNEL = "LAFWsync"
local ANSWER_GAP = 30          -- seconds between two answers to "who's there"
local PING_EVERY = 300         -- "still here in Forever", every 5 minutes
local PING_GRACE = 60          -- a ping may be this late before we stop counting on it

-- When each member's addon last spoke this session (GetTime). The addon
-- only runs in Forever, so hearing from it means they're playing Forever.
Sync.seen = {}

Sync.stats = { sent = 0, heard = 0, rejected = 0, byFaction = {} }

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end
local function Peers()
    A.db.peers = A.db.peers or {}
    return A.db.peers
end

local function Find(battleTag)
    if not A.db or not battleTag then return nil end
    local full = A.BN.TagKeys(battleTag)
    local peers = Peers()
    if full and peers[full] then return peers[full] end
    -- The group may show "Name" while the announcement said "Name#1234".
    for key, entry in pairs(peers) do
        if A.BN.SameTag(key, battleTag) then return entry end
    end
end

-- The character a member's addon last announced, and its main (nil when
-- that character is their main, or not linked to one).
function Sync:Character(battleTag)
    local p = Find(battleTag)
    if p then return p.char, p.main end
end

-- Their main, if the character they announced is `char`: a main announced
-- for another character says nothing about this one.
function Sync:MainFor(battleTag, char)
    local p = Find(battleTag)
    if p and p.char == char then return p.main end
end

-------------------------------------------------------------------------------
-- The hidden channel
-------------------------------------------------------------------------------
local function HideFromChatWindows()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame then
            if ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, frame, CHANNEL)
            elseif ChatFrameUtil and ChatFrameUtil.RemoveChannel then pcall(ChatFrameUtil.RemoveChannel, frame, CHANNEL) end
        end
    end
end

function Sync:ChannelId()
    local id = Call(GetChannelName, CHANNEL)
    return type(id) == "number" and id > 0 and id or nil
end

-- In the channel (already, after a /reload, or once joined): say who we are
-- and ask who's there, then keep saying we're here every PING_EVERY seconds.
function Sync:Ready()
    HideFromChatWindows()
    self.joinedAt = GetTime()
    self:Announce(true)
    if not self.ticker and C_Timer.NewTicker then
        self.ticker = C_Timer.NewTicker(PING_EVERY, function() Sync:Ping() end)
    end
end

function Sync:Join()
    if self:ChannelId() then self:Ready(); return true end
    Call(JoinTemporaryChannel, CHANNEL)
    C_Timer.After(2, function()
        if Sync:ChannelId() then Sync:Ready() end
    end)
end

-------------------------------------------------------------------------------
-- Messages
--   H  "H\tTag\tChar\tRealm\tFaction\tAsk\tMain\tProfs\tClass\tLevel\tSeq\tOnMain"
--      who you are now. Char and Main are full names; Main is empty on the
--      main or with no main for this server. 0.2 stops after Ask, 0.3-0.6
--      after Main.
--   P  "P\tTag" every 5 minutes: still here (in Forever).
--   A  "A\tTag\tSeq\tName\tProfs\tClass\tLevel\tIsMain"
--      one of your other characters on this server, sent after an H with
--      the same Seq. A new Seq replaces the list.
-------------------------------------------------------------------------------
local MAX_OTHERS = 15

function Sync:Send(text)
    local id = self:ChannelId()
    if not id or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, "CHANNEL", id)
    if ok and result ~= false then self.stats.sent = self.stats.sent + 1; return true end
    self.stats.lastSendError = ok and tostring(result) or "error"
    return false
end

-- Free text we pass along (professions): no codes, no tabs, sane length.
local function CleanText(t)
    if type(t) ~= "string" or t == "" or #t > 120 or t:find("[|%c]") then return nil end
    return t
end
local function CleanClass(t)
    if type(t) == "string" and t:match("^%u+$") and #t <= 20 then return t end
end
local function CleanLevel(t)
    local n = tonumber(t)
    if n and n >= 1 and n <= 200 then return math.floor(n) end
end
Sync.CleanText = CleanText

function Sync:Announce(ask)
    local _, tag = A.BN:Self()
    local char = A.BN.PlayerName()
    if not tag or not char then return end
    local realm = GetRealmName() or ""
    local faction = UnitFactionGroup("player") or ""
    self.lastAnnounce = GetTime()
    self.seq = (self.seq or 0) + 1
    local seq = tostring(time() % 100000) .. "." .. self.seq
    local main = A.Me and A.BN.CleanName(A.Me:MainForCurrent()) or ""
    local profs = A.Me and CleanText(A.Me:Professions()) or ""
    local _, classFile = UnitClass("player")
    self:Send(table.concat({ "H", tag, char, realm, faction, ask and "1" or "0", main,
        profs, classFile or "", tostring(UnitLevel("player") or ""), seq,
        (A.Me and A.Me:MainKey() and A.Me:MainKey() == A.Me:CurrentKey()) and "1" or "0" }, "\t"))
    -- Your other characters here, a few at a time so the game doesn't
    -- throttle them.
    local others = A.Me and A.Me:OthersHere() or {}
    for i = 1, math.min(#others, MAX_OTHERS) do
        local c = others[i]
        local name = A.BN.CleanName(c.name)
        if name then
            C_Timer.After(0.25 * i, function()
                Sync:Send(table.concat({ "A", tag, seq, name, CleanText(c.profs) or "", c.class or "",
                    tostring(c.level or ""), c.isMain and "1" or "0" }, "\t"))
            end)
        end
    end
end

function Sync:OnMessage(text, sender)
    local kind = text:sub(1, 1)
    if kind == "A" then return self:OnOther(text) end
    if kind == "P" then return self:OnPing(text) end
    local _, tag, char, realm, faction, ask, main, profs, class, level, seq, onMain = strsplit("\t", text)
    if kind ~= "H" then return end
    local full = A.BN.TagKeys(tag)
    char = A.BN.CleanName(char)
    if not full or not char then self.stats.rejected = self.stats.rejected + 1; return end
    local _, selfTag = A.BN:Self()
    if selfTag and A.BN.SameTag(selfTag, tag) then return end   -- our own echo
    main = A.BN.CleanName(main)
    if main == char then main = nil end
    local before = Peers()[full]
    local entry = { char = char, main = main, realm = realm, faction = faction, at = time(),
        profs = CleanText(profs), class = CleanClass(class), level = CleanLevel(level),
        seq = seq, others = before and before.others or {},
        onMain = onMain == "1" or nil }   -- 0.7.2+: they're on the main they set
    -- A new announcement starts a new list of their other characters.
    if seq and seq ~= "" and (not before or before.seq ~= seq) then entry.others = {} end
    Peers()[full] = entry
    local wasSeen = self:InForever(tag)
    self.seen[full] = GetTime()
    if wasSeen ~= true then A:NamesChanged() end
    self.stats.heard = self.stats.heard + 1
    if faction and faction ~= "" then
        self.stats.byFaction[faction] = (self.stats.byFaction[faction] or 0) + 1
    end
    if not before or before.char ~= char or before.main ~= main or before.profs ~= entry.profs then A:NamesChanged() end
    -- Someone new asked who's there: answer, at most every ANSWER_GAP
    -- seconds and after a random pause so everyone doesn't answer at once.
    if ask == "1" and (not self.lastAnnounce or GetTime() - self.lastAnnounce > ANSWER_GAP) then
        C_Timer.After(1 + math.random() * 4, function()
            if not Sync.lastAnnounce or GetTime() - Sync.lastAnnounce > ANSWER_GAP then Sync:Announce(false) end
        end)
    end
end

function Sync:OnOther(text)
    local _, tag, seq, name, profs, class, level, isMain = strsplit("\t", text)
    local full = A.BN.TagKeys(tag)
    name = A.BN.CleanName(name)
    local p = full and Peers()[full]
    -- Only for the announcement it belongs to.
    if not p or not name or p.seq ~= seq then self.stats.rejected = self.stats.rejected + 1; return end
    if #p.others >= MAX_OTHERS then return end
    for _, o in ipairs(p.others) do if o.name == name then return end end
    self.seen[full] = GetTime()
    p.others[#p.others + 1] = { name = name, profs = CleanText(profs), class = CleanClass(class),
        level = CleanLevel(level), isMain = isMain == "1" }
    A:NamesChanged()
end

-- What a member's addon told us: their current character and its details,
-- and their other characters on that server.
function Sync:Peer(battleTag) return Find(battleTag) end

-- "P\tTag": still here.
function Sync:Ping()
    local _, tag = A.BN:Self()
    if tag and self:ChannelId() then self:Send("P\t" .. tag) end
end

function Sync:OnPing(text)
    local _, tag = strsplit("\t", text)
    local full = A.BN.TagKeys(tag)
    if not full then return end
    local _, selfTag = A.BN:Self()
    if selfTag and A.BN.SameTag(selfTag, tag) then return end
    local was = self:InForever(tag)
    self.seen[full] = GetTime()
    -- Someone we have no details for yet: ask.
    if not Peers()[full] and (not self.lastAnnounce or GetTime() - self.lastAnnounce > ANSWER_GAP) then
        self:Announce(true)
    end
    if was ~= true then A:NamesChanged() end
end

-- Is this member playing Forever right now, as far as their addon tells?
-- true: heard lately. false: they run the addon but have been quiet too long.
-- nil: no way to tell (no addon, or we only just arrived ourselves).
function Sync:InForever(battleTag)
    if not battleTag then return nil end
    local now = GetTime()
    for key, at in pairs(self.seen) do
        if A.BN.SameTag(key, battleTag) then
            if now - at <= PING_EVERY + PING_GRACE then return true end
            return false
        end
    end
    if not Find(battleTag) then return nil end
    -- A member known to run the addon who hasn't spoken: give them time to
    -- answer our "who's there" first.
    if not self.joinedAt or now - self.joinedAt < PING_GRACE then return nil end
    return false
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("CHANNEL_UI_UPDATE")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        end
        -- Wait for the default channels so ours doesn't take their numbers.
        C_Timer.After(10, function() Sync:Join() end)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, text, channel, sender = ...
        if prefix == PREFIX and (not issecretvalue or not issecretvalue(text)) and type(text) == "string" then
            pcall(Sync.OnMessage, Sync, text, sender)
        end
    elseif event == "CHANNEL_UI_UPDATE" then
        if Sync:ChannelId() then HideFromChatWindows() end
    end
end)
