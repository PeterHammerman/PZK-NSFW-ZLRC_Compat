-- ZLRC_NpcApproach  (item 11: NPC surrender / excitation encounters, part 2)
--
-- Gets a hostile A-Life NPC (an IsoZombie shell) to the player after the player has surrendered / been caught by excitation, and keeps
-- QUEUED NPCs near the player instead of letting A-Life send them wandering (once the player is shielded, ZLRC_Shield, A-Life drops its
-- target and falls back to patrol/wander).
--
-- Three drivers per NPC, switched AUTOMATICALLY when it makes no progress (the console says which one worked):
--   "alife"  ProjectALife.Movement.begin(record, shell, {x,y,z}, {pace="run"}). If A-Life refuses with "actor_action_conflict" (the NPC is
--            on a walk of its own) that walk is cancelled (ActionLedger.cancelActor, what Jeem does) and the call is repeated once.
--   "post"   ZLRC_NpcHold: a temporary garrison ORDER at the target spot - A-Life's own stance module walks the NPC there and holds it
--            ("hold_garrison"), exactly like an outpost guard; it fights threats within a leash and walks back. No wandering.
--   "native" the engine's zombie AI, as ZomboRut walks zombies in: setUseless(false) + setTarget(player) + setNoTeeth(true).
-- Order: queued (wait) NPCs: post -> alife -> native.   Walking-in NPCs (go): alife -> post -> native.
--
-- API:  A.begin(player, npc, opts) / A.status(npc) -> "moving"|"arrived"|"waiting"|"failed", reason / A.promote(npc) / A.stop(npc)
--   opts.wait = true : QUEUED: walk to opts.spot = {dx,dy} and hold that reserved spot until A.promote / A.stop.
--   A.promote(npc)   : queued -> full approach (up to the trigger range, status "arrived").

require "ZLRC/ZLRC_Core"
require "ZLRC/ZLRC_NpcHold"

ZLRC.Approach = ZLRC.Approach or {}
local A = ZLRC.Approach
local H = ZLRC.Hold
local active = setmetatable({}, { __mode = "k" })       -- [npc] = approach state
A.active = active

local ORDER_WAIT = { "post", "alife", "native" }
local ORDER_GO   = { "alife", "post", "native" }
local PROGRESS_MIN   = 0.35     -- tiles the distance must shrink within the progress window to count as progress
local PROGRESS_MS    = { alife = 2500, post = 6000, native = 3000 }
local REISSUE_MS     = 1000

local function now() return getTimestampMs() end

local function arriveDist()
    local v = tonumber(ZLRC.sv("npcTriggerRange", 1.6)) or 1.6
    if v < 1.0 then v = 1.0 end
    return v
end

local function timeoutMs() return (tonumber(ZLRC.sv("npcApproachTimeout", 25)) or 25) * 1000 end

local function alifeMovement()
    local PA = rawget(_G, "ProjectALife")
    local M = PA and PA.Movement
    if M and type(M.begin) == "function" then return M end
    return nil
end

local function driverName(a) return a.order[a.driver or 0] end

local function driverUsable(name, npc)
    if name == "alife" then return alifeMovement() ~= nil and ZLRC.record(npc) ~= nil end
    if name == "post" then
        return ZLRC.sv("npcHoldPost", true) == true and H ~= nil and type(H.pin) == "function"
            and ZLRC.record(npc) ~= nil and ZLRC.npcUid(npc) ~= nil
    end
    return true
end

local function nextUsable(a, from)
    for i = from, #a.order do
        if driverUsable(a.order[i], a.npc) then return i end
    end
    return nil
end

local function baseline(npc)
    ZLRC.call(npc, "setUseless", true)
    ZLRC.call(npc, "setNoTeeth", true)
    ZLRC.call(npc, "setTarget", nil)
    ZLRC.call(npc, "clearAggroList")
end

local function stopDriver(a)
    local d = a.driver and driverName(a)
    if d == "alife" then
        local M = alifeMovement()
        if M and type(M.stop) == "function" then pcall(M.stop, a.npc) end
    elseif d == "native" then
        baseline(a.npc)
    end
    if H and H.isPinned(a.npc) then H.release(a.npc) end      -- whichever driver set it
end

local function restoreWaitCollision(a)
    if a.waitCollisionChanged then
        ZLRC.call(a.npc, "setCollidable", a.waitWasCollidable)
        a.waitCollisionChanged = nil
    end
end

--- the point this NPC is sent to: the player's tile (go) or the player + its wait spot (wait)
local function goalOf(a)
    local p = a.player
    local x, y, z = p:getX(), p:getY(), p:getZ()
    if a.mode == "wait" and a.spot then return x + a.spot[1], y + a.spot[2], z end
    return x, y, z
