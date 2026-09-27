-- maze_gen.lua - pure-Lua maze generation, solving and braiding.
-- No KOReader dependencies; works on Lua 5.1 (LuaJIT) through 5.4.
-- A maze is a flat array of cells, indexed (y-1)*size + x.
-- Each cell: { n=bool, e=bool, s=bool, w=bool } (true = wall standing).
-- Cells outside the chosen shape mask are nil.

local MazeGen = {}

local DIRS = {
    { name = "n", dx =  0, dy = -1, opp = "s" },
    { name = "e", dx =  1, dy =  0, opp = "w" },
    { name = "s", dx =  0, dy =  1, opp = "n" },
    { name = "w", dx = -1, dy =  0, opp = "e" },
}

local function idx(x, y, size)
    return (y - 1) * size + x
end

-- ---------------------------------------------------------------- shapes

-- Normalized cell-center coords in (-0.5, 0.5); v grows downward.
local function norm(x, y, size)
    return (x - 0.5) / size - 0.5, (y - 0.5) / size - 0.5
end

local function in_star(u, v)
    -- 5-pointed star, point-in-polygon in y-up space.
    local verts = {}
    for i = 0, 9 do
        local ang = -math.pi / 2 + i * math.pi / 5
        local r = (i % 2 == 0) and 0.48 or 0.20
        verts[#verts + 1] = { x = r * math.cos(ang), y = r * math.sin(ang) }
    end
    local x, y = u, -v
    local inside, j = false, #verts
    for i = 1, #verts do
        local xi, yi = verts[i].x, verts[i].y
        local xj, yj = verts[j].x, verts[j].y
        if ((yi > y) ~= (yj > y))
                and (x < (xj - xi) * (y - yi) / (yj - yi) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

local SHAPE_DEFS = {
    square = function() return true end,
    circle = function(x, y, size)
        local u, v = norm(x, y, size)
        return u * u + v * v <= 0.48 * 0.48
    end,
    diamond = function(x, y, size)
        local u, v = norm(x, y, size)
        return math.abs(u) + math.abs(v) <= 0.47
    end,
    triangle = function(x, y, size)
        local u, v = norm(x, y, size)
        return v >= -0.45 and v <= 0.45 and math.abs(u) <= (v + 0.45) * 0.5
    end,
    cross = function(x, y, size)
        local u, v = norm(x, y, size)
        return math.abs(u) <= 0.15 or math.abs(v) <= 0.15
    end,
    heart = function(x, y, size)
        local u, v = norm(x, y, size)
        local X, Y = u * 3.2, -v * 3.2
        local a = X * X + Y * Y - 1
        return a * a * a - X * X * Y * Y * Y <= 0
    end,
    star = function(x, y, size)
        local u, v = norm(x, y, size)
        return in_star(u, v)
    end,
    crescent = function(x, y, size)
        local u, v = norm(x, y, size)
        local in_big = u * u + v * v <= 0.46 * 0.46
        local dx, dy = u - 0.22, v
        return in_big and not (dx * dx + dy * dy <= 0.38 * 0.38)
    end,
}

MazeGen.SHAPES = {
    { id = "square",   text = "Square" },
    { id = "circle",   text = "Circle" },
    { id = "heart",    text = "Heart" },
    { id = "star",     text = "Star" },
    { id = "diamond",  text = "Diamond" },
    { id = "triangle", text = "Triangle" },
    { id = "crescent", text = "Crescent" },
    { id = "cross",    text = "Cross" },
    { id = "random",   text = "Random" },
}

function MazeGen.shape_text(shape_id)
    for _, s in ipairs(MazeGen.SHAPES) do
        if s.id == shape_id then return s.text end
    end
    return "Square"
end

function MazeGen.resolve_shape(shape_id)
    if shape_id == "random" then
        local pool = {}
        for _, s in ipairs(MazeGen.SHAPES) do
            if s.id ~= "random" then pool[#pool + 1] = s.id end
        end
        return pool[math.random(#pool)]
    end
    if SHAPE_DEFS[shape_id] then return shape_id end
    return "square"
end

-- ---------------------------------------------------------------- generate

-- Generate a maze of size x size cells, clipped to the given shape.
-- braid: 0.0 = perfect maze; higher adds loops (0.3 medium, 0.6 hard).
-- shape_id: one of MazeGen.SHAPES ids, or "random".
function MazeGen.generate(size, braid, shape_id)
    assert(size >= 2, "maze size must be at least 2")
    braid = braid or 0
    shape_id = MazeGen.resolve_shape(shape_id or "square")
    local mask = SHAPE_DEFS[shape_id]

    local cells = {}
    local mask_cells = {}
    for y = 1, size do
        for x = 1, size do
            if mask(x, y, size) then
                local i = idx(x, y, size)
                cells[i] = { n = true, e = true, s = true, w = true }
                mask_cells[#mask_cells + 1] = { x = x, y = y }
            end
        end
    end
    assert(#mask_cells > 0, "shape mask is empty")

    -- Keep only the largest 4-connected component. Thin shapes can
    -- pinch into diagonal-only contact at small sizes, which would
    -- leave unreachable cells; pruning guarantees a fully
    -- traversable maze by construction.
    do
        local seen, best = {}, {}
        for _, mc in ipairs(mask_cells) do
            local i0 = idx(mc.x, mc.y, size)
            if not seen[i0] then
                local comp, q = {}, { i0 }
                seen[i0] = true
                while #q > 0 do
                    local i = q[#q]
                    q[#q] = nil
                    comp[#comp + 1] = i
                    local x = ((i - 1) % size) + 1
                    local y = math.floor((i - 1) / size) + 1
                    for _, d in ipairs(DIRS) do
                        local nx, ny = x + d.dx, y + d.dy
                        if nx >= 1 and nx <= size and ny >= 1 and ny <= size then
                            local ni = idx(nx, ny, size)
                            if cells[ni] and not seen[ni] then
                                seen[ni] = true
                                q[#q + 1] = ni
                            end
                        end
                    end
                end
                if #comp > #best then best = comp end
            end
        end
        local keep = {}
        for _, i in ipairs(best) do keep[i] = true end
        local pruned = {}
        for _, mc in ipairs(mask_cells) do
            local i = idx(mc.x, mc.y, size)
            if keep[i] then
                pruned[#pruned + 1] = mc
            else
                cells[i] = nil
            end
        end
        mask_cells = pruned
    end

    -- Iterative randomized depth-first carve, restricted to mask cells.
    local first = mask_cells[math.random(#mask_cells)]
    local visited = { [idx(first.x, first.y, size)] = true }
    local stack = { first }
    while #stack > 0 do
        local top = stack[#stack]
        local nbs = {}
        for _, d in ipairs(DIRS) do
            local nx, ny = top.x + d.dx, top.y + d.dy
            if nx >= 1 and nx <= size and ny >= 1 and ny <= size then
                local ni = idx(nx, ny, size)
                if cells[ni] and not visited[ni] then
                    nbs[#nbs + 1] = { x = nx, y = ny, dir = d }
                end
            end
        end
        if #nbs == 0 then
            stack[#stack] = nil -- backtrack
        else
            local nb = nbs[math.random(#nbs)]
            cells[idx(top.x, top.y, size)][nb.dir.name] = false
            cells[idx(nb.x, nb.y, size)][nb.dir.opp] = false
            visited[idx(nb.x, nb.y, size)] = true
            stack[#stack + 1] = { x = nb.x, y = nb.y }
        end
    end

    -- Entrance: north wall of the topmost-leftmost mask cell.
    -- Exit: south wall of the bottommost-rightmost mask cell.
    -- Those neighbours are never in the mask, so the openings are safe.
    local s_idx, g_idx = MazeGen.endpoints(cells, size)
    cells[s_idx].n = false
    cells[g_idx].s = false

    -- Braiding: knock extra walls at dead ends to add loops.
    -- Boundary walls (facing out of the mask) are never touched.
    if braid > 0 then
        for _, mc in ipairs(mask_cells) do
            local x, y = mc.x, mc.y
            local c = cells[idx(x, y, size)]
            local walls = 0
            if c.n then walls = walls + 1 end
            if c.e then walls = walls + 1 end
            if c.s then walls = walls + 1 end
            if c.w then walls = walls + 1 end
            if walls == 3 and math.random() < braid then
                local opts = {}
                for _, d in ipairs(DIRS) do
                    local nx, ny = x + d.dx, y + d.dy
                    if nx >= 1 and nx <= size and ny >= 1 and ny <= size
                            and c[d.name] and cells[idx(nx, ny, size)] then
                        opts[#opts + 1] = d
                    end
                end
                if #opts > 0 then
                    local d = opts[math.random(#opts)]
                    c[d.name] = false
                    cells[idx(x + d.dx, y + d.dy, size)][d.opp] = false
                end
            end
        end
    end

    return cells, shape_id
end

-- Entrance (topmost-leftmost mask cell) and exit (bottommost-rightmost).
function MazeGen.endpoints(cells, size)
    local s_idx, g_idx
    for y = 1, size do
        for x = 1, size do
            local i = idx(x, y, size)
            if cells[i] then
                if not s_idx then s_idx = i end
                g_idx = i
            end
        end
    end
    return s_idx, g_idx
end

-- Shortest path from entrance to exit, as a list of cell indexes.
function MazeGen.solve(cells, size)
    local start, goal = MazeGen.endpoints(cells, size)
    local prev = { [start] = 0 }
    local queue = { start }
    local head = 1
    while head <= #queue do
        local cur = queue[head]
        head = head + 1
        if cur == goal then break end
        local x = ((cur - 1) % size) + 1
        local y = math.floor((cur - 1) / size) + 1
        local c = cells[cur]
        for _, d in ipairs(DIRS) do
            if not c[d.name] then
                local nx, ny = x + d.dx, y + d.dy
                if nx >= 1 and nx <= size and ny >= 1 and ny <= size then
                    local ni = idx(nx, ny, size)
                    if cells[ni] and not prev[ni] then
                        prev[ni] = cur
                        queue[#queue + 1] = ni
                    end
                end
            end
        end
    end

    local path = {}
    local cur = goal
    while cur and cur ~= 0 do
        path[#path + 1] = cur
        cur = prev[cur]
    end
    local rpath = {}
    for i = #path, 1, -1 do
        rpath[#rpath + 1] = path[i]
    end
    return rpath
end

-- Sanity check used by tests: internal walls are shared identically by
-- both neighbours; open walls only ever lead into the mask, except the
-- entrance/exit openings.
function MazeGen.check_walls(cells, size)
    local s_idx, g_idx = MazeGen.endpoints(cells, size)
    local sx = ((s_idx - 1) % size) + 1
    local sy = math.floor((s_idx - 1) / size) + 1
    local gx = ((g_idx - 1) % size) + 1
    local gy = math.floor((g_idx - 1) / size) + 1
    for y = 1, size do
        for x = 1, size do
            local i = idx(x, y, size)
            local c = cells[i]
            if c then
                local function check(dir, dx, dy)
                    local nx, ny = x + dx, y + dy
                    local open = not c[dir]
                    local is_entrance = (x == sx and y == sy and dir == "n")
                    local is_exit = (x == gx and y == gy and dir == "s")
                    if nx < 1 or nx > size or ny < 1 or ny > size
                            or not cells[idx(nx, ny, size)] then
                        -- facing out of the mask: must be a wall,
                        -- except the entrance/exit openings
                        assert(not open or is_entrance or is_exit,
                            "maze leaks out of the mask")
                    else
                        local n = cells[idx(nx, ny, size)]
                        local opp = DIRS[1]
                        for _, d in ipairs(DIRS) do
                            if d.name == dir then opp = d end
                        end
                        assert(c[dir] == n[opp.opp], "wall mismatch")
                    end
                end
                check("n", 0, -1)
                check("s", 0, 1)
                check("e", 1, 0)
                check("w", -1, 0)
            end
        end
    end
    assert(not cells[s_idx].n, "entrance not open")
    assert(not cells[g_idx].s, "exit not open")
    return true
end

return MazeGen
