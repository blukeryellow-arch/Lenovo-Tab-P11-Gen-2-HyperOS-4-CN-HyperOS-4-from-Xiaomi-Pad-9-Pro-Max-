# donor-pipeline run 37020690506 (2026-10-02T15:20:16Z)

## probe
```
brak donor-product w cache - bedzie Drive
probe [drive.usercontent.google.com] -> 206 CR='bytes 0-0/10340028849' body0=b'P'
speed 1-watkowo (32 MiB): 0.00 MB/s
Filesystem      Size  Used Avail Use% Mounted on
/dev/root       145G   59G   86G  41% /
```
## ekstrakcja (tail 100)
```
# probe: status=200 CR='' CL='2009' AR='none' CT='text/html; charset=utf-8' body0=b'<'
# probe retry 1/10: brak dowodu range (status=200 CT=text/html; charset=utf-8 body0=b'<')
# probe: status=200 CR='' CL='2009' AR='none' CT='text/html; charset=utf-8' body0=b'<'
# probe retry 2/10: brak dowodu range (status=200 CT=text/html; charset=utf-8 body0=b'<')
# probe: status=200 CR='' CL='2009' AR='none' CT='text/html; charset=utf-8' body0=b'<'
# probe retry 3/10: brak dowodu range (status=200 CT=text/html; charset=utf-8 body0=b'<')
# probe: status=200 CR='' CL='2009' AR='none' CT='text/html; charset=utf-8' body0=b'<'
# probe retry 4/10: brak dowodu range (status=200 CT=text/html; charset=utf-8 body0=b'<')
# probe: status=200 CR='' CL='2009' AR='none' CT='text/html; charset=utf-8' body0=b'<'
# probe retry 5/10: brak dowodu range (status=200 CT=text/html; charset=utf-8 body0=b'<')
# probe: status=200 CR='' CL='2009' AR='none' CT='text/html; charset=utf-8' body0=b'<'
# probe retry 6/10: brak dowodu range (status=200 CT=text/html; charset=utf-8 body0=b'<')
# probe: status=200 CR='' CL='2009' AR='none' CT='text/html; charset=utf-8' body0=b'<'
# probe retry 7/10: brak dowodu range (status=200 CT=text/html; charset=utf-8 body0=b'<')
# probe: status=200 CR='' CL='2009' AR='none' CT='text/html; charset=utf-8' body0=b'<'
# probe retry 8/10: brak dowodu range (status=200 CT=text/html; charset=utf-8 body0=b'<')
# probe: status=200 CR='' CL='2009' AR='none' CT='text/html; charset=utf-8' body0=b'<'
# probe retry 9/10: brak dowodu range (status=200 CT=text/html; charset=utf-8 body0=b'<')
# probe: status=200 CR='' CL='2009' AR='none' CT='text/html; charset=utf-8' body0=b'<'
# probe retry 10/10: brak dowodu range (status=200 CT=text/html; charset=utf-8 body0=b'<')
probe nie wyszedl po 10 probach (60s przerwy) - Drive quota/interstitial? Ostatni blad: brak dowodu range (status=200 CT=text/html; charset=utf-8 body0=b'<')
```
## harvest (tail 120)
```
```
## manifesty
```
```
## dysk
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/root       145G   59G   86G  41% /
```
