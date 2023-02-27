" I have a key to open my vimrc, so i put notes at the top for me to remember
" rare commands
" https://devhints.io/tabular
"
" tpope/vim-abolish:
"     snake_case (crs),
"     camelCase (crc),
"     UPPER_CASE (cru),
"
"     MixedCase (crm),
"     dash-case (cr-),
"     dot.case (cr.),
"     space case (cr<space>),
"     Title Case (crt).
"
set nocompatible              " be iMproved, required

let nvimlsp = 1

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
Plug 'tpope/vim-abolish'
" useful for a work specific setup (metadata files + source files)
Plug 'derekwyatt/vim-fswitch'
" <leader>c<Space> is the only thing I know about this but it sure does work
Plug 'scrooloose/nerdcommenter'
" not sure what these two do /exactly/ just know they work
Plug 'rust-lang/rust.vim'
Plug 'mattn/webapi-vim'

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
"Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }

" Images in terminal?
" Plug 'edluffy/hologram.nvim'

Plug 'AndrewRadev/linediff.vim'
Plug 'puremourning/vimspector'

" :Tab
Plug 'godlygeek/tabular'

Plug 'ctrlpvim/ctrlp.vim'

" cast on crit
if !nvimlsp
    " Plug 'neoclide/coc.nvim', {'branch': 'release'}
    Plug 'neoclide/coc.nvim', {'branch': 'master', 'do': 'yarn install --frozen-lockfile'}
endif

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

if nvimlsp
    " Semantic language support
    Plug 'neovim/nvim-lspconfig'
    Plug 'nvim-lua/lsp_extensions.nvim'
    Plug 'hrsh7th/cmp-nvim-lsp', {'branch': 'main'}
    Plug 'hrsh7th/cmp-buffer', {'branch': 'main'}
    Plug 'hrsh7th/cmp-path', {'branch': 'main'}
    Plug 'hrsh7th/nvim-cmp', {'branch': 'main'}
    Plug 'ray-x/lsp_signature.nvim'
    " Only because nvim-cmp _requires_ snippets
    Plug 'hrsh7th/cmp-vsnip', {'branch': 'main'}
    Plug 'hrsh7th/vim-vsnip'
    " Syntactic language support
    Plug 'cespare/vim-toml', {'branch': 'main'}
    Plug 'stephpy/vim-yaml'
    Plug 'rust-lang/rust.vim'
    Plug 'rhysd/vim-clang-format'
    Plug 'mfussenegger/nvim-jdtls' "java
    "Plug 'fatih/vim-go'
    Plug 'plasticboy/vim-markdown'
    Plug 'nvim-lua/lsp-status.nvim'
endif

call plug#end()

if executable('rg')
    set grepprg=rg\ --no-heading\ --vimgrep
    set grepformat=%f:%l:%c:%m
endif

if nvimlsp

