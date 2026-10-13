# Prompt pour Claude Code : bufpanel.nvim

Tu travailles dans un repo vide qui deviendra un plugin Neovim nommé `bufpanel.nvim`. Construis le plugin complet en Lua, plus un README en français. Code et identifiants en anglais, commentaires et documentation en français.

## Objectif

Un panneau latéral (style neo-tree) ouvert à gauche, qui affiche :

1. **Buffers** : les fichiers ouverts dans les buffers. Section toujours présente.
2. **Récents** : l'historique des fichiers ouverts dernièrement dans le `cwd` courant. Section repliable.

Le panneau s'ouvre automatiquement au démarrage de Neovim (configurable) et peut être fermé ou rouvert à tout moment.

## Affichage cible

```
 BUFFERS (4)
 ▎ 󰢱 init.lua        lua/cfg
    panel.lua    ●  lua/bp
    main.rs         src
    Cargo.toml

 RÉCENTS (8)                 ▾
    history.lua     lua/bp
    README.md
    lib.rs          src
    config.toml     .cargo
 ─────────────────────────────
 x fermer  ⏎ ouvrir  R récents
```

- Nom du fichier en premier, dossier parent (relatif au `cwd`) aligné à droite et grisé. Fichier à la racine du `cwd` : pas de dossier.
- Si deux entrées affichées ont le même nom, ajouter assez de segments de chemin pour les distinguer.
- `▎` marque le buffer courant (celui de la dernière fenêtre d'édition), `●` marque un buffer modifié.
- Icônes via `nvim-web-devicons` si installé et si `icons = true`. Sinon, aucune icône et aucune erreur.
- En-têtes avec compteur. La section Récents affiche `▾` ouverte, `▸` repliée.
- Ligne d'aide en bas, désactivable.
- Le nom trop long est tronqué avec `…` pour respecter la largeur du panneau.

## Configuration par défaut

```lua
require("bufpanel").setup({
  width = 32,
  open_on_startup = true,
  startup_exclude_filetypes = { "gitcommit", "gitrebase" },
  icons = true,
  show_help = true,
  recent = {
    visible = true,    -- section dépliée au démarrage
    max_display = 15,  -- entrées affichées
    max_stored = 50,   -- entrées conservées par cwd
  },
  keymaps = {
    open = "<CR>",
    close_buffer = "x",
    toggle_recent = "R",
    close_panel = "q",
  },
})
```

Fusion profonde avec `vim.tbl_deep_extend("force", defaults, opts)`. Un keymap mis à `false` est désactivé.

## Commandes

- `:BufPanelOpen`, `:BufPanelClose`, `:BufPanelToggle`
- `:BufPanelFocus` : ouvre le panneau si nécessaire et y place le curseur.

Aucun keymap global n'est créé par le plugin. L'utilisateur les définit lui-même (exemple dans le README avec `keys` de Lazy).

## Règles fonctionnelles

### Section Buffers

- Inclure seulement les buffers listés (`buflisted`), avec un nom, `buftype == ""`.
- **Ordre stable** : ordre de première apparition. Maintenir une liste interne de `bufnr`, ajoutée sur `BufAdd`, retirée sur `BufDelete`/`BufWipeout`. À l'initialisation, trier les buffers existants par `bufnr`. L'ordre ne change jamais quand on navigue entre les buffers.
- `x` sur un buffer :
  - S'il est modifié : refuser, `vim.notify` niveau WARN, rien d'autre.
  - Sinon : le supprimer sans fermer les fenêtres qui l'affichent. Pour chaque fenêtre qui l'affiche, basculer d'abord vers le buffer alternatif s'il est valide et listé, sinon vers un autre buffer listé, sinon vers un nouveau buffer vide. Ensuite `bdelete`.
  - Le fichier reste dans l'historique et apparaît donc dans Récents dès qu'il n'est plus ouvert.

### Section Récents

- Historique propre au plugin, **filtré par `cwd`** (cwd global, `vim.fn.getcwd()`).
- Enregistrer un fichier sur `BufEnter` si : `buftype == ""`, nom non vide, fichier existant sur disque. Chemin absolu normalisé. Le fichier passe en tête de la liste de ce `cwd`, sans doublon.
- Clé de rangement : le `cwd` au moment de l'ouverture. Si le fichier n'est pas sous ce `cwd`, ne pas l'enregistrer.
- **Exclure** les fichiers actuellement ouverts dans la section Buffers.
- Ignorer à l'affichage les fichiers qui n'existent plus.
- Ordre : plus récent en haut (ici le MRU est voulu).
- `x` dans Récents : aucun effet. On ne retire rien de l'historique.
- Persistance : `vim.fn.stdpath("data") .. "/bufpanel/history.json"`, structure `{ [cwd] = { "chemin1", "chemin2", ... } }`. Écriture à chaque changement avec un debounce (environ 500 ms, `vim.uv.new_timer`) et sur `VimLeavePre`. À l'écriture, relire le fichier et fusionner pour le `cwd` courant seulement, pour ne pas écraser ce qu'une autre instance de Neovim a écrit pour d'autres projets. JSON corrompu ou absent : repartir d'une table vide, sans erreur bloquante.
- Sur `DirChanged`, rafraîchir le panneau.

### Ouverture d'un fichier (`⏎`)

- Ouvrir dans la dernière fenêtre d'édition utilisée (suivie via `WinEnter`, en ignorant le panneau et les fenêtres flottantes). Si elle n'existe plus, prendre une autre fenêtre normale de l'onglet. S'il n'y en a aucune, créer un `vsplit` à droite du panneau.
- Jamais dans la fenêtre du panneau.
- Le curseur va dans la fenêtre d'édition après l'ouverture.
- `⏎` sur un en-tête Récents : même effet que `R`. Sur une ligne vide ou l'aide : rien.

### Panneau

- Ouverture : `topleft vsplit`, largeur `width`, `winfixwidth`. Une seule instance par onglet (v1 : onglet courant seulement).
- Buffer du panneau : `buftype=nofile`, `bufhidden=hide`, `swapfile=false`, `buflisted=false`, `modifiable=false` (sauf pendant le rendu), `filetype=bufpanel`.
- Fenêtre : pas de numéros, `signcolumn=no`, `foldcolumn=0`, `wrap=false`, `cursorline=true`, `spell=false`, `statuscolumn=""`.
- Ouverture au démarrage : si `vim.v.vim_did_enter == 1` au moment du `setup`, ouvrir immédiatement, sinon sur `VimEnter`. Ne pas ouvrir si `vim.o.diff`, si le filetype du buffer initial est dans `startup_exclude_filetypes`, ou si Neovim est lancé en mode headless. Le panneau s'ouvre **sans prendre le focus**.
- Rafraîchissement sur `BufAdd`, `BufDelete`, `BufWipeout`, `BufEnter`, `BufModifiedSet`, `BufFilePost`, `DirChanged`. Regrouper les rafraîchissements avec `vim.schedule` pour éviter plusieurs rendus par événement. Ne rien faire si le panneau est fermé.
- Si le panneau devient la dernière fenêtre de l'onglet après la fermeture d'une fenêtre d'édition, fermer le panneau aussi (et donc quitter Neovim si c'était le dernier onglet). Gérer via `QuitPre` ou `WinClosed`, en évitant les boucles.
- Si un autre buffer est chargé dans la fenêtre du panneau (ex. `:e fichier` lancé depuis le panneau), le déplacer dans la fenêtre d'édition et remettre le buffer du panneau.
- Après un rendu, conserver la position du curseur sur la même entrée si elle existe encore.

