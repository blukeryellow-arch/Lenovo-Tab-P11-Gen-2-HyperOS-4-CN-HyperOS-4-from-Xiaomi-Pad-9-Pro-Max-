# Lenovo TB350FU runtime audit

- target build from device log: `TB350FU_S231044_260105_ROW`
- downloaded forensic package: `https://support.halabtech.com/index.php?a=downloads&b=file&c=download&id=1043822`
- scope: read-only identification of the classpath artifact behind the Lenovo battery NPE
- this package is **not** used as a HyperOS donor or copied into an output image

## Audit failure diagnostic

- failed command: `unzip -Z1 "$archive" > "$work/archive-files.txt"`
- exit code: `9`

```
lenovo-runtime-audit/TB350FU_USER_S231044_2601050946_MP_ROW.zip 98747 B
lenovo-runtime-audit/archive-files.txt 0 B
lenovo-runtime-audit/download.stderr 555 B
```

### download.stderr (tail)
```
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
100 17630    0 17630    0     0  12112      0 --:--:--  0:00:01 --:--:-- 12112100 98747    0 98747    0     0  59805      0 --:--:--  0:00:01 --:--:--  406k
```
