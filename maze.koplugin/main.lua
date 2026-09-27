-- Maze Generator plugin for KOReader.
-- Adds a "Maze generator" entry to the main menu (Tools). Pick a size
-- (10x10 to 100x100) and a difficulty, hit Generate, and the plugin
-- writes a 2-page PDF (maze + solution) into your documents folder,
-- ready to open and draw on.

local _ = require("gettext")
local DataStorage = require("datastorage")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local T = require("ffi/util").template

local MazeGen = require("maze_gen")
local MazePDF = require("maze_pdf")

local Screen = Device.screen

local MazeGenPlugin = WidgetContainer:extend{
    name = "maze",
    is_doc_only = false,
}

local SIZE_CHOICES = { 10, 15, 20, 25, 30, 40, 50, 75, 100 }
local DEFAULT_SIZE = 25

-- braid: fraction of dead ends opened into loops. 0 = perfect maze
-- (one true path); higher = more loops, harder to solve.
local DIFFICULTIES = {
    { id = "easy",   text = _("Easy"),   braid = 0 },
    { id = "medium", text = _("Medium"), braid = 0.3 },
    { id = "hard",   text = _("Hard"),   braid = 0.6 },
}
local DEFAULT_DIFFICULTY = "medium"

-- Where finished mazes go. On a Kindle this is visible to the stock
-- reader app, so you can open the PDF there and draw on it.
local function default_output_dir()
    return "/mnt/us/documents/Mazes"
end

function MazeGenPlugin:init()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/maze.lua")
    self.size = self.settings:readSetting("size") or DEFAULT_SIZE
    self.difficulty = self.settings:readSetting("difficulty") or DEFAULT_DIFFICULTY
    self.shape = self.settings:readSetting("shape") or "square"
    self.ui.menu:registerToMainMenu(self)
end

function MazeGenPlugin:addToMainMenu(menu_items)
    menu_items.maze_generator = {
        text = _("Maze generator"),
        sorting_hint = "tools",
        callback = function()
            self:showMainMenu()
        end,
    }
end

function MazeGenPlugin:getDifficulty()
    for _, d in ipairs(DIFFICULTIES) do
        if d.id == self.difficulty then return d end
    end
    return DIFFICULTIES[2]
end

function MazeGenPlugin:showMainMenu()
    local menu
    local function closeMenu()
        if menu then UIManager:close(menu) end
    end
    local diff = self:getDifficulty()
    local items = {
        {
            text = T(_("Size: %1 x %1"), self.size),
            callback = function()
                closeMenu()
                self:showSizeMenu()
            end,
        },
        {
            text = T(_("Difficulty: %1"), diff.text),
            callback = function()
                closeMenu()
                self:showDifficultyMenu()
            end,
        },
        {
            text = T(_("Shape: %1"), MazeGen.shape_text(self.shape)),
            callback = function()
                closeMenu()
                self:showShapeMenu()
            end,
        },
        {
            text = _("Generate maze"),
            callback = function()
                closeMenu()
                self:generateMaze()
            end,
        },
    }
    menu = Menu:new{
        title = _("Maze generator"),
        item_table = items,
        width = math.floor(Screen:getWidth() * 0.7),
        height = math.floor(Screen:getHeight() * 0.45),
    }
    UIManager:show(menu)
end

function MazeGenPlugin:showSizeMenu()
    local menu
    local function closeMenu()
        if menu then UIManager:close(menu) end
    end
    local items = {}
    for _, size in ipairs(SIZE_CHOICES) do
        items[#items + 1] = {
            text = T(_("%1 x %1"), size),
            mandatory = (size == self.size) and "✓" or nil,
            callback = function()
                self.size = size
                self.settings:saveSetting("size", size)
                self.settings:flush()
                closeMenu()
                self:showMainMenu()
                return true
            end,
        }
    end
    menu = Menu:new{
        title = _("Maze size"),
        item_table = items,
        width = math.floor(Screen:getWidth() * 0.6),
        height = math.floor(Screen:getHeight() * 0.7),
    }
    UIManager:show(menu)
end

function MazeGenPlugin:showDifficultyMenu()
    local menu
    local function closeMenu()
        if menu then UIManager:close(menu) end
    end
    local items = {}
    for _, d in ipairs(DIFFICULTIES) do
        items[#items + 1] = {
            text = d.text,
            mandatory = (d.id == self.difficulty) and "✓" or nil,
            callback = function()
                self.difficulty = d.id
                self.settings:saveSetting("difficulty", d.id)
                self.settings:flush()
                closeMenu()
                self:showMainMenu()
                return true
            end,
        }
    end
    menu = Menu:new{
        title = _("Difficulty"),
        item_table = items,
        width = math.floor(Screen:getWidth() * 0.6),
        height = math.floor(Screen:getHeight() * 0.4),
    }
    UIManager:show(menu)
end

function MazeGenPlugin:showShapeMenu()
    local menu
    local function closeMenu()
        if menu then UIManager:close(menu) end
    end
    local items = {}
    for _, s in ipairs(MazeGen.SHAPES) do
        items[#items + 1] = {
            text = s.text,
            mandatory = (s.id == self.shape) and "✓" or nil,
            callback = function()
                self.shape = s.id
                self.settings:saveSetting("shape", s.id)
                self.settings:flush()
                closeMenu()
                self:showMainMenu()
                return true
            end,
        }
    end
    menu = Menu:new{
        title = _("Maze shape"),
        item_table = items,
        width = math.floor(Screen:getWidth() * 0.6),
        height = math.floor(Screen:getHeight() * 0.7),
    }
    UIManager:show(menu)
end

function MazeGenPlugin:getOutputDir()
    local dir = default_output_dir()
    if lfs.attributes(dir, "mode") == "directory" then
        return dir
    end
    if lfs.mkdir(dir) then
        return dir
    end
    -- Fallback: KOReader's own data dir (always writable).
    dir = DataStorage:getDataDir() .. "/mazes"
    if lfs.attributes(dir, "mode") ~= "directory" then
        lfs.mkdir(dir)
    end
    return dir
end

function MazeGenPlugin:generateMaze()
    local diff = self:getDifficulty()
    local shape_id = MazeGen.resolve_shape(self.shape)
    math.randomseed(os.time())
    local ok, cells = pcall(MazeGen.generate, self.size, diff.braid, shape_id)
    if not ok then
        UIManager:show(InfoMessage:new{
            text = _("Couldn't generate the maze. Try a smaller size."),
        })
        return
    end
    local solution = MazeGen.solve(cells, self.size)
    local shape_label = MazeGen.shape_text(shape_id)
    local pdf = MazePDF.generate(cells, self.size, diff.text, solution, shape_label)
    local dir = self:getOutputDir()
    local fname = string.format("maze-%dx%d-%s-%s-%s.pdf",
        self.size, self.size, diff.id, shape_id, os.date("%Y%m%d-%H%M%S"))
    local path = dir .. "/" .. fname
    local f, err = io.open(path, "wb")
    if not f then
        UIManager:show(InfoMessage:new{
            text = T(_("Couldn't write the maze file:\n%1"), err or "?"),
        })
        return
    end
    f:write(pdf)
    f:close()
    UIManager:show(InfoMessage:new{
        text = T(_("Maze saved!\n%1\n\nFind it in your library to draw on it."), fname),
        timeout = 5,
    })
end

return MazeGenPlugin
