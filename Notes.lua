-------------------------------------------------------------------------------
-- Sharing through member notes.
--
-- The hidden channel (Sync.lua) only reaches members on your own server and
-- faction. A member note is kept by the Blizzard Group itself and reaches
-- every member, whatever their server, faction or game. So each addon writes
-- your current character into your own note in the community, readable by
-- people too:
--     "Tachi Gravewatch (alt of Tachi Nightwatch)"
--     "Tachi Nightwatch (main)"
--     "Tachi Nightwatch"                       (no main set)
-- and reads the others' notes (BattleNetNames.lua, BN.ParseNote).
-- Alts don't fit a note: they still come over the channel.
-------------------------------------------------------------------------------
local _, A = ...
local Notes = {}
A.Notes = Notes
Notes.stats = { written = 0, skipped = 0 }

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

-- The note for who you are now, longest form first: shorter ones are tried
-- if the group refuses a long note.
function Notes:Candidates()
    local char = A.BN.PlayerName()
    if not char then return {} end
    local main = A.Me and A.Me:MainForCurrent()
    local onMain = A.Me and A.Me:MainKey() and A.Me:MainKey() == A.Me:CurrentKey()
    local list = {}
    if main then
        list[#list + 1] = char .. " (alt of " .. main .. ")"
        local first = main:match("^(%S+)")
        if first and first ~= main then list[#list + 1] = char .. " (alt of " .. first .. ")" end
    elseif onMain then
        list[#list + 1] = char .. " (main)"
    end
    list[#list + 1] = char
    return list
end

local function Valid(clubType, text)
    if not (C_Club and C_Club.ValidateText and Enum and Enum.ClubFieldType and Enum.ClubFieldType.ClubMemberNote) then
        return true
    end
    local result = Call(C_Club.ValidateText, clubType, text, Enum.ClubFieldType.ClubMemberNote)
    local success = Enum.ValidateNameResult and (Enum.ValidateNameResult.Success or Enum.ValidateNameResult.NameSuccess) or 0
    return result == nil or result == success or result == 0
end

-- Write your note in the community LAFW uses for chat (never in other groups).
function Notes:Write()
    if not A.db or not (C_Club and C_Club.SetClubMemberNote and C_Club.GetMemberInfoForSelf) then return end
    local clubId = A.CommunityChat and A.CommunityChat:ClubId()
    if not clubId or not A.BN:IsBattleNetClub(clubId) then return end
    local privileges = Call(C_Club.GetClubPrivileges, clubId)
    if type(privileges) == "table" and privileges.canSetOwnMemberNote == false then
        self.stats.lastError = "the group doesn't allow members to set their own note"
        return
    end
    local me = Call(C_Club.GetMemberInfoForSelf, clubId)
    if type(me) ~= "table" or type(me.memberId) ~= "number" then return end
    local info = Call(C_Club.GetClubInfo, clubId)
    local clubType = info and info.clubType or (Enum and Enum.ClubType and Enum.ClubType.BattleNet)
    for _, text in ipairs(self:Candidates()) do
        if Valid(clubType, text) then
            if me.memberNote == text then self.stats.skipped = self.stats.skipped + 1; return end
            local ok = pcall(C_Club.SetClubMemberNote, clubId, me.memberId, text)
            if ok then
                self.stats.written = self.stats.written + 1
                self.stats.last, self.stats.lastError = text, nil
            else
                self.stats.lastError = "the game refused the note"
            end
            return
        end
    end
    self.stats.lastError = "no note short enough"
end

-- Communities finish loading a little after login; a main change or a new
-- character rewrites it.
local pending
function Notes:Soon(delay)
    if pending then return end
    pending = true
    C_Timer.After(delay or 3, function() pending = nil; pcall(Notes.Write, Notes) end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CLUB_MEMBER_UPDATED")
events:RegisterEvent("CLUB_MEMBERS_UPDATED")
events:SetScript("OnEvent", function(_, event)
    if not A.db then return end
    if event == "PLAYER_LOGIN" then
        Notes:Soon(8)
        C_Timer.After(30, function() pcall(Notes.Write, Notes) end)   -- in case the group was slow
    else
        -- Someone's note changed: repaint names.
        A:NamesChanged()
    end
end)
