-- ZLRC_Captives  (item 6)
--
-- What goes wrong today (derived from the sources):
--   A-Life NPCs are IsoZombie shells that A-Life despawns/respawns as the player leaves/returns (OrphanGuard purges
--   stale saved shells, Watchdog/Lifecycle re-hydrate a fresh one from the actor record). ZomboRut keeps its own list of
--   captives (player modData "zr_subduedRegistry") and, when it cannot find the captive's body, SPAWNS A GENERIC NAKED
--   ZOMBIE with the captured visuals. Result: a lifeless zombie lying where the subdued NPC was, while the real NPC is
--   hydrated again, free. In addition, a downed A-Life NPC bleeds out (ProjectALifeBleedOutAtMs ~10 s -> Kill()).
--
-- What this module does for a REAL A-Life NPC (one with ProjectALifeUID) that is subdued:
--   1. "capture": moves the captive out of ZomboRut's registry into our own persistent store, so ZomboRut never makes a
--      generic copy (the A-Life actor record stays the single source of truth for the person).
--   2. while the shell is alive: keeps A-Life's "held down" bookkeeping satisfied (far-future DownedUntilMs, refreshed
--      prone timer, no bleed-out) so it neither stands up nor dies by itself.
--   3. whenever A-Life gives that actor a new shell (we scan, and also wrap Watchdog.bind): re-applies the captive state
--      at the stored position (flag zrSubdued=true; ZomboRut's own enforce() then lays it down every tick).
--   4. ZR_Subdued.release() on such an NPC: hands the body back to A-Life (ProjectALifeOwned=true) and forgets the captive.
--   5. ZR_Subdued.getBinding() keeps returning the stored binding for captured NPCs.
--
-- Plain (non-NPC) subdued zombies are untouched: ZomboRut's own persistence already handles those.

require "ZLRC/ZLRC_Core"

local HOLD_MS = 10 * 60 * 1000

local function ts() return getTimestampMs() end

local function captivesStore()
    return ZLRC.store().captives
end

local function playerMD()
    local p
    pcall(function() p = getSpecificPlayer(0) end)
    return p and ZLRC.md(p) or nil
end

-- A-Life bookkeeping that keeps a downed shell "legitimately held down" -------------------------------------------------
local function keepHeldDown(shell)
    local d = ZLRC.md(shell)
    if not d then return end
    d.ProjectALifeDownedUntilMs = ts() + HOLD_MS
    d.ProjectALifeBleedOutAtMs  = nil
    local PA = rawget(_G, "ProjectALife")
    if PA and PA.AIFence and type(PA.AIFence.proneFirstMs) == "table" then
        PA.AIFence.proneFirstMs[shell] = ts()     -- stops the "downed too long, force get-up" hard cap
    end
end

local function applyCaptive(shell, entry)
    local d = ZLRC.md(shell)
    if not d then return end
    d.zrSubdued, d.zlrcCaptive, d.ProjectALifeOwned = true, true, true
    pcall(function()
        local dx, dy = shell:getX() - entry.x, shell:getY() - entry.y
        if dx * dx + dy * dy > 0.5 then
            if shell.teleportTo then shell:teleportTo(entry.x, entry.y, entry.z) end
            shell:setX(entry.x); shell:setY(entry.y); shell:setZ(entry.z)
        end
    end)
    pcall(function() shell:setFallOnFront(entry.onFront == true) end)
    pcall(function() shell:setOnFloor(true) end)
    pcall(function() if ZR_Subdued and ZR_Subdued.enforce then ZR_Subdued.enforce(shell) end end)
    keepHeldDown(shell)
    ZLRC.log("captive re-applied to %s at %.1f,%.1f", tostring(ZLRC.npcUid(shell)), entry.x, entry.y)
end

-- 1. capture -------------------------------------------------------------------------------------------------------------
local function capture(shell)
    local uid = ZLRC.npcUid(shell)
    if not uid then return end
    local d = ZLRC.md(shell)
    local pmd = playerMD()
    local reg = pmd and pmd.zr_subduedRegistry
    local key = d.zrSubduedKey
    local zrEntry = key and reg and reg[key] or nil
    captivesStore()[uid] = {
        x = shell:getX(), y = shell:getY(), z = shell:getZ(),
        onFront = (zrEntry and zrEntry.onFront) or false,
        binding = zrEntry and zrEntry.binding or nil,
        since = ts(),
    }
    if key and reg then reg[key] = nil end      -- ZomboRut must not materialise a generic copy of a real person
    d.zlrcCaptive = true
    keepHeldDown(shell)
    ZLRC.log("captured NPC %s", uid)
end

-- periodic maintenance (every ~0.5 s) ---------------------------------------------------------------------------------------
local tickN = 0
local function maintain()
    if not (ZLRC.enabled() and ZLRC.sv("persistCaptives", true) == true) then return end
    local cell = getCell()
    local list = cell and cell:getZombieList()
    if not list then return end
    local store = captivesStore()
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z and z:isAlive() then
            local uid = ZLRC.npcUid(z)
            if uid then
                local d = ZLRC.md(z)
                local entry = store[uid]
                if d.zrSubdued and not entry then
                    capture(z)                               -- just subdued: newly a captive
                elseif d.zrSubdued and entry then
                    entry.x, entry.y, entry.z = z:getX(), z:getY(), z:getZ()   -- follows it when dragged
                    keepHeldDown(z)
                elseif entry and not d.zrSubdued then
                    if d.zlrcCaptive then
                        store[uid] = nil                     -- was released by something other than us
                        d.zlrcCaptive = nil
                    else
                        applyCaptive(z, entry)               -- fresh shell for a stored captive
                    end
                end
            end
        end
    end
end

Events.OnTick.Add(function()
    tickN = tickN + 1
    if tickN % 30 ~= 0 then return end
    local ok, err = pcall(maintain)
    if not ok then ZLRC.log("captive maintain error: %s", tostring(err)) end
end)

-- 4. death clears the captive record ------------------------------------------------------------------------------------------
Events.OnZombieDead.Add(function(z)
    local uid = ZLRC.npcUid(z)
    if uid then captivesStore()[uid] = nil end
end)

-- immediate re-apply when A-Life binds a new shell to an actor -------------------------------------------------------------------
ZLRC.whenReady("A-Life Watchdog.bind",
    function()
        local PA = rawget(_G, "ProjectALife")
        return PA and PA.Watchdog and type(PA.Watchdog.bind) == "function"
    end,
    function()
        ZLRC.wrap(ProjectALife.Watchdog, "bind", function(orig)
            return function(uid, generation, shell, ...)
                local r1, r2 = orig(uid, generation, shell, ...)
                if ZLRC.enabled() and ZLRC.sv("persistCaptives", true) == true then
                    local entry = type(uid) == "string" and captivesStore()[uid] or nil
                    if entry and shell ~= nil then pcall(applyCaptive, shell, entry) end
                end
                return r1, r2
            end
        end)
    end)

-- ZomboRut hand-over: release + binding --------------------------------------------------------------------------------------------
ZLRC.whenReady("ZR_Subdued.release/getBinding",
    function() return rawget(_G, "ZR_Subdued") and type(ZR_Subdued.release) == "function" end,
    function()
        ZLRC.wrap(ZR_Subdued, "release", function(orig)
            return function(zombie, ...)
                local uid = ZLRC.npcUid(zombie)
                local r = orig(zombie, ...)
                if uid then
                    local d = ZLRC.md(zombie)
                    if d then
                        d.ProjectALifeOwned = true            -- ZomboRut set it false; the person belongs to A-Life again
                        d.zlrcCaptive = nil
                        d.ProjectALifeDownedUntilMs = nil     -- let A-Life's normal get-up logic take over
                    end
                    captivesStore()[uid] = nil
                    ZLRC.log("captive %s released back to A-Life", uid)
                end
                return r
            end
        end)
        if type(ZR_Subdued.getBinding) == "function" then
            ZLRC.wrap(ZR_Subdued, "getBinding", function(orig)
                return function(zombie, ...)
                    local b = orig(zombie, ...)
                    if b ~= nil then return b end
                    local uid = ZLRC.npcUid(zombie)
                    local e = uid and captivesStore()[uid]
                    return e and e.binding or nil
                end
            end)
        end
    end)
