-------------------------------------------------------------------------------
-- The "LAFW data" channel.
--
-- The hidden chat channel (Sync.lua) only reaches your own server and
-- faction. A Blizzard Group's channels reach every member, whatever their
-- faction or server, and keep their history. So the group owner adds one
-- channel named "LAFW data", and each copy of the addon:
--   - posts one short line about you (character, main, your other characters
--     on this server) when that changes: a new character, a new main;
--   - reads everyone's lines, from the channel's history at login and live;
--   - removes your own older lines, so the channel holds about one per member;
--   - turns the channel's notifications off and keeps it marked as read, so
--     nobody sees it unless they open it in the Communities window.
--
-- The game lets addons post in a group only right after a key press or a
-- click (like /l), so the post waits for your first one.
--
-- Line: "LAFW1 <seq> <part>/<parts> <payload chunk>", the payload being
--   "1~Char~Realm~Faction~CLASS~Level~Main~OnMain~InviteName~Alt:CLASS:Level:IsMain,..."
-------------------------------------------------------------------------------
local ADDON, A = ...
local Data = {}
A.Data = Data

local NAME = "lafw data"         -- the channel's name, compared without case
local TAG = "LAFW1"
local CHUNK = 200                -- payload characters per line
local HISTORY = 100              -- lines read back at login
local MAX_OTHERS = 15
local RECENT = 6 * 3600          -- a line this recent says "in Forever", if they're still online
local MAX_CLEANUP = 6            -- own old lines removed per session

Data.stats = { sent = 0, heard = 0, history = 0, rejected = 0, own = 0, removed = 0, byFaction = {} }
Data.queue = {}                  -- actions waiting for a key press or click
Data.parts = {}                  -- [memberKey] = { seq, n, got = {} }
Data.online = {}                 -- [key] = false once seen going offline this session

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end
local function Secret(v) return issecretvalue and v ~= nil and issecretvalue(v) end
local function Str(v) if type(v) == "string" and not Secret(v) and v ~= "" then return v end end

local function DB()
    A.db.data = A.db.data or {}
    local d = A.db.data
    d.notified = d.notified or {}   -- ["club:stream"] = true once notifications were turned off
    d.posted = d.posted or {}       -- ["club:stream"] = the payload we last posted
    return d
end

-------------------------------------------------------------------------------
-- Finding the channel
-------------------------------------------------------------------------------
function Data:Find()
    local clubs = Call(C_Club and C_Club.GetSubscribedClubs) or {}
    for _, club in ipairs(clubs) do
        if club.clubId and A.BN:IsBattleNetClub(club.clubId) then
            for _, st in ipairs(Call(C_Club.GetStreams, club.clubId) or {}) do
                local name = Str(st.name)
                if name and name:lower():match("^%s*(.-)%s*$") == NAME then
                    return club.clubId, st.streamId, Str(club.name)
                end
            end
        end
    end
end

local function StreamKey(clubId, streamId) return clubId .. ":" .. streamId end
local function PeerKey(clubId, memberId) return "m:" .. clubId .. ":" .. memberId end

