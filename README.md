# bwftool (Broadcast Wave Format metadata tool)

Public domain.

##usage
###Pretty-print BWF metadata in the input
```
  % bwftool.pl [show] <input.wav>
```

###Dump BWF information in JSON format
```
  % bwftool.pl dump <input.wav>
```

###Extract BWF metadata to a file
```
  % bwftool.pl extract <input.wav> <output>
```

###Copy BWF header from a file to another
```
  % bwftool.pl copy <bwfinput> <output.wav>
```
* bwfinput can be either extracted BWF info or another WAV file
* WARNING: file specified as output is modified

###Generate Vorbis comment fields from BWF metadata
```
  % bwftool.pl vorbis <input.wav>
```
The format is suitable for use with metaflac --import-tags-from-file

###Remove BWF metadata from a file
```
  % bwftool.pl remove <input.wav>
```

