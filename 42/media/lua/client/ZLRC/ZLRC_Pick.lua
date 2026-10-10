-- ZLRC_Pick: find things the player right-clicked on (clicked squares + their 8 neighbours).
require "ZLRC/ZLRC_Core"

local function squaresOf(worldobjects)
    local seen, out = {}, {}
    local function add(sq)
        if sq == nil then return end
        local k = sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()
        if not seen[k] then seen[k] = true; out[#out + 1] = sq end
    end
    local cell = getCell()
    for _, o in ipairs(worldobjects or {}) do
        local ok, sq = pcall(function() return o:getSquare() end)
        if ok and sq then
            for dx = -1, 1 do for dy = -1, 1 do
                add(cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ()))
            end end
        end
    end
    return out
end

--- returns { zombies = { IsoZombie... }, bodies = { IsoDeadBody... } }
function ZLRC.pick(worldobjects)
    local res, seenZ = { zombies = {}, bodies = {} }, {}
    for _, sq in ipairs(squaresOf(worldobjects)) do
        local mo = sq:getMovingObjects()
        for i = 0, mo:size() - 1 do
            local o = mo:get(i)
            if ZLRC.isZombie(o) and ZLRC.alive(o) and not seenZ[o] then
                seenZ[o] = true
                res.zombies[#res.zombies + 1] = o
            end
        end
        local db = sq:getDeadBodys()
        for i = 0, db:size() - 1 do res.bodies[#res.bodies + 1] = db:get(i) end
    end
    return res
end

function ZLRC.distTo(player, obj)
    local ok, d = pcall(function()
        local dx, dy = player:getX() - obj:getX(), player:getY() - obj:getY()
        return math.sqrt(dx * dx + dy * dy)
    end)
    return ok and d or 999
end
