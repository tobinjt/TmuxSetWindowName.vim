-- TmuxSetWindowName: When running under tmux(1), set the window's title to the
--                    name of the file being edited.
-- Author:            John Tobin <johntobin@johntobin.ie>
-- License:           Licensed under the Apache 2.0 licence, see the LICENSE
--                    file included in the repository.
-- Source:            https://github.com/tobinjt/TmuxSetWindowName.vim

local M = {}

M.config = {
  -- How many seconds to wait between title updates. This doesn't apply when
  -- changing between windows. It does apply when entering or exiting insert
  -- mode to show whether the buffer has been modified.
  minimum_timeout_between_title_updates = 5,
}

M.state = {
  last_update_timestamp = 0,
  -- Save the original window name to restore it when leaving.
  orig_window_name = nil,
}

function M.tmux_get_window_list()
  -- Return a list of tmux windows in the current session.
  --
  -- Returns:
  --   List of strings in the format "{pane_id} #{window_name}".
  local cmd = 'tmux list-windows -F "#{pane_id} #{window_name}" 2>&1'
  return vim.fn.systemlist(cmd)
end

function M.tmux_window_list_to_dict(window_list)
  -- Convert the output of tmux_get_window_list() to a dict mapping window
  -- numbers to window titles.
  --
  -- We start with lines like:
  --   %0 vim foo.txt
  --   %1
  -- Then return:
  --   dict = {
  --     ['%0'] = 'vim foo.txt',
  --     ['%1'] = '',
  --   }
  --
  -- Args:
  --   window_list: list of strings returned by tmux_get_window_list().
  --
  -- Returns:
  --   Dict mapping window ID to window title.
  local dict = {}
  for _, line in ipairs(window_list) do
    local id, name = line:match("^(%%%d+) (.*)$")
    if id then
      dict[id] = name
    else
      -- Handle the case where name might be empty
      id = line:match("^(%%%d+)$")
      if id then
        dict[id] = ""
      else
        vim.notify('TmuxWindowListToDict: Unparsed line: "' .. line .. '"', vim.log.levels.INFO)
      end
    end
  end
  return dict
end

function M.tmux_get_window_name()
  -- Get the name of the current window.
  --
  -- Returns:
  --   string, the name of the current window, or an error message if the name
  --   can't be found.
  local window_names = M.tmux_window_list_to_dict(M.tmux_get_window_list())
  local pane_id = vim.env.TMUX_PANE
  if window_names[pane_id] then
    return window_names[pane_id]
  end
  return 'Unable to find window name'
end

function M.tmux_set_window_name(name, ignore_timeout)
  -- Set the name of the current window if it has changed and either the timeout
  -- has passed or ignore_timeout is true.
  --
  -- Args:
  --   name: the new name of the window. The original window name will be
  --         prepended to this.
  --   ignore_timeout: if ignore_timeout is true, update even if the timeout
  --                   hasn't expired.
  local current_timestamp = os.time()
  local minimum_delay = M.config.minimum_timeout_between_title_updates
  if not ignore_timeout and (M.state.last_update_timestamp + minimum_delay) > current_timestamp then
    return
  end
  M.state.last_update_timestamp = current_timestamp

  name = M.state.orig_window_name .. ' ' .. name
  local current_window_name = M.tmux_get_window_name()
  if current_window_name == name then
    return
  end

  local pane_id = vim.env.TMUX_PANE
  vim.fn.system({ 'tmux', 'rename-window', '-t', pane_id, name })
end

function M.tmux_format_filename_for_display(filename)
  -- Format the filename for display, adding extra information.
  --
  -- Args:
  --   filename: string to add extra information to.
  --
  -- Returns:
  --   string, the formatted filename to display.
  local parts = { 'nvim' }

  local additional_info = ''
  if vim.bo.readonly then
    additional_info = additional_info .. '[RO]'
  end
  if vim.bo.filetype == 'help' then
    additional_info = additional_info .. '[Help]'
  end
  if vim.bo.modified then
    additional_info = additional_info .. '[+]'
  end

  if additional_info ~= '' then
    table.insert(parts, additional_info)
  end
  table.insert(parts, filename)
  return table.concat(parts, ' ')
end

function M.tmux_set_window_name_to_filename(ignore_timeout)
  -- Set the window name to the name of the current file plus additional info.
  --
  -- Args:
  --   ignore_timeout: boolean, if true ignore the timeout between name updates.
  local filename = vim.fn.expand('%:t')
  if filename == '' then
    return
  end

  M.tmux_set_window_name(M.tmux_format_filename_for_display(filename), ignore_timeout)
end

function M.setup(opts)
  -- Don't load the plugin unless we're running under tmux.
  if not vim.env.TMUX then
    return
  end

  vim.g.loaded_TmuxSetWindowName = '2025-07-06'

  local defaults = {
    -- How many seconds to wait between title updates. This doesn't apply when
    -- changing between windows. It does apply when entering or exiting insert
    -- mode to show whether the buffer has been modified.
    minimum_timeout_between_title_updates = 5,
  }
  M.config = vim.tbl_deep_extend("force", defaults, opts or {})

  -- Save the original window name to restore it when leaving.
  if not M.state.orig_window_name then
    M.state.orig_window_name = M.tmux_get_window_name()
  end

  -- Set up autocmds to update the window name on different events.
  local group = vim.api.nvim_create_augroup('TmuxSetWindowName', { clear = true })

  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      -- Restore the original window name when exiting.
      M.tmux_set_window_name(M.state.orig_window_name, true)
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufEnter', 'BufWritePost' }, {
    group = group,
    callback = function()
      -- Set the tmux window name when moving between buffers, writing a file,
      -- or editing a different file.
      M.tmux_set_window_name_to_filename(true)
    end,
  })

  vim.api.nvim_create_autocmd({ 'InsertEnter', 'InsertLeave' }, {
    group = group,
    callback = function()
      -- Set the tmux window name when entering or leaving insert mode so it's
      -- set after suspending.
      M.tmux_set_window_name_to_filename(false)
    end,
  })
end

return M
