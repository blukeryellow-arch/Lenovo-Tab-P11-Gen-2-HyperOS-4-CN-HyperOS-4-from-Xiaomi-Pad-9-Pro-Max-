package org.mysticalos.launcher;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.BatteryManager;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.text.Editable;
import android.text.TextUtils;
import android.text.TextWatcher;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.GridLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.TextClock;
import android.widget.TextView;
import android.widget.Toast;

import java.io.BufferedReader;
import java.io.FileReader;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

public class MysticalHomeActivity extends Activity {
    private List<AppRepository.AppEntry> allApps = new ArrayList<>();
    private GridLayout appGrid;
    private LinearLayout dockRow;
    private LinearLayout dynamicIslandPill;
    private TextView islandTitle;
    private TextView islandSub;
    private TextView ramBadge;
    private TextView dateBadge;
    private EditText searchBox;
    private String queryText = "";
    private boolean islandExpanded = false;

    private final BroadcastReceiver pkgReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            reloadAppsAndRender();
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SHOW_WALLPAPER);
        getWindow().setStatusBarColor(Color.TRANSPARENT);
        getWindow().setNavigationBarColor(Color.argb(120, 10, 12, 22));

        buildUi();

        IntentFilter filter = new IntentFilter();
        filter.addAction(Intent.ACTION_PACKAGE_ADDED);
        filter.addAction(Intent.ACTION_PACKAGE_REMOVED);
        filter.addAction(Intent.ACTION_PACKAGE_CHANGED);
        filter.addDataScheme("package");
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(pkgReceiver, filter, 4 /* RECEIVER_NOT_EXPORTED */);
        } else {
            registerReceiver(pkgReceiver, filter);
        }

        reloadAppsAndRender();
    }

    @Override
    protected void onResume() {
        super.onResume();
        updateSystemHeader();
        renderGridAndDock();
    }

    @Override
    protected void onDestroy() {
        try {
            unregisterReceiver(pkgReceiver);
        } catch (Throwable ignored) {}
        super.onDestroy();
    }

    @Override
    public void onBackPressed() {
        if (islandExpanded) {
            islandExpanded = false;
            updateSystemHeader();
            return;
        }
        if (searchBox != null && !TextUtils.isEmpty(searchBox.getText())) {
            searchBox.setText("");
        }
    }

    private void buildUi() {
        LinearLayout outer = new LinearLayout(this);
        outer.setOrientation(LinearLayout.VERTICAL);
        outer.setBackgroundColor(Color.argb(105, 8, 10, 20));
        outer.setOnLongClickListener(v -> {
            openQuickWallpaperOrIconMenu();
            return true;
        });

        // Always-on HyperOS 4 Dynamic Island Pill preview & status pill
        dynamicIslandPill = new LinearLayout(this);
        dynamicIslandPill.setOrientation(LinearLayout.VERTICAL);
        dynamicIslandPill.setGravity(Gravity.CENTER_HORIZONTAL);
        GradientDrawable ibg = new GradientDrawable();
        ibg.setColor(Color.argb(238, 8, 10, 16));
        ibg.setCornerRadius(dp(22));
        ibg.setStroke(dp(1), Color.argb(110, 0, 212, 255));
        dynamicIslandPill.setBackground(ibg);
        dynamicIslandPill.setPadding(dp(16), dp(7), dp(16), dp(7));
        LinearLayout.LayoutParams ilp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        ilp.gravity = Gravity.CENTER_HORIZONTAL;
        ilp.setMargins(dp(16), dp(14), dp(16), dp(8));
        dynamicIslandPill.setLayoutParams(ilp);
        dynamicIslandPill.setOnClickListener(v -> {
            islandExpanded = !islandExpanded;
            updateSystemHeader();
        });

        islandTitle = new TextView(this);
        islandTitle.setTextColor(Color.WHITE);
        islandTitle.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        islandTitle.setTypeface(Typeface.DEFAULT_BOLD);
        dynamicIslandPill.addView(islandTitle);

        islandSub = new TextView(this);
        islandSub.setTextColor(Color.rgb(122, 236, 200));
        islandSub.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
        islandSub.setPadding(0, dp(4), 0, 0);
        islandSub.setVisibility(View.GONE);
        dynamicIslandPill.addView(islandSub);
        outer.addView(dynamicIslandPill);

        // Header Flux Card
        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.VERTICAL);
        GradientDrawable hbg = new GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                new int[]{Color.argb(185, 22, 24, 48), Color.argb(175, 16, 20, 38)});
        hbg.setCornerRadius(dp(22));
        hbg.setStroke(dp(1), Color.argb(80, 110, 145, 255));
        header.setBackground(hbg);
        int hp = dp(14);
        header.setPadding(hp, hp, hp, hp);
        LinearLayout.LayoutParams hlp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
        hlp.setMargins(dp(14), dp(2), dp(14), dp(10));
        header.setLayoutParams(hlp);

        LinearLayout topRow = new LinearLayout(this);
        topRow.setOrientation(LinearLayout.HORIZONTAL);
        topRow.setGravity(Gravity.CENTER_VERTICAL);

        LinearLayout clockCol = new LinearLayout(this);
        clockCol.setOrientation(LinearLayout.VERTICAL);
        clockCol.setLayoutParams(new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f));

        TextClock tc = new TextClock(this);
        tc.setFormat24Hour("HH:mm");
        tc.setFormat12Hour("HH:mm");
        tc.setTextColor(Color.WHITE);
        tc.setTextSize(TypedValue.COMPLEX_UNIT_SP, 30);
        tc.setTypeface(Typeface.DEFAULT_BOLD);
        clockCol.addView(tc);

        dateBadge = new TextView(this);
        dateBadge.setTextColor(Color.rgb(185, 198, 228));
        dateBadge.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        clockCol.addView(dateBadge);
        topRow.addView(clockCol);

        Button styleBtn = new Button(this);
        styleBtn.setText("Ikony ColorOS 17");
        styleBtn.setAllCaps(false);
        styleBtn.setTextColor(Color.WHITE);
        styleBtn.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        GradientDrawable sbg = new GradientDrawable(
                GradientDrawable.Orientation.LEFT_RIGHT,
                new int[]{Color.rgb(91, 60, 245), Color.rgb(0, 175, 225)});
        sbg.setCornerRadius(dp(14));
        styleBtn.setBackground(sbg);
        styleBtn.setPadding(dp(12), dp(6), dp(12), dp(6));
        styleBtn.setOnClickListener(v -> startActivity(new Intent(this, IconStyleActivity.class)));
        topRow.addView(styleBtn);
        header.addView(topRow);

        ramBadge = new TextView(this);
        ramBadge.setTextColor(Color.rgb(122, 236, 200));
        ramBadge.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
        ramBadge.setPadding(0, dp(6), 0, dp(8));
        header.addView(ramBadge);

        searchBox = new EditText(this);
        searchBox.setHint("Szukaj aplikacji w MysticalOS...");
        searchBox.setHintTextColor(Color.rgb(150, 162, 190));
        searchBox.setTextColor(Color.WHITE);
        searchBox.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        searchBox.setSingleLine(true);
        GradientDrawable eb = new GradientDrawable();
        eb.setColor(Color.argb(135, 12, 16, 30));
        eb.setCornerRadius(dp(12));
        eb.setStroke(dp(1), Color.argb(70, 255, 255, 255));
        searchBox.setBackground(eb);
        searchBox.setPadding(dp(12), dp(8), dp(12), dp(8));
        searchBox.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {
                queryText = s == null ? "" : s.toString().trim().toLowerCase(Locale.ROOT);
                renderGridAndDock();
            }
            @Override public void afterTextChanged(Editable s) {}
        });
        header.addView(searchBox);
        outer.addView(header);

        // Scrollable grid for icons and 1x2 / 2x1 / 2x2 ColorOS 17 Flux tiles
        ScrollView scroll = new ScrollView(this);
        scroll.setLayoutParams(new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f));
        scroll.setFillViewport(true);
        scroll.setOnLongClickListener(v -> {
            openQuickWallpaperOrIconMenu();
            return true;
        });

        appGrid = new GridLayout(this);
        appGrid.setPadding(dp(10), dp(4), dp(10), dp(12));
        appGrid.setOnLongClickListener(v -> {
            openQuickWallpaperOrIconMenu();
            return true;
        });
        scroll.addView(appGrid);
        outer.addView(scroll);

        // Bottom Dock
        dockRow = new LinearLayout(this);
        dockRow.setOrientation(LinearLayout.HORIZONTAL);
        dockRow.setGravity(Gravity.CENTER);
        GradientDrawable dbg = new GradientDrawable();
        dbg.setColor(Color.argb(190, 18, 22, 42));
        dbg.setCornerRadius(dp(24));
        dbg.setStroke(dp(1), Color.argb(75, 130, 160, 255));
        dockRow.setBackground(dbg);
        dockRow.setPadding(dp(10), dp(10), dp(10), dp(10));
        LinearLayout.LayoutParams dlp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
        dlp.setMargins(dp(14), dp(6), dp(14), dp(18));
        dockRow.setLayoutParams(dlp);
        outer.addView(dockRow);

        setContentView(outer);
        updateSystemHeader();
    }

    private int readBatteryPct() {
        try {
            BatteryManager bm = (BatteryManager) getSystemService(Context.BATTERY_SERVICE);
            if (bm != null) {
                int p = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY);
                if (p >= 0 && p <= 100) return p;
            }
        } catch (Throwable ignored) {}
        return 100;
    }

    private void updateSystemHeader() {
        String dateStr = new SimpleDateFormat("EEEE, d MMM", new Locale("pl", "PL")).format(new Date());
        if (dateBadge != null) {
            dateBadge.setText("MysticalOS 1.0 · " + dateStr);
        }
        String mem = readMemSummary();
        if (ramBadge != null) {
            ramBadge.setText(mem);
        }
        if (dynamicIslandPill != null) {
            boolean showIsland = LauncherPrefs.isDynamicIslandAlwaysOn(this);
            dynamicIslandPill.setVisibility(showIsland ? View.VISIBLE : View.GONE);
            int bat = readBatteryPct();
            if (islandTitle != null) {
                islandTitle.setText("● Dynamic Island · " + bat + "% · ColorOS 17 (" + LauncherPrefs.getIconScale(this) + "%)");
            }
            if (islandSub != null) {
                islandSub.setVisibility(islandExpanded ? View.VISIBLE : View.GONE);
                islandSub.setText(mem + " · Dotknij aby zwinac");
            }
        }
    }

    private String readMemSummary() {
        long totKb = 0;
        long availKb = 0;
        try (BufferedReader br = new BufferedReader(new FileReader("/proc/meminfo"))) {
            String line;
            while ((line = br.readLine()) != null) {
                if (line.startsWith("MemTotal:")) {
                    totKb = parseKb(line);
                } else if (line.startsWith("MemAvailable:")) {
                    availKb = parseKb(line);
                }
                if (totKb > 0 && availKb > 0) break;
            }
        } catch (Throwable ignored) {}
        if (totKb <= 0) {
            return "MysticalOS Flux17 · r9c-memd aktywny";
        }
        return String.format(Locale.US, "RAM %d/%d MiB · r9c-memd", availKb / 1024, totKb / 1024);
    }

    private static long parseKb(String line) {
        String[] parts = line.trim().split("\\s+");
        if (parts.length >= 2) {
            try {
                return Long.parseLong(parts[1]);
            } catch (NumberFormatException ignored) {}
        }
        return 0;
    }

    private void reloadAppsAndRender() {
        allApps = AppRepository.loadAllApps(this);
        renderGridAndDock();
    }

    private void renderGridAndDock() {
        if (appGrid == null) return;
        appGrid.removeAllViews();

        int cols = LauncherPrefs.getGridCols(this);
        int globalIconScale = LauncherPrefs.getIconScale(this);
        int labelScale = LauncherPrefs.getLabelScale(this);
        int shape = LauncherPrefs.getIconShape(this);
        boolean showLabels = LauncherPrefs.getShowLabels(this);

        appGrid.setColumnCount(cols);

        int screenW = getResources().getDisplayMetrics().widthPixels - dp(24);
        int cellW = Math.max(dp(64), screenW / cols);
        int baseIconDp = (cols == 5) ? 46 : 52;
        int baseGlobalIconPx = dp(Math.round(baseIconDp * globalIconScale / 100f));
        int unitH = Math.max(dp(92), baseGlobalIconPx + dp(38));

        List<AppRepository.AppEntry> filtered = new ArrayList<>();
        for (AppRepository.AppEntry e : allApps) {
            if (TextUtils.isEmpty(queryText) || e.label.toLowerCase(Locale.ROOT).contains(queryText)) {
                filtered.add(e);
            }
        }

        boolean[][] occupied = new boolean[140][cols];
        PackageManager pm = getPackageManager();

        for (AppRepository.AppEntry e : filtered) {
            int[] span = LauncherPrefs.getTileSpan(this, e.componentKey);
            int cSpan = Math.min(span[0], cols);
            int rSpan = span[1];
            int appScale = LauncherPrefs.getEffectiveIconScale(this, e.componentKey);
            int thisIconPx = dp(Math.round(baseIconDp * appScale / 100f));

            int[] pos = findFreeSlot(occupied, cols, cSpan, rSpan);
            int row = pos[0];
            int col = pos[1];
            markSlot(occupied, row, col, cSpan, rSpan);

            View tile = buildAppTile(e, pm, cSpan, rSpan, cellW, unitH, thisIconPx, appScale, shape, showLabels, labelScale);
            GridLayout.LayoutParams glp = new GridLayout.LayoutParams(
                    GridLayout.spec(row, rSpan),
                    GridLayout.spec(col, cSpan));
            glp.width = cellW * cSpan - dp(8);
            glp.height = unitH * rSpan - dp(8);
            glp.setMargins(dp(4), dp(4), dp(4), dp(4));
            tile.setLayoutParams(glp);
            appGrid.addView(tile);
        }

        renderDock(pm, baseGlobalIconPx, shape);
    }

    private int[] findFreeSlot(boolean[][] occ, int cols, int cSpan, int rSpan) {
        for (int r = 0; r + rSpan <= occ.length; r++) {
            for (int c = 0; c + cSpan <= cols; c++) {
                boolean free = true;
                for (int dr = 0; dr < rSpan && free; dr++) {
                    for (int dc = 0; dc < cSpan; dc++) {
                        if (occ[r + dr][c + dc]) {
                            free = false;
                            break;
                        }
                    }
                }
                if (free) return new int[]{r, c};
            }
        }
        return new int[]{0, 0};
    }

    private void markSlot(boolean[][] occ, int row, int col, int cSpan, int rSpan) {
        for (int dr = 0; dr < rSpan && row + dr < occ.length; dr++) {
            for (int dc = 0; dc < cSpan && col + dc < occ[0].length; dc++) {
                occ[row + dr][col + dc] = true;
            }
        }
    }

    private View buildAppTile(
            AppRepository.AppEntry e,
            PackageManager pm,
            int cSpan,
            int rSpan,
            int cellW,
            int unitH,
            int iconPx,
            int appScalePct,
            int shape,
            boolean showLabels,
            int labelScale) {

        boolean isLarge = (cSpan > 1 || rSpan > 1);
        Drawable rawIcon = e.resolveInfo.loadIcon(pm);

        if (isLarge) {
            ImageView cardView = new ImageView(this);
            cardView.setScaleType(ImageView.ScaleType.FIT_XY);
            int wPx = Math.max(160, cellW * cSpan - dp(8));
            int hPx = Math.max(160, unitH * rSpan - dp(8));
            Bitmap cardBmp = FluxIconRenderer.renderFluxTileCard(
                    this,
                    rawIcon,
                    e.label,
                    wPx,
                    hPx,
                    cSpan,
                    rSpan,
                    appScalePct,
                    shape,
                    LauncherPrefs.getCornerPct(this),
                    showLabels || isLarge,
                    LauncherPrefs.getWallpaperAccentColor(this));
            cardView.setImageBitmap(cardBmp);
            cardView.setOnClickListener(v -> launchEntry(e));
            cardView.setOnLongClickListener(v -> {
                showTileOptionsDialog(e);
                return true;
            });
            return cardView;
        }

        LinearLayout card = new LinearLayout(this);
        card.setGravity(Gravity.CENTER);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(2), dp(4), dp(2), dp(4));

        int maxTileIcon = Math.max(dp(32), Math.min(iconPx, unitH - dp(22)));
        ImageView iv = new ImageView(this);
        Bitmap bmp = FluxIconRenderer.renderAppIcon(this, rawIcon, Math.max(maxTileIcon, dp(72)), shape);
        iv.setImageBitmap(bmp);
        iv.setLayoutParams(new LinearLayout.LayoutParams(maxTileIcon, maxTileIcon));
        card.addView(iv);

        if (showLabels) {
            TextView tv = new TextView(this);
            tv.setText(e.label);
            tv.setTextColor(Color.WHITE);
            tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f * labelScale / 100f);
            tv.setMaxLines(1);
            tv.setEllipsize(TextUtils.TruncateAt.END);
            tv.setGravity(Gravity.CENTER_HORIZONTAL);
            tv.setPadding(dp(2), dp(4), dp(2), 0);
            card.addView(tv);
        }

        card.setOnClickListener(v -> launchEntry(e));
        card.setOnLongClickListener(v -> {
            showTileOptionsDialog(e);
            return true;
        });
        return card;
    }

    private void renderDock(PackageManager pm, int iconPx, int shape) {
        if (dockRow == null) return;
        dockRow.removeAllViews();

        List<AppRepository.AppEntry> dockApps = new ArrayList<>();
        String[] preferredHints = {"phone", "dialer", "messages", "sms", "mms", "camera", "droidify", "gallery"};
        for (String hint : preferredHints) {
            if (dockApps.size() >= 4) break;
            for (AppRepository.AppEntry e : allApps) {
                String low = (e.packageName + " " + e.label).toLowerCase(Locale.ROOT);
                if (low.contains(hint) && !dockApps.contains(e)) {
                    dockApps.add(e);
                    break;
                }
            }
        }
        for (AppRepository.AppEntry e : allApps) {
            if (dockApps.size() >= 4) break;
            if (!dockApps.contains(e)) {
                dockApps.add(e);
            }
        }

        int dockPx = Math.min(iconPx, dp(56));
        for (AppRepository.AppEntry e : dockApps) {
            LinearLayout slot = new LinearLayout(this);
            slot.setGravity(Gravity.CENTER);
            slot.setLayoutParams(new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f));
            ImageView iv = new ImageView(this);
            iv.setImageBitmap(FluxIconRenderer.renderAppIcon(this, e.resolveInfo.loadIcon(pm), Math.max(dockPx, dp(72)), shape));
            iv.setLayoutParams(new LinearLayout.LayoutParams(dockPx, dockPx));
            slot.addView(iv);
            slot.setOnClickListener(v -> launchEntry(e));
            slot.setOnLongClickListener(v -> {
                showTileOptionsDialog(e);
                return true;
            });
            dockRow.addView(slot);
        }
    }

    private void launchEntry(AppRepository.AppEntry e) {
        try {
            LauncherPrefs.recordLaunch(this, e.componentKey);
            Intent i = new Intent(Intent.ACTION_MAIN);
            i.addCategory(Intent.CATEGORY_LAUNCHER);
            i.setComponent(new ComponentName(e.packageName, e.className));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
            startActivity(i);
        } catch (Throwable t) {
            Toast.makeText(this, "Nie mozna otworzyc " + e.label, Toast.LENGTH_SHORT).show();
        }
    }

    private void showTileOptionsDialog(final AppRepository.AppEntry e) {
        LinearLayout customBox = new LinearLayout(this);
        customBox.setOrientation(LinearLayout.VERTICAL);
        customBox.setPadding(dp(18), dp(12), dp(18), dp(6));

        final TextView scaleTxt = new TextView(this);
        int curScale = LauncherPrefs.getEffectiveIconScale(this, e.componentKey);
        scaleTxt.setText("Indywidualny rozmiar ikony: " + curScale + "%");
        scaleTxt.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        customBox.addView(scaleTxt);

        SeekBar appSeek = new SeekBar(this);
        appSeek.setMax(90); // 60..150
        appSeek.setProgress(curScale - 60);
        appSeek.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar sb, int progress, boolean fromUser) {
                int pct = 60 + progress;
                LauncherPrefs.setAppIconScale(MysticalHomeActivity.this, e.componentKey, pct);
                scaleTxt.setText("Indywidualny rozmiar ikony: " + pct + "%");
                renderGridAndDock();
            }
            @Override public void onStartTrackingTouch(SeekBar sb) {}
            @Override public void onStopTrackingTouch(SeekBar sb) {}
        });
        customBox.addView(appSeek);

        String cur = LauncherPrefs.getTileSpanTag(this, e.componentKey);
        String[] items = {
                (cur.equals("1x1") ? "[x] " : "") + "Rozmiar kafelka: 1x1 (Standard)",
                (cur.equals("2x1") ? "[x] " : "") + "Rozmiar kafelka: 2x1 (Szeroka kapsula)",
                (cur.equals("1x2") ? "[x] " : "") + "Rozmiar kafelka: 1x2 (Wysoka karta)",
                (cur.equals("2x2") ? "[x] " : "") + "Rozmiar kafelka: 2x2 (Duzy kafelek ColorOS 17)",
                "Uzyj rozmiaru globalnego (reset tej ikony)",
                "Rozmiar i ksztalt wszystkich ikon ColorOS 17...",
                "Informacje o aplikacji",
                "Odinstaluj"
        };
        new AlertDialog.Builder(this)
                .setTitle(e.label + " · ColorOS 17")
                .setView(customBox)
                .setItems(items, (dlg, which) -> {
                    if (which == 0) {
                        LauncherPrefs.setTileSpan(this, e.componentKey, "1x1");
                        renderGridAndDock();
                    } else if (which == 1) {
                        LauncherPrefs.setTileSpan(this, e.componentKey, "2x1");
                        renderGridAndDock();
                    } else if (which == 2) {
                        LauncherPrefs.setTileSpan(this, e.componentKey, "1x2");
                        renderGridAndDock();
                    } else if (which == 3) {
                        LauncherPrefs.setTileSpan(this, e.componentKey, "2x2");
                        renderGridAndDock();
                    } else if (which == 4) {
                        LauncherPrefs.setAppIconScale(this, e.componentKey, 0);
                        LauncherPrefs.setTileSpan(this, e.componentKey, "1x1");
                        renderGridAndDock();
                    } else if (which == 5) {
                        startActivity(new Intent(this, IconStyleActivity.class));
                    } else if (which == 6) {
                        Intent info = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
                        info.setData(Uri.parse("package:" + e.packageName));
                        info.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(info);
                    } else if (which == 7) {
                        Intent del = new Intent(Intent.ACTION_DELETE, Uri.parse("package:" + e.packageName));
                        del.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(del);
                    }
                })
                .show();
    }

    private void openQuickWallpaperOrIconMenu() {
        String[] opts = {
                "Ikony i rozmiar (ColorOS 17 Style)...",
                "Dodaj kafelek widgetowy ColorOS 17...",
                "Ustaw domyslny Launcher (Home)...",
                "Odswiez liste aplikacji"
        };
        new AlertDialog.Builder(this)
                .setTitle("MysticalOS Launcher")
                .setItems(opts, (d, w) -> {
                    if (w == 0) {
                        startActivity(new Intent(this, IconStyleActivity.class));
                    } else if (w == 1) {
                        startActivity(new Intent(this, ColorOsTileConfigActivity.class));
                    } else if (w == 2) {
                        startActivity(new Intent(Settings.ACTION_HOME_SETTINGS));
                    } else if (w == 3) {
                        reloadAppsAndRender();
                    }
                })
                .show();
    }

    private int dp(float v) {
        return FluxIconRenderer.dpToPx(this, v);
    }
}
