-- ZLRC_Bik  (item 7)
-- ZomboLust plays Bink (.bik) clips in its "Sexual Activity Viewer" window (ZomboLust.UI). ZomboRut scenes carry no
-- ZomboLust animation events, so this module drives that same window from the ZomboRut scene's progress.
--
-- Behaviour (as requested):
--   * The window is NEVER opened or brought to front by this module. The clip is only LOADED into the window object
--     (ZomboLust_ImageUI:setVideo builds the VideoTexture and keeps it; the window renders/advances it only while visible).
--   * You open the window yourself with ZomboLust's own sidebar button; it then shows the clip that is currently playing,
--     and keeps following the scene's stages while open. Close it any time; it will not pop up again.
--   * At scene end the window is closed and cleared, exactly like ZomboLust does after its own animations.
--
-- Clip names (from the shipped video list):
--     ZL_<Skin>_<Back|Front>_<Chain|Free>_<Anal|Vaginal>_<1..6>.bik
--     ZL_<Skin>_Oral_<Chain|Free>_<1..6>.bik
--     ZL_<Skin>_Pregnant_<Anal|Vaginal>_<1..6>.bik            (Being Female mod)
--     ZL_Zombie_<Back|Front>_<Chain|Free>_<Anal|Vaginal>_<1..6>.bik, ZL_Zombie_Oral_<Chain|Free>_<1..6>.bik  (female zombie)
--   Skin = Argent | Blanc | Brun | Sombre, picked from the female participant's skin texture index exactly like ZomboLust
--   (0 Argent, 1-2 Blanc, 3 Brun, 4+ Sombre).  Chain = subdued / forced on the player (ZomboRut launches from an attacker),
--   Free = regular / consensual (friendly NPC scenes, plain corpse scenes).  1..6 = intensity, advanced over the scene.

require "ZLRC/ZLRC_Core"

local ZomboRutScene = ZLRC.ZRS      -- lazy proxy: ZomboRutScene is only reachable through require()

local STAGES = 6

-- scene classification --------------------------------------------------------------------------------------------------------
--- returns "Back" | "Front" | "Oral", or nil when the scene has no matching clip (footjob, tackle, drag, punch, lunge ...)
local function orientationOf(sceneId, cfg)
    if cfg and (cfg.isUtility or cfg.kind == "utility") then return nil end
    local id = string.lower(tostring(sceneId or ""))
    for _, bad in ipairs({ "tackle", "drag", "footjob", "punch", "lunge" }) do
        if id:find(bad, 1, true) then return nil end
    end
    if id:find("bj", 1, true) or id:find("oral", 1, true) or id:find("facesit", 1, true) or id:find("lotus", 1, true) then
        return "Oral"
    end
    if id:find("doggy", 1, true) or id:find("spoon", 1, true) then return "Back" end
    return "Front"
end

local function skinName(character)
    local idx
    if character and character.getHumanVisual then
        local hv = character:getHumanVisual()
        if hv and hv.getSkinTextureIndex then idx = hv:getSkinTextureIndex() end
    end
    if idx == 0 then return "Argent" end
    if idx == 1 or idx == 2 then return "Blanc" end
    if idx == 3 then return "Brun" end
    if idx == nil then return "Blanc" end
    return "Sombre"
end

local function female(obj)
    return obj ~= nil and obj.isFemale ~= nil and obj:isFemale() == true
end

--- Being Female: ZomboRut itself probes pregnancy through BF.animation:filterVariants (for the local player). We do the same and
--- only ever for the player. Unverified against the BF mod (not part of the upload); any failure simply means "not pregnant".
local function playerPregnant()
    local BF = rawget(_G, "BF")
    local anim = BF and BF.animation
    if not (anim and anim.filterVariants) then return false end
    local ok, res = pcall(anim.filterVariants, anim, { { name = "pregnant", steps = { 4 }, loop = 1, pregnancy = true, path = "media/ui/animation" } })
    return ok and type(res) == "table" and res[1] ~= nil
