-- ZLRC_NpcSex  (item 5)
-- Friendly / allied A-Life NPC -> entry inside ZomboRut's own "ZomboRut Options" menu: "ZR: Ask for Sex" -> positions.
--
-- The position list is built from ZomboRut's own scene registry (listLogical / getLogical / _resolveGender), for the EXACT gender
-- pair of player and NPC (no "assumed partner" fallback). Utility scenes (drag/tackle) and violent ones (punch/lunge) are skipped.
-- "Defeat"-kind scenes (facesit, blowjob, reverse lotus ...) go into a "More" sub-menu: when launched through the corpse route
-- ZomboRut itself plays them as plain sex ("defeat-as-sex mode").
--
-- ONE launch route for everything: ZomboRut's corpse pipeline on a husk. ZomboRut's live launcher needs the Bandits mod, and its
-- attacker route (playSceneFromAttacker) was tried first and abandoned: it parks the real NPC 50 tiles away (A-Life then respawns a
-- duplicate at the old spot) and copies the NPC's clothes onto the husk, which ZomboRut's scene-start strip then rips off and drops
-- as items. Here the real NPC never moves: it is held (hidden, non-colliding, zlrcBusy, ProjectALifeCorpseOf marker so A-Life's
-- Fence/Executor leave it alone), the husk is a NAKED copy of its looks, and afterwards the NPC returns to A-Life's baseline state.

require "ZLRC/ZLRC_Core"
require "ZLRC/ZLRC_Pick"

local ZomboRutScene = ZLRC.ZRS      -- lazy proxy: ZomboRutScene is only reachable through require()

ZLRC.NpcSex = ZLRC.NpcSex or {}
local S = ZLRC.NpcSex
S.sessions = S.sessions or setmetatable({}, { __mode = "k" })     -- [player] = session

local function ts() return getTimestampMs() end

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

-- eligibility -----------------------------------------------------------------------------------------------------------------
--- returns true, or false + reason (the reason is only used for debug logging)
local function eligible(player, npc)
    if not ZLRC.isNpc(npc) or not ZLRC.alive(npc) then return false, "not a live A-Life NPC" end
    if ZLRC.isSubdued(npc) or ZLRC.isHusk(npc) then return false, "subdued/husk" end
    local d = ZLRC.md(npc)
    if d and d.zlrcBusy then return false, "busy" end
    if gcode(player) == "M" and gcode(npc) == "M" then return false, "male+male has no scenes here" end
    if npc:isOnFloor() or npc:isKnockedDown() or npc:isCrawling() then return false, "NPC is down" end
    local friendly, why = ZLRC.friendlyOrAllied(npc, player)
    if not friendly then return false, why .. " (needs friendly or allied)" end
    return true, why
end

-- scene catalog -------------------------------------------------------------------------------------------------------------------
local SKIP_ID = { "tackle", "drag", "heldrag", "punch", "lunge", "utility" }

local LABEL_FIXES = {                                   -- friendlier names for ZomboRut's "Defeat ..." and unlabeled scenes
    DefeatBJ = "Blowjob", DefeatLesbianFaceSit = "Face sit", DefeatRevLotus = "Reverse lotus",
    DefeatForcedCowGirl = "Cowgirl (variant)", DefeatForcedCowgirl = "Cowgirl (variant)",
}

local function prettyFromId(id)
    local first = id:match("^([^_]+)") or id
    if id:find("^Sex_Subdue") then first = id:gsub("^Sex_Subdue", ""):match("^([^_]+)") or first end
    return (first:gsub("(%l)(%u)", "%1 %2"))
end

local function labelFor(id, cfg)
    local raw = cfg and cfg.label
    if raw and LABEL_FIXES[raw] then return LABEL_FIXES[raw] end
    if raw then
        local ok, U = pcall(require, "ZomboRut/ContextMenu/ZR_MenuUtil")
        if ok and type(U) == "table" and U.sceneLabel then return U.sceneLabel(raw) end
        return raw
    end
    return prettyFromId(id)
end

