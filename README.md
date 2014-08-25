# bwftool (Broadcast Wave Format metadata tool)

Public domain.

##usage

```
  % bwftool.pl dump <input.wav>
```
Dump BWF information in JSON format

```
  % bwftool.pl extract <input.wav> <output>
```
Extract BWF metadata to a file

```
  % bwftool.pl copy <bwfinput> <output.wav>
```
Copy BWF header on <bwfinput> to <output.wav>
* <bwfinput> can be either extracted BWF info or another WAV file
* WARNING: <output.wav> is modified

