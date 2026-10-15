-- ZLRC_NpcSex  (item 5)
-- Friendly / allied A-Life NPC -> ZomboRut's "ZR: Ask for Sex" menu.
-- Scenes are offered only for the exact player/NPC gender pair:
--     F+M : Holding, Standing Doggy, Spooning, Footjob, Doggy, Cowgirl
--     M+F : Holding, Standing Doggy, Spooning, Footjob, Doggy, Missionary
--     F+M : Missionary uses a dedicated FM scene and animation pair.
--     F+M / M+F : Blowjob is under "More..."; F+M also has Cowgirl (variant)
--     F+F : Cowgirl; Face sit and Reverse lotus are under "More..."
--     M+M : no options
--
-- Two launch routes, both ZomboRut's own scene engine:
--   "corpse": hold the NPC, spawn a husk copying its looks, and play the registered scene on that husk.
--   "attacker": use playSceneFromAttacker(player, npc, id), which hides the NPC, copies its clothes onto a husk, then restores it.
-- In both cases the NPC is first put on hold for A-Life (ProjectALifeCorpseOf marker + zlrcBusy), and afterwards returned to
-- A-Life's baseline shell state.

require "ZLRC/ZLRC_Core"
require "ZLRC/ZLRC_Pick"

local ZomboRutScene = ZLRC.ZRS      -- lazy proxy: ZomboRutScene is only reachable through require()

ZLRC.NpcSex = ZLRC.NpcSex or {}
local S = ZLRC.NpcSex
S.sessions = S.sessions or setmetatable({}, { __mode = "k" })     -- [player] = session
S.VERSION = "item11-r18"      -- ZLRC_NpcEncounter checks this: a mixed install of old/new files must be reported, not crash

local function ts() return getTimestampMs() end

-- Offered positions. For each, the first route that resolves for the exact gender pair wins.
local POSITIONS = {
    { key = "holding", fallbackLabel = "Holding", labelKey = "ContextMenu_ZR_Scene_Holding", routes = {
        { base = "Holding_Holding_Holding", mode = "corpse" },
    } },
    { key = "standingDoggy", fallbackLabel = "Standing Doggy", labelKey = "ContextMenu_ZR_Scene_StandingDoggy", routes = {
        { base = "StandingDoggy_StandingDoggy_StandingDoggy", mode = "corpse" },
    } },
    { key = "spooning", fallbackLabel = "Spooning", labelKey = "ContextMenu_ZR_Scene_Spooning", routes = {
        { base = "Spooning_Spooning_Spooning", mode = "corpse" },
    } },
    { key = "footjob", fallbackLabel = "Footjob", labelKey = "ContextMenu_ZR_Scene_Footjob", routes = {
        { base = "Footjob_Footjob_Footjob", mode = "corpse" },
    } },
    { key = "doggy", fallbackLabel = "Doggy", labelKey = "ContextMenu_ZLRC_NpcSex_Doggy", routes = {
        { base = "Sex_SubdueDoggy", mode = "attacker", shyRough = true },
    } },
    { key = "cowgirl", fallbackLabel = "Cowgirl", labelKey = "ContextMenu_ZR_Scene_Cowgirl", routes = {
        { base = "Cowgirl_Cowgirl_Cowgirl", mode = "corpse" },
        { base = "Sex_SubdueCowgirl", mode = "attacker", shyRough = true },
    } },
    { key = "missionary", fallbackLabel = "Missionary", labelKey = "ContextMenu_ZLRC_NpcSex_Missionary", routes = {
        { base = "Sex_SubdueMissionary", mode = "attacker", genders = "MF", shyRough = true },
        { base = "Sex_SubdueMissionary_FM", mode = "attacker", genders = "FM" },
    } },
    { key = "blowjob", fallbackLabel = "Blowjob", labelKey = "ContextMenu_ZLRC_NpcSex_Blowjob", more = true, routes = {
        { base = "DefeatBJ_DefeatBJ_DefeatBJ", mode = "attacker" },
    } },
    { key = "cowgirlVariant", fallbackLabel = "Cowgirl (variant)", labelKey = "ContextMenu_ZLRC_NpcSex_CowgirlVariant", more = true, routes = {
        { base = "DefeatForcedCowGirl_DefeatForcedCowGirl_DefeatForcedCowGirl", mode = "attacker", genders = "FM" },
    } },
    { key = "faceSit", fallbackLabel = "Face sit", labelKey = "ContextMenu_ZLRC_NpcSex_FaceSit", more = true, routes = {
        { base = "DefeatLesbianFaceSit_DefeatLesbianFaceSit_DefeatLesbianFaceSit", mode = "attacker", genders = "FF" },
    } },
    { key = "reverseLotus", fallbackLabel = "Reverse lotus", labelKey = "ContextMenu_ZLRC_NpcSex_ReverseLotus", more = true, routes = {
        { base = "DefeatRevLotus_DefeatRevLotus_DefeatRevLotus", mode = "attacker", genders = "FF" },
    } },
}
S.POSITIONS = POSITIONS

