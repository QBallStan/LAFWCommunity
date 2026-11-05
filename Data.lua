-------------------------------------------------------------------------------
-- The "LAFW data" channel.
--
-- The hidden chat channel (Sync.lua) only reaches your own server and
-- faction. A Blizzard Group's channels reach every member, whatever their
-- faction or server, and keep their history. So the group owner adds one
-- channel named "LAFW data", and each copy of the addon:
--   - says hello when you log in: posts your line, and everyone online with
--     the addon answers by posting theirs, so their lines are fresh;
--   - posts a short line about you (character, main, level, professions, and
--     your other characters on this server) when that changes: a new
--     character, a new main, a level or a skill up (those at most every 10
--     minutes), or when you press "Share now" in the settings;
--   - reads everyone's lines as they're posted. The game hides group message
--     text from addons except in chat events, so the channel is joined as a
--     chat channel (kept out of the chat windows) and read from there; the
--     channel's history only serves to remove your own old lines. What was
--     heard is kept, so members seen before stay known while offline;
--   - removes your own older lines, so the channel holds about one per member;
--   - turns the channel's notifications off and keeps it marked as read, so
--     nobody sees it unless they open it in the Communities window.
--
-- The game lets addons post in a group only right after a key press or a
-- click (like /l), so the post waits for your first one.
--
-- Line: "LAFW1 <seq> <part>/<parts> <payload chunk>", the payload being
--   "1~Char~Realm~Faction~CLASS~Level~Main~OnMain~InviteName~Alt:CLASS:Level:IsMain:Profs,...~Profs"
-- then "~1" on a hello (a login: others answer) or "~0" on anything else.
-- (Profs came in 0.11.0, the hello flag in 0.12.0; older lines simply lack them.)
-------------------------------------------------------------------------------
local ADDON, A = ...
local Data = {}
A.Data = Data

local NAME = "lafw data"         -- the channel's name, compared without case
local TAG = "LAFW1"
local CHUNK = 200                -- payload characters per line
local HISTORY = 200              -- lines read back at login
local MAX_OTHERS = 15
local RECENT = 6 * 3600          -- a line this recent says "in Forever", if they're still online
local MAX_CLEANUP = 40           -- own old lines removed per session, at most
local AUTO_GAP = 600             -- level and skill ups are shared at most this often (seconds)
local HELLO_GAP = 120            -- no new "hello" if we posted this recently (a quick /reload)
local REPLY_GAP = 120            -- answer someone's hello only if our last post is older than this

Data.stats = { sent = 0, heard = 0, history = 0, rejected = 0, own = 0, removed = 0, byFaction = {} }
Data.queue = {}                  -- actions waiting for a key press or click
Data.parts = {}                  -- [memberKey] = { seq, n, got = {} }
Data.online = {}                 -- [key] = false once seen going offline this session
Data.seenIds = {}                -- lines already read
Data.removing = {}               -- own old lines already queued for removal
Data.ownSeen = {}                -- own lines already counted

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end
local function Secret(v) return issecretvalue and v ~= nil and issecretvalue(v) end
local function Str(v) if type(v) == "string" and not Secret(v) and v ~= "" then return v end end
local function MessageKey(info)
    local id = info and info.messageId
    if type(id) ~= "table" or Secret(id.epoch) then return nil end
    return tostring(id.epoch) .. ":" .. tostring(id.position)
end


