if has('nvim')
    finish
endif

if exists('g:loaded_TmuxSetWindowName')
  " That variable is set in the autoloaded code.
    finish
endif

if v:version < 900
    echoerr 'TmuxSetWindowName.vim requires Neovim or Vim 9.0+'
    finish
endif

import autoload 'TmuxSetWindowName.vim'
call TmuxSetWindowName.Setup()
