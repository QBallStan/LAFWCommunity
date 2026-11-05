local _, A = ...
function A:MountAdvancedRoster()
    local host=CommunitiesFrame
    if not self.embedded or not host or not self.window then return end
    local f=self.window
    f:SetParent(host); f:ClearAllPoints(); f:SetScale(1)
    f:SetPoint("TOPLEFT",host,"TOPLEFT",197,-28)
    f:SetPoint("BOTTOMRIGHT",host,"BOTTOMRIGHT",-25,2)
    -- Above Blizzard's (see-through) controls, so it takes every click.
    f:SetFrameLevel(host:GetFrameLevel()+40)
    f:SetMovable(false)
    local width=math.max(300,f:GetWidth()-40)
    f.content:SetWidth(width)
    for _,card in ipairs(f.cards) do
        card:SetWidth(width)
        card.arrow:ClearAllPoints(); card.arrow:SetPoint("TOPRIGHT",card,"TOPRIGHT",-12,-6)
    end
end
function A:InstallCommunityIntegration()
    local host=CommunitiesFrame
    if not host or self.communityButton or not host.RosterTab then return end
    local button=CreateFrame("CheckButton",nil,host)
    self.communityButton=button
    button:SetSize(host.RosterTab:GetSize())
    button:SetPoint("TOPLEFT",host.RosterTab,"BOTTOMLEFT",0,-20)
    button:SetFrameLevel(host:GetFrameLevel()+30)
    local nativeHighlight=host.RosterTab:GetHighlightTexture()
    local nativeChecked=host.RosterTab:GetCheckedTexture()
    local nativePushed=host.RosterTab:GetPushedTexture()
    -- Copy native tab regions with their own dimensions and anchors, not stretched to the button.
    for _,region in ipairs({host.RosterTab:GetRegions()}) do
        if region:GetObjectType()=="Texture" and region~=nativeHighlight and region~=nativeChecked and region~=nativePushed then
            local layer,sublevel=region:GetDrawLayer()
            local copy=button:CreateTexture(nil,layer,nil,sublevel)
            local atlas=region:GetAtlas()
            if atlas then copy:SetAtlas(atlas) else copy:SetTexture(region:GetTexture()) end
            copy:SetTexCoord(region:GetTexCoord()); copy:SetSize(region:GetSize())
            copy:SetBlendMode(region:GetBlendMode()); copy:SetAlpha(region:GetAlpha())
            for i=1,region:GetNumPoints() do
                local point,relative,relativePoint,x,y=region:GetPoint(i)
                copy:SetPoint(point,button,relativePoint,x,y)
            end
            copy:SetShown(region:IsShown())
        end
    end
    local icon=button:CreateTexture(nil,"OVERLAY",nil,7)
    icon:SetSize(26,26); icon:SetPoint("CENTER",0,0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    -- Keep the icon above all hover and selection artwork.
    local iconLayer=CreateFrame("Frame",nil,button)
    iconLayer:SetAllPoints(button); iconLayer:SetFrameLevel(button:GetFrameLevel()+2)
    icon:Hide()
    local foreground=iconLayer:CreateTexture(nil,"ARTWORK")
    foreground:SetSize(26,26); foreground:SetPoint("CENTER")
    foreground:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    button:GetHighlightTexture():SetBlendMode("ADD")
    button:GetHighlightTexture():SetAlpha(.2)
    button:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
    button:GetCheckedTexture():SetBlendMode("ADD")
    button:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetText("Advanced Roster"); GameTooltip:Show()
    end)
    button:SetScript("OnLeave",function() GameTooltip:Hide() end)
    local function Leave()
        local wasEmbedded=A.embedded
        A.embedded=false
        button:SetChecked(false)
        if wasEmbedded and A.window then A.window:Hide() end
        if A.altEditor then A.altEditor:Hide() end
        if A.hiddenNative then
            -- Fade Blizzard's controls back in. They were only made see-through,
            -- never hidden: showing or hiding them (or switching the window's
            -- view) from addon code taints the Communities window, and the game
            -- then blocks Blizzard's own actions there, such as Set Note.
            for frame, alpha in pairs(A.hiddenNative) do frame:SetAlpha(alpha) end
            A.hiddenNative=nil
        end
    end
    local function Update()
        local id=host:GetSelectedClubId()
        button:SetShown(id~=nil)
        if A.embedded and id then
            A.db.clubId=id; A:Refresh(); A:Draw(); A:MountAdvancedRoster()
        elseif not id then Leave() end
    end
    button:SetScript("OnClick",function()
        if InCombatLockdown() then A:Message("Open Advanced Roster after combat."); return end
        local id=host:GetSelectedClubId()
        if not id then return end
        A.db.clubId=id; A:Refresh()
        if A.window then A.window:Hide() end
        Leave()
        A.hiddenNative={}
        for _,key in ipairs({"MemberList","Chat","ChatEditBox","StreamDropdown","CommunitiesListDropdown","CommunityMemberListDropdown","GuildMemberListDropdown","VoiceChatHeadset","CommunitiesCalendarButton","CommunitiesControlFrame","InviteButton","ChatChannelDropdown","ChatChannelDropdownButton","StreamOptionsDropdown","AddToChatWindowDropdown"}) do
            local frame=host[key]
            if frame and frame.SetAlpha and not A.hiddenNative[frame] then A.hiddenNative[frame]=frame:GetAlpha(); frame:SetAlpha(0) end
        end
        -- Hide native header controls, including controls whose names differ by client build.
        local left,top=host:GetLeft(),host:GetTop()
        for _,child in ipairs({host:GetChildren()}) do
            if child~=button and child~=A.window and child:IsShown() and child:GetLeft() and child:GetTop()
                and left and top and child:GetLeft()>left+190 and child:GetLeft()<left+host:GetWidth()-30
                and child:GetTop()>top-85 and child:GetTop()<top-25 and child:GetHeight()<70 then
                if not A.hiddenNative[child] then A.hiddenNative[child]=child:GetAlpha(); child:SetAlpha(0) end
            end
        end
        button:SetChecked(true)
        if host.ChatTab then host.ChatTab:SetChecked(false) end
        host.RosterTab:SetChecked(false)
        A.embedded=true; A:BuildWindow(); A:MountAdvancedRoster(); A.window:Show()
    end)
    if host.ChatTab then host.ChatTab:HookScript("OnClick",Leave) end
    host.RosterTab:HookScript("OnClick",Leave)
    host:HookScript("OnHide",Leave)
    host:HookScript("OnShow",Update)
    host:HookScript("OnSizeChanged",function() A:MountAdvancedRoster() end)
    if host.UpdateSelectedClubInfo then hooksecurefunc(host,"UpdateSelectedClubInfo",Update) end
    if host.UpdateCommunitiesTabs then hooksecurefunc(host,"UpdateCommunitiesTabs",Update) end
    hooksecurefunc(A,"BuildWindow",function() A:MountAdvancedRoster() end)
    local standalone=A.Toggle
    A.Toggle=function(self)
        if self.embedded or (self.window and self.window:GetParent()~=UIParent) then
            Leave()
            if self.window then self.window:Hide() end
            self:Refresh(); self:BuildWindow(); return
        end
        standalone(self)
    end
    Update()
end
local loader=CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED"); loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent",function() if A.db then A:InstallCommunityIntegration() end end)
