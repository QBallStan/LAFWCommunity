-------------------------------------------------------------------------------
-- Your characters and your main, plus the settings window.
--
-- Every character you log in with the addon is remembered (account-wide).
-- You pick your main; every other character on the same server (ruleset)
-- is its alt. Each server has its own main. Shared with other LAFW
-- Community users (Sync), so a Blizzard Group shows "Alt - Main" for you.
--
-- The settings window (minimap button, the "My characters" button in the
-- community window, /lafw settings) holds every option and the main picker.
-------------------------------------------------------------------------------
local _, A = ...
local Me = {}
A.Me = Me

-- Keyed by full name and server: on Forever several characters can share a
-- first name ("Aldren Stonewatch", "Aldren Brightwater").
local function Key(name, realm) return (name or "?") .. "-" .. (realm or "?") end

function Me:Data()
    A.db.me = A.db.me or { chars = {}, mains = {} }
    local d = A.db.me
    d.chars = d.chars or {}
    d.mains = d.mains or {}
    -- 0.3-0.4 kept one main for every server.
    if d.main then
        local c = d.chars[d.main]
        if c and c.realm and not d.mains[c.realm] then d.mains[c.realm] = d.main end
        d.main = nil
    end
    return d
end

-- The current character's professions: "Tailoring 1/75 - Enchanting 1/75".
function Me:Professions()
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return nil end
    local ok, first, second = pcall(GetProfessions)
    if not ok then return nil end
    local list = {}
    for _, index in ipairs({ first or false, second or false }) do
        if index then
            local fine, name, _, skill, maxSkill = pcall(GetProfessionInfo, index)
            if fine and type(name) == "string" and name ~= "" then
                local rank = type(skill) == "number" and (" " .. skill .. (type(maxSkill) == "number" and "/" .. maxSkill or "")) or ""
                list[#list + 1] = name .. rank
            end
        end
    end
    return #list > 0 and table.concat(list, " - ") or nil
end

-- Your other characters on the current server, for the roster and Sync.
function Me:OthersHere()
    local d, here, current = self:Data(), GetRealmName(), self:CurrentKey()
    local list = {}
    for key, c in pairs(d.chars) do
        if c.realm == here and key ~= current then
            list[#list + 1] = { key = key, name = c.name, profs = c.profs, class = c.class,
                level = c.level, faction = c.faction, isMain = d.mains[here] == key }
        end
    end
    table.sort(list, function(a, b)
        if a.isMain ~= b.isMain then return a.isMain end
        return a.name < b.name
    end)
    return list
end

function Me:CurrentKey()
    return Key(A.BN.PlayerName() or UnitName("player"), GetRealmName())
end

-- Remember the character you're on.
function Me:Record()
    local d = self:Data()
    local key = self:CurrentKey()
    local realm = GetRealmName()
    local _, classFile = UnitClass("player")
    -- 0.3.0 keyed characters by first name only: move that entry over.
    local oldKey = Key(UnitName("player"), realm)
    if oldKey ~= key and d.chars[oldKey] and not d.chars[key] then
        d.chars[key] = d.chars[oldKey]; d.chars[oldKey] = nil
        for r, k in pairs(d.mains) do if k == oldKey then d.mains[r] = key end end
    end
    local c = d.chars[key] or {}
    c.alt = nil   -- 0.3-0.4 per-character alt switch, no longer used
    c.name, c.realm = A.BN.PlayerName() or UnitName("player"), realm
    c.faction, c.class, c.level = UnitFactionGroup("player"), classFile, UnitLevel("player")
    c.profs = self:Professions() or c.profs
    c.seen = time()
    d.chars[key] = c
    if self.window and self.window:IsShown() then self:Render() end
end

function Me:MainKey(realm)
    local d = self:Data()
    local key = d.mains[realm or GetRealmName()]
    return key and d.chars[key] and key or nil
end

-- The main to show next to the current character: nil when this server has
-- no main, or when you're on it.
function Me:MainForCurrent()
    local key = self:MainKey()
    if not key or key == self:CurrentKey() then return nil end
    return self:Data().chars[key].name
end

function Me:SetMain(key)
    local d = self:Data()
    local c = d.chars[key]
    if not c or not c.realm then return end
    d.mains[c.realm] = key
    if A.Sync then A.Sync:Announce(false) end
    A:NamesChanged()
end

function Me:Forget(key)
    local d = self:Data()
    if key == self:CurrentKey() or not d.chars[key] then return end
    local realm = d.chars[key].realm
    d.chars[key] = nil
    if realm and d.mains[realm] == key then
        d.mains[realm] = nil
        if A.Sync and realm == GetRealmName() then A.Sync:Announce(false) end
    end
end

-------------------------------------------------------------------------------
-- The settings window
-------------------------------------------------------------------------------
local W = 520
local ROW_H = 30

local function Text(parent, template, x, y, width)
    local t = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    t:SetPoint("TOPLEFT", x, y)
    if width then t:SetWidth(width) end
    t:SetJustifyH("LEFT")
    return t
end
local function PanelButton(parent, label, width, action)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24); b:SetText(label); b:SetScript("OnClick", action)
    return b
