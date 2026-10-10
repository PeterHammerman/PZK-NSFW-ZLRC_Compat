-- ZLRC_ExcitationPre (item 8, part 1 of 2)
-- Registered from a *shared* file on purpose: shared Lua loads before every mod's client Lua, so this
-- OnPlayerUpdate listener runs BEFORE ZomboLust's own updateExcitation listener in the same frame.
-- It only records the excitation value; ZLRC_Excitation.lua (client) corrects the delta afterwards.

require "ZLRC/ZLRC_Core"

ZLRC._excPre = ZLRC._excPre or setmetatable({}, { __mode = "k" })

Events.OnPlayerUpdate.Add(function(player)
    if player == nil then return end
    if ZLRC.sv("excitationSource", 1) == 1 or not ZLRC.enabled() then
        ZLRC._excPre[player] = nil
        return
    end
    local ES = rawget(_G, "ZomboLust_ExcitationSystem")
    if not (ES and type(ES.getExcitation) == "function") then return end
    local ok, v = pcall(ES.getExcitation, player)
    if ok and type(v) == "number" then ZLRC._excPre[player] = v end
end)
