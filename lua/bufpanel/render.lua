-- Construction des lignes, surbrillance par extmarks et table ligne -> item.
local config = require("bufpanel.config")
local state = require("bufpanel.state")
local buffers = require("bufpanel.buffers")
local history = require("bufpanel.history")

local M = {}

M.ns = vim.api.nvim_create_namespace("bufpanel")

local MARKER = "▎"
local MODIFIED = "●"
local ELLIPSIS = "…"
local OPEN = "▾"
local CLOSED = "▸"

local width_of = vim.fn.strdisplaywidth

--- Tronque `s` à `max` colonnes en ajoutant « … » à la fin.
local function truncate_right(s, max)
  if width_of(s) <= max then
    return s
  end
  if max <= 0 then
    return ""
  end
  local out, n = "", vim.fn.strchars(s)
  for i = 0, n - 1 do
    local c = vim.fn.strcharpart(s, i, 1)
    if width_of(out .. c) + 1 > max then
      break
    end
    out = out .. c
  end
  return out .. ELLIPSIS
end

--- Tronque `s` à `max` colonnes en ajoutant « … » au début.
local function truncate_left(s, max)
  if width_of(s) <= max then
    return s
  end
  if max <= 0 then
    return ""
  end
  local out, n = "", vim.fn.strchars(s)
  for i = n - 1, 0, -1 do
    local c = vim.fn.strcharpart(s, i, 1)
    if width_of(c .. out) + 1 > max then
      break
    end
    out = c .. out
  end
  return ELLIPSIS .. out
end