end

function A.begin(player, npc, opts)
    if player == nil or npc == nil then return false end
    A.stop(npc)
    local t = now()
    local d = ZLRC.dist2d(player, npc)
    local mode = (opts and opts.wait) and "wait" or "go"
    local a = { player = player, npc = npc, t0 = t, run = not (opts and opts.run == false),
                best = d, progressAt = t, lastIssue = 0, status = "moving", switches = 0,
                mode = mode, spot = opts and opts.spot or nil, order = (mode == "wait") and ORDER_WAIT or ORDER_GO }
    if mode == "wait" then
        local wasCollidable = ZLRC.call(npc, "isCollidable")
        if type(wasCollidable) == "boolean" then
            a.waitWasCollidable = wasCollidable
            if wasCollidable then
                ZLRC.call(npc, "setCollidable", false)
                a.waitCollisionChanged = true
            end
        end
    end
    a.driver = nextUsable(a, 1)
    if not a.driver then a.status, a.reason = "failed", "no driver available" end
    active[npc] = a
    if a.status == "failed" then restoreWaitCollision(a) end
    ZLRC.info("approach start (%s): npc=%s dist=%.1f driver=%s", a.mode, tostring(ZLRC.npcUid(npc)), d, a.driver and driverName(a) or "none")
    return a.status ~= "failed"
end

function A.status(npc)
    local a = active[npc]
    if not a then return "failed", "not approaching" end
    return a.status, a.reason
end

function A.promote(npc, opts)
    local a = active[npc]
    if not a or a.mode ~= "wait" then return false end
    local t = now()
    stopDriver(a)                                   -- release the post / stop the wait mover; a fresh walk-in starts
    restoreWaitCollision(a)
    a.mode, a.spot, a.status, a.reason = "go", nil, "moving", nil
    a.order = ORDER_GO
    a.driver = nextUsable(a, 1)
    a.t0, a.progressAt, a.best, a.lastIssue = t, t, ZLRC.dist2d(a.player, npc), 0
    if opts and opts.run ~= nil then a.run = opts.run end
    if not a.driver then a.status, a.reason = "failed", "no driver available" end
    ZLRC.info("approach promoted: npc=%s dist=%.1f driver=%s", tostring(ZLRC.npcUid(npc)), a.best, a.driver and driverName(a) or "none")
    return true
end

function A.stop(npc)
    local a = active[npc]
    if not a then
        if H and H.isPinned(npc) then H.release(npc) end
        return
    end
    active[npc] = nil
    stopDriver(a)
    restoreWaitCollision(a)
end

local function fail(a, why)
    a.status, a.reason = "failed", why
    ZLRC.info("approach failed: npc=%s %s", tostring(ZLRC.npcUid(a.npc)), tostring(why))
    stopDriver(a)
    restoreWaitCollision(a)
    a.driver = nil
end

local function issueAlife(a)
    local M = alifeMovement()
    local rec = ZLRC.record(a.npc)
    if not (M and rec) then return false end
    local x, y, z = goalOf(a)
    local function try()
        return pcall(M.begin, rec, a.npc, { x = x, y = y, z = z }, { pace = a.run and "run" or "walk", entranceClaim = false })
    end
    local ok, res, why = try()
    if ok and res == nil and why == "actor_action_conflict" then
        -- the NPC is on a walk of its own (patrol/wander): end it, then ask again (Jeem does the same before taking an NPC over)
        if H and H.cancelAction(a.npc) then ok, res, why = try() end
    end
    if not ok then ZLRC.log("alife Movement.begin error: %s", tostring(res)); return false end
    if res == nil then ZLRC.log("alife Movement.begin refused: %s", tostring(why)) end
    return res ~= nil
end

local function issuePost(a, t)
    if not (H and H.pin) then return false end
    local px, py, pz = a.player:getX(), a.player:getY(), a.player:getZ()
    local x, y
    if a.mode == "wait" and a.spot then
        x, y = px + a.spot[1], py + a.spot[2]
    else
        -- the post is a point 1.2 tiles from the player on the NPC's side
        local dx, dy = a.npc:getX() - px, a.npc:getY() - py
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 0.01 then dx, dy, len = 1, 0, 1 end
        x, y = px + dx / len * 1.2, py + dy / len * 1.2
    end
    local dx, dy = a.npc:getX() - x, a.npc:getY() - y
    local d = math.sqrt(dx * dx + dy * dy)
    -- not getting closer between two asks: its current walk is the one in the way
    if a.lastPostDist and d > a.lastPostDist - 0.3 and d > 2 then H.cancelAction(a.npc) end
    a.lastPostDist = d
    local force = a.mode == "wait" and (a.status == "waiting" or a.forcePost == true)
    a.forcePost = false
    return H.pin(a.npc, { x = x, y = y, z = pz }, { x = px, y = py, z = pz },
        { waiting = a.mode == "wait", force = force })
