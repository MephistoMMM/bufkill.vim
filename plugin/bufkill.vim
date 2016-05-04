" bufkill.vim
" Maintainer:	John Orr (john undersc0re orr yah00 c0m)
" Version:	1.10
" Last Change:	16 June 2011
"
" Changer: Mephis Pheies ( MephistoMMM )
" Changer Email: mephistommm@gmail.com
" Changer Info: 
"	fix bug in updateList, and change buflist to circular list, and delete
"	some command definitions.


" Introduction: {{{1
" Basic Usage:
" When you want to unload/delete/wipe a buffer, use:
"   :bun/:bd/:bw to close the window as well (vim command), or
"   :BUN/:BD/:BW to leave the window intact (this script).
" To move backwards/forwards through recently accessed buffers, use:
"   :BB/:BF
" To move to the alternate buffer whilst preserving cursor column, use:
"   :BA
" or override Ctrl-^ via g:BufKillOverrideCtrlCaret
" Mappings are also defined.

" Description:
" This is a script to
" a) unload, delete or wipe a buffer without closing the window it was displayed in
" b) in its place, display the buffer most recently used in the window, prior
"    to the buffer being killed.  This selection is taken from the full list of
"    buffers ever displayed in the particular window.
" c) allow one level of undo in case you kill a buffer then change your mind
" d) allow navigation through recently accessed buffers, without closing them.
" e) override the standard Ctrl-^ (Ctrl-6) functionality to maintain the
"    correct cursor column position. (Enable via g:BufKillOverrideCtrlCaret)
"
" The inspiration for this script came from
" a) my own frustration with vim's lack of this functionality
" b) the description of the emacs kill-buffer command in tip #622
"    (this script basically duplicates this command I believe,
"    not sure about the undo functionality)
" c) comments by Keith Roberts when the issue was raised in the
"    vim@vim.org mailing list.

" Possible Improvements:
" If you're particularly interested in any of these, let me know - some are
" definitely planned to happen when time permits:
"
" - Provide a function to save window variables as global variables,
"   in order to have them preserved by session saving/restoring commands,
"   and then restore the globals to window variables with another function.
"
" - Add a mode (or duplicate to a new script) to save 'views' - where a view
"   is being at a particular place in a particular file, arrived at via
"   a buffer switch, gf or tag jump.  Allow jumping back to the previous
"   view, and kill (delete, wipe) the file when jumping back past the
"   last view in that file.

" Changelog:
" Mephis Pheies Change - fix update bug, and change buflist to circular list,
"                        and delete command definition.
" 1.10 - Various fixes, eg relating to quicklists
" 1.9  - Remove unnecessary mapping delays, and a debug message
" 1.8  - Improved mapping handling, and robustness
" 1.7  - Minor improvements.
" 1.6  - Added (opt-in) Ctrl-^ override support to preserve cursor column
" 1.5  - Improved honouring of the 'confirm' vim option.
" 1.4  - Add buffer navigation, support for scratch buffer removal
" 1.3  - Convert to vim 7 lists instead of string-based lists
" 1.2  - Add column-saving support, to ensure returning to a buffer means
"        positioning the cursor not only at the right line, but also column,
"        and prompting the user when removing modified buffers
" 1.1  - Fix handling of modified, un-named buffers
" 1.0  - initial functionality
"
" Implementation Notes:
" g:BufKillList stores the list of buffers accessed so far, in order
"      of most recent access, for each respective window.
" g:BufKillColumnList store the list of columns the cursor was in when
"      a buffer was left.  It follows that since g:BufKillList lists
"      all buffers ever entered, but g:BufKillColumnList lists columns
"      only for those exited, the latter is expected to be one element
"      shorted than the former (since the current buffer should only be
"      entered, but not yet exited).
" w:BufKillIndex stores the current index into the g:BufKillList array

" Reload guard and 'compatible' handling {{{1
let s:save_cpo = &cpo
set cpo&vim

