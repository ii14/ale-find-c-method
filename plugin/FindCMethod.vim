let s:ref_request_ids = []

function! s:RefHandler(conn_id, response) abort
  " Validate response
  if !has_key(a:response, 'id') | return | endif
  let l:idx = index(s:ref_request_ids, a:response.id)
  if l:idx == -1 | return | endif
  call remove(s:ref_request_ids, l:idx)

  let l:result = get(a:response, 'result', [])

  " Map [{file,range}] -> {file:[ranges]}
  let l:files = {}
  if type(l:result) is v:t_list
    for l:response_item in l:result
      let l:filename = ale#path#FromURI(l:response_item.uri)
      if !has_key(l:files, l:filename)
        let l:files[l:filename] = [l:response_item.range]
      else
        call add(l:files[l:filename], l:response_item.range)
      endif
    endfor
  endif

  if empty(l:files)
    echomsg 'No references found'
    return
  endif

  " Load every file
  let l:matches = []
  for [l:filename, l:ranges] in items(l:files)
    let l:contents = readfile(l:filename)
    for l:range in l:ranges
      " Get lines with references
      let l:line = l:contents[l:range.end.line][l:range.end.character:]
      " Match assignments (word preceded with '=')
      let l:match = match(l:line, '\(\s*=\s*\)\@<=\w')
      if l:match != -1
        let l:match_line = l:range.end.line
        let l:match_col = l:range.end.character + l:match
        " echomsg l:line[l:match:] " Uncomment to print the actual match
        call add(l:matches, {
          \ 'filename': l:filename,
          \ 'line': l:match_line,
          \ 'col': l:match_col,
          \ 'content': l:contents[l:range.end.line]
          \ })
      endif
    endfor
  endfor

  " Handle results
  if empty(l:matches)
    echomsg 'No references found'
    return
  endif

  let l:select = 0
  if len(l:matches) > 1
    " A quick and dirty solution and it sucks, but it's working.
    let l:idx = 0
    let l:prompt = ''
    for l:match in l:matches
      let l:idx += 1
      let l:prompt .=
        \ l:idx . ') ' .
        \ l:match.filename . ':' . l:match.line . ':' . l:match.col . "\n" .
        \ l:match.content . "\n"
    endfor
    let l:prompt .= 'Pick symbol: '

    let l:res = input(l:prompt)
    if l:res ==# ''
      return
    elseif l:res < 1 || l:res > len(l:matches)
      echomsg 'Out of bounds'
    else
      let l:select = l:res - 1
    endif
  endif

  let l:selected = l:matches[l:select]
  execute 'edit ' . fnameescape(l:selected.filename)
  call cursor(l:selected.line + 1, l:selected.col + 1)
  ALEGoToDefinition
endfunction

function! s:RefOnReady(line, column, options, linter, lsp_details) abort
  let l:id = a:lsp_details.connection_id
  if !ale#lsp#HasCapability(l:id, 'references') | return | endif
  let l:buffer = a:lsp_details.buffer
  let l:Callback = function('s:RefHandler')
  call ale#lsp#RegisterCallback(l:id, l:Callback)
  " Send a message saying the buffer has changed first, or the
  " references position probably won't make sense.
  call ale#lsp#NotifyForChanges(l:id, l:buffer)
  let l:message = ale#lsp#message#References(l:buffer, a:line, a:column)
  let l:request_id = ale#lsp#Send(l:id, l:message)
  call add(s:ref_request_ids, l:request_id)
endfunction

function! s:FindCMethod(...) abort
  let l:buffer = bufnr('')
  let [l:line, l:column] = getpos('.')[1:2]
  let l:column = min([l:column, len(getline(l:line))])
  let l:Callback = function('s:RefOnReady', [l:line, l:column, {}])

  for l:linter in ale#linter#Get(&filetype)
    if !empty(l:linter.lsp)
      call ale#lsp_linter#StartLSP(l:buffer, l:linter, l:Callback)
    endif
  endfor
endfunction

command! FindCMethod call s:FindCMethod()
