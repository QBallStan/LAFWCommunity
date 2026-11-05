local _, A = ...
-- Colors this addon gave the community chat before, replaced once unless
-- you've recolored it since: purple (0.1-0.5, too close to whispers), then
-- mint (0.6-0.7, too close to guild).
local OLD_COLORS={ {.72,.48,1}, {.55,.95,.70} }
-- The community chat color: a warm gold-tan, chosen against every default
-- chat color of the Forever client with CIEDE2000 (how different two colors
-- look). Nearest defaults: pet battle log 17, honor 18, raid and instance
-- orange 18; guild 39, whispers 53 (10+ is a plainly visible difference).
-- If your own chat colors sit close to it, the most distinct of the others
-- is used instead.
local PREFERRED={200/255,160/255,95/255}
local CANDIDATES={
    PREFERRED,
    {60/255,185/255,155/255},    -- jade
    {0,185/255,195/255},         -- deep cyan
    {1,190/255,145/255},         -- peach
    {1,125/255,170/255},         -- rose
}
local CLEAR=12   -- below this ΔE the preferred color is too close to one of yours
local function ClubLinks(clubId)
    return A.db and A.db.links and A.db.links[tostring(clubId)] or {}
end
local function Near(r,g,b,c) return math.abs(r-c[1])<.02 and math.abs(g-c[2])<.02 and math.abs(b-c[3])<.02 end

-- sRGB (0-1) to CIELAB, D65.
local function Lab(r,g,b)
    local function lin(u) return u>0.04045 and ((u+0.055)/1.055)^2.4 or u/12.92 end
    r,g,b=lin(r),lin(g),lin(b)
    local x=(0.4124*r+0.3576*g+0.1805*b)/0.95047
    local y=0.2126*r+0.7152*g+0.0722*b
    local z=(0.0193*r+0.1192*g+0.9505*b)/1.08883
    local function f(t) return t>0.008856 and t^(1/3) or 7.787*t+16/116 end
    local fx,fy,fz=f(x),f(y),f(z)
    return 116*fy-16,500*(fx-fy),200*(fy-fz)
end
-- CIEDE2000 color difference.
local function DeltaE(c1,c2)
    local rad,deg=math.rad,math.deg
    local L1,a1,b1=Lab(c1[1],c1[2],c1[3]); local L2,a2,b2=Lab(c2[1],c2[2],c2[3])
    local C1,C2=math.sqrt(a1*a1+b1*b1),math.sqrt(a2*a2+b2*b2)
    local Cb=(C1+C2)/2
    local G=0.5*(1-math.sqrt(Cb^7/(Cb^7+25^7)))
    local a1p,a2p=(1+G)*a1,(1+G)*a2
    local C1p,C2p=math.sqrt(a1p*a1p+b1*b1),math.sqrt(a2p*a2p+b2*b2)
    local h1=deg(math.atan2(b1,a1p))%360; local h2=deg(math.atan2(b2,a2p))%360
    local dL,dC=L2-L1,C2p-C1p
    local dh=h2-h1
    if C1p*C2p==0 then dh=0 elseif dh>180 then dh=dh-360 elseif dh<-180 then dh=dh+360 end
    local dH=2*math.sqrt(C1p*C2p)*math.sin(rad(dh/2))
    local Lb,Cbp=(L1+L2)/2,(C1p+C2p)/2
    local hb
    if C1p*C2p==0 then hb=h1+h2
    elseif math.abs(h1-h2)<=180 then hb=(h1+h2)/2
    elseif h1+h2<360 then hb=(h1+h2+360)/2 else hb=(h1+h2-360)/2 end
    local T=1-0.17*math.cos(rad(hb-30))+0.24*math.cos(rad(2*hb))+0.32*math.cos(rad(3*hb+6))-0.20*math.cos(rad(4*hb-63))
    local dth=30*math.exp(-((hb-275)/25)^2)
    local Rc=2*math.sqrt(Cbp^7/(Cbp^7+25^7))
    local Sl=1+0.015*(Lb-50)^2/math.sqrt(20+(Lb-50)^2)
    local Sc,Sh=1+0.045*Cbp,1+0.015*Cbp*T
    local Rt=-math.sin(rad(2*dth))*Rc
    return math.sqrt((dL/Sl)^2+(dC/Sc)^2+(dH/Sh)^2+Rt*(dC/Sc)*(dH/Sh))
end
A.ChatDeltaE=DeltaE