end

--- Build the plan for a scene: a function stage -> clip file name, or nil when this scene has no clip.
local function planFor(player, active)
    local orient = orientationOf(active.sceneId, active.cfg)
    if not orient then return nil end

    local partner = active.body
    local friendlyNpc = active.zlrcNpcScene == true
    local chain = active.launchSource == "fromAttacker"
    local mode = chain and "Chain" or "Free"

    -- who is the female actor?  the player if female, else the (NPC-copy) partner; an ordinary zombie corpse with a male player
    -- plays the female-zombie clips instead (as ZomboLust does for male victims)
    local actor, prefix
    if female(player) then
        actor = player
    elseif female(partner) and friendlyNpc then
        actor = partner
    end
    if actor then prefix = "ZL_" .. skinName(actor) .. "_" else prefix = "ZL_Zombie_" end

    local pregnant = actor == player and orient ~= "Oral" and prefix ~= "ZL_Zombie_" and playerPregnant()

    return function(stage)
        if orient == "Oral" then
            return string.format("%sOral_%s_%d.bik", prefix, mode, stage)
        end
        if pregnant then
            return string.format("%sPregnant_Vaginal_%d.bik", prefix, stage)
        end
        return string.format("%s%s_%s_Vaginal_%d.bik", prefix, orient, mode, stage)
    end
end
ZLRC._bikPlanFor = planFor      -- exposed for tests

-- window control ------------------------------------------------------------------------------------------------------------------
--- Load a clip into the viewer WITHOUT showing it. (ZomboLust's own ZLShowImage handler is deliberately not used: it always calls
--- setVisible(true) + bringToTop(), which is the pop-up we must avoid.)
local function loadClip(name)
    local ui = rawget(_G, "ZomboLust") and ZomboLust.UI
    if not (ui and ui.setVideo) then return false end
    ui:setVideo(name)
    ZLRC.log("bik clip loaded (window %s): %s", ui:getIsVisible() and "open" or "closed", name)
    return true
end

local function closeWindow()
    local ui = rawget(_G, "ZomboLust") and ZomboLust.UI
    if ui and ui.close then ui:close() end      -- hides + clears, as ZomboLust does when its own animations end
end

local live = setmetatable({}, { __mode = "k" })               -- [player] = { t0, durMs, clipOf, stage }

ZLRC.whenReady("ZomboRutScene bik callbacks",
    function()
        return ZLRC.zrScene() ~= nil
            and type(ZomboRutScene.registerSceneStartCallback) == "function"
            and type(ZomboRutScene.registerSceneEndCallback) == "function"
    end,
    function()
        ZomboRutScene.registerSceneStartCallback(function(player, active)
            if not (ZLRC.enabled() and ZLRC.sv("showBik", true) == true) or type(active) ~= "table" then return end
            -- ZLRC_NpcSex flags friendly-NPC scenes right after launch; at start time use the pending marker
            if ZLRC._npcScene[player] then active.zlrcNpcScene = true end
            local clipOf = planFor(player, active)
            if not clipOf then return end
            local secs  = tonumber(active.effectiveDuration) or tonumber(active.cfg and active.cfg.duration) or 17
            live[player] = { t0 = getTimestampMs(), durMs = secs * 1000, clipOf = clipOf, stage = 0 }
        end)
        ZomboRutScene.registerSceneEndCallback(function(player, _active, _result)
            if live[player] then
                live[player] = nil
                closeWindow()
            end
        end)
    end)

Events.OnTick.Add(function()
    for player, st in pairs(live) do
        local frac = (getTimestampMs() - st.t0) / st.durMs
        local want = math.max(1, math.min(STAGES, math.floor(frac * STAGES) + 1))
        if want ~= st.stage then
            st.stage = want
            loadClip(st.clipOf(want))
        end
    end
end)
