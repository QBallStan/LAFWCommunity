-------------------------------------------------------------------------------
-- Minimap button: left-click opens the settings window, right-click the
-- roster, hover for who's online. Drag it around the minimap; its spot is
-- saved.
-------------------------------------------------------------------------------
local _, A = ...
local M = {}
A.Minimap = M

local ICON = "Interface\\Icons\\INV_Misc_Book_09"   -- the community tab's icon

local function Settings()
    A.db.minimap = A.db.minimap or { angle = 200, hide = false }
    return A.db.minimap
end

-- Place the button at `angle` (degrees) on the minimap's edge, round or
-- square.
local function Place(b, angle)
    local map = Minimap
    local rad = math.rad(angle)
    local x, y = math.cos(rad), math.sin(rad)
    local w, h = map:GetWidth() / 2 + 5, map:GetHeight() / 2 + 5
    local square = type(GetMinimapShape) == "function" and GetMinimapShape() == "SQUARE"
    if square then
        -- Push the point out to the square's edge.
        local m = math.max(math.abs(x), math.abs(y))
        if m > 0 then x, y = x / m, y / m end
        w, h = w + 5, h + 5
    end
    b:ClearAllPoints()
    b:SetPoint("CENTER", map, "CENTER", x * w, y * h)
end

function M:Create()
    if self.button or not Minimap then return end
    local b = CreateFrame("Button", "LAFWCommunityMinimapButton", Minimap)
    self.button = b
    b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20); bg:SetPoint("CENTER", 0, 1)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON); icon:SetSize(18, 18); icon:SetPoint("CENTER", 0, 1)
    icon:SetTexCoord(.07, .93, .07, .93)
    b.icon = icon
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(52, 52); border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then A:Toggle() else A.Settings:Toggle() end
    end)
    b:SetScript("OnMouseDown", function() icon:SetPoint("CENTER", 1, 0) end)
    b:SetScript("OnMouseUp", function() icon:SetPoint("CENTER", 0, 1) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("LAFW Community")
        -- Who's online in the group.
        local online = A.Presence and A.Presence:Online() or {}
        GameTooltip:AddLine(#online .. " online", .2, 1, .4)
        for i, m in ipairs(online) do
            if i > 25 then GameTooltip:AddLine(("and %d more"):format(#online - 25), .65, .65, .65); break end
            local c = A.StatusColor and A.StatusColor({ online = true, presence = m.presence }) or { 1, 1, 1 }
            GameTooltip:AddDoubleLine(tostring(m.name), m.status ~= "Online" and m.status or "", 1, 1, 1, c[1], c[2], c[3])
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffd100Left-click|r settings", 1, 1, 1)
        GameTooltip:AddLine("|cffffd100Right-click|r roster", 1, 1, 1)
        GameTooltip:AddLine("|cffffd100Drag|r to move", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            local angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
            Settings().angle = angle
            Place(self, angle)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    Place(b, Settings().angle)
    b:SetShown(not Settings().hide)
end

function M:SetShown(on)
    Settings().hide = not on
    if self.button then self.button:SetShown(on) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function() if A.db then M:Create() end end)