local function registerMissionaryFM()
    if not (ZomboRutScene and type(ZomboRutScene.register) == "function"
        and type(ZomboRutScene._scenes) == "table") then
        return false
    end

    local sceneId = "Sex_SubdueMissionary_FM"
    if not ZomboRutScene._scenes[sceneId] then
        ZomboRutScene.register(sceneId, {
            label = "Missionary",
            kind = "consensual",
            duration = 17,
            outroDuration = 5,
            forcedOrientation = "HeadEnd_onBack",
            soundProfile = "soft_moan",
            pregnancyRisk = true,
            exactGenderOnly = true,
            chains = { A = { "Intro", "Main", "Outro" } },
        })
    end

    local stageTicks = require "ZomboRut/ZR_StageTicks"
    local varOffsets = require "ZomboRut/ZR_VarOffsets"
    stageTicks[sceneId] = stageTicks[sceneId] or { intro = 300, main = 420, outro = 300, loops = 2 }
    varOffsets[sceneId] = varOffsets[sceneId]
        or { fwd = -0.9, yaw = 180.0, fullTicks = 1446, intros = { "A" }, outros = { "A" }, mains = {} }
    return true
end

ZLRC.whenReady("ZomboRut FM missionary scene registration",
    function()
        return ZLRC.zrScene() ~= nil
            and type(ZomboRutScene.register) == "function"
            and type(ZomboRutScene._scenes) == "table"
    end,
    function()
        registerMissionaryFM()
    end)

local function zrReady()
    return ZLRC.zrScene() ~= nil
        and type(ZomboRutScene.playSceneFromCorpse) == "function"
        and type(ZomboRutScene._resolveGender) == "function"
        and type(ZomboRutScene._scenes) == "table"
end

local function zrEnabled()
    local t = SandboxVars and SandboxVars.ZomboRut
    return not (t and t.enableMod == false)
end

local function inScene(player)
    return S.sessions[player] ~= nil
        or (ZomboRutScene and ZomboRutScene._active and ZomboRutScene._active[player] ~= nil)
end

local function gcode(obj) return ZLRC.isFemale(obj) and "F" or "M" end

local traitApiWarning = false
local function hasZRtrait(player, trait)
    local api = rawget(_G, "ZR_Trait")
    if not (api and type(api.has) == "function") then
        if not traitApiWarning then
            traitApiWarning = true
            ZLRC.warn("ZomboRut trait API is unavailable; Shy NPC-scene rules cannot be applied")
        end
        return false
    end
    local ok, has = pcall(api.has, player, trait)
    if not ok then
        ZLRC.log("could not read ZomboRut trait %s: %s", tostring(trait), tostring(has))
        return false
    end
    return has == true
end

local function hasCondom(player)
    local inventory = player and player:getInventory()
    return inventory ~= nil and inventory:getFirstType("BF.Condom") ~= nil
end

local function markZLRCScene(active, session)
    if type(active) ~= "table" then return end
    active.zlrcNpcScene = true
    active.noTrauma = true
    active.ctx = active.ctx or {}
    active.ctx.condomActive = session.condomActive == true
        and active.cfg ~= nil and active.cfg.pregnancyRisk == true or nil
end

-- eligibility -----------------------------------------------------------------------------------------------------------------
--- returns true, or false + reason (the reason is only used for debug logging)
local function eligible(player, npc, opts)
    if not ZLRC.isNpc(npc) or not ZLRC.alive(npc) then return false, "not a live A-Life NPC" end
    if ZLRC.isSubdued(npc) or ZLRC.isHusk(npc) then return false, "subdued/husk" end
    local d = ZLRC.md(npc)
    if d and d.zlrcBusy then return false, "busy" end
    local forced = opts and opts.forced == true
    -- forced (item 11, hostile NPC takes a surrendered player): friendliness is not required; the scene pool decides about gender pairs
    if not forced and gcode(player) == "M" and gcode(npc) == "M" then return false, "male+male has no scenes here" end
    if npc:isOnFloor() or npc:isKnockedDown() or npc:isCrawling() then return false, "NPC is down" end
    if forced then return true, "forced (hostile NPC takes surrendered/excited player)" end
    local friendly, why = ZLRC.friendlyOrAllied(npc, player)
    if not friendly then return false, why .. " (needs friendly or allied)" end
    return true, why
end

--- list of { id, mode, label } valid for this exact pair
local function resolve(player, npc)
    registerMissionaryFM()
    local out = {}
    local pair = gcode(player) .. gcode(npc)
    for _, pos in ipairs(POSITIONS) do
        for _, route in ipairs(pos.routes) do
            if route.genders == nil or route.genders == pair then
                local usable = true
                if route.mode == "attacker" and type(ZomboRutScene.playSceneFromAttacker) ~= "function" then usable = false end
                if usable and route.mode == "attacker" and type(ZomboRutScene.zombieScenesBlocked) == "function"
                   and ZomboRutScene.zombieScenesBlocked(npc) then usable = false end
                if usable then
                    local ok, id = pcall(ZomboRutScene._resolveGender, player, npc, route.base)
                    -- _resolveGender may "assume" a male partner for same-gender pairs; accept only an exact gender match
                    if ok and type(id) == "string" and id:sub(-2) == pair then
                        local cfg = ZomboRutScene._scenes[id]
                        local shy = hasZRtrait(player, "Innocent")
                        if cfg and not cfg.debugOnly
                           and not (shy and pair ~= "FF" and (cfg.isDefeat == true or route.shyRough == true)) then
                            out[#out + 1] = {
                                id = id,
                                mode = route.mode,
                                label = getTextOrNull(pos.labelKey) or pos.fallbackLabel,
                                more = pos.more,
                            }
                            break
                        end
                    end
                end
            end
        end
    end
    return out
