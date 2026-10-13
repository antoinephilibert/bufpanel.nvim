-- Actions du panneau. Elles lisent la table ligne -> item, jamais le texte.
local state = require("bufpanel.state")

local M = {}

---@return table|nil
local function item_under_cursor()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return state.line_items[row]
end

--- Ouvre l'entrée sous le curseur dans la fenêtre d'édition.
function M.open()
  local item = item_under_cursor()
  if not item then
    return
  end
  local panel = require("bufpanel.panel")
  if item.kind == "buffer" then
    if vim.api.nvim_buf_is_valid(item.bufnr) then
      panel.show_in_edit_win(item.bufnr)
    end
  elseif item.kind == "recent" then
    local bufnr = vim.fn.bufadd(item.path)
    vim.bo[bufnr].buflisted = true
    panel.show_in_edit_win(bufnr)
  elseif item.kind == "header" and item.section == "recent" then
    M.toggle_recent()
  end
end

--- Ferme le buffer sous le curseur. Sans effet dans les Récents.
function M.close_buffer()
  local item = item_under_cursor()
  if item and item.kind == "buffer" then
    require("bufpanel.buffers").close(item.bufnr)
  end
end

--- Déplie ou replie la section Récents.
function M.toggle_recent()
  state.recent_visible = not state.recent_visible
  require("bufpanel.render").render()
end

return M