if v:version < 700
  echoe "bufkill.vim requires vim version 7.00 or greater (mainly because it uses the new lists functionality)"
  finish
endif

if exists("loaded_bufkill")
  finish
endif
let loaded_bufkill = 1


" User configurable variables {{{1
" The following variables can be set in your .vimrc/_vimrc file to override
" those in this file, such that upgrades to the script won't require you to
" re-edit these variables.

" g:BufKillCommandWhenLastBufferKilled {{{2
" When you kill the last buffer that has appeared in a window, something
" has to be displayed if we are to avoid closing the window.  Provide the
" command to be run at this time in this variable.  The default is 'enew',
" meaning that a blank window will be show, with an empty, 'No File' buffer.
" If this parameter is not set to something valid which changes the buffer
" displayed in the window, the window may be closed.
if !exists('g:BufKillCommandWhenLastBufferKilled')
  let g:BufKillCommandWhenLastBufferKilled = 'enew'
endif

" g:BufKillActionWhenBufferDisplayedInAnotherWindow {{{2
" If the buffer you are attempting to kill in one window is also displayed
" in another, you may not want to kill it afterall.  This option lets you
" decide how this situation should be handled, and can take one of the following
" values:
"   'kill' - kill the buffer regardless, always
"   'confirm' - ask for confirmation before removing it
"   'cancel' - don't kill it
" Regardless of the setting of this variable, the buffer will always be
" killed if you add an exclamation mark to the command, eg :BD!
if !exists('g:BufKillActionWhenBufferDisplayedInAnotherWindow')
  let g:BufKillActionWhenBufferDisplayedInAnotherWindow = 'confirm'
endif

" g:BufKillFunctionSelectingValidBuffersToDisplay {{{2
" When a buffer is removed from a window, the script finds the previous
" buffer displayed in the window.  However, that buffer may have been
" unloaded/deleted/wiped by some other mechanism, so it may not be a
" valid choice.  For some people, an unloaded buffer may be a valid choice,
" for others, no.
" - If unloaded buffers should be displayed, set this
"   variable to 'bufexists'.
" - If unloaded buffers should not be displayed, set this
"   variable to 'buflisted' (default).
" - Setting this variable to 'auto' means that the command :BW will use
"   'bufexists' to decide if a buffer is valid to display, whilst using
"   :BD or :BUN will use 'buflisted'
if !exists('g:BufKillFunctionSelectingValidBuffersToDisplay')
  let g:BufKillFunctionSelectingValidBuffersToDisplay = 'buflisted'
endif

" g:BufKillActionWhenModifiedFileToBeKilled {{{2
" When a request is made to kill (wipe, delete, or unload) a modified buffer
" and the "bang" (!) wasn't included in the commend, two possibilities exist:
" 1) Fail in the same way as :bw or :bd would, or
" 2) Prompt the user to save, not save, or cancel the request.
" Possible values are 'fail' (for options 1), and 'confirm' for option 2
" This is similar to the vim 'confirm' option.  Thus, if this variable
" isn't defined, the 'confirm' setting will be adopted.  Since we want
" the most current value of 'confirm', no default value need be set
" for this variable, and it needn't exist.

" g:BufKillOverrideCtrlCaret {{{2
" The standard vim functionality for Ctrl-^ or Ctrl-6 (swap to alternate
" buffer) swaps to the alternate file, and preserves the line within that file,
" but does not preserve the column within the line - instead it goes to the
" start of the line.  If you prefer to go to the same column as well,
" set this variable to 1.
if !exists('g:BufKillOverrideCtrlCaret')
  let g:BufKillOverrideCtrlCaret = 0
endif

" g:BufKillVerbose {{{2
" If set to 1, prints extra info about what's being done, why, and how to
" change it
if !exists('g:BufKillVerbose')
  let g:BufKillVerbose = 1
endif


" Commands {{{1
"
if !exists(':BB')
  command -bang BB    :call <SID>GotoBuffer('bufback',"<bang>")
