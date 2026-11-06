-------------------------------------------------------------------------------
-- The roster: the LAFW tab in the Communities window (or its own window
-- with /lafw). One line per member: status, name, what they're playing
-- (when the game tells: you and your Battle.net friends), and their status.
-------------------------------------------------------------------------------
local _, A = ...
local function Text(parent, size, x, y, width)
    local t = parent:CreateFontString(nil, "OVERLAY")
    t:SetFont(STANDARD_TEXT_FONT, size, ""); t:SetPoint("TOPLEFT", x, y)
    if width then t:SetWidth(width) end
    t:SetJustifyH("LEFT"); t:SetTextColor(.92, .92, .92); t:SetWordWrap(false)
    return t
end
local function Button(parent, label, width, action)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22); b:SetText(label); b:SetScript("OnClick", action)
    return b
end

-- Status colors.
local COLORS = {
    online = { .2, 1, .4 },       -- online (in Forever, when known)
    elsewhere = { .35, .65, 1 },  -- the Battle.net app, or another game
    away = { 1, .82, 0 },
    busy = { 1, .35, .35 },
    offline = { .6, .6, .6 },
}
function A.StatusColor(row)
    local e = Enum and Enum.ClubMemberPresence or {}
    if not row.online then return COLORS.offline end
    if row.presence == e.Away then return COLORS.away end
    if row.presence == e.Busy then return COLORS.busy end
    if row.presence == e.OnlineMobile or row.where == "elsewhere" then return COLORS.elsewhere end
    return COLORS.online
end
-- The short status at the end of a line.
function A.StatusLabel(row)
    local e = Enum and Enum.ClubMemberPresence or {}
    if not row.online then return "Offline" end
    if row.presence == e.Away then return "Away" end
    if row.presence == e.Busy then return "Busy" end
    if row.presence == e.OnlineMobile then return "App" end
    if row.where == "elsewhere" then return "Other game" end
    if row.where == "forever" then return "In Forever" end
    return "Online"
end
local function Matches(row, query)
    if query == "" then return true end
    return (tostring(row.name) .. " " .. (row.detail or "") .. " " .. (row.role or "")):lower():find(query, 1, true) ~= nil
end

-- Right-click on a member: a small menu (Invite to group), greyed out with
-- the reason when they can't be invited from here.
function A:RowMenu(owner, row)
    local ok, why = self:CanInvite(row)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, function(_, root)
            root:CreateTitle(tostring(row.name or ""))
            local b = root:CreateButton(INVITE or "Invite to group", function() A:InviteRow(row) end)
            if not ok then
                b:SetEnabled(false)
                if why and b.SetTooltip then b:SetTooltip(function(tip) GameTooltip_SetTitle(tip, why) end) end
            end
        end)
    elseif ok then
        self:InviteRow(row)
    elseif why then
        self:Message(why)
    end
end

local ROW_H = 22
local NAME_X, DETAIL_X = 20, 230

local function Tooltip(card)
    local row = card.row
    if not row then return end
    GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
    GameTooltip:SetText(tostring(row.name), 1, 1, 1)
    local c = A.StatusColor(row)
    local status = row.status or "Unknown"
    if row.online and row.where == "forever" then status = status .. ", in Forever"
    elseif row.online and row.where == "elsewhere" then status = status .. ", in another game" end
    GameTooltip:AddLine(status, c[1], c[2], c[3])
    if row.role then GameTooltip:AddLine(row.role, 1, .82, 0) end
    if row.detail and row.detail ~= "" then GameTooltip:AddLine("Playing: " .. row.detail, .9, .9, .9, true) end
    if row.realm then GameTooltip:AddLine(row.realm .. (row.faction and (", " .. row.faction) or ""), .65, .65, .65) end
    if row.battleTag and not row.named and not row.isSelf then
        GameTooltip:AddLine("No name set: they can set one in their member note.", .65, .65, .65, true)
    elseif row.isSelf and not row.named then
        GameTooltip:AddLine("Others see your BattleTag: set your name in the settings (minimap button).", 1, .82, 0, true)
    end
    if row.battleTag and A.BN:Settings().showTag ~= true then GameTooltip:AddLine("BattleTag: " .. row.battleTag, .65, .65, .65) end
    if A:CanInvite(row) then GameTooltip:AddLine("Right-click to invite", .5, .8, 1) end
    GameTooltip:Show()
end

local function Card(f, i)
    local card = CreateFrame("Frame", nil, f.content, "BackdropTemplate")
    card:SetHeight(ROW_H)
    card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    local base = i % 2 == 0 and .055 or .015
    card:SetBackdropColor(.7, .7, .7, base)
    card.dot = card:CreateTexture(nil, "ARTWORK"); card.dot:SetSize(7, 7); card.dot:SetPoint("LEFT", 8, 0)
    card.dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    card.name = Text(card, 12, NAME_X, -5)
    card.tag = Text(card, 10, 0, 0); card.tag:ClearAllPoints(); card.tag:SetPoint("LEFT", card.name, "RIGHT", 5, 0)
    card.detail = Text(card, 10, DETAIL_X, -6); card.detail:SetTextColor(.7, .7, .7)
    card.status = Text(card, 10, 0, 0, 80); card.status:ClearAllPoints(); card.status:SetPoint("RIGHT", -8, 0)
    card.status:SetJustifyH("RIGHT")
    card:EnableMouse(true)
    card:SetScript("OnMouseUp", function(self, button) if button == "RightButton" and self.row then A:RowMenu(self, self.row) end end)
    card:SetScript("OnEnter", function(self) self:SetBackdropColor(.7, .7, .7, .12); Tooltip(self) end)
    card:SetScript("OnLeave", function(self) self:SetBackdropColor(.7, .7, .7, base); GameTooltip:Hide() end)
    return card