end
S._resolve = resolve

-- A-Life displacement guard ---------------------------------------------------------------------------------------------------------
-- ZomboRut parks the NPC 50 tiles away for the scene and teleports it back afterwards. A-Life's Watchdog reads a jump of more than
-- Watchdog.maximumStep (20) tiles between two checks as "shell_displaced": it unbinds the shell, stores the NPC and later hydrates a
-- NEW shell (generation+1) somewhere else - while ZomboRut restores the old body as an ordinary zombie. Result seen in-game: duplicate /
-- vanished NPCs, NPCs coming back without their clothes. Fix: right after every park/restore we tell the Watchdog the shell's new position
-- (binding.lastPosition, the field it compares against), so no jump is ever seen.
function S.syncWatchdog(npc)
    if npc == nil then return false end
    local PA = rawget(_G, "ProjectALife")
    local W = PA and PA.Watchdog
    if not (W and type(W.bindings) == "table") then return false end
    local uid = ZLRC.npcUid(npc)
    local b = uid and W.bindings[uid]
    if type(b) ~= "table" then return false end
    local pos
    if type(W.adapters) == "table" and type(W.adapters.shellPosition) == "function" then
        local ok, p = pcall(W.adapters.shellPosition, b.shell or npc)
        if ok and type(p) == "table" then pos = p end
    end
    if pos == nil then pos = { x = npc:getX(), y = npc:getY(), z = npc:getZ() } end
    b.lastPosition = pos
    return true
end

-- hold / restore ------------------------------------------------------------------------------------------------------------------
local function hold(npc, snap)
    local d = ZLRC.md(npc)
    snap.hadCorpseOf = d.ProjectALifeCorpseOf
    d.zlrcBusy = true
    d.ProjectALifeCorpseOf = snap.uid                         -- "not an actor right now" for A-Life
    pcall(function() npc:setTarget(nil) end)
    pcall(function() npc:clearAggroList() end)
    pcall(function() npc:setAlpha(0.00392); npc:setTargetAlpha(0.00392) end)
    pcall(function() npc:setDoRender(false) end)
    pcall(function() npc:setCollidable(false) end)
    pcall(function() npc:setCanWalk(false) end)
    pcall(function() npc:setUseless(true); npc:setNoTeeth(true) end)
end

local function restore(npc, snap)
    if npc == nil then return end
    local d = ZLRC.md(npc)
    if d then
        d.zlrcBusy = nil
        d._zrHusk = nil
        if snap and snap.hadCorpseOf == nil then d.ProjectALifeCorpseOf = nil end
    end
    pcall(function() npc:setAlpha(1); npc:setTargetAlpha(1) end)
    pcall(function() npc:setDoRender(true) end)
    pcall(function() npc:setCollidable(true) end)
    -- A-Life's baseline shell state (what its own shell adapter/fence assert)
    pcall(function() npc:setUseless(true); npc:setNoTeeth(true); npc:setCanWalk(true) end)
    pcall(function() npc:setTarget(nil); npc:clearAggroList() end)
    pcall(function() npc:resetModelNextFrame() end)
end

-- husk ----------------------------------------------------------------------------------------------------------------------------
local function makeHusk(player, npc)
    if not addZombiesInOutfit then return nil end
    local list
    pcall(function()
        list = addZombiesInOutfit(player:getX(), player:getY(), player:getZ(), 1,
            "Naked" .. tostring(1 + ZombRand(101)), ZLRC.isFemale(npc) and 100 or 0,
            false, false, false, false, false, false, 1)
    end)
    local fresh = list and list:size() > 0 and list:get(0) or nil
    if not fresh then return nil end
    pcall(function() fresh:setAlpha(0.00392); fresh:setTargetAlpha(0.00392) end)
    pcall(function()                                          -- same looks as the NPC (skin, hair, face)
        local fv, nv = fresh:getHumanVisual(), npc:getHumanVisual()
        if fv and nv and fv.copyFrom then fv:copyFrom(nv) end
    end)
    pcall(function() fresh:resetModel(); fresh:resetModelNextFrame() end)
    pcall(function()                                          -- silent
        local desc = fresh:getDescriptor()
        if desc and desc.setVoicePrefix then desc:setVoicePrefix("NotAZombie") end
        local em = fresh:getEmitter()
        if em and em.stopAll then em:stopAll() end
        fresh:setDoDeathSound(false)
    end)
    pcall(function() fresh:Kill(nil, false) end)
    local body
    pcall(function()
        if fresh.becomeCorpseSilently then body = fresh:becomeCorpseSilently()
        elseif fresh.dieNetwork then body = fresh:dieNetwork(nil, nil, false, nil); if fresh.setOnDeathDone then fresh:setOnDeathDone(true) end end
    end)
    if not body then
        pcall(function() fresh:removeFromWorld() end)
        return nil
    end
    pcall(function()
        local d = body:getModData()
        for k in pairs(d) do d[k] = nil end
        d._zrHusk = true                                      -- also makes A-Life/Jeem ignore it (ZLRC_NpcIgnore)
    end)
    pcall(function() body:setAlpha(0.00392); body:setTargetAlpha(0.00392); body:setDoRender(false) end)
    return body
end

