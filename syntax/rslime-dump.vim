" rslime-dump: highlight for Dump()/Print() panel output
" Structure (stable):  ==> Dumping object at: 0x…, name=p, class=TH1F
"                      fNcells                       102                 Number of bins…
"                      fXaxis                        ->76928d3878        X axis descriptor
"                      (TH1F *) 0x76928d3800

syn match rslimeDumpHeader  /^==>.*$/ contains=rslimeDumpAddr
syn match rslimeDumpTypeVal /^(\S.*$/ contains=rslimeDumpType,rslimeDumpAddr
syn match rslimeDumpType    /(\zs\w\+\ze\s*[*&])/ contained
syn match rslimeDumpAddr    /\(->\)\?0x\x\+\|->\x\{6,}/ containedin=ALL
syn match rslimeDumpMember  /^\w\+/
syn match rslimeDumpComment /^\w\+\s\+\S\+\s\{2,}\zs.*$/
syn match rslimeDumpNumber  /^\w\+\s\+\zs[-+]\?\d\+\%(\.\d\+\)\?\%([eE][-+]\?\d\+\)\?/

hi def link rslimeDumpHeader  PreProc
hi def link rslimeDumpTypeVal Special
hi def link rslimeDumpType    Type
hi def link rslimeDumpAddr    Underlined
hi def link rslimeDumpMember  Identifier
hi def link rslimeDumpComment Comment
hi def link rslimeDumpNumber  Number
