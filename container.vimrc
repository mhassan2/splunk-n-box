au! BufRead,BufNewFile *.sass         setfiletype sass 
au! BufRead,BufNewFile *.scss       setfiletype css
" Use vim settings, instead of vi
set nocompatible
set loadplugins
" Reindent operations (<< and >>)
""" BIKESHEDDING set shiftwidth=4
" 4 space tab
""" BIKESHEDDING set tabstop=4
" Causes backspace to delete 4 spaces
""" BIKESHEDDING set softtabstop=4
" Replaces a <TAB> with spaces
""" BIKESHEDDING set expandtab
" Uses shiftwidth instead of tabstop at start of lines
set smarttab
set modeline
set ruler
set history=100
set nowrap
" Change terminal title
set title
" No annoying error noises
set noerrorbells
" Make backspace delete lots of things
set backspace=indent,eol,start
" Show us the command we're typing
set showcmd
" Highlight matching parens
set showmatch
" Search options: incremental search, highlight search
set hlsearch
set incsearch
" Selective case insensitivity
set smartcase
" Show full tags when doing search completion
set showfulltag
" Speed up macros
set lazyredraw
" No annoying error noises
set noerrorbells
" Wrap on these
set whichwrap+=<,>,[,]
" Use the cool tab complete menu
set wildmenu
set wildmode=longest,full
set wildignore+=*.o,*~,*.pyc
" Allow edit buffers to be hidden
set hidden
" 1 height windows
set winminheight=1
" misc
set autowrite

if exists('+autochdir')
    set autochdir
endif
set ttyfast
set smartcase

filetype indent on
filetype plugin on
set autoindent
set smartindent
syntax on

colorscheme slate
" make the mouse works under screen :
set ttymouse=xterm2
set mouse=ar

if has("gui_running")
    set guifont=Monospace\ 8
	set guioptions-=T
	set guioptions-=m
	set guioptions-=l
	set guioptions-=L
	set guioptions-=r
	set guioptions-=R
	set mousemodel=extend
	set mousefocus
	set mousehide
	set noguipty
	set guicursor=a:blinkon0

    "Stupid comment character"
    "# Custom options"
    set fuoptions=maxvert,maxhorz
    set lines=24 columns=80
    

	highlight Normal     gui=NONE guibg=Black guifg=White
	highlight NonText    gui=NONE guibg=Black
	highlight Pmenu      gui=NONE guifg=Black guibg=LightGrey
	highlight PmenuSel   gui=NONE guifg=LightGrey guibg=Black
	highlight PmenuSbar  gui=NONE guifg=LightGrey guibg=Black
	highlight PmenuThumb gui=NONE guifg=Black guibg=LightGrey 
endif

" Change buffer
map <C-N> :bn<CR>
map <C-P> :bp<CR>

" Shell like Home / End
inoremap <C-A> <Home>
inoremap <C-E> <End>

" Hide coloration of found words
map <C-C> :nohlsearch<CR>

autocmd FileType Makefile noexpandtab
au filetype tmpl set omnifunc=htmlcomplete#CompleteTags

" Change the current tab with ^j and ^k (normal mode only)
nnoremap <silent> <C-j> :tabnext<CR>
nnoremap <silent> <C-k> :tabprevious<CR>

"----MyH--
color desert
set number
