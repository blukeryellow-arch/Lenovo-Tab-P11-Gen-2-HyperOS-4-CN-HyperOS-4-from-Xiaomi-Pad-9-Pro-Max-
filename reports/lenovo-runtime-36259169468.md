# Lenovo TB350FU runtime audit

- target build from device log: `TB350FU_S231044_260105_ROW`
- downloaded forensic package: `https://support.halabtech.com/index.php?a=downloads&b=file&c=download&id=1043822`
- scope: read-only identification of the classpath artifact behind the Lenovo battery NPE
- this package is **not** used as a HyperOS donor or copied into an output image

## Download-route diagnostic

- HalabTech returned an HTML/login response instead of a ZIP to an anonymous request.
- alternative public page: `https://filewale.com/files/lenovo-tab-p11-gen-2-tb350fu_user_s231044_2601050946_mp_row_filewalecomzip/45346`
```
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=1080&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=1200&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=128&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=16&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=1920&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=256&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=32&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=384&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=48&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=64&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=640&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=750&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=828&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1778443525060-331651893.gif&amp;w=96&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=1080&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=1200&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=128&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=16&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=1920&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=256&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=32&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=384&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=48&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=64&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=640&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=750&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=828&amp;q=75
https%3A%2F%2Fdhbv6ec3d056z.cloudfront.net%2Fuploads%2Fimages%2F1779798451506-100990746.png&amp;w=96&amp;q=75
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1778443525060-331651893.gif\
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1778443609283-671133185.svg\
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1778444536629-997633836.png\
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1779798451506-100990746.png
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1779798451506-100990746.png\
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1779798451506-100990746.png\\\
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1779798890456-115967878.png
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1779798890456-115967878.png\
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1784209866013-950161766.jpg\
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1788932788385-828869750.jpeg\
https://dhbv6ec3d056z.cloudfront.net/uploads/images/1790142234057-688669780.png\
https://dhbv6ec3d056z.cloudfront.net\
https://filewale.com/dashboard/downloads
https://filewale.com/dashboard/downloads\
https://filewale.com/files/lenovo-tab-p11-gen-2-tb350fu_user_s231044_2601050946_mp_row_filewalecomzip/45346
https://filewale.com/files/lenovo-tab-p11-gen-2-tb350fu_user_s231044_2601050946_mp_row_filewalecomzip/45346\
https://filewale.com/files/lenovo-tab-p11-gen-2-tb350fu_user_s231044_2601050946_mp_row_filewalecomzip/45346\\\
```

## Audit failure diagnostic

- failed command: `false`
- exit code: `1`

```
lenovo-runtime-audit/download.stderr 555 B
lenovo-runtime-audit/filewale-page.html 139190 B
lenovo-runtime-audit/filewale.stderr 633 B
lenovo-runtime-audit/halab-response.html 98747 B
```

### download.stderr (tail)
```
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
100  8065    0  8065    0     0   7027      0 --:--:--  0:00:01 --:--:--  7027100 98747    0 98747    0     0  57486      0 --:--:--  0:00:01 --:--:--  155k100 98747    0 98747    0     0  57481      0 --:--:--  0:00:01 --:--:--  155k
```

### filewale.stderr (tail)
```
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0  0     0    0     0    0     0      0      0 --:--:--  0:00:01 --:--:--     0  0     0    0     0    0     0      0      0 --:--:--  0:00:02 --:--:--     0  0     0    0     0    0     0      0      0 --:--:--  0:00:03 --:--:--     0  0     0    0     0    0     0      0      0 --:--:--  0:00:04 --:--:--     0100  135k    0  135k    0     0  29926      0 --:--:--  0:00:04 --:--:-- 29933
```
