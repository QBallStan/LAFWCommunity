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
function A:Communities()
    local clubs = Call(C_Club and C_Club.GetSubscribedClubs) or {}
    local result = {}
    for _, club in ipairs(clubs) do
        if club.clubId then result[#result + 1] = club end
    end
    table.sort(result, function(a,b) return (a.name or "") < (b.name or "") end)
    return result
end
function A:Refresh()
    self.rows = {}
    local id = self.db.clubId
    if not id then self.status = "Choose a community above."; return end
    local found
    for _, club in ipairs(self:Communities()) do
        if club.clubId == id then found = true end
    end
    if not found then self.status = "Selected community is unavailable. Choose another community."; return end
    local members = Call(C_Club and C_Club.GetClubMembers, id)
    if not members then self.status = "Roster unavailable or loading. Try Refresh shortly."; return end
    for _, memberId in ipairs(members) do
        local info = Call(C_Club and C_Club.GetMemberInfo, id, memberId)
        if info then
            local faction = "Unknown"
            if Enum and Enum.PvPFaction then
                if info.faction == Enum.PvPFaction.Alliance then faction = "Alliance"
                elseif info.faction == Enum.PvPFaction.Horde then faction = "Horde" end
            end
            if faction == "Unknown" and info.isSelf then
                faction = UnitFactionGroup("player") or "Unknown"
            end
            local class = info.classID and GetClassInfo(info.classID)
            local presence = Enum and Enum.ClubMemberPresence
            local online
            if presence and info.presence ~= nil then
                online = info.presence ~= presence.Offline and info.presence ~= presence.Unknown
            end
            -- Character communities list each member's professions.
            local professions = {}
            for _, field in ipairs({ "profession1Name", "profession2Name" }) do
                if type(info[field]) == "string" and info[field] ~= "" then professions[#professions + 1] = info[field] end
            end
            local row = { name = info.name or "Unknown", faction = faction,
                level = info.level, memberId = memberId, class = class, online = online,
                professions = #professions > 0 and table.concat(professions, " - ") or nil }
            -- A Blizzard Group lists BattleTags: show the character instead,
            -- with what we know of it and of the member's other characters.
            if self.BN and self.BN:IsBattleNetClub(id) then pcall(self.FillBattleNetRow, self, row, info, id) end
            self.rows[#self.rows + 1] = row
        end
    end
    table.sort(self.rows, function(a,b) return a.name < b.name end)
    self.status = #self.rows .. " characters returned by this client. Visibility may be partial."
end
local function ClassName(classFile)
    if not classFile then return nil end
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile])
        or classFile:sub(1, 1) .. classFile:sub(2):lower()
end

-- A Blizzard Group row: the member's current character (yours, or what
-- their addon announced) and, as alts, their other characters on that server.
function A:FillBattleNetRow(row, info, clubId)
    local BN = self.BN
    row.battleTag = info.name
    local others
    -- The tab shows just the character, tagged (alt) or (main); the main's
    -- name is in the tooltip. Chat and the member list keep "Alt - Main".
    local char, source, main, noteIsMain = nil, nil, nil, nil
    if BN:Settings().enabled then char, source, main, noteIsMain = BN:Resolve(info.bnetAccountId, info.name, clubId, info) end
    row.mainOnly = source == "note-main" or nil   -- we know their main, not what they're on
    if char then
        row.name = BN:Shown(char)
        row.mainName = main and BN:Shown(main) ~= row.name and main or nil
        row.role = main and "alt" or nil
    end
    if info.isSelf == true then
        local _, classFile = UnitClass("player")
        row.class, row.level = ClassName(classFile), UnitLevel("player")
        row.faction = UnitFactionGroup("player") or row.faction
        others = self.Me:OthersHere()
        row.professions = self.Me:Professions()
        if char and not main and self.Me:MainKey() == self.Me:CurrentKey() then row.role = "main" end
    else
        local p = self.Sync and self.Sync:Peer(self.Sync:KeyFor(clubId, info) or info.name)
        -- Their addon's details only describe the character it announced.
        if p and (not char or char == p.char) then
            row.class, row.level, row.professions = ClassName(p.class), p.level, p.profs
            if p.faction == "Alliance" or p.faction == "Horde" then row.faction = p.faction end
            others = p.others
            if char and not main and p.onMain then row.role = "main" end
        end
        -- Their member note says they're on their main.
        if char and not main and noteIsMain then row.role = "main" end
    end
    -- Online but not in Forever: on the Battle.net phone app, a friend in
    -- another game (or another WoW), or a member whose addon has gone quiet.
    -- Someone we can't place stays plain online.
    row.elsewhere = nil
    if row.online and info.isSelf ~= true then
        local presence = Enum and Enum.ClubMemberPresence
        local where = BN:FriendWhere(info.bnetAccountId, info.name)
        local key = self.Sync and (self.Sync:KeyFor(clubId, info) or info.name)
        local inForever = self.Sync and self.Sync:InForever(key)
        if presence and presence.OnlineMobile and info.presence == presence.OnlineMobile then
            row.elsewhere, row.elsewhereWhy = true, "on the Battle.net app"
        elseif where == "forever" or inForever == true then
            row.elsewhere = false
        elseif where == "elsewhere" then
            row.elsewhere, row.elsewhereWhy = true, "in another game"
        elseif inForever == false then
            row.elsewhere, row.elsewhereWhy = true, "not in Forever"
        end
    elseif info.isSelf == true then
        row.elsewhere = false
    end
    -- How to invite them: through Battle.net for a friend in Forever, else by
    -- the invite name their addon gave us.
    row.invite = nil
    if info.isSelf == true then
        row.inviteWhy = "That's you"
    elseif not row.online then
        row.inviteWhy = "Offline"
    elseif row.elsewhere then
        row.inviteWhy = "Not in Forever right now"
    else
        local friend = BN:FriendInfo(info.bnetAccountId, info.name)
        local game = friend and friend.gameAccountInfo
        local key = self.Sync and (self.Sync:KeyFor(clubId, info) or info.name)
        local p = self.Sync and self.Sync:Peer(key)
        if BN:FriendWhere(info.bnetAccountId, info.name) == "forever" and type(game) == "table" and game.gameAccountID then
            row.invite = { gameAccountID = game.gameAccountID }
        elseif p and self.Sync:InForever(key) and (p.inviteName or p.char) then
            row.invite = { name = p.inviteName or p.char }
        else
            row.inviteWhy = "Can't tell which character to invite (not a Battle.net friend, no LAFW Community)"
        end
    end
    row.bnAlts = {}
    for _, o in ipairs(others or {}) do
        row.bnAlts[#row.bnAlts + 1] = { name = BN:Shown(o.name), role = o.isMain and "main" or nil,
            class = ClassName(o.class), level = o.level, professions = o.profs,
            faction = o.faction or row.faction, online = false, memberId = row.memberId .. ":" .. o.name }
    end
end

-- Invite a member row to your group. Character communities invite by the
-- row's character name.
function A:InviteRow(row)
    if not row then return end
    local inv = row.invite
    if inv and inv.gameAccountID and BNInviteFriend then
        pcall(BNInviteFriend, inv.gameAccountID)
    elseif inv and inv.name then
        local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
        if fn then pcall(fn, inv.name) end
    elseif not row.battleTag and row.online and row.name then
        local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
        if fn then pcall(fn, row.name) end
    end
end
function A:CanInvite(row)
    if not row then return false, nil end
    if row.invite then return true end
    if not row.battleTag then return row.online == true, row.online and nil or "Offline" end
    return false, row.inviteWhy
end

-- Who's in Forever changes as members' addons go quiet: repaint the open
-- tab now and then.
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(60, function()
        if A.window and A.window:IsShown() and A.db and A.db.clubId then
            pcall(function() A:Refresh(); A:Draw() end)
        end
    end)
end

-- Names changed (a setting, your main, or a member announcing): repaint
-- the Communities member list and the roster. Bursts repaint once.
local repaintPending
function A:NamesChanged()
    if repaintPending then return end
    repaintPending = true
    C_Timer.After(0.3, function()
        repaintPending = nil
        if A.BN then pcall(A.BN.RefreshMemberList, A.BN) end
        if A.window and A.window:IsShown() and A.db.clubId then
            pcall(function() A:Refresh(); A:Draw() end)
        end
    end)
end
function A:Diagnostics()
    local version, build, _, interface = GetBuildInfo()
    self.db.diagnostics = { version = version, build = build, interface = interface,
        locale = GetLocale(), checkedAt = time(), clubAPI = type(C_Club and C_Club.GetClubMembers) == "function" }
    self:Message("Client " .. version .. " / build " .. build .. " / interface " .. interface)
    self:Message("Community roster API: " .. (self.db.diagnostics.clubAPI and "present (behavior unverified)" or "unavailable"))
end
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == "LAFWCommunity" then
        if type(LAFWCommunityDB) ~= "table" then LAFWCommunityDB = {} end
        A.db = LAFWCommunityDB
        A.db.schemaVersion = 1
        A.db.professions = nil   -- 0.8 kept a separate cache; characters now carry their own
        SLASH_LAFWCOMMUNITY1 = "/lafw"
        SlashCmdList.LAFWCOMMUNITY = function(command)
            command = (command or ""):lower():match("^%s*(.-)%s*$")
            if command == "diagnostics" then A:Diagnostics()
            elseif command == "test" then A:Test()
            elseif command == "main" or command == "settings" or command == "config" then A.Me:Open()
            elseif command == "names" or command == "names tag" or command == "names first" then
                local cfg = A.BN:Settings()
                if command == "names first" then
                    cfg.firstOnly = not cfg.firstOnly
                    A:Message("Blizzard Group names: " .. (cfg.firstOnly and "first names only" or "full names") .. ".")
                    if A.Me.window and A.Me.window:IsShown() then A.Me:Render() end
                elseif command == "names tag" then
                    cfg.showTag = not cfg.showTag
                    A:Message("Blizzard Group names: BattleTag after the character " .. (cfg.showTag and "on" or "off") .. ".")
                else
                    cfg.enabled = not cfg.enabled
                    A:Message("Blizzard Group names: " .. (cfg.enabled and "character names" or "BattleTags")
                        .. ". Type /lafw names again to switch back.")
                end
            else A:Toggle() end
        end
    end
end)