end

function A:Draw()
    local f = self.window
    if not f then return end
    local query = f.search:GetText():lower()
    local shown = {}
    for _, row in ipairs(self.rows) do if Matches(row, query) then shown[#shown + 1] = row end end
    local width = math.max(300, f.content:GetWidth())
    for i, row in ipairs(shown) do
        local card = f.cards[i] or Card(f, i)
        f.cards[i] = card
        card.row = row
        card:ClearAllPoints(); card:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + 1)); card:SetWidth(width)
        local c = A.StatusColor(row)
        card.dot:SetVertexColor(c[1], c[2], c[3])
        card.name:SetWidth(0); card.name:SetText(tostring(row.name))
        if card.name:GetStringWidth() > DETAIL_X - NAME_X - 70 then card.name:SetWidth(DETAIL_X - NAME_X - 70) end
        if row.online then card.name:SetTextColor(.95, .95, .95) else card.name:SetTextColor(.6, .6, .6) end
        local tag = row.role and ("|cffffd100" .. row.role .. "|r") or ""
        if row.battleTag and not row.named and not row.isSelf and row.source ~= "friend" then tag = tag .. (tag ~= "" and " " or "") .. "|cff808080no name|r" end
        card.tag:SetText(tag)
        card.detail:SetWidth(math.max(60, width - DETAIL_X - 95)); card.detail:SetText(row.detail or "")
        card.status:SetText(A.StatusLabel(row)); card.status:SetTextColor(c[1], c[2], c[3])
        card:Show()
    end
    for i = #shown + 1, #f.cards do f.cards[i]:Hide(); f.cards[i].row = nil end
    f.content:SetHeight(math.max(10, #shown * (ROW_H + 1)))
    f.empty:SetShown(#shown == 0)
    f.statusText:SetText(self.status or "")
    if f.heading then
        local name = "LAFW Community"
        for _, club in ipairs(self:Communities()) do if club.clubId == self.rosterClub then name = club.name or name end end
        f.heading:SetText(self.embedded and "" or name)
    end
end

function A:BuildWindow()
    local f
    if self.embedded then
        f = CreateFrame("Frame", nil, CommunitiesFrame, "BackdropTemplate")
        f:SetSize(590, 360)
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        f:SetBackdropColor(.095, .095, .095, 1); f:SetBackdropBorderColor(.20, .20, .20, 1)
        f:EnableMouse(true)
    else
        f = CreateFrame("Frame", "LAFWCommunityRoster", UIParent, "BasicFrameTemplateWithInset")
        f.TitleText:SetText("LAFW Community"); f:SetSize(620, 520); f:SetPoint("CENTER")
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        tinsert(UISpecialFrames, "LAFWCommunityRoster")
        f.heading = Text(f, 14, 14, -30, 300)
    end
    self.window = f
    local top = self.embedded and -8 or -50
    f.search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.search:SetPoint("TOPLEFT", 18, top); f.search:SetSize(220, 22); f.search:SetAutoFocus(false)
    local placeholder = Text(f.search, 11, 2, -5, 200); placeholder:SetText("Search names..."); placeholder:SetTextColor(.55, .55, .55)
    f.search:SetScript("OnTextChanged", function(box) placeholder:SetShown(box:GetText() == ""); A:Draw() end)
    f.search:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    local settings = Button(f, "Settings", 90, function() A.Settings:Open() end)
    settings:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, top + 1)
    local refresh = Button(f, "Refresh", 80, function() A:Refresh(); A:Draw() end)
    refresh:SetPoint("RIGHT", settings, "LEFT", -6, 0)
    f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", 10, top - 30); f.scroll:SetPoint("BOTTOMRIGHT", -30, 30)
    f.content = CreateFrame("Frame", nil, f.scroll); f.content:SetSize(540, 10); f.scroll:SetScrollChild(f.content)
    f.scroll:SetScript("OnSizeChanged", function(s, w) f.content:SetWidth(w) end)
    f.cards = {}
    f.empty = Text(f, 12, 25, top - 50, 500); f.empty:SetText("No one matches.")
    f.statusText = Text(f, 10, 0, 0, 400); f.statusText:ClearAllPoints(); f.statusText:SetPoint("BOTTOMLEFT", 14, 10)
    f.statusText:SetTextColor(.65, .65, .65)
    local legend = Text(f, 10, 0, 0, 300); legend:ClearAllPoints(); legend:SetPoint("BOTTOMRIGHT", -14, 10); legend:SetJustifyH("RIGHT")
    legend:SetText("|cff33ff66online|r  |cff59a6ffapp / other game|r  |cffffd100away|r  |cffff5959busy|r")
    self:Draw()
end

function A:Toggle()
    if not self.window then self:Refresh(); self:BuildWindow()
    elseif self.window:IsShown() then self.window:Hide()
    else self:Refresh(); self:Draw(); self.window:Show() end
end
