-------------------------------------------------------------------------------
-- The community the addon follows: the one chosen in the settings window,
-- else the one selected in the community window's LAFW tab, else your first
-- Blizzard Group.
--
-- 1.7.0: the addon no longer touches chat at all. /l and adding the
-- community to the General tab are gone: the chat box hooks behind /l kept
-- party chat from sticking (Nov 10), and tabs are ChatProfiles' job.
-------------------------------------------------------------------------------
local _, A = ...
local CC = {}
A.CommunityChat = CC

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

-------------------------------------------------------------------------------
-- Which community
-------------------------------------------------------------------------------
function CC:Clubs()
    local list = Call(C_Club and C_Club.GetSubscribedClubs) or {}
    local out = {}
    for _, club in ipairs(list) do if club.clubId then out[#out + 1] = club end end
    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    return out
end

function CC:ClubId()
    local clubs = self:Clubs()
    local function Has(id)
        for _, c in ipairs(clubs) do if c.clubId == id then return true end end
    end
    local db = A.db or {}
    if db.chatClubId and Has(db.chatClubId) then return db.chatClubId end
    if db.clubId and Has(db.clubId) then return db.clubId end
    for _, c in ipairs(clubs) do
        if A.BN:IsBattleNetClub(c.clubId) then return c.clubId end
    end
end

function CC:ClubName()
    local id = self:ClubId()
    for _, c in ipairs(self:Clubs()) do if c.clubId == id then return c.name end end
end
