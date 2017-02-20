let g:solarized_termcolors=256
let g:solarized_italic=0
let g:solarized_visibility="medium"
syntax enable
set background=dark

"let g:airline_powerline_fonts=1

let g:syntastic_check_on_open=1
let g:syntastic_enable_signs=1

"let g:easytags_async=1
let g:neocomplete#enable_at_startup = 1

set nocompatible              " be iMproved, required
filetype off                  " required

" set the runtime path to include Vundle and initialize
if has("win32")
  set rtp+=C:/Users/John/vimfiles/bundle/Vundle.vim
  call vundle#begin('$USERPROFILE/vimfiles/bundle')
else
  set rtp+=~/.vim/bundle/Vundle.vim
  call vundle#begin()
endif

" let Vundle manage Vundle, required
Plugin 'VundleVim/Vundle.vim'
Plugin 'tpope/vim-surround'
Plugin 'derekwyatt/vim-fswitch'
Plugin 'scrooloose/nerdcommenter'
Plugin 'rust-lang/rust.vim'
if has("gui_running")
  Plugin 'scrooloose/syntastic'
endif

"Plugin 'vim-airline/vim-airline'
"Plugin 'vim-airline/vim-airline-themes'

Plugin 'altercation/vim-colors-solarized'

Plugin 'majutsushi/tagbar'

if has("lua")
  Plugin 'Shougo/neocomplete.vim'
endif

Plugin 'supertab'
Plugin 'TagHighlight'
Plugin 'pangloss/vim-javascript'

" All of your Plugins must be added before the following line
call vundle#end()            " required
filetype plugin indent on    " required

nnoremap  ;  :
nnoremap  :  ;
vnoremap  ;  :
vnoremap  :  ;

" set go -=m
if has("gui_running")
  set go -=T
  set go -=r
  call togglebg#map("<F4>")
else
  "colo solarized
  colo desert
end
let mapleader = ","
let g:mapleader = ","
if has("gui_running") "utf-8
  set listchars=trail:·,nbsp:·,tab:\ \ ""
else
  set listchars=trail:-,nbsp:~,tab:\ \ ""
endif
set list

set colorcolumn=81


"set hlsearch / \+\ze\t
set wildignore=*.o,~*,*.pyc,*.luac

" Automatic reloading of .vimrc
autocmd! bufwritepost .vimrc source %

" Better copy & paste
set pastetoggle=<F2>
set clipboard=unnamed

" Options
set backspace=indent,eol,start
set relativenumber
set history=700
set undolevels=700
set wildmenu
set ruler
set ignorecase
set hlsearch
set noeb
set novb
set t_vb=
set tm=1000
set nowrap
set tabstop=4
set shiftwidth=4
set expandtab
set smarttab
set scrolloff=5
set nosmartindent

set tabstop=4
set shiftwidth=4
set softtabstop=4

set ai
set laststatus=2
set bs=2

set noesckeys
set ttimeout
set ttimeoutlen=1

" Move swapfiles
set nobackup
set noswapfile

" Macros
nnoremap <C-L> :noh<CR><C-L>
nnoremap <leader>cd :cd %:p:h<CR>:pwd<CR>

inoremap <End> `

au BufEnter *.c inoremap <buffer> ` ->

let @e='i%F.hcaw v0pI#ifndef A vF.s_Hyyplcawdefine o#endifO' "Header declare

inoremap <c-BS> vbc
" Leader
 noremap <leader>. :TagbarToggle<CR>
 noremap <F8>      :TagbarToggle<CR>
 noremap <leader>/ :TagbarTogglePause<CR>
 "noremap <leader>. :TlistToggle<cr>
