vim9script

# TmuxSetWindowName: When running under tmux(1), set the window's title to the
#                    name of the file being edited.
# Author:            John Tobin <johntobin@johntobin.ie>
# License:           Licensed under the Apache 2.0 licence, see the LICENSE file
#                    included in the repository.
# Source:            https://github.com/tobinjt/TmuxSetWindowName.vim

# Don't load the plugin unless we're running under tmux.
if empty($TMUX)
  finish
endif

if exists('g:loaded_TmuxSetWindowName')
  finish
endif
g:loaded_TmuxSetWindowName = '2026-04-15'

var last_update_timestamp = 0
# How many seconds to wait between title updates. This doesn't apply when
# changing between windows. It does apply when entering or exiting insert mode
# to show whether the buffer has been modified.
if !exists('g:TmuxSetWindowName_minimum_timeout_between_title_updates')
  g:TmuxSetWindowName_minimum_timeout_between_title_updates = 5
endif

def TmuxGetWindowName(): string
  # Get the name of the current window.
  #
  # Returns:
  #   string, the name of the current window, or an error message if the name
  #   can't be found.
  var cmd = ['tmux', 'display-message', '-t', $TMUX_PANE, '-p', '#W']
  var result = system(cmd)->trim()
  if v:shell_error != 0
    return 'Unable to find window name'
  endif
  return result
enddef

def TmuxSetWindowName(name: string, ignore_timeout: bool)
  # Set the name of the current window if it has changed and either the timeout
  # has passed or ignore_timeout is true.
  #
  # Args:
  #   name: the new name of the window
  #   ignore_timeout: if ignore_timeout is true, update even if the timeout
  #                   hasn't expired.
  var current_timestamp = localtime()
  var minimum_delay_timestamp = last_update_timestamp
    + g:TmuxSetWindowName_minimum_timeout_between_title_updates
  if !ignore_timeout && minimum_delay_timestamp > current_timestamp
    return
  endif
  last_update_timestamp = current_timestamp

  var current_window_name = TmuxGetWindowName()
  if current_window_name == name
    return
  endif

  var cmd = ['tmux', 'rename-window', '-t', $TMUX_PANE, name]
  system(cmd)
enddef

def TmuxFormatFilenameForDisplay(filename: string): string
  # Format the filename for display, adding extra information.
  #
  # Args:
  #   filename: string to add extra information to.
  #
  # Returns:
  #   string, the formatted filename to display.
  var additional_info_list = [
    &readonly ? 'RO' : '',
    &filetype == 'help' ? 'Help' : '',
    &modified ? '+' : '',
  ]
  var additional_info = additional_info_list
    ->filter((_, v) => !empty(v))
    ->mapnew((_, v) => '[' .. v .. ']')
    ->join('')

  return [orig_window_name, 'vim', additional_info, filename]
    ->filter((_, v) => !empty(v))
    ->join(' ')
enddef

def TmuxSetWindowNameToFilename(ignore_timeout: bool)
  # Set the window name to the name of the current file plus additional info.
  #
  # Args:
  #   ignore_timeout: boolean, if true ignore the timeout between name updates.
  var filename = expand('%:t')
  if empty(filename)
    return
  endif

  TmuxSetWindowName(TmuxFormatFilenameForDisplay(filename), ignore_timeout)
enddef

# Save the original window name to restore it when leaving.
var orig_window_name = TmuxGetWindowName()

# Set up autocmds to update the window name on different events.
augroup TmuxSetWindowName
  autocmd!
  # Restore the original window name when exiting.
  autocmd VimLeavePre * TmuxSetWindowName(orig_window_name, true)
  # Set the tmux window name when moving between buffers, writing a file, or
  # editing a different file.
  autocmd BufReadPost,BufEnter,BufWritePost * TmuxSetWindowNameToFilename(true)
  # Set the tmux window name when entering or leaving insert mode so it's set
  # after suspending.
  autocmd InsertEnter,InsertLeave * TmuxSetWindowNameToFilename(false)
augroup END
