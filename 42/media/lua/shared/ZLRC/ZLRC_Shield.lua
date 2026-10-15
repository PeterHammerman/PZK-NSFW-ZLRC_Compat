-- ZLRC_Shield  (item 11: NPC surrender / excitation encounters, part 1 of 3)
--
-- Decides when A-Life NPCs must leave the PLAYER alone. It is consulted from ZLRC_NpcIgnore's protectedTarget(), i.e. through
-- the single wrapper on ProjectALife.TargetPolicy.canAttack that every A-Life consumer (Perception, Combat, Gunner, SquadTactics,
-- HitRelay, Executor) already goes through. (ZLRC.wrap refuses to wrap its own wrapper twice, so this must NOT install a second one.)
--
-- The player is shielded while
--   * an encounter session (ZLRC_NpcEncounter) exists for them: NPC walking in, scene running, ...
--   * ZomboRut's give-up machine is active for them (any phase) - "a player that surrendered is not attacked any more"
--   * a ZomboRut scene is running on them
--   * the post-scene grace window is open (default 200 s), or ZomboRut is in its escape phase
--   * ZomboDesire's escape/invisibility timer is active
-- This protects against A-Life attacks only; vanilla zombies remain under their respective mods' handling.

require "ZLRC/ZLRC_Core"

ZLRC.Enc = ZLRC.Enc or {}
local E = ZLRC.Enc
E.sessions      = E.sessions      or setmetatable({}, { __mode = "k" })   -- [player] = session (owned by ZLRC_NpcEncounter)
E.graceUntil    = E.graceUntil    or setmetatable({}, { __mode = "k" })   -- [player] = ms
E.cooldownUntil = E.cooldownUntil or setmetatable({}, { __mode = "k" })   -- [player] = ms

local function isPlayer(obj)
    if obj == nil then return false end
    local ok, r = pcall(instanceof, obj, "IsoPlayer")
    return ok and r == true
end

--- Reason string when A-Life NPCs must not target/hurt this object, else nil. Only ever answers for players.
function ZLRC.shieldReason(target)
    if not ZLRC.enabled() then return nil end
    if not isPlayer(target) then return nil end

    local s = E.sessions[target]
    if s then return "zlrc_encounter_" .. tostring(s.state) end

    local g = E.graceUntil[target]
    if g and getTimestampMs() < g then return "zlrc_grace" end

    local escape = rawget(_G, "ZomboDesire_EscapeHandler")
    if escape and escape.escapeTimerSet == true then return "zlrc_zombodesire_escape" end

    local zs = rawget(_G, "ZR_Surrender")
    if zs and type(zs.getPhase) == "function" then
        local ok, phase = pcall(zs.getPhase, target)
        if ok and phase == "escape" then return "zlrc_escape" end
    end
    if ZLRC.call(target, "isGhostMode") == true then return "zlrc_ghosted" end

    if ZLRC.sv("npcShieldGiveUp", true) == true then
        if zs and type(zs.isActive) == "function" then
            local ok, v = pcall(zs.isActive, target)
            if ok and v == true then return "zlrc_giveup" end
        end
        local zrs = ZLRC.zrScene()
        if zrs and type(zrs._active) == "table" and zrs._active[target] ~= nil then return "zlrc_in_scene" end
    end
    return nil
end

return ZLRC