end

local function assertNative(a)
    local npc, p = a.npc, a.player
    ZLRC.call(npc, "setUseless", false)
    ZLRC.call(npc, "setNoTeeth", true)
    ZLRC.call(npc, "setCanWalk", true)
    ZLRC.call(npc, "setTarget", p)
end

local function reissue(a, t, every)
    if (t - a.lastIssue) < every then return end
    a.lastIssue = t
    local d = driverName(a)
    if d == "alife" then
        if not issueAlife(a) then a.progressAt = math.min(a.progressAt, t - PROGRESS_MS.alife - 1) end   -- unusable now: switch at once
    elseif d == "post" then
        if not issuePost(a, t) then a.progressAt = math.min(a.progressAt, t - PROGRESS_MS.post - 1) end
    else
        assertNative(a)
    end
end

local function step(a, t)
    if a.status ~= "moving" and a.status ~= "waiting" then return end
    local npc, p = a.npc, a.player
    if not (ZLRC.alive(npc) and ZLRC.alive(p)) then return fail(a, "NPC or player gone") end

    local d = ZLRC.dist2d(p, npc)
    if a.mode == "wait" then
        -- Queued NPCs hold at their individual reserved spot, not merely anywhere within range of the player.
        local gx, gy = goalOf(a)
        local dx, dy = npc:getX() - gx, npc:getY() - gy
        local goalDist = math.sqrt(dx * dx + dy * dy)
        if goalDist <= 0.9 then
            if a.status ~= "waiting" then
                ZLRC.info("approach: npc=%s holding reserved spot (player dist %.1f, via %s)", tostring(ZLRC.npcUid(npc)), d, tostring(driverName(a)))
            end
            a.status, a.progressAt, a.best, a.t0 = "waiting", t, goalDist, t
            reissue(a, t, REISSUE_MS)
            return
        end
        if a.status == "waiting" then          -- drifted away: walk back
            a.status, a.progressAt, a.best, a.t0, a.lastIssue = "moving", t, goalDist, t, 0
            a.forcePost = true
            ZLRC.info("approach: waiting npc=%s drifted %.1f tiles from reserved spot - pulled back", tostring(ZLRC.npcUid(npc)), goalDist)
        end
    elseif d <= arriveDist() then
        a.status = "arrived"
        ZLRC.info("approach arrived: npc=%s dist=%.2f after %.1fs via %s", tostring(ZLRC.npcUid(npc)), d, (t - a.t0) / 1000, tostring(driverName(a)))
        stopDriver(a)
        return
    end
    if (t - a.t0) > timeoutMs() then return fail(a, string.format("timeout (dist %.1f)", d)) end

    local name = driverName(a)
    local progressDistance = d
    if a.mode == "wait" then
        local gx, gy = goalOf(a)
        local dx, dy = npc:getX() - gx, npc:getY() - gy
        progressDistance = math.sqrt(dx * dx + dy * dy)
    end
    if progressDistance < a.best - PROGRESS_MIN then
        a.best, a.progressAt = progressDistance, t
    elseif (t - a.progressAt) > (PROGRESS_MS[name] or 2500) then
        local from = a.driver
        stopDriver(a)
        local nxt = nextUsable(a, from + 1)
        if not nxt then return fail(a, string.format("no progress with any driver (dist %.1f)", d)) end
        ZLRC.info("approach: no progress with %s (dist %.1f) -> switching to %s", name, d, a.order[nxt])
        a.driver, a.switches, a.progressAt, a.best, a.lastIssue, a.lastPostDist = nxt, a.switches + 1, t, progressDistance, 0, nil
        name = driverName(a)
    end
    reissue(a, t, name == "post" and 2000 or REISSUE_MS)
end

local tickAt = 0
Events.OnTick.Add(function()
    local t = now()
    if (t - tickAt) < 200 then return end
    tickAt = t
    for _, a in pairs(active) do
        local ok, err = pcall(step, a, t)
        if not ok then ZLRC.log("approach step error: %s", tostring(err)) end
    end
end)

-- the engine resets useless/target on its own schedule; re-assert from the shell's own update (as ZomboRut does for zombies)
Events.OnZombieUpdate.Add(function(z)
    local a = active[z]
    if a and (a.status == "moving" or a.status == "waiting") and a.driver and driverName(a) == "native" then pcall(assertNative, a) end
end)

return A
