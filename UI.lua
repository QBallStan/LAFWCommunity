local _, A = ...
local function Text(parent, size, x, y, width)
    local t = parent:CreateFontString(nil, "OVERLAY")
    t:SetFont(STANDARD_TEXT_FONT, size, ""); t:SetPoint("TOPLEFT", x, y)
    t:SetWidth(width); t:SetJustifyH("LEFT"); t:SetTextColor(.92,.92,.92)
    return t
end
local function Panel(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1})
    f:SetBackdropColor(.095,.095,.095,1); f:SetBackdropBorderColor(.20,.20,.20,1)
    return f
end
-- Capsule built from a solid center and circular end caps.
local function FactionIcon(parent)
    local f=CreateFrame("Frame",nil,parent)
    f:SetSize(18,18)
    f.icon=f:CreateTexture(nil,"ARTWORK"); f.icon:SetAllPoints()
    function f:SetFaction(faction)
        self.faction=faction
        local known=faction=="Alliance" or faction=="Horde"
        self.icon:SetShown(known)
        if known then self.icon:SetAtlas(faction=="Horde" and "communities-icon-faction-horde" or "communities-icon-faction-alliance") end
    end
    f:EnableMouse(true)
    f:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetText(self.faction or "Unknown faction"); GameTooltip:Show()
    end)
    f:SetScript("OnLeave",function() GameTooltip:Hide() end)
    return f
end
local function Button(parent, label, x, y, width, action, modern)
    local b = CreateFrame("Button", nil, parent, modern and "BackdropTemplate" or "UIPanelButtonTemplate")
    b:SetSize(width,26); b:SetPoint("TOPLEFT",x,y)
    if modern then
        b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); b:SetBackdropColor(.15,.15,.15,1)
        b.label=Text(b,12,8,-7,width-16); b.label:SetJustifyH("CENTER")
        b:SetScript("OnEnter",function(self) self:SetBackdropColor(.23,.23,.23,1) end)
        b:SetScript("OnLeave",function(self) self:SetBackdropColor(.15,.15,.15,1) end)
        b.label:SetText(label)
    else b:SetText(label) end
    b:SetScript("OnClick",action)
    return b
end
-- A name and its small grey "(alt)" / "(main)" tag, kept inside `room`
-- pixels: a long name is cut short ("...") rather than running into the
-- next column.
local function NameWithTag(parent, fs, tagFS, name, tag, room)
    fs:SetWordWrap(false); fs:SetWidth(0); fs:SetText(name)
    tagFS:SetText(tag or ""); tagFS:SetShown(tag ~= nil)
    local tagW = tag and (tagFS:GetStringWidth() + 3) or 0
    local maxW = room - tagW
    if fs:GetStringWidth() > maxW then fs:SetWidth(maxW) end
    tagFS:ClearAllPoints(); tagFS:SetPoint("LEFT", fs, "RIGHT", 3, 0)
end
local function TagFor(role) return role == "alt" and "(alt)" or (role == "main" and "(main)" or nil) end
A.NameWithTag, A.TagFor = NameWithTag, TagFor

-- Columns: level 4, name 60 (alt lines 70), faction 195, Main/Alt 222, class
-- 260 up to the "+" at the right.
local MAIN_X, MAIN_W, DETAIL_X = 222, 32, 260
local MAIN_LABEL, ALT_LABEL = "|cffffd100Main|r", "|cff9a9a9aAlt|r"
-- What the Main column says for a member row: "Main" on their main, "Alt"
-- on an alt (whose main is in the tooltip), nothing when it isn't known.
local function MainColumn(row, display)
    if row.role == "alt" then return ALT_LABEL end
    if row.role == "main" then return MAIN_LABEL end
    if display ~= row then return ALT_LABEL end              -- character community: on a linked alt
    if not row.bnAlts and row.alts and #row.alts > 0 then return MAIN_LABEL end
    return ""
end
-- An expanded line: the member's main, or one of their alts.
local function LineColumn(row, alt)
    if alt == row or alt.role == "main" then return MAIN_LABEL end
    return ALT_LABEL
end
A.MainColumn, A.LineColumn = MainColumn, LineColumn
local function OneLine(fs, text, width)
    fs:SetWordWrap(false); fs:SetWidth(width); fs:SetText(text)
end

