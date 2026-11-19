" I have a key to open my vimrc, so i put notes at the top for me to remember
" crates
" rare commands
" https://devhints.io/tabular
" :Tab /|
" :Tab /=
"
" :G to see git status (for rebase/merge)
"
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
" Background follows `theme-switch` (~/.local/state/theme/mode); dark when unset.
let s:theme_mode_file = expand('~/.local/state/theme/mode')
if filereadable(s:theme_mode_file) && get(readfile(s:theme_mode_file, '', 1), 0, '') ==# 'light'
  set background=light
else
  set background=dark
endif
set mouse=a

if has("mac")
    let &t_SI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=1\x7\<Esc>\\"
    let &t_SR = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=2\x7\<Esc>\\"
    let &t_EI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=0\x7\<Esc>\\"
endif

if executable('rg')
    set grepprg=rg\ --no-heading\ --vimgrep
    set grepformat=%f:%l:%c:%m
endif

lua << END
    local cmp = require'cmp'

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
      }, {
        { name = 'crates' },
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
    local opts = { noremap = true, silent = true }

    local on_attach = function(client, bufnr)
      vim.keymap.set('n', 'gD', function() vim.lsp.buf.declaration() end, opts)
      vim.keymap.set('n', 'gd', function() vim.lsp.buf.definition() end, opts)
      vim.keymap.set('n', 'gi', function() vim.lsp.buf.implementation() end, opts)
      vim.keymap.set('n', 'gr', function() vim.lsp.buf.references() end, opts)

      -- vim.diagnostic.goto_prev/goto_next are deprecated in 0.12.
      vim.keymap.set('n', '[g', function() vim.diagnostic.jump({ count = -1, float = true }) end, opts)
      vim.keymap.set('n', ']g', function() vim.diagnostic.jump({ count = 1, float = true }) end, opts)

      vim.keymap.set('n', 'K', function() vim.lsp.buf.hover() end, opts)
      vim.keymap.set('n', 'gt', function() vim.lsp.buf.type_definition() end, opts)
      vim.keymap.set('n', ',rn', function() vim.lsp.buf.rename() end, opts)
      vim.keymap.set('n', ',y', function() vim.lsp.buf.code_action() end, opts)
      vim.keymap.set('n', ',z', function() vim.diagnostic.open_float() end, opts)
      -- vim.lsp.buf.formatting() was removed; format() is the replacement.
      vim.keymap.set('n', ',q', function() vim.lsp.buf.format() end, opts)
      -- vim.diagnostic.set_loclist() was removed; the name is now setloclist().
      vim.keymap.set('n', ',rz', function() vim.diagnostic.setloclist() end, opts)

      -- Get signatures (and _only_ signatures) when in argument lists.
      require "lsp_signature".on_attach({
        doc_lines = 0,
        handler_opts = { border = "none" },
      })
    end

    local capabilities = require('cmp_nvim_lsp').default_capabilities()

    vim.g.rustaceanvim = {
        tools = {
        },
        server = {
            on_attach = on_attach,
            default_settings = {
                cargo = {
                    allFeatures = true,
                },
                completion = {
                    postfix = {
                        enable = false,
                    },
                },
                diagnostics = {
                    disabled = { "unresolved-proc-macro" },
                },
            }
        }
    }

    -- tsserver was renamed to ts_ls.
    vim.lsp.config("ts_ls", {
        on_attach = on_attach,
        capabilities = capabilities,
    })
    vim.lsp.config("pyright", {
        on_attach = on_attach,
        capabilities = capabilities,
    })
    vim.lsp.config("clangd", {
        on_attach = on_attach,
        capabilities = capabilities,
    })
    vim.lsp.config("nixd", {
        on_attach = on_attach,
        capabilities = capabilities,
        -- nixd rejects a null workspace/configuration reply ("expected object").
        -- A plain {} would be encoded as a JSON array, so use empty_dict().
        settings = { nixd = vim.empty_dict() },
    })
    vim.lsp.config("tailwindcss", {
        on_attach = on_attach,
        capabilities = capabilities,
    })
    vim.lsp.config("yamlls", {
        on_attach = on_attach,
        capabilities = capabilities,
        settings = {
            yaml = {
                schemas = {
                    -- https://www.reddit.com/r/neovim/comments/ze9gbe/kubernetes_auto_completion_support_in_neovim/
                    -- kubernetes = "*.yaml",
                    ["http://json.schemastore.org/github-workflow"] = ".github/workflows/*",
                    ["http://json.schemastore.org/github-action"] = ".github/action.{yml,yaml}",
                    ["http://json.schemastore.org/ansible-stable-2.9"] = "roles/tasks/*.{yml,yaml}",
                    ["http://json.schemastore.org/prettierrc"] = ".prettierrc.{yml,yaml}",
                    ["http://json.schemastore.org/kustomization"] = "kustomization.{yml,yaml}",
                    ["http://json.schemastore.org/ansible-playbook"] = "*play*.{yml,yaml}",
                    ["http://json.schemastore.org/chart"] = "Chart.{yml,yaml}",
                    ["https://json.schemastore.org/dependabot-v2"] = ".github/dependabot.{yml,yaml}",
                    ["https://json.schemastore.org/gitlab-ci"] = "*gitlab-ci*.{yml,yaml}",
                    ["https://raw.githubusercontent.com/OAI/OpenAPI-Specification/main/schemas/v3.1/schema.json"] = "*api*.{yml,yaml}",
                    ["https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json"] = "*docker-compose*.{yml,yaml}",
                    ["https://raw.githubusercontent.com/argoproj/argo-workflows/master/api/jsonschema/schema.json"] = "*flow*.{yml,yaml}",
                },
            },
        },
    })
    vim.lsp.config("gopls", {
        on_attach = on_attach,
        capabilities = capabilities,
        settings = {
            gopls = {
                analyses = {
                    unusedparams = true,
                },
                staticcheck = true,
                gofumpt = true,
            },
        },
    })

    -- Start the servers whose binaries nixos/modules/language-servers.nix installs.
    -- Required since Neovim 0.11: vim.lsp.config() only registers a config.
    vim.lsp.enable({ "ts_ls", "pyright", "clangd", "nixd", "tailwindcss", "yamlls" })
    -- lsp/gopls.lua shells out to `go env`; only darwin hosts install the go toolchain.
    vim.lsp.enable("gopls", vim.fn.executable("go") == 1)

    local crates = require('crates')
    vim.keymap.set('n', ',Ct', crates.toggle, opts)
    vim.keymap.set('n', ',Cr', crates.reload, opts)

    vim.keymap.set('n', ',Cv', crates.show_versions_popup, opts)
    vim.keymap.set('n', ',Cf', crates.show_features_popup, opts)
    vim.keymap.set('n', ',Cd', crates.show_dependencies_popup, opts)

    vim.keymap.set('n', ',Cu', crates.update_crate, opts)
    vim.keymap.set('v', ',Cu', crates.update_crates, opts)
    vim.keymap.set('n', ',Ca', crates.update_all_crates, opts)
    vim.keymap.set('n', ',CU', crates.upgrade_crate, opts)
    vim.keymap.set('v', ',CU', crates.upgrade_crates, opts)
    vim.keymap.set('n', ',CA', crates.upgrade_all_crates, opts)

    vim.keymap.set('n', ',CH', crates.open_homepage, opts)
    vim.keymap.set('n', ',CR', crates.open_repository, opts)
    vim.keymap.set('n', ',CD', crates.open_documentation, opts)
    vim.keymap.set('n', ',CC', crates.open_crates_io, opts)

    crates.setup()

    vim.diagnostic.config({
        virtual_text = false,
    })

    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1

    -- set termguicolors to enable highlight groups
    vim.opt.termguicolors = true

    require("catppuccin").setup({
        flavour = "auto", -- latte, frappe, macchiato, mocha; auto follows `background`
        background = { -- :h background
            light = "latte",
            dark = "mocha",
        },
        transparent_background = false, -- disables setting the background color.
        show_end_of_buffer = false, -- shows the '~' characters after the end of buffers
        term_colors = false, -- sets terminal colors (e.g. `g:terminal_color_0`)
        dim_inactive = {
            enabled = false, -- dims the background color of inactive window
            shade = "dark",
            percentage = 0.15, -- percentage of the shade to apply to the inactive window
        },
        no_italic = false, -- Force no italic
        no_bold = false, -- Force no bold
        no_underline = false, -- Force no underline
        styles = { -- Handles the styles of general hi groups (see `:h highlight-args`):
            comments = {}, -- Change the style of comments
            conditionals = {},
            loops = {},
            functions = {},
            keywords = {},
            strings = {},
            variables = {},
            numbers = {},
            booleans = {},
            properties = {},
            types = {},
            operators = {},
        },
        color_overrides = {},
        custom_highlights = {},
        integrations = {
            -- (https://github.com/catppuccin/nvim#integrations)
            cmp = true,
            treesitter = true,
        },
    })

    vim.cmd.colorscheme "catppuccin"

    -- Command to toggle inline diagnostics
    vim.api.nvim_create_user_command(
      'DiagnosticsToggleVirtualText',
      function()
        local current_value = vim.diagnostic.config().virtual_text
        if current_value then
          vim.diagnostic.config({virtual_text = false})
        else
          vim.diagnostic.config({virtual_text = true})
        end
      end,
      {}
    )

    -- Command to toggle diagnostics
    vim.api.nvim_create_user_command(
      'DiagnosticsToggle',
      function()
        vim.diagnostic.enable(not vim.diagnostic.is_enabled())
      end,
      {}
    )

    -- nvim-treesitter main branch has no setup(): highlighting is opted in per
    -- FileType. withAllGrammars ships every parser, and pcall leaves filetypes
    -- without one on the regex syntax.
    vim.api.nvim_create_autocmd('FileType', {
      callback = function() pcall(vim.treesitter.start) end,
    })

    require('nvim-highlight-colors').setup({})
END

filetype plugin indent on

" the million dollar stock-vim mistake. I can't even tell you what ; does
" normally
nnoremap  ;  :
nnoremap  :  ;
vnoremap  ;  :
vnoremap  :  ;

" leader p to paste w/o yank
vnoremap <leader>p "_dP

nnoremap <silent> <leader> :WhichKey ','<CR>
vnoremap <silent> <leader> :WhichKeyVisual ','<CR>

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
" set pastetoggle=<F2>

" ==========================================================================
" random vim settings tweaks
" A lot of these are carryovers from vim, not sure if they all matter for nvim
" ==========================================================================

set hidden
set pyxversion=3
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
"set noshowmode

" move swapfiles
set nobackup
set noswapfile

" recovery: undo trees survive across sessions, and buffers with unsaved changes
" are copied out on quit (`:q!` deletes the swap file and keeps nothing)
if exists('*stdpath')
  let s:statedir = stdpath('state')
else
  let s:statedir = (empty($XDG_STATE_HOME) ? $HOME . '/.local/state' : $XDG_STATE_HOME) . '/vim'
endif

if has('persistent_undo')
  let &undodir = s:statedir . '/undo//'
  silent! call mkdir(expand(&undodir), 'p', 0700)
  set undofile
endif

let g:rescue_dir = s:statedir . '/rescue'
let g:rescue_keep_days = 14

function! RescueUnsavedBuffers()
  call mkdir(g:rescue_dir, 'p', 0700)
  for l:old in glob(g:rescue_dir . '/*', 0, 1)
    if localtime() - getftime(l:old) > g:rescue_keep_days * 86400
      call delete(l:old)
    endif
  endfor
  for l:buf in getbufinfo({'buflisted': 1})
    if get(l:buf, 'changed', 0) && empty(getbufvar(l:buf.bufnr, '&buftype'))
      let l:name = l:buf.name ==# '' ? 'unnamed' : fnamemodify(l:buf.name, ':t')
      let l:out = g:rescue_dir . '/' . strftime('%Y%m%d-%H%M%S') . '-' . l:name
      call writefile(getbufline(l:buf.bufnr, 1, '$'), l:out)
    endif
  endfor
endfunction

augroup RescueUnsavedBuffers
  autocmd!
  autocmd VimLeavePre * call RescueUnsavedBuffers()
augroup END

" clear highlights with C-l and add "cd to current file" when vim-rooter doesn't
nnoremap <c-m> :noh<cr>:sign unplace *<cr><c-l>
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

noremap <leader>t :!ctags -R .<cr>:redr!<cr>
au Filetype rust noremap <leader>t :RustTest<cr>
inoremap <c-BS> vbc
nnoremap <leader>/ :NERDTreeToggle<CR>
"nnoremap <leader>a maggVGy`azz
nnoremap <leader>w :w!<cr>
nnoremap <leader>e :bd<cr>
nnoremap <leader>E :bd!<cr>
nnoremap <leader>3 :q!<cr>
" quick edit vimrc
nnoremap <leader>v :vsplit ~/dotfiles/.vimrc<cr>
nnoremap <leader>f :FSHere<cr>
" maybe swap to jq; but I have python more often than I have jq
nnoremap <leader>j :!python3 -m json.tool<cr>
" delete current file (don't add <cr>)
nnoremap <leader>DD :call delete(expand('%'))
"nnoremap <C-Q> NERDCommenterToggle
"noremap <c-J> <c-w>j
"noremap <c-K> <c-w>k
"noremap <c-L> <c-w>l
"noremap <c-H> <c-w>h

nnoremap <leader>g :Bufstop<cr>
nnoremap <Leader>b :FZF<CR>
"nnoremap <leader>b :Files<cr>

noremap <silent> H :nohl<cr>:redraw<cr>

nnoremap <leader>l :call NumberToggle()<cr>
vnoremap <leader>l :call NumberToggle()<cr>
nnoremap <leader>s :call SpellToggle()<cr>
vnoremap <leader>s :call SpellToggle()<cr>

cmap w!! w !sudo tee > /dev/null %

" inline hints
noremap <leader>rr <cmd>lua vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }), { bufnr = 0 })<cr>
noremap <leader>rb :BlamerToggle<CR>
noremap <leader>rm :RainbowToggle<CR>

