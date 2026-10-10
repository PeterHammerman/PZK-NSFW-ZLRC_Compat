-- ZLRC_NpcIgnore  (items 2, 3, 4, and the bleed-out half of 6)
--
-- Seams used (all verified in the shipped sources):
--   * ProjectALife.TargetPolicy.canAttack(target, stamp) -> allowed, reason
--       Every A-Life consumer (Perception, Combat, SquadTactics, Gunner, HitRelay, Executor) calls it
--       through the table at call time, so one wrapper covers target acquisition AND damage refusal.
--   * ProjectALifeJimmy.Residents.sweep.liveZombies()  -> { {x,y,obj}, ... }   (residents "deal with" zombies in a base)
--   * ProjectALifeJimmy.Residents.bodies.bodyOn(square) -> IsoDeadBody|nil     (residents carry corpses to the dump)
--   * ProjectALife.Health.tick(shell, data, now)       (downed NPCs bleed out and are Kill()ed after ~10 s)

require "ZLRC/ZLRC_Core"

local function playerDraggingCorpseNear(obj, radius)
    if obj == nil then return false end
    local found = false
    local ox, oy
    pcall(function() ox, oy = obj:getX(), obj:getY() end)
    if not ox then return false end
    ZLRC.eachPlayer(function(p)
        if found then return end
        local ok, dragging = pcall(function() return p:isDraggingCorpse() end)
        if ok and dragging == true then
            local dx, dy = p:getX() - ox, p:getY() - oy
            if dx * dx + dy * dy <= radius * radius then found = true end
        end
    end)
    return found
end

--- Reason string if NPCs must leave this *living* target alone, else nil.
local function protectedTarget(target)
    if target == nil or not ZLRC.enabled() then return nil end
    local d = ZLRC.md(target)
    if d and d.zlrcBusy then return "zlrc_busy_in_scene" end   -- NPC currently in a ZomboRut scene with the player
    if ZLRC.sv("npcIgnoreSubdued", true) == true then
        if ZLRC.isSubdued(target) then return "zlrc_subdued" end
        if ZLRC.isHusk(target)    then return "zlrc_scene_husk" end
    end
    if ZLRC.sv("npcIgnoreDragged", true) == true then
        local ok, grapple = pcall(function() return target:isReanimatedForGrappleOnly() end)
        if ok and grapple == true then return "zlrc_grappled_corpse" end
    end
    return nil
end
ZLRC.protectedTarget = protectedTarget

--- Same, for a ground corpse (Jeem body clean-up).
local function protectedBody(body)
    if body == nil or not ZLRC.enabled() then return false end
    if ZLRC.isHusk(body) or ZLRC.isSubdued(body) then return true end
    if ZLRC.sv("npcIgnoreDragged", true) == true and playerDraggingCorpseNear(body, 3.0) then
        return true
    end
    return false
end

-- ------------------------------------------------------------------ A-Life: never target / hit them
ZLRC.whenReady("A-Life TargetPolicy.canAttack",
    function()
        local PA = rawget(_G, "ProjectALife")
        return PA and PA.TargetPolicy and type(PA.TargetPolicy.canAttack) == "function"
    end,
    function()
        ZLRC.wrap(ProjectALife.TargetPolicy, "canAttack", function(orig)
            return function(target, ...)
                local reason = protectedTarget(target)
                if reason then return false, reason end
                return orig(target, ...)
            end
        end)
    end)

-- ------------------------------------------------------------------ A-Life: a captive must not bleed out
local BLEED_KEYS = { "ProjectALifeBleedOutAtMs" }
local function clearBleed(shell, data)
    data = data or ZLRC.md(shell)
    if type(data) ~= "table" then return end
    for _, k in ipairs(BLEED_KEYS) do data[k] = nil end
end

local function isCaptiveNpc(shell)
    return ZLRC.sv("persistCaptives", true) == true and ZLRC.enabled()
        and ZLRC.isSubdued(shell) and ZLRC.isNpc(shell)
end

ZLRC.whenReady("A-Life Health.tick",
    function()
        local PA = rawget(_G, "ProjectALife")
        return PA and PA.Health and type(PA.Health.tick) == "function"
    end,
    function()
        ZLRC.wrap(ProjectALife.Health, "tick", function(orig)
            return function(shell, data, ...)
                if isCaptiveNpc(shell) then clearBleed(shell, data) end
                local a, b, c = orig(shell, data, ...)
                if isCaptiveNpc(shell) then clearBleed(shell, data) end
                return a, b, c
            end
        end)
    end)

-- ------------------------------------------------------------------ Jeem: residents leave them alone
ZLRC.whenReady("Jeem sweep.liveZombies",
    function()
        local J = rawget(_G, "ProjectALifeJimmy")
        return J and J.Residents and J.Residents.sweep and type(J.Residents.sweep.liveZombies) == "function"
    end,
    function()
        ZLRC.wrap(ProjectALifeJimmy.Residents.sweep, "liveZombies", function(orig)
            return function(...)
                local list = orig(...)
                if type(list) ~= "table" then return list end
                local out = {}
                for _, e in ipairs(list) do
                    local skip = false
                    if type(e) == "table" and e.obj ~= nil then
                        skip = protectedTarget(e.obj) ~= nil
                            or (ZLRC.sv("npcIgnoreDragged", true) == true and playerDraggingCorpseNear(e.obj, 3.0))
                    end
                    if not skip then out[#out + 1] = e end
                end
                return out
            end
        end)
    end)

ZLRC.whenReady("Jeem bodies.bodyOn",
    function()
        local J = rawget(_G, "ProjectALifeJimmy")
        return J and J.Residents and J.Residents.bodies and type(J.Residents.bodies.bodyOn) == "function"
    end,
    function()
        ZLRC.wrap(ProjectALifeJimmy.Residents.bodies, "bodyOn", function(orig)
            return function(square, ...)
                local body = orig(square, ...)
                if body ~= nil and protectedBody(body) then return nil end
                return body
            end
        end)
    end)
