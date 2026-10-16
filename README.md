# bufpanel.nvim

Un panneau latéral (style neo-tree), ouvert à gauche, qui affiche les **buffers ouverts** dans un ordre stable et les **fichiers récents** du répertoire de travail courant.

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

- Le nom du fichier vient en premier, le dossier parent (relatif au `cwd`) est aligné à droite et grisé.
- `▎` marque le buffer courant, `●` un buffer modifié.
- Quand deux entrées ont le même nom, assez de segments de chemin sont ajoutés pour les distinguer (`cfg/init.lua`, `bp/init.lua`).
- Les noms trop longs sont tronqués avec `…`.

## Prérequis

- Neovim **0.10** ou plus récent.
- Une [Nerd Font](https://www.nerdfonts.com/) si les icônes sont activées.
- [`nvim-web-devicons`](https://github.com/nvim-tree/nvim-web-devicons) (optionnel). Sans lui, le panneau s'affiche sans icônes, sans erreur.

## Installation avec lazy.nvim

Le panneau s'ouvre au démarrage : le plugin doit donc être chargé immédiatement (`lazy = false`).

```lua
{
  "antoinephilibert/bufpanel.nvim",
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

### Sans ouverture au démarrage

Si le panneau ne doit s'ouvrir qu'à la demande, désactivez `open_on_startup`. Le plugin peut alors être chargé paresseusement par ses commandes et raccourcis :

```lua
{
  "antoinephilibert/bufpanel.nvim",
  cmd = { "BufPanelOpen", "BufPanelToggle", "BufPanelFocus" },
  opts = {
    open_on_startup = false,
  },
  keys = {
    { "<leader>e", "<cmd>BufPanelToggle<cr>", desc = "BufPanel : afficher/masquer" },
    { "<leader>E", "<cmd>BufPanelFocus<cr>", desc = "BufPanel : focus" },
  },
}
```

> En chargement paresseux, l'historique n'est alimenté qu'à partir du chargement du plugin. Gardez `lazy = false` pour ne rien manquer.

## Installation locale (développement)

```lua
{
  dir = "~/chemin/vers/bufpanel.nvim",
  name = "bufpanel.nvim",
  lazy = false,
  opts = {},
}
```

## Configuration

Valeurs par défaut :

```lua
require("bufpanel").setup({
  width = 32,                -- largeur du panneau
  open_on_startup = true,    -- ouvrir le panneau au démarrage (sans prendre le focus)
  min_columns = 0,           -- pas d'ouverture automatique si Neovim a moins de colonnes (0 = sans limite)
  startup_exclude_filetypes = { "gitcommit", "gitrebase" }, -- pas d'ouverture au démarrage pour ces filetypes
  icons = true,              -- icônes via nvim-web-devicons, si installé
  show_help = true,          -- ligne d'aide en bas du panneau
  close_on_filetypes = {},   -- filetypes qui ferment le panneau (voir « Fermeture automatique »)
  reopen_after = true,       -- rouvrir le panneau quand ces fenêtres se ferment
  recent = {
    visible = true,          -- section dépliée au démarrage
    max_display = 15,        -- entrées affichées
    max_stored = 50,         -- entrées conservées par cwd
  },
  keymaps = {                -- raccourcis locaux au panneau ; `false` désactive
    open = "<CR>",
    close_buffer = "x",
    toggle_recent = "R",
    close_panel = "q",
  },
})
```

Les options sont fusionnées en profondeur avec les valeurs par défaut (`vim.tbl_deep_extend("force", ...)`) : il suffit de passer ce qui change.

Le panneau ne s'ouvre pas au démarrage en mode `diff` (`nvim -d`), en mode headless, ni si le filetype du buffer initial figure dans `startup_exclude_filetypes`.

Avec `min_columns`, les ouvertures automatiques (démarrage, réouverture après `close_on_filetypes`) sont ignorées tant que Neovim fait moins de `min_columns` colonnes (`vim.o.columns`). Les commandes `:BufPanelOpen`, `:BufPanelToggle` et `:BufPanelFocus` ouvrent toujours le panneau.

## Commandes

| Commande | Effet |
| --- | --- |
| `:BufPanelOpen` | Ouvre le panneau dans l'onglet courant |
| `:BufPanelClose` | Ferme le panneau |
| `:BufPanelToggle` | Ouvre ou ferme le panneau |
| `:BufPanelFocus` | Ouvre le panneau si nécessaire et y place le curseur |

Le plugin ne crée aucun raccourci global : définissez les vôtres (voir l'exemple `keys` plus haut).

## Raccourcis du panneau

| Touche | Effet |
| --- | --- |
| `<CR>` | Ouvre l'entrée dans la dernière fenêtre d'édition. Sur l'en-tête Récents : déplie/replie la section |
| `x` | Ferme le buffer sous le curseur (sans effet dans les Récents) |
| `R` | Déplie/replie la section Récents |
| `q` | Ferme le panneau |

## Comportements

### Ordre stable des buffers

Les buffers apparaissent dans l'ordre où ils ont été ouverts. Naviguer d'un buffer à l'autre ne change jamais cet ordre. Seuls les buffers listés, nommés et de type normal (`buftype` vide) sont affichés.

### Fermeture d'un buffer

`x` ferme le buffer sous le curseur **sans fermer les fenêtres** qui l'affichent : chaque fenêtre bascule d'abord vers le buffer alternatif, sinon vers un autre buffer listé, sinon vers un buffer vide.

Un buffer **modifié** n'est jamais fermé : un avertissement s'affiche et rien d'autre ne se passe. Enregistrez-le ou annulez vos changements d'abord.

Le fichier fermé reste dans l'historique et apparaît aussitôt dans la section Récents.

### Ouverture d'un fichier

`<CR>` ouvre l'entrée dans la dernière fenêtre d'édition utilisée, jamais dans le panneau. Si cette fenêtre n'existe plus, une autre fenêtre normale de l'onglet est utilisée, sinon une nouvelle fenêtre est créée à droite du panneau. Le curseur passe dans la fenêtre d'édition.

Si un fichier est chargé par erreur dans la fenêtre du panneau (par exemple `:e fichier` lancé depuis le panneau), il est renvoyé vers la fenêtre d'édition.

### Fermeture avec la dernière fenêtre

Quand la dernière fenêtre d'édition d'un onglet est fermée (`:q`, `<C-w>c`…), le panneau se ferme aussi, ce qui quitte Neovim s'il s'agissait du dernier onglet. Exception : si la fenêtre a été fermée par `:bdelete`, une nouvelle fenêtre d'édition est recréée à droite du panneau plutôt que de quitter Neovim.

### Fermeture automatique

Le panneau peut se fermer quand la fenêtre d'un plugin s'ouvre (explorateur de fichiers, Git…) et se rouvrir quand elle se ferme. Listez les filetypes concernés :

```lua
opts = {
  close_on_filetypes = { "neo-tree", "NvimTree", "fugitive" },
},
```

- Pour trouver le filetype d'un plugin, ouvrez sa fenêtre et tapez `:set ft?`.
- Seules les fenêtres de l'onglet courant comptent. Les fenêtres flottantes sont aussi prises en compte, même si l'effet est peu visible puisqu'elles couvrent déjà l'écran.
- Les plugins qui s'ouvrent dans un nouvel onglet (ex. Diffview) n'ont pas besoin d'être listés : le panneau n'y est pas ouvert.
- Avec `reopen_after = true` (par défaut), le panneau se rouvre, sans prendre le focus, quand toutes les fenêtres qui l'ont fermé sont fermées et qu'il reste une fenêtre d'édition dans l'onglet.
- Une fermeture manuelle (`:BufPanelClose`, `:BufPanelToggle`, `q`) n'est jamais annulée par une réouverture automatique.
- Une ouverture manuelle (`:BufPanelOpen`, `:BufPanelToggle`, `:BufPanelFocus`) pendant que la fenêtre d'un de ces plugins est ouverte est respectée : le panneau ne se referme qu'à l'apparition d'une nouvelle fenêtre de la liste.
- Au démarrage, si une de ces fenêtres est déjà ouverte (ex. `nvim .` avec neo-tree), le panneau ne s'ouvre pas. Il s'ouvrira quand elle se fermera.

Liste vide par défaut : rien ne change si l'option n'est pas configurée.

### Historique par `cwd`

La section Récents affiche l'historique propre au plugin, **filtré par le répertoire de travail global** (`:pwd`) :

- un fichier est enregistré à chaque fois qu'on entre dans son buffer, s'il existe sur disque et se trouve sous le `cwd` courant ;
- l'entrée la plus récente est en haut ;
- les fichiers déjà ouverts dans la section Buffers et ceux qui n'existent plus sont masqués ;
- changer de `cwd` (`:cd`) rafraîchit le panneau avec l'historique du nouveau répertoire.

L'historique est enregistré dans :

```
~/.local/share/nvim/bufpanel/history.json
```

(plus précisément `vim.fn.stdpath("data") .. "/bufpanel/history.json"`). Il est écrit peu après chaque changement et à la fermeture de Neovim. À chaque écriture, le fichier est relu et seuls les répertoires modifiés par l'instance courante sont fusionnés : plusieurs instances de Neovim peuvent tourner en parallèle sans écraser l'historique des autres projets. Un fichier absent ou corrompu est ignoré.

Pour **réinitialiser** l'historique, quittez Neovim puis supprimez le fichier :

```sh
rm ~/.local/share/nvim/bufpanel/history.json
```

## Surbrillance

| Groupe | Lien par défaut | Usage |
| --- | --- | --- |
| `BufPanelHeader` | `Title` | En-têtes de section |
| `BufPanelCurrent` | `Directory` | Nom du buffer courant |
| `BufPanelCurrentMarker` | `Special` | Marqueur `▎` |
| `BufPanelModified` | `DiagnosticWarn` | Marqueur `●` |
| `BufPanelDir` | `Comment` | Dossier parent |
| `BufPanelHelp` | `Comment` | Ligne d'aide |

Les groupes sont définis avec `default = true` : vos propres définitions ont priorité, y compris après un changement de thème.

```lua
vim.api.nvim_set_hl(0, "BufPanelCurrent", { fg = "#89b4fa", bold = true })
vim.api.nvim_set_hl(0, "BufPanelModified", { fg = "#fab387" })
```

Pour qu'elles survivent à un `:colorscheme`, placez-les dans un autocommand `ColorScheme`.

## Licence

MIT