local function removeHusk(body)
    if body == nil then return end
    pcall(function() if body.removeFromSquare then body:removeFromSquare() end end)
    pcall(function() if body.removeFromWorld then body:removeFromWorld() end end)
end

local function forwardOf(character)
    local ok, forward = pcall(function() return character:getForwardDirection() end)
    if not ok or not forward then return nil end
    local okX, x = pcall(function()
        return forward.getX and forward:getX() or forward.x
    end)
    local okY, y = pcall(function()
        return forward.getY and forward:getY() or forward.y
    end)
    if not okX or not okY or type(x) ~= "number" or type(y) ~= "number" then return nil end
    local length = math.sqrt(x * x + y * y)
    if length < 0.001 then return nil end
    return { x = x / length, y = y / length }
end

local function lockForward(character, direction)
    if not (character and direction and type(character.setForwardDirection) == "function") then return end
    pcall(character.setForwardDirection, character, direction.x, direction.y)
end

local function addAdditionalPain(bodyPart, amount, sceneId)
    local ok, beforeOrError = pcall(function()
        if not bodyPart then error("body part unavailable") end
        local before = bodyPart:getAdditionalPain() or 0
        bodyPart:setAdditionalPain(math.min(100, before + amount))
        if type(syncBodyPart) == "function" then
            syncBodyPart(bodyPart, 0x00608200)
        end
        return before
    end)
    if not ok then
        ZLRC.log("NPC chain pain failed for %s: %s", tostring(sceneId), tostring(beforeOrError))
        return
    end
end

local function applyChainScenePain(player, sceneId, cfg)
    local ok, err = pcall(function()
        local damage = player:getBodyDamage()
        if not damage then error("player body damage unavailable") end
        local parts = damage:getBodyParts()
        if not parts then error("player body parts unavailable") end
        -- A small baseline ache on every body part represents the strain from each chain scene.
        for i = 0, parts:size() - 1 do
            addAdditionalPain(parts:get(i), 5, sceneId)
        end

        local id = string.lower(tostring(sceneId or ""))
        local oral = cfg and cfg.isOral == true
            or id:find("defeatbj", 1, true) ~= nil
            or id:find("facesit", 1, true) ~= nil
            or id:find("revlotus", 1, true) ~= nil
        local penetrative = not (cfg and cfg.nonPenetrative == true)
            and (cfg and cfg.pregnancyRisk == true
                or id:find("holding", 1, true) ~= nil
                or id:find("doggy", 1, true) ~= nil
                or id:find("cowgirl", 1, true) ~= nil
                or id:find("missionary", 1, true) ~= nil
                or id:find("spooning", 1, true) ~= nil)

        if oral then
            addAdditionalPain(damage:getBodyPart(BodyPartType.Head), 15, sceneId)
            addAdditionalPain(damage:getBodyPart(BodyPartType.Neck), 15, sceneId)
        elseif penetrative then
            addAdditionalPain(damage:getBodyPart(BodyPartType.Groin), 15, sceneId)
            addAdditionalPain(damage:getBodyPart(BodyPartType.Torso_Lower), 15, sceneId)
        end

        if type(player.addArmMuscleStrain) == "function" then
            player:addArmMuscleStrain(3)
        end
        if type(player.addBackMuscleStrain) == "function" then
            player:addBackMuscleStrain(3)
        end
        if type(player.addLegMuscleStrain) == "function" then
            player:addLegMuscleStrain(3)
        end
        ZLRC.info("NPC chain scene %s applied body-wide muscle strain pain%s",
            tostring(sceneId), oral and " plus head/neck pain" or (penetrative and " plus groin/lower torso pain" or ""))
    end)
    if not ok then
        ZLRC.log("NPC chain scene pain failed for %s: %s", tostring(sceneId), tostring(err))
    end
end

local function applyViciousNoCondomIntercourse(womb)
    local amountInMilliliters = ZombRand(10, 50)
    local amount = amountInMilliliters / 1000
    womb:haloText({
        text = getText("IGUI_BF_UI_Sperm") .. " " .. tostring(amountInMilliliters) .. " ml",
        style = "good",
    })
    womb.amount = math.min(womb.capacity, womb.amount + amount)
    womb.total = womb.total + amount
    womb:publishState()
    if not womb.pregnancyData then womb:impregnate() end
    ZLRC.log("Being Female condom bypassed for Vicious hostile NPC chain; condom left unused")
end

local function deferChainScenePain(player, sceneId, cfg)
    local function applyNextTick()
        Events.OnTick.Remove(applyNextTick)
        applyChainScenePain(player, sceneId, cfg)
    end
    Events.OnTick.Add(applyNextTick)
end

ZLRC.whenReady("Being Female Womb.intercourse (Vicious NPC chain condom rule)",
    function()
        local ok, module = pcall(require, "BF/components/Womb")
        local womb = ok and module and module.Womb
        return womb ~= nil and type(womb.prototype) == "table" and type(womb.prototype.intercourse) == "function"
    end,
    function()
        local module = require "BF/components/Womb"
        ZLRC.wrap(module.Womb.prototype, "intercourse", function(orig)
            return function(womb, ...)
                local player = womb and womb.player
                local session = player and S.sessions[player]
                if session and session.surrenderChain == true and session.ignoreCondom == true then
                    local inventory = player:getInventory()
                    if inventory and inventory:getFirstType("BF.Condom") ~= nil then
                        return applyViciousNoCondomIntercourse(womb)
                    end
                end
                return orig(womb, ...)
            end
        end)
        ZLRC.info("Being Female intercourse hook installed for Vicious hostile NPC chains")
    end)

