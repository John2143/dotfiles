set nocompatible              " be iMproved, required

" use this if you use vim
for key in ['<Up>', '<Down>', '<Left>', '<Right>']
    exec 'nnoremap' key '<Nop>'
    exec 'inoremap' key '<Nop>'
    exec 'vnoremap' key '<Nop>'
endfor

" good shit
let mapleader = ","
let g:mapleader = ","

" skip clipboard.vim: its doesn't work on most computers I use so just have
" overrides in my .vimrc
"let g:loaded_clipboard_provider=1

syntax on
set background=dark
set mouse=a

if has("mac")
    let &t_SI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=1\x7\<Esc>\\"
    let &t_SR = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=2\x7\<Esc>\\"
    let &t_EI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=0\x7\<Esc>\\"
endif

filetype off                  " required

call plug#begin()

" full monitor-sized movements made easy
Plug 'easymotion/vim-easymotion'
" niche things I use once a year
Plug 'tpope/vim-surround'
Plug 'tpope/vim-fugitive'
" useful for a work specific setup (metadata files + source files)
Plug 'derekwyatt/vim-fswitch'
" <leader>c<Space> is the only thing I know about this but it sure does work
Plug 'scrooloose/nerdcommenter'
" not sure what these two do /exactly/ just know they work
Plug 'rust-lang/rust.vim'
Plug 'nvim-treesitter/nvim-treesitter'
" silent but deadly
"Plug 'airblade/vim-rooter'
" kinda don't like this but I keep it around
Plug 'elzr/vim-json'
" better than the default, worse than fzf for browsing stuff
Plug 'scrooloose/nerdtree'
" just syntax highlighting for vue/js/c
Plug 'posva/vim-vue'
Plug 'pangloss/vim-javascript'
Plug 'vim-scripts/TagHighlight'
" fish told me to use this
Plug 'dag/vim-fish'
" useful for self-interrogation
Plug 'APZelos/blamer.nvim'
" make my tab do something useful when theres no LSP
" NOTE: don't use with neovim
"let g:neocomplete#enable_at_startup = 1
"Plug 'Shougo/neocomplete.vim'
Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }

" cast on crit
" Plug 'neoclide/coc.nvim', {'branch': 'release'}
Plug 'neoclide/coc.nvim', {'branch': 'master', 'do': 'yarn install --frozen-lockfile'}

" fzf is very cool. Use a LOT of [:Files, :Buf, :Rg]
if has("mac")
    set rtp+=/usr/local/opt/fzf
end
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'

" colorschemes
Plug 'altercation/vim-colors-solarized'
Plug 'sainnhe/sonokai'
Plug 'sainnhe/gruvbox-material'
Plug 'chriskempson/base16-vim'
Plug 'lifepillar/vim-gruvbox8'

call plug#end()

if executable('rg')
    set grepprg=rg\ --no-heading\ --vimgrep
    set grepformat=%f:%l:%c:%m
endif

" save my problems for future me
set hidden

" I think I wrote this in like 2010
set pyxversion=3

" ==========================================================================
" coc block starts here
"
" this is mostly standard bindings with a bit of flavor
" ==========================================================================

" if pop-up-menu then go to next selection else
inoremap <silent><expr> <TAB>
      \ pumvisible() ? "\<C-n>" :
      \ <SID>check_back_space() ? "\<TAB>" :
      \ coc#refresh()
" if shift pressed and pop-up-menu then go to prev selection else un-indent
" NOTE: change this when they invent uppercase tab
inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"

function! s:check_back_space() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction

" Use <c-space> to trigger completion. I prefer tab but 1/1000 times I need this
inoremap <silent><expr> <c-space> coc#refresh()

" Use <cr> to confirm completion, `<C-g>u` means break undo chain at current
" position. Coc only does snippet and additional edit on confirm.
" <cr> could be remapped by other vim plugin, try `:verbose imap <CR>`.
if exists('*complete_info')
  inoremap <expr> <cr> complete_info()["selected"] != "-1" ? "\<C-y>" : "\<C-g>u\<CR>"
else
  inoremap <expr> <cr> pumvisible() ? "\<C-y>" : "\<C-g>u\<CR>"
endif

" Use `[g` and `]g` to navigate diagnostics
nmap <silent> [g <Plug>(coc-diagnostic-prev)
nmap <silent> ]g <Plug>(coc-diagnostic-next)

nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)

nnoremap <silent> K :call <SID>show_documentation()<CR>
vmap <leader>M  <Plug>(coc-format-selected)
nmap <leader>M  <Plug>(coc-format-selected)
function! s:show_documentation()
  if (index(['vim','help'], &filetype) >= 0)
    execute 'h '.expand('<cword>')
  else
    call CocAction('doHover')
  endif
endfunction
autocmd CursorHold * silent call CocActionAsync('highlight')

nmap <leader>rn <Plug>(coc-rename)

" Remap for do codeAction of selected region
xmap <leader>y <Plug>(coc-codeaction-selected)
nmap <leader>y v<Plug>(coc-codeaction-selected)

