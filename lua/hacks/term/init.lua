local api = vim.api
local g = vim.g
local M = {}
local set_buf = api.nvim_set_current_buf

g.nvchad_terms = {}

-- remove the previous callback table; we'll create per-terminal named functions on M
M._click_callbacks = {}

-- add a simple counter to number terminals
local term_count = 0

local pos_data = {
  sp = { resize = "height", area = "lines" },
  vsp = { resize = "width", area = "columns" },
  ["bo sp"] = { resize = "height", area = "lines" },
  ["bo vsp"] = { resize = "width", area = "columns" },
}

-- local nvconfig = require "nvconfig"
-- local config = nvconfig.term

local config = {
  startinsert = true,
  base46_colors = false,
  winopts = { number = false, relativenumber = false },
  sizes = { sp = 0.3, vsp = 0.41, ["bo sp"] = 0.3, ["bo vsp"] = 0.41 },
  float = {
    relative = "editor",
    row = 0.3,
    col = 0.25,
    width = 0.5,
    height = 0.4,
    border = "single",
  },
}

-- create some winbar highlight links (background, button and close "x")

local errColor = vim.api.nvim_get_hl(0, { name = "ErrorMsg" })
local stlColor = vim.api.nvim_get_hl(0, { name = "StatusLine" })
local btnAColor = vim.api.nvim_get_hl(0, { name = "Directory" })

pcall(vim.cmd, "highlight default link NvTermWinbar StatusLine")
pcall(vim.cmd, "highlight default link NvTermWinbarButtonActive Directory")
pcall(vim.cmd, "highlight default link NvTermWinbarButton StatusLine")
pcall(vim.cmd, "highlight default link NvTermWinbarCloseActive ErrorMsg")
pcall(vim.cmd, "highlight default NvTermWinbarAdd guifg=NvimDarkGrey1 guibg=#98c379")


vim.api.nvim_set_hl(0, "NvTermWinbarButtonActive", {
  fg = btnAColor.fg,
  bg = btnAColor.bg,
  bold = true,
})

vim.api.nvim_set_hl(0, "NvTermWinbarButton", {
  fg = stlColor.fg,
  bg = stlColor.bg,
  bold = false,
})

vim.api.nvim_set_hl(0, "NvTermWinbarClose", {
  fg = errColor.fg,
  bg = stlColor.bg,
  bold = errColor.bold,
})

if config.base46_colors then
  dofile(vim.g.base46_cache .. "term")
end

-- used for initially resizing terms
vim.g.nvhterm = false
vim.g.nvvterm = false

-------------------------- util funcs -----------------------------
local function save_term_info(index, val)
  local terms_list = g.nvchad_terms
  terms_list[tostring(index)] = val
  g.nvchad_terms = terms_list
end

local function opts_to_id(id)
  for _, opts in pairs(g.nvchad_terms) do
    if opts.id == id then
      return opts
    end
  end
end

local function get_terms_for_window(win)
  local filtered_terms = {}
  for buf, opts in pairs(g.nvchad_terms) do
    if opts.win == win then
      filtered_terms[buf] = opts
    end
  end
  return filtered_terms
end

local function get_adjacent_buf(terms, main_buf)
  -- sorting
  local ids = {}
  for k in pairs(terms) do
    table.insert(ids, k)
  end
  table.sort(ids, function(a, b) return a < b end)

  -- find index
  for i, k in pairs(ids) do
    if k == main_buf then
      if i < #ids then -- if not last, take right
        return ids[i + 1]
      else
        return ids[i - 1] -- last, take left
      end
    end
  end
end

local function focus_window(win)
  if win and api.nvim_win_is_valid(win) then
    pcall(api.nvim_set_current_win, win)
  end
end

local function create_float(buffer, float_opts)
  local opts = vim.tbl_deep_extend("force", config.float, float_opts or {})

  opts.width = math.ceil(opts.width * vim.o.columns)
  opts.height = math.ceil(opts.height * vim.o.lines)
  opts.row = math.ceil(opts.row * vim.o.lines)
  opts.col = math.ceil(opts.col * vim.o.columns)

  vim.api.nvim_open_win(buffer, true, opts)
end

local function format_cmd(cmd)
  return type(cmd) == "string" and cmd or cmd()
end

function M.print_buff(buf)
  return function ()
    vim.notify(buf)
  end
end


local function get_active_term_buff()
  for key, _ in pairs(g.nvchad_terms) do
    buf = tonumber(key)
    if vim.api.nvim_buf_is_valid(buf) and vim.fn.bufwinid(buf) ~= -1 then
      return buf
    end
  end
end