ZLRC.whenReady("Being Female condom-aware NPC womb animation",
    function()
        local ok, module = pcall(require, "BF/components/Player")
        local playerClass = ok and module and module.Player
        return playerClass ~= nil and type(playerClass.prototype) == "table"
            and type(playerClass.prototype.hasItem) == "function"
    end,
    function()
        local module = require "BF/components/Player"
        ZLRC.wrap(module.Player.prototype, "hasItem", function(orig)
            return function(womb, itemName, recursive)
                local player = womb and womb.player
                local session = player and S.sessions[player]
                if session and itemName == "BF.Condom" then
                    return session.condomActive == true
                end
                return orig(womb, itemName, recursive)
            end
        end)
        ZLRC.info("Being Female womb animation now follows the NPC scene condom rule")
    end)

ZLRC.whenReady("ZomboLust trauma event isolation for NPC scenes",
    function()
        local desire = rawget(_G, "ZomboDesire")
        local handlers = desire and desire.EventMarkerModules
        return handlers ~= nil and type(handlers.ZLApplyTrauma) == "function"
    end,
    function()
        local handlers = ZomboDesire.EventMarkerModules
        ZLRC.wrap(handlers, "ZLApplyTrauma", function(orig)
            return function(action, ...)
                local player = action and action.character
                if player and S.sessions[player] then
                    ZLRC.log("suppressed ZomboLust zombie trauma event during ZLRC NPC scene")
                    return
                end
                return orig(action, ...)
            end
        end)
        ZLRC.info("ZomboLust zombie trauma event isolated from ZLRC NPC scenes")
    end)

-- start / finish -------------------------------------------------------------------------------------------------------------------
function S.start(player, npc, sceneId, mode, opts)
    if not (zrReady() and ZLRC.enabled()) then return false end
    if S.sessions[player] or inScene(player) then return false end
    local okE, why = eligible(player, npc, opts)
    if not okE then ZLRC.log("NPC scene refused: %s", tostring(why)); return false end
    local surrender = rawget(_G, "ZR_Surrender")
    local waitingPoseCleared = opts and opts.forced == true and surrender
        and type(surrender.setExternalSceneWaiting) == "function"
        and surrender.setExternalSceneWaiting(player, false) == true
    local uid = ZLRC.npcUid(npc)
    local snap = { x = npc:getX(), y = npc:getY(), z = npc:getZ(), uid = uid, banditPacified = false }

    hold(npc, snap)

    local encounter = ZLRC.Enc and ZLRC.Enc.sessions and ZLRC.Enc.sessions[player]
    local surrenderChain = (opts and opts.surrenderChain == true)
        or ((opts and opts.forced == true) and encounter and encounter.kind == "surrender")
    local ignoreCondom = surrenderChain == true and ZLRC.zomboLustDifficulty() == 3
    local session = {
        npc = npc,
        snap = snap,
        body = nil,
        t0 = ts(),
        forced = (opts and opts.forced == true) or nil,
        surrenderChain = surrenderChain or nil,
        ignoreCondom = ignoreCondom,
        condomActive = hasCondom(player) and not ignoreCondom,
        watchdogSyncAt = ts(),
    }
    S.sessions[player] = session

    local body
    if mode == "attacker" then
        -- ZomboRut parks the NPC itself and builds the husk from the NPC's own clothing
        ZLRC._npcScene[player] = true
        local ok, started = pcall(ZomboRutScene.playSceneFromAttacker, player, npc, sceneId)
        ZLRC._npcScene[player] = nil
        if not ok or not started then
            S.sessions[player] = nil
            restore(npc, snap)
            if waitingPoseCleared then surrender.setExternalSceneWaiting(player, true) end
            ZLRC.log("playSceneFromAttacker refused (%s)", tostring(started))
            return false
        end
        local act = ZomboRutScene._active and ZomboRutScene._active[player]
        markZLRCScene(act, session)
        S.syncWatchdog(npc)                                   -- ZomboRut just parked the NPC far away: not a "displaced shell"
        ZLRC.log("NPC scene %s (attacker route) started with %s", tostring(sceneId), tostring(uid))
        return true
    end

    body = makeHusk(player, npc)
    if not body then
        S.sessions[player] = nil
        restore(npc, snap)
        if waitingPoseCleared then surrender.setExternalSceneWaiting(player, true) end
        ZLRC.warn("could not create husk; NPC scene cancelled")
        return false
    end

    ZLRC._npcScene[player] = true                              -- read by ZLRC_CloakGuard at scene start
    session.body = body

    local ok, started = pcall(ZomboRutScene.playSceneFromCorpse, player, body, sceneId, { launchSource = "fromLive" })
    ZLRC._npcScene[player] = nil                               -- start callbacks already ran inside the call above
    if not ok or not started then
        S.sessions[player] = nil
        removeHusk(body)
        restore(npc, snap)
        if waitingPoseCleared then surrender.setExternalSceneWaiting(player, true) end
        ZLRC.log("playSceneFromCorpse refused (%s)", tostring(started))
        return false
    end

    -- Same bookkeeping ZomboRut keeps for live partners, so its own end-of-scene cleanup also puts things back.
    local act = ZomboRutScene._active and ZomboRutScene._active[player]
    if act then
        act.liveTargetSnapshot = snap
        act.liveOriginal       = npc
        act.corpseHusk         = body
        act.partnerIsBandit    = false
        markZLRCScene(act, session)
    end
    ZLRC.log("NPC scene %s (corpse route) started with %s", tostring(sceneId), tostring(uid))
    return true
