-- Ouverture, fermeture et options de la fenêtre du panneau.
local config = require("bufpanel.config")
local state = require("bufpanel.state")

local M = {}

-- Options locales de la fenêtre du panneau
local WIN_OPTIONS = {
  number = false,
  relativenumber = false,
  signcolumn = "no",
  foldcolumn = "0",
  wrap = false,
  cursorline = true,
  spell = false,
  statuscolumn = "",
  winfixwidth = true,
  list = false,
}

---@param win integer|nil
---@return boolean
local function is_float(win)
  return vim.api.nvim_win_get_config(win).relative ~= ""
end

--- Le panneau est-il ouvert dans l'onglet courant ?
---@return boolean
function M.is_open()
  local win = state.win
  return win ~= nil
    and vim.api.nvim_win_is_valid(win)
    and vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage()
end

--- Fenêtre éligible comme fenêtre d'édition : normale, non flottante, hors panneau.
---@param win integer|nil
---@return boolean
function M.is_edit_win(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return false
  end
  if win == state.win or is_float(win) then
    return false
  end
  local buf = vim.api.nvim_win_get_buf(win)
  return buf ~= state.buf and vim.bo[buf].buftype == ""
end

--- Dernière fenêtre d'édition utilisée, sinon une autre fenêtre normale de l'onglet.
---@return integer|nil
function M.get_edit_win()
  local tab = vim.api.nvim_get_current_tabpage()
  local last = state.last_edit_win
  if M.is_edit_win(last) and vim.api.nvim_win_get_tabpage(last) == tab then
    return last
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if M.is_edit_win(win) then
      return win
    end
  end
  return nil
end

--- Fenêtres non flottantes de l'onglet courant.
---@return integer[]
function M.tab_wins()
  local wins = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if not is_float(win) then
      table.insert(wins, win)
    end
  end
  return wins
end

local function set_keymaps(buf)
  local actions = require("bufpanel.actions")
  local km = config.options.keymaps
  local maps = {
    { km.open, actions.open, "Ouvrir" },
    { km.close_buffer, actions.close_buffer, "Fermer le buffer" },
    { km.toggle_recent, actions.toggle_recent, "Afficher/masquer les récents" },
    { km.close_panel, M.close, "Fermer le panneau" },
  }
  for _, m in ipairs(maps) do
    if m[1] then
      vim.keymap.set("n", m[1], m[2], { buffer = buf, nowait = true, silent = true, desc = "BufPanel : " .. m[3] })
    end
  end
end

--- Crée (ou réutilise) le buffer du panneau.
---@return integer
local function ensure_buf()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    return state.buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  state.buf = buf
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  vim.bo[buf].modifiable = false
  pcall(vim.api.nvim_buf_set_name, buf, "bufpanel://panel")
  set_keymaps(buf)
  vim.bo[buf].filetype = "bufpanel"
  return buf
end

--- Applique les options locales de la fenêtre du panneau.
---@param win integer
function M.apply_win_options(win)
  for name, value in pairs(WIN_OPTIONS) do
    vim.api.nvim_set_option_value(name, value, { win = win, scope = "local" })
  end
end

--- Rend aux options d'une fenêtre créée depuis le panneau leurs valeurs globales.
---@param win integer
local function reset_win_options(win)
  local names = vim.tbl_keys(WIN_OPTIONS)
  vim.api.nvim_win_call(win, function()
    vim.cmd("setlocal " .. table.concat(names, "< ") .. "<")
  end)
end

--- Ouvre le panneau dans l'onglet courant.
--- Une ouverture manuelle (sans `auto`) annule le suivi de la fermeture
--- automatique et accepte les fenêtres déclencheuses déjà présentes.
---@param opts { focus: boolean, auto: boolean }|nil
function M.open(opts)
  opts = opts or {}
  if not opts.auto then
    local autoclose = require("bufpanel.autoclose")
    local tab = vim.api.nvim_get_current_tabpage()
    autoclose.forget(tab)
    autoclose.ignore_current(tab)
  end
  if M.is_open() then
    if opts.focus then
      vim.api.nvim_set_current_win(state.win)
    end
    return
  end
  -- Neovim trop étroit : pas d'ouverture automatique (l'ouverture manuelle reste possible)
  if opts.auto and vim.o.columns < (config.options.min_columns or 0) then
    return
  end
  local buf = ensure_buf()
  local prev = vim.api.nvim_get_current_win()
  -- win = -1 : split au niveau supérieur, tout à gauche (équivalent de `topleft vsplit`)
  local win = vim.api.nvim_open_win(buf, false, {
    split = "left",
    win = -1,
    width = config.options.width,
  })
  state.win = win
  M.apply_win_options(win)
  vim.api.nvim_win_set_width(win, config.options.width)
  require("bufpanel.render").render()
  if opts.focus then
    vim.api.nvim_set_current_win(win)
  elseif vim.api.nvim_win_is_valid(prev) then
    vim.api.nvim_set_current_win(prev)
  end
end

--- Ferme le panneau de l'onglet courant.
--- Une fermeture manuelle (sans `auto`) n'est jamais annulée par une
--- réouverture automatique, même si le panneau était déjà fermé.
---@param opts { auto: boolean }|nil
function M.close(opts)
  if not (opts and opts.auto) then
    require("bufpanel.autoclose").forget(vim.api.nvim_get_current_tabpage())
  end
  if not M.is_open() then
    state.win = nil
    return
  end
  local win = state.win
  if #M.tab_wins() == 1 then
    -- Le panneau est seul : on lui laisse une fenêtre d'édition vide à côté
    vim.api.nvim_win_call(win, function()
      vim.cmd("rightbelow vnew")
    end)
    reset_win_options(vim.api.nvim_get_current_win())
  end
  state.win = nil
  pcall(vim.api.nvim_win_close, win, true)
end

function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

--- Ouvre le panneau si nécessaire et y place le curseur.
function M.focus()
  M.open({ focus = true })
end

--- Affiche `bufnr` dans la fenêtre d'édition (créée à droite du panneau
--- si besoin) et y place le curseur. Jamais dans la fenêtre du panneau.
---@param bufnr integer
---@return integer|nil win
function M.show_in_edit_win(bufnr)
  local win = M.get_edit_win()
  if win then
    vim.api.nvim_win_set_buf(win, bufnr)
  else
    local opts = { split = "right", win = -1 }
    if M.is_open() then
      opts = { split = "right", win = state.win }
    end
    win = vim.api.nvim_open_win(bufnr, false, opts)
    reset_win_options(win)
    if M.is_open() then
      vim.api.nvim_win_set_width(state.win, config.options.width)
    end
  end
  vim.api.nvim_set_current_win(win)
  state.last_edit_win = win
  return win
end

--- Si un autre buffer a été chargé dans la fenêtre du panneau, le déplacer
--- dans la fenêtre d'édition et remettre le buffer du panneau.
function M.restore_panel_buf()
  local win = state.win
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    return
  end
  local intruder = vim.api.nvim_win_get_buf(win)
  if intruder == state.buf then
    return
  end
  vim.api.nvim_win_set_buf(win, state.buf)
  M.apply_win_options(win)
  M.show_in_edit_win(intruder)
  require("bufpanel.render").render()
end

return M
