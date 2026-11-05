-------------------------------------------------------------------------------
-- The community in chat.
--
--   /l      talks in the community, like /p for party: type "/l " and the
--           chat box switches to the community and stays there; "/l text"
--           sends one line.
--   General the community chat is added to the General chat tab once, the
--   tab    first time. Removing it there (right-click the tab > Settings >
--           Channels) sticks: the addon never adds it again.
--
-- The community is the one chosen in the settings window, else the one
-- selected in the community window's LAFW tab, else your first Blizzard
-- Group.
-------------------------------------------------------------------------------
local _, A = ...
local CC = {}
A.CommunityChat = CC
CC.stats = { added = nil, addedVia = nil, slashSends = 0, switched = 0 }

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

-------------------------------------------------------------------------------
-- Which community and stream
-------------------------------------------------------------------------------
function CC:Clubs()
    local list = Call(C_Club and C_Club.GetSubscribedClubs) or {}
    local out = {}
    for _, club in ipairs(list) do if club.clubId then out[#out + 1] = club end end
    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    return out
end

function CC:ClubId()
    local clubs = self:Clubs()
    local function Has(id)
        for _, c in ipairs(clubs) do if c.clubId == id then return true end end
    end
    local db = A.db or {}
    if db.chatClubId and Has(db.chatClubId) then return db.chatClubId end
    if db.clubId and Has(db.clubId) then return db.clubId end
    for _, c in ipairs(clubs) do
        if A.BN:IsBattleNetClub(c.clubId) then return c.clubId end
    end
end

function CC:ClubName()
    local id = self:ClubId()
    for _, c in ipairs(self:Clubs()) do if c.clubId == id then return c.name end end
end

-- The community's main chat stream ("General").
function CC:StreamId(clubId)
    local streams = clubId and Call(C_Club.GetStreams, clubId)
    if type(streams) ~= "table" or #streams == 0 then return nil end
    local general = Enum and Enum.ClubStreamType and Enum.ClubStreamType.General
    for _, st in ipairs(streams) do
        if general and st.streamType == general then return st.streamId end
    end
    table.sort(streams, function(a, b) return (a.streamId or 0) < (b.streamId or 0) end)
    return streams[1].streamId
end

function CC:ChannelName(clubId, streamId)
    if ChatFrameUtil and ChatFrameUtil.GetCommunitiesChannelName then
        return Call(ChatFrameUtil.GetCommunitiesChannelName, clubId, streamId)
    end
    if Chat_GetCommunitiesChannelName then return Call(Chat_GetCommunitiesChannelName, clubId, streamId) end
    return "Community:" .. clubId .. ":" .. streamId
end

-- The chat channel number the community has in this session (like the 5 in
-- "/5"), joining it if needed.
function CC:ChannelNumber(join)
    local clubId = self:ClubId()
    local streamId = self:StreamId(clubId)
    if not streamId then return nil end
    local name = self:ChannelName(clubId, streamId)
    local id = name and Call(GetChannelName, name)
    if (not id or id == 0) and join and C_Club.AddClubStreamChatChannel then
        Call(C_Club.AddClubStreamChatChannel, clubId, streamId)
        id = Call(GetChannelName, name)
    end
    return (type(id) == "number" and id > 0) and id or nil, clubId, streamId, name
end

-------------------------------------------------------------------------------
-- The General tab: add the community once.
-------------------------------------------------------------------------------
local function FrameHasChannel(frame, name)
    for _, n in ipairs(frame.channelList or {}) do if n == name then return true end end
end

function CC:AddToGeneralTab()
    local db = A.db
    local clubId = self:ClubId()
    local streamId = self:StreamId(clubId)
    if not db or not streamId then return end
    db.chatTab = db.chatTab or {}
    local key = clubId .. ":" .. streamId
    if db.chatTab[key] then return end           -- done once; your choice since then stands
    local name = self:ChannelName(clubId, streamId)
    local frame = ChatFrame1
    if not frame or not name then return end
    if FrameHasChannel(frame, name) then db.chatTab[key] = "already"; self.stats.added = true; return end
    -- Blizzard's own "show this community in this tab", under whichever
    -- name this build uses.
    local tries = {
        { "ChatFrameUtil.AddNewCommunitiesChannel", ChatFrameUtil and ChatFrameUtil.AddNewCommunitiesChannel, 1, clubId, streamId },
        { "ChatFrame_AddNewCommunitiesChannel", _G.ChatFrame_AddNewCommunitiesChannel, 1, clubId, streamId },
        { "ChatFrameUtil.AddCommunitiesChannel", ChatFrameUtil and ChatFrameUtil.AddCommunitiesChannel, frame, clubId, streamId, true },
        { "ChatFrame_AddCommunitiesChannel", _G.ChatFrame_AddCommunitiesChannel, frame, clubId, streamId, true },
    }
    for _, t in ipairs(tries) do
        if type(t[2]) == "function" then
            local ok = pcall(t[2], select(3, unpack(t)))
            if ok and FrameHasChannel(frame, name) then
                db.chatTab[key] = t[1]; self.stats.added, self.stats.addedVia = true, t[1]
                return
            end
        end
    end
    -- Fallback: join the community's channel and add it to the tab.
    self:ChannelNumber(true)
    local add = (ChatFrameUtil and ChatFrameUtil.AddChannel) or _G.ChatFrame_AddChannel
    if add then pcall(add, frame, name) end
    if FrameHasChannel(frame, name) then
        db.chatTab[key] = "AddChannel"; self.stats.added, self.stats.addedVia = true, "AddChannel"
    else
        self.stats.added = false   -- try again next login
    end
end

-------------------------------------------------------------------------------
-- /l
-------------------------------------------------------------------------------
-- Point a chat box at the community, the way "/5 " would.
local function StickTo(editBox, number)
    if not editBox or not number then return end
    editBox:SetAttribute("chatType", "CHANNEL")
    editBox:SetAttribute("channelTarget", number)
    if editBox.UpdateHeader then pcall(editBox.UpdateHeader, editBox)
    elseif ChatEdit_UpdateHeader then pcall(ChatEdit_UpdateHeader, editBox) end
end

function CC:Send(text, editBox)
    local number, clubId, streamId = self:ChannelNumber(true)
    if not streamId then
        A:Message("No community chosen for /l: pick one in the settings window (minimap button).")
        return
    end
    if text and text:find("%S") then
        local ok = pcall(C_Club.SendMessage, clubId, streamId, text)
        if ok then self.stats.slashSends = self.stats.slashSends + 1 end
    end
    StickTo(editBox, number)
end

-- Typing "/l " swaps in "/<number> " so the game switches the chat box to
-- the community at once, exactly like "/p ".
local swapping
local function OnTextChanged(editBox, userInput)
    if swapping or not userInput then return end
    local text = editBox:GetText()
    if type(text) ~= "string" then return end
    local rest = text:match("^/[lL] (.*)$")
    if not rest then return end
    local number = CC:ChannelNumber(true)
    if not number then return end
    swapping = true
    editBox:SetText("/" .. number .. " " .. rest)
    swapping = false
    CC.stats.switched = CC.stats.switched + 1
end

function CC:InstallSlash()
    if self.slashInstalled then return end
    self.slashInstalled = true
    -- Keep /l if another addon already owns it: say so in the test.
    if hash_SlashCmdList and hash_SlashCmdList["/L"] then self.stats.slashTaken = true end
    SLASH_LAFWCOMMUNITYCHAT1 = "/l"
    SlashCmdList.LAFWCOMMUNITYCHAT = function(msg, editBox) CC:Send(msg, editBox) end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local box = _G["ChatFrame" .. i .. "EditBox"]
        if box and box.HookScript then box:HookScript("OnTextChanged", OnTextChanged) end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CLUB_STREAM_SUBSCRIBED")
events:RegisterEvent("CLUB_STREAMS_LOADED")
local tries = 0
events:SetScript("OnEvent", function(_, event)
    if not A.db then return end
    if event == "PLAYER_LOGIN" then
        CC:InstallSlash()
        -- Communities finish loading a little after login.
        local function Try()
            tries = tries + 1
            CC:AddToGeneralTab()
            if CC.stats.added ~= true and tries < 6 then C_Timer.After(5, Try) end
        end
        C_Timer.After(5, Try)
    else
        CC:AddToGeneralTab()
    end
end)
