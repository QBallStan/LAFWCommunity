-------------------------------------------------------------------------------
-- Characters seen. Whenever the game reports which character a member is
-- playing, it's remembered (in your saved variables, per group member), so
-- the addon can list a member's other characters and name members while
-- they're offline. Each copy of the addon learns this by itself: it knows
-- the characters it has seen members on while you were online.
-------------------------------------------------------------------------------
local _, A = ...
local Seen = {}
A.Seen = Seen

local function DB()
    A.db.seen = A.db.seen or {}
    return A.db.seen
end
local function Key(clubId, memberId) return tostring(clubId) .. ":" .. tostring(memberId) end

-- c: { name, classFile, className, level, faction, realm, zone }
function Seen:Record(clubId, memberId, c)
    if not A.db or not clubId or not memberId or type(c) ~= "table" or type(c.name) ~= "string" then return end
    local db = DB()
    local key = Key(clubId, memberId)
    local m = db[key] or { chars = {} }
    db[key] = m
    local ck = c.name .. "-" .. (c.realm or "?")
    local e = m.chars[ck] or {}
    e.name, e.realm = c.name, c.realm
    e.class = c.classFile or e.class
    e.className = c.className or e.className
    e.level = c.level or e.level
    e.faction = c.faction or e.faction
    e.at = time()
    m.chars[ck] = e
    m.last, m.at = ck, e.at
end

-- The character they were last seen on, and when.
function Seen:Last(clubId, memberId)
    if not A.db or not clubId or not memberId then return nil end
    local m = DB()[Key(clubId, memberId)]
    local e = m and m.last and m.chars[m.last]
    if e then return e, m.at end
end

-- Every character seen for them, most recently seen first.
function Seen:Characters(clubId, memberId)
    local list = {}
    if not A.db or not clubId or not memberId then return list end
    local m = DB()[Key(clubId, memberId)]
    local last = m and m.last and m.chars[m.last]
    for _, e in pairs(m and m.chars or {}) do list[#list + 1] = e end
    table.sort(list, function(a, b)
        if (a == last) ~= (b == last) then return a == last end
        if (a.at or 0) ~= (b.at or 0) then return (a.at or 0) > (b.at or 0) end
        return a.name < b.name
    end)
    return list
end

-- "5 min ago", "3 h ago", "2 days ago".
function A.Ago(at)
    if not at then return "never" end
    local s = math.max(0, time() - at)
    if s < 120 then return "just now" end
    if s < 3600 then return math.floor(s / 60) .. " min ago" end
    if s < 86400 then return math.floor(s / 3600) .. " h ago" end
    local d = math.floor(s / 86400)
    return d .. (d == 1 and " day ago" or " days ago")
end