endif
if !exists(':BF')
  command -bang BF    :call <SID>GotoBuffer('bufforward',"<bang>")
endif
if !exists(':BD')
  command -bang BD    :call <SID>BufKill('bd',"<bang>")
endif
if !exists(':BUN')
  command -bang BUN   :call <SID>BufKill('bun',"<bang>")
endif
if !exists(':BD')
  command -bang BD    :call <SID>BufKill('bd',"<bang>")
endif
if !exists(':BW')
  command -bang BW    :call <SID>BufKill('bw',"<bang>")
endif
if !exists(':BUNDO')
  command -bang BUNDO :call <SID>UndoKill()
endif

" Keyboard mappings {{{1
"
noremap <Plug>BufKillNew         :call <SID>BufKill('new', '')<CR>
noremap <Plug>BufKillBack        :call <SID>GotoBuffer('bufback', '')<CR>
noremap <Plug>BufKillBangBack    :call <SID>GotoBuffer('bufback', '!')<CR>
noremap <Plug>BufKillForward     :call <SID>GotoBuffer('bufforward', '')<CR>
noremap <Plug>BufKillBangForward :call <SID>GotoBuffer('bufforward', '!')<CR>
noremap <Plug>BufKillBun         :call <SID>BufKill('bun', '')<CR>
noremap <Plug>BufKillBangBun     :call <SID>BufKill('bun', '!')<CR>
noremap <Plug>BufKillBd          :call <SID>BufKill('bd', '')<CR>
noremap <Plug>BufKillBangBd      :call <SID>BufKill('bd', '!')<CR>
noremap <Plug>BufKillBw          :call <SID>BufKill('bw', '')<CR>
noremap <Plug>BufKillBangBw      :call <SID>BufKill('bw', '!')<CR>
noremap <Plug>BufKillUndo        :call <SID>UndoKill()<CR>

function! <SID>CreateUniqueMapping(lhs, rhs, ...)
  if hasmapto(a:rhs) && !(a:0 == 1 && a:1 == 'AllowDuplicate')
    " The user appears to have defined an alternate mapping for this command
    return
  elseif maparg(a:lhs, 'n') != ""
    " The user appears to have defined a mapping for a:lhs already
    return
  endif
  exec 'nmap <silent> <unique> '.a:lhs.' '.a:rhs
endfunction

call <SID>CreateUniqueMapping('<Leader>bt',   '<Plug>BufKillNew')
call <SID>CreateUniqueMapping('<Leader>bn',   '<Plug>BufKillBack')
call <SID>CreateUniqueMapping('<Leader>bp',   '<Plug>BufKillForward')
"call <SID>CreateUniqueMapping('<Leader>bun',  '<Plug>BufKillBun')
"call <SID>CreateUniqueMapping('<Leader>!bun', '<Plug>BufKillBangBun')
call <SID>CreateUniqueMapping('<Leader>bd',   '<Plug>BufKillBd')
call <SID>CreateUniqueMapping('<Leader>!bd',  '<Plug>BufKillBangBd')
"call <SID>CreateUniqueMapping('<Leader>bw',   '<Plug>BufKillBw')
"call <SID>CreateUniqueMapping('<Leader>!bw',  '<Plug>BufKillBangBw')
call <SID>CreateUniqueMapping('<Leader>bundo','<Plug>BufKillUndo')
"if g:BufKillOverrideCtrlCaret == 1
  "call <SID>CreateUniqueMapping('<C-^>', '<Plug>BufKillAlt', 'AllowDuplicate')
"endif


