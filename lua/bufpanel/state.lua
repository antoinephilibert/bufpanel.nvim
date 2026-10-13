-- État partagé entre les modules.
local M = {
  -- Fenêtre du panneau (onglet courant seulement en v1)
  win = nil,
  -- Buffer du panneau, réutilisé d'une ouverture à l'autre
  buf = nil,
  -- Dernière fenêtre d'édition utilisée (hors panneau et flottantes)
  last_edit_win = nil,
  -- Section Récents dépliée ?
  recent_visible = true,
  -- Table ligne (1-based) -> item { kind, bufnr?, path? }
  line_items = {},
  -- Un rafraîchissement est déjà planifié
  refresh_pending = false,
  -- Garde contre les boucles pendant la fermeture automatique
  closing = false,
  -- Onglet -> ensemble { [winid] = true } des fenêtres qui ont fermé le panneau
  auto_closed_by = {},
  -- Une vérification des fenêtres déclencheuses est déjà planifiée
  check_pending = false,
}

return M