-- Notifications off, once (so a member who wants them back can turn them on).
function Data:Quiet(clubId, streamId)
    local none = Enum and Enum.ClubStreamNotificationFilter and Enum.ClubStreamNotificationFilter.None
    local key = StreamKey(clubId, streamId)
    local d = DB()
    if none and not d.notified[key] and C_Club.SetClubStreamNotificationSettings then
        local settings = Call(C_Club.GetClubStreamNotificationSettings, clubId) or {}
        local list, found = {}, false
        for _, s in ipairs(settings) do
            if s.streamId == streamId then list[#list + 1] = { streamId = streamId, filter = none }; found = true
            else list[#list + 1] = { streamId = s.streamId, filter = s.filter } end
        end
        if not found then list[#list + 1] = { streamId = streamId, filter = none } end
        if pcall(C_Club.SetClubStreamNotificationSettings, clubId, list) then d.notified[key] = true end
    end
    self:MarkRead()
end

function Data:Filter()
    if not self.clubId then return nil end
    for _, s in ipairs(Call(C_Club.GetClubStreamNotificationSettings, self.clubId) or {}) do
        if s.streamId == self.streamId then return s.filter end
    end
end

-- Keep the channel read, unless the player chose to follow it.
function Data:MarkRead()
    if not self.clubId then return end
    local all = Enum and Enum.ClubStreamNotificationFilter and Enum.ClubStreamNotificationFilter.All
    if all and self:Filter() == all then return end
    Call(C_Club.AdvanceStreamViewMarker, self.clubId, self.streamId)
end

-------------------------------------------------------------------------------
-- What we post
-------------------------------------------------------------------------------
local function Field(v) v = tostring(v or ""); return (v:gsub("[~,:|%c]", "")) end

function Data:Payload()
    local char = A.BN.PlayerName()
    if not char then return nil end
    local _, classFile = UnitClass("player")
    local main = A.Me and A.BN.CleanName(A.Me:MainForCurrent()) or ""
    local onMain = A.Me and A.Me:MainKey() and A.Me:MainKey() == A.Me:CurrentKey()
    local alts = {}
    local others = A.Me and A.Me:OthersHere() or {}
    for i = 1, math.min(#others, MAX_OTHERS) do
        local o = others[i]
        local name = A.BN.CleanName(o.name)
        if name then alts[#alts + 1] = table.concat({ Field(name), Field(o.class), Field(o.level), o.isMain and "1" or "0" }, ":") end
    end
    return table.concat({ "1", Field(char), Field(GetRealmName()), Field(UnitFactionGroup("player")),
        Field(classFile), Field(UnitLevel("player")), Field(main), onMain and "1" or "0",
        Field(A.Sync and A.Sync:InviteName()), table.concat(alts, ",") }, "~")
end

-- The lines for one payload.
function Data.Lines(payload, seq)
    local n = math.max(1, math.ceil(#payload / CHUNK))
    local lines = {}
    for i = 1, n do
        lines[i] = ("%s %s %d/%d %s"):format(TAG, seq, i, n, payload:sub((i - 1) * CHUNK + 1, i * CHUNK))
    end
    return lines
end

-- Post if what we'd say differs from our last line in the channel.
function Data:Update(force)
    if not self.clubId or not self.historyRead or self.stopped then return end
    local payload = self:Payload()
    if not payload then return end
    local d = DB()
    local key = StreamKey(self.clubId, self.streamId)
    if not force and d.posted[key] == payload and self.ownLatest then return end
    if self.pendingPayload == payload then return end
    self.pendingPayload = payload
    local seq = tostring(time())
    local clubId, streamId = self.clubId, self.streamId
    for _, line in ipairs(Data.Lines(payload, seq)) do
        self:Queue(function()
            local ok = pcall(C_Club.SendMessage, clubId, streamId, line)
            if ok then Data.stats.sent = Data.stats.sent + 1 end
            return ok
        end, "send")
    end
    self:Queue(function() d.posted[key] = payload; Data.pendingPayload = nil; return true end, "done", true)
end

-- Remove our own older lines (one per key press).
function Data:CleanUp(keep)
    local privileges = Call(C_Club.GetClubPrivileges, self.clubId)
    if not (privileges and privileges.canDestroyOwnMessage) then return end
    local clubId, streamId = self.clubId, self.streamId
    for _, id in ipairs(self.ownOld or {}) do
        if self.stats.removed + #self.queue >= MAX_CLEANUP then break end
        self:Queue(function()
            local ok = pcall(C_Club.DestroyMessage, clubId, streamId, id)
            if ok then Data.stats.removed = Data.stats.removed + 1 end
            return ok
        end, "remove")
    end
    self.ownOld = {}
end

-------------------------------------------------------------------------------
-- Waiting for a key press or a click
-------------------------------------------------------------------------------
local input
function Data:Queue(fn, what, free)
    self.queue[#self.queue + 1] = { fn = fn, what = what, free = free }
    if input and not InCombatLockdown() then input:EnableKeyboard(true) end
end

-- One action per key press or click; bookkeeping steps run along with it.
function Data:OnInput()
    if self.stopped then wipe(self.queue) end
    local item = table.remove(self.queue, 1)
    while item do
        self.lastAction = item.what
        item.fn()
        if not item.free then break end
        item = table.remove(self.queue, 1)
    end
    while self.queue[1] and self.queue[1].free do table.remove(self.queue, 1).fn() end
    if #self.queue == 0 and input and not InCombatLockdown() then input:EnableKeyboard(false) end
end

local function MakeInput()
    if input then return end
    input = CreateFrame("Frame", "LAFWCommunityDataInput")
    input:SetPropagateKeyboardInput(true)
    input:EnableKeyboard(#Data.queue > 0)
    input:SetScript("OnKeyDown", function() if #Data.queue > 0 then pcall(Data.OnInput, Data) end end)
    if WorldFrame and WorldFrame.HookScript then
        WorldFrame:HookScript("OnMouseDown", function() if #Data.queue > 0 then pcall(Data.OnInput, Data) end end)
    end
end

-------------------------------------------------------------------------------
-- What we read
-------------------------------------------------------------------------------
local function CleanClass(t) if type(t) == "string" and t:match("^%u+$") and #t <= 20 then return t end end
local function CleanLevel(t) local n = tonumber(t); if n and n >= 1 and n <= 200 then return math.floor(n) end end
local function CleanInvite(t) if type(t) == "string" and t ~= "" and #t <= 80 and not t:find("[|%c]") then return t end end

local function MessageTime(info)
    local epoch = info and info.messageId and info.messageId.epoch
    if type(epoch) == "number" and not Secret(epoch) then
        -- Microseconds; older builds may give seconds.
        return epoch > 1e12 and math.floor(epoch / 1e6) or epoch
    end
end

function Data.Parse(payload)
    local v, char, realm, faction, class, level, main, onMain, invite, alts = strsplit("~", payload)
    if v ~= "1" then return nil end
    char = A.BN.CleanName(char)
    if not char then return nil end
    main = A.BN.CleanName(main)
    if main == char then main = nil end
    local entry = { char = char, main = main, realm = realm ~= "" and realm or nil,
        faction = (faction == "Alliance" or faction == "Horde") and faction or nil,
        class = CleanClass(class), level = CleanLevel(level), onMain = onMain == "1" or nil,
        inviteName = CleanInvite(invite), others = {} }
    for alt in (alts or ""):gmatch("[^,]+") do
        local name, c, l, isMain = strsplit(":", alt)
        name = A.BN.CleanName(name)
        if name and #entry.others < MAX_OTHERS then
            entry.others[#entry.others + 1] = { name = name, class = CleanClass(c), level = CleanLevel(l), isMain = isMain == "1" }
        end
    end
    return entry
end

-- One line from the channel (history or live).
function Data:OnLine(info, live)
    if type(info) ~= "table" or info.destroyed then return end
    local text, author = Str(info.content), info.author
    if not text or type(author) ~= "table" then return end
    local seq, i, n, chunk = text:match("^" .. TAG .. " (%d+) (%d+)/(%d+) (.*)$")
    i, n = tonumber(i), tonumber(n)
    if not seq or not i or not n or n > 10 or i > n then self.stats.rejected = self.stats.rejected + 1; return end
    local at = MessageTime(info) or time()
    if author.isSelf then
        self.stats.own = self.stats.own + 1
        -- Our newest line stays; older ones go.
        self.ownLines = self.ownLines or {}
        self.ownLines[#self.ownLines + 1] = { id = info.messageId, at = at, seq = seq }
        return
    end
    local memberId = author.memberId
    if type(memberId) ~= "number" then return end
    local mkey = memberId .. ":" .. seq
    local p = self.parts[mkey] or { n = n, got = {}, count = 0 }
    self.parts[mkey] = p
    if not p.got[i] then p.got[i] = chunk; p.count = p.count + 1 end
    if p.count < p.n then return end
    self.parts[mkey] = nil
    local entry = Data.Parse(table.concat(p.got))
    if not entry then self.stats.rejected = self.stats.rejected + 1; return end
    self:Store(self.clubId, memberId, entry, at, live)
end

function Data:Store(clubId, memberId, entry, at, live)
    local key = PeerKey(clubId, memberId)
    A.db.peers = A.db.peers or {}
    local before = A.db.peers[key]
    if before and (before.at or 0) > at then return end   -- history arriving after something newer
    entry.at, entry.clubs, entry.source = at, { [tostring(clubId)] = memberId }, "data"
    A.db.peers[key] = entry
    if live then self.online[key] = nil end
    self.stats.heard = self.stats.heard + 1
    if entry.faction then self.stats.byFaction[entry.faction] = (self.stats.byFaction[entry.faction] or 0) + 1 end
    if not before or before.char ~= entry.char or before.main ~= entry.main or #before.others ~= #entry.others then
        A:NamesChanged()
    end
end

-- Their addon posted lately, and they haven't gone offline since.
function Data:Owns(key) return type(key) == "string" and key:sub(1, 2) == "m:" end
function Data:InForever(key)
    local p = A.db.peers and A.db.peers[key]
    if not p or self.online[key] == false then return nil end
    if p.at and time() - p.at <= RECENT then return true end
    return nil
end

function Data:ReadHistory()
    if not self.clubId then return end
    local ranges = Call(C_Club.GetMessageRanges, self.clubId, self.streamId)
    local range = type(ranges) == "table" and ranges[#ranges]
    if range and range.oldestMessageId and range.newestMessageId then
        local messages = Call(C_Club.GetMessagesInRange, self.clubId, self.streamId, range.oldestMessageId, range.newestMessageId) or {}
        self.ownLines = {}
        for _, m in ipairs(messages) do
            self.stats.history = self.stats.history + 1
            pcall(self.OnLine, self, m, false)
        end
    end
    -- Our own lines: keep the newest, remove the rest.
    table.sort(self.ownLines or {}, function(a, b) return a.at > b.at end)
    self.ownLatest = self.ownLines and self.ownLines[1]
    self.ownOld = {}
    for k = 2, #(self.ownLines or {}) do self.ownOld[#self.ownOld + 1] = self.ownLines[k].id end
    if not self.historyRead then
        self.historyRead = true
        self:Update()
        self:CleanUp()
    end
end

-------------------------------------------------------------------------------
-- Start
-------------------------------------------------------------------------------
function Data:Start()
    if self.clubId then return true end
    local clubId, streamId, clubName = self:Find()
    if not clubId then return false end
    self.clubId, self.streamId, self.clubName = clubId, streamId, clubName
    self.subscribed = Call(C_Club.IsSubscribedToStream, clubId, streamId)
    if not input and not InCombatLockdown() then pcall(MakeInput) end
    self:Quiet(clubId, streamId)
    local has = Call(C_Club.RequestMoreMessagesBefore, clubId, streamId, nil, HISTORY)
    self.historyAsked = true
    if has then self:ReadHistory() end
    -- No history after a while (an empty channel, or none came): go on without it.
    C_Timer.After(15, function()
        if not Data.historyRead then
            Data.historyTimedOut = true
            Data:ReadHistory()
        end
    end)
    return true
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CLUB_STREAM_ADDED")
events:RegisterEvent("CLUB_STREAMS_LOADED")
events:RegisterEvent("CLUB_MESSAGE_ADDED")
events:RegisterEvent("CLUB_MESSAGE_HISTORY_RECEIVED")
events:RegisterEvent("CLUB_MEMBER_PRESENCE_UPDATED")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if not A.db then return end
    if event == "PLAYER_LOGIN" then
        if not InCombatLockdown() then pcall(MakeInput) end
        C_Timer.After(8, function() pcall(Data.Start, Data) end)
    elseif event == "CLUB_STREAM_ADDED" or event == "CLUB_STREAMS_LOADED" then
        if not Data.clubId and IsLoggedIn() then C_Timer.After(1, function() pcall(Data.Start, Data) end) end
    elseif event == "CLUB_MESSAGE_ADDED" then
        if a1 == Data.clubId and a2 == Data.streamId then
            local info = Call(C_Club.GetMessageInfo, a1, a2, a3)
            if info and info.author and info.author.isSelf then
                Data.ownLatest = { id = info.messageId, at = MessageTime(info) or time() }
            else
                pcall(Data.OnLine, Data, info, true)
            end
            Data:MarkRead()
        end
    elseif event == "CLUB_MESSAGE_HISTORY_RECEIVED" then
        if a1 == Data.clubId and a2 == Data.streamId then pcall(Data.ReadHistory, Data) end
    elseif event == "CLUB_MEMBER_PRESENCE_UPDATED" then
        local offline = Enum and Enum.ClubMemberPresence and Enum.ClubMemberPresence.Offline
        if a1 == Data.clubId and offline and a3 == offline then
            local key = PeerKey(a1, a2)
            if A.db.peers and A.db.peers[key] then Data.online[key] = false; A:NamesChanged() end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if not input then pcall(MakeInput) end
        if input and #Data.queue > 0 then input:EnableKeyboard(true) end
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        -- The game refused one of ours: stop trying this session, and say so in the test.
        if a1 == ADDON then
            Data.blocked = tostring(a2)
            DB().blocked = { what = tostring(a2), action = Data.lastAction, at = time() }
            if Data.lastAction then Data.stopped = true; wipe(Data.queue) end
        end
    end
end)

-- A character or main change: post again.
function Data:Changed() if self.historyRead then self:Update() end end
