# Full recovery audit bootstrap failure

- failed command: `( cd work/payload-dumper-src && go build -trimpath -o ../payload-dumper-go . ) >> work/payload-bootstrap.log 2>&1`
- exit code: `1`

```
work/payload-bootstrap.log 1542 B
work/payload-dumper-src/.editorconfig 639 B
work/payload-dumper-src/.git/HEAD 41 B
work/payload-dumper-src/.git/config 205 B
work/payload-dumper-src/.git/description 73 B
work/payload-dumper-src/.git/index 1403 B
work/payload-dumper-src/.git/packed-refs 103 B
work/payload-dumper-src/.git/shallow 41 B
work/payload-dumper-src/.gitignore 750 B
work/payload-dumper-src/.goreleaser.yml 1714 B
work/payload-dumper-src/Dockerfile 373 B
work/payload-dumper-src/LICENSE 11347 B
work/payload-dumper-src/README.md 12619 B
work/payload-dumper-src/chromeos_update_engine/update_metadata.pb.go 82399 B
work/payload-dumper-src/go.mod 511 B
work/payload-dumper-src/go.sum 1950 B
work/payload-dumper-src/main.go 3282 B
work/payload-dumper-src/payload.go 9825 B
work/payload-dumper-src/reader.go 731 B
work/payload-dumper-src/update_metadata.proto 19231 B
```

### payload-bootstrap.log
```
Cloning into 'work/payload-dumper-src'...
Note: switching to 'a51234eaead276ff3d8b8c4c439c51c7f46a96a8'.

You are in 'detached HEAD' state. You can look around, make experimental
changes and commit them, and you can discard any commits you make in this
state without impacting any branches by switching back to a branch.

If you want to create a new branch to retain commits you create, you may
do so (now or later) by using -c with the switch command. Example:

  git switch -c <new-branch-name>

Or undo this operation with:

  git switch -

Turn off this advice by setting config variable advice.detachedHead to false

go: downloading github.com/dustin/go-humanize v1.0.1
go: downloading github.com/spencercw/go-xz v0.0.0-20181128201811-c82a2123b492
go: downloading github.com/valyala/gozstd v1.21.1
go: downloading github.com/vbauerster/mpb/v5 v5.4.0
go: downloading google.golang.org/protobuf v1.34.2
go: downloading github.com/acarl005/stripansi v0.0.0-20180116102854-5a71ef0e047d
go: downloading github.com/mattn/go-runewidth v0.0.9
go: downloading github.com/VividCortex/ewma v1.1.1
go: downloading golang.org/x/sys v0.22.0
# github.com/spencercw/go-xz
/home/runner/go/pkg/mod/github.com/spencercw/go-xz@v0.0.0-20181128201811-c82a2123b492/compression.go:36:10: fatal error: lzma.h: No such file or directory
   36 | #include <lzma.h>
      |          ^~~~~~~~
compilation terminated.
/home/runner/work/_temp/edfe9866-ea15-402b-8577-8561091a8e56.sh: line 4: reports/hyperos-recovery-bootstrap-36276277466.md: No such file or directory
```
