-------------------------------------------------------------------------------
-- Member notes.
--
-- The hidden channel (Sync.lua) only reaches members on your own server and
-- faction. A member note is kept by the Blizzard Group itself and every
-- member sees it, whatever their server, faction or game. Addons may read
-- notes but not write them (the game blocks it: Blizzard's UI only), so each
-- member sets theirs once by hand, to their main:
--     "Main: Tachi Nightwatch"
-- The settings window shows the exact text to copy. The addon reads everyone's
-- note (BattleNetNames.lua, BN.ParseNote).
-------------------------------------------------------------------------------
local _, A = ...
local Notes = {}
A.Notes = Notes

-- The note to set for your current server: "Main: <your main>".
function Notes:Suggested()
    local key = A.Me and A.Me:MainKey()
    local c = key and A.Me:Data().chars[key]
    if not c or not c.name then return nil end
    return "Main: " .. c.name
end

-- Your note in the chat community as it is now, if the game tells us.
function Notes:Current()
    local clubId = A.CommunityChat and A.CommunityChat:ClubId()
    if not clubId or not (C_Club and C_Club.GetMemberInfoForSelf) then return nil end
    local ok, me = pcall(C_Club.GetMemberInfoForSelf, clubId)
    if ok and type(me) == "table" and type(me.memberNote) == "string" and me.memberNote ~= "" then return me.memberNote end
end

local events = CreateFrame("Frame")
events:RegisterEvent("CLUB_MEMBER_UPDATED")
events:RegisterEvent("CLUB_MEMBERS_UPDATED")
events:SetScript("OnEvent", function()
    if not A.db then return end
    -- Someone's note changed: repaint names, and our own note's status.
    A:NamesChanged()
    if A.Me and A.Me.window and A.Me.window:IsShown() then pcall(A.Me.Render, A.Me) end
end)