end
-- A checkbox bound to a setting: get() reads it, set(on) writes it.
local function Check(parent, x, y, label, tooltip, get, set)
    local b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    b:SetSize(24, 24); b:SetPoint("TOPLEFT", x, y)
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("LEFT", b, "RIGHT", 2, 0); t:SetText(label)
    b:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); Me:Render(); A:NamesChanged() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(label, 1, 1, 1)
        GameTooltip:AddLine(tooltip, nil, nil, nil, true); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b.Get = get
    return b
end
local function Heading(parent, y, label)
    local t = Text(parent, "GameFontNormal", 18, y)
    t:SetText(label)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, .82, 0, .25); line:SetHeight(1)
    line:SetPoint("LEFT", t, "RIGHT", 8, 0); line:SetPoint("RIGHT", parent, "RIGHT", -18, 0)
    return t
end

function Me:Open()
    if self.window then self.window:Show(); self:Render(); return end
    local f = CreateFrame("Frame", "LAFWCommunitySettings", UIParent, "BasicFrameTemplateWithInset")
    self.window = f
    f:SetSize(W, 712); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f.TitleText:SetText("LAFW Community")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetScript("OnShow", function() Me:Render() end)
    tinsert(UISpecialFrames, "LAFWCommunitySettings")   -- Escape closes it

    local cfg = function() return A.BN:Settings() end
    Heading(f, -34, "Names in Blizzard Groups")
    f.checks = {
        Check(f, 16, -54, "Show character names instead of BattleTags",
            "Shows the character each member is playing, when it can be known: yours, your Battle.net friends', and members running LAFW Community.",
            function() return cfg().enabled end, function(on) cfg().enabled = on end),
        Check(f, 16, -80, "First names only",
            "\"Aldren\" instead of \"Aldren Brightwater\".",
            function() return cfg().firstOnly end, function(on) cfg().firstOnly = on end),
        Check(f, 16, -106, "Also show the BattleTag",
            "Adds the BattleTag after the character, e.g. \"Aldren Brightwater (Aldie)\".",
            function() return cfg().showTag end, function(on) cfg().showTag = on end),
        Check(f, 16, -132, "Show the minimap button",
            "You can always open this window with /lafw settings.",
            function() return not (A.db.minimap and A.db.minimap.hide) end,
            function(on) if A.Minimap then A.Minimap:SetShown(on) end end),
    }

    Heading(f, -168, "Community chat")
    f.clubLabel = Text(f, "GameFontHighlight", 20, -192, 330)
    f.clubLabel:SetWordWrap(false)
    local change = PanelButton(f, "Change", 90, function()
        -- Step to the next community you're in.
        local CC = A.CommunityChat
        local clubs, current = CC:Clubs(), CC:ClubId()
        if #clubs == 0 then return end
        local nextIndex = 1
        for i, c in ipairs(clubs) do if c.clubId == current then nextIndex = i % #clubs + 1 end end
        A.db.chatClubId = clubs[nextIndex].clubId
        CC:AddToGeneralTab()
        Me:Render()
    end)
    change:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -186)
    -- The community chat color: click the swatch for the game's color
    -- picker; Default goes back to the addon's color.
    local colorLabel = Text(f, "GameFontHighlight", 20, -222)
    colorLabel:SetText("Color")
    local swatch = CreateFrame("Button", nil, f)
    swatch:SetSize(20, 20); swatch:SetPoint("LEFT", colorLabel, "RIGHT", 10, 0)
    local border = swatch:CreateTexture(nil, "BACKGROUND"); border:SetAllPoints(); border:SetColorTexture(.75, .75, .75, 1)
    local fill = swatch:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1); fill:SetPoint("BOTTOMRIGHT", -1, 1); fill:SetColorTexture(1, 1, 1, 1)
    swatch.fill = fill
    f.swatch = swatch
    f.colorNote = Text(f, "GameFontHighlightSmall", 0, 0)
    f.colorNote:ClearAllPoints(); f.colorNote:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    f.colorNote:SetTextColor(.75, .75, .75)
    local function SetColor(r, g, b)
        A.db.chatColor = { r, g, b }
        A:ApplyCommunityColor(A.db.chatColor)
        Me:Render()
    end
    swatch:SetScript("OnClick", function()
        local c = A:CommunityColor()
        local before = { c[1], c[2], c[3] }
        local hadOwn = A.db.chatColor ~= nil
        local picker = ColorPickerFrame
        if not picker and C_AddOns and C_AddOns.LoadAddOn then
            pcall(C_AddOns.LoadAddOn, "Blizzard_ColorPicker")
            picker = ColorPickerFrame
        end
        if not picker then A:Message("The game's color picker isn't available."); return end
        local function Current() return picker:GetColorRGB() end
        local function Cancel()
            if hadOwn then SetColor(before[1], before[2], before[3])
            else A.db.chatColor = nil; A:ApplyCommunityColor(nil); Me:Render() end
        end
        if picker.SetupColorPickerAndShow then
            picker:SetupColorPickerAndShow({ r = c[1], g = c[2], b = c[3], hasOpacity = false,
                swatchFunc = function() SetColor(Current()) end, cancelFunc = Cancel })
        else
            picker.hasOpacity = false
            picker.func = function() SetColor(Current()) end
            picker.cancelFunc = Cancel
            picker.previousValues = before
            picker:SetColorRGB(c[1], c[2], c[3])
            ShowUIPanel(picker)
        end
        -- Our window sits on the same layer as the picker and would hide it.
        if picker.SetFrameStrata then picker:SetFrameStrata("FULLSCREEN_DIALOG") end
        if picker.Raise then picker:Raise() end
    end)
    swatch:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Community chat color", 1, 1, 1)
        GameTooltip:AddLine("Click to choose. You can also change it in Blizzard's chat settings"
            .. " (right-click a chat tab > Settings > Channels); the addon keeps whichever you set last.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    swatch:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.colorDefault = PanelButton(f, "Default", 90, function()
        A.db.chatColor = nil
        A:ApplyCommunityColor(nil)
        Me:Render()
    end)
    f.colorDefault:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -216)

    local chatHelp = Text(f, "GameFontHighlightSmall", 20, -246, W - 40)
    chatHelp:SetText("Type /l to talk in it, like /p for party. It's added to your General chat tab once;"
        .. " to remove it, right-click the tab > Settings > Channels.")
    chatHelp:SetTextColor(.75, .75, .75)

    Heading(f, -282, "Your main")
    local help = Text(f, "GameFontHighlightSmall", 18, -302, W - 36)
    help:SetText("Pick your main. Every other character on the same server shows as its alt: \"Alt - Main\"."
        .. " Each server has its own main. A character appears here once you log in on it with the addon.")
    help:SetTextColor(.75, .75, .75)

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -336); scroll:SetPoint("BOTTOMRIGHT", -32, 48)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(W - 50, 10); scroll:SetScrollChild(content)
    f.content, f.rows = content, {}

    local roster = PanelButton(f, "Open roster", 110, function() f:Hide(); A:Toggle() end)
    roster:SetPoint("BOTTOMLEFT", 16, 14)
    local close = PanelButton(f, "Close", 100, function() f:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -16, 14)
    self:Render()