function! <SID>BufKill(cmd, bang) "{{{1
" The main function that sparks the buffer change/removal
  if !exists('g:BufKillList')
    echoe "BufKill Error: array g:BufKillList does not exist!"
    echoe "Restart vim and retry, and if problems persist, notify the author!"
    return
  endif

  call <SID>SaveWindowPos()

  " Get the buffer to delete - the current one obviously
  let s:BufKillBufferToKill = bufnr('%')
  let s:BufKillBufferToKillPath = expand('%:p')

  " If the buffer is already '[No File]' then doing enew won't create a new
  " buffer, hence the bd/bw command will kill the current buffer and take
  " the window with it... so check for this case
  " However - if it's a scratch buffer with text enew should create a new
  " buffer, so don't return if it is a scratch buffer
  if bufname('%') == '' && ! &modified && &modifiable
    " No buffer to kill, ensure not scratch buffer
    if &buftype == 'nofile' && &swapfile == 0
      " Is scratch buffer, keep processing
    else
      return
    endif
  endif

  " Just to make sure, check that this matches the buffer currently pointer to
  " by w:BufKillIndex - else I've stuffed up
  if s:BufKillBufferToKill != g:BufKillList[w:BufKillIndex]
    echom "BufKill Warning: bufferToKill = ".s:BufKillBufferToKill." != element ".w:BufKillIndex." in the list: (".string(g:BufKillList).")"
    echom "Please notify the author of the circumstances of this message!"
  endif

  " If the buffer is modified, and a:bang is not set, give the same kind of
  " error (or confirmation) as normal bw/bd
  if &modified && strlen(a:bang) == 0
    if exists('g:BufKillActionWhenModifiedFileToBeKilled')
      let s:BufKillActionWhenModifiedFileToBeKilled = g:BufKillActionWhenModifiedFileToBeKilled
    else
      if &confirm
        let s:BufKillActionWhenModifiedFileToBeKilled = 'confirm'
      else
        let s:BufKillActionWhenModifiedFileToBeKilled = 'fail'
      endif
    endif
    if s:BufKillActionWhenModifiedFileToBeKilled =~ '[Ff][Aa][Ii][Ll]'
      echo "No write since last change for buffer '" . bufname(s:BufKillBufferToKill) . "' (add ! to override)"
      return
    elseif s:BufKillActionWhenModifiedFileToBeKilled =~ '[Cc][Oo][Nn][Ff][Ii][Rr][Mm]'
      let options = "&Yes\n&No\n&Cancel"
      let actionAdjustment = 0
      let bufname = bufname(winbufnr(winnr()))
      if bufname == ''
        let bufname = '[No File]'
        let options = "&No\n&Cancel"
        let actionAdjustment = 1
      endif
      let action=confirm("Save Changes in " . bufname . " before operation?", options)
      if action + actionAdjustment == 1
        " Yes - try to save - if there is an error, cancel
        let v:errmsg = ""
        silent w
        if v:errmsg != ""
          echoerr "Unable to write buffer!"
          return
        endif
      elseif action + actionAdjustment == 2
        " No, abandon changes
        set nomodified
      else
        " Cancel (or any other result), don't do the open
        return
      endif
    else
      echoe "Illegal value (' . s:BufKillActionWhenModifiedFileToBeKilled . ') stored in variable s:BufKillActionWhenModifiedFileToBeKilled, please notify the author"
    endif
  endif

  " create new buffer
  if (a:cmd == 'new')
    exec g:BufKillCommandWhenLastBufferKilled 
    return
  endif
  

  " Get a list of all windows which have this buffer loaded
  let s:BufKillWindowListWithBufferLoaded = []
  let i = 1
  let buf = winbufnr(i)
  while buf != -1
    if buf == s:BufKillBufferToKill
      let s:BufKillWindowListWithBufferLoaded += [i]
    endif
    let i = i + 1
    let buf = winbufnr(i)
  endwhile

  " Handle the case where the buffer is displayed in multiple windows
  if len(s:BufKillWindowListWithBufferLoaded) > 1 && strlen(a:bang) == 0
    if g:BufKillActionWhenBufferDisplayedInAnotherWindow =~ '[Cc][Aa][Nn][Cc][Ee][Ll]'
      if g:BufKillVerbose
        echom "Buffer '" . bufname(s:BufKillBufferToKill) . "' displayed in multiple windows - " . a:cmd . " cancelled (add ! to kill anywawy, or set g:BufKillActionWhenBufferDisplayedInAnotherWindow to 'confirm' or 'kill')"
      endif
      return
    elseif g:BufKillActionWhenBufferDisplayedInAnotherWindow =~ '[Cc][Oo][Nn][Ff][Ii][Rr][Mm]'
      let choice = confirm("Buffer '" . bufname(s:BufKillBufferToKill) . "' displayed in multiple windows - " . a:cmd . " it anyway?", "&Yes\n&No", 1)
      if choice != 1
        return
      endif
    elseif g:BufKillActionWhenBufferDisplayedInAnotherWindow =~ '[Rr][Ee][Mm][Oo][Vv][Ee]'
      if g:BufKillVerbose
        echom "Buffer '" . bufname(s:BufKillBufferToKill) . "' displayed in multiple windows - executing " . a:cmd . " anyway."
      endif
      " Fall through and continue
    endif
  endif

  " For each window that the file is loaded in, go to the previous buffer from its list
  let i = 0
  " to change
  while i < len(s:BufKillWindowListWithBufferLoaded)
    let win = s:BufKillWindowListWithBufferLoaded[i]

    " Go to the right window in which to perform the action
    if win > 0
      exec 'normal! ' . win . 'w'
    endif

    " Go to the previous buffer for this window
    call <SID>GotoBuffer(a:cmd, a:bang)

    let i = i + 1
  endwhile

  " Restore the cursor to the correct window _before_ removing the buffer,
  " since the buffer removal could have side effects on the windows (eg
  " minibuffer disappearing due to not enough buffers)
  call <SID>RestoreWindowPos()

  " Kill the old buffer, but save info about it for undo purposes
  let s:BufKillLastWindowListWithBufferLoaded = s:BufKillWindowListWithBufferLoaded
  let s:BufKillLastBufferKilledPath = s:BufKillBufferToKillPath
  let s:BufKillLastBufferKilledNum = s:BufKillBufferToKill
  " In some cases (eg when deleting the quickfix buffer) the buffer will
  " already have been deleted by the switching to another buffer in its
  " window.  Thus we must check before deleting.
  if bufexists(s:BufKillBufferToKill)
    let killCmd = a:cmd . a:bang . s:BufKillBufferToKill
    exec killCmd
  else
  endif

