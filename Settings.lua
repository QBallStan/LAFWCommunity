-------------------------------------------------------------------------------
-- The settings window (minimap button, /lafw settings): names, alerts, the
-- community chat, and your display name in the group.
--
-- Your display name is your member note in the group. Only Blizzard's own
-- menu can set it (the game blocks addons from it), so the window prepares
-- the text and shows how to paste it.
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
-- Your display name
-------------------------------------------------------------------------------
-- The group your name applies to: the community chat's group, when it's a
-- Blizzard Group.
function S:GroupId()
    local id = A.CommunityChat and A.CommunityChat:ClubId()
    if id and A.BN:IsBattleNetClub(id) then return id end
    for _, club in ipairs(A:Communities()) do
        if A.BN:IsBattleNetClub(club.clubId) then return club.clubId end
    end
end

-- Your member note in that group, as it is now.
function S:CurrentNote()
    local id = self:GroupId()
    if not id or not (C_Club and C_Club.GetMemberInfoForSelf) then return nil end
    local ok, me = pcall(C_Club.GetMemberInfoForSelf, id)
    if ok and type(me) == "table" and type(me.memberNote) == "string" and me.memberNote ~= "" then return me.memberNote end
end

-- What to offer in the box: your note if you have one, else your character.
function S:Suggested()
    return A.BN.ParseNote(self:CurrentNote()) or A.BN.PlayerName() or UnitName("player")
end

-------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------
function S:Open()
    if self.window then self.window:Show(); self:Render(); return end
    local f = CreateFrame("Frame", "LAFWCommunitySettings", UIParent, "BasicFrameTemplateWithInset")
    self.window = f
    f:SetSize(W, 520); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f.TitleText:SetText("LAFW Community")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetScript("OnShow", function() S:Render() end)
    tinsert(UISpecialFrames, "LAFWCommunitySettings")   -- Escape closes it

    -- Your name
    Heading(f, -34, "Your name in the group")
    f.noteState = Text(f, "GameFontHighlight", 20, -58, W - 40)
    f.noteState:SetWordWrap(false)
    local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    box:SetSize(260, 22); box:SetPoint("TOPLEFT", 26, -80); box:SetAutoFocus(false); box:SetMaxLetters(40)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnEnterPressed", function(self) self:HighlightText() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.nameBox = box
    local select = PanelButton(f, "Select to copy", 120, function() box:SetFocus(); box:HighlightText() end)
    select:SetPoint("LEFT", box, "RIGHT", 10, 0)
    local nameHelp = Text(f, "GameFontHighlightSmall", 20, -108, W - 40)
    nameHelp:SetText("Everyone in the group sees you by the name in your member note, whatever their server or faction."
        .. " Type the name you want, press Ctrl+C, then in the Communities window right-click your own name > Set Note"
        .. " and paste it (Ctrl+V). The game doesn't let addons set it for you.")
    nameHelp:SetTextColor(.75, .75, .75)

    -- Names and alerts
    local cfg = function() return A.BN:Settings() end
    Heading(f, -170, "Display")
    f.checks = {
        Check(f, 16, -190, "Show names instead of BattleTags",
            "Members show by the name in their member note; Battle.net friends without one by the character they're playing.",
            function() return cfg().enabled end, function(on) cfg().enabled = on end),
        Check(f, 16, -216, "Also show the BattleTag",
            "Adds the BattleTag after the name, e.g. \"Aldren (Aldie)\".",
            function() return cfg().showTag end, function(on) cfg().showTag = on end),
        Check(f, 16, -242, "First names only for characters",
            "\"Aldren\" instead of \"Aldren Brightwater\" when a friend (or you) shows by character. Names from notes show as written.",
            function() return cfg().firstOnly end, function(on) cfg().firstOnly = on end),
        Check(f, 16, -268, "Tell me when members come online or go offline",
            "A line in chat, like guild members' login notices.",
            function() return A.db.alerts ~= false end, function(on) A.db.alerts = on end),
        Check(f, 16, -294, "Show the minimap button",
            "You can always open this window with /lafw settings.",
            function() return not (A.db.minimap and A.db.minimap.hide) end,
            function(on) if A.Minimap then A.Minimap:SetShown(on) end end),
    }

    -- Community chat
    Heading(f, -330, "Community chat")
    f.clubLabel = Text(f, "GameFontHighlight", 20, -354, 330)
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
        if A.Presence then A.Presence:Subscribe() end
        S:Render()
    end)
    change:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -348)
    -- The community chat color: click the swatch for the game's color
    -- picker; Default goes back to the addon's color.
    local colorLabel = Text(f, "GameFontHighlight", 20, -384)
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
        S:Render()
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
            else A.db.chatColor = nil; A:ApplyCommunityColor(nil); S:Render() end
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
        S:Render()
    end)
    f.colorDefault:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -378)
    local chatHelp = Text(f, "GameFontHighlightSmall", 20, -410, W - 40)
    chatHelp:SetText("Type /l to talk in it, like /p for party. It's added to your General chat tab once;"
        .. " to remove it, right-click the tab > Settings > Channels.")
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
    local note = A.BN.ParseNote(self:CurrentNote())
    if not self:GroupId() then
        f.noteState:SetText("|cff9a9a9aYou're not in a Blizzard Group.|r")
    elseif note then
        f.noteState:SetText("Others see you as |cff33cc80" .. note .. "|r")
    else
        f.noteState:SetText("|cffffd100No name set yet:|r others see your BattleTag.")
    end
    if not f.nameBox:HasFocus() then f.nameBox:SetText(self:Suggested() or "") end
    local clubName = A.CommunityChat and A.CommunityChat:ClubName()
    f.clubLabel:SetText("Community: " .. (clubName and ("|cffffffff" .. clubName .. "|r") or "|cff9a9a9anone yet|r"))
    if A.CommunityColor then
        local c = A:CommunityColor()
        f.swatch.fill:SetColorTexture(c[1], c[2], c[3], 1)
        local own = A.db.chatColor ~= nil
        f.colorNote:SetText(own and "your color" or "default")
        f.colorDefault:SetEnabled(own)
    end
end