end

function Me:Toggle()
    if self.window and self.window:IsShown() then self.window:Hide() else self:Open() end
end

function Me:Row(i)
    local f = self.window
    local r = f.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, f.content, "BackdropTemplate")
    r:SetSize(W - 50, ROW_H - 2)
    r:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    r.name = Text(r, "GameFontHighlight", 8, -8, 250)
    r.name:SetWordWrap(false)
    r.role = Text(r, "GameFontHighlightSmall", 262, -9, 50)
    r.main = PanelButton(r, "Set main", 84, function() end)
    r.main:SetPoint("LEFT", 314, 0)
    r.forget = PanelButton(r, "Forget", 64, function() end)
    r.forget:SetPoint("LEFT", 402, 0)
    r.forget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Remove from this list (it comes back next time you log in on it).", nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    r.forget:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.rows[i] = r
    return r
end

function Me:Render()
    local f = self.window
    if not f or not f:IsShown() then return end
    for _, b in ipairs(f.checks) do b:SetChecked(b.Get() and true or false) end
    local clubName = A.CommunityChat and A.CommunityChat:ClubName()
    f.clubLabel:SetText("Community: " .. (clubName and ("|cffffffff" .. clubName .. "|r") or "|cff9a9a9anone yet|r"))
    if A.CommunityColor then
        local c = A:CommunityColor()
        f.swatch.fill:SetColorTexture(c[1], c[2], c[3], 1)
        local own = A.db.chatColor ~= nil
        f.colorNote:SetText(own and "your color" or "default")
        f.colorDefault:SetEnabled(own)
    end
    local d = self:Data()
    local current = self:CurrentKey()
    -- Grouped by server, your current server first; main first in each.
    local byRealm, realms = {}, {}
    for key, c in pairs(d.chars) do
        local realm = c.realm or "?"
        if not byRealm[realm] then byRealm[realm] = {}; realms[#realms + 1] = realm end
        table.insert(byRealm[realm], key)
    end
    local here = GetRealmName()
    table.sort(realms, function(a, b)
        if a == here then return true elseif b == here then return false end
        return a < b
    end)
    local rows = {}
    for _, realm in ipairs(realms) do
        local keys, main = byRealm[realm], d.mains[realm]
        table.sort(keys, function(a, b)
            if a == main then return true elseif b == main then return false end
            return a < b
        end)
        if #realms > 1 then rows[#rows + 1] = { header = realm } end
        for _, key in ipairs(keys) do rows[#rows + 1] = { key = key, main = main } end
    end
    for _, r in ipairs(f.rows) do r:Hide() end
    for i, row in ipairs(rows) do
        local r = self:Row(i)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        if row.header then
            r:SetBackdropColor(0, 0, 0, 0)
            r.name:SetText(row.header); r.name:SetTextColor(1, .82, 0)
            r.role:SetText(""); r.main:Hide(); r.forget:Hide()
        else
            local key, c = row.key, d.chars[row.key]
            local isMain = key == row.main
            r:SetBackdropColor(1, 1, 1, isMain and .09 or (i % 2 == 0 and .035 or .015))
            local color = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
            r.name:SetText(c.name .. (key == current and "  |cff33cc80(now)|r" or ""))
            if color then r.name:SetTextColor(color.r, color.g, color.b) else r.name:SetTextColor(.92, .92, .92) end
            r.role:SetText(isMain and "|cffffd100Main|r" or (row.main and "|cff9a9a9aAlt|r" or ""))
            r.main:Show(); r.main:SetEnabled(not isMain)
            r.main:SetText(isMain and "Main" or "Set main")
            r.main:SetScript("OnClick", function() Me:SetMain(key); Me:Render() end)
            r.forget:SetShown(key ~= current)
            r.forget:SetScript("OnClick", function() Me:Forget(key); Me:Render() end)
        end
        r:Show()
    end
    f.content:SetHeight(math.max(10, #rows * ROW_H))
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("SKILL_LINES_CHANGED")
local pendingRecord
events:SetScript("OnEvent", function(_, event)
    if not A.db then return end
    if event == "PLAYER_LOGIN" then Me:Record(); return end
    -- Skill and level changes come in bursts: record once, then tell others.
    if pendingRecord then return end
    pendingRecord = true
    C_Timer.After(2, function()
        pendingRecord = nil
        local key = Me:CurrentKey()
        local before = Me:Data().chars[key] and Me:Data().chars[key].profs
        Me:Record()
        local after = Me:Data().chars[key] and Me:Data().chars[key].profs
        if before ~= after and A.Sync then A.Sync:Announce(false) end
    end)
end)
