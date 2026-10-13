-- Valeurs par défaut et fusion avec les options de l'utilisateur.
local M = {}

M.defaults = {
  width = 32,
  open_on_startup = true,
  startup_exclude_filetypes = { "gitcommit", "gitrebase" },
  icons = true,
  show_help = true,
  close_on_filetypes = {}, -- filetypes qui ferment le panneau
  reopen_after = true, -- rouvrir le panneau quand ces fenêtres se ferment
  recent = {
    visible = true, -- section dépliée au démarrage
    max_display = 15, -- entrées affichées
    max_stored = 50, -- entrées conservées par cwd
  },
  keymaps = {
    open = "<CR>",
    close_buffer = "x",
    toggle_recent = "R",
    close_panel = "q",
  },
}

M.options = vim.deepcopy(M.defaults)

--- Fusionne les options utilisateur avec les valeurs par défaut.
---@param opts table|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M
