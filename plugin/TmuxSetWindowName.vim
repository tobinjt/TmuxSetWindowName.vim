" TmuxSetWindowName: When running under tmux(1), set the window's title to the
"                    name of the file being edited.
" Author:            John Tobin <johntobin@johntobin.ie>
" License:           Licensed under the Apache 2.0 licence, see the LICENSE file
"                    included in the repository.
" Source:            https://github.com/tobinjt/TmuxSetWindowName.vim

" Don't load the plugin unless we're running under tmux.
if ! exists('$TMUX')
  finish
endif
if exists('g:loaded_TmuxSetWindowName')
  finish
endif
let g:loaded_TmuxSetWindowName = '2025-07-06'
let s:last_update_timestamp = 0
" How many seconds to wait between title updates.  This doesn't apply when
" changing between windows.  It does apply when entering or exiting insert mode
" to show whether the buffer has been modified.
let g:TmuxSetWindowName_minimum_timeout_between_title_updates = 5

function! s:TmuxGetWindowList()
  " Return a list of tmux windows in the current session.
  "
  " Returns:
  "   List of strings in the format "{pane_id} #{window_name}".

  let l:cmd = 'tmux list-windows -F "#{pane_id} #{window_name}" 2>&1'
  return systemlist(l:cmd)
endfunction

function! s:TmuxWindowListToDict(window_list)
  " Convert the output of s:TmuxGetWindowList() to a dict mapping window numbers
  " to window titles.
  "
  " We start with lines like:
  "   %0 vim foo.txt
  "   %1
  " Then return:
  "   dict = {
  "     '%0': 'vim foo.txt',
  "     '%1': '',
  "   }
  "
  " Args:
  "   window_list: list of strings returned by TmuxGetWindowList().
  "
  " Returns:
  "   Dict mapping window ID to window title.

  let l:dict = {}
  for l:line in a:window_list
    let l:matches = matchlist(l:line, '^\(%\d\+\) \(.*\)$')
    if empty(l:matches)
      echomsg 'TmuxWindowListToDict: Unparsed line: "' . l:line . '"'
    else
      let l:dict[l:matches[1]] = l:matches[2]
    endif
  endfor
  return l:dict
endfunction

function! s:TmuxGetWindowName()
  " Get the name of the current window.
  "
  " Returns:
  "   string, the name of the current window, or an error message if the name
  "   can't be found.

  let l:window_names = s:TmuxWindowListToDict(s:TmuxGetWindowList())
  for [l:id, l:name] in items(l:window_names)
    if l:id == $TMUX_PANE
      return l:name
    endif
  endfor

  return 'Unable to find window name'
endfunction

function! s:TmuxSetWindowName(name, ignore_timeout)
  " Set the name of the current window if it has changed and either the timeout
  " has passed or ignore_timeout is true.
  "
  " Args:
  "   name: the new name of the window
  "   ignore_timeout: if ignore_timeout is true, update even if the timeout
  "                   hasn't expired.

  let l:current_timestamp = localtime()
  let l:minimum_delay_timestamp = s:last_update_timestamp
    \ + g:TmuxSetWindowName_minimum_timeout_between_title_updates
  if a:ignore_timeout is v:false
        \ && l:minimum_delay_timestamp > l:current_timestamp
    return
  endif
  let s:last_update_timestamp = l:current_timestamp

  let l:current_window_name = s:TmuxGetWindowName()
  if l:current_window_name == a:name
    return
  endif

  call system('tmux rename-window -t '
   \            . shellescape($TMUX_PANE)
   \            . ' '
   \            . shellescape(a:name)
   \            . ' 2>&1')
endfunction

function! s:TmuxFormatFilenameForDisplay(filename)
  " Format the filename for display, adding extra information.
  "
  " Args:
  "   filename: string to add extra information to.
  "
  " Returns:
  "   string, the formatted filename to display.

  let l:additional_info_list =
    \ [&readonly            ? 'RO'   : '',
    \  &filetype ==# 'help' ? 'Help' : '',
    \  &modified            ? '+'    : '',
    \ ]
  let l:additional_info =
    \ join(map(filter(l:additional_info_list,
    \                 'strlen(v:val) > 0'),
    \          '"[" . v:val . "]"'),
    \       '')

  if has('nvim')
    let l:editor = 'nvim'
  else
    let l:editor = 'vim'
  endif
  return join(filter([l:editor,
    \                 l:additional_info,
    \                 a:filename,
    \                ],
    \                'strlen(v:val) > 0'),
    \         ' ')
endfunction

function! s:TmuxSetWindowNameToFilename(ignore_timeout)
  " Set the window name to the name of the current file plus additional info.
  "
  " Args:
  "   ignore_timeout: boolean, if true ignore the timeout between name updates.

  let l:filename = expand('%:t')
  if l:filename ==# ''
    return
  endif

  call s:TmuxSetWindowName(
      \ s:TmuxFormatFilenameForDisplay(l:filename), a:ignore_timeout)
endfunction

" Save the original window name to restore it when leaving.
let s:orig_window_name = s:TmuxGetWindowName()
" Set up autocmds to update the window name on different events.
augroup TmuxSetWindowName
  autocmd!
  " Restore the original window name when exiting.
  autocmd VimLeavePre * call s:TmuxSetWindowName(s:orig_window_name, v:true)
  " Set the tmux window name when moving between buffers, writing a file, or
  " editing a different file.
  autocmd BufReadPost,BufEnter,BufWritePost *
      \ call s:TmuxSetWindowNameToFilename(v:true)
  " Set the tmux window name when entering or leaving insert mode so it's set
  " after suspending.
  autocmd InsertEnter,InsertLeave * call s:TmuxSetWindowNameToFilename(v:false)
augroup END
