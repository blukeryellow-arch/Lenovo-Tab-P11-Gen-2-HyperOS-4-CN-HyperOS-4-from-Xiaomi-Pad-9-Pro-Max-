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
    private LinearLayout searchBarContainer;
    private LinearLayout searchPillBtn;
    private LinearLayout editModeBar;
    private TextView islandTitle;
    private TextView islandSub;
    private TextView islandActionLink;
    private TextView dateBadge;
    private TextView weatherBadge;
    private EditText searchBox;
    private String queryText = "";
    private boolean islandExpanded = false;
    private boolean searchOpen = false;
    private boolean editBarOpen = false;

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
        getWindow().setNavigationBarColor(Color.TRANSPARENT);

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
        if (editBarOpen) {
            editBarOpen = false;
            updateEditModeBar();
            return;
        }
        if (searchOpen || !TextUtils.isEmpty(queryText)) {
            searchOpen = false;
            queryText = "";
            if (searchBox != null) searchBox.setText("");
            updateSearchBarVisibility();
            renderGridAndDock();
        }
    }

    private void buildUi() {
        LinearLayout outer = new LinearLayout(this);
        outer.setOrientation(LinearLayout.VERTICAL);
        outer.setBackgroundColor(Color.TRANSPARENT);
        outer.setOnLongClickListener(v -> {
            toggleEditModeBar();
            return true;
        });

        // 1. Always-On HyperOS 4 Super Island (Dynamic Island) pill at top center
        dynamicIslandPill = new LinearLayout(this);
        dynamicIslandPill.setOrientation(LinearLayout.VERTICAL);
        dynamicIslandPill.setGravity(Gravity.CENTER_HORIZONTAL);
        GradientDrawable ibg = new GradientDrawable();
        ibg.setColor(Color.argb(245, 9, 10, 14));
        ibg.setCornerRadius(dp(22));
        ibg.setStroke(dp(1), Color.argb(65, 255, 255, 255));
        dynamicIslandPill.setBackground(ibg);
        dynamicIslandPill.setPadding(dp(16), dp(6), dp(16), dp(6));
        LinearLayout.LayoutParams ilp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        ilp.gravity = Gravity.CENTER_HORIZONTAL;
        ilp.setMargins(dp(16), dp(10), dp(16), dp(6));
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
        islandSub.setTextColor(Color.rgb(164, 232, 255));
        islandSub.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
        islandSub.setPadding(0, dp(4), 0, 0);
        islandSub.setVisibility(View.GONE);
        dynamicIslandPill.addView(islandSub);

        islandActionLink = new TextView(this);
        islandActionLink.setText("Styl ikon ColorOS 17 >");
        islandActionLink.setTextColor(Color.rgb(98, 224, 255));
        islandActionLink.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
        islandActionLink.setTypeface(Typeface.DEFAULT_BOLD);
        islandActionLink.setPadding(0, dp(4), 0, dp(2));
        islandActionLink.setVisibility(View.GONE);
        islandActionLink.setOnClickListener(v -> startActivity(new Intent(this, IconStyleActivity.class)));
        dynamicIslandPill.addView(islandActionLink);

        outer.addView(dynamicIslandPill);

        // 2. Clean, borderless HyperOS 4 Clock & Weather Widget (no heavy dark RAM card!)
        LinearLayout clockWeatherRow = new LinearLayout(this);
        clockWeatherRow.setOrientation(LinearLayout.HORIZONTAL);
        clockWeatherRow.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout.LayoutParams cwlp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
        cwlp.setMargins(dp(20), dp(6), dp(20), dp(10));
        clockWeatherRow.setLayoutParams(cwlp);
        clockWeatherRow.setOnLongClickListener(v -> {
            toggleEditModeBar();
            return true;
        });

        LinearLayout clockCol = new LinearLayout(this);
        clockCol.setOrientation(LinearLayout.VERTICAL);
        clockCol.setLayoutParams(new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f));

        TextClock tc = new TextClock(this);
        tc.setFormat24Hour("HH:mm");
        tc.setFormat12Hour("HH:mm");
        tc.setTextColor(Color.WHITE);
        tc.setTextSize(TypedValue.COMPLEX_UNIT_SP, 44);
        tc.setTypeface(Typeface.create("sans-serif-light", Typeface.NORMAL));
        tc.setShadowLayer(dp(4), 0, dp(2), Color.argb(120, 0, 0, 0));
        clockCol.addView(tc);

        dateBadge = new TextView(this);
        dateBadge.setTextColor(Color.argb(235, 255, 255, 255));
        dateBadge.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        dateBadge.setShadowLayer(dp(3), 0, dp(1), Color.argb(120, 0, 0, 0));
        clockCol.addView(dateBadge);
        clockWeatherRow.addView(clockCol);

        weatherBadge = new TextView(this);
        weatherBadge.setText("18°C\nSlonecznie");
        weatherBadge.setGravity(Gravity.END);
        weatherBadge.setTextColor(Color.WHITE);
        weatherBadge.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        weatherBadge.setTypeface(Typeface.DEFAULT_BOLD);
        weatherBadge.setShadowLayer(dp(3), 0, dp(1), Color.argb(120, 0, 0, 0));
        clockWeatherRow.addView(weatherBadge);

        outer.addView(clockWeatherRow);

        // Expandable live search box (hidden until user taps HyperOS 4 Search Pill above dock)
        searchBarContainer = new LinearLayout(this);
        searchBarContainer.setOrientation(LinearLayout.HORIZONTAL);
        searchBarContainer.setVisibility(View.GONE);
        LinearLayout.LayoutParams sblp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        sblp.setMargins(dp(18), dp(2), dp(18), dp(6));
        searchBarContainer.setLayoutParams(sblp);

        searchBox = new EditText(this);
        searchBox.setHint("Szukaj aplikacji...");
        searchBox.setHintTextColor(Color.argb(200, 235, 242, 255));
        searchBox.setTextColor(Color.WHITE);
        searchBox.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        searchBox.setSingleLine(true);
        GradientDrawable eb = new GradientDrawable();
        eb.setColor(Color.argb(150, 18, 28, 52));
        eb.setCornerRadius(dp(18));
        eb.setStroke(dp(1), Color.argb(110, 255, 255, 255));
        searchBox.setBackground(eb);
        searchBox.setPadding(dp(14), dp(9), dp(14), dp(9));
        searchBox.setLayoutParams(new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f));
        searchBox.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {
                queryText = s == null ? "" : s.toString().trim().toLowerCase(Locale.ROOT);
                renderGridAndDock();
            }
            @Override public void afterTextChanged(Editable s) {}
        });
        searchBarContainer.addView(searchBox);
        outer.addView(searchBarContainer);

        // 3. Scrollable HyperOS 4 grid + ColorOS 17 resizeable tiles
        ScrollView scroll = new ScrollView(this);
        scroll.setLayoutParams(new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f));
        scroll.setFillViewport(true);
        scroll.setOnLongClickListener(v -> {
            toggleEditModeBar();
            return true;
        });

        appGrid = new GridLayout(this);
        appGrid.setPadding(dp(12), dp(2), dp(12), dp(8));
        appGrid.setOnLongClickListener(v -> {
            toggleEditModeBar();
            return true;
        });
        scroll.addView(appGrid);
        outer.addView(scroll);

        // 4. HyperOS 4 bottom page dots + frosted Search Pill above Dock
        searchPillBtn = new LinearLayout(this);
        searchPillBtn.setOrientation(LinearLayout.HORIZONTAL);
        searchPillBtn.setGravity(Gravity.CENTER);
        GradientDrawable spBg = new GradientDrawable();
        spBg.setColor(Color.argb(95, 255, 255, 255));
        spBg.setCornerRadius(dp(16));
        spBg.setStroke(dp(1), Color.argb(110, 255, 255, 255));
        searchPillBtn.setBackground(spBg);
        searchPillBtn.setPadding(dp(18), dp(6), dp(18), dp(6));
        LinearLayout.LayoutParams splp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        splp.gravity = Gravity.CENTER_HORIZONTAL;
        splp.setMargins(0, dp(4), 0, dp(6));
        searchPillBtn.setLayoutParams(splp);

        TextView spTxt = new TextView(this);
        spTxt.setText("Szukaj");
        spTxt.setTextColor(Color.WHITE);
        spTxt.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        spTxt.setShadowLayer(dp(2), 0, dp(1), Color.argb(90, 0, 0, 0));
        searchPillBtn.addView(spTxt);
        searchPillBtn.setOnClickListener(v -> {
            searchOpen = !searchOpen;
            if (!searchOpen && searchBox != null) searchBox.setText("");
            updateSearchBarVisibility();
        });
        outer.addView(searchPillBtn);

        // 5. HyperOS 4 Home Edit Mode toolbar (shown on long press)
        editModeBar = new LinearLayout(this);
        editModeBar.setOrientation(LinearLayout.HORIZONTAL);
        editModeBar.setGravity(Gravity.CENTER);
        editModeBar.setVisibility(View.GONE);
        GradientDrawable emBg = new GradientDrawable();
        emBg.setColor(Color.argb(215, 245, 248, 255));
        emBg.setCornerRadius(dp(22));
        editModeBar.setBackground(emBg);
        editModeBar.setPadding(dp(8), dp(8), dp(8), dp(8));
        LinearLayout.LayoutParams emlp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        emlp.setMargins(dp(14), dp(2), dp(14), dp(6));
        editModeBar.setLayoutParams(emlp);

        editModeBar.addView(makeEditAction("Tapety", v -> cycleHyperOsWallpaper()));
        editModeBar.addView(makeEditAction("Widzety", v -> startActivity(new Intent(this, ColorOsTileConfigActivity.class))));
        editModeBar.addView(makeEditAction("Ikony", v -> startActivity(new Intent(this, IconStyleActivity.class))));
        editModeBar.addView(makeEditAction("Ustaw.", v -> openQuickWallpaperOrIconMenu()));
        outer.addView(editModeBar);

        // 6. HyperOS 4 Frosted Glass Pill Dock (no text labels, clean glass frame)
        dockRow = new LinearLayout(this);
        dockRow.setOrientation(LinearLayout.HORIZONTAL);
        dockRow.setGravity(Gravity.CENTER);
        GradientDrawable dbg = new GradientDrawable();
        dbg.setColor(Color.argb(85, 255, 255, 255));
        dbg.setCornerRadius(dp(26));
        dbg.setStroke(dp(1), Color.argb(125, 255, 255, 255));
        dockRow.setBackground(dbg);
        dockRow.setPadding(dp(10), dp(10), dp(10), dp(10));
        LinearLayout.LayoutParams dlp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
        dlp.setMargins(dp(14), dp(2), dp(14), dp(16));
        dockRow.setLayoutParams(dlp);
        outer.addView(dockRow);

        setContentView(outer);
        updateSystemHeader();
    }

    private Button makeEditAction(String label, View.OnClickListener click) {
        Button b = new Button(this);
        b.setText(label);
        b.setAllCaps(false);
        b.setTextColor(Color.rgb(24, 34, 60));
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        b.setTypeface(Typeface.DEFAULT_BOLD);
        b.setBackgroundColor(Color.TRANSPARENT);
        b.setLayoutParams(new LinearLayout.LayoutParams(0, dp(36), 1f));
        b.setOnClickListener(click);
        return b;
    }

    private void toggleEditModeBar() {
        editBarOpen = !editBarOpen;
        updateEditModeBar();
    }

    private void updateEditModeBar() {
        if (editModeBar != null) {
            editModeBar.setVisibility(editBarOpen ? View.VISIBLE : View.GONE);
        }
    }

    private void updateSearchBarVisibility() {
        if (searchBarContainer != null) {
            searchBarContainer.setVisibility(searchOpen ? View.VISIBLE : View.GONE);
            if (searchOpen && searchBox != null) searchBox.requestFocus();
        }
    }

    private void cycleHyperOsWallpaper() {
        int next = (LauncherPrefs.getWallpaperIndex(this) + 1) % 6;
        LauncherPrefs.setWallpaperIndex(this, next);
        boolean ok = LauncherPrefs.applyWallpaperBitmap(this, next);
        Toast.makeText(this, "Tapeta: " + LauncherPrefs.wallpaperName(next) + (ok ? "" : " (podglad)"), Toast.LENGTH_SHORT).show();
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
            dateBadge.setText(dateStr);
        }
        String mem = readMemSummary();
        if (dynamicIslandPill != null) {
            boolean showIsland = LauncherPrefs.isDynamicIslandAlwaysOn(this);
            dynamicIslandPill.setVisibility(showIsland ? View.VISIBLE : View.GONE);
            int bat = readBatteryPct();
            if (islandTitle != null) {
                islandTitle.setText("●  HyperIsland · " + bat + "%");
            }
            if (islandSub != null) {
                islandSub.setVisibility(islandExpanded ? View.VISIBLE : View.GONE);
                islandSub.setText(mem + " · Ikony " + LauncherPrefs.getIconScale(this) + "%");
            }
            if (islandActionLink != null) {
                islandActionLink.setVisibility(islandExpanded ? View.VISIBLE : View.GONE);
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
            return "Dynamic Island Always-On · r9c-memd";
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
        int baseIconDp = (cols == 5) ? 48 : 54;
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
            tv.setShadowLayer(dp(3), 0, dp(1), Color.argb(135, 0, 0, 0));
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
                .setTitle(e.label + " · HyperOS 4 / ColorOS 17")
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
                "Zmien tapete HyperOS 4 (" + LauncherPrefs.wallpaperName(LauncherPrefs.getWallpaperIndex(this)) + ")",
                "Dodaj kafelek widgetowy ColorOS 17...",
                "Ustaw domyslny Launcher (Home)...",
                "Odswiez liste aplikacji"
        };
        new AlertDialog.Builder(this)
                .setTitle("HyperOS 4 Launcher · MysticalOS")
                .setItems(opts, (d, w) -> {
                    if (w == 0) {
                        startActivity(new Intent(this, IconStyleActivity.class));
                    } else if (w == 1) {
                        cycleHyperOsWallpaper();
                    } else if (w == 2) {
                        startActivity(new Intent(this, ColorOsTileConfigActivity.class));
                    } else if (w == 3) {
                        startActivity(new Intent(Settings.ACTION_HOME_SETTINGS));
                    } else if (w == 4) {
                        reloadAppsAndRender();
                    }
                })
                .show();
    }

    private int dp(float v) {
        return FluxIconRenderer.dpToPx(this, v);
    }
}