local function DB()
    A.db.data = A.db.data or {}
    local d = A.db.data
    d.notified = d.notified or {}   -- ["club:stream"] = true once notifications were turned off
    d.posted = d.posted or {}       -- ["club:stream"] = the payload we last posted
    d.postedAt = d.postedAt or {}   -- ["club:stream"] = when
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
        if name then alts[#alts + 1] = table.concat({ Field(name), Field(o.class), Field(o.level), o.isMain and "1" or "0", Field(o.profs) }, ":") end
    end
    return table.concat({ "1", Field(char), Field(GetRealmName()), Field(UnitFactionGroup("player")),
        Field(classFile), Field(UnitLevel("player")), Field(main), onMain and "1" or "0",
        Field(A.Sync and A.Sync:InviteName()), table.concat(alts, ","),
        Field(A.Me and A.Me:Professions()) }, "~")
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
function Data:Update(force, hello)
    if not self.clubId or not self.historyRead or self.stopped then return end
    local payload = self:Payload()
    if not payload then return end
    local d = DB()
    local key = StreamKey(self.clubId, self.streamId)
    if not force and d.posted[key] == payload and self.ownLatest then return end
    if self.pendingPayload == payload then return end
    self.pendingPayload = payload
    -- A new number each post, so our own lines tell posts apart.
    local seq = math.max(time(), (self.lastSeq or 0) + 1)
    self.lastSeq = seq
    seq = tostring(seq)
    local clubId, streamId = self.clubId, self.streamId
    for _, line in ipairs(Data.Lines(payload .. (hello and "~1" or "~0"), seq)) do
        self:Queue(function()
            Data.lastSendAt = GetTime()
            local ok = pcall(C_Club.SendMessage, clubId, streamId, line)
            if ok then Data.stats.sent = Data.stats.sent + 1 end
            return ok
        end, "send")
    end
    self:Queue(function()
        d.posted[key], d.postedAt[key] = payload, time()
        Data.pendingPayload = nil
        if A.Me and A.Me.window and A.Me.window:IsShown() then pcall(A.Me.Render, A.Me) end
        return true
    end, "done", true)
end

-- Remove our own older lines (one per key press).
function Data:CleanUp(keep)
    local privileges = Call(C_Club.GetClubPrivileges, self.clubId)
    if not (privileges and privileges.canDestroyOwnMessage) then return end
    local clubId, streamId = self.clubId, self.streamId
    for _, id in ipairs(self.ownOld or {}) do
        if (self.cleanupQueued or 0) >= MAX_CLEANUP then break end
        self.cleanupQueued = (self.cleanupQueued or 0) + 1
        self.removing[MessageKey({ messageId = id }) or id] = true
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
local function CleanProfs(t) if type(t) == "string" and t ~= "" and #t <= 120 and not t:find("[|%c]") then return t end end
local function CleanInvite(t) if type(t) == "string" and t ~= "" and #t <= 80 and not t:find("[|%c]") then return t end end

local function MessageTime(info)
    local epoch = info and info.messageId and info.messageId.epoch
    if type(epoch) == "number" and not Secret(epoch) then
        -- Microseconds; older builds may give seconds.
        return epoch > 1e12 and math.floor(epoch / 1e6) or epoch
    end
end

function Data.Parse(payload)
    local v, char, realm, faction, class, level, main, onMain, invite, alts, profs, hello = strsplit("~", payload)
    if v ~= "1" then return nil end
    char = A.BN.CleanName(char)
    if not char then return nil end
    main = A.BN.CleanName(main)
    if main == char then main = nil end
    local entry = { char = char, main = main, realm = realm ~= "" and realm or nil,
        faction = (faction == "Alliance" or faction == "Horde") and faction or nil,
        class = CleanClass(class), level = CleanLevel(level), onMain = onMain == "1" or nil,
        inviteName = CleanInvite(invite), profs = CleanProfs(profs), others = {} }
    entry.hello = hello == "1" or nil
    for alt in (alts or ""):gmatch("[^,]+") do
        local name, c, l, isMain, p = strsplit(":", alt)
        name = A.BN.CleanName(name)
        if name and #entry.others < MAX_OTHERS then
            entry.others[#entry.others + 1] = { name = name, class = CleanClass(c), level = CleanLevel(l), isMain = isMain == "1", profs = CleanProfs(p) }
        end
    end
    return entry
end

-- One line from the channel (history or live).
-- The last lines seen in the channel and what became of them, for /lafw test
-- (kept in the saved variables, so they can be read after a /reload).
function Data:Note(info, live, result)
    local d = DB()
    d.debug = d.debug or {}
    local author = type(info) == "table" and type(info.author) == "table" and info.author or {}
    local content = type(info) == "table" and info.content
    local text = Secret(content) and "<secret>" or (type(content) == "string" and content:sub(1, 70)) or ("<" .. type(content) .. ">")
    table.insert(d.debug, 1, { at = time(), live = live and true or false, member = Secret(author.memberId) and "<secret>" or tostring(author.memberId),
        self = Secret(author.isSelf) and "<secret>" or tostring(author.isSelf), text = text, result = result })
    while #d.debug > 12 do table.remove(d.debug) end
end

function Data:OnLine(info, live)
    if type(info) ~= "table" or info.destroyed then return end
    local author = info.author
    if type(author) ~= "table" then self:Note(info, live, "no author"); return end
    local mk = MessageKey(info)
    local at = MessageTime(info) or time()
    -- Ours: only the messages themselves matter (to remove old ones), and
    -- that needs no text.
    if author.isSelf == true then
        if mk and self.ownSeen[mk] then return end
        if mk then self.ownSeen[mk] = true end
        self.stats.own = self.stats.own + 1
        self.ownLines = self.ownLines or {}
        self.ownLines[#self.ownLines + 1] = { id = info.messageId, at = at }
        self:Note(info, live, "yours")
        return
    end
    -- The game hides group message text from addons ("|Kw12|k") everywhere
    -- except in chat events, so only those lines can be read.
    local text = Str(info.content)
    if not text then self:Note(info, live, "no text"); return end
    local seq, i, n, chunk = text:match("^" .. TAG .. " (%d+) (%d+)/(%d+) (.*)$")
    i, n = tonumber(i), tonumber(n)
    if not seq or not i or not n or n > 10 or i > n then
        if text:find("^|K") then
            self.stats.hidden = (self.stats.hidden or 0) + 1
            self:Note(info, live, "text hidden by the game")
        else
            self.stats.rejected = self.stats.rejected + 1
            self:Note(info, live, "not an addon line")
        end
        return
    end
    -- The same line can come again: once is enough.
    if mk then
        if self.seenIds[mk] then return end
        self.seenIds[mk] = true
    end
    local memberId = author.memberId
    if type(memberId) ~= "number" or Secret(memberId) then self:Note(info, live, "no member ID (" .. type(memberId) .. ")"); return end
    local mkey = memberId .. ":" .. seq
    local p = self.parts[mkey] or { n = n, got = {}, count = 0 }
    self.parts[mkey] = p
    if not p.got[i] then p.got[i] = chunk; p.count = p.count + 1 end
    if p.count < p.n then self:Note(info, live, ("part %d of %d"):format(i, n)); return end
    self.parts[mkey] = nil
    local entry = Data.Parse(table.concat(p.got))
    if not entry then
        self.stats.rejected = self.stats.rejected + 1
        self:Note(info, live, "couldn't read it")
        return
    end
    self:Note(info, live, "stored: " .. entry.char)
    local hello = entry.hello
    entry.hello = nil
    self:Store(self.clubId, memberId, entry, at, live)
    -- Someone just logged in: answer with our line (once for a burst of logins).
    if hello and live then self:Reply() end
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
    A:NamesChanged()
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
    self.stats.ranges = type(ranges) == "table" and #ranges or -1
    for _, range in ipairs(type(ranges) == "table" and ranges or {}) do
        if range.oldestMessageId and range.newestMessageId then
            local messages = Call(C_Club.GetMessagesInRange, self.clubId, self.streamId, range.oldestMessageId, range.newestMessageId) or {}
            for _, m in ipairs(messages) do
                self.stats.history = self.stats.history + 1
                pcall(self.OnLine, self, m, false)
            end
        end
    end
    for _, l in ipairs(self.ownLines or {}) do
        if not self.ownLatest or l.at > self.ownLatest.at then self.ownLatest = l end
    end
    if not self.historyRead then
        self.historyRead = true
        -- Logging in: say hello (others answer), unless we just did (a quick /reload).
        local last = DB().postedAt[StreamKey(self.clubId, self.streamId)]
        if last and time() - last < HELLO_GAP then self:Update() else self:Update(true, true) end
    end
    self:OwnOld()
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
    if self.subscribed then
        self:JoinChat()
        self:RequestHistory()
    else
        self:Subscribe()
        -- Never subscribed: carry on without history after a while.
        C_Timer.After(20, function() if not Data.historyAsked then Data:RequestHistory() end end)
    end
    return true
end

-- The game only sends you a channel's messages, and lets you post in it,
-- once you're subscribed to it, which normally happens when you open it in
-- the Communities window. Do the same: focus it until the game subscribes
-- us, then let go (the subscription stays).
function Data:Subscribe()
    if not self.clubId then return end
    self.subscribing = true
    self.stats.focused = (self.stats.focused or 0) + 1
    Call(C_Club.FocusStream, self.clubId, self.streamId)
end

-- Lines can only be read from chat events, which come for channels you're
-- in as a chat channel: join it as one, and keep it out of the chat windows
-- (once; after that, showing it in a window is up to you).
function Data:JoinChat()
    if not self.clubId or self.chatJoined then return end
    self.chatJoined = true
    Call(C_Club.AddClubStreamChatChannel, self.clubId, self.streamId)
    local d, key = DB(), StreamKey(self.clubId, self.streamId)
    d.hidden = d.hidden or {}
    if d.hidden[key] then return end
    d.hidden[key] = true
    C_Timer.After(2, function()
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            local frame = _G["ChatFrame" .. i]
            if frame and ChatFrameUtil and ChatFrameUtil.RemoveCommunitiesChannel then
                pcall(ChatFrameUtil.RemoveCommunitiesChannel, frame, Data.clubId, Data.streamId, true)
            elseif frame and ChatFrame_RemoveCommunitiesChannel then
                pcall(ChatFrame_RemoveCommunitiesChannel, frame, Data.clubId, Data.streamId, true)
            end
        end
    end)
end

-- A line in a group channel, as chat sees it: here the text is readable.
function Data:OnChat(text)
    if not self.clubId or type(text) ~= "string" or Secret(text) then return end
    local info, clubId, streamId = Call(C_Club.GetInfoFromLastCommunityChatLine)
    if clubId ~= self.clubId or streamId ~= self.streamId or type(info) ~= "table" then return end
    self.stats.chatLines = (self.stats.chatLines or 0) + 1
    local line = { messageId = info.messageId, author = info.author, content = text }
    if type(line.author) == "table" and line.author.isSelf == true then self:OnOwnLine(line) else self:OnLine(line, true) end
    self:MarkRead()
end

function Data:OnSubscribed()
    self.subscribed = true
    self:JoinChat()
    if self.subscribing then
        self.subscribing = nil
        -- Leave it focused if the Communities window is showing it.
        local cf = CommunitiesFrame
        if not (cf and cf.focusedClubId == self.clubId and cf.focusedStreamId == self.streamId) then
            Call(C_Club.UnfocusStream, self.clubId, self.streamId)
        end
    end
    if not self.historyAsked then self:RequestHistory() end
    if self.retryPost then self.retryPost = nil; self.pendingPayload = nil; self:Update(true) end
end

function Data:RequestHistory()
    self.historyAsked = true
    local has = Call(C_Club.RequestMoreMessagesBefore, self.clubId, self.streamId, nil, HISTORY)
    if has then self:ReadHistory() end
    -- No history after a while (an empty channel, or none came): go on without it.
    C_Timer.After(15, function()
        if not Data.historyRead then
            Data.historyTimedOut = true
            Data:ReadHistory()
        end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CLUB_STREAM_ADDED")
events:RegisterEvent("CLUB_STREAMS_LOADED")
events:RegisterEvent("CLUB_MESSAGE_ADDED")
events:RegisterEvent("CLUB_MESSAGE_HISTORY_RECEIVED")
events:RegisterEvent("CLUB_STREAM_SUBSCRIBED")
events:RegisterEvent("CLUB_STREAM_UNSUBSCRIBED")
events:RegisterEvent("CLUB_ERROR")
events:RegisterEvent("CHAT_MSG_COMMUNITIES_CHANNEL")
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
        if a1 == Data.clubId then Data.stats.liveEvents = (Data.stats.liveEvents or 0) + 1 end
        if a1 == Data.clubId and a2 == Data.streamId then
            Data.stats.liveOurs = (Data.stats.liveOurs or 0) + 1
            local info = Call(C_Club.GetMessageInfo, a1, a2, a3)
            if info and info.author and info.author.isSelf then
                pcall(Data.OnOwnLine, Data, info)
            else
                pcall(Data.OnLine, Data, info, true)
            end
            Data:MarkRead()
        end
    elseif event == "CHAT_MSG_COMMUNITIES_CHANNEL" then
        pcall(Data.OnChat, Data, a1)
    elseif event == "CLUB_STREAM_SUBSCRIBED" then
        if a1 == Data.clubId and a2 == Data.streamId then pcall(Data.OnSubscribed, Data) end
    elseif event == "CLUB_STREAM_UNSUBSCRIBED" then
        if a1 == Data.clubId and a2 == Data.streamId then
            Data.subscribed = false
            C_Timer.After(2, function() if not Data.subscribed then Data:Subscribe() end end)
        end
    elseif event == "CLUB_ERROR" then
        -- "Couldn't send message" right after one of ours: subscribe and post again.
        if Data.lastSendAt and GetTime() - Data.lastSendAt < 5 then
            Data.stats.sendErrors = (Data.stats.sendErrors or 0) + 1
            Data.lastSendError = tostring(a2)
            Data.pendingPayload = nil
            wipe(Data.queue)
            if not Data.retried then
                Data.retried = true
                Data.retryPost = true
                Data.subscribed = Call(C_Club.IsSubscribedToStream, Data.clubId, Data.streamId)
                if Data.subscribed then Data:OnSubscribed() else Data:Subscribe() end
            end
        end
    elseif event == "CLUB_MESSAGE_HISTORY_RECEIVED" then
        if a1 == Data.clubId and a2 == Data.streamId then
            Data.stats.historyEvents = (Data.stats.historyEvents or 0) + 1
            pcall(Data.ReadHistory, Data)
        end
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

-- In case the game doesn't tell us about new lines in a channel we're not
-- looking at: check the channel every minute.
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(60, function()
        if Data.clubId and Data.historyRead and Data.subscribed then
            Call(C_Club.RequestMoreMessagesBefore, Data.clubId, Data.streamId, nil, 50)
            pcall(Data.ReadHistory, Data)
        end
    end)
end

-- One of our own lines arrived: a new post makes the previous one old.
function Data:OnOwnLine(info)
    self:OnLine(info, true)
    self:OwnOld()
end

-- Our own lines: the newest post stays (its parts go out within a couple of
-- minutes of each other), everything older goes. Times are the game's own,
-- so the computer's clock doesn't matter.
function Data:OwnOld()
    local newest
    for _, l in ipairs(self.ownLines or {}) do if not newest or l.at > newest.at then newest = l end end
    if not newest then return end
    self.ownLatest = newest
    self.ownOld = {}
    for _, l in ipairs(self.ownLines) do
        local k = MessageKey({ messageId = l.id }) or l
        if l.at < newest.at - 120 and not self.removing[k] then table.insert(self.ownOld, l.id) end
    end
    if #self.ownOld > 0 then self:CleanUp() end
end

-- Something about you changed: post again. A level or skill up (auto) waits
-- until AUTO_GAP seconds have passed since our last post.
function Data:Changed(auto)
    if not self.historyRead then return end
    if auto then
        local last = DB().postedAt[StreamKey(self.clubId, self.streamId)]
        local wait = last and (last + AUTO_GAP - time()) or 0
        if wait > 0 then
            if not self.autoTimer then
                self.autoTimer = true
                C_Timer.After(wait, function() Data.autoTimer = nil; Data:Update() end)
            end
            return
        end
    end
    self:Update()
end

-- Someone said hello: post our line, unless we posted moments ago or a post
-- is already on its way.
function Data:Reply()
    if self.stopped or not self.historyRead or self.pendingPayload then return end
    local last = DB().postedAt[StreamKey(self.clubId, self.streamId)]
    if last and time() - last < REPLY_GAP then return end
    self.stats.replies = (self.stats.replies or 0) + 1
    self:Update(true)
end

-- The "Share now" button: post right away (the click lets us).
function Data:ShareNow()
    if self.stopped then A:Message("The game blocked sharing this session; it'll try again after a /reload."); return end
    if not self.clubId then pcall(self.Start, self) end
    if not self.clubId then A:Message("Your group has no \"LAFW data\" channel yet: the group owner adds it once."); return end
    self.retried = nil
    if not self.subscribed and not Call(C_Club.IsSubscribedToStream, self.clubId, self.streamId) then
        -- Not subscribed yet: post once the game subscribes us.
        self.retryPost = true
        if not self.subscribing then self:Subscribe() end
        A:Message("Connecting to the LAFW data channel; your characters go out on your next key press or click.")
        return
    end
    self.subscribed = true
    if not self.historyRead then pcall(self.ReadHistory, self) end
    self.pendingPayload = nil
    self:Update(true)
    if #self.queue > 0 then pcall(self.OnInput, self) end
end

-- For the settings window: a line of status, and whether "Share now" can work.
function Data:Status()
    if self.stopped or self.blocked then return "|cffff6060blocked by the game this session|r", false end
    if not self.clubId then return "|cff9a9a9ano \"LAFW data\" channel in your group yet|r", true end
    if not self.subscribed then return "|cffffd100connecting to the LAFW data channel...|r", true end
    if #self.queue > 0 then return "|cffffd100sending, on your next key press or click|r", true end
    local at = DB().postedAt[StreamKey(self.clubId, self.streamId)]
    if not at then
        return self.ownLatest and "|cff33cc80shared|r" or "|cffffd100not shared yet|r", true
    end
    local ago = time() - at
    local when = ago < 60 and "just now" or (ago < 3600 and (math.floor(ago / 60) .. " min ago"))
        or (ago < 86400 and (math.floor(ago / 3600) .. " h ago")) or date("%d %b", at)
    return "|cff33cc80shared " .. when .. "|r", true
end
