-- ZLRC_Excitation (item 8, part 2 of 2)
-- Sandbox ZLRC.excitationSource: 1 = zombies + NPCs (vanilla ZomboLust), 2 = zombies only,
-- 3 = A-Life NPCs only, 4 = nothing.
--
-- ZomboLust's pheromone loop is a file-local function (no hook), and its gain is linear in the number
-- of bodies inside PheromoneRadius (horde fear is linear in the count inside HordeRadius). So after its
-- listener ran we look at what changed this frame and scale it by (allowed bodies / counted bodies).
-- Limitation: a Lewd-trait flat passive gain that lands in the same frame is scaled with it.

require "ZLRC/ZLRC_Core"

local function counts(player, radius)
    local total, npc = 0, 0
    local cell = player:getCell()
    local list = cell and cell:getZombieList()
    if not list then return 0, 0 end
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local r2 = radius * radius
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z and z:isAlive() and z:getZ() == pz then
            local dx, dy = z:getX() - px, z:getY() - py
            if dx * dx + dy * dy <= r2 then
                total = total + 1
                if ZLRC.isNpc(z) then npc = npc + 1 end
            end
        end
    end
    return total, npc
end

local function post(player)
    local before = ZLRC._excPre and ZLRC._excPre[player]
    if before == nil then return end
    ZLRC._excPre[player] = nil
    local mode = ZLRC.sv("excitationSource", 1)
    if mode == 1 or not ZLRC.enabled() then return end

    local ES = rawget(_G, "ZomboLust_ExcitationSystem")
    if not (ES and ES.getExcitation and ES.setExcitation) then return end
    local after = ES.getExcitation(player)
    local delta = after - before
    if math.abs(delta) < 1e-9 then return end

    local radius = (delta > 0) and (ES.PheromoneRadius or 2.0) or (ES.HordeRadius or 5.0)
    local total, npc = counts(player, radius)
    if total == 0 then return end              -- nothing nearby: the change is not ours to touch

    local zombies = total - npc
    local kept
    if     mode == 2 then kept = zombies
    elseif mode == 3 then kept = npc
    else                  kept = 0 end

    local scaled = before + delta * (kept / total)
    if math.abs(scaled - after) > 1e-9 then
        ES.setExcitation(player, scaled)
        ZLRC.log("excitation %.4f -> %.4f (mode=%d zombies=%d npcs=%d)", after, scaled, mode, zombies, npc)
    end
end

Events.OnPlayerUpdate.Add(function(player)
    local ok, err = pcall(post, player)
    if not ok then ZLRC.log("excitation post error: %s", tostring(err)) end
end)