-- How close a color comes to any chat color in this game but `ownType`.
local function Nearest(c,ownType)
    local nearest,who=math.huge,nil
    for chatType,info in pairs(ChatTypeInfo or {}) do
        if chatType~=ownType and type(info)=="table" and type(info.r)=="number" then
            local d=DeltaE(c,{info.r,info.g,info.b})
            if d<nearest then nearest,who=d,chatType end
        end
    end
    return nearest,who
end
-- The preferred color, unless one of your chat colors is too close to it;
-- then the candidate that stands furthest from all of them.
function A:PickChatColor(ownType)
    if Nearest(PREFERRED,ownType)>=CLEAR then return PREFERRED end
    local best,bestScore
    for _,c in ipairs(CANDIDATES) do
        local d=Nearest(c,ownType)
        if not bestScore or d>bestScore then best,bestScore=c,d end
    end
    return best
end
function A:ColorCommunityChat()
    if not self.db or not self.db.clubId or not C_Club or not C_Club.GetStreams then return end
    local ok,streams=pcall(C_Club.GetStreams,self.db.clubId)
    if not ok or type(streams)~="table" then return end
    self.db.chatColors=self.db.chatColors or {}
    for _,stream in ipairs(streams) do
        local channelName
        if ChatFrameUtil and ChatFrameUtil.GetCommunitiesChannelName then
            channelName=ChatFrameUtil.GetCommunitiesChannelName(self.db.clubId,stream.streamId)
        end
        if channelName then
            local channelId=GetChannelName(channelName)
            if channelId and channelId>0 then
                local key=tostring(self.db.clubId)..":"..tostring(stream.streamId)
                local previous=self.db.chatColors[key]
                local chatType="CHANNEL"..channelId
                local info=ChatTypeInfo[chatType]
                -- Set a default once per stream/channel assignment, preserving later personal color changes.
                -- A color this addon set before is replaced once, unless you've recolored it since.
                local stillOurs=false
                if previous and (previous.v or 0)<3 and info then
                    for _,c in ipairs(OLD_COLORS) do if Near(info.r,info.g,info.b,c) then stillOurs=true end end
                end
                if info and (not previous or previous.channelId~=channelId or stillOurs) then
                    local c=self:PickChatColor(chatType)
                    ChangeChatColor(chatType,c[1],c[2],c[3])
                    self.db.chatColors[key]={channelId=channelId,v=3}
                elseif previous and (previous.v or 0)<3 then
                    previous.v=3   -- recolored by you: keep it
                end
            end
        end
    end
end
local function Decorate(name,display,clubId)
    if not A.db or clubId~=A.db.clubId or type(name)~="string" or type(display)~="string" then return display end
    local links=ClubLinks(clubId)
    if not next(links) or not C_Club then return display end
    local ok,members=pcall(C_Club.GetClubMembers,clubId)
    if not ok or not members then return display end
    local match
    for _,id in ipairs(members) do
        local success,info=pcall(C_Club.GetMemberInfo,clubId,id)
        if success and info and info.name==name then
            if match then return display end
            match=id
        end
    end
    local mainId=match and links[match]
    if not mainId or mainId==match then return display end
    local success,main=pcall(C_Club.GetMemberInfo,clubId,mainId)
    if not success or not main or type(main.name)~="string" or main.name:find("[|%c]") then return display end
    -- Change only visible link text; Blizzard keeps the sender and community message targets.
    local suffix=" - "..main.name
    if display:sub(-1)=="]" then return display:sub(1,-2)..suffix.."]" end
    return display..suffix
end
function A:InstallChat()
    if self.chatInstalled then return end
    if type(GetPlayerCommunityLink)~="function" then return end
    self.chatInstalled=true
    local original=GetPlayerCommunityLink
    GetPlayerCommunityLink=function(name,display,clubId,...)
        return original(name,Decorate(name,display,clubId),clubId,...)
    end
end
local events=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_LOGIN","PLAYER_ENTERING_WORLD","CHANNEL_UI_UPDATE","CHAT_MSG_CHANNEL_NOTICE","CLUB_STREAM_SUBSCRIBED","ADDON_LOADED"}) do events:RegisterEvent(event) end
local pending
local function Update()
    pending=nil
    if A.db then A:InstallChat(); A:ColorCommunityChat() end
end
events:SetScript("OnEvent",function()
    if not pending then pending=true; C_Timer.After(.5,Update) end
end)