### Rendu

- Construire les lignes et une table `line -> item` (`{ kind = "buffer"|"recent"|"header"|"help", bufnr?, path? }`). Les actions lisent cette table, jamais le texte.
- Surbrillance avec `nvim_buf_set_extmark` dans un namespace dédié.
- Groupes de surbrillance définis avec `default = true` pour que l'utilisateur puisse les remplacer :
  - `BufPanelHeader` -> `Title`
  - `BufPanelCurrent` -> `Directory`
  - `BufPanelCurrentMarker` -> `Special`
  - `BufPanelModified` -> `DiagnosticWarn`
  - `BufPanelDir` -> `Comment`
  - `BufPanelHelp` -> `Comment`
- Redéfinir les groupes sur `ColorScheme`.

## Structure attendue

```
bufpanel.nvim/
├── lua/bufpanel/
│   ├── init.lua        -- setup, commandes, autocommandes
│   ├── config.lua      -- valeurs par défaut et fusion
│   ├── state.lua       -- état partagé (fenêtre, buffer, dernière fenêtre d'édition, section repliée)
│   ├── buffers.lua     -- liste stable des buffers, fermeture sécuritaire
│   ├── history.lua     -- historique par cwd, persistance JSON
│   ├── panel.lua       -- ouverture, fermeture, options de fenêtre
│   ├── render.lua      -- construction des lignes, extmarks, table line -> item
│   ├── actions.lua     -- open, close_buffer, toggle_recent
│   └── highlights.lua
├── doc/bufpanel.txt    -- aide Vim minimale (:h bufpanel)
├── README.md
└── LICENSE             -- MIT
```

Pas de dépendance obligatoire. Neovim 0.10 minimum (`vim.uv`, `vim.json`). Vérifier la version dans `setup` et avertir proprement si elle est trop ancienne.

## README (en français)

Le README doit contenir :

1. Description courte et la capture texte de l'affichage ci-dessus.
2. Prérequis (Neovim 0.10+, Nerd Font si icônes, `nvim-web-devicons` optionnel).
3. **Installation avec lazy.nvim**, avec `lazy = false` parce que le panneau s'ouvre au démarrage :

   ```lua
   {
     "<utilisateur>/bufpanel.nvim",
     lazy = false,
     dependencies = { "nvim-tree/nvim-web-devicons" }, -- optionnel
     opts = {
       width = 32,
     },
     keys = {
       { "<leader>e", "<cmd>BufPanelToggle<cr>", desc = "BufPanel : afficher/masquer" },
       { "<leader>E", "<cmd>BufPanelFocus<cr>", desc = "BufPanel : focus" },
     },
   }
   ```

   Ajouter une variante pour désactiver l'ouverture au démarrage (`open_on_startup = false`).
4. Installation locale pendant le développement (`dir = "~/chemin/vers/bufpanel.nvim"` dans la spec Lazy).
5. Configuration complète avec les valeurs par défaut commentées.
6. Commandes et keymaps du panneau.
7. Comportements : ordre stable, refus de fermer un buffer modifié, historique par `cwd`, emplacement du fichier JSON et comment le réinitialiser.
8. Groupes de surbrillance et exemple de personnalisation.

## Livraison

- Écris tous les fichiers.
- Valide la syntaxe avec `luac -p` (ou `nvim --headless -c "luafile ..."`) sur chaque fichier Lua.
- Lance un test headless minimal : `nvim --headless -u NONE --cmd "set rtp+=." -c "lua require('bufpanel').setup({ open_on_startup = false })" -c "BufPanelOpen" -c "qa!"` et corrige les erreurs.
- Termine avec une liste de vérifications manuelles à faire dans un vrai Neovim (fermeture d'un buffer modifié, dernier buffer fermé, `:q` depuis la dernière fenêtre d'édition, changement de `cwd`, deux instances en parallèle).