--- { { id = concreteSceneId, label = "...", more = bool }, ... } valid for this exact player/NPC gender pair
local function resolve(player, npc)
    local out, usedLabels = {}, {}
    local pair = gcode(player) .. gcode(npc)
    local ids = ZomboRutScene.listLogical and ZomboRutScene.listLogical() or {}
    for _, logical in ipairs(ids) do
        local lower = logical:lower()
        local skip = false
        for _, bad in ipairs(SKIP_ID) do if lower:find(bad, 1, true) then skip = true; break end end
        local cfg = not skip and ZomboRutScene.getLogical(logical) or nil
        if cfg and not (cfg.debug or cfg.debugOnly or cfg.isUtility or cfg.kind == "utility") then
            local ok, concrete = pcall(ZomboRutScene._resolveGender, player, npc, logical)
            -- _resolveGender may "assume" a male partner for same-gender pairs; accept only an exact gender match
            if ok and type(concrete) == "string" and concrete:sub(-2) == pair then
                local ccfg = ZomboRutScene._scenes[concrete]
                if ccfg and not ccfg.debugOnly then
                    local label = labelFor(logical, cfg)
                    if usedLabels[label] then label = label .. " (" .. (usedLabels[label] + 1) .. ")" end
                    usedLabels[label] = (usedLabels[label] or 0) + 1
                    out[#out + 1] = { id = concrete, label = label, more = (cfg.isDefeat == true), sort = (cfg.friendlyOnly and "0" or "1") .. label }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.sort < b.sort end)
    return out
end
S._resolve = resolve

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

-- start / finish -------------------------------------------------------------------------------------------------------------------
function S.start(player, npc, sceneId)
    if not (zrReady() and ZLRC.enabled()) then return false end
    if S.sessions[player] or inScene(player) then return false end
    local okE, why = eligible(player, npc)
    if not okE then ZLRC.log("NPC scene refused: %s", tostring(why)); return false end
    local uid = ZLRC.npcUid(npc)
    local snap = { x = npc:getX(), y = npc:getY(), z = npc:getZ(), uid = uid, banditPacified = false }

    hold(npc, snap)
    local body = makeHusk(player, npc)
    if not body then
        restore(npc, snap)
        ZLRC.warn("could not create husk; NPC scene cancelled")
        return false
    end

    ZLRC._npcScene[player] = true                              -- read by ZLRC_CloakGuard / ZLRC_Bik at scene start
    S.sessions[player] = { npc = npc, snap = snap, body = body, t0 = ts() }

    local ok, started = pcall(ZomboRutScene.playSceneFromCorpse, player, body, sceneId, { launchSource = "fromLive" })
    ZLRC._npcScene[player] = nil                               -- start callbacks already ran inside the call above
    if not ok or not started then
        S.sessions[player] = nil
        removeHusk(body)
        restore(npc, snap)
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
        act.zlrcNpcScene       = true
    end
    ZLRC.log("NPC scene %s started with %s", tostring(sceneId), tostring(uid))
    return true
end

local finalizeAt = setmetatable({}, { __mode = "k" })         -- [player] = ms

local function finalize(player)
    local s = S.sessions[player]
    S.sessions[player] = nil
    finalizeAt[player] = nil
    if not s then return end
    removeHusk(s.body)                                        -- idempotent; ZomboRut normally removed it already
    restore(s.npc, s.snap)
    ZLRC.log("NPC %s restored to A-Life", tostring(s.snap and s.snap.uid))
end

ZLRC.whenReady("ZomboRut end callback (NpcSex)",
    function() return ZLRC.zrScene() ~= nil and type(ZomboRutScene.registerSceneEndCallback) == "function" end,
    function()
        ZomboRutScene.registerSceneEndCallback(function(player, active, _result)
            if S.sessions[player] and type(active) == "table" and active.zlrcNpcScene then
                finalizeAt[player] = ts() + 1500                -- let ZomboRut finish its own restore first
            end
        end)
    end)

Events.OnTick.Add(function()
    local now = ts()
    for player, s in pairs(S.sessions) do
        local at = finalizeAt[player]
        if at and now >= at then
            pcall(finalize, player)
        elseif not at then
            -- safety net: scene vanished without an end callback, or NPC lost
            local active = ZomboRutScene and ZomboRutScene._active and ZomboRutScene._active[player]
            if (now - s.t0) > 5000 and not active then pcall(finalize, player) end
            if (now - s.t0) > 300000 then pcall(finalize, player) end
        end
    end
end)

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

    local more = {}
    for _, e in ipairs(entries) do
        if e.more then
            more[#more + 1] = e
        else
            local id = e.id
            sub:addOption(e.label, player, function(p) S.start(p, npc, id) end)
        end
    end
    if #more > 0 and ZLRC.sv("npcSexMoreScenes", true) == true then
        local moreOpt = sub:addOption(getText("ContextMenu_ZLRC_More"), player, nil)
        local moreSub = ISContextMenu:getNew(sub)
        sub:addSubMenu(moreOpt, moreSub)
        for _, e in ipairs(more) do
            local id = e.id
            moreSub:addOption(e.label, player, function(p) S.start(p, npc, id) end)
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(fill)
