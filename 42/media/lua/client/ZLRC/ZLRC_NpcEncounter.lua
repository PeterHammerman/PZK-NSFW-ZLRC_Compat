-- ZLRC_NpcEncounter  (item 11: NPC surrender / excitation encounters, part 3 of 3)
--
-- Hostile A-Life NPCs (encounters and raids alike - anything A-Life says is hostile to the player) get the same two "defeat" paths
-- that zombies have:
--
--   SURRENDER (ZomboRut)   - a player who gives up (hotkey/menu, or auto-surrender from zombies) or who is exhausted with a hostile
--                            NPC engaging them is no longer attacked. The hostile NPC(s) walk/run to the player and play a ZomboRut
--                            "Defeat" scene (hand items and clothes drop, bik window, then collapse -> escape with ZomboRut's ghost).
--   EXCITATION (ZomboLust) - a player whose ZomboLust excitation is high enough: a hostile NPC that reaches them triggers ZomboDesire's
--                            own contact scene (strip -> animation -> struggle minigame) instead of attacking.
--
-- State machine per player (ZLRC.Enc.sessions[player]):  pick -> approach -> launch -> scene -> between -> (pick ... | finish)
--   * QUEUE (surrender): every other hostile NPC in earshot is called in too and WAITS near the player (outside ZomboRut's scene-fade
--     cone) while the current one has its scene; only NPCs that had their turn are released back to A-Life.
--   * ZomboRut's own chain can launch an A-Life NPC as well (bridge on playSceneFromAttacker): it is routed through ZLRC_NpcSex so the
--     NPC is held/restored, and a friendly NPC it nominates is swapped for a hostile one.
--   * Everything NPC-specific is ours; every scene is played by ZomboRut / ZomboDesire themselves, through their own entry points:
--       ZR_API.giveUp / ZR_Surrender.holdForScene / ZomboRutScene.playSceneFromAttacker (via ZLRC.NpcSex.startForced)
--       ZomboDesire.collisionListener(player, zombie)
--   * While a session exists the player is shielded from A-Life NPCs (ZLRC_Shield). After the last scene a grace window keeps them
--     shielded (sandbox npcGraceSeconds) while ZomboRut's collapse/escape/ghost runs for the zombies.
--   * ZomboRut's give-up machine is held ("holdForScene") for the whole session: that stops its timer from ending the give-up while
--     the NPC is still walking in, and stops it from firing a scene on the NPC shell without our hold/restore. (Side effect, chosen
--     for reliability: the compatibility layer restores the hands-up emote while the NPC is waiting.)

require "ZLRC/ZLRC_Core"
require "ZLRC/ZLRC_Shield"
require "ZLRC/ZLRC_Pick"
require "ZLRC/ZLRC_NpcSex"
require "ZLRC/ZLRC_NpcApproach"

local E  = ZLRC.Enc
local S  = ZLRC.NpcSex
local A  = ZLRC.Approach
local ZomboRutScene = ZLRC.ZRS      -- lazy proxy

E.armedSince = E.armedSince or setmetatable({}, { __mode = "k" })     -- [player] = ms exhaustion+hostile first seen
E.lustRolled = E.lustRolled or setmetatable({}, { __mode = "k" })     -- [npc]    = ms of the last excitation roll for that NPC
E.finishedGiveUp = E.finishedGiveUp or setmetatable({}, { __mode = "k" })   -- [player] = true: this give-up already had its encounter
E.explained  = E.explained  or setmetatable({}, { __mode = "k" })     -- [player] = true: "why no encounter" was logged for this give-up
E.giveUpAt   = E.giveUpAt   or setmetatable({}, { __mode = "k" })     -- [player] = ms the current give-up was first seen
E.closing    = E.closing    or setmetatable({}, { __mode = "k" })     -- [player] = ms until which ZomboRut's own launcher may not use NPCs
E.spareSaid  = E.spareSaid  or setmetatable({}, { __mode = "k" })     -- [player] = true for this surrender

-- ------------------------------------------------------------------ install check
-- Item 11 touches ZLRC_Core, ZLRC_NpcIgnore, ZLRC_NpcSex and adds four files. If only some of them were replaced the encounter must not
-- run half-way (it would error every 250 ms): it reports exactly what is missing once and stays off.
local function installProblem()
    local missing = {}
    local function need(name, v) if type(v) ~= "function" then missing[#missing + 1] = name end end
    need("ZLRC.call (ZLRC_Core.lua)", ZLRC.call)
    need("ZLRC.hostileNow (ZLRC_Core.lua)", ZLRC.hostileNow)
    need("ZLRC.exhaustion (ZLRC_Core.lua)", ZLRC.exhaustion)
    need("ZLRC.shieldReason (ZLRC_Shield.lua)", ZLRC.shieldReason)
    need("NpcSex.forcedPool (ZLRC_NpcSex.lua)", S.forcedPool)
    need("NpcSex.startForced (ZLRC_NpcSex.lua)", S.startForced)
    need("Approach.begin (ZLRC_NpcApproach.lua)", A.begin)
    need("Approach.promote (ZLRC_NpcApproach.lua)", A.promote)
    need("NpcSex.syncWatchdog (ZLRC_NpcSex.lua)", S.syncWatchdog)
    need("ZLRC.satisfy (ZLRC_Core.lua)", ZLRC.satisfy)
    need("Hold.pin (ZLRC_NpcHold.lua)", ZLRC.Hold and ZLRC.Hold.pin)
    if S.VERSION ~= "item11-r18" then missing[#missing + 1] = "ZLRC_NpcSex.lua is an older version (" .. tostring(S.VERSION) .. ")" end
    if #missing == 0 then return nil end
    return table.concat(missing, "; ")
end
E.installProblem = installProblem()
if E.installProblem then
    ZLRC.info("ITEM 11 DISABLED - mixed install. Missing/outdated: %s. Copy ALL files of the new release over the old ones.", E.installProblem)
else
    ZLRC.info("item 11 (NPC surrender / excitation encounters) loaded, NpcSex=%s", tostring(S.VERSION))
end

local function now() return getTimestampMs() end
local function sv(name, default) return ZLRC.sv(name, default) end

-- ------------------------------------------------------------------ small readers
local function zrSur()
    local zs = rawget(_G, "ZR_Surrender")
    if zs and type(zs.isActive) == "function" and type(zs.holdForScene) == "function" then return zs end
    return nil
end

--- "surrender" | "collapse" | "escape" | nil
local function surrenderPhase(player)
    local zs = zrSur()
    if not zs then return nil end
    local ok, act = pcall(zs.isActive, player)
    if not ok or act ~= true then return nil end
    local ok2, ph = pcall(zs.getPhase, player)
    if ok2 and type(ph) == "string" then return ph end
    return "surrender"
end

local function surrenderSceneActive(player)
    local zs = zrSur()
    if not (zs and type(zs.getState) == "function") then return false end
    local ok, st = pcall(zs.getState, player)
    return ok and type(st) == "table" and st.sceneActive == true
end

local function inScene(player)
    if S.sessions[player] ~= nil then return true end
    local zrs = ZLRC.zrScene()
    return zrs ~= nil and type(zrs._active) == "table" and zrs._active[player] ~= nil
end

local function inVehicle(player)
    return ZLRC.call(player, "getVehicle") ~= nil
end

local function excitationOf(player)
    local ES = rawget(_G, "ZomboLust_ExcitationSystem")
    if not (ES and type(ES.getExcitation) == "function") then return nil end
    local ok, v = pcall(ES.getExcitation, player)
    if ok and type(v) == "number" then return v end
    return nil
end

local function isFem(o) return ZLRC.isFemale(o) end

local function npcBusy(npc)
    local d = ZLRC.md(npc)
    if not d then return true end
    if d.zlrcBusy or d.ProjectALifeCorpseOf ~= nil then return true end
    if ZLRC.isSubdued(npc) or ZLRC.isHusk(npc) then return true end
    return ZLRC.call(npc, "isOnFloor") == true or ZLRC.call(npc, "isKnockedDown") == true or ZLRC.call(npc, "isCrawling") == true
end

local function isExcluded(excluded, npc)
    return excluded ~= nil and (excluded[npc] == true or excluded[ZLRC.npcUid(npc)] == true)
end

local function excludeNpc(s, npc)
    if not (s and npc) then return end
    s.excluded[npc] = true
    local uid = ZLRC.npcUid(npc)
    if uid ~= nil then s.excluded[uid] = true end
end

--- Hostile, engaged (inside `radius`), usable A-Life NPCs, nearest first. `want(npc)` is an extra filter.
local function collect(player, radius, excluded, want)
    local out = {}
    local cell = getCell()
    local list = cell and cell:getZombieList()
    if not list then return out end
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local r2 = radius * radius
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z and ZLRC.isNpc(z) and ZLRC.alive(z) and not isExcluded(excluded, z) then
            local dx, dy = z:getX() - px, z:getY() - py
            local d2 = dx * dx + dy * dy
            if d2 <= r2 and math.abs(z:getZ() - pz) < 1.5 and not npcBusy(z)
               and ZLRC.hostileNow(z, player) and (want == nil or want(z)) then
                out[#out + 1] = { npc = z, d2 = d2 }
            end
        end
    end
    table.sort(out, function(a, b) return a.d2 < b.d2 end)
    return out
end

--- Failsafe: plain zombies (not A-Life NPCs) or friendly A-Life NPCs of another faction within sandbox npcDangerRadius of the player.
--- Hostile NPCs that are about to have a scene must lose interest in the player and fight those instead (their own A-Life logic does it
--- once they are released); no scene is started while this is > 0.
local dangerCache = setmetatable({}, { __mode = "k" })
local function dangerNear(player)
    local r = tonumber(sv("npcDangerRadius", 10)) or 10
    if r <= 0 then return 0 end
    local t = now()
    local c = dangerCache[player]
    if c and (t - c.t) < 500 then return c.n, c.what end
    local n, what = 0, nil
    local cell = getCell()
    local list = cell and cell:getZombieList()
    if list then
        local px, py, pz = player:getX(), player:getY(), player:getZ()
        local r2 = r * r
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if z and ZLRC.alive(z) then
                local dx, dy = z:getX() - px, z:getY() - py
                if dx * dx + dy * dy <= r2 and math.abs(z:getZ() - pz) < 1.5 then
                    if not ZLRC.isNpc(z) then
                        if not (ZLRC.isSubdued(z) or ZLRC.isHusk(z)) then
                            n = n + 1; what = what or "zombie"
                        end
                    elseif not npcBusy(z) and ZLRC.friendlyOrAllied(z, player) == true then
                        n = n + 1; what = what or "other-faction NPC"
                    end
                end
            end
        end
    end
    dangerCache[player] = { t = t, n = n, what = what }
    return n, what
end

local function surrenderWant(player)
    return function(z)
        local fp = S.forcedPool
        if type(fp) ~= "function" then return false end        -- reported once by the install check below
        local pool = fp(player, z)
        return type(pool) == "table" and #pool > 0
    end
end
local function lustWant(player)      return function(z) return isFem(z) ~= isFem(player) end end

-- ------------------------------------------------------------------ session handling
local function setState(player, s, state)
    s.state, s.stateAt = state, now()
    ZLRC.info("encounter[%s]: -> %s (taker=%s, scenes=%d)", s.kind, state, s.taker and tostring(ZLRC.npcUid(s.taker)) or "-", s.takers)
end

local function releaseHold(player, s)
    if not s.held then return end
    s.held = false
    local zs = zrSur()
    if zs and surrenderPhase(player) == "surrender" and not inScene(player) then
        local release = zs.holdForExternalSceneChain or zs.holdForScene
        if type(release) == "function" then pcall(release, player, false) end
    end
end

local function lustRelease(s)
    local h = s.lustHold
    s.lustHold = nil
    if not h then return end
    local d = ZLRC.md(h.npc)
    if d then
        d.zlrcBusy = nil
        if h.hadCorpseOf == nil then d.ProjectALifeCorpseOf = nil end
    end
end

local function finish(player, s, reason)
    if E.sessions[player] ~= s then return end
    if s.taker then A.stop(s.taker) end
    for z in pairs(s.queue) do A.stop(z) end                       -- NPCs that never had their turn go back to A-Life
    s.queue = setmetatable({}, { __mode = "k" })
    s.reservedSpots, s.spotByNpc = {}, setmetatable({}, { __mode = "k" })
    lustRelease(s)
    releaseHold(player, s)
    local t = now()
    if s.kind == "surrender" and s.takers > 0 then E.closing[player] = t + 30000 end   -- ZomboRut's chain must not start more NPC scenes now
    local graceS = (s.takers > 0) and (tonumber(sv("npcGraceSeconds", 200)) or 200) or 2
    if graceS > 0 then E.graceUntil[player] = math.max(E.graceUntil[player] or 0, t + graceS * 1000) end
    local cd = (s.takers > 0) and (tonumber(sv("npcDefeatCooldown", 60)) or 60) or 30     -- no scene happened: do not retry at once
    E.cooldownUntil[player] = t + cd * 1000
    E.armedSince[player] = nil
    E.sessions[player] = nil
    -- one encounter per give-up (a danger abort may start again once it is gone)
    if s.kind == "surrender" and not tostring(reason):find("danger", 1, true) and surrenderPhase(player) == "surrender" then
        E.finishedGiveUp[player] = true
    end
    ZLRC.info("encounter[%s] finished: %s (scenes=%d, grace=%ds, cooldown=%ds)", s.kind, tostring(reason), s.takers, graceS, cd)
end

local function newSession(player, kind)
    local s = { kind = kind, state = "pick", t0 = now(), stateAt = now(), takers = 0, held = false,
                excluded = setmetatable({}, { __mode = "k" }), queue = setmetatable({}, { __mode = "k" }),
                waitFailed = setmetatable({}, { __mode = "k" }), queueAt = 0 }
    E.sessions[player] = s
    ZLRC.info("encounter[%s] started", kind)
    return s
end

local function startSurrenderSession(player, how)
    local s = newSession(player, "surrender")
    s.how = how
    local zs = zrSur()
    if zs then
        local hold = zs.holdForExternalSceneChain or zs.holdForScene
        local ok = type(hold) == "function" and pcall(hold, player, true)
        s.held = ok == true
    end
    return s
end

local function surrenderRadius()
    return math.max(20, tonumber(sv("npcCallRadius", 25)) or 25)
end

local function radiusFor(s)
    if s.kind == "lust" then return tonumber(sv("lustNpcRadius", 8)) or 8 end
    return surrenderRadius()
end

local function maxTakers(kind)
    local configured = math.max(1, math.floor(tonumber(sv("npcMaxTakers", 8)) or 8))
    if kind ~= "surrender" then return configured end
    local difficulty = ZLRC.zomboLustDifficulty()
    if difficulty == 1 then return 1 end
    if difficulty == 2 then return math.min(3, configured) end
    return configured
end

local function wantFor(player, s)
    if s.kind == "lust" then return lustWant(player) end
    return surrenderWant(player)
end

-- ------------------------------------------------------------------ ZomboDesire launch (excitation path)
local function lustEntry()
    local ZD = rawget(_G, "ZomboDesire")
    if ZD and type(ZD.collisionListener) == "function" then return ZD.collisionListener, "collisionListener" end
    local fn = rawget(_G, "ZomboDesireOnCollide")
    if type(fn) == "function" then return fn, "ZomboDesireOnCollide" end
    return nil
end

local function lustLaunch(player, npc)
    local fn, name = lustEntry()
    if not fn then return false, "ZomboDesire entry point not found" end
    local d = ZLRC.md(npc)
    if d and d.zlrcBanditFlag then d.isBandit = nil; d.zlrcBanditFlag = nil end      -- ZLRC_StripGuard's opt-out flag must not block a hostile NPC
    local ok, err = pcall(fn, player, npc)
    if not ok then return false, tostring(err) end
    return true, name
end

--- evidence that ZomboDesire took the NPC: it attached a ZombHuman brain, or locked the player's movement
local function lustTaken(player, npc)
    local d = ZLRC.md(npc)
    if d and d.zombHumanBrain ~= nil then return true end
    return ZLRC.call(player, "isBlockMovement") == true
end

local function lustHoldNpc(s, npc)
    local d = ZLRC.md(npc)
    if not d then return end
    s.lustHold = { npc = npc, hadCorpseOf = d.ProjectALifeCorpseOf }
    d.zlrcBusy = true
    d.ProjectALifeCorpseOf = ZLRC.npcUid(npc)            -- same "not an actor right now" marker NpcSex uses for scenes
end

-- ------------------------------------------------------------------ queue (surrender)
-- Wait spots are free, distinct tiles in a 2-3 square ring around the player.
local SPOTS = {}
for y = -3, 3 do
    for x = -3, 3 do
        local d2 = x * x + y * y
        if d2 >= 4 and d2 <= 9 then SPOTS[#SPOTS + 1] = { x, y } end
    end
end

local function releaseWaitSpot(s, npc)
    local spot = s.spotByNpc and s.spotByNpc[npc]
    if not spot then return end
    if s.reservedSpots then s.reservedSpots[spot.key] = nil end
    s.spotByNpc[npc] = nil
end

local function reserveWaitSpot(player, s, npc)
    local cell = getCell()
    if not cell then return nil end
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local tx0, ty0, tz = math.floor(px), math.floor(py), math.floor(pz)
    s.reservedSpots = s.reservedSpots or {}
    s.spotByNpc = s.spotByNpc or setmetatable({}, { __mode = "k" })
    for _, offset in ipairs(SPOTS) do
        local tx, ty = tx0 + offset[1], ty0 + offset[2]
        local dx, dy = tx + 0.5 - px, ty + 0.5 - py
        local d2 = dx * dx + dy * dy
        local key = string.format("%d:%d:%d", tx, ty, tz)
        if d2 >= 4 and d2 <= 9 and not s.reservedSpots[key] then
            local square = cell:getGridSquare(tx, ty, tz)
            local free = false
            if square and type(square.isFree) == "function" then
                local ok, value = pcall(square.isFree, square, false)
                free = ok and value == true
                if not ok and not s.waitSpotCheckWarning then
                    s.waitSpotCheckWarning = true
                    ZLRC.log("could not check whether a queued-NPC wait square is free: %s", tostring(value))
                end
            elseif square and not s.waitSpotCheckWarning then
                s.waitSpotCheckWarning = true
                ZLRC.log("queued-NPC wait square does not provide isFree")
            end
            if free then
                local spot = { key = key, dx = dx, dy = dy }
                s.reservedSpots[key] = npc
                s.spotByNpc[npc] = spot
                return { dx, dy }
            end
        end
    end
    return nil
end

local function queueUpdate(player, s)
    if s.kind ~= "surrender" or sv("npcQueue", true) ~= true then return end
    local t = now()
    if (t - s.queueAt) < 1000 then return end
    s.queueAt = t
    for z in pairs(s.queue) do
        local st = A.status(z)
        if not ZLRC.alive(z) or npcBusy(z) or isExcluded(s.excluded, z) or z == s.taker then
            s.queue[z] = nil
            A.stop(z)
            releaseWaitSpot(s, z)
        elseif st == "failed" and s.queue[z] ~= "held" then
            local held, why = false, "A-Life hold unavailable"
            local hold = ZLRC.Hold
            if hold and type(hold.pin) == "function" then
                local px, py, pz = player:getX(), player:getY(), player:getZ()
                held, why = hold.pin(z, { x = z:getX(), y = z:getY(), z = z:getZ() },
                    { x = px, y = py, z = pz }, { waiting = true, force = true })
            end
            releaseWaitSpot(s, z)
            if held then
                s.queue[z] = "held"
                ZLRC.info("encounter[surrender]: queued NPC %s could not reach its wait spot; holding its current position until its turn",
                    tostring(ZLRC.npcUid(z)))
            else
                s.waitFailed[z] = true
                s.queue[z] = nil
                A.stop(z)
                ZLRC.info("encounter[surrender]: queued NPC %s could not be held (%s); keeping it eligible for a direct approach",
                    tostring(ZLRC.npcUid(z)), tostring(why))
            end
        end
    end
    local queued = 0
    for _ in pairs(s.queue) do queued = queued + 1 end
    local room = maxTakers(s.kind) - s.takers - (s.taker and 1 or 0) - queued       -- only as many as can still take a turn
    if room <= 0 then return end
    local cands = collect(player, radiusFor(s), s.excluded, surrenderWant(player))
    for _, c in ipairs(cands) do
        local z = c.npc
        if room <= 0 then break end
        if z ~= s.taker and not s.queue[z] and not s.waitFailed[z] then
            local spot = reserveWaitSpot(player, s, z)
            if spot then
                if A.begin(player, z, { run = true, wait = true, spot = spot }) then
                    s.queue[z] = true
                    room = room - 1
                else
                    s.waitFailed[z] = true
                    A.stop(z)
                    releaseWaitSpot(s, z)
                    ZLRC.info("encounter[surrender]: queued NPC %s could not start a wait approach; keeping it eligible for a direct approach",
                        tostring(ZLRC.npcUid(z)))
                end
            end
        end
    end
end

-- ------------------------------------------------------------------ state machine
local function advance(player, s)
    local t = now()
    if not ZLRC.alive(player) then return finish(player, s, "player dead") end
    if inVehicle(player) then return finish(player, s, "player entered a vehicle") end
    if (t - s.t0) > 600000 then return finish(player, s, "encounter took too long") end

    -- a scene started by ZomboRut's own launcher (routed through the bridge below) while we were not launching one: adopt it
    if s.kind == "surrender" and s.state ~= "scene" and s.state ~= "launch" then
        local ns = S.sessions[player]
        if ns and ns.npc and not isExcluded(s.excluded, ns.npc) then
            if s.taker and s.taker ~= ns.npc then A.stop(s.taker) end
            s.taker = ns.npc
            s.takers = s.takers + 1
            excludeNpc(s, ns.npc)
            s.queue[ns.npc] = nil
            releaseWaitSpot(s, ns.npc)
            A.stop(ns.npc)
            ZLRC.info("encounter[surrender]: ZomboRut's own chain started a scene with NPC %s - adopted", tostring(ZLRC.npcUid(ns.npc)))
            return setState(player, s, "scene")
        end
    end
    if s.state == "pick" or s.state == "approach" or s.state == "scene" or s.state == "between" then queueUpdate(player, s) end

    if s.kind == "surrender" and s.state ~= "scene" and s.state ~= "between" and surrenderPhase(player) ~= "surrender" then
        return finish(player, s, "give-up ended")
    end

    if s.state == "pick" or s.state == "approach" or s.state == "launch" then
        local dn, what = dangerNear(player)
        if dn > 0 then return finish(player, s, string.format("danger nearby (%d %s within %s tiles) - NPCs lose interest and deal with it", dn, tostring(what), tostring(sv("npcDangerRadius", 10)))) end
    end

    if s.state == "pick" then
        local cands = collect(player, radiusFor(s), s.excluded, wantFor(player, s))
        if #cands == 0 then
            if s.takers > 0 or (t - s.stateAt) > 6000 then return finish(player, s, "no hostile NPC left") end
            return
        end
        if s.takers >= maxTakers(s.kind) then return finish(player, s, "max NPC scenes reached") end
        s.taker = cands[1].npc
        s.waitFailed[s.taker] = nil
        s.tries = 0
        s.queue[s.taker] = nil
        if not A.promote(s.taker, { run = true }) then A.begin(player, s.taker, { run = true }) end
        return setState(player, s, "approach")

    elseif s.state == "approach" then
        local npc = s.taker
        if not npc or not ZLRC.alive(npc) or npcBusy(npc) then
            if npc then excludeNpc(s, npc); A.stop(npc); releaseWaitSpot(s, npc) end
            s.taker = nil
            return setState(player, s, "pick")
        end
        local st, why = A.status(npc)
        if st == "arrived" then
            return setState(player, s, "launch")
        elseif st == "failed" then
            ZLRC.info("encounter[%s]: giving up on NPC %s (%s)", s.kind, tostring(ZLRC.npcUid(npc)), tostring(why))
            excludeNpc(s, npc); A.stop(npc); releaseWaitSpot(s, npc); s.taker = nil
            return setState(player, s, "pick")
        end

    elseif s.state == "launch" then
        local npc = s.taker
        A.stop(npc)
        if s.kind == "surrender" then
            local ok = S.startForced(player, npc, true)
            if ok then
                s.takers = s.takers + 1
                excludeNpc(s, npc)
                releaseWaitSpot(s, npc)
                return setState(player, s, "scene")
            end
            ZLRC.info("encounter[surrender]: no ZomboRut scene could be started with NPC %s", tostring(ZLRC.npcUid(npc)))
            excludeNpc(s, npc); releaseWaitSpot(s, npc); s.taker = nil
            return setState(player, s, "pick")
        end
        -- excitation path
        s.tries = (s.tries or 0) + 1
        local ok, how = lustLaunch(player, npc)
        ZLRC.info("encounter[lust]: ZomboDesire launch attempt %d via %s -> %s", s.tries, tostring(how), tostring(ok))
        if not ok then
            excludeNpc(s, npc); s.taker = nil
            return finish(player, s, "ZomboDesire launch failed: " .. tostring(how))
        end
        return setState(player, s, "lustwait")

    elseif s.state == "lustwait" then
        local npc = s.taker
        if npc and lustTaken(player, npc) then
            s.takers = s.takers + 1
            excludeNpc(s, npc)
            lustHoldNpc(s, npc)
            return setState(player, s, "lustscene")
        end
        if (t - s.stateAt) > 2500 then
            -- ZomboDesire declined (lost its own bite-vs-animation roll, gender gate, player state gate, ...): retry a few times
            if npc and ZLRC.alive(npc) and (s.tries or 0) < 5 then
                if ZLRC.dist2d(player, npc) > (tonumber(sv("npcTriggerRange", 1.6)) or 1.6) + 0.8 then
                    A.begin(player, npc, { run = true })
                    return setState(player, s, "approach")
                end
                return setState(player, s, "launch")
            end
            if npc then excludeNpc(s, npc) end
            s.taker = nil
            return finish(player, s, "ZomboDesire did not start a scene (the NPC simply attacks, like a zombie that lost its roll)")
        end

    elseif s.state == "lustscene" then
        local npc = s.taker
        local d = npc and ZLRC.md(npc)
        local ended = (t - s.stateAt) > 4000 and not lustTaken(player, npc or player)
        if ended or (t - s.stateAt) > 240000 or not npc or not ZLRC.alive(npc) then
            if ended then
                ZLRC.satisfy(player)
            end
            lustRelease(s)
            s.taker = nil
            s.sceneEndAt = t
            return setState(player, s, "between")
        end

    elseif s.state == "scene" then
        if not inScene(player) then
            s.taker = nil
            s.sceneEndAt = t
            return setState(player, s, "between")
        end

    elseif s.state == "between" then
        if (t - (s.sceneEndAt or t)) < 1200 then return end          -- let ZomboRut / ZomboDesire finish their own end-of-scene work
        if s.kind == "surrender" then
            if surrenderPhase(player) ~= "surrender" then return finish(player, s, "ZomboRut moved on (collapse/escape)") end
            if s.takers >= maxTakers(s.kind) then return finish(player, s, "max NPC scenes reached") end
        else
            local ex = excitationOf(player)
            if not ex or ex < (tonumber(sv("lustNpcMinExcitation", 40)) or 40) or s.takers >= maxTakers(s.kind) then
                return finish(player, s, "scene(s) done")
            end
        end
        return setState(player, s, "pick")
    end
end

-- ------------------------------------------------------------------ trigger detection
local function zrDefeatAllowed()
    local t = SandboxVars and SandboxVars.ZomboRut
    if t and t.enableMod == false then return false end
    local zs = zrSur()
    if not zs then return false end
    if type(zs.exhaustActive) == "function" then
        local ok, v = pcall(zs.exhaustActive)
        if ok and v ~= true then return false end        -- ZomboRut "defeat mode" without the exhaustion route
    end
    return true
end

local function giveUp(player)
    local api = rawget(_G, "ZR_API")
    if api and type(api.giveUp) == "function" and type(api.Source) == "table" then
        local ok, res, why = pcall(api.giveUp, player, { source = api.Source.ATTACKED })
        if ok and res == true then return true end
        return false, ok and tostring(why) or tostring(res)
    end
    local zs = zrSur()
    if zs and type(zs.start) == "function" then
        local ok, res = pcall(zs.start, player, true, { source = "attacked" })
        return ok and res == true, "ZR_Surrender.start"
    end
    return false, "ZomboRut give-up API missing"
end

--- Why did a give-up not turn into an encounter? Logged once per give-up (the question "K sometimes only stops the attack").
local function explain(player)
    local t = now()
    local r = surrenderRadius()
    local total, inRange, withScene, nearest = 0, 0, 0, nil
    local cell = getCell()
    local list = cell and cell:getZombieList()
    if list then
        local px, py = player:getX(), player:getY()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if z and ZLRC.isNpc(z) and ZLRC.alive(z) and ZLRC.hostileNow(z, player) then
                local d = ZLRC.dist2d(player, z)
                total = total + 1
                if not nearest or d < nearest then nearest = d end
                if d <= r then
                    inRange = inRange + 1
                    if not npcBusy(z) and #S.forcedPool(player, z) > 0 then withScene = withScene + 1 end
                end
            end
        end
    end
    local dn, what = dangerNear(player)
    ZLRC.info("give-up without an NPC encounter: hostile NPCs known=%d, within %d tiles=%d, usable (free + a scene exists)=%d, nearest=%s, danger=%d%s, defeatOn=%s, joinGiveUp=%s, sceneActive=%s, finishedThisGiveUp=%s",
        total, r, inRange, withScene, nearest and string.format("%.1f", nearest) or "-", dn, what and (" (" .. what .. ")") or "",
        tostring(sv("npcDefeatEnabled", true)), tostring(sv("npcJoinGiveUp", true)), tostring(surrenderSceneActive(player)), tostring(E.finishedGiveUp[player] == true))
end

local function detect(player)
    if E.installProblem then return end
    local t = now()
    if inScene(player) or inVehicle(player) then E.armedSince[player] = nil; return end

    local phase = surrenderPhase(player)
    local defeatOn = sv("npcDefeatEnabled", true) == true

    if phase ~= "surrender" then
        -- the give-up is over: the next one is a new encounter (closing flag / "already had one" / diagnostics reset)
        E.finishedGiveUp[player], E.explained[player], E.giveUpAt[player] = nil, nil, nil
        E.spareSaid[player] = nil
        if (E.closing[player] or 0) > 0 then E.closing[player] = nil end
    end

    -- A) the player is already giving up (hotkey / menu / zombies): hostile NPCs in earshot join like zombies do.
    --    A give-up is the player's own decision: the cooldown that spaces out AUTOMATIC encounters does not apply to it.
    if phase == "surrender" then
        E.giveUpAt[player] = E.giveUpAt[player] or t
        if E.finishedGiveUp[player] then return end
        if defeatOn and sv("npcJoinGiveUp", true) == true and not surrenderSceneActive(player) then
            if dangerNear(player) == 0 then
                local cands = collect(player, surrenderRadius(), nil, surrenderWant(player))
                if #cands > 0 then
                    if not E.spareSaid[player] then
                        E.spareSaid[player] = true
                        local ok, err = pcall(function() player:Say("Spare me") end)
                        if not ok then ZLRC.log("could not display surrender speech: %s", tostring(err)) end
                    end
                    if not E.sessions[player] then startSurrenderSession(player, "joined give-up") end
                    return
                end
            end
        end
        if not E.explained[player] and (t - E.giveUpAt[player]) > 1500 then
            E.explained[player] = true
            explain(player)
        end
        return
    end
    if phase ~= nil then return end     -- collapse / escape: leave it alone
    if (E.cooldownUntil[player] or 0) > t then return end

    -- automatic encounters (B, C) need the danger check too
    if dangerNear(player) > 0 then E.armedSince[player] = nil; return end

    -- B) exhausted + a hostile NPC engaging: auto-surrender (ZomboRut's exhaustion route, for NPC attackers)
    if defeatOn and zrDefeatAllowed() then
        local ex = ZLRC.exhaustion(player)
        local need = (tonumber(sv("npcDefeatExhaustion", 85)) or 85) / 100
        if ex and ex >= need then
            local cands = collect(player, tonumber(sv("npcEngageRadius", 6)) or 6, nil, surrenderWant(player))
            if #cands > 0 then
                E.armedSince[player] = E.armedSince[player] or t
                if (t - E.armedSince[player]) >= 1500 then
                    E.armedSince[player] = nil
                    local chance = tonumber(sv("npcDefeatChance", 100)) or 100
                    if ZombRand(100) < chance then
                        local ok, why = giveUp(player)
                        if ok then
                            ZLRC.info("exhausted (%.0f%%) with a hostile NPC at %.1f tiles -> surrender", ex * 100, math.sqrt(cands[1].d2))
                            startSurrenderSession(player, "exhaustion")
                        else
                            ZLRC.info("auto-surrender refused: %s", tostring(why))
                            E.cooldownUntil[player] = t + 5000
                        end
                    else
                        E.cooldownUntil[player] = t + 10000
                    end
                end
                return
            end
        end
        E.armedSince[player] = nil
    end

    -- C) excitation: chance scales with ZomboLust excitation, per hostile NPC, re-rolled every 20 s
    if sv("lustNpcEnabled", true) == true then
        local ex = excitationOf(player)
        local minEx = tonumber(sv("lustNpcMinExcitation", 40)) or 40
        if ex and ex >= minEx and lustEntry() ~= nil then
            local cands = collect(player, tonumber(sv("lustNpcRadius", 8)) or 8, nil, lustWant(player))
            for _, c in ipairs(cands) do
                local last = E.lustRolled[c.npc]
                if not last or (t - last) > 20000 then
                    E.lustRolled[c.npc] = t
                    local chance = (tonumber(sv("lustNpcChance", 100)) or 100) * (ex / 100)
                    if ZombRand(100) < chance then
                        ZLRC.info("excitation %.0f%% with hostile NPC %s at %.1f tiles -> lust encounter", ex, tostring(ZLRC.npcUid(c.npc)), math.sqrt(c.d2))
                        newSession(player, "lust")
                        return
                    end
                end
            end
        end
    end
end

-- ------------------------------------------------------------------ ZomboRut's own chain launcher and A-Life NPCs
-- ZomboRut treats every IsoZombie as a possible aggressor, and an A-Life NPC is one: during a give-up its chain nominates the nearest
-- one and calls ZomboRutScene.playSceneFromAttacker itself - without the hold/restore A-Life needs (the NPC would be lost) and possibly
-- with a friendly NPC. Two wrappers fix that:
--   * zombieScenesBlocked : an A-Life NPC is never "a plain zombie whose defeat scenes are disabled" while ours / a give-up is active, so
--                           NPC encounters do not depend on ZomboRut's "zombie defeat" switch (this patch has its own switches).
--   * playSceneFromAttacker (bridge) : a launch for an A-Life NPC that did not come from this patch is routed through ZLRC_NpcSex.
--       hostile NPC          -> played (held/restored properly)
--       friendly/neutral NPC -> swapped for the nearest hostile NPC, or refused ("defeat-disabled": ZomboRut ends the give-up normally)
--       while this patch is closing the encounter (max scenes reached / nobody left) -> refused, so ZomboRut ends normally too.
local function ours()
    for _, v in pairs(ZLRC._npcScene or {}) do if v then return true end end
    return false
end

local function anyGiveUp()
    local zs = zrSur()
    if zs and type(zs.activeCharacters) == "function" then
        local ok, list = pcall(zs.activeCharacters)
        return ok and type(list) == "table" and #list > 0
    end
    return false
end

ZLRC.whenReady("ZomboRutScene.zombieScenesBlocked (NPC pass-through)",
    function() local z = ZLRC.zrScene(); return z ~= nil and type(z.zombieScenesBlocked) == "function" end,
    function()
        ZLRC.wrap(ZLRC.zrScene(), "zombieScenesBlocked", function(orig)
            return function(obj, ...)
                if ZLRC.enabled() and not E.installProblem and sv("npcDefeatEnabled", true) == true
                   and obj ~= nil and ZLRC.isNpc(obj) and (ours() or anyGiveUp()) then
                    return false
                end
                return orig(obj, ...)
            end
        end)
    end)

ZLRC.whenReady("ZomboRutScene.playSceneFromAttacker (NPC bridge)",
    function() local z = ZLRC.zrScene(); return z ~= nil and type(z.playSceneFromAttacker) == "function" end,
    function()
        ZLRC.wrap(ZLRC.zrScene(), "playSceneFromAttacker", function(orig)
            return function(player, attacker, sceneId, ...)
                if not (ZLRC.enabled() and not E.installProblem and player ~= nil and attacker ~= nil
                        and sv("npcDefeatEnabled", true) == true and ZLRC.isNpc(attacker) and not ours()) then
                    return orig(player, attacker, sceneId, ...)
                end
                -- ZomboRut's own launcher picked an A-Life NPC
                if (E.closing[player] or 0) > now() then
                    ZLRC.info("bridge: ZomboRut wanted NPC %s but the NPC encounter is closing -> refused", tostring(ZLRC.npcUid(attacker)))
                    return false, "defeat-disabled"
                end
                if dangerNear(player) > 0 then
                    ZLRC.info("bridge: ZomboRut wanted NPC %s but zombies/other factions are close -> refused", tostring(ZLRC.npcUid(attacker)))
                    return false, "defeat-disabled"
                end
                local target = attacker
                local hostile = ZLRC.hostileNow(attacker, player) and not npcBusy(attacker)
                if not hostile and sv("npcChainGuard", true) == true then
                    local s = E.sessions[player]
                    local cands = collect(player, surrenderRadius(), s and s.excluded or nil, surrenderWant(player))
                    target = cands[1] and cands[1].npc or nil
                    if not target then
                        ZLRC.info("bridge: ZomboRut nominated non-hostile NPC %s and no hostile NPC is available -> refused", tostring(ZLRC.npcUid(attacker)))
                        return false, "defeat-disabled"
                    end
                    ZLRC.info("bridge: ZomboRut nominated non-hostile NPC %s -> using hostile NPC %s instead", tostring(ZLRC.npcUid(attacker)), tostring(ZLRC.npcUid(target)))
                end
                local ok
                local encounter = E.sessions[player]
                local surrenderChain = encounter and encounter.kind == "surrender"
                if surrenderChain and encounter.takers >= maxTakers("surrender") then
                    E.closing[player] = now() + 30000
                    ZLRC.info("bridge: hostile NPC chain reached its difficulty limit (%d scenes) -> refused another NPC scene",
                        encounter.takers)
                    return false, "defeat-disabled"
                end
                if target == attacker and type(sceneId) == "string" then
                    ok = S.start(player, target, sceneId, "attacker", { forced = true, surrenderChain = surrenderChain == true })
                end
                if not ok then ok = S.startForced(player, target, surrenderChain == true) end
                if ok then
                    ZLRC.info("bridge: ZomboRut's chain launch for NPC %s played through ZLRC", tostring(ZLRC.npcUid(target)))
                    return true
                end
                return false, "npc-launch-failed"
            end
        end)
    end)

-- After every scene ZomboRut clears its "scene active" flag itself; keep its give-up machine held while the NPC chain continues, so its
-- timer cannot end the give-up and its own chain does not start a scene behind our back.
ZLRC.whenReady("ZomboRut end callback (NPC chain re-hold)",
    function() local z = ZLRC.zrScene(); return z ~= nil and type(z.registerSceneEndCallback) == "function" end,
    function()
        ZLRC.zrScene().registerSceneEndCallback(function(player, _active, _result)
            local s = player and E.sessions[player]
            if s and s.kind == "surrender" and s.held and surrenderPhase(player) == "surrender" then
                local zs = zrSur()
                local hold = zs and (zs.holdForExternalSceneChain or zs.holdForScene)
                if type(hold) == "function" then pcall(hold, player, true) end
            end
        end)
    end)

-- ------------------------------------------------------------------ driver
local nextAt = setmetatable({}, { __mode = "k" })
Events.OnPlayerUpdate.Add(function(player)
    if player == nil then return end
    local t = now()
    if nextAt[player] and t < nextAt[player] then return end
    nextAt[player] = t + 250
    if ZLRC.has(player, "isLocalPlayer") and ZLRC.call(player, "isLocalPlayer") ~= true then return end

    local s = E.sessions[player]
    if not ZLRC.enabled() then
        if s then finish(player, s, "mod disabled") end
        return
    end
    local ok, err = pcall(function()
        if s and s.kind == "surrender" and s.held and surrenderPhase(player) == "surrender" and not inScene(player) then
            local playing = ZLRC.call(player, "getVariableBoolean", "EmotePlaying") == true
            local emote = ZLRC.call(player, "getVariableString", "emote")
            if not playing or emote ~= "surrender" then
                local poseAt = s.poseAt or 0
                if (t - poseAt) >= 1000 then
                    s.poseAt = t
                    ZLRC.call(player, "playEmote", "surrender")
                end
            end
        end
        if s then advance(player, s) else detect(player) end
    end)
    if not ok then
        -- never retry every 250 ms: in debug mode each caught error prints a full stack trace
        nextAt[player] = t + 10000
        if (t - (E.lastWarnAt or 0)) > 30000 then
            E.lastWarnAt = t
            ZLRC.warn("encounter error (backing off 10 s): %s", tostring(err))
        end
        if s and E.sessions[player] == s then finish(player, s, "error") end
    end
end)

Events.OnPlayerDeath.Add(function(player)
    local s = E.sessions[player]
    if s then finish(player, s, "player died") end
    E.graceUntil[player] = nil
end)

-- test / debug hooks
ZLRC.Encounter = { detect = detect, advance = advance, finish = finish, collect = collect }

return ZLRC.Encounter
