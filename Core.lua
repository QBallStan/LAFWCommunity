-------------------------------------------------------------------------------
-- LAFW Community: the roster data, invites, the slash command and the saved
-- settings.
-------------------------------------------------------------------------------
local _, A = ...
A.rows = {}
function A:Message(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cffbb88eeLAFW:|r " .. text)
end
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if ok then return result end
end
local function Secret(v) return issecretvalue and v ~= nil and issecretvalue(v) end

function A:Communities()
    local clubs = Call(C_Club and C_Club.GetSubscribedClubs) or {}
    local result = {}
    for _, club in ipairs(clubs) do
        if club.clubId then result[#result + 1] = club end
    end
    table.sort(result, function(a, b) return (a.name or "") < (b.name or "") end)
    return result
end

-- The community the roster shows: the one picked in the Communities window
-- (LAFW tab), else the community chat's group.
function A:RosterClub()
    local id = self.db.clubId
    for _, club in ipairs(self:Communities()) do if club.clubId == id then return id end end
    return self.Settings and self.Settings:GroupId()
end

local function ClassName(classFile)
    if not classFile then return nil end
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile])
        or classFile:sub(1, 1) .. classFile:sub(2):lower()
end

-- Role names for the tooltip and the small tag in the roster.
local function RoleName(role)
    local r = Enum and Enum.ClubRoleIdentifier
    if not r or role == nil then return nil end
    if role == r.Owner then return "Owner" end
    if role == r.Leader then return "Leader" end
    if role == r.Moderator then return "Moderator" end
end

