-- Install languages for cspell

local function split(text)
  local result = {}
  for word in string.gmatch(text .. ",", "(.-),") do
    table.insert(result, word:match("^%s*(.-)%s*$"))
  end
  return result
end

local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

-- Lang support
local lang_types = {
  pl = "dict-pl_pl",
  nl = "dict-nl-nl",
  hr = "dict-hr-hr",
  it = "dict-it-it",
}

local function dir_exists(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil and stat.type == "directory"
end

local function strip_comments(text)
  -- remove // comments
  text = text:gsub("//[^\n]*", "")
  -- remove /* */ comments
  text = text:gsub("/%*.-%*/", "")
  return text
end

local function is_package_installed(package_name)
  local package_json_path = vim.fn.stdpath("data") .. "/mason/packages/cspell/package.json"
  local lines = vim.fn.readfile(package_json_path)
  if not lines or #lines == 0 then
    return false
  end

  local ok, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok or type(data) ~= "table" then
    return false
  end

  local deps = data.dependencies or {}
  local dev_deps = data.devDependencies or {}

  return deps[package_name] ~= nil or dev_deps[package_name] ~= nil
end

local function list_lang_types()
  print("List of supported languages:")
  for lang in pairs(lang_types) do
    print("-", lang)
  end
end

local function update_cspell_conf(lang)
  local cspell_json_path = vim.fn.stdpath("config") .. "/cspell.json"
  local import_name = "@cspell/" .. lang_types[lang] .. "/cspell-ext.json"
  local lang_meta = vim.fn.stdpath("data") .. "/mason/packages/cspell/node_modules/" .. import_name

  local cspell_lines = vim.fn.readfile(cspell_json_path)
  local meta_lines = vim.fn.readfile(lang_meta)

  -- get language code from meta data (Different formats eg. pl-pl pt_PT)
  local meta_ok, meta_data = pcall(vim.json.decode, strip_comments(table.concat(meta_lines, "\n")))
  if not meta_ok or type(meta_data) ~= "table" then
    print("[Error] decoding cspell JSON file!")
    return
  end

  local lang_code = meta_data and meta_data.id

  local cspell_ok, data = pcall(vim.json.decode, table.concat(cspell_lines, "\n"))
  if not cspell_ok or type(data) ~= "table" then
    print("[Error] decoding cspell JSON file!")
    return
  end

  local imports = data.import or {}
  local languages = split(data.language) or {}
  local dictionaries = data.dictionaries or { "en" }

  if not contains(imports, import_name) then
    table.insert(imports, import_name)
  end

  if not contains(languages, lang) then
    table.insert(languages, lang)
  end

  if not contains(dictionaries, lang_code) then
    table.insert(dictionaries, lang_code)
  end

  data["language"] = table.concat(languages, ",")
  data["import"] = imports
  data["dictionaries"] = dictionaries

  local modified_json = vim.json.encode(data)

  -- Split the string into lines for writefile
  local output_lines = {}
  for line in modified_json:gmatch("[^\n]+") do
    table.insert(output_lines, line)
  end

  -- Write the modified lines back to a new file
  vim.fn.writefile(output_lines, cspell_json_path)
end

local M = {}

function M.setup()
  vim.api.nvim_create_user_command("CSpellLangInstall", function(opts)
    local selected_lang = lang_types[opts.args]
    local mason_dir = vim.fn.stdpath("data") .. "/mason"

    -- Check are we even support this language
    if selected_lang == nil then
      print("Could not find this language in supported languages")
      list_lang_types()
      return
    end

    -- Check if mason installed
    if not dir_exists(mason_dir) then
      print("[ERROR] Could not find Mason dir. Is mason installed?")
      return
    end

    -- Check if cspell installed
    if not dir_exists(mason_dir .. "/packages/cspell") then
      print("[ERROR] Could not find cspell dir. Is cspell installed?")
    end

    -- Check if language is not yet installed
    if is_package_installed("@cspell/" .. selected_lang) then
      print("CSpell", opts.args, "dictionary is already installed")
      return
    end

    -- Finally install language

    print("Installing packages ...")
    local output =
        vim.fn.system("cd " .. mason_dir .. "/packages/cspell && npm install " .. "@cspell/" .. selected_lang)
    print(output)

    update_cspell_conf(opts.args)
    print("cspell.json updated!")
  end, {
    nargs = 1,
  })
end

return M
