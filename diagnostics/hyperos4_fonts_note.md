# Czcionki w HyperOS 4 (source) — nie sa w obrazie, sa symlinkiem w /data

Zmierzono 2026-09-23 na pliku sciagnietym z Twojego Dysku kanalem kawalkow
(`system.img` 937 791 488 B, sha256 `4d3c61fe358f78102f5cae7bdaacc9f7a5d5d3c726d881dbc0ee3dcc697ee462`;
paczka `images/system.assets.tar.gz` 749 834 731 B, sha256 `afb1e37bc86b2d3b2bf74a1510718dec39f6d77d0637a47bb22b3777b71b9225`).

```
$ tar tzvf images/system.assets.tar.gz | grep fonts.xml
lrw-r--r-- root/root 0 2009-01-01 ./system/etc/fonts.xml -> /data/system/fonts/theme_webview/fonts.xml
```

Konsekwencje dla sciezki A (nadaja sie do uzycia bez ruszania partycji systemowych):

1. **Nie patchujemy `system/etc/fonts.xml` ani `system/fonts/*.ttc`.** Po pierwsze po to nie
   trzeba: framework czyta konfiguracje z `/data/system/fonts/theme_webview/fonts.xml`. Po
   drugie nie mozna: obok `framework-res.apk` lezy `framework-res.apk.fsv_meta`, czyli pliki
   systemu sa pod fs-verity (potwierdza `flags=0` + hashtree z `vbmeta.img` — weryfikacja
   wlaczona, kazda zmiana bajta = odczyt `EIO`).
2. **Wyswietlanie HyperOS = plik w `/data` + uprawnienie roota.** Modul `hyperos_look_p11g2`
   moze dostarczac `service.sh`, ktory montuje (bind) katalog czcionek z modulu pod
   `/data/system/fonts/theme_webview` — to sciezka, ktorej uzywa sam MIUI/HyperOS, wiec
   nie wymaga overlayu ani resetu `daemon`. `fonts.xml` docelowy ma te sama skladnie co
   AOSP (`<familyset>`), wiec konfiguracja z `system/fonts` targetu da sie przekonwertowac.
3. Czego jeszcze brakuje do domkniecia motywu: `product/overlay`, `system_ext/overlay`,
   `vendor_mystical.img` (tam sa RRO z ksztaltami UI) — w `system.img` NIE MA adnego
   `/overlay/*.apk` (zmierzone: 0 plikow). Te trzy obrazy zostaly do ściągnięcia.

Uwaga praktyczna: na targetowym Lenovo (stock A14) `theme_webview` moze nie istniec — wowczas
`hwui.use_gpu_path`/font fallback i tak przejdzie, ale plik trzeba utworzyc, nie zakladac, ze
jest. `verify_module.sh` powinien sprawdzac oba stany (link jest/nie ma).
