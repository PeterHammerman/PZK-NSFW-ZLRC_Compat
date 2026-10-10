-- ZLRC_StripGuard  (item 1)
-- Bumping / running into / stepping on an A-Life NPC fires ZomboDesire's zombie-catch logic and
-- ZomboLust's clothing strip, because A-Life NPCs are IsoZombie bodies. That must only happen when
-- the NPC is actually hostile.
--
-- Layers (each is independent):
--   1. modData.isBandit opt-out flag    - ZomboDesire's own "not a valid attacker" exclusion (earliest cut-off)
--   2. ZomboLust_ClothingStrip.*       - zombie -> player strip entry points (zombie is arg 1)
--   3. ZomboLust_ClothingStripForZombHuman.stripZombHuman
--   4. ZomboLust_SexualIntentSystem.scanProximity  (stops "intent" being rolled for friendly NPCs)

require "ZLRC/ZLRC_Core"

local function player0()
    local p
    pcall(function() p = getSpecificPlayer(0) end)
    return p
end

--- true when any argument is an A-Life NPC that is not known to be hostile
local function blocks(...)
    if not ZLRC.enabled() or ZLRC.sv("stripGuard", true) ~= true then return false end
    local p = player0()
    for i = 1, select("#", ...) do
        local a = select(i, ...)
        if a ~= nil and ZLRC.isNpc(a) and not ZLRC.isKnownHostile(a, p) then
            ZLRC.log("strip/catch blocked for non-hostile NPC (%s)", tostring(ZLRC.npcUid(a)))
            return true
        end
    end
    return false
end
ZLRC.stripBlocks = blocks

-- 1. ZomboDesire's own opt-out ---------------------------------------------------------------------------------------
-- Verified in ZomboDesire_Intercept.lua: collisionListener returns early when collidedChar:getModData().isBandit is set
-- ("A Bandit is not a valid attacker ... prevents a conflict, since bandits are IsoZombie"). That flag is read nowhere
-- else in ZomboDesire/ZomboLust/ZomboRut, so it is the framework's sanctioned way to say "not a catcher".
-- We set it on A-Life NPCs only while they are NOT hostile to the player, and remove it again (only if we set it) when
-- they turn hostile or the option is switched off. NOTE: the listener itself must NOT be replaced/re-registered: its
-- suspend/re-add logic uses a file-local reference, so swapping it would break the suspensions and create duplicates.
local SCAN_RADIUS2 = 12 * 12
local scanN = 0

local function syncFlags()
    if not ZLRC.enabled() then return end
    local p = player0()
    local cell = getCell()
    local list = p and cell and cell:getZombieList()
    if not list then return end
    local on = ZLRC.sv("stripGuard", true) == true
    local px, py = p:getX(), p:getY()
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z then
            local dx, dy = z:getX() - px, z:getY() - py
            if dx * dx + dy * dy <= SCAN_RADIUS2 and ZLRC.isNpc(z) then
                local d = ZLRC.md(z)
                if d then
                    local want = on and not ZLRC.isKnownHostile(z, p)
                    if want then
                        if not d.isBandit then d.isBandit = true; d.zlrcBanditFlag = true end
                    elseif d.zlrcBanditFlag then
                        d.isBandit = nil; d.zlrcBanditFlag = nil
                    end
                end
            end
        end
    end
end

Events.OnTick.Add(function()
    scanN = scanN + 1
    if scanN % 6 ~= 0 then return end
    local ok, err = pcall(syncFlags)
    if not ok then ZLRC.log("strip flag sync error: %s", tostring(err)) end
end)

-- 2. clothing strip ------------------------------------------------------------------------
ZLRC.whenReady("ZomboLust_ClothingStrip",
    function() return rawget(_G, "ZomboLust_ClothingStrip") and type(ZomboLust_ClothingStrip.attemptStripping) == "function" end,
    function()
        for _, fn in ipairs({ "attemptStripping", "stripTarget", "removeOneClothing" }) do
            ZLRC.wrap(ZomboLust_ClothingStrip, fn, function(orig)
                return function(zombie, ...)
                    if blocks(zombie) then return false end
                    return orig(zombie, ...)
                end
            end)
        end
    end)

-- 3. ZombHuman strip -------------------------------------------------------------------------
ZLRC.whenReady("ZomboLust_ClothingStripForZombHuman",
    function() return rawget(_G, "ZomboLust_ClothingStripForZombHuman") and type(ZomboLust_ClothingStripForZombHuman.stripZombHuman) == "function" end,
    function()
        ZLRC.wrap(ZomboLust_ClothingStripForZombHuman, "stripZombHuman", function(orig)
            return function(z, ...)
                if blocks(z) then return end
                return orig(z, ...)
            end
        end)
    end)

-- 4. intent roll ------------------------------------------------------------------------------
ZLRC.whenReady("ZomboLust_SexualIntentSystem.scanProximity",
    function() return rawget(_G, "ZomboLust_SexualIntentSystem") and type(ZomboLust_SexualIntentSystem.scanProximity) == "function" end,
    function()
        ZLRC.wrap(ZomboLust_SexualIntentSystem, "scanProximity", function(orig)
            return function(player, zombie, ...)
                if blocks(zombie) then return end
                return orig(player, zombie, ...)
            end
        end)
    end)