endfunction

function! <SID>RingBufferListSeat(logical_seat, list_len)
  "Treat buffer list as a circular list, "This function change logical_seat 
  "to the actual seat according to the length of list.
  
  " if logical_seat is navigation , add list_len to logical_seat until
  " logical_seat > 0
  let valid_seat = a:logical_seat
  while (valid_seat < 0 )
    let valid_seat += a:list_len
  endwhile

  " return the a:logical_seat mode list_len
  return valid_seat % a:list_len
endfunction


function! <SID>GotoBuffer(cmd, bang) "{{{1
  "Function to display the previous buffer for the specified window
  " a:cmd is one of
  "     bw - Wiping the current buffer
  "     bd - Deleting the current buffer
  "     bufback - stepping back through the list
  "     bufforward - stepping forward through the list
  let w:BufKillBeforeIndex = w:BufKillIndex

  if (a:cmd=='bw' || a:cmd=='bd')
    let w:BufKillLastCmd = a:cmd . a:bang
    " Handle the 'auto' setting for
    " g:BufKillFunctionSelectingValidBuffersToDisplay
    let validityFunction = g:BufKillFunctionSelectingValidBuffersToDisplay
    if validityFunction == 'auto'
      " The theory here is that if a person usually uses bd, then buffers
      " they've intended to delete will still exist, but not be listed.  Hence
      " we use buflisted to check if they've deleted the buffer already, so as
      " not to show the ones they've deleted.  If instead they use bw,
      " then the assumption is that to really delete buffers they use bw, so
      " if they've used bd, they were meaning to hide the file from view - but
      " keep it around - hence we should find it if it's only been deleted,
      " hence we use bufexists to look for it.  Yes, it's weak logic - but you
      " can always override it! ;)
      if a:cmd == 'bw'
        let validityFunction = 'bufexists'
      else
        let validityFunction = 'buflisted'
      endif
    endif
    let w:BufKillIndex = <SID>RingBufferListSeat(w:BufKillIndex-1, len(g:BufKillList))
  else
    let w:BufKillLastCmd = 'bufchange'
    " Should only be used with undeleted (and unwiped) buffers
    let validityFunction = 'buflisted'

    if a:cmd == 'bufforward'
      let w:BufKillIndex = <SID>RingBufferListSeat(w:BufKillIndex+1, len(g:BufKillList))
    elseif a:cmd == 'bufback'
      let w:BufKillIndex = <SID>RingBufferListSeat(w:BufKillIndex-1, len(g:BufKillList))
    endif
  endif

  " Find the most recent buffer to display
  if (w:BufKillBeforeIndex != w:BufKillIndex)
    let newBuffer = g:BufKillList[w:BufKillIndex]
    exec 'let validityResult = '.validityFunction.'(newBuffer)'
    while !validityResult
      " some buffers are the user not need, and some invalid buffers are those
      " user delete using other command which not within this package 
      call remove(g:BufKillList, w:BufKillIndex)
      call remove(g:BufKillColumnList, w:BufKillIndex)
      " for circular list , bufforward alse need to conside
      if a:cmd == 'bufforward'
        let w:BufKillIndex = <SID>RingBufferListSeat(w:BufKillIndex+1, len(g:BufKillList))
      else
        let w:BufKillIndex = <SID>RingBufferListSeat(w:BufKillIndex-1, len(g:BufKillList))
      endif
      " After back the starting point，Back out it
      if (w:BufKillBeforeIndex == w:BufKillIndex)
        break
      endif
      let newBuffer = g:BufKillList[w:BufKillIndex]
      exec 'let validityResult = '.validityFunction.'(newBuffer)'
    endwhile
  endif

  " When find the different buffer, use it
  " When not find and w:BufKillLastCmd has been set, just unset it and echo
  " messages
  if (w:BufKillBeforeIndex != w:BufKillIndex)
    let newColumn = g:BufKillColumnList[w:BufKillIndex]
    let cmd = 'b' . a:bang . newBuffer . "|call cursor(line('.')," . newColumn . ')'
    exec cmd
  elseif (w:BufKillLastCmd == 'bufchange')
    let w:BufKillLastCmd = ''
    echom 'No Other List Buffers.'
  endif