" ==========================================================================
" coc block end
" ==========================================================================

filetype plugin indent on    " required

" the million dollar stock-vim mistake. I can't even tell you what ; does
" normally
nnoremap  ;  :
nnoremap  :  ;
vnoremap  ;  :
vnoremap  :  ;

if has("gui_running")
    " disable menubar in a mode I never use
    set guioptions -=m
end

"" Automatic reloading of .vimrc
autocmd! bufwritepost .vimrc source %

" unsupported file types
au BufNewFile,BufRead *.jinja set ft=json syntax=json
au BufNewFile,BufRead .fishrc set ft=fish syntax=fish

"" Better copy & paste
set pastetoggle=<F2>

" ==========================================================================
" random vim settings tweaks
" A lot of these are carryovers from vim, not sure if they all matter for nvim
" ==========================================================================
set backspace=indent,eol,start

" make questions like 'whats on line 15' impossible to answer
set relativenumber
" relativly fast updatetime, but I like it
set updatetime=300
set cmdheight=1
" I use a lot of ':vs' and 'C-b %', so this makes it more comfortable
" 'signcolumn=yes' is better for most people
set signcolumn=number
" when I make mistakes, I only do 699 in a row at most.
set history=700
set undolevels=700
" not sure why this isn't default
set wildmenu
set wildignore=*.o,~*,*.pyc,*.luac
" sorry torvalds, 80 columns still makes me happy
set ruler
set colorcolumn=81
" ignorecases in '/' and highlight matches
set ignorecase
set hlsearch
" no error bells and visual bells.
set noeb
set novb
set t_vb=
" leader cleared after 1000 ms. good balance.
set timeoutlen=1000
" esc works basically instantly
set ttimeout
set ttimeoutlen=5
" thicc
set nowrap
" 4 spaces per tab. tabs are probably better, but pragmatic solutions prevail
" 4shrug
set tabstop=4
set shiftwidth=4
set expandtab
set smarttab

set tabstop=4
set shiftwidth=4
set softtabstop=4
" my tab key works fine, thank you
set nosmartindent
" keep at least 5 lines of context above and below while scrolling
set scrolloff=5
" you're a monster if you leave this off. you're also a monster if you have
" trailing newlines always on.
set listchars=trail:-,nbsp:-,tab:\ \ ""
set list
" o/O auto indent
set autoindent
" my statusline has stuff like filetype and line endings, so always display it
set laststatus=2
" buffed backspace
set bs=2

" move swapfiles
set nobackup
set noswapfile

" clear highlights with C-l and add "cd to current file" when vim-rooter doesn't
nnoremap <c-l> :noh<cr>:sign unplace *<cr><c-l>
nnoremap <leader>cd :cd %:p:h<cr>:pwd<cr>

" ` = -> for c. might start using for rust but its much less common than in c
inoremap <end> `
au BufEnter *.c inoremap <buffer> ` ->
au BufEnter *.json set conceallevel=0

" cool for debugging: numbertoggle when losing focus
au FocusLost * :set norelativenumber
au FocusGained * :set relativenumber

" take current filename and add include guards (for c/c++)
let @e='i%F.hcaw v0pI#ifndef A vF.s_Hyyplcawdefine o#endifO' "Header declare

noremap <leader>t :!ctags -R .<cr>:UpdateTypesFileOnly<cr>:redr!<cr>
inoremap <c-BS> vbc
nnoremap <leader>/ :NERDTreeToggle<CR>
"nnoremap <leader>a maggVGy`azz
nnoremap <leader>w :w!<cr>
nnoremap <leader>e :q<cr>
nnoremap <leader>E :q!<cr>
" quick edit vimrc
nnoremap <leader>v :vsplit ~/.vimrc<cr>
nnoremap <leader>f :FSHere<cr>
" maybe swap to jq; but I have python more often than I have jq
nnoremap <leader>j :!python3 -m json.tool<cr>
" delete current file (don't add <cr>)
nnoremap <leader>DD :call delete(expand('%'))
"nnoremap <C-Q> NERDCommenterToggle
noremap <c-J> <c-w>j
noremap <c-K> <c-w>k
noremap <c-L> <c-w>l
noremap <c-H> <c-w>h

nnoremap <leader>g :Buf<cr>
nnoremap <leader>b :GFiles<cr>

noremap <silent> H :nohl<cr>:redraw<cr>

nnoremap <leader>l :call NumberToggle()<cr>
vnoremap <leader>l :call NumberToggle()<cr>
nnoremap <leader>s :call SpellToggle()<cr>
vnoremap <leader>s :call SpellToggle()<cr>

" inline hints
noremap <leader>rr :CocCommand rust-analyzer.toggleInlayHints<CR>
noremap <leader>rb :BlamerToggle<CR>

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

" ==========================================================================
" Status Line
" ==========================================================================
hi User1 guifg=#ffdad8  guibg=#880c0e "Error text
hi User2 guifg=#000000  guibg=#F4905C "Notify text
hi User3 guifg=#268b52                "HI1

set splitright

