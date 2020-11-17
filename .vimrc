let g:solarized_termcolors=256
let g:solarized_italic=0
let g:solarized_visibility="medium"
syntax on
set background=dark
set mouse=a

if has("macunix")
    let &t_SI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=1\x7\<Esc>\\"
    let &t_SR = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=2\x7\<Esc>\\"
    let &t_EI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=0\x7\<Esc>\\"
endif

"let g:easytags_async=1
let g:neocomplete#enable_at_startup = 1

set nocompatible              " be iMproved, required
filetype off                  " required

call plug#begin()

Plug 'easymotion/vim-easymotion'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-fugitive'
Plug 'derekwyatt/vim-fswitch'
Plug 'scrooloose/nerdcommenter'
Plug 'rust-lang/rust.vim'
Plug 'nvim-treesitter/nvim-treesitter'
Plug 'elzr/vim-json'
Plug 'scrooloose/nerdtree'
Plug 'posva/vim-vue'
Plug 'dag/vim-fish'
Plug 'APZelos/blamer.nvim'
"Plug 'neoclide/coc.nvim', {'branch': 'release'}
"Plug 'autozimu/LanguageClient-neovim', {
    "\ 'branch': 'next',
    "\ 'do': 'bash install.sh',
    "\ }

for key in ['<Up>', '<Down>', '<Left>', '<Right>']
    exec 'nnoremap' key '<Nop>'
    exec 'inoremap' key '<Nop>'
    exec 'vnoremap' key '<Nop>'
endfor

Plug 'neoclide/coc.nvim', {'branch': 'release'}

if has("macunix")
    set rtp+=/usr/local/opt/fzf
end

Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'

Plug 'altercation/vim-colors-solarized'
Plug 'sainnhe/sonokai'
Plug 'sainnhe/gruvbox-material'
Plug 'chriskempson/base16-vim'
Plug 'lifepillar/vim-gruvbox8'

let g:sonokai_style = 'shusia'
let g:sonokai_enable_italic = 0
let g:sonokai_disable_italic_comment = 1

Plug 'majutsushi/tagbar'

if has("lua")
  Plug 'Shougo/neocomplete.vim'
endif

"Plug 'ervandew/supertab'
Plug 'vim-scripts/TagHighlight'
Plug 'pangloss/vim-javascript'

call plug#end()

set hidden
set pyxversion=3

"let g:LanguageClient_serverCommands = {
    "\ 'rust': ['~/.cargo/bin/rust-analyzer'],
    "\ 'json': ['~/.nvm/versions/node/v13.5.0/bin/vscode-json-languageserver', '--stdio'],
    "\ }

"nnoremap K :call LanguageClient_contextMenu()<CR>
"nnoremap M :call LanguageClient_textDocument_hover()<CR>

inoremap <silent><expr> <TAB>
      \ pumvisible() ? "\<C-n>" :
      \ <SID>check_back_space() ? "\<TAB>" :
      \ coc#refresh()
inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"

function! s:check_back_space() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction

" Use <c-space> to trigger completion.
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
xmap <leader>M  <Plug>(coc-format-selected)
nmap <leader>M  <Plug>(coc-format-selected)
function! s:show_documentation()
  if (index(['vim','help'], &filetype) >= 0)
    execute 'h '.expand('<cword>')
  else
    call CocAction('doHover')
  endif
endfunction
autocmd CursorHold * silent call CocActionAsync('highlight')

filetype plugin indent on    " required

nnoremap  ;  :
nnoremap  :  ;
vnoremap  ;  :
vnoremap  :  ;

if has("gui_running")
  set go -=m
end

if has("gui_running") || (has("unix") && system("uname -s") == "Darwin\n")
  call togglebg#map("<F4>")
  colo solarized
else
  colo desert
end
let mapleader = ","
let g:mapleader = ","

set listchars=trail:-,nbsp:-,tab:\ \ ""
set list

set colorcolumn=81

"set hlsearch / \+\ze\t
set wildignore=*.o,~*,*.pyc,*.luac

"" Automatic reloading of .vimrc
autocmd! bufwritepost .vimrc source %
au BufNewFile,BufRead *.jinja set ft=json syntax=json
au BufNewFile,BufRead *.ts set ft=javascript syntax=javascript
au BufNewFile,BufRead .fishrc set ft=fish syntax=fish