-- Status colors: online in Forever (green), online elsewhere (blue: another
-- game, another WoW, the Battle.net app), offline (grey).
local STATUS = { online = { .2, 1, .4 }, elsewhere = { .35, .65, 1 }, offline = { .6, .6, .6 } }
local function Status(r)
    if not r.online then return STATUS.offline end
    if r.elsewhere then return STATUS.elsewhere end
    return STATUS.online
end
A.StatusColor = Status

-- Right-click on a member: a small menu (Invite to group). Greyed out, with
-- the reason, when they can't be invited from here.
function A:RowMenu(owner,row)
    local ok,why=self:CanInvite(row)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner,function(_,root)
            root:CreateTitle(row.name or "")
            local b=root:CreateButton(INVITE or "Invite to group",function() A:InviteRow(row) end)
            if not ok then
                b:SetEnabled(false)
                if why and b.SetTooltip then
                    b:SetTooltip(function(tip) GameTooltip_SetTitle(tip,why) end)
                end
            end
        end)
    elseif ok then
        self:InviteRow(row)          -- no menu system: invite straight away
    elseif why then
        self:Message(why)
    end
end

function A:Draw()
    local f=self.window
    if not f then return end
    local query=f.search:GetText():lower()
    self.expanded=self.expanded or {}
    local links=self:Links()
    local byId={}
    for _,row in ipairs(self.rows) do byId[row.memberId]=row end
    local filtered,online={},0
    for _,row in ipairs(self.rows) do
        if not (links[row.memberId] and byId[links[row.memberId]]) then
            row.alts={}; row.groupOnline=row.online; row.activeAlt=nil
            local matches=(row.name.." "..(row.mainName or "").." "..(row.class or "")..(row.activeAlt and "  |cff33cc80Online: "..row.activeAlt.."|r" or "")):lower():find(query,1,true)
            local factionMatch=self.faction=="All" or row.faction==self.faction
            for altId,mainId in pairs(links) do
                local alt=byId[altId]
                if mainId==row.memberId and alt then
                    row.alts[#row.alts+1]=alt
                    matches=matches or (alt.name.." "..(alt.class or "")):lower():find(query,1,true)
                    factionMatch=factionMatch or alt.faction==self.faction
                    if alt.online then row.groupOnline=true; row.activeAlt=alt.name end
                end
            end
            -- A Blizzard Group member's other characters, from their addon.
            for _,alt in ipairs(row.bnAlts or {}) do
                row.alts[#row.alts+1]=alt
                matches=matches or (alt.name.." "..(alt.class or "")):lower():find(query,1,true)
            end
            if not row.bnAlts then table.sort(row.alts,function(a,b) return a.name<b.name end) end
            if row.groupOnline then online=online+1 end
            if matches and factionMatch then filtered[#filtered+1]=row end
        end
    end
    self.offset=math.min(self.offset or 0,math.max(0,#filtered-#f.cards))
    local y=0
    for i,card in ipairs(f.cards) do
        local row=filtered[i+self.offset]
        card:SetShown(row~=nil)
        if row then
            card.row=row
            card:ClearAllPoints(); card:SetPoint("TOPLEFT",f.content,"TOPLEFT",0,-y)
            local alts=row.alts or {}
            local expanded=self.expanded[row.memberId]
            local height=expanded and ( #alts>0 and 28+#alts*25 or 48) or 24
            card:SetHeight(height); y=y+height+1
            local display=row
            if not row.online then
                for _,alt in ipairs(alts) do if alt.online then display=alt; break end end
            end
            card.name:ClearAllPoints(); card.name:SetPoint("TOPLEFT",card,"TOPLEFT",60,-6)
            -- 60 to the faction icon at 195, less a little gap.
            NameWithTag(card,card.name,card.role,display.name,nil,130)
            card.name:SetTextColor(unpack(Status(display)))
            card.level:SetText("Lvl "..(display.level or "?"))
            card.name:SetFont(STANDARD_TEXT_FONT,11,"")
            card.mainLabel=card.mainLabel or Text(card,11,0,0,240)
            card.mainLabel:ClearAllPoints()
            card.mainLabel:SetPoint("TOPLEFT",card,"TOPLEFT",48,-22)
            card.mainLabel:SetShown(false)
            card.mainLabel:SetText(display~=row and "Main: "..row.name or "")
            card.mainLabel:SetTextColor(.65,.65,.65)
            local nameWidth=math.min(400,card.name:GetStringWidth())
            card.badge:ClearAllPoints(); card.badge:SetPoint("TOPLEFT",card, "TOPLEFT",195,-2)
            card.badge:SetFaction(display.faction)
            OneLine(card.main,MainColumn(row,display),MAIN_W)
            local cardW=card:GetWidth() or 540
            OneLine(card.detail,display.class or "",
                math.max(80,cardW-DETAIL_X-(#alts>0 and 64 or 16)))
            do
                local c=Status(row.groupOnline and (row.online and row or {online=true}) or {online=false})
                card.dot:SetVertexColor(c[1]*.9,c[2]*.85,c[3]*.9)
            end
            card.arrow:SetText((#alts>0 and #alts.." alts  " or "")..(expanded and "-" or "+"))
            if card.altLines then for _,line in ipairs(card.altLines) do line:Hide() end end
            card.expansion:SetShown(expanded and true or false)
            if expanded then
                card.expansion:SetText(#alts==0 and (row.bnAlts and "No other characters known. They appear once this member runs LAFW Community." or "No linked alts.") or "")
                card.altLines=card.altLines or {}
                for _,line in ipairs(card.altLines) do line:Hide() end
                local children={}
                if display~=row then children[#children+1]=row end
                for _,alt in ipairs(alts) do if alt~=display then children[#children+1]=alt end end
                for index,alt in ipairs(children) do
                    local line=card.altLines[index]
                    if not line then
                        line=CreateFrame("Frame",nil,card,"BackdropTemplate"); line:SetHeight(24)
                        line:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); line:SetBackdropColor(.65,.65,.65,.045)
                        line.level=Text(line,11,4,-6,44)
                        -- Draw a bent right arrow without relying on font glyph coverage.
                        local function Stroke(w,h,x,y)
                            local t=line:CreateTexture(nil,"ARTWORK"); t:SetColorTexture(.5,.5,.5,1)
                            t:SetSize(w,h); t:SetPoint("TOPLEFT",x,y); return t
                        end
                        Stroke(1,7,49,-7); Stroke(8,1,49,-14)
                        local tip=Stroke(4,4,54,-12); tip:SetRotation(math.pi/4)
                        line.name=Text(line,11,70,-6,120)
                        line.role=Text(line,10,0,0,0); line.role:SetWidth(0); line.role:SetTextColor(.55,.55,.55)
                        line.badge=FactionIcon(line)
                        line.main=Text(line,11,MAIN_X,-6,MAIN_W); line.main:SetTextColor(.8,.8,.8)
                        line.detail=Text(line,10,DETAIL_X,-6,190); line.detail:SetTextColor(.65,.65,.65)
                        card.altLines[index]=line
                    end
                    line:ClearAllPoints(); line:SetPoint("TOPLEFT",card,"TOPLEFT",0,-26-(index-1)*25)
                    line:SetPoint("RIGHT",card,"RIGHT",0,0); line:Show()
                    line.level:SetText("Lvl "..(alt.level or "?"))
                    line.name:SetTextColor(alt.online and .2 or .6,alt.online and 1 or .6,alt.online and .4 or .6)
                    NameWithTag(line,line.name,line.role,alt.name,nil,120)
                    OneLine(line.main,LineColumn(row,alt),MAIN_W)
                    line.badge:ClearAllPoints(); line.badge:SetPoint("TOPLEFT",line,"TOPLEFT",195,-2)
                    line.badge:SetFaction(alt.faction)
                    OneLine(line.detail,alt.class or "",
                        math.max(80,(card:GetWidth() or 540)-DETAIL_X-16))
                end
            end
        end
    end
    f.content:SetHeight(math.max(f.scroll:GetHeight(),y+12))
    if f.updateScroll then f.updateScroll() end
    f.count:Hide()
    if f.admin then f.admin:SetShown(self:IsOwner()) end
    f.status:SetText((self.status or "").."\n"..#filtered.." matching characters - Scroll to browse")
    f.empty:SetShown(#filtered==0)
    local selected="Choose community"
    for _,club in ipairs(self:Communities()) do if club.clubId==self.db.clubId then selected=club.name or selected end end
    f.heading:SetText(self.embedded and "" or selected)
end
function A:BuildWindow()
    local modern=false
    local embedded=self.embedded
    local f
    if embedded then
        f=CreateFrame("Frame",nil,CommunitiesFrame)
        f:SetSize(590,360)
    else
        f=CreateFrame("Frame",nil,UIParent,"BasicFrameTemplateWithInset")
        f.TitleText:SetText("LAFW Community"); f:SetSize(740,620); f:SetPoint("CENTER")
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing)
    end
    self.window=f
    f.heading=Text(f,16,12,-12,300)
    f.heading:SetText("Advanced Roster")
    f.count=Text(f,11,12,-30,110); f.count:SetTextColor(.2,.8,.45)
    local actions={}
    actions[1]=Button(f,"Refresh",0,0,90,function() A:Refresh(); A:Draw() end,false)
    -- Your main and every setting live in the settings window now.
    local altButton=Button(f,"My characters",0,0,110,function() A.Me:Open() end,false)
    altButton:ClearAllPoints(); altButton:SetPoint("TOPRIGHT",f,"TOPRIGHT",-10,-5)
    actions[2]=Button(f,"Diagnostics",0,0,100,function() A:Diagnostics() end,false)
    f.admin=Button(f,"Admin",0,0,80,function() A:EditAlts(true) end,false); actions[3]=f.admin
    for i,button in ipairs(actions) do
        button:ClearAllPoints(); button:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-4-(i-1)*104,0)
        button:SetHeight(22)
    end
    local searchBG=CreateFrame("Frame",nil,f)
    searchBG:SetPoint("TOPLEFT",185,-5); searchBG:SetPoint("TOPRIGHT",f,"TOPRIGHT",-135,-5); searchBG:SetHeight(26)
    f.search=CreateFrame("EditBox",nil,searchBG,"InputBoxTemplate"); f.search:SetPoint("TOPLEFT",8,0); f.search:SetPoint("TOPRIGHT",-8,0); f.search:SetHeight(24)
    f.search:SetFontObject("GameFontHighlight"); f.search:SetAutoFocus(false)
    local placeholder=Text(searchBG,11,8,-7,230); placeholder:SetText("Search players or classes..."); placeholder:SetTextColor(.55,.55,.55)
    f.search:SetScript("OnTextChanged",function(box) placeholder:SetShown(box:GetText()==""); A.offset=0; A:Draw() end)
    f.search:SetScript("OnEscapePressed",function(box) box:ClearFocus(); f:Hide() end)
    self.faction=self.faction or "All"
    local factionMenu=CreateFrame("DropdownButton",nil,f,"WowStyle1DropdownTemplate")
    factionMenu:SetPoint("TOPLEFT",12,-5); factionMenu:SetWidth(160)
    factionMenu:SetDefaultText(self.faction=="All" and "All factions" or self.faction)
    factionMenu:SetupMenu(function(_,root)
        for _,value in ipairs({"All","Alliance","Horde"}) do
            local faction=value
            root:CreateRadio(faction=="All" and "All factions" or faction,
                function() return A.faction==faction end,
                function() A.faction=faction; A.offset=0; A:Draw() end)
        end
    end)
    f.scroll=CreateFrame("ScrollFrame",nil,f,modern and nil or "UIPanelScrollFrameTemplate")
    if modern then
        local slider=CreateFrame("Slider",nil,f,"BackdropTemplate")
        f.modernScroll=slider
        slider:SetPoint("TOPLEFT",f.scroll,"TOPRIGHT",10,0); slider:SetSize(6,328)
        slider:SetOrientation("VERTICAL"); slider:SetMinMaxValues(0,1); slider:SetValueStep(1)
        slider:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); slider:SetBackdropColor(.12,.12,.12,1)
        slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        local thumb=slider:GetThumbTexture(); thumb:SetSize(6,36); thumb:SetVertexColor(.40,.40,.40,1)
        slider:SetScript("OnValueChanged",function(_,value) f.scroll:SetVerticalScroll(value) end)
        local function UpdateScroll()
            local range=math.max(0,f.content:GetHeight()-f.scroll:GetHeight())
            slider:SetMinMaxValues(0,math.max(1,range)); slider:SetShown(range>0)
            thumb:SetHeight(math.max(28,328*328/math.max(328,f.content:GetHeight())))
            local value=math.min(f.scroll:GetVerticalScroll(),range)
            slider:SetValue(value); f.scroll:SetVerticalScroll(value)
        end
        f.updateScroll=UpdateScroll
        f.scroll:SetScript("OnScrollRangeChanged",UpdateScroll)
        f.scroll:EnableMouseWheel(true)
        f.scroll:SetScript("OnMouseWheel",function(_,delta)
            local range=math.max(0,f.content:GetHeight()-f.scroll:GetHeight())
            slider:SetValue(math.max(0,math.min(range,slider:GetValue()-delta*38)))
        end)
    end
    f.scroll:SetPoint("TOPLEFT",10,-55); f.scroll:SetPoint("BOTTOMRIGHT",-30,49)
    f.content=CreateFrame("Frame",nil,f.scroll); f.content:SetSize(670,328); f.scroll:SetScrollChild(f.content)
    f.cards={}
    for i=1,40 do
        local card=Panel(f.content); card:SetSize(540,59)
        if modern then
            card:SetBackdropColor(.14,.14,.14,1); card:SetBackdropBorderColor(.14,.14,.14,1)
        else
            card:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
            card:SetBackdropColor(.7,.7,.7,i%2==0 and .055 or .015)

        end
        card.level=Text(card,11,4,-6,44)
        card.name=Text(card,11,48,-6,140); card.name:SetWidth(0)
        card.role=Text(card,10,0,0,0); card.role:SetWidth(0); card.role:SetTextColor(.55,.55,.55)
        card.dot=card:CreateTexture(nil,"ARTWORK"); card.dot:SetSize(6,6); card.dot:SetPoint("TOPLEFT",49,-9)
        card.dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        card.badge=FactionIcon(card)
        card.main=Text(card,11,MAIN_X,-6,MAIN_W); card.main:SetTextColor(.8,.8,.8)
        card.detail=Text(card,10,DETAIL_X,-6,190); card.detail:SetTextColor(.65,.65,.65)
        card.arrow=Text(card,10,450,-6,74); card.arrow:SetJustifyH("RIGHT")
        card.expansion=Text(card,10,48,-27,600); card.expansion:SetSpacing(8)
        card:EnableMouse(true); card:SetScript("OnMouseUp",function(self,button)
            if not self.row then return end
            if button=="RightButton" then A:RowMenu(self,self.row); return end
            A.expanded[self.row.memberId]=not A.expanded[self.row.memberId]; A:Draw()
        end)
        card:SetScript("OnEnter",function(self)
            self:SetBackdropColor(.7,.7,.7,.12)
            local r0=self.row
            local status=not r0 and "" or (r0.online==true and (r0.elsewhere and ("Online, "..(r0.elsewhereWhy or "not in Forever"))
                or (r0.elsewhere==false and "Online in Forever" or (r0.battleTag and "Online (game unknown)" or "Online")))
                or (r0.online==false and "Offline" or "Status unknown"))
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetText(status)
            if r0 and r0.online then
                local c=Status(r0); GameTooltipTextLeft1:SetTextColor(c[1],c[2],c[3])
            end
            local row=self.row
            if row then
                if row.role=="alt" and row.mainName then GameTooltip:AddLine("Alt of "..row.mainName,1,.82,0)
                elseif row.role=="main" then GameTooltip:AddLine("Main character",1,.82,0) end
                if row.battleTag then GameTooltip:AddLine("BattleTag: "..row.battleTag,.65,.65,.65) end
                if A:CanInvite(row) then GameTooltip:AddLine("Right-click to invite",.5,.8,1) end
            end
            GameTooltip:Show()
        end)
        card:SetScript("OnLeave",function(self) self:SetBackdropColor(.7,.7,.7,i%2==0 and .055 or .015); GameTooltip:Hide() end)
        f.cards[i]=card
    end
    f.empty=Text(f,12,25,-95,510); f.empty:SetText("No matching characters. Choose a community or refresh the roster.")
    f.status=Text(f,10,12,0,540); f.status:ClearAllPoints(); f.status:SetPoint("BOTTOMLEFT",12,27); f.status:SetTextColor(.65,.65,.65)
    f:EnableMouseWheel(true); f:SetScript("OnMouseWheel",function(_,delta)
        if modern then f.scroll:GetScript("OnMouseWheel")(f.scroll,delta)
        else f.scroll:SetVerticalScroll(math.max(0,math.min(f.scroll:GetVerticalScroll()-delta*38,math.max(0,f.content:GetHeight()-f.scroll:GetHeight())))) end
    end)
    f:SetScript("OnKeyDown",function(self,key) if key=="ESCAPE" then self:SetPropagateKeyboardInput(false); self:Hide() else self:SetPropagateKeyboardInput(true) end end)
    self:Draw()
end
function A:Toggle()
    if not self.window then self:Refresh(); self:BuildWindow()
    elseif self.window:IsShown() then self.window:Hide()
    else self:Refresh(); self:Draw(); self.window:Show() end
end

function A:Links()
    self.db.links=self.db.links or {}
    local key=tostring(self.db.clubId or "none")
    self.db.links[key]=self.db.links[key] or {}
    return self.db.links[key]
end
function A:SelfMember()
    if not self.db.clubId or not C_Club or not C_Club.GetMemberInfoForSelf then return end
    local ok,member=pcall(C_Club.GetMemberInfoForSelf,self.db.clubId)
    if ok then return member end
end
function A:IsOwner()
    local member=self:SelfMember()
    return member and Enum and Enum.ClubRoleIdentifier and member.role==Enum.ClubRoleIdentifier.Owner or false
end
function A:EditAlts(admin)
    if admin and not self:IsOwner() then return end
    local member=self:SelfMember()
    if not member then self:Message("Choose a community containing this character first."); return end
    if self.altEditor then self.altEditor:Hide() end
    local clubId=self.db.clubId
    local links=self:Links()
    local ownMain=links[member.memberId] or member.memberId
    local selected=ownMain
    local f=CreateFrame("Frame",nil,UIParent,"BasicFrameTemplateWithInset")
    self.altEditor=f; f:SetSize(560,500); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f.TitleText:SetText(admin and "Community owner - Alt management" or "My alts")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing)
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown",function(self,key)
        self:SetPropagateKeyboardInput(key~="ESCAPE")
        if key=="ESCAPE" then self:Hide() end
    end)
    Text(f,11,20,-44,510):SetText("Select a main, then link or remove characters below.\nSelf-declared links are saved locally; other members do not receive them yet.")
    local mainLabel=Text(f,12,20,-91,510)
    mainLabel:SetTextColor(1,.82,0)
    local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",20,-132); scroll:SetSize(490,300)
    local content=CreateFrame("Frame",nil,scroll); content:SetSize(490,300); scroll:SetScrollChild(content)
    local controls={}
    local function allowed()
        if A.db.clubId~=clubId then return false end
        if admin then return A:IsOwner() end
        local current=A:SelfMember()
        return current and (current.memberId==selected or links[current.memberId]==selected)
    end
    local function render()
        for _,control in ipairs(controls) do control:Hide() end
        controls={}
        local mainName="Unknown"
        for _,row in ipairs(A.rows) do if row.memberId==selected then mainName=row.name end end
        mainLabel:SetText("Main: "..mainName)
        for i,row in ipairs(A.rows) do
            local id=row.memberId
            local background=CreateFrame("Frame",nil,content,"BackdropTemplate")
            background:SetSize(478,32); background:SetPoint("TOPLEFT",0,-(i-1)*36)
            background:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
            background:SetBackdropColor(1,1,1,id==selected and .09 or (i%2==0 and .035 or .015))
            controls[#controls+1]=background
            local line=Text(background,12,8,-9,235)
            line:SetText(row.name..(id==selected and " (main)" or ""))
            line:SetTextColor(id==selected and 1 or .85,id==selected and .82 or .85,id==selected and 0 or .85)
            local label=links[id]==selected and "Remove alt" or "Mark as alt"
            local button=Button(content,label,270,-(i-1)*36,110,function()
                if not allowed() or id==selected then return end
                if links[id]==selected then links[id]=nil
                elseif not links[id] then
                    for _,parent in pairs(links) do if parent==id then A:Message("Remove this character's alts before linking it."); return end end
                    links[id]=selected
                else A:Message("This character is already linked. Remove the existing link first."); return end
                render(); A:Draw()
            end,false)
            button:SetShown(id~=selected); controls[#controls+1]=button
            if admin or id==member.memberId or links[id]==ownMain or id==ownMain then
                local choose=Button(content,"Main",390,-(i-1)*36,70,function()
                    if A.db.clubId~=clubId or (admin and not A:IsOwner()) then return end
                    -- Changing main re-roots the whole existing group atomically.
                    local old=links[id] or id
                    if not admin and old~=ownMain then return end
                    links[id]=nil
                    for alt,parent in pairs(links) do if parent==old then links[alt]=id end end
                    if old~=id then links[old]=id end
                    selected=id; if not admin then ownMain=id end
                    render(); A:Draw()
                end,false)
                controls[#controls+1]=choose
            end
        end
        content:SetHeight(math.max(300,#A.rows*36))
    end
    local close=Button(f,"Close",0,0,110,function() f:Hide() end,false)
    close:ClearAllPoints(); close:SetPoint("BOTTOMRIGHT",-18,16)
    render()
end
