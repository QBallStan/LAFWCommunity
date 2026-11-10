-------------------------------------------------------------------------------
-- The settings window (minimap button, /lafw settings): names, alerts and
-- the community chat.
-------------------------------------------------------------------------------
local _, A = ...
local S = {}
A.Settings = S

local W = 520

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
    b:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); S:Render(); A:NamesChanged() end)
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

-------------------------------------------------------------------------------
-- The group
-------------------------------------------------------------------------------
-- The group the addon follows: the community chat's group, when it's a
-- Blizzard Group.
function S:GroupId()
    local id = A.CommunityChat and A.CommunityChat:ClubId()
    if id and A.BN:IsBattleNetClub(id) then return id end
    for _, club in ipairs(A:Communities()) do
        if A.BN:IsBattleNetClub(club.clubId) then return club.clubId end
    end
end

-------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------
function S:Open()
    if self.window then self.window:Show(); self:Render(); return end
    local f = CreateFrame("Frame", "LAFWCommunitySettings", UIParent, "BasicFrameTemplateWithInset")
    self.window = f
    f:SetSize(W, 330); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f.TitleText:SetText("LAFW Community")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetScript("OnShow", function() S:Render() end)
    tinsert(UISpecialFrames, "LAFWCommunitySettings")   -- Escape closes it

    -- Names and alerts
    local cfg = function() return A.BN:Settings() end
    Heading(f, -34, "Display")
    f.checks = {
        Check(f, 16, -54, "Show names instead of BattleTags",
            "Members show by the character they're playing; offline members by the last character you saw them on.",
            function() return cfg().enabled end, function(on) cfg().enabled = on end),
        Check(f, 16, -80, "Also show the BattleTag",
            "Adds the BattleTag after the name, e.g. \"Aldren (Aldie)\".",
            function() return cfg().showTag end, function(on) cfg().showTag = on end),
        Check(f, 16, -106, "First names only",
            "\"Aldren\" instead of \"Aldren Brightwater\".",
            function() return cfg().firstOnly end, function(on) cfg().firstOnly = on end),
        Check(f, 16, -132, "Tell me when members come online or go offline",
            "A line in chat, like guild members' login notices.",
            function() return A.db.alerts ~= false end, function(on) A.db.alerts = on end),
        Check(f, 16, -158, "Show the minimap button",
            "You can always open this window with /lafw settings.",
            function() return not (A.db.minimap and A.db.minimap.hide) end,
            function(on) if A.Minimap then A.Minimap:SetShown(on) end end),
    }

    -- The community the addon follows
    Heading(f, -194, "Community")
    f.clubLabel = Text(f, "GameFontHighlight", 20, -218, 330)
    f.clubLabel:SetWordWrap(false)
    local change = PanelButton(f, "Change", 90, function()
        -- Step to the next community you're in.
        local CC = A.CommunityChat
        local clubs, current = CC:Clubs(), CC:ClubId()
        if #clubs == 0 then return end
        local nextIndex = 1
        for i, c in ipairs(clubs) do if c.clubId == current then nextIndex = i % #clubs + 1 end end
        A.db.chatClubId = clubs[nextIndex].clubId
        if A.Presence then A.Presence:Subscribe() end
        S:Render()
    end)
    change:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -212)
    local chatHelp = Text(f, "GameFontHighlightSmall", 20, -244, W - 40)
    chatHelp:SetText("The Blizzard Group the addon follows: its names, roster and login alerts.")
    chatHelp:SetTextColor(.75, .75, .75)

    local roster = PanelButton(f, "Open roster", 110, function() f:Hide(); A:Toggle() end)
    roster:SetPoint("BOTTOMLEFT", 16, 14)
    local close = PanelButton(f, "Close", 100, function() f:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -16, 14)
    self:Render()
end

function S:Toggle()
    if self.window and self.window:IsShown() then self.window:Hide() else self:Open() end
end

function S:Render()
    local f = self.window
    if not f or not f:IsShown() then return end
    for _, b in ipairs(f.checks) do b:SetChecked(b.Get() and true or false) end
    local clubName = A.CommunityChat and A.CommunityChat:ClubName()
    f.clubLabel:SetText("Community: " .. (clubName and ("|cffffffff" .. clubName .. "|r") or "|cff9a9a9anone yet|r"))
end
