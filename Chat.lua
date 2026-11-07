-------------------------------------------------------------------------------
-- Chat colors: the addon no longer colors any channel.
--
-- Up to 1.4 it painted the community chat's channel, by channel number. When
-- channel numbers moved around (General, Trade and the community trading
-- places), the color stayed on numbers that now belong to other channels.
-- This undoes it once: every numbered channel still wearing one of the
-- addon's colors goes back to the game's default channel color.
-------------------------------------------------------------------------------
local _, A = ...

local DEFAULT = { 255 / 255, 192 / 255, 192 / 255 }   -- Forever's default channel color
-- Every color the addon ever set: gold (default since 0.8.2), purple, mint,
-- tan, and the fallbacks it could pick.
local OURS = {
    { 200 / 255, 165 / 255, 0 }, { .72, .48, 1 }, { .55, .95, .70 }, { 200 / 255, 160 / 255, 95 / 255 },
    { 60 / 255, 185 / 255, 155 / 255 }, { 0, 185 / 255, 195 / 255 }, { 1, 190 / 255, 145 / 255 }, { 1, 125 / 255, 170 / 255 },
}
local function Near(r, g, b, c) return math.abs(r - c[1]) < .02 and math.abs(g - c[2]) < .02 and math.abs(b - c[3]) < .02 end

function A:ResetChatColors()
    local db = self.db
    local ours = {}
    for _, c in ipairs(OURS) do ours[#ours + 1] = c end
    if type(db.chatColor) == "table" and type(db.chatColor[1]) == "number" then ours[#ours + 1] = db.chatColor end
    for _, e in pairs(db.chatColors or {}) do
        if type(e) == "table" and type(e.applied) == "table" and type(e.applied[1]) == "number" then ours[#ours + 1] = e.applied end
    end
    local reset = 0
    for i = 1, 20 do
        local info = ChatTypeInfo and ChatTypeInfo["CHANNEL" .. i]
        if info and type(info.r) == "number" then
            for _, c in ipairs(ours) do
                if Near(info.r, info.g, info.b, c) then
                    pcall(ChangeChatColor, "CHANNEL" .. i, DEFAULT[1], DEFAULT[2], DEFAULT[3])
                    reset = reset + 1
                    break
                end
            end
        end
    end
    db.chatColor, db.chatColors = nil, nil
    db.chatColorsReset = true
    if reset > 0 then self:Message(("chat channel colors set back to the game's default (%d channel%s)."):format(reset, reset == 1 and "" or "s")) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    if A.db and not A.db.chatColorsReset then C_Timer.After(5, function() pcall(A.ResetChatColors, A) end) end
end)
