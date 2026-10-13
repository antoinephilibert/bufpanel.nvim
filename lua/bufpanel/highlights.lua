-- Groupes de surbrillance du panneau.
local M = {}

local links = {
  BufPanelHeader = "Title",
  BufPanelCurrent = "Directory",
  BufPanelCurrentMarker = "Special",
  BufPanelModified = "DiagnosticWarn",
  BufPanelDir = "Comment",
  BufPanelHelp = "Comment",
}

--- Définit les groupes. `default = true` laisse l'utilisateur les remplacer.
function M.setup()
  for group, target in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end
end

return M
