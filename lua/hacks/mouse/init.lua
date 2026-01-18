local function open_in_file_manager()
  local path = vim.fn.expand("<cfile>")
  if vim.fn.isdirectory(path) == 0 then
    path = vim.fn.fnamemodify(path, ":h")  -- use parent folder for files
  end

  local cmd
  if vim.fn.has("mac") == 1 then
    cmd = { "open", path }
  elseif vim.fn.has("unix") == 1 then
    cmd = { "xdg-open", path }
  elseif vim.fn.has("win32") == 1 then
    cmd = { "explorer", path }
  end

  if cmd then
    vim.fn.jobstart(cmd, { detach = true })
  end
end

local M = {}

function M.setup() 
  -- expose globally
  _G.open_in_file_manager = open_in_file_manager

  vim.cmd([[anoremenu PopUp.Open\ in\ File\ Manager :lua open_in_file_manager()<CR>]])
end

return M
