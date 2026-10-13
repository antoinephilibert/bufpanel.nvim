-- Historique des fichiers ouverts, rangé par cwd, persisté en JSON.
local config = require("bufpanel.config")

local M = {}

-- { [cwd] = { "chemin1", "chemin2", ... } }, plus récent en tête
local data = {}
-- cwd modifiés dans cette instance depuis la dernière écriture
local dirty = {}
local timer = nil

local DEBOUNCE_MS = 500

--- Chemin du fichier de persistance.
---@return string
function M.file()
  return vim.fn.stdpath("data") .. "/bufpanel/history.json"
end

--- Normalise un chemin en absolu.
---@param path string
---@return string
function M.normalize(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

--- cwd global normalisé (clé de rangement).
---@return string
function M.cwd()
  return vim.fs.normalize(vim.fn.getcwd(-1, -1))
end

local function is_under(path, dir)
  if dir == "/" then
    return path:sub(1, 1) == "/"
  end
  return path:sub(1, #dir + 1) == dir .. "/"
end

local function exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

--- Lit le fichier JSON. Absent ou corrompu : table vide.
---@return table
local function read_file()
  local fd = io.open(M.file(), "r")
  if not fd then
    return {}
  end
  local content = fd:read("*a")
  fd:close()
  if not content or content == "" then
    return {}
  end
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then
    return {}
  end
  -- Ne garde que les entrées bien formées
  local clean = {}
  for cwd, paths in pairs(decoded) do
    if type(cwd) == "string" and type(paths) == "table" then
      local list = {}
      for _, p in ipairs(paths) do
        if type(p) == "string" then
          table.insert(list, p)
        end
      end
      clean[cwd] = list
    end
  end
  return clean
end

--- Charge l'historique depuis le disque.
function M.load()
  data = read_file()
  dirty = {}
end

--- Fusionne deux listes : `first` en tête, puis les entrées de `second` absentes.
local function merge(first, second, max)
  local seen, result = {}, {}
  for _, list in ipairs({ first or {}, second or {} }) do
    for _, p in ipairs(list) do
      if not seen[p] and #result < max then
        seen[p] = true
        table.insert(result, p)
      end
    end
  end
  return result
end

--- Écrit l'historique. Relit d'abord le fichier pour ne pas écraser
--- ce qu'une autre instance a écrit pour d'autres projets.
function M.save()
  if timer then
    timer:stop()
  end
  if next(dirty) == nil then
    return
  end
  local max = config.options.recent.max_stored
  local disk = read_file()
  for cwd in pairs(dirty) do
    disk[cwd] = merge(data[cwd], disk[cwd], max)
    data[cwd] = disk[cwd]
  end
  dirty = {}

  local file = M.file()
  vim.fn.mkdir(vim.fs.dirname(file), "p")
  local ok, encoded = pcall(vim.json.encode, disk)
  if not ok then
    return
  end
  -- Écriture atomique : fichier temporaire puis renommage
  local tmp = file .. ".tmp." .. vim.uv.os_getpid()
  local fd = io.open(tmp, "w")
  if not fd then
    return
  end
  fd:write(encoded)
  fd:close()
  local renamed = vim.uv.fs_rename(tmp, file)
  if not renamed then
    os.remove(tmp)
  end
end

--- Planifie une écriture (debounce).
function M.schedule_save()
  if not timer then
    timer = vim.uv.new_timer()
  end
  timer:stop()
  timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(M.save))
end

--- Enregistre le fichier d'un buffer en tête de l'historique du cwd courant.
---@param bufnr integer
function M.record(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "" then
    return
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return
  end
  local path = M.normalize(name)
  if not exists(path) then
    return
  end
  local cwd = M.cwd()
  if not is_under(path, cwd) then
    return
  end

  local list = data[cwd] or {}
  if list[1] == path then
    return
  end
  local new = { path }
  for _, p in ipairs(list) do
    if p ~= path and #new < config.options.recent.max_stored then
      table.insert(new, p)
    end
  end
  data[cwd] = new
  dirty[cwd] = true
  M.schedule_save()
end

--- Entrées à afficher pour le cwd courant.
---@param exclude table<string, boolean> chemins normalisés à exclure (buffers ouverts)
---@return string[]
function M.list(exclude)
  local result = {}
  local max = config.options.recent.max_display
  for _, path in ipairs(data[M.cwd()] or {}) do
    if #result >= max then
      break
    end
    if not exclude[path] and exists(path) then
      table.insert(result, path)
    end
  end
  return result
end

return M
