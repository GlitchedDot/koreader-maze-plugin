-- maze_pdf.lua - minimal vector-PDF writer for mazes (pure Lua, 5.1-safe).
-- Produces a 2-page PDF: page 1 the maze, page 2 the maze with solution.
-- Page size matches the Kindle Scribe screen (1404x1872 @ 300dpi).
-- Uses only the base-14 Helvetica font, so no font embedding is needed.

local MazePDF = {}

local PAGE_W = 1404 / 300 * 72 -- 336.96 pt
local PAGE_H = 1872 / 300 * 72 -- 449.28 pt
local MARGIN = 26

local function num(v)
    local s = string.format("%.2f", v)
    s = s:gsub("0+$", ""):gsub("%.$", "")
    if s == "-0" then s = "0" end
    return s
end

local function esc(s)
    return (s:gsub("[\\%(%)]", "\\%0"))
end

-- ---------------------------------------------------------------- PDF core

local function new_pdf()
    return { objs = {} }
end

local function add_obj(pdf, body)
    pdf.objs[#pdf.objs + 1] = body
    return #pdf.objs
end

local function assemble(pdf)
    local out = { "%PDF-1.4\n" }
    local offsets = {}
    local pos = #out[1]
    for i, body in ipairs(pdf.objs) do
        offsets[i] = pos
        local chunk = i .. " 0 obj\n" .. body .. "\nendobj\n"
        out[#out + 1] = chunk
        pos = pos + #chunk
    end
    local xref_pos = pos
    out[#out + 1] = "xref\n0 " .. (#pdf.objs + 1) .. "\n"
    out[#out + 1] = "0000000000 65535 f \n"
    for i = 1, #pdf.objs do
        out[#out + 1] = string.format("%010d 00000 n \n", offsets[i])
    end
    out[#out + 1] = "trailer\n<< /Size " .. (#pdf.objs + 1)
        .. " /Root 1 0 R >>\nstartxref\n" .. xref_pos .. "\n%%EOF\n"
    return table.concat(out)
end

local function stream_obj(data)
    return "<< /Length " .. #data .. " >>\nstream\n" .. data .. "endstream"
end

-- ---------------------------------------------------------------- maze art

-- Geometry shared by both pages. Returns a table with cell rect helper.
local function geometry(size)
    local title_h = 46 -- room for title + subtitle
    local side = math.min(PAGE_W - MARGIN * 2, PAGE_H - MARGIN * 2 - title_h)
    local ox = (PAGE_W - side) / 2
    local top = PAGE_H - MARGIN - title_h
    local oy = top - side
    local cell = side / size
    local g = {
        ox = ox, oy = oy, side = side, cell = cell,
        title_y = PAGE_H - MARGIN - 12,
        subtitle_y = PAGE_H - MARGIN - 30,
    }
    function g.rect(x, y)
        local x0 = ox + (x - 1) * cell
        local x1 = ox + x * cell
        local y1 = oy + side - (y - 1) * cell -- top edge (PDF y-up)
        local y0 = oy + side - y * cell       -- bottom edge
        return x0, y0, x1, y1
    end
    function g.center(x, y)
        local x0, y0, x1, y1 = g.rect(x, y)
        return (x0 + x1) / 2, (y0 + y1) / 2
    end
    return g
end

local function wall_segments(cells, size, g)
    local p = {}
    for y = 1, size do
        for x = 1, size do
            local c = cells[(y - 1) * size + x]
            if c then
                local x0, y0, x1, y1 = g.rect(x, y)
                if c.n then p[#p + 1] = num(x0).." "..num(y1).." m "..num(x1).." "..num(y1).." l" end
                if c.s then p[#p + 1] = num(x0).." "..num(y0).." m "..num(x1).." "..num(y0).." l" end
                if c.w then p[#p + 1] = num(x0).." "..num(y0).." m "..num(x0).." "..num(y1).." l" end
                if c.e then p[#p + 1] = num(x1).." "..num(y0).." m "..num(x1).." "..num(y1).." l" end
            end
        end
    end
    return table.concat(p, "\n")
end

local function centered_text(g, y, ptsize, gray, text)
    -- crude Helvetica centering (avg glyph ~0.55em)
    local w = #text * ptsize * 0.55
    local tx = (PAGE_W - w) / 2
    return "BT /F1 " .. num(ptsize) .. " Tf " .. num(gray) .. " g "
        .. num(tx) .. " " .. num(y) .. " Td (" .. esc(text) .. ") Tj ET"
end

local function maze_page(cells, size, title, subtitle, g, solution, show_solution)
    local p = {}
    p[#p + 1] = centered_text(g, g.title_y, 15, 0, title)
    if subtitle then
        p[#p + 1] = centered_text(g, g.subtitle_y, 9.5, 0.25, subtitle)
    end
    -- start/finish markers follow the solution endpoints, so shaped
    -- mazes (whose entrance/exit aren't the grid corners) work too.
    local s_idx, g_idx = solution[1], solution[#solution]
    local function mark(fill)
        local cx, cy = g.center(((s_idx - 1) % size) + 1,
            math.floor((s_idx - 1) / size) + 1)
        local ex, ey = g.center(((g_idx - 1) % size) + 1,
            math.floor((g_idx - 1) / size) + 1)
        local s = math.max(2, g.cell * 0.55)
        local q = {}
        if fill then
            q[#q + 1] = "0 g " .. num(cx - s / 2) .. " " .. num(cy - s / 2)
                .. " " .. num(s) .. " " .. num(s) .. " re f"
        end
        q[#q + 1] = "0 G " .. num(math.max(1, g.cell * 0.2)) .. " w "
            .. num(ex - s / 2) .. " " .. num(ey - s / 2)
            .. " " .. num(s) .. " " .. num(s) .. " re S"
        return table.concat(q, "\n")
    end
    if show_solution then
        -- solution page: light walls, bold solution path on top
        p[#p + 1] = "0.72 G"
        p[#p + 1] = num(math.max(0.5, g.cell * 0.07)) .. " w"
        p[#p + 1] = wall_segments(cells, size, g)
        p[#p + 1] = "S"
        local q = {}
        for i, ci in ipairs(solution) do
            local cx, cy = g.center(((ci - 1) % size) + 1, math.floor((ci - 1) / size) + 1)
            q[#q + 1] = num(cx) .. " " .. num(cy) .. (i == 1 and " m" or " l")
        end
        p[#p + 1] = "0 G " .. num(math.max(0.8, g.cell * 0.32)) .. " w 1 J 1 j"
        p[#p + 1] = table.concat(q, "\n")
        p[#p + 1] = "S"
        -- re-mark start/finish on top of the path
        p[#p + 1] = mark(true)
    else
        p[#p + 1] = "0 G"
        p[#p + 1] = num(math.max(0.6, g.cell * 0.09)) .. " w"
        p[#p + 1] = wall_segments(cells, size, g)
        p[#p + 1] = "S"
        -- start: solid square; finish: hollow square (readable on B&W e-ink)
        p[#p + 1] = mark(true)
    end
    return table.concat(p, "\n") .. "\n"
end

-- cells: from MazeGen.generate. size: grid size. diff_label: "Easy" etc.
-- solution: from MazeGen.solve (list of cell indexes).
-- shape_label: e.g. "Heart" (nil or "Square" for the classic square maze).
function MazePDF.generate(cells, size, diff_label, solution, shape_label)
    local g = geometry(size)
    local title = "Maze " .. size .. " x " .. size .. " (" .. diff_label .. ")"
    if shape_label and shape_label ~= "Square" then
        title = shape_label .. " " .. title
    end
    local pdf = new_pdf()
    add_obj(pdf, "<< /Type /Catalog /Pages 2 0 R >>")
    add_obj(pdf, "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>")
    local page_res = "/Resources << /Font << /F1 7 0 R >> >>"
    add_obj(pdf, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 "
        .. num(PAGE_W) .. " " .. num(PAGE_H) .. "] /Contents 5 0 R " .. page_res .. " >>")
    add_obj(pdf, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 "
        .. num(PAGE_W) .. " " .. num(PAGE_H) .. "] /Contents 6 0 R " .. page_res .. " >>")
    add_obj(pdf, stream_obj(maze_page(cells, size,
        title,
        "Enter at the solid square - exit at the hollow square.",
        g, solution, false)))
    add_obj(pdf, stream_obj(maze_page(cells, size, "Solution", nil, g, solution, true)))
    add_obj(pdf, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    return assemble(pdf)
end

return MazePDF
