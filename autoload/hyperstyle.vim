if exists("g:hyperstyle_autoloaded") | finish | endif
let g:hyperstyle_autoloaded=1

"
" Check if python is supported, and invoke the python env.
"

if !has("python") && !has("python3")
  echohl WarningMsg
  echomsg "vim-hyperstyle requires vim with python support."
  if has("nvim") | echomsg "for Neovim, see `:help nvim-python`."
  else | echomsg "you may need to rebuild vim with --with-python."
  endif
  echohl None
  finish
endif

let s:current_file=expand("<sfile>")
python << EOF
import sys, os, vim
path = os.path.dirname(vim.eval("s:current_file")) + '/../python'
sys.path.insert(0, path)
import hyperstyle as hyperstyle
EOF

"
" Same-line expansions
"

" Expand spaces (fl_ => float:_)
function! hyperstyle#expand_space()
  if ! s:at_eol() | return "" | endif
  return s:expand_inline({ 'fn': 'expand_property', 'append': ' ' })
endfunction

" Expand colons (fl: => float:)
function! hyperstyle#expand_colon()
  if ! s:at_eol() | return "" | endif
  return s:expand_inline({ 'fn': 'expand_property', 'append': '' })
endfunction

" Expand semicolons (display: b; => display: block;)
function! hyperstyle#expand_semicolon()
  if ! s:at_eol() | return "" | endif
  return s:expand_inline({ 'fn': 'expand_statement', 'append': b:hyperstyle_semi })
endfunction

"
" The <Tab> key combines the `:` expansion and the `;` expansion.
" Also, only work on indented lines. This will avoid expanding selectors.
"

function! hyperstyle#expand_tab()
  if ! s:at_indented_line() | return "" | endif
  if ! s:at_eol() | return "" | endif

  let r = s:expand_inline({ 'fn': "expand_property", 'append': ' ',
    \ 'expr': '^\s*\([a-z0-9]\+\)\s*$' })
  if r != '' | return r | endif

  let r = s:expand_inline({ 'fn': "expand_statement",
    \ 'append': b:hyperstyle_semi })
  if r != '' | return r | endif

  return ''
endfunction

"
" Expands carriage return (db => display: block;)
" This one is different because it takes from the previous line
"

function! hyperstyle#expand_cr()
  " If it broke in the middle of a line, don't.
  if match(getline('.'), '^\s*$') == -1 | return '' | endif

  return s:expand_inline({
    \ 'line': line('.')-1,
    \ 'fn': 'expand_statement',
    \ 'expr': '^\s*\(.\+\)\s*$',
    \ 'clear': '"_dd^"_C',
    \ 'append': b:hyperstyle_semi . "\n"
    \ })
endfunction

"
" (Internal) Gets from the current line, passes it to a python function,
" then modifies the buffer as needed
"

function! s:expand_inline(o)
  let linenum = exists('a:o.line') ? a:o.line : line('.')
  let expr = exists('a:o.expr') ? a:o.expr : '^\s*\(.\+\).$'
  let clear = exists('a:o.clear') ? a:o.clear : '0"_C'
  let ln = s:get_line_info(linenum, expr) 
  let out = s:pyfn(a:o.fn, ln.shorthand)
  if out == '' | return "" | endif

  " Delete current line and replace
  exe 'normal! '.clear
  return (ln.indent) . out . (a:o.append)
endfunction

"
" Executes a python function with a given string as an argument
"

function! s:pyfn(fn, str)
  let escaped = substitute(a:str, '"', '\"', 'g')
  return s:pyeval("hyperstyle.".a:fn."(\"".escaped."\")")
endfunction

"
" pyeval() polyfill
"

try
  call pyeval('1')
  function! s:pyeval(code)
    return pyeval('(' . a:code . ') or ""')
  endfunction
catch /E117/ " Unknown function
  function! s:pyeval(code)
    python result = eval(vim.eval('a:code'))
    python if isinstance(result, str): vim.command('return ' + repr(result))
  endfunction
endtry

"
" (Internal) Splits a line to indent and shorthand
"
"  - indent: indentation text
"  - shorthand: the thing matching regexps
"

function! s:get_line_info(ln, expr)
  let linetext = getline(a:ln)
  let indent = matchstr(linetext, '^\s*')
  let shorthands = matchlist(linetext, a:expr)
  let shorthand = ""
  if exists("shorthands[1]") | let shorthand = shorthands[1] | endif
  return { "indent": indent, "shorthand": shorthand, "text": linetext }
endfunction

" (internal) Checks if we're at the end of the line.
function s:at_eol()
  return col('.') >= strlen(getline('.'))
endfunction

" (internal) Checks if we're at a line that's indented
function s:at_indented_line()
  return getline('.') =~ '^\s'
endfunction