noremap <Leader>m <esc>:b#<CR>

vnoremap <Leader>s :sort<CR>

" search with Rg for selected text
vnoremap <leader>x "ay:Rg a<cr>
vnoremap <leader>X "ay:Tags a<cr>

nnoremap gb :Bufstop<cr>

vnoremap < <gv
vnoremap > >gv
nnoremap > >>
nnoremap < <<

" vimspector
nnoremap <Leader>qq :call vimspector#Launch()<CR>
nnoremap <Leader>qe :call vimspector#Reset()<CR>
nnoremap <Leader>qc :call vimspector#Continue()<CR>

nnoremap <Leader>qb :call vimspector#ListBreakpoints()<CR>
nnoremap <Leader>qt :call vimspector#ToggleBreakpoint()<CR>
nnoremap <Leader>qT :call vimspector#ClearBreakpoints()<CR>
nnoremap <leader>qy <Plug>VimspectorToggleConditionalBreakpoint

inoremap <silent><script><expr> <C-J> copilot#Accept("\<CR>")

" pressing ctrl shift j will join without space
vnoremap <C-J> gJ

nmap <Leader>qr <Plug>VimspectorRestart
nmap <Leader>qh <Plug>VimspectorStepOut
nmap <Leader>ql <Plug>VimspectorStepInto
nmap <Leader>qj <Plug>VimspectorStepOver

