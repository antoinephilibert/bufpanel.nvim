# Prompt pour Claude Code : fermeture automatique du panneau

Le plugin `bufpanel.nvim` existe déjà dans ce repo. Ajoute une fonctionnalité : le panneau se ferme automatiquement quand une fenêtre d'un plugin précis s'ouvre, et se rouvre quand cette fenêtre se ferme. Lis d'abord le code existant (`config.lua`, `state.lua`, `panel.lua`, `init.lua`) et intègre-toi à sa structure. Code en anglais, commentaires et documentation en français.

## Configuration

Ajouter deux options :

```lua
close_on_filetypes = {},  -- filetypes qui ferment le panneau
reopen_after = true,      -- rouvrir le panneau quand ces fenêtres se ferment
```

Liste vide par défaut : aucun changement de comportement pour qui ne configure rien.

## Comportement

### Fermeture

- Une seule fonction de vérification, déclenchée par deux événements : `BufWinEnter` et `FileType`. Les deux sont nécessaires parce que certains plugins règlent le filetype après avoir affiché le buffer, d'autres avant. Exécuter la vérification avec `vim.schedule` et la regrouper pour éviter un double traitement.
- La vérification ne fait rien si `close_on_filetypes` est vide ou si le panneau est fermé dans l'onglet courant.
- Elle parcourt les fenêtres de l'onglet courant (flottantes comprises), en excluant celle du panneau. Si le filetype d'une de ces fenêtres est dans la liste, fermer le panneau.
- Mémoriser dans l'état de l'onglet l'id de chaque fenêtre déclencheuse (`auto_closed_by`, un ensemble de winid). Ce suivi est par onglet.

### Réouverture

- Seulement si `reopen_after = true` et que le panneau a été fermé par ce mécanisme.
- Sur `WinClosed` : retirer le winid de `auto_closed_by`. Quand l'ensemble devient vide, rouvrir le panneau via `vim.schedule`, sans prendre le focus.
- Avant de rouvrir, vérifier : l'onglet existe encore, Neovim n'est pas en train de quitter (`vim.v.exiting == vim.NIL`), le panneau n'est pas déjà ouvert, il reste au moins une fenêtre d'édition normale dans l'onglet.

### Interaction avec les actions manuelles

- `:BufPanelClose`, `:BufPanelToggle` (fermeture) ou `q` : vider `auto_closed_by`. Une fermeture manuelle n'est jamais annulée par une réouverture automatique.
- `:BufPanelOpen`, `:BufPanelToggle` (ouverture) ou `:BufPanelFocus` pendant qu'une fenêtre déclencheuse est ouverte : vider `auto_closed_by` et ouvrir. Le panneau ne se referme pas tant qu'une nouvelle fenêtre déclencheuse n'apparaît pas.

### Démarrage

- Au moment de l'ouverture automatique au démarrage, si une fenêtre déclencheuse est déjà présente (ex. `nvim .` qui ouvre neo-tree), ne pas ouvrir le panneau.
- Si `reopen_after = true`, enregistrer cette fenêtre dans `auto_closed_by` pour que le panneau s'ouvre quand elle se ferme.

## Documentation

- README : ajouter les deux options dans la configuration complète, plus une section « Fermeture automatique » avec un exemple :

  ```lua
  opts = {
    close_on_filetypes = { "neo-tree", "NvimTree", "fugitive" },
  },
  ```

  Expliquer comment trouver le filetype d'un plugin (`:set ft?` dans sa fenêtre) et préciser que les fenêtres flottantes sont aussi prises en compte, même si l'effet est peu visible puisqu'elles couvrent déjà l'écran. Mentionner que les plugins qui s'ouvrent dans un nouvel onglet (ex. Diffview) n'ont pas besoin d'être listés.
- `doc/bufpanel.txt` : mêmes ajouts, version courte.

## Validation

- `luac -p` sur les fichiers Lua modifiés.
- Test headless avec un filetype factice :
  1. `setup({ open_on_startup = false, close_on_filetypes = { "bptest" } })`, puis `:BufPanelOpen`.
  2. `vsplit`, `enew`, `setlocal filetype=bptest` : vérifier que le panneau est fermé.
  3. Fermer cette fenêtre : vérifier que le panneau est rouvert.
  4. Refaire l'étape 2, puis `:BufPanelClose` (déjà fermé) et fermer la fenêtre : vérifier que le panneau reste fermé.
  Faire échouer le test avec `cquit 1` si une assertion échoue, et corriger jusqu'à ce qu'il passe.
- Terminer avec une courte liste de vérifications manuelles (neo-tree ouvert puis fermé, fermeture manuelle pendant que neo-tree est ouvert, `nvim .` au démarrage, `:q` sur la dernière fenêtre d'édition pendant que neo-tree est ouvert).
