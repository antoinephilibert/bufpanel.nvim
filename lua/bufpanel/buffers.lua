-- Liste stable des buffers (ordre de première apparition) et fermeture sécuritaire.
local M = {}

-- Liste ordonnée de bufnr
local order = {}

--- Un buffer est affiché s'il est listé, nommé et de type normal.
---@param bufnr integer
---@return boolean
function M.is_valid(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr)
    and vim.bo[bufnr].buflisted
    and vim.bo[bufnr].buftype == ""
    and vim.api.nvim_buf_get_name(bufnr) ~= ""
end

local function index_of(bufnr)
  for i, b in ipairs(order) do
    if b == bufnr then
      return i
    end
  end
  return nil
end

--- Initialise la liste avec les buffers existants, triés par bufnr.
function M.init()
  order = {}
  local bufs = vim.api.nvim_list_bufs()
  table.sort(bufs)
  for _, bufnr in ipairs(bufs) do
    table.insert(order, bufnr)
  end
end

--- Ajoute un buffer en fin de liste s'il n'y est pas déjà (BufAdd).
---@param bufnr integer
function M.add(bufnr)
  if not index_of(bufnr) then
    table.insert(order, bufnr)
  end
end

--- Retire un buffer de la liste (BufDelete, BufWipeout).
---@param bufnr integer
function M.remove(bufnr)
  local i = index_of(bufnr)
  if i then
    table.remove(order, i)
  end
end

--- Buffers à afficher, dans l'ordre stable.
---@return integer[]
function M.list()
  -- Rattrape les buffers valides qui auraient échappé à BufAdd
  -- (ex. buffer devenu listé après sa création).
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if M.is_valid(bufnr) and not index_of(bufnr) then
      table.insert(order, bufnr)
    end
  end
  local result = {}
  for _, bufnr in ipairs(order) do
    if M.is_valid(bufnr) then
      table.insert(result, bufnr)
    end
  end
  return result
end

--- Choisit le buffer de remplacement pour une fenêtre qui affiche `bufnr`.
---@param win integer
---@param bufnr integer
---@return integer|nil
local function replacement_for(win, bufnr)
  local alt = vim.api.nvim_win_call(win, function()
    return vim.fn.bufnr("#")
  end)
  if alt > 0 and alt ~= bufnr and vim.api.nvim_buf_is_valid(alt) and vim.bo[alt].buflisted then
    return alt
  end
  -- Sinon un voisin dans la liste stable : le suivant, puis le précédent.
  local listed = M.list()
  local pos
  for i, b in ipairs(listed) do
    if b == bufnr then
      pos = i
      break
    end
  end
  if pos then
    return listed[pos + 1] or listed[pos - 1]
  end
  for _, b in ipairs(listed) do
    if b ~= bufnr then
      return b
    end
  end
  return nil
end

--- Ferme un buffer sans fermer les fenêtres qui l'affichent.
--- Refuse si le buffer est modifié.
---@param bufnr integer
---@return boolean closed
function M.close(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  if vim.bo[bufnr].modified then
    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
    vim.notify(
      string.format("bufpanel : « %s » est modifié, enregistrez-le avant de le fermer.", name),
      vim.log.levels.WARN
    )
    return false
  end

  local empty
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    local target = replacement_for(win, bufnr)
    if not target then
      empty = empty or vim.api.nvim_create_buf(true, false)
      target = empty
    end
    vim.api.nvim_win_set_buf(win, target)
  end

  local ok, err = pcall(vim.cmd, "bdelete " .. bufnr)
  if not ok then
    vim.notify("bufpanel : " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  return true
end

return M