end

local finalizeAt = setmetatable({}, { __mode = "k" })         -- [player] = ms

local function restoreNearbyCollisions(s)
    for npc in pairs(s.suppressedNpcs or {}) do
        ZLRC.call(npc, "setCollidable", true)
    end
    s.suppressedNpcs = nil
end

local function isolateNearbyNpcs(player, s)
    local cell = getCell()
    local list = cell and cell:getZombieList()
    if not list then return end
    s.suppressedNpcs = s.suppressedNpcs or setmetatable({}, { __mode = "k" })
    local nearby = setmetatable({}, { __mode = "k" })
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    for i = 0, list:size() - 1 do
        local npc = list:get(i)
        if npc and npc ~= s.npc and ZLRC.isNpc(npc) and ZLRC.alive(npc) then
            local dx, dy = npc:getX() - px, npc:getY() - py
            if dx * dx + dy * dy <= 16 and math.abs(npc:getZ() - pz) < 1.5 then
                nearby[npc] = true
                if not s.suppressedNpcs[npc] and ZLRC.call(npc, "isCollidable") == true then
                    s.suppressedNpcs[npc] = true
                    ZLRC.call(npc, "setCollidable", false)
                end
            end
        end
    end
    for npc in pairs(s.suppressedNpcs) do
        if not nearby[npc] then
            ZLRC.call(npc, "setCollidable", true)
            s.suppressedNpcs[npc] = nil
        end
    end
end

local function finalize(player)
    local s = S.sessions[player]
    S.sessions[player] = nil
    finalizeAt[player] = nil
    if not s then return end
    restoreNearbyCollisions(s)
    removeHusk(s.body)                                        -- idempotent; ZomboRut normally removed it already
    restore(s.npc, s.snap)
    S.syncWatchdog(s.npc)
    ZLRC.log("NPC %s restored to A-Life", tostring(s.snap and s.snap.uid))
end

local function applyShyChainEffects(player)
    if not hasZRtrait(player, "Innocent") then return end

    local stats = player:getStats()
    if stats then
        stats:set(CharacterStat.STRESS, 1.0)
    else
        ZLRC.warn("could not set maximum stress after Shy hostile NPC chain: player stats unavailable")
    end

    if hasZRtrait(player, "Traumatized") then return end
    local trauma = rawget(_G, "ZR_Trauma")
    if not (trauma and type(trauma.add) == "function") then
        ZLRC.warn("ZomboRut trauma API is unavailable; Shy hostile NPC chain could not apply trauma")
        return
    end
    local ok, changed, before = pcall(trauma.add, player, 1, false)
    if not ok then
        ZLRC.warn("could not apply ZomboRut trauma after Shy hostile NPC chain: %s", tostring(changed))
    elseif changed then
        ZLRC.info("Shy hostile NPC chain applied ZomboRut trauma (previous level %s) and maximum stress",
            tostring(before))
    else
        ZLRC.info("Shy hostile NPC chain set maximum stress; ZomboRut trauma rules suppressed a new trauma effect")
    end
end

ZLRC.whenReady("ZomboRut end callback (NpcSex)",
    function() return ZLRC.zrScene() ~= nil and type(ZomboRutScene.registerSceneEndCallback) == "function" end,
    function()
        ZomboRutScene.registerSceneEndCallback(function(player, active, result)
            local ns = S.sessions[player]
            if ns and type(active) == "table" and active.zlrcNpcScene and result == "Released"
               and not active.struggleEscaped then
                ZLRC.satisfy(player)
                if ns.surrenderChain then
                    deferChainScenePain(player, active.sceneId, active.cfg)
                    applyShyChainEffects(player)
                end
            end
            if S.sessions[player] and type(active) == "table" and active.zlrcNpcScene then
                finalizeAt[player] = ts() + 1500                -- let ZomboRut finish its own restore first
                S.syncWatchdog(S.sessions[player].npc)          -- ZomboRut already teleported the NPC back
            end
        end)
    end)

Events.OnTick.Add(function()
    local now = ts()
    for player, s in pairs(S.sessions) do
        if now - (s.watchdogSyncAt or 0) >= 500 then
            s.watchdogSyncAt = now
            S.syncWatchdog(s.npc)
        end
        local active = ZomboRutScene and ZomboRutScene._active and ZomboRutScene._active[player]
        if type(active) == "table" then
            markZLRCScene(active, s)
            if now - (s.collisionScanAt or 0) >= 250 then
                s.collisionScanAt = now
                isolateNearbyNpcs(player, s)
            end
        elseif s.suppressedNpcs then
            restoreNearbyCollisions(s)
        end
        if type(active) == "table" and active.zlrcNpcScene and active.anchor and active.partnerAnchor then
            local partner = active.partnerRef
            local lock = s.facingLock or {}
            lock.player = lock.player or forwardOf(player)
            lock.partner = lock.partner or (partner and forwardOf(partner))
            if lock.player or lock.partner then s.facingLock = lock end
            if s.facingLock then
                if s.facingLock.player then lockForward(player, s.facingLock.player) end
                lockForward(partner, s.facingLock.partner)
            end
        end
        local at = finalizeAt[player]
        if at and now >= at then
            pcall(finalize, player)
        elseif not at then
            -- safety net: scene vanished without an end callback, or NPC lost
            if (now - s.t0) > 5000 and not active then pcall(finalize, player) end
            if (now - s.t0) > 300000 then pcall(finalize, player) end
        end
    end
end)