local function create_tab(buf, active, name)
  local is_active = active and "Active" or ""
  local tab_name = name or ("term: b" .. tostring(buf))
  return ""
    .. "%#NvTermWinbarButton" .. is_active .. "#"
    .. "%@v:lua.require'hacks.term'.focus_term'" .. tostring(buf) .. "'@"
    .. "   " .. tab_name .. " "
    .. "%X"
    .. "%#NvTermWinbarClose" .. is_active .. "#"
    .. "%@v:lua.require'hacks.term'.emit_close'" .. tostring(buf) .. "'@"
    .. " "
    .. "%X"
    .. "%#NvTermWinbar#"
end



local function render_winbar(win)
  -- set a clickable winbar above the terminal window with its number and a close button
  local tabs = ""
  local ids = {} -- for sorting
  local terms = get_terms_for_window(win)
  for ix, _ in pairs(terms) do
    table.insert(ids, ix)
  end

  table.sort(ids, function(a, b) return a < b end)

  for _, id in pairs(ids) do
    local is_active = api.nvim_buf_is_valid(terms[id].buf) and vim.fn.bufwinid(terms[id].buf) ~= -1
    tabs = tabs .. create_tab(terms[id].buf, is_active, terms[id].name)
  end

  local winbar = ""
    .. "%#NvTermWinbar#"               -- overall winbar (darker background)
    .. tabs
    .. " "               -- reset back to background so close doesn't stretch
    -- .. create_tab(num + 1, false)
    .. "%#NvTermWinbarAdd#"          -- small add-button highlight
    .. "%@v:lua.require'hacks.term'.add_term_to_window'".. tostring(win) .."'@" -- TODO make global command
    .. " + "
    .. "%X"
    .. "%#NvTermWinbar#"
    .. "%="                             -- push remaining space to the right (keeps tabs on left)

  pcall(api.nvim_win_set_option, win, "winbar", winbar)
end

-- focus terminal by its assigned number (used by tab click)
function M.focus_term(buf_str)
  local buf = tonumber(buf_str)
  return function ()
    -- hide active term
    local active_term_buf = get_active_term_buff()
    local win = g.nvchad_terms[buf_str].win
    -- open new term
    if vim.api.nvim_buf_is_valid(buf) and vim.fn.bufwinid(buf) == -1 then
      vim.api.nvim_buf_set_option(active_term_buf, "bufhidden", "hide")
      focus_window(win)
      vim.api.nvim_set_current_buf(buf)
      render_winbar(win)
    end
  end
end

function M.emit_close(buf_str)
  return function ()
    api.nvim_exec_autocmds("TermClose", { buffer = tonumber(buf_str) })
    return ""
  end
end

-- close terminal by its assigned number (used by callbacks)
function M.close_term(buf_str)
  local buf = tonumber(buf_str)
  if not buf then return "" end

  local win = g.nvchad_terms[buf_str].win -- bufwinid() can be empty
  local is_active = api.nvim_buf_is_valid(buf) and vim.fn.bufwinid(buf) ~= -1
  local sibling_terms = get_terms_for_window(win)

  -- only term in window, close the window, delete buffer
  if vim.tbl_count(sibling_terms) <= 1 then
    pcall(api.nvim_win_close, win, true)
    if buf and api.nvim_buf_is_valid(buf) then
      pcall(api.nvim_buf_delete, buf, { force = true })
    end
    save_term_info(buf, nil)
    return ""
  end

  -- if current term is active, focus sibling first
  if is_active then
    local sibling_buf = get_adjacent_buf(sibling_terms, buf_str)
    M.focus_term(sibling_buf)()
  end

  -- delete the buffer
  if buf and api.nvim_buf_is_valid(buf) then
    pcall(api.nvim_buf_delete, buf, { force = true })
  end
  save_term_info(buf, nil)
  render_winbar(win)
  return ""
end

M.display = function(opts)
  if opts.pos == "float" then
    create_float(opts.buf, opts.float_opts)
  elseif not opts.headless then
    vim.cmd(opts.pos)
  end

  local win = opts.win or api.nvim_get_current_win()
  opts.win = win

  vim.bo[opts.buf].buflisted = false
  vim.bo[opts.buf].ft = "NvTerm_" .. opts.pos:gsub(" ", "")

  if config.startinsert then
    vim.cmd "startinsert"
  end

  -- resize non floating wins initially + or only when they're toggleable
  if (opts.pos == "sp" and not vim.g.nvhterm) or (opts.pos == "vsp" and not vim.g.nvvterm) or (opts.pos ~= "float") then
    local pos_type = pos_data[opts.pos]
    local size = opts.size and opts.size or config.sizes[opts.pos]
    local new_size = vim.o[pos_type.area] * size
    api["nvim_win_set_" .. pos_type.resize](0, math.floor(new_size))
  end

  api.nvim_win_set_buf(win, opts.buf)

  local winopts = vim.tbl_deep_extend("force", config.winopts, opts.winopts or {})

  for k, v in pairs(winopts) do
    vim.wo[win][k] = v
  end

  save_term_info(opts.buf, opts)
  render_winbar(win)
