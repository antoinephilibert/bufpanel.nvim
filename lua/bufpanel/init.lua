-- bufpanel.nvim : panneau latéral des buffers ouverts et des fichiers récents.
local M = {}

local refresh_events = {
  "BufAdd",
  "BufDelete",
  "BufWipeout",
  "BufEnter",
  "BufModifiedSet",
  "BufFilePost",
  "DirChanged",
}

--- Planifie un seul rendu pour toute une rafale d'événements.
local function request_refresh()
  local state = require("bufpanel.state")
  local panel = require("bufpanel.panel")
  if state.refresh_pending or not panel.is_open() then
    return
  end
  state.refresh_pending = true
  vim.schedule(function()
    state.refresh_pending = false
    if panel.is_open() then
      require("bufpanel.render").render()
    end
  end)
end

M.refresh = request_refresh

local function is_headless()
  return vim.tbl_contains(vim.v.argv, "--headless")
end

local function should_open_on_startup()
  local opts = require("bufpanel.config").options
  if not opts.open_on_startup or vim.o.diff or is_headless() then
    return false
  end
  local ft = vim.bo[vim.api.nvim_get_current_buf()].filetype
  return not vim.tbl_contains(opts.startup_exclude_filetypes or {}, ft)
end

local function startup_open()
  if should_open_on_startup() then
    require("bufpanel.panel").open({ focus = false })
  end
end

local function create_commands()
  local panel = require("bufpanel.panel")
  local cmd = vim.api.nvim_create_user_command
  cmd("BufPanelOpen", function()
    panel.open()
  end, { desc = "Ouvrir le panneau BufPanel" })
  cmd("BufPanelClose", function()
    panel.close()
  end, { desc = "Fermer le panneau BufPanel" })
  cmd("BufPanelToggle", function()
    panel.toggle()
  end, { desc = "Afficher/masquer le panneau BufPanel" })
  cmd("BufPanelFocus", function()
    panel.focus()
  end, { desc = "Placer le curseur dans le panneau BufPanel" })
end

local function create_autocmds()
  local state = require("bufpanel.state")
  local panel = require("bufpanel.panel")
  local buffers = require("bufpanel.buffers")
  local history = require("bufpanel.history")

  local group = vim.api.nvim_create_augroup("BufPanel", { clear = true })
  local au = function(event, opts)
    opts.group = group
    vim.api.nvim_create_autocmd(event, opts)
  end

  au("BufAdd", {
    callback = function(args)
      buffers.add(args.buf)
    end,
  })
  au({ "BufDelete", "BufWipeout" }, {
    callback = function(args)
      buffers.remove(args.buf)
    end,
  })
  au("BufEnter", {
    callback = function(args)
      history.record(args.buf)
      local win = vim.api.nvim_get_current_win()
      if panel.is_edit_win(win) then
        state.last_edit_win = win
      end
    end,
  })
  au(refresh_events, { callback = request_refresh })

  au("WinEnter", {
    callback = function()
      local win = vim.api.nvim_get_current_win()
      if panel.is_edit_win(win) then
        state.last_edit_win = win
      end
    end,
  })

  -- Un autre buffer chargé dans la fenêtre du panneau est renvoyé vers la fenêtre d'édition
  au("BufWinEnter", {
    callback = function()
      if state.win and vim.api.nvim_win_is_valid(state.win) and vim.api.nvim_win_get_buf(state.win) ~= state.buf then
        vim.schedule(panel.restore_panel_buf)
      end
    end,
  })

  -- `:q` depuis la dernière fenêtre d'édition : fermer d'abord le panneau,
  -- pour que la commande quitte l'onglet (ou Neovim) normalement.
  au("QuitPre", {
    callback = function()
      if not panel.is_open() then
        return
      end
      local cur = vim.api.nvim_get_current_win()
      if cur == state.win then
        return
      end
      for _, win in ipairs(panel.tab_wins()) do
        if win ~= cur and win ~= state.win then
          return
        end
      end
      state.closing = true
      local win = state.win
      state.win = nil
      pcall(vim.api.nvim_win_close, win, true)
      state.closing = false
    end,
  })

  -- Autres fermetures (`<C-w>c`, `:close`…) : si le panneau reste seul, le fermer aussi.
  au("WinClosed", {
    callback = function(args)
      if state.closing then
        return
      end
      local closed_buf = args.buf
      vim.schedule(function()
        if state.closing or not panel.is_open() then
          return
        end
        local wins = panel.tab_wins()
        if #wins ~= 1 or wins[1] ~= state.win then
          return
        end
        -- Le buffer de la fenêtre fermée n'est plus listé : elle a été fermée par `:bdelete`.
        local deleted = not vim.api.nvim_buf_is_valid(closed_buf)
          or (vim.bo[closed_buf].buftype == "" and not vim.bo[closed_buf].buflisted)
        if deleted then
          -- On ne quitte pas Neovim pour autant : on recrée une fenêtre
          -- d'édition à droite du panneau.
          local target = buffers.list()[1] or vim.api.nvim_create_buf(true, false)
          panel.show_in_edit_win(target)
          return
        end
        state.closing = true
        if #vim.api.nvim_list_tabpages() > 1 then
          local win = state.win
          state.win = nil
          pcall(vim.api.nvim_win_close, win, true)
        else
          local ok, err = pcall(vim.cmd, "quit")
          if not ok then
            vim.notify("bufpanel : " .. tostring(err), vim.log.levels.WARN)
          end
        end
        state.closing = false
      end)
    end,
  })

  au("VimLeavePre", {
    callback = function()
      history.save()
    end,
  })
  au("ColorScheme", {
    callback = function()
      require("bufpanel.highlights").setup()
    end,
  })
end

--- Point d'entrée du plugin.
---@param opts table|nil
function M.setup(opts)
  if vim.fn.has("nvim-0.10") ~= 1 then
    vim.notify("bufpanel.nvim nécessite Neovim 0.10 ou plus récent.", vim.log.levels.ERROR)
    return
  end

  local config = require("bufpanel.config")
  local state = require("bufpanel.state")
  local panel = require("bufpanel.panel")

  config.setup(opts)
  state.recent_visible = config.options.recent.visible
  require("bufpanel.highlights").setup()
  require("bufpanel.buffers").init()
  require("bufpanel.history").load()

  local cur = vim.api.nvim_get_current_win()
  if panel.is_edit_win(cur) then
    state.last_edit_win = cur
  end

  create_commands()
  create_autocmds()

  if panel.is_open() then
    require("bufpanel.render").render()
  elseif vim.v.vim_did_enter == 1 then
    startup_open()
  else
    vim.api.nvim_create_autocmd("VimEnter", {
      group = vim.api.nvim_create_augroup("BufPanelStartup", { clear = true }),
      once = true,
      callback = startup_open,
    })
  end
end

return M