--- Découpe un chemin en segments affichables (relatifs au cwd si possible).
---@param path string chemin absolu normalisé
---@param cwd string
---@return string[]
local function segments(path, cwd)
  local rel
  if cwd == "/" and path:sub(1, 1) == "/" then
    rel = path:sub(2)
  elseif path:sub(1, #cwd + 1) == cwd .. "/" then
    rel = path:sub(#cwd + 2)
  else
    rel = vim.fn.fnamemodify(path, ":~")
  end
  return vim.split(rel, "/", { plain = true })
end

local function suffix(segs, n)
  return table.concat(segs, "/", #segs - n + 1, #segs)
end

--- Calcule nom et dossier de chaque entrée. Les noms identiques reçoivent
--- assez de segments de chemin pour être distingués.
---@param entries table[] entrées avec `path`
local function compute_labels(entries)
  local cwd = history.cwd()
  for _, e in ipairs(entries) do
    e.segs = segments(e.path, cwd)
    e.depth = 1
  end
  local changed = true
  while changed do
    changed = false
    local groups = {}
    for _, e in ipairs(entries) do
      local key = suffix(e.segs, e.depth)
      groups[key] = groups[key] or {}
      table.insert(groups[key], e)
    end
    for _, group in pairs(groups) do
      if #group > 1 then
        for _, e in ipairs(group) do
          if e.depth < #e.segs then
            e.depth = e.depth + 1
            changed = true
          end
        end
      end
    end
  end
  for _, e in ipairs(entries) do
    e.name = suffix(e.segs, e.depth)
    local rest = #e.segs - e.depth
    if rest == 0 then
      e.dir = ""
    elseif rest == 1 and e.segs[1] == "" then
      e.dir = "/"
    else
      e.dir = table.concat(e.segs, "/", 1, rest)
    end
  end
end

local devicons_cache
local function get_icon(name)
  if not config.options.icons then
    return nil
  end
  if devicons_cache == nil then
    local ok, mod = pcall(require, "nvim-web-devicons")
    devicons_cache = ok and mod or false
  end
  if not devicons_cache then
    return nil
  end
  local ok, icon, hl = pcall(devicons_cache.get_icon, name, vim.fn.fnamemodify(name, ":e"), { default = true })
  if ok and icon and icon ~= "" then
    return icon, hl
  end
  return nil
end

--- Constructeur de lignes : chaque morceau ajouté peut porter un groupe.
local function new_line()
  return { text = "", hls = {} }
end

local function push(line, s, hl)
  if s == "" then
    return
  end
  local start = #line.text
  line.text = line.text .. s
  if hl then
    table.insert(line.hls, { start, #line.text, hl })
  end
end

--- Ligne d'une entrée (buffer ou récent).
local function entry_line(e, width, current)
  local line = new_line()
  push(line, " ")
  if current then
    push(line, MARKER, "BufPanelCurrentMarker")
  else
    push(line, " ")
  end
  push(line, " ")
  local icon, icon_hl = get_icon(vim.fn.fnamemodify(e.path, ":t"))
  if icon then
    push(line, icon, icon_hl)
    push(line, " ")
  end

  -- Partie droite : marqueur de modification puis dossier
  local available = width - width_of(line.text) - 1
  local mod = e.modified and MODIFIED or ""
  local dir = e.dir
  local function right_width(d)
    local w = width_of(mod)
    if d ~= "" then
      w = w + (mod ~= "" and 2 or 0) + width_of(d)
    end
    return w > 0 and w + 1 or 0 -- +1 : espace minimal après le nom
  end
  local name_w = width_of(e.name)
  if name_w + right_width(dir) > available then
    -- On sacrifie d'abord le dossier
    local room = available - name_w - 1 - width_of(mod) - (mod ~= "" and 2 or 0)
    dir = room >= 4 and truncate_left(dir, room) or ""
  end
  local name = truncate_right(e.name, available - right_width(dir))

  push(line, name, current and "BufPanelCurrent" or nil)
  local right_w = right_width(dir)
  if right_w > 0 then
    push(line, string.rep(" ", math.max(1, available - width_of(name) - right_w + 1)))
    push(line, mod, "BufPanelModified")
    if dir ~= "" then
      if mod ~= "" then
        push(line, "  ")
      end
      push(line, dir, "BufPanelDir")
    end
  end
  return line
end

--- En-tête de section, avec indicateur optionnel aligné à droite.
local function header_line(title, count, width, indicator)
  local line = new_line()
  local text = string.format(" %s (%d)", title, count)
  if indicator then
    local pad = width - width_of(text) - width_of(indicator) - 1
    text = text .. string.rep(" ", math.max(1, pad)) .. indicator
  end
  push(line, text, "BufPanelHeader")
  return line
end

local function key_label(lhs)
  if lhs == "<CR>" or lhs == "<cr>" or lhs == "<Enter>" then
    return "⏎"
  end
  return lhs
end

local function help_lines(width)
  local km = config.options.keymaps
  local parts = {}
  for _, def in ipairs({
    { km.close_buffer, "fermer" },
    { km.open, "ouvrir" },
    { km.toggle_recent, "récents" },
  }) do
    if def[1] then
      table.insert(parts, key_label(def[1]) .. " " .. def[2])
    end
  end
  local sep = new_line()
  push(sep, " " .. string.rep("─", math.max(0, width - 2)), "BufPanelHelp")
  local help = new_line()
  push(help, " " .. truncate_right(table.concat(parts, "  "), width - 2), "BufPanelHelp")
  return { sep, help }
end

local function item_key(item)
  if not item then
    return nil
  end
  if item.kind == "buffer" then
    return "buffer:" .. item.bufnr
  elseif item.kind == "recent" then
    return "recent:" .. item.path
  elseif item.kind == "header" then
    return "header:" .. item.section
  end
  return item.kind
end

--- Construit le contenu du panneau.
---@param width integer
---@return table[] lines, table items
function M.build(width)
  local panel = require("bufpanel.panel")
  local edit_win = panel.get_edit_win()
  local current_buf = edit_win and vim.api.nvim_win_get_buf(edit_win) or nil

  local buf_entries, open_paths = {}, {}
  for _, bufnr in ipairs(buffers.list()) do
    local path = history.normalize(vim.api.nvim_buf_get_name(bufnr))
    open_paths[path] = true
    table.insert(buf_entries, {
      kind = "buffer",
      bufnr = bufnr,
      path = path,
      modified = vim.bo[bufnr].modified,
    })
  end
  local recent_entries = {}
  for _, path in ipairs(history.list(open_paths)) do
    table.insert(recent_entries, { kind = "recent", path = path })
  end

  -- Les libellés tiennent compte de toutes les entrées affichées
  local displayed = vim.list_extend({}, buf_entries)
  if state.recent_visible then
    vim.list_extend(displayed, recent_entries)
  end
  compute_labels(displayed)

  local lines, items = {}, {}
  local function add(line, item)
    table.insert(lines, line)
    items[#lines] = item
  end

  add(header_line("BUFFERS", #buf_entries, width), { kind = "header", section = "buffers" })
  for _, e in ipairs(buf_entries) do
    add(entry_line(e, width, e.bufnr == current_buf), { kind = "buffer", bufnr = e.bufnr, path = e.path })
  end
  add(new_line(), nil)
  add(
    header_line("RÉCENTS", #recent_entries, width, state.recent_visible and OPEN or CLOSED),
    { kind = "header", section = "recent" }
  )
  if state.recent_visible then
    for _, e in ipairs(recent_entries) do
      add(entry_line(e, width, false), { kind = "recent", path = e.path })
    end
  end
  if config.options.show_help then
    for _, l in ipairs(help_lines(width)) do
      add(l, { kind = "help" })
    end
  end
  return lines, items
end

--- Rend le panneau dans son buffer, en conservant le curseur sur la même entrée.
function M.render()
  local buf, win = state.buf, state.win
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  local win_ok = win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf
  local width = win_ok and vim.api.nvim_win_get_width(win) or config.options.width

  local prev_row = win_ok and vim.api.nvim_win_get_cursor(win)[1] or 1
  local prev_key = item_key(state.line_items[prev_row])

  local lines, items = M.build(width)
  local texts = {}
  for i, l in ipairs(lines) do
    texts[i] = l.text
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, texts)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false

  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  for i, l in ipairs(lines) do
    for _, hl in ipairs(l.hls) do
      vim.api.nvim_buf_set_extmark(buf, M.ns, i - 1, hl[1], { end_col = hl[2], hl_group = hl[3] })
    end
  end
  state.line_items = items

  if win_ok then
    local row = math.min(prev_row, #texts)
    if prev_key then
      for i = 1, #texts do
        if item_key(items[i]) == prev_key then
          row = i
          break
        end
      end
    end
    pcall(vim.api.nvim_win_set_cursor, win, { math.max(row, 1), 0 })
  end
end

return M