-- NPC clothes stay on the NPC (item 11) ---------------------------------------------------------------------------------------------
-- For a zombie attacker ZomboRut strips the lower body for the scene and DROPS the clothing on the ground (and re-applies the visuals
-- at the end). For an A-Life NPC that means walking around without trousers afterwards. The visual strip for the scene itself is kept
-- (the NPC is hidden anyway, the husk shows it); only the dropping / removal of the real items is skipped for A-Life NPCs.
local function keepNpcClothes() return ZLRC.enabled() and ZLRC.sv("npcKeepClothes", true) == true end

ZLRC.whenReady("ZomboRutScene._dropLowerBodyVisualsAsItems (keep NPC clothes)",
    function() return ZLRC.zrScene() ~= nil and type(ZomboRutScene._dropLowerBodyVisualsAsItems) == "function" end,
    function()
        ZLRC.wrap(ZLRC.zrScene(), "_dropLowerBodyVisualsAsItems", function(orig)
            return function(attacker, ...)
                if attacker ~= nil and keepNpcClothes() and ZLRC.isNpc(attacker) then return 0 end
                return orig(attacker, ...)
            end
        end)
    end)

ZLRC.whenReady("ZomboRutScene._stripLowerBody (keep NPC clothes)",
    function() return ZLRC.zrScene() ~= nil and type(ZomboRutScene._stripLowerBody) == "function" end,
    function()
        ZLRC.wrap(ZLRC.zrScene(), "_stripLowerBody", function(orig)
            return function(attacker, ...)
                if attacker ~= nil and keepNpcClothes() and ZLRC.isNpc(attacker) then return 0 end
                return orig(attacker, ...)
            end
        end)
    end)

-- forced scenes (item 11) ----------------------------------------------------------------------------------------------------------
-- A HOSTILE NPC takes a surrendered / excited player. Scenes come from ZomboRut's own "force" family (the Defeat* scenes it plays for
-- zombies), launched through the same "attacker" route as above, with the NPC held for A-Life and restored afterwards.
local DEFEAT_BASES = {      -- scene ids as ZomboRut names them; only used when ZR_API.buildPool is unavailable
    "DefeatPunch_DefeatPunch_DefeatPunch",
    "DefeatBJ_DefeatBJ_DefeatBJ",
    "DefeatLunge_DefeatLunge_DefeatLunge",
    "DefeatLesbianFaceSit_DefeatLesbianFaceSit_DefeatLesbianFaceSit",
    "DefeatForcedCowGirl_DefeatForcedCowGirl_DefeatForcedCowGirl",
    "DefeatRevLotus_DefeatRevLotus_DefeatRevLotus",
}