end

local function create(opts)
  opts.buf = opts.buf or vim.api.nvim_create_buf(false, true)

  -- handle cmd opt
  local shell = vim.o.shell
  local cmd = shell

  -- kinda hacky but it works
  local dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
  local osc_script = dir .. "/bash-osc-integration.sh"

  if opts.cmd and opts.buf then
    cmd = { shell, "--init-file", osc_script, "-c", format_cmd(opts.cmd) .. "; " .. shell }
  else -- TODO add, non bash support
    cmd = { shell, "--init-file", osc_script }
  end

  M.display(opts)

  opts.termopen_opts = vim.tbl_extend("force", opts.termopen_opts or {}, {
    detach = false,
    env = vim.tbl_extend("force", vim.fn.environ(), {
      NVIM_INJECTION = "1", -- todo add to config
    }),
  })
  if not opts.nvim_term_exists then
    vim.fn.termopen(cmd, opts.termopen_opts)
    opts.nvim_term_exists = true
    term_count = term_count + 1
  end

  save_term_info(opts.buf, opts)

  if not opts.headless then
    vim.g.nvhterm = opts.pos == "sp"
    vim.g.nvvterm = opts.pos == "vsp"
  end
end


----------------------- tabs management ------------------------------

function M.add_term_to_window(w)
  return function ()
    --vim.notify('Spawn terminal on window: ' .. tostring(w))
    local win = tonumber(w or vim.api.nvim_get_current_win())
    if not vim.api.nvim_win_is_valid(win) then
      return
    end

    -- get current buffer in the window
    local old_buf = vim.api.nvim_win_get_buf(win)

    -- make sure buffer won't be deleted when window is replaced
    vim.api.nvim_buf_set_option(old_buf, "bufhidden", "hide")

    -- create a new empty buffer
    local new_buf = vim.api.nvim_create_buf(false, true) -- listed=false, scratch=true

    -- focus window
    focus_window(win)

    local pos = g.nvchad_terms[tostring(old_buf)].pos

    create({ buf = new_buf, win = win, headless = true, pos = pos})
    -- set the new buffer in the same window
    vim.api.nvim_win_set_buf(win, new_buf)

    render_winbar(win)

    return old_buf, new_buf
  end
end


--------------------------- user api -------------------------------
M.new = function(opts)
  create(opts)
end

M.toggle = function(opts)
  local x = opts_to_id(opts.id)
  opts.buf = x and x.buf or nil

  if (x == nil or not api.nvim_buf_is_valid(x.buf)) or vim.fn.bufwinid(x.buf) == -1 then
    create(opts)
  else
    api.nvim_win_close(x.win, true)
  end
end

-- spawns term with *cmd & runs the *cmd if the keybind is run again
M.runner = function(opts)
  local x = opts_to_id(opts.id)
  local clear_cmd = opts.clear_cmd or "clear; "
  opts.buf = x and x.buf or nil

  -- if buf doesnt exist
  if x == nil then
    create(opts)
  else
    -- window isnt visible
    if vim.fn.bufwinid(x.buf) == -1 then
      M.display(opts)
    end

    local cmd = format_cmd(opts.cmd)

    if x.buf == api.nvim_get_current_buf() then
      vim.cmd "bp"
      cmd = format_cmd(opts.cmd)
      set_buf(x.buf)
    end

    local job_id = vim.b[x.buf].terminal_job_id
    vim.api.nvim_chan_send(job_id, clear_cmd .. cmd .. " \n")
  end
end

--------------------------- autocmds -------------------------------
api.nvim_create_autocmd("TermClose", {
  callback = function(args)
    M.close_term(tostring(args.buf))
  end,
})

api.nvim_create_autocmd({ 'TermRequest' }, {
  desc = 'Handles OSC 7 title events',
  callback = function(ev)
    local buf = ev.buf
    local file_table = vim.split(ev.file, "/")
    local shell_name = file_table[#file_table]
    local name

    local val, _ = string.gsub(ev.data.sequence, '\27]633;', '')
    --- @diagnostic disable-next-line: deprecated
    local code, value = unpack(vim.split(val, ";"))
    if code == "E" and value then -- base proc, change dir
      name = vim.split(value, " ")[1] -- indexes start at 1 in lua!
    else
      name = shell_name
    end

    local term = g.nvchad_terms[tostring(buf)]
    term.name = name
    save_term_info(buf, term)
    render_winbar(term.win)
  end
})

return M
