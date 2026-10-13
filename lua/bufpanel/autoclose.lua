-- Fermeture automatique du panneau quand une fenêtre de certains plugins
-- s'ouvre (`close_on_filetypes`), et réouverture quand elles se ferment.
local config = require("bufpanel.config")
local state = require("bufpanel.state")

local M = {}

--- Fenêtres de l'onglet (flottantes comprises, panneau exclu) dont le filetype
--- ferme le panneau. Les fenêtres déjà acceptées par une ouverture manuelle
--- sont ignorées.
---@param tab integer
---@return integer[]
function M.find_triggers(tab)
  local fts = config.options.close_on_filetypes or {}
  local wins = {}
  if #fts == 0 then
    return wins
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if win ~= state.win and not vim.w[win].bufpanel_ignore then
      local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
      if vim.tbl_contains(fts, ft) then
        table.insert(wins, win)
      end
    end
  end
  return wins
end

--- Ajoute des fenêtres déclencheuses au suivi de l'onglet.
---@param tab integer
---@param wins integer[]
function M.remember(tab, wins)
  local set = state.auto_closed_by[tab] or {}
  for _, win in ipairs(wins) do
    set[win] = true
  end
  state.auto_closed_by[tab] = set
end

--- Oublie les fenêtres déclencheuses de l'onglet : plus de réouverture automatique.
---@param tab integer
function M.forget(tab)
  state.auto_closed_by[tab] = nil
end

--- Marque les fenêtres déclencheuses présentes comme acceptées : après une
--- ouverture manuelle, elles ne referment plus le panneau. La variable de
--- fenêtre disparaît avec la fenêtre.
---@param tab integer
function M.ignore_current(tab)
  for _, win in ipairs(M.find_triggers(tab)) do
    vim.w[win].bufpanel_ignore = true
  end
end

--- Ferme le panneau si une fenêtre déclencheuse est présente dans l'onglet courant.
function M.check()
  local panel = require("bufpanel.panel")
  if #(config.options.close_on_filetypes or {}) == 0 or not panel.is_open() then
    return
  end
  local tab = vim.api.nvim_get_current_tabpage()
  local triggers = M.find_triggers(tab)
  if #triggers == 0 then
    return
  end
  M.remember(tab, triggers)
  panel.close({ auto = true })
end

--- Planifie une seule vérification pour toute une rafale d'événements.
function M.request_check()
  if state.check_pending then
    return
  end
  state.check_pending = true
  vim.schedule(function()
    state.check_pending = false
    M.check()
  end)
end

--- Rouvre le panneau dans `tab` si plus aucune fenêtre déclencheuse n'y est suivie.
---@param tab integer
function M.reopen(tab)
  local set = state.auto_closed_by[tab]
  if not set or next(set) ~= nil then
    return
  end
  if not vim.api.nvim_tabpage_is_valid(tab) or vim.v.exiting ~= vim.NIL then
    state.auto_closed_by[tab] = nil
    return
  end
  -- Le panneau ne s'ouvre que dans l'onglet courant : on réessaie sur TabEnter.
  if tab ~= vim.api.nvim_get_current_tabpage() then
    return
  end
  local panel = require("bufpanel.panel")
  if panel.is_open() then
    state.auto_closed_by[tab] = nil
    return
  end
  -- D'autres fenêtres déclencheuses sont apparues pendant la fermeture : on attend aussi leur fermeture.
  local triggers = M.find_triggers(tab)
  if #triggers > 0 then
    M.remember(tab, triggers)
    return
  end
  state.auto_closed_by[tab] = nil
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if panel.is_edit_win(win) then
      panel.open({ auto = true })
      return
    end
  end
end

--- Retire une fenêtre fermée du suivi. Quand l'onglet n'en suit plus aucune,
--- le panneau est rouvert.
---@param win integer
function M.on_win_closed(win)
  for tab, set in pairs(state.auto_closed_by) do
    if set[win] then
      set[win] = nil
      if next(set) == nil then
        if config.options.reopen_after then
          vim.schedule(function()
            M.reopen(tab)
          end)
        else
          state.auto_closed_by[tab] = nil
        end
      end
      return
    end
  end
end

return M