function A:Refresh()
    self.rows = {}
    local id = self:RosterClub()
    if not id then self.status = "You're not in a community yet."; return end
    self.rosterClub = id
    local members = Call(C_Club and C_Club.GetClubMembers, id)
    if not members then self.status = "Roster loading. Try Refresh in a moment."; return end
    local isBN = self.BN:IsBattleNetClub(id)
    local P = self.Presence
    local online = 0
    for _, memberId in ipairs(members) do
        local info = Call(C_Club and C_Club.GetMemberInfo, id, memberId)
        if type(info) == "table" then
            local presence = not Secret(info.presence) and info.presence or nil
            local row = { memberId = memberId, isSelf = info.isSelf == true, presence = presence,
                online = P.IsOnline(presence), status = P.StatusText(presence), role = RoleName(info.role),
                name = info.name or "?" }
            if isBN then
                pcall(self.FillBattleNetRow, self, row, info, id)
            else
                -- A character community lists characters.
                row.character = info.name
                row.detail = table.concat({ info.classID and GetClassInfo(info.classID) or "",
                    info.level and ("Level " .. info.level) or "" }, " "):match("^%s*(.-)%s*$")
            end
            if row.online then online = online + 1 end
            self.rows[#self.rows + 1] = row
        end
    end
    -- Online first, then by name.
    table.sort(self.rows, function(a, b)
        if a.online ~= b.online then return a.online end
        return tostring(a.name):lower() < tostring(b.name):lower()
    end)
    self.status = ("%d members, %d online"):format(#self.rows, online)
end

-- A Blizzard Group member: the character they're playing (the game says,
-- for every online member), or the last one seen while they're offline,
-- and every character seen for them.
function A:FillBattleNetRow(row, info, clubId)
    local BN = self.BN
    row.battleTag = info.name
    local shown, source = nil, nil
    if BN:Settings().enabled then shown, source = BN:Resolve(info.bnetAccountId, info.name, clubId, info) end
    if shown then row.name = shown end
    row.source = source
    row.chars = self.Seen:Characters(clubId, row.memberId)
    if row.isSelf then
        local _, classFile = UnitClass("player")
        row.detail = (ClassName(classFile) or "") .. " " .. (UnitLevel("player") or "")
        local zone = GetRealZoneText and GetRealZoneText()
        if zone and zone ~= "" then row.detail = row.detail .. ", " .. zone end
        row.faction = UnitFactionGroup("player")
        row.where = "forever"
        return
    end
    row.where = BN:FriendWhere(info.bnetAccountId, info.name)
    local game = BN:GameCharacter(info.bnetAccountId, info.name)
    if game then
        local bits = {}
        if game.className then bits[#bits + 1] = game.className .. (game.level and (" " .. game.level) or "") end
        if game.zone then bits[#bits + 1] = game.zone end
        row.detail = table.concat(bits, ", ")
        row.realm, row.faction = game.realm, game.faction
        if game.gameAccountID then row.invite = { gameAccountID = game.gameAccountID } end
        -- Whisper the character: its name, with the server when it's another.
        if game.rawName then
            local mine = GetNormalizedRealmName and GetNormalizedRealmName()
            row.tellTarget = (game.realmName and game.realmName ~= mine) and (game.rawName .. "-" .. game.realmName) or game.rawName
        end
        return
    end
    if row.where == "elsewhere" and row.online then row.detail = "In another game" end
    -- Not in Forever right now: the character they play the most, and when
    -- they were last seen.
    local last = self.Seen:Usual(clubId, row.memberId)
    local _, at = self.Seen:Last(clubId, row.memberId)
    if last then
        row.faction = last.faction
        local what = (last.className or ClassName(last.class) or "") .. (last.level and (" " .. last.level) or "")
        if not row.detail then row.detail = (what ~= "" and (what .. " - ") or "") .. "last seen " .. A.Ago(at) end
        row.lastSeen = at
    end
end

-- Whisper a member's character (your own faction: the game doesn't carry
-- whispers across factions), or their Battle.net account (anyone online).
function A:CanWhisper(row)
    if not row or row.isSelf then return false end
    if not row.online then return false, "Offline" end
    if row.battleTag and not row.tellTarget then return false, "Not playing Forever right now" end
    if not self:SameFaction(row) then return false, "Other faction: use the Battle.net whisper" end
    return true
end
function A:CanWhisperBNet(row)
    if not row or row.isSelf or not row.battleTag then return false end
    if not row.online then return false, "Offline" end
    return true
end
-- Opens the chat box on a whisper to `target`, without going through "/w"
-- (character names here can have spaces).
local function OpenTell(target, chatType)
    local box = ChatFrameUtil and ChatFrameUtil.ChooseBoxForSend and ChatFrameUtil.ChooseBoxForSend()
        or (ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend())
    if not box then return end
    -- As Blizzard's own Battle.net whisper does (ChatFrameUtil.SendBNetTell).
    box:SetTellTarget(target)
    box:SetChatType(chatType)
    local active = ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow()
    if box ~= active and ChatFrameUtil and ChatFrameUtil.OpenChat then ChatFrameUtil.OpenChat("")
    elseif box.UpdateHeader then box:UpdateHeader() end
end
function A:WhisperRow(row)
    if not self:CanWhisper(row) then return end
    if row.tellTarget then pcall(OpenTell, row.tellTarget, "WHISPER")
    elseif row.character then
        local send = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
        if send then pcall(send, row.character) end
    end
end
function A:WhisperBNetRow(row)
    if not self:CanWhisperBNet(row) then return end
    local send = (ChatFrameUtil and ChatFrameUtil.SendBNetTell) or ChatFrame_SendBNetTell
    if send then pcall(send, row.battleTag) end
end

-- Invite a member: someone in a Blizzard Group playing Forever through
-- Battle.net; in a character community, by character name.
function A:InviteRow(row)
    if not row then return end
    if row.invite and row.invite.gameAccountID and BNInviteFriend then
        pcall(BNInviteFriend, row.invite.gameAccountID)
    elseif not row.battleTag and row.online and row.character then
        local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
        if fn then pcall(fn, row.character) end
    end
end
-- Only your own faction can be invited.
function A:SameFaction(row)
    local mine = UnitFactionGroup("player")
    return not row.battleTag or (row.faction ~= nil and row.faction == mine)
end
function A:CanInvite(row)
    if not row then return false end
    if row.isSelf then return false, "That's you" end
    if not row.online then return false, "Offline" end
    if not self:SameFaction(row) then return false, "Other faction" end
    if row.invite then return true end
    if not row.battleTag then return row.character ~= nil end
    return false, "Not playing Forever right now"
end

-- Statuses change: repaint the open roster now and then.
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(30, function()
        if A.window and A.window:IsShown() and A.db then
            pcall(function() A:Refresh(); A:Draw() end)
        end
    end)
end

-- Names changed (a setting, a member's character): repaint the Communities member
-- list and the roster. Bursts repaint once.
local repaintPending
function A:NamesChanged()
    if repaintPending then return end
    repaintPending = true
    C_Timer.After(0.3, function()
        repaintPending = nil
        if A.BN then pcall(A.BN.RefreshMemberList, A.BN) end
        if A.window and A.window:IsShown() then
            pcall(function() A:Refresh(); A:Draw() end)
        end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == "LAFWCommunity" then
        if type(LAFWCommunityDB) ~= "table" then LAFWCommunityDB = {} end
        A.db = LAFWCommunityDB
        A.db.schemaVersion = 2
        -- Left over from 0.x: characters, mains, other members' data, the
        -- data channel.
        A.db.me, A.db.peers, A.db.professions, A.db.data, A.db.diagnostics = nil, nil, nil, nil, nil
        SLASH_LAFWCOMMUNITY1 = "/lafw"
        SlashCmdList.LAFWCOMMUNITY = function(command)
            command = (command or ""):lower():match("^%s*(.-)%s*$")
            if command == "test" then A:Test()
            elseif command == "settings" or command == "config" or command == "options" then A.Settings:Open()
            else A:Toggle() end
        end
    end
end)