endfunction   " GotoBuffer

function! <SID>UpdateList(event) "{{{1
  " Function to update the window list with info about the current buffer
  if !exists('g:BufKillList')
    let g:BufKillList = []
  endif
  if !exists('g:BufKillColumnList')
    let g:BufKillColumnList = []
  endif
  if !exists('w:BufKillIndex')
    let w:BufKillIndex = -1
  endif
  if !exists('w:BufKillLastCmd')
    let w:BufKillLastCmd = ''
  endif
  let bufferNum = bufnr('%')

  if (w:BufKillLastCmd=~'bufchange')
    " When stepping through files, the g:BufKillList should not be changed
    " here, only by the GotoBuffer command since the files must already
    " exist in the list to jump to them.
  elseif (w:BufKillLastCmd != '')
    " When killing buffer , the w:BufKillBeforeIndex should be deleted 
    " here.
    
    " if the w:BufKillIndex pointer go to the tail, change it to the tail-1
    if(len(g:BufKillList)-2 < w:BufKillIndex)
      let w:BufKillIndex = <SID>RingBufferListSeat(w:BufKillIndex-1, len(w:BufKillIndex))
    end

    " The branch is diverging, remove the 
    call remove(g:BufKillList, w:BufKillBeforeIndex)
    " Same for column list
    call remove(g:BufKillColumnList, w:BufKillBeforeIndex)
  else
    " When buffer entering by other ways,
    " if existing buffer , just adjust w:BufKillIndex to existingIndex
    " if new buffer , add it to w:BufKillIndex
    
    let existingIndex = index(g:BufKillList, bufferNum)
    if existingIndex != -1
      let w:BufKillIndex = existingIndex
    else
      " Now add the buffer to the list, at the end
      let w:BufKillIndex = len(g:BufKillList) 
      let g:BufKillList += [bufferNum]
    endif
  endif

  " Reset since command processed
  let w:BufKillLastCmd = ''