nnoremap <leader>a maggVGy`azz
nnoremap <leader>w :w!<cr>
nnoremap <leader>e :q<cr>
nnoremap <leader>E :q!<cr>
nnoremap <leader>v :vsplit ~/.vimrc<cr>
nnoremap <leader>f :FSHere<cr>
nnoremap <leader>DD :call delete(expand('%'))
"nnoremap <C-Q> NERDCommenterToggle
noremap <c-Down> <c-w>j
noremap <c-Up> <c-w>k
noremap <c-Right> <c-w>l
noremap <c-Left> <c-w>h

noremap <leader>L <c-w>l
noremap <leader>H <c-w>h
noremap <leader>K <c-w>k
noremap <leader>J <c-w>j

noremap <Leader>n <esc>:tabprevious<CR>
noremap <Leader>m <esc>:tabnext<CR>

vnoremap <Leader>s :sort<CR>

vnoremap < <gv
vnoremap > >gv
nnoremap > >>
nnoremap < <<

let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0

" Status Line
hi User1 guifg=#ffdad8  guibg=#880c0e "Error text
hi User2 guifg=#000000  guibg=#F4905C "Notify text
hi User3 guifg=#268b52                "HI1

"set statusline =%t\                                 "Current file path
"set statusline+=%2*%M%H%W%*                         "Flags->-+, HLP, PRV
"set statusline+=\ [%{&spelllang}                    "Language
"set statusline+=%{','.(&fenc!=''?&fenc:&enc).']'}   "Encoding

"set statusline+=%1*%{StatuslineTabWarning()}%*
"set statusline+=%=

"set statusline+=%#warningmsg#
"set statusline+=%{SyntasticStatuslineFlag()}
"set statusline+=%*

"set statusline+=[%03b]\                 "ASCIsdfI val
"set statusline+=%03l,%03c               "line,col

"statusline setup
set statusline =%3*
set statusline+=%.30f\ %y    "tail of the filename
set statusline+=%*

"display a warning if fileformat isnt unix
set statusline+=[%{&spelllang}                    "Language

set statusline+=%{','.&ff.','.&enc}
set statusline+=%*
set statusline+=]

set statusline+=%h      "help file flag

"read only flag
set statusline+=%2*%m%h%h%*

"set statusline+=%{fugitive#statusline()}

"display a warning if &et is wrong, or we have mixed-indenting
set statusline+=%1*
set statusline+=%{StatuslineTabWarning()}
set statusline+=%*

if has("gui_running")
  set statusline+=%#warningmsg#
  set statusline+=%{SyntasticStatuslineFlag()}
  set statusline+=%*
endif

"display a warning if &paste is set
set statusline+=%#error#
set statusline+=%{&paste?'[paste]':''}
set statusline+=%*

set statusline+=%=      "left/right separator

set statusline+=[%b]
set statusline+=\ %c,     "cursor column
set statusline+=%l/%L   "cursor line/total lines
set statusline+=\ %P    "percent through file
set laststatus=2

noremap <leader>t :!ctags -R .<cr>:UpdateTypesFileOnly<cr>:redr!<cr>

autocmd cursorhold,bufwritepost * unlet! b:statusline_tab_warning
function! StatuslineTabWarning()
    if !exists("b:statusline_tab_warning")
        let tabs = search('\t ', 'nw')
        let tspace = search('\s\+$', 'nw')
        let espace = search('\($\n\s*\)\+\%$')
        let st = []
        if tabs > 0
            call add(st, 'MX>'.tabs)
        endif
        if tspace > 0
            call add(st, 'TR>'.tspace)
        endif
        if espace > 0
            call add(st, 'ES')
        endif
        let b:statusline_tab_warning = ''
        if len(st) > 0
            let b:statusline_tab_warning = '['.join(st, " ").']'
        endif
    endif
    return b:statusline_tab_warning
endfunction

set number
function! NumberToggle()
  if(&relativenumber == 1)
    set norelativenumber
  else
    set relativenumber
  endif
endfunc

nnoremap <leader>l :call NumberToggle()<cr>
vnoremap <leader>l :call NumberToggle()<cr>
au FocusLost * :set norelativenumber
au BufNewFile,BufRead *.cu set ft=cu
