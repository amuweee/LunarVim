local M = {}

local check_backspace = function()
  local col = vim.fn.col "." - 1
  return col == 0 or vim.fn.getline("."):sub(col, col):match "%s"
end

local function T(str)
  return vim.api.nvim_replace_termcodes(str, true, true, true)
end

local is_emmet_active = function()
  local clients = vim.lsp.buf_get_clients()

  for _, client in pairs(clients) do
    if client.name == "emmet_ls" then
      return true
    end
  end
  return false
end

M.config = function()
  local status_cmp_ok, cmp = pcall(require, "cmp")
  if not status_cmp_ok then
    return
  end
  local status_luasnip_ok, luasnip = pcall(require, "luasnip")
  if not status_luasnip_ok then
    return
  end
  local win_get_cursor = vim.api.nvim_win_get_cursor
  local get_current_buf = vim.api.nvim_get_current_buf

  local function inside_snippet()
    -- for outdated versions of luasnip
    if not luasnip.session.current_nodes then
      return false
    end

    local node = luasnip.session.current_nodes[get_current_buf()]
    if not node then
      return false
    end

    local snip_begin_pos, snip_end_pos = node.parent.snippet.mark:pos_begin_end()
    local pos = win_get_cursor(0)
    pos[1] = pos[1] - 1 -- LuaSnip is 0-based not 1-based like nvim for rows
    return pos[1] >= snip_begin_pos[1] and pos[1] <= snip_end_pos[1]
  end

  ---sets the current buffer's luasnip to the one nearest the cursor
  ---@return boolean true if a node is found, false otherwise
  local function seek_luasnip_cursor_node()
    -- for outdated versions of luasnip
    if not luasnip.session.current_nodes then
      return false
    end

    local pos = win_get_cursor(0)
    pos[1] = pos[1] - 1
    local node = luasnip.session.current_nodes[get_current_buf()]
    if not node then
      return false
    end

    local snippet = node.parent.snippet
    local exit_node = snippet.insert_nodes[0]

    -- exit early if we're past the exit node
    if exit_node then
      local exit_pos_end = exit_node.mark:pos_end()
      if (pos[1] > exit_pos_end[1]) or (pos[1] == exit_pos_end[1] and pos[2] > exit_pos_end[2]) then
        snippet:remove_from_jumplist()
        luasnip.session.current_nodes[get_current_buf()] = nil

        return false
      end
    end

    node = snippet.inner_first:jump_into(1, true)
    while node ~= nil and node.next ~= nil and node ~= snippet do
      local n_next = node.next
      local next_pos = n_next and n_next.mark:pos_begin()
      local candidate = n_next ~= snippet and next_pos and (pos[1] < next_pos[1])
        or (pos[1] == next_pos[1] and pos[2] < next_pos[2])

      -- Past unmarked exit node, exit early
      if n_next == nil or n_next == snippet.next then
        snippet:remove_from_jumplist()
        luasnip.session.current_nodes[get_current_buf()] = nil

        return false
      end

      if candidate then
        luasnip.session.current_nodes[get_current_buf()] = node
        return true
      end

      local ok
      ok, node = pcall(node.jump_from, node, 1, true) -- no_move until last stop
      if not ok then
        snippet:remove_from_jumplist()
        luasnip.session.current_nodes[get_current_buf()] = nil

        return false
      end
    end

    -- No candidate, but have an exit node
    if exit_node then
      -- to jump to the exit node, seek to snippet
      luasnip.session.current_nodes[get_current_buf()] = snippet
      return true
    end

    -- No exit node, exit from snippet
    snippet:remove_from_jumplist()
    luasnip.session.current_nodes[get_current_buf()] = nil
    return false
  end

  lvim.builtin.cmp = {
    confirm_opts = {
      behavior = cmp.ConfirmBehavior.Replace,
      select = false,
    },
    experimental = {
      ghost_text = true,
      native_menu = false,
    },
    formatting = {
      kind_icons = {
        Class = " ",
        Color = " ",
        Constant = "ﲀ ",
        Constructor = " ",
        Enum = "練",
        EnumMember = " ",
        Event = " ",
        Field = " ",
        File = "",
        Folder = " ",
        Function = " ",
        Interface = "ﰮ ",
        Keyword = " ",
        Method = " ",
        Module = " ",
        Operator = "",
        Property = " ",
        Reference = " ",
        Snippet = " ",
        Struct = " ",
        Text = " ",
        TypeParameter = " ",
        Unit = "塞",
        Value = " ",
        Variable = " ",
      },
      format = function(entry, vim_item)
        vim_item.kind = lvim.builtin.cmp.formatting.kind_icons[vim_item.kind]
        vim_item.menu = ({
          nvim_lsp = "(LSP)",
          emoji = "(Emoji)",
          path = "(Path)",
          calc = "(Calc)",
          cmp_tabnine = "(Tabnine)",
          vsnip = "(Snippet)",
          luasnip = "(Snippet)",
          buffer = "(Buffer)",
        })[entry.source.name]
        vim_item.dup = ({
          buffer = 1,
          path = 1,
          nvim_lsp = 0,
        })[entry.source.name] or 0
        return vim_item
      end,
    },
    snippet = {
      expand = function(args)
        require("luasnip").lsp_expand(args.body)
      end,
    },
    documentation = {
      border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
    },
    sources = {
      { name = "nvim_lsp" },
      { name = "path" },
      { name = "luasnip" },
      { name = "cmp_tabnine" },
      { name = "nvim_lua" },
      { name = "buffer" },
      { name = "calc" },
      { name = "emoji" },
      { name = "treesitter" },
      { name = "crates" },
    },
    mapping = {
      ["<C-d>"] = cmp.mapping.scroll_docs(-4),
      ["<C-f>"] = cmp.mapping.scroll_docs(4),
      -- TODO: potentially fix emmet nonsense
      ["<Tab>"] = cmp.mapping(function()
        if cmp.visible() then
          cmp.select_next_item()
        elseif luasnip.expandable() then
          luasnip.expand()
        elseif inside_snippet() and seek_luasnip_cursor_node() and luasnip.jumpable() then
          luasnip.jump(1)
        elseif check_backspace() then
          vim.fn.feedkeys(T "<Tab>", "n")
        elseif is_emmet_active() then
          return vim.fn["cmp#complete"]()
        else
          vim.fn.feedkeys(T "<Tab>", "n")
        end
      end, {
        "i",
        "s",
      }),
      ["<S-Tab>"] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_prev_item()
        elseif inside_snippet() and luasnip.jumpable(-1) then
          luasnip.jump(-1)
        else
          fallback()
        end
      end, {
        "i",
        "s",
      }),

      ["<C-Space>"] = cmp.mapping.complete(),
      ["<C-e>"] = cmp.mapping.close(),
      ["<CR>"] = cmp.mapping(function(fallback)
        if cmp.visible() and cmp.confirm(lvim.builtin.cmp.confirm_opts) then
          return
        end

        if inside_snippet() and seek_luasnip_cursor_node() and luasnip.jumpable() then
          if not luasnip.jump(1) then
            fallback()
          end
        else
          fallback()
        end
      end),
    },
  }
end

M.setup = function()
  require("luasnip/loaders/from_vscode").lazy_load()
  require("cmp").setup(lvim.builtin.cmp)
end

return M
