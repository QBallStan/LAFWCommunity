-------------------------------------------------------------------------------
-- Characters seen. Whenever the game reports which character a member is
-- playing, it's remembered (in your saved variables) with how long it's been
-- seen played, so the addon can list a member's characters and name members
-- while they're offline by the one they play most.
--
-- People, not member numbers: the game's member numbers in a group change
-- from one session to the next (seen Nov 8: a number that was Lefkada one
-- day was Milon, then Luben), and so do the account numbers. The only thing
-- that stays the same is the characters. So:
--   * a person is a set of characters (db.people);
--   * within one session, a member number is one person: every character
--     seen under it this session joins that person;
--   * a character seen again in a later session finds its person, and that
--     member number belongs to that person for the rest of the session.
-- A member who hasn't been seen playing yet this session can't be told apart
-- from anyone else, so they keep their BattleTag until they're seen.
-------------------------------------------------------------------------------
local _, A = ...
local Seen = {}
A.Seen = Seen

local session = {}   -- ["club:member"] = person id, this session only

local function DB()
    local db = A.db
    -- 1.6.0: db.seen was keyed by member number, which mixed people up.
    if db.seen then db.seen = nil end
    db.people = db.people or {}
    db.charOwner = db.charOwner or {}
    db.nextPerson = db.nextPerson or 1
    return db
end
local function Key(clubId, memberId) return tostring(clubId) .. ":" .. tostring(memberId) end

-- Fold person `from` into person `into` (two sets of characters that turn
-- out to be the same member).
local function Merge(db, into, from)
    if into == from then return end
    local a, b = db.people[into], db.people[from]
    if not a or not b then return end
    for ck, e in pairs(b.chars) do
        local mine = a.chars[ck]
        if not mine or (e.at or 0) > (mine.at or 0) then
            if mine then e.played = (e.played or 0) + (mine.played or 0) end
            a.chars[ck] = e
        else
            mine.played = (mine.played or 0) + (e.played or 0)
        end
        db.charOwner[ck] = into
    end
    if (b.at or 0) > (a.at or 0) then a.at, a.last = b.at, b.last end
    db.people[from] = nil
    for k, pid in pairs(session) do if pid == from then session[k] = into end end
end

-- c: { name, classFile, className, level, faction, realm }
function Seen:Record(clubId, memberId, c)
    if not A.db or not clubId or not memberId or type(c) ~= "table" or type(c.name) ~= "string" then return end
    local db = DB()
    local key = Key(clubId, memberId)
    local ck = c.name .. "-" .. (c.realm or "?")
    local owner, current = db.charOwner[ck], session[key]
    if owner and not db.people[owner] then owner = nil end
    if current and not db.people[current] then current = nil end
    local pid
    if owner and current and owner ~= current then
        Merge(db, owner, current); pid = owner
    else
        pid = owner or current
    end
    if not pid then
        pid = db.nextPerson
        db.nextPerson = pid + 1
        db.people[pid] = { chars = {} }
    end
    session[key] = pid
    db.charOwner[ck] = pid
    local p = db.people[pid]
    local e = p.chars[ck] or {}
    e.name, e.realm = c.name, c.realm
    e.class = c.classFile or e.class
    e.className = c.className or e.className
    e.level = c.level or e.level
    e.faction = c.faction or e.faction
    -- Time seen playing it: the time since it was last seen, when that's
    -- a short gap (the addon looks every minute while you're online).
    local now = time()
    if p.last == ck and e.at and now - e.at <= 180 then e.played = (e.played or 0) + (now - e.at) end
    e.at = now
    p.chars[ck] = e
    p.last, p.at = ck, now
end

local function Person(clubId, memberId)
    if not A.db or not clubId or not memberId then return nil end
    local pid = session[Key(clubId, memberId)]
    return pid and DB().people[pid]
end

-- The character they were last seen on, and when.
function Seen:Last(clubId, memberId)
    local p = Person(clubId, memberId)
    local e = p and p.last and p.chars[p.last]
    if e then return e, p.at end
end

-- The character they've been seen playing the longest (ties: the latest),
-- to name them while they're offline.
function Seen:Usual(clubId, memberId)
    local p = Person(clubId, memberId)
    if not p then return nil end
    local best = p.last and p.chars[p.last]
    for _, e in pairs(p.chars) do
        local pl, bp = e.played or 0, best and (best.played or 0)
        if not best or pl > bp or (pl == bp and (e.at or 0) > (best.at or 0)) then best = e end
    end
    return best, p.at
end

-- Every character seen for them, the current one first, then most recent.
function Seen:Characters(clubId, memberId)
    local list = {}
    local p = Person(clubId, memberId)
    if not p then return list end
    local last = p.last and p.chars[p.last]
    for _, e in pairs(p.chars) do list[#list + 1] = e end
    table.sort(list, function(a, b)
        if (a == last) ~= (b == last) then return a == last end
        if (a.at or 0) ~= (b.at or 0) then return (a.at or 0) > (b.at or 0) end
        return a.name < b.name
    end)
    return list
end

-- How many people are remembered (for /lafw test).
function Seen:Count()
    local n = 0
    for _ in pairs(A.db and A.db.people or {}) do n = n + 1 end
    return n
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
