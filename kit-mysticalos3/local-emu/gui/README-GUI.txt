=== MysticalOS Emu Viewer (GUI) ===

1. Wymagania: Windows 10/11 + WSL2 z kitem w ~/kit (patrz INSTRUKCJA-EMU-LOCAL.txt)
2. Odpalanie: dwuklik Start-GUI.bat
3. Przyciski:
   - START emulatora: odpala test boota w nowym oknie (fazy + statusy LIVE)
   - STOP: ubija emulator
   - Screenshot / auto co 5 s: zdjecie ekranu Androida (dziala dopiero, gdy
     system zyje - wczesniej czarny/brak)
4. Pasek na gorze: loops (restarty; 1 = OK), fatal, zyg (zygote), data (/data)
5. Screenshoty zapisuja sie w Downloads/emu-gui/screen.png
6. Zmiana sciezki obrazu: edytuj MysticalEmuGui.ps1 (ImgWin) albo gui/gui-start.sh (IMG=)