nmap <Leader>di <Plug>VimspectorBalloonEval
" for visual mode, the visually selected text
xmap <Leader>di <Plug>VimspectorBalloonEval

let g:rustfmt_autosave = 0
if has('mac')
    let g:rust_clip_command = "pbcopy"
endif

let NERDTreeShowHidden=1

" ==========================================================================
" Status Line
" ==========================================================================
hi User1 guifg=#ffdad8  guibg=#880c0e "Error text
hi User2 guifg=#000000  guibg=#F4905C "Notify text
hi User3 guifg=#268b52                "HI1

set splitright

let g:lightline = {
      \ 'colorscheme': 'wombat',
      \ 'active': {
      \   'left': [ [ 'mode', 'paste' ],
      \             [ 'gitbranch', 'readonly', 'filename', 'stw', 'modified' ] ],
      \   'right': [ [ 'lsp' ] ]
      \ },
      \ 'component_function': {
      \   'gitbranch': 'FugitiveStatusline',
      \   'stw': 'StatuslineTabWarning',
      \   'lsp': 'LspStatus'
      \ },
      \ }

function! LightlineReadonly()
  return &readonly && &filetype !=# 'help' ? 'RO' : ''
endfunction

function! LightlineLsp()
  return LspStatus()
endfunction

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
  "if luaeval('#vim.lsp.get_clients() > 0')
    "return luaeval("require('lsp-status').status()")
  "endif

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