set statusline=
set statusline+=%3*
set statusline+=%.30f\ %y    "tail of the filename
set statusline+=%*

"display a warning if fileformat isnt unix
set statusline+=[%{&spelllang}                    "Language

set statusline+=%{',\ '.&ff.',\ '.&enc}
set statusline+=%*
set statusline+=]

set statusline+=%h      "help file flag

"read only flag
set statusline+=%2*%m%h%h%*

set statusline+=%{FugitiveStatusline()}

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

set statusline+=%1*
set statusline+=%{coc#status()}%{get(b:,'coc_current_function','')}
set statusline+=%*

" ==========================================================================
set statusline+=%=      "left/right separator
" ==========================================================================

set statusline+=[%b]
set statusline+=\ %c,     "cursor column
set statusline+=%l/%L   "cursor line/total lines
set statusline+=\ %P    "percent through file

" ==========================================================================
" status line end
" ==========================================================================

" warn about mixed tabs/space, extra ending spaces, and more
autocmd cursorhold,bufwritepost * unlet! b:statusline_tab_warning
function! StatuslineTabWarning()
    if !exists("b:statusline_tab_warning")
        let tabs = search('\t ', 'nw')
        let tspace = search('\s\+$', 'nw')
        let espace = search('\($\n\s*\)\+\%$', "nw")
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

" toggle relativenumber
set number
function! NumberToggle()
  if(&relativenumber == 1)
    set norelativenumber
  else
    set relativenumber
  endif
endfunc

" toggle spellcheck
function! SpellToggle()
  if(&spell == 1)
    set nospell
  else
    set spell
  endif
endfunc

let g:blamer_enabled = 0
let g:blamer_delay = 300
let g:blamer_relative_time = 1
highlight Blamer guifg=lightgrey

" Use system clipboards properly when yanking to '*'
function! s:paste(event)
    ":echom a:event
    if(a:event.operator ==# 'y' && a:event.regname ==# '*')
        if has("mac")
            call system('pbcopy', a:event.regcontents)
        else
            call system('/mnt/c/Windows/System32/clip.exe', a:event.regcontents)
        endif
    endif
endfunction

if has("windows") || has("mac")
    augroup YANK
        autocmd!
        autocmd TextYankPost * call s:paste(v:event)
    augroup END
endif

" ==========================================================================
" colorscheme stuff
" putting this at the top makes it break or something
" ==========================================================================

colo sonokai
" colo solarized

let g:solarized_termcolors=256
let g:solarized_italic=0
let g:solarized_visibility="medium"

let g:sonokai_style = 'shusia'
let g:sonokai_enable_italic = 0
let g:sonokai_disable_italic_comment = 1

call togglebg#map("<F4>")

" work related internal bindings for common functions
au! BufEnter */silo-presets/*  let b:fswitchdst = 'json' | let b:fswitchlocs = 'reg:/silo-presets/silo-metadata'
au! BufEnter */silo-metadata/* let b:fswitchdst = 'yaml,py,txt,xml,json' | let b:fswitchlocs = 'reg:/silo-metadata/silo-presets'

nnoremap <leader><leader>u :!rally preset upload --file "%" -e UAT<cr>
nnoremap <leader><leader>U :!rally preset upload --file "%" -e PROD --no-protect<cr>
nnoremap <leader><leader>i :!rally preset upload --file "%" -e QA<cr>
nnoremap <leader>u :!rally supply make --file "%" --to UAT<cr>
nnoremap <leader>i :!rally supply make --file "%" --to QA<cr>
nnoremap <leader>U :!rally supply make --file "%" --to PROD --no-protect<cr>
nnoremap <leader>k :!rally preset info --file "%" --e UAT,PROD<cr>
nnoremap <leader>d :call Rallydiff("")<cr>
nnoremap <leader>D :call Rallydiff("-e PROD")<cr>
nnoremap <leader>c :call Rallydiff("-e QA")<cr>
nnoremap <leader>C :call Rallydiff("-e DEV")<cr>
nnoremap D :diffoff<cr>
nnoremap <leader><leader>Q :%!node ~/node-rally-tools/util/addMIOSupport.js<cr>
nnoremap <leader><leader>N :%!node ~/node-rally-tools/util/addDynamicNext.js<cr>

function! Rallydiff(extra)
    let file = system("rally preset diff --only-new --file '" . bufname("%") . "' --raw " . a:extra)
    execute "silent vs" . file
    execute "silent windo diffthis"
    "echo file
endfunction


function! TSInstallAllF()
  for s:ts_lang in ["rust", "json", "typescript", "javascript", "python", "c", "vue", "html", "latex", "lua"]
    execute "TSInstallFromGrammar " . s:ts_lang
  endfor
endfunction

command TSInstallAll :call TSInstallAllF()

" treesitter lua setup
lua <<EOF
require'nvim-treesitter.configs'.setup {
  -- ensure_installed = { "rust", "json", "typescript", "javascript", "python", "c", "vue", "html", "latex", "lua", },
  highlight = {
    enable = true,              -- false will disable the whole extension
    disable = { },  -- list of language that will be disabled
  },
}
EOF