lua << END
    local cmp = require'cmp'

    local lsp_status = require('lsp-status')
    lsp_status.register_progress()
    lsp_status.config({
        indicator_errors = 'E',
        indicator_warnings = 'W',
        indicator_info = 'i',
        indicator_hint = 'H',
        indicator_ok = 'Ok',
    })

    local lspconfig = require'lspconfig'
    cmp.setup({
      snippet = {
        -- REQUIRED by nvim-cmp. get rid of it once we can
        expand = function(args)
          vim.fn["vsnip#anonymous"](args.body)
        end,
      },
      window = {
        completion = cmp.config.window.bordered(),
      },
      mapping = {
        ['<S-Tab>'] = cmp.mapping.select_prev_item(),
        ['<Tab>'] = cmp.mapping.select_next_item(),
        ['<CR>'] = cmp.mapping.confirm({ select = true }),
      },
      sources = cmp.config.sources({
        -- TODO: currently snippets from lsp end up getting prioritized -- stop that!
        { name = 'nvim_lsp' },
      }, {
        { name = 'path' },
      }),
      experimental = {
        ghost_text = true,
      },
    })

    -- Enable completing paths in :
    cmp.setup.cmdline(':', {
      sources = cmp.config.sources({
        { name = 'path' }
      })
    })

    -- Setup lspconfig.
    local on_attach = function(client, bufnr)
      local function buf_set_keymap(...) vim.api.nvim_buf_set_keymap(bufnr, ...) end
      local function buf_set_option(...) vim.api.nvim_buf_set_option(bufnr, ...) end

      --Enable completion triggered by <c-x><c-o>
      buf_set_option('omnifunc', 'v:lua.vim.lsp.omnifunc')

      -- Mappings.
      local opts = { noremap=true, silent=true }

      -- See `:help vim.lsp.*` for documentation on any of the below functions
      buf_set_keymap('n', 'gD', '<Cmd>lua vim.lsp.buf.declaration()<CR>', opts)
      buf_set_keymap('n', 'gd', '<Cmd>lua vim.lsp.buf.definition()<CR>', opts)
      buf_set_keymap('n', 'gi', '<cmd>lua vim.lsp.buf.implementation()<CR>', opts)
      buf_set_keymap('n', 'gr', '<cmd>lua vim.lsp.buf.references()<CR>', opts)

      buf_set_keymap('n', '[g', '<cmd>lua vim.diagnostic.goto_prev()<CR>', opts)
      buf_set_keymap('n', ']g', '<cmd>lua vim.diagnostic.goto_next()<CR>', opts)

      buf_set_keymap('n', 'K', '<Cmd>lua vim.lsp.buf.hover()<CR>', opts)

      buf_set_keymap('n', ',rn', '<cmd>lua vim.lsp.buf.rename()<CR>', opts)
      buf_set_keymap('n', ',y', '<cmd>lua vim.lsp.buf.code_action()<CR>', opts)
      buf_set_keymap('n', ',z', '<cmd>lua vim.diagnostic.open_float()<CR>', opts)

      buf_set_keymap('n', ",q", "<cmd>lua vim.lsp.buf.formatting()<CR>", opts)
      buf_set_keymap('n', ',rz', '<cmd>lua vim.diagnostic.set_loclist()<CR>', opts)

      -- buf_set_keymap('n', '<C-k>', '<cmd>lua vim.lsp.buf.signature_help()<CR>', opts)
      -- buf_set_keymap('n', ',D', '<cmd>lua vim.lsp.buf.type_definition()<CR>', opts)

      -- Get signatures (and _only_ signatures) when in argument lists.
      require "lsp_signature".on_attach({
        doc_lines = 0,
        handler_opts = {
          border = "none"
        },
      })

      lsp_status.on_attach(client)
    end

    local capabilities_cmp = require('cmp_nvim_lsp').default_capabilities()
    local capabilities = vim.tbl_extend('keep', capabilities_cmp, lsp_status.capabilities)

    lspconfig.rust_analyzer.setup {
        on_attach = on_attach,
        flags = {
            debounce_text_changes = 150,
        },
        settings = {
            ["rust-analyzer"] = {
                cargo = {
                    allFeatures = true,
                },
                completion = {
                    postfix = {
                        enable = false,
                    },
                },
            },
        },
        root_dir = lspconfig.util.root_pattern('src'),
        capabilities = capabilities,
    }

    lspconfig.tsserver.setup {
        on_attach = on_attach,
        flags = {
            debounce_text_changes = 150,
        },
        capabilities = capabilities,
    }
    lspconfig.pyright.setup{
        on_attach = on_attach,
        flags = {
            debounce_text_changes = 150,
        },
        root_dir = lspconfig.util.find_git_ancestor,
        capabilities = capabilities,
    }
    lspconfig.jdtls.setup{
        on_attach = on_attach,
        flags = {
            debounce_text_changes = 150,
        },
        capabilities = capabilities,
    }

    vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(
      vim.lsp.diagnostic.on_publish_diagnostics, {
        virtual_text = true,
        signs = true,
        update_in_insert = true,
      }
    )