" colo sonokai
" colo solarized
" colo tokyonight
" colorscheme catppuccin-mocha " catppuccin catppuccin-latte, catppuccin-frappe, catppuccin-macchiato, catppuccin-mocha
" (handled in lua section now)

let g:solarized_termcolors=256
let g:solarized_italic=0
let g:solarized_visibility="medium"

call togglebg#map("<F4>")

" work related internal bindings for common functions
au! BufEnter */silo-presets/*  let b:fswitchdst = 'json' | let b:fswitchlocs = 'reg:/silo-presets/silo-metadata'
au! BufEnter */silo-metadata/* let b:fswitchdst = 'yaml,py,txt,xml,json' | let b:fswitchlocs = 'reg:/silo-metadata/silo-presets'

nnoremap <leader><leader>u :!rally preset upload --file "%" -e MSDEV<cr>
nnoremap <leader><leader>U :!rally preset upload --file "%" -e MSPROD<cr>
"nnoremap <leader><leader>U :!rally preset upload --file "%" -e PROD --no-protect<cr>
"nnoremap <leader><leader>i :!rally preset upload --file "%" -e QA<cr>
"nnoremap <leader><leader>I :!rally preset upload --file "%" -e DEV<cr>
"nnoremap <leader><leader>R :!rally preset upload --file "%" -e DEV<cr>
nnoremap <leader>ru :!rally supply make --file "%" --to MSDEV<cr>
nnoremap <leader>rU :!rally supply make --file "%" --to MSPROD<cr>
"nnoremap <leader>ri :!rally supply make --file "%" --to QA<cr>
"nnoremap <leader>rU :!rally supply make --file "%" --to PROD --no-protect<cr>
"nnoremap <leader>rI :!rally supply make --file "%" --to DEV<cr>
"nnoremap <leader>rk :!rally preset info --file "%" --e UAT,PROD<cr>
nnoremap <leader>rd :call Rallydiff("-e MSDEV")<cr>
nnoremap <leader>rD :call Rallydiff("-e MSPROD")<cr>
"nnoremap <leader>rD :call Rallydiff("-e PROD")<cr>
"nnoremap <leader>rc :call Rallydiff("-e QA")<cr>
"nnoremap <leader>rC :call Rallydiff("-e DEV")<cr>
nnoremap D :diffoff<cr>
nnoremap <leader><leader>Q :%!node ~/node-rally-tools/util/addMIOSupport.js<cr>
nnoremap <leader><leader>N :%!node ~/node-rally-tools/util/addDynamicNext.js<cr>
command! -bang -nargs=* SFiles
  \ call fzf#vim#grep(
  \   'git diff staging...HEAD --name-only ', 0,
  \   fzf#vim#with_preview(), 0)

function! Rallydiff(extra)
    let file = system("rally preset diff --only-new --file '" . bufname("%") . "' --raw " . a:extra)
    execute "silent vs" . file
    execute "silent windo diffthis"
    "echo file
endfunction


function! VisualSelection()
    if mode()=="v"
        let [line_start, column_start] = getpos("v")[1:2]
        let [line_end, column_end] = getpos(".")[1:2]
    else
        let [line_start, column_start] = getpos("'<")[1:2]
        let [line_end, column_end] = getpos("'>")[1:2]
    end
    if (line2byte(line_start)+column_start) > (line2byte(line_end)+column_end)
        let [line_start, column_start, line_end, column_end] =
        \   [line_end, column_end, line_start, column_start]
    end
    let lines = getline(line_start, line_end)
    if len(lines) == 0
            return ''
    endif
    let lines[-1] = lines[-1][: column_end - 1]
    let lines[0] = lines[0][column_start - 1:]
    return join(lines, "\n")
endfunction

function! NumberToDate()
    " take the current selection in pass it into the unix command `date -r`.
    " this will convert the number into a date.
    let vs = VisualSelection()
    let date = system("date -r " . vs . " +'%Y-%m-%d %H:%M:%S'")
    " print the date to status line
    echom date
endfunction

nnoremap <leader>d :call NumberToDate()<cr>

" fix fish
set shell=bash