endfunction   " UpdateList

function! <SID>UpdateLastColumn(event) "{{{1
  " Function to save the current column and buffer and window numbers,
  if !exists('g:BufKillList')
    " Just give up for now.
    return
  endif
  let index = index(g:BufKillList, bufnr('%'))
  if index != -1
    " Extend list if required, then set the value
    let g:BufKillColumnList += repeat([0], index - len(g:BufKillColumnList) + 1)
    let g:BufKillColumnList[index] = col('.')
  else
    echom 'UpdateLastColumn failed to find bufnr ' . bufnr('%') . ' in g:BufKillList'
  endif
endfunction

function! <SID>UndoKill() "{{{1

  if !exists('s:BufKillLastBufferKilledNum') || !exists('s:BufKillLastBufferKilledPath') || s:BufKillLastBufferKilledNum == -1 || s:BufKillLastBufferKilledPath == ''
    echoe 'BufKill: nothing to undo (only one level of undo is supported)'
  else
    if bufexists(s:BufKillLastBufferKilledNum)
      let cmd = 'b' . s:BufKillLastBufferKilledNum
    elseif filereadable(s:BufKillLastBufferKilledPath)
      let cmd = 'e ' . s:BufKillLastBufferKilledPath
    else
      unlet s:BufKillLastBufferKilledNum
      unlet s:BufKillLastBufferKilledPath
      unlet s:BufKillLastWindowListWithBufferLoaded
      echoe 'BufKill: unable to undo. Neither buffer (' . s:BufKillLastBufferKilledNum . ') nor file (' . s:BufKillLastBufferKilledPath . ') could be found.'
    endif

    " For each window the buffer was removed from, show it again
    call <SID>SaveWindowPos()
    let i = 0
    while i < len(s:BufKillLastWindowListWithBufferLoaded)
      let win = s:BufKillLastWindowListWithBufferLoaded[i]
      exec 'normal! ' . win . 'w'
      exec cmd
      let i = i + 1
    endwhile
    call <SID>RestoreWindowPos()

    unlet s:BufKillLastBufferKilledNum
    unlet s:BufKillLastBufferKilledPath
    unlet s:BufKillLastWindowListWithBufferLoaded
  endif
endfunction

function! <SID>SaveWindowPos() "{{{1
  " Save the current window, to be able to come back to it after doing things
  " in other windows
  let s:BufKillWindowPos = winnr()
endfunction

function! <SID>RestoreWindowPos() "{{{1
  " Restore the window from it's saved config variable
  exec 'normal! ' . s:BufKillWindowPos . 'w'
endfunction

" Autocommands {{{1
"
augroup BufKill
autocmd BufKill WinEnter * call <SID>UpdateList('WinEnter')
autocmd BufKill BufEnter * call <SID>UpdateList('BufEnter')
autocmd BufKill WinLeave * call <SID>UpdateLastColumn('WinLeave')
autocmd BufKill BufLeave * call <SID>UpdateLastColumn('BufLeave')

" Cleanup and modelines {{{1
let &cpo = s:save_cpo

" vim:ft=vim:fdm=marker:fen:fmr={{{,}}}:
