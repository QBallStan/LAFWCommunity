local _, A = ...
-- 0.1-0.5 colored the community chat purple, too close to whispers.
local OLD_PURPLE={.72,.48,1}
-- Candidate colors for the community chat. The one furthest from every chat
-- color in this game (yours included, if you changed any) is used.
local CANDIDATES={
    {.55,.95,.70},   -- mint (furthest from the default chat colors)
    {.30,.72,1.0},   -- sky blue
    {.25,.85,.70},   -- teal
    {1.0,.72,.20},   -- amber
    {.60,.90,.30},   -- lime
    {1.0,.45,.55},   -- coral pink
    {.55,.65,1.0},   -- periwinkle
}
local function ClubLinks(clubId)
    return A.db and A.db.links and A.db.links[tostring(clubId)] or {}
end
local function Near(r,g,b,c) return math.abs(r-c[1])<.02 and math.abs(g-c[2])<.02 and math.abs(b-c[3])<.02 end
-- The candidate with the most distance to its nearest chat color.
function A:PickChatColor(ownType)
    local best,bestScore
    for _,c in ipairs(CANDIDATES) do
        local nearest=math.huge
        for chatType,info in pairs(ChatTypeInfo or {}) do
            if chatType~=ownType and type(info)=="table" and type(info.r)=="number" then
                -- Perceptual weights: the eye tells greens apart least.
                local d=2*(info.r-c[1])^2+4*(info.g-c[2])^2+3*(info.b-c[3])^2
                if d<nearest then nearest=d end
            end
        end
        if not bestScore or nearest>bestScore then best,bestScore=c,nearest end
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
                -- The old purple is replaced once, unless you've recolored it since.
                local stillPurple=previous and not previous.v and info and Near(info.r,info.g,info.b,OLD_PURPLE)
                if info and (not previous or previous.channelId~=channelId or stillPurple) then
                    local c=self:PickChatColor(chatType)
                    ChangeChatColor(chatType,c[1],c[2],c[3])
                    self.db.chatColors[key]={channelId=channelId,v=2}
                elseif previous and not previous.v then
                    previous.v=2   -- recolored by you: keep it
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
