-------------------------------------------------------------------------------
-- Character names in Blizzard Groups.
--
-- A Blizzard Group (a Battle.net community) shows each sender by BattleTag.
-- This shows the character they are playing instead, wherever it can be
-- known:
--   * you: your current character (and your main, from /lafw main);
--   * your Battle.net friends: the character the game already reports for
--     them (they need nothing installed);
--   * other members running LAFW Community: their addon announces its
--     character on a hidden chat channel (A.Sync, below).
-- Members who set a main in their addon show as "Alt - Main" while on an
-- alt. Anyone else keeps their BattleTag. Only the shown text changes: clicking
-- the name still whispers or opens the menu for the right person.
-------------------------------------------------------------------------------
local _, A = ...
local BN = {}
A.BN = BN
BN.stats = { bnLinkCalls = 0, playerLinkCalls = 0, renamed = 0, kept = 0, memberRows = 0 }

local function Safe(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function Str(v) v = Safe(v); return type(v) == "string" and v ~= "" and v or nil end
local function Num(v) v = Safe(v); return type(v) == "number" and v or nil end
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

-- "Name#1234" and "Name" both name the same BattleTag.
local function TagKeys(tag)
    tag = Str(tag)
    if not tag then return nil end
    local short = tag:match("^([^#]+)#%d+$")
    return tag:lower(), short and short:lower()
end
BN.TagKeys = TagKeys

-- Two BattleTags name the same account, with or without the "#1234".
local function SameTag(a, b)
    local af, as = TagKeys(a)
    local bf, bs = TagKeys(b)
    if not af or not bf then return false end
    if af == bf then return true end
    -- Only one side may lack the number; two different numbers are two people.
    if not as and bs then return af == bs end
    if as and not bs then return as == bf end
    return false
end
BN.SameTag = SameTag

-- Forever characters have a family name: UnitName returns it as its second
-- value, and Blizzard joins the two with this separator ("Aldren Brightwater").
local SEP = Constants and Constants.CharacterNameSeparatorConsts
    and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "
if type(SEP) ~= "string" or SEP == "" then SEP = " " end
BN.SEP = SEP

-- One word of a name: letters only (any alphabet), no escape codes.
local function CleanWord(w)
    w = Str(w)
    if not w or #w > 48 or w:find("[|%c%s%p%d]") then return nil end
    return w
end

-- A character name we are willing to show: one to three clean words
-- joined by the separator.
local function CleanName(name)
    name = Str(name)
    if not name or #name > 100 then return nil end
    local words, start = {}, 1
    while true do
        local s, e = name:find(SEP, start, true)
        local word = CleanWord(name:sub(start, s and s - 1 or nil))
        if not word then return nil end
        words[#words + 1] = word
        if not s then break end
        start = e + 1
    end
    if #words > 3 then return nil end
    return table.concat(words, SEP)
end
BN.CleanName = CleanName

-- First name plus family name, when there is one.
function BN.Join(first, surname)
    first = CleanWord(first)
    if not first then return nil end
    surname = CleanWord(surname)
    return surname and (first .. SEP .. surname) or first
end

-- Your full name. On Forever, UnitName("player")'s second value is your
-- family name (elsewhere it's nil for yourself).
function BN.PlayerName()
    local first, surname = UnitName("player")
    return BN.Join(first, surname)
end

-- The name as shown: full, or the first name only.
function BN:Shown(full)
    if not full then return nil end
    if self:Settings().firstOnly then
        local s = full:find(SEP, 1, true)
        if s then return full:sub(1, s - 1) end
    end
    return full
end

function BN:Settings()
    local db = A.db or {}
    db.bnNames = db.bnNames or { enabled = true, showTag = false, firstOnly = false }
    local cfg = db.bnNames
    -- Character names are on by default: before 0.7.1 a chat command could
    -- switch them off by accident, so they're switched back on once.
    if A.db and not cfg.v then cfg.enabled = true; cfg.v = 2 end
    return cfg
end

-------------------------------------------------------------------------------
-- Who am I on Battle.net
-------------------------------------------------------------------------------
function BN:Self()
    local accountID, battleTag = Call(BNGetInfo)
    return Num(accountID), Str(battleTag)
end

-------------------------------------------------------------------------------
-- Is this a Blizzard Group
-------------------------------------------------------------------------------
local clubTypeCache = {}
function BN:IsBattleNetClub(clubId)
    clubId = Num(clubId)
    if not clubId then return false end
    if clubTypeCache[clubId] ~= nil then return clubTypeCache[clubId] end
    local info = Call(C_Club and C_Club.GetClubInfo, clubId)
    local t = info and Num(info.clubType)
    local isBN = t ~= nil and Enum and Enum.ClubType and t == Enum.ClubType.BattleNet or false
    if info then clubTypeCache[clubId] = isBN end
    return isBN
end
function BN:ForgetClubTypes() wipe(clubTypeCache) end

-------------------------------------------------------------------------------
-- The character of one Battle.net account
-- Returns name, source ("self" / "friend" / "addon") or nil.
-------------------------------------------------------------------------------
local function FromFriendAccount(info)
    if type(info) ~= "table" then return nil end
    local game = info.gameAccountInfo
    if type(game) == "table" and Safe(game.isOnline) ~= false then
        local name = CleanName(game.characterName)
        if not name then return nil end
        -- A family name, if the game reports one in its own field.
        if not name:find(SEP, 1, true) then
            local surname = Str(game.characterSurname) or Str(game.surname)
            if not surname then
                for k, v in pairs(game) do
                    if type(k) == "string" and k:lower():find("surname") and Str(v) then surname = v; break end
                end
            end
            name = BN.Join(name, surname) or name
        end
        return name
    end
end

function BN:FriendCharacter(bnetAccountID, battleTag)
    if not C_BattleNet then return nil end
    bnetAccountID = Num(bnetAccountID)
    if bnetAccountID and bnetAccountID ~= 0 then
        local name = FromFriendAccount(Call(C_BattleNet.GetAccountInfoByID, bnetAccountID))
        if name then return name end
    end
    -- No account ID: look the BattleTag up among friends.
    if not TagKeys(battleTag) then return nil end
    local count = Call(BNGetNumFriends) or 0
    for i = 1, count do
        local info = Call(C_BattleNet.GetFriendAccountInfo, i)
        if info and SameTag(info.battleTag, battleTag) then
            return FromFriendAccount(info)
        end
    end
end

-- A Battle.net friend's account info, found by account ID or BattleTag.
function BN:FriendInfo(bnetAccountID, battleTag)
    if not C_BattleNet then return nil end
    bnetAccountID = Num(bnetAccountID)
    if bnetAccountID and bnetAccountID ~= 0 then
        local info = Call(C_BattleNet.GetAccountInfoByID, bnetAccountID)
        if type(info) == "table" then return info end
    end
    if not TagKeys(battleTag) then return nil end
    for i = 1, (Call(BNGetNumFriends) or 0) do
        local info = Call(C_BattleNet.GetFriendAccountInfo, i)
        if info and SameTag(info.battleTag, battleTag) then return info end
    end
end

-- Where a Battle.net friend is: "forever" (in this same game), "elsewhere"
-- (online in another game, another WoW, or the Battle.net app), or nil
-- (not a friend, or offline).
function BN:FriendWhere(bnetAccountID, battleTag)
    local info = self:FriendInfo(bnetAccountID, battleTag)
    if type(info) ~= "table" then return nil end
    local game = info.gameAccountInfo
    local online = type(game) == "table" and Safe(game.isOnline)
    if online then
        local program = Str(game.clientProgram)
        local project = Num(game.wowProjectID)
        local isWoW = program == (BNET_CLIENT_WOW or "WoW")
        if isWoW and (not WOW_PROJECT_ID or not project or project == WOW_PROJECT_ID) then return "forever" end
        return "elsewhere"
    end
    -- Online on Battle.net without a game.
    if Safe(info.isOnline) or (type(game) == "table" and Str(game.clientProgram) == "BSAp") then return "elsewhere" end
    return nil
end

-- Returns character, source ("self" / "friend" / "addon"), main (nil when
-- unknown, or when they are on their main).
-- The group's own entry for this sender: found by account ID, else by name.
-- Its isSelf is the reliable way to know a message is yours (the group's
-- account IDs need not match BNGetInfo's).
function BN:Member(clubId, bnetAccountID, battleTag)
    clubId = Num(clubId)
    if not clubId or not C_Club then return nil end
    local members = Call(C_Club.GetClubMembers, clubId)
    if type(members) ~= "table" then return nil end
    local byName
    for _, memberId in ipairs(members) do
        local info = Call(C_Club.GetMemberInfo, clubId, memberId)
        if info then
            local id = Num(info.bnetAccountId)
            if bnetAccountID and id and id == bnetAccountID then return info end
            if not byName and battleTag and SameTag(info.name, battleTag) then byName = info end
        end
    end
    return byName
end

function BN:Resolve(bnetAccountID, battleTag, clubId, member)
    local selfID, selfTag = self:Self()
    bnetAccountID = Num(bnetAccountID)
    member = member or self:Member(clubId, bnetAccountID, battleTag)
    local isSelf = member and Safe(member.isSelf) == true
    if not isSelf then isSelf = (bnetAccountID and selfID and bnetAccountID == selfID) end
    if not isSelf and selfTag and battleTag then isSelf = SameTag(selfTag, battleTag) end
    if isSelf then
        local name = BN.PlayerName()
        if name then return name, "self", A.Me and CleanName(A.Me:MainForCurrent()) end
    end
    local name = self:FriendCharacter(bnetAccountID, battleTag)
    if name then return name, "friend", A.Sync and A.Sync:MainFor(battleTag, name) end
    if A.Sync then
        local char, main = A.Sync:Character(battleTag)
        if char then return char, "addon", main end
    end
end

-------------------------------------------------------------------------------
-- The shown name
-------------------------------------------------------------------------------
local function Replace(display, old, new)
    local s, e = display:find(old, 1, true)
    if not s then return nil end
    return display:sub(1, s - 1) .. new .. display:sub(e + 1)
end

-- display: the link text Blizzard is about to show (may carry brackets and
-- color codes); playerName: the BattleTag in it.
-- The text to show for a member instead of their BattleTag, or nil to keep
-- it: "Alt - Main", as character communities showed before; full names, or
-- first names only. An alt that shows the same as its main shows once.
function BN:NameFor(bnetAccountID, battleTag, clubId, member)
    local cfg = self:Settings()
    battleTag = Str(battleTag)
    if not cfg.enabled or not battleTag then return nil end
    local name, source, main = self:Resolve(bnetAccountID, battleTag, clubId, member)
    if not name then return nil end
    local alt, mainShown = self:Shown(name), self:Shown(main)
    local shown = (mainShown and mainShown ~= alt) and (alt .. " - " .. mainShown) or alt
    if cfg.showTag then
        shown = shown .. " (" .. (battleTag:match("^([^#]+)") or battleTag) .. ")"
    end
    return shown
end

function BN:Decorate(display, playerName, bnetAccountID, clubId)
    display, playerName = Str(display), Str(playerName)
    if not display or not playerName then return nil end
    local shown = self:NameFor(bnetAccountID, playerName, clubId)
    if not shown then return nil end
    return Replace(display, playerName, shown) or Replace(display, playerName:match("^([^#]+)") or playerName, shown)
end

-------------------------------------------------------------------------------
-- The member list in the Communities window. Blizzard fills each row from
-- its member info; after it does, a Blizzard Group row's name text is
-- swapped. Rows are pooled, so the hook runs on every refill.
-------------------------------------------------------------------------------
local ROW_METHODS = { "SetMember", "UpdateName", "UpdatePresence", "RefreshExpandedColumns" }

local function RowNameText(row)
    local nf = row.NameFrame
    local fs = (nf and (nf.Name or nf.Text)) or row.Name
    if fs and fs.SetText then return fs end
end

local renaming
local function RenameRow(row)
    if renaming then return end   -- Blizzard's relayout may call back in here
    renaming = true
    pcall(BN.RenameRowNow, row)
    renaming = false
end
function BN.RenameRowNow(row)
    local info = row.memberInfo or (row.GetMemberInfo and Call(row.GetMemberInfo, row))
    if type(info) ~= "table" then return end
    local clubType = Num(info.clubType)
    if not (Enum and Enum.ClubType and clubType == Enum.ClubType.BattleNet) then return end
    local fs = RowNameText(row)
    if not fs then return end
    local clubId = CommunitiesFrame and CommunitiesFrame.GetSelectedClubId and Call(CommunitiesFrame.GetSelectedClubId, CommunitiesFrame)
    local shown = BN:NameFor(info.bnetAccountId, info.name, clubId, info)
    if shown and fs:GetText() ~= shown then
        BN.SetRowName(row, fs, shown)
        BN.stats.memberRows = BN.stats.memberRows + 1
    end
end

-- Blizzard lays the row out (the name's width, and the owner's crown and
-- other icons after it) from the text it set. After changing the text, ask
-- the row to lay itself out again; failing that, resize the name and its
-- frame by the difference, so the icons move with the name's end.
function BN.SetRowName(row, fs, text)
    local nf = row.NameFrame
    local oldW = fs:GetWidth() or 0
    fs:SetText(text)
    if type(row.UpdateNameFrame) == "function" and pcall(row.UpdateNameFrame, row) then
        BN.stats.relaid = (BN.stats.relaid or 0) + 1
        return
    end
    local newW = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth() or oldW
    if nf and nf.GetWidth and nf ~= row then
        -- Keep the whole name frame inside the row.
        local icons = math.max(0, (nf:GetWidth() or 0) - oldW)
        local room = (row:GetWidth() or 0) - icons - 20
        if room > 0 then newW = math.min(newW, room) end
        fs:SetWidth(newW)
        nf:SetWidth(newW + icons)
    else
        fs:SetWidth(newW)
    end
    BN.stats.resized = (BN.stats.resized or 0) + 1
end
BN.RenameRow = RenameRow

local hookedRows = setmetatable({}, { __mode = "k" })
local function HookRow(row)
    if hookedRows[row] then return end
    hookedRows[row] = true
    for _, m in ipairs(ROW_METHODS) do
        if type(row[m]) == "function" then hooksecurefunc(row, m, RenameRow) end
    end
    RenameRow(row)
end

function BN:InstallMemberList()
    local list = CommunitiesFrame and CommunitiesFrame.MemberList
    local box = list and list.ScrollBox
    if not box or self.memberListHooked then return end
    self.memberListHooked = true
    -- Rows made from now on, and the ones that already exist.
    if ScrollUtil and ScrollUtil.AddAcquiredFrameCallback then
        ScrollUtil.AddAcquiredFrameCallback(box, function(_, frame) HookRow(frame) end, BN, true)
    elseif box.RegisterCallback and box.Event and box.Event.OnAcquiredFrame then
        box:RegisterCallback(box.Event.OnAcquiredFrame, function(_, frame) HookRow(frame) end, BN)
    end
    if box.ForEachFrame then Call(box.ForEachFrame, box, HookRow) end
end

-- Repaint after names change (a setting, or a member's addon announcing).
function BN:RefreshMemberList()
    local box = CommunitiesFrame and CommunitiesFrame.MemberList and CommunitiesFrame.MemberList.ScrollBox
    if box and box.ForEachFrame and CommunitiesFrame:IsShown() then
        Call(box.ForEachFrame, box, function(row)
            -- Back to Blizzard's text (and layout), then rename.
            local fs = RowNameText(row)
            if fs and row.memberInfo and Str(row.memberInfo.name) then
                BN.SetRowName(row, fs, row.memberInfo.name)
            end
            RenameRow(row)
        end)
    end
end

-------------------------------------------------------------------------------
-- Hooks: Blizzard builds a Blizzard Group sender's link with
-- GetBNPlayerCommunityLink (a character community's with
-- GetPlayerCommunityLink). Both are wrapped; only the display text changes.
-------------------------------------------------------------------------------

function BN:InstallHooks()
    if self.hooked then return end
    self.hooked = true
    if type(GetBNPlayerCommunityLink) == "function" then
        local original = GetBNPlayerCommunityLink
        GetBNPlayerCommunityLink = function(playerName, display, bnetIDAccount, clubId, ...)
            BN.stats.bnLinkCalls = BN.stats.bnLinkCalls + 1
            local ok, new = pcall(BN.Decorate, BN, display, playerName, bnetIDAccount, clubId)
            if ok and new then BN.stats.renamed = BN.stats.renamed + 1; display = new
            else BN.stats.kept = BN.stats.kept + 1 end
            return original(playerName, display, bnetIDAccount, clubId, ...)
        end
        self.hookedBN = true
    end
    -- Some builds may route Blizzard Group senders through the character
    -- link; act only when the club really is a Blizzard Group.
    if type(GetPlayerCommunityLink) == "function" then
        local original = GetPlayerCommunityLink
        GetPlayerCommunityLink = function(playerName, display, clubId, ...)
            BN.stats.playerLinkCalls = BN.stats.playerLinkCalls + 1
            if BN:IsBattleNetClub(clubId) then
                local ok, new = pcall(BN.Decorate, BN, display, playerName, nil, clubId)
                if ok and new then BN.stats.renamed = BN.stats.renamed + 1; display = new
                else BN.stats.kept = BN.stats.kept + 1 end
            end
            return original(playerName, display, clubId, ...)
        end
        self.hookedPlayer = true
    end
end

-- The test command looks at what the chat events actually carry.
BN.lastChat = nil
local chatWatch = CreateFrame("Frame")
chatWatch:RegisterEvent("CHAT_MSG_COMMUNITIES_CHANNEL")
chatWatch:SetScript("OnEvent", function(_, _, ...)
    local args = { ... }
    local sample = { at = time(), count = (BN.lastChat and BN.lastChat.count or 0) + 1, types = {} }
    for i = 1, 17 do
        local v = args[i]
        if issecretvalue and v ~= nil and issecretvalue(v) then sample.types[i] = "secret"
        else sample.types[i] = type(v) end
    end
    sample.author = Str(args[2])
    sample.bnSenderID = Num(args[13])
    BN.lastChat = sample
end)

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("CLUB_ADDED")
loader:RegisterEvent("CLUB_REMOVED")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then BN:InstallHooks(); BN:InstallMemberList()
    elseif event == "ADDON_LOADED" then
        if name == "Blizzard_Communities" then BN:InstallMemberList() end
    else BN:ForgetClubTypes() end
end)