au! BufEnter */silo-presets/*  let b:fswitchdst = 'json' | let b:fswitchlocs = 'reg:/silo-presets/silo-metadata'
au! BufEnter */silo-metadata/* let b:fswitchdst = 'yaml,py,txt,xml,json' | let b:fswitchlocs = 'reg:/silo-metadata/silo-presets'


"" Better copy & paste
set pastetoggle=<F2>

" Options
set backspace=indent,eol,start
set relativenumber
set updatetime=300
set cmdheight=1
set signcolumn=number
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

set ttimeout
set ttimeoutlen=1

" Move swapfiles
set nobackup
set noswapfile

" Macros
nnoremap <C-L> :noh<CR>:sign unplace *<CR><C-L>
nnoremap <leader>cd :cd %:p:h<CR>:pwd<CR>

inoremap <End> `

au BufEnter *.c inoremap <buffer> ` ->
au BufEnter *.json set conceallevel=0

let @e='i%F.hcaw v0pI#ifndef A vF.s_Hyyplcawdefine o#endifO' "Header declare

let g:blamer_enabled = 0
let g:blamer_delay = 300
highlight Blamer guifg=lightgrey
let g:blamer_relative_time = 1

inoremap <c-BS> vbc
" Leader
 noremap <leader>. :TagbarToggle<CR>
 noremap <F8>      :TagbarToggle<CR>
 noremap <leader>/ :NERDTreeToggle<CR>
 "noremap <leader>. :TlistToggle<cr>
nnoremap <leader>a maggVGy`azz
nnoremap <silent> <leader>A :!pbcopy < "%"<CR>
nnoremap <leader>w :w!<cr>
nnoremap <leader>e :q<cr>
nnoremap <leader>E :q!<cr>
nnoremap <leader>v :vsplit ~/.vimrc<cr>
nnoremap <leader>f :FSHere<cr>
nnoremap <leader>j :!python3 -m json.tool<cr>
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

set splitright

function! Rallydiff(extra)
    let file = system("rally preset diff --only-new --file '" . bufname("%") . "' --raw " . a:extra)
    execute "silent vs" . file
    execute "silent windo diffthis"
    "echo file
endfunction

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

set number
function! NumberToggle()
  if(&relativenumber == 1)
    set norelativenumber
  else
    set relativenumber
  endif
endfunc

function! SpellToggle()
  if(&spell == 1)
    set nospell
  else
    set spell
  endif
endfunc

nnoremap <leader>l :call NumberToggle()<cr>
vnoremap <leader>l :call NumberToggle()<cr>
nnoremap <leader>s :call SpellToggle()<cr>
vnoremap <leader>s :call SpellToggle()<cr>
"au FocusLost * :set norelativenumber
"au BufNewFile,BufRead *.cu set ft=cu

"inoremap <silent><expr> <TAB>
      "\ pumvisible() ? "\<C-n>" :
      "\ <SID>check_back_space() ? "\<TAB>" :
      "\ coc#refresh()
"inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"

"function! s:check_back_space() abort
  "let col = col('.') - 1
  "return !col || getline('.')[col - 1]  =~# '\s'
"endfunction

"inoremap <silent><expr> <c-space> coc#refresh()

"nmap <silent> [c <Plug>(coc-diagnostic-prev)
"nmap <silent> ]c <Plug>(coc-diagnostic-next)

"" Remap keys for gotos
"nmap <silent> gd <Plug>(coc-definition)
"nmap <silent> gy <Plug>(coc-type-definition)
"nmap <silent> gi <Plug>(coc-implementation)
"nmap <silent> gr <Plug>(coc-references)

"nnoremap <silent> K :call <SID>show_documentation()<CR>

"function! s:show_documentation()
  "if (index(['vim','help'], &filetype) >= 0)
    "execute 'h '.expand('<cword>')
  "else
    "call CocAction('doHover')
  "endif
"endfunction

nmap <leader>rn <Plug>(coc-rename)

" Remap for do codeAction of selected region
xmap <leader>y <Plug>(coc-codeaction-selected)
nmap <leader>y <Plug>(coc-codeaction-selected)w

nmap <leader>ac  <Plug>(coc-codeaction)

noremap <leader>rr :CocCommand rust-analyzer.toggleInlayHints<CR>
noremap <leader>rb :BlamerToggle<CR>

"command! -nargs=? Fold :call     CocAction('fold', <f-args>)