--- list of scene ids ZomboRut can play for this exact player/NPC pair as a non-friendly ("force") scene
function S.forcedPool(player, npc)
    local out, seen = {}, {}
    if not zrReady() then return out end
    if type(ZomboRutScene._sameGenderBlocked) == "function" then
        local okB, blocked = pcall(ZomboRutScene._sameGenderBlocked, player, npc)
        if okB and blocked == true then return out end
    end
    local function add(id)
        if type(id) ~= "string" or seen[id] then return end
        local cfg = ZomboRutScene._scenes[id]
        if cfg == nil or cfg.debugOnly or cfg.corpseOnly or cfg.friendlyOnly or cfg.isUtility then return end
        seen[id] = true
        out[#out + 1] = id
    end
    local api = rawget(_G, "ZR_API")
    if api and type(api.buildPool) == "function" and type(api.Family) == "table" then
        local ok, pool = pcall(api.buildPool, player, npc, api.Family.FORCE)
        if ok and type(pool) == "table" then for _, id in ipairs(pool) do add(id) end end
    end
    if #out == 0 then
        for _, base in ipairs(DEFEAT_BASES) do
            local ok, id = pcall(ZomboRutScene._resolveGender, player, npc, base)
            if ok then add(id) end
        end
    end
    return out
end

--- Try the pool in random order (at most 4 launches). Returns true when a scene started.
function S.startForced(player, npc, surrenderChain)
    local pool = S.forcedPool(player, npc)
    for i = #pool, 2, -1 do
        local j = ZombRand(i) + 1
        pool[i], pool[j] = pool[j], pool[i]
    end
    for i = 1, math.min(4, #pool) do
        if S.start(player, npc, pool[i], "attacker", { forced = true, surrenderChain = surrenderChain == true }) then return true, pool[i] end
        if S.sessions[player] or inScene(player) then return false end   -- something else grabbed the player meanwhile
    end
    return false
end

-- context menu ---------------------------------------------------------------------------------------------------------------------
-- Join ZomboRut's own root submenu ("ZomboRut Options"). ZomboRut builds it lazily inside its own OnFillWorldObjectContextMenu
-- handler; ours is registered later (loadModAfter), so we look for that root option and reuse it, and only create the same
-- root (same text, same icon) if ZomboRut did not need it for this click.
local function zrIcon(option, name)
    local ok, U = pcall(require, "ZomboRut/ContextMenu/ZR_MenuUtil")
    if ok and type(U) == "table" and U.icon then U.icon(option, name) end
end

local function zrRootMenu(context, worldobjects)
    local mainName = getText("ContextMenu_Main")
    for _, opt in ipairs(context.options or {}) do
        if opt.name == mainName and opt.subOption then
            local sub = context:getSubMenu(opt.subOption)
            if sub then return sub end
        end
    end
    local rootOption = context:addOption(mainName, worldobjects, nil)
    zrIcon(rootOption, "Main")
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(rootOption, sub)
    return sub
end

-- Diagnostics: this prints WITHOUT needing the sandbox debug switch (one short line per distinct reason, at most every 5 s,
-- and only when you right-click a real A-Life NPC close to you), because "why is there no option" must be answerable from
-- console.txt alone. With the game started in debug mode the reason is also shown as a greyed-out menu line.
local lastWhy, lastWhyAt = nil, 0
local function diagnose(player, z, why)
    if lastWhy == why and ts() - lastWhyAt < 5000 then return end
    lastWhy, lastWhyAt = why, ts()
    print(string.format("[ZLRC] Ask-for-sex not offered for NPC %s (%s%s, player %s): %s",
        tostring(ZLRC.npcUid(z)), gcode(z), "", gcode(player), tostring(why)))
end

local function hasNearbyNpcBystander(player, target)
    local cell = getCell()
    local list = cell and cell:getZombieList()
    if not list then return false end
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local radiusSquared = 8 * 8
    for i = 0, list:size() - 1 do
        local npc = list:get(i)
        if npc ~= target and ZLRC.isNpc(npc) and ZLRC.alive(npc) then
            local dx, dy = npc:getX() - px, npc:getY() - py
            if dx * dx + dy * dy <= radiusSquared and math.abs(npc:getZ() - pz) < 1.5 then
                return true
            end
        end
    end
    return false
end

local function fill(playerNum, context, worldobjects, test)
    if test or not ZLRC.enabled() or ZLRC.sv("npcSexEnabled", true) ~= true then return end
    if not (zrReady() and zrEnabled()) then return end
    local player = getSpecificPlayer(playerNum)
    if not player or player:isAsleep() or player:getVehicle() then return end
    if player:isDraggingCorpse() or inScene(player) then return end

    local npc, firstWhy, firstNpc
    for _, z in ipairs(ZLRC.pick(worldobjects).zombies) do
        if ZLRC.isNpc(z) and ZLRC.distTo(player, z) < 4 then
            local ok, why = eligible(player, z)
            if ok then npc = z; break end
            if not firstWhy then firstWhy, firstNpc = why, z end
        end
    end

    if not npc then
        if firstWhy then
            diagnose(player, firstNpc, firstWhy)
            if getDebug and getDebug() then
                local zrMenu = zrRootMenu(context, worldobjects)
                local opt = zrMenu:addOption(getText("ContextMenu_ZR_AskForSexMenu") .. " [unavailable: " .. tostring(firstWhy) .. "]", player, nil)
                opt.notAvailable = true
            end
        end
        return
    end

    local shyOutside = hasZRtrait(player, "Innocent") and player:isOutside()
    local shyBystanders = hasZRtrait(player, "Innocent") and hasNearbyNpcBystander(player, npc)
    if shyOutside or shyBystanders then
        diagnose(player, npc, shyOutside and "Shy personality prevents consensual scenes outdoors"
            or "Shy personality prevents consensual scenes while other NPCs are nearby")
        local zrMenu = zrRootMenu(context, worldobjects)
        local option = zrMenu:addOption(getText("ContextMenu_ZR_AskForSexMenu"), player, nil)
        zrIcon(option, "AskForSex")
        option.notAvailable = true
        local tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setVisible(false)
        tooltip.description = " <RED>" .. getText(shyOutside and "ContextMenu_Mast_inno" or "ContextMenu_Mast_bandi")
        option.toolTip = tooltip
        return
    end

    local entries = resolve(player, npc)
    if #entries == 0 then
        diagnose(player, npc, "no ZomboRut scene exists for gender pair " .. gcode(player) .. "+" .. gcode(npc))
        return
    end

    local zrMenu = zrRootMenu(context, worldobjects)
    local root = zrMenu:addOption(getText("ContextMenu_ZR_AskForSexMenu"), player, nil)
    zrIcon(root, "AskForSex")
    local sub = ISContextMenu:getNew(context)
    zrMenu:addSubMenu(root, sub)
    local moreSub
    for _, e in ipairs(entries) do
        local id, mode = e.id, e.mode
        local targetSub = sub
        if e.more then
            if not moreSub then
                local moreOption = sub:addOption(getTextOrNull("ContextMenu_ZLRC_NpcSex_More") or "More...", player, nil)
                moreSub = ISContextMenu:getNew(context)
                sub:addSubMenu(moreOption, moreSub)
            end
            targetSub = moreSub
        end
        targetSub:addOption(e.label, player, function(p) S.start(p, npc, id, mode) end)
    end
end

Events.OnFillWorldObjectContextMenu.Add(fill)
