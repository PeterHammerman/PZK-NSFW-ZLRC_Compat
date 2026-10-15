-- ZLRC_NpcHold  (item 11, part 4: keep queued / approaching hostile NPCs where they are told to be)
--
-- Problem seen in play: once the player surrenders, A-Life stops the attack (ZLRC_Shield) and the hostile NPC falls back to its normal
-- decisions - patrol, wander, errands - so it walks away from the scene. A-Life's own Movement.begin cannot hold it either: while an
-- action runs (a patrol walk) A-Life asks no module ("actor_action_conflict" in the log).
--
-- What outpost guards use (and Jeem's residents): the NPC's record memory carries an ORDER - memory.stance = "garrison" with a
-- memory.garrisonPost - and A-Life's stance module walks the NPC to that post and keeps it there ("hold_garrison"); with a threat
-- around it fights within a leash of the post and walks back afterwards. This module sets exactly that, temporarily:
--
--   H.pin(npc, post, anchor)  save the NPC's own order fields, set a garrison order at `post`, end the walk it is on (so the order is read)
--   H.release(npc)            put the saved fields back
--   H.cancelAction(npc)       ActionLedger.cancelActor (what Jeem does before taking over an NPC)
--
-- Safety: the original fields are stored INSIDE the NPC's own memory (memory.zlrcSaved) and the pin flag is memory.zlrcPinned, so if the
-- game is saved/quit mid-encounter (A-Life persists the whole registry) the order is undone at the next game start (H.restoreStale).
-- The memory edit uses ActorRegistry.updateTransient (no disk write of its own).

require "ZLRC/ZLRC_Core"

ZLRC.Hold = ZLRC.Hold or {}
local H = ZLRC.Hold
H.pinned = H.pinned or setmetatable({}, { __mode = "k" })       -- [npc] = { uid, post, at }

-- the order fields we touch (and give back)
local KEYS = { "stance", "stanceAnchor", "garrisonPost", "garrisonBounds", "holdPost", "stanceRole", "garrisonRest", "stanceFace", "behaviorProfile", "adminMode", "behavior", "moduleOverrides" }

local function now() return getTimestampMs() end

local function registry()
    local PA = rawget(_G, "ProjectALife")
    local R = PA and PA.ActorRegistry
    if R and type(R.read) == "function" and type(R.updateTransient) == "function" then return R end
    return nil
end

local function deep(v)
    if type(v) ~= "table" then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = deep(x) end
    return o
end

local function centre(p) return { x = math.floor(p.x) + 0.5, y = math.floor(p.y) + 0.5, z = p.z or 0 } end

--- edit an actor's memory through the registry (one retry on a revision conflict)
local function mutate(uid, fn)
    local R = registry()
    if not R or uid == nil then return false end
    for _ = 1, 2 do
        local rec = R.read(uid)
        if not rec then return false end
        local ok = R.updateTransient(uid, rec.revision, function(r)
            if type(r.memory) ~= "table" then r.memory = {} end
            fn(r.memory, r)
        end, true)
        if ok then return true end
    end
    return false
end

function H.cancelAction(npc)
    local PA = rawget(_G, "ProjectALife")
    local L = PA and PA.ActionLedger
    local R = registry()
    local uid = ZLRC.npcUid(npc)
    if not (L and R and uid and type(L.cancelActor) == "function") then return false end
    local rec = R.read(uid)
    if not rec then return false end
    local ok, n = pcall(L.cancelActor, rec.uid, rec.generation, "zlrc_hold")
    return ok and (tonumber(n) or 0) > 0
end

--- Give the NPC a garrison order at `post` ({x,y,z}); `anchor` is where it "belongs" (the player). Idempotent for the same post.
function H.pin(npc, post, anchor, opts)
    if npc == nil or type(post) ~= "table" then return false, "bad args" end
    local uid = ZLRC.npcUid(npc)
    if not uid then return false, "no A-Life uid" end
    local p = centre(post)
    local cur = H.pinned[npc]
    local force = opts and opts.force == true
    if cur and cur.uid == uid and cur.post.x == p.x and cur.post.y == p.y and not force then return true end
    local a = type(anchor) == "table" and anchor or post
    local ok = mutate(uid, function(m)
        if m.zlrcPinned ~= true then
            local saved = { has = {}, vals = {} }
            for _, k in ipairs(KEYS) do
                if m[k] ~= nil then saved.has[k] = true; saved.vals[k] = deep(m[k]) end
            end
            m.zlrcSaved = saved
        end
        m.zlrcPinned = true
        m.stance = "garrison"
        m.stanceAnchor = { x = a.x, y = a.y, z = a.z or 0 }
        m.garrisonPost = p
        m.garrisonBounds = nil
        local waiting = opts and opts.waiting == true
        m.holdPost = waiting
        m.stanceRole, m.garrisonRest, m.stanceFace = waiting and "guard" or nil, nil, nil
        if waiting then
            m.adminMode, m.behavior = "guard", "guard"
            local overrides = type(m.moduleOverrides) == "table" and deep(m.moduleOverrides) or {}
            for _, key in ipairs({ "fortify", "cqbsweep", "flee", "investigate", "regroup", "groupMarch", "patrolRest" }) do
                overrides[key] = "off"
            end
            m.moduleOverrides = overrides
        else
            m.adminMode, m.behavior = nil, nil
            m.moduleOverrides = nil
        end
        m.behaviorProfile = "patrol"   -- "an unknown profile means seek-and-destroy" (Jeem): real garrison members are 'patrol'
    end)
    if not ok then return false, "registry refused" end
    H.pinned[npc] = { uid = uid, post = p, at = now() }
    H.cancelAction(npc)             -- while a walk runs, A-Life asks no module: end it so the order is read
    ZLRC.info("hold: pinned npc=%s at (%.1f,%.1f)", tostring(uid), p.x, p.y)
    return true
end

local function restoreMemory(m)
    if m.zlrcPinned ~= true then return false end
    local s = type(m.zlrcSaved) == "table" and m.zlrcSaved or { has = {}, vals = {} }
    for _, k in ipairs(KEYS) do
        if s.has and s.has[k] then m[k] = deep(s.vals[k]) else m[k] = nil end
    end
    m.zlrcPinned, m.zlrcSaved = nil, nil
    return true
end

function H.release(npc)
    local cur = H.pinned[npc]
    H.pinned[npc] = nil
    local uid = (cur and cur.uid) or ZLRC.npcUid(npc)
    if not uid then return false end
    local did = false
    local ok = mutate(uid, function(m) did = restoreMemory(m) end)
    if ok and did then ZLRC.info("hold: released npc=%s", tostring(uid)) end
    return ok
end

function H.isPinned(npc) return H.pinned[npc] ~= nil end

--- undo orders left in the registry by a save/quit in the middle of an encounter
function H.restoreStale()
    local R = registry()
    if not (R and type(R.list) == "function") then return 0 end
    local n = 0
    for _, rec in ipairs(R.list()) do
        local m = type(rec.memory) == "table" and rec.memory or nil
        if m and m.zlrcPinned == true then
            if mutate(rec.uid, function(mm) restoreMemory(mm) end) then n = n + 1 end
        end
    end
    if n > 0 then ZLRC.info("hold: undid %d stale garrison order(s) left by a previous session", n) end
    return n
end

-- re-assert: A-Life's own writes (a new generation, a shelter ending) can clear the order
local tickAt = 0
Events.OnTick.Add(function()
    local t = now()
    if (t - tickAt) < 2000 then return end
    tickAt = t
    local R = registry()
    if not R then return end
    for npc, cur in pairs(H.pinned) do
        local rec = R.read(cur.uid)
        local m = rec and rec.memory
        if not (type(m) == "table" and m.zlrcPinned == true and m.stance == "garrison"
                and type(m.garrisonPost) == "table" and m.garrisonPost.x == cur.post.x and m.garrisonPost.y == cur.post.y) then
            local post = cur.post
            H.pinned[npc] = nil
            H.pin(npc, post, post)
        end
    end
end)

Events.OnGameStart.Add(function()
    local ok, err = pcall(H.restoreStale)
    if not ok then ZLRC.log("hold: restoreStale error: %s", tostring(err)) end
end)

return H