END

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

if !nvimlsp

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
    vmap <leader>Y <Plug>(coc-range-select)

endif

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

" leader p to paste w/o yank
vnoremap <leader>p "_dP

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
au Filetype rust noremap <leader>t :RustTest<cr>
inoremap <c-BS> vbc
nnoremap <leader>/ :NERDTreeToggle<CR>
"nnoremap <leader>a maggVGy`azz
nnoremap <leader>w :w!<cr>
nnoremap <leader>e :bd<cr>
nnoremap <leader>E :bd!<cr>
nnoremap <leader>3 :q!<cr>
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
noremap <Leader>m <esc>:b#<CR>

vnoremap <Leader>s :sort<CR>

" search with Rg for selected text
vnoremap <leader>x "ay:Rg a<cr>
vnoremap <leader>X "ay:Tags a<cr>

vnoremap < <gv
vnoremap > >gv
nnoremap > >>
nnoremap < <<

" vimspector
nnoremap <Leader>qq :call vimspector#Launch()<CR>
nnoremap <Leader>qe :call vimspector#Reset()<CR>
nnoremap <Leader>qc :call vimspector#Continue()<CR>

nnoremap <Leader>qt :call vimspector#ToggleBreakpoint()<CR>
nnoremap <Leader>qT :call vimspector#ClearBreakpoints()<CR>

nmap <Leader>qr <Plug>VimspectorRestart
nmap <Leader>qh <Plug>VimspectorStepOut
nmap <Leader>ql <Plug>VimspectorStepInto
nmap <Leader>qj <Plug>VimspectorStepOver

let g:vim_json_syntax_conceal = 0

let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0

let g:rustfmt_autosave = 1
if has('mac')
    let g:rust_clip_command = "pbcopy"
endif

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

if !nvimlsp
    set statusline+=%1*
    set statusline+=%{coc#status()}%{get(b:,'coc_current_function','')}
    set statusline+=%*
endif

" ==========================================================================
set statusline+=%=      "left/right separator
" ==========================================================================
"
if nvimlsp
    set statusline+=%1*
    set statusline+=%{LspStatus()}
    set statusline+=%*
endif

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

function! LspStatus() abort
  if luaeval('#vim.lsp.buf_get_clients() > 0')
    return luaeval("require('lsp-status').status()")
  endif

  return ''
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
nnoremap <leader><leader>I :!rally preset upload --file "%" -e DEV<cr>
"nnoremap <leader><leader>R :!rally preset upload --file "%" -e DEV<cr>
nnoremap <leader>u :!rally supply make --file "%" --to UAT<cr>
nnoremap <leader>i :!rally supply make --file "%" --to QA<cr>
nnoremap <leader>U :!rally supply make --file "%" --to PROD --no-protect<cr>
nnoremap <leader>I :!rally supply make --file "%" --to DEV<cr>
nnoremap <leader>k :!rally preset info --file "%" --e UAT,PROD<cr>
nnoremap <leader>d :call Rallydiff("")<cr>
nnoremap <leader>D :call Rallydiff("-e PROD")<cr>
nnoremap <leader>c :call Rallydiff("-e QA")<cr>
nnoremap <leader>C :call Rallydiff("-e DEV")<cr>
nnoremap D :diffoff<cr>
nnoremap <leader><leader>Q :%!node ~/node-rally-tools/util/addMIOSupport.js<cr>
nnoremap <leader><leader>N :%!node ~/node-rally-tools/util/addDynamicNext.js<cr>
command! -bang -nargs=* SFiles
  \ call fzf#vim#grep(
  \   'git diff staging...HEAD --name-only', 0,
  \   fzf#vim#with_preview({'dir': systemlist('git rev-parse --show-toplevel')[0]}), <bang>0)


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

" fix fish
set shell=/bin/bash
