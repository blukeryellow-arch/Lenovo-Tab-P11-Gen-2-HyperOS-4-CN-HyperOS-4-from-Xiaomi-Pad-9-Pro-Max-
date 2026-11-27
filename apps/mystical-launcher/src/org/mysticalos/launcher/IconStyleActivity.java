package org.mysticalos.launcher;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import java.util.ArrayList;
import java.util.List;

public class IconStyleActivity extends Activity {
    private LinearLayout previewRow;
    private ImageView tilePreviewView;
    private TextView sizeValText;
    private TextView cornerValText;
    private TextView labelValText;
    private final List<Drawable> sampleDrawables = new ArrayList<>();
    private final List<String> sampleLabels = new ArrayList<>();
    private List<AppRepository.AppEntry> allApps = new ArrayList<>();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);

        allApps = AppRepository.loadAllApps(this);
        loadSamples();

        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(Color.rgb(11, 13, 24));

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int p = dp(18);
        root.setPadding(p, dp(34), p, dp(28));
        scroll.addView(root);

        TextView title = new TextView(this);
        title.setText("Ikony ColorOS 17 · HyperOS 4 Studio");
        title.setTextColor(Color.WHITE);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 21);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        root.addView(title);

        TextView sub = new TextView(this);
        sub.setText("Zmieniaj globalny oraz indywidualny rozmiar ikon (60%–150%, kafelki 1x1 / 2x1 / 1x2 / 2x2) oraz konfiguruj Dynamic Island.");
        sub.setTextColor(Color.rgb(168, 178, 206));
        sub.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        sub.setPadding(0, dp(4), 0, dp(14));
        root.addView(sub);

        // Quick actions for HyperOS 4 + ColorOS 17 desktop tiles
        LinearLayout quickCard = makeCard();
        quickCard.addView(makeSectionTitle("Szybkie akcje na pulpicie HyperOS 4"));

        Button addTileBtn = makeAccentButton("Przypnij duzy kafelek aplikacji (1x1 / 2x1 / 1x2 / 2x2)");
        addTileBtn.setOnClickListener(v -> startActivity(new Intent(this, ColorOsTileConfigActivity.class)));
        LinearLayout.LayoutParams qlp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(44));
        qlp.setMargins(0, dp(10), 0, dp(8));
        addTileBtn.setLayoutParams(qlp);
        quickCard.addView(addTileBtn);

        LinearLayout qRow = new LinearLayout(this);
        qRow.setOrientation(LinearLayout.HORIZONTAL);
        Button hyperBtn = makePillButton("Ustawienia ikon HyperOS 4");
        hyperBtn.setLayoutParams(new LinearLayout.LayoutParams(0, dp(40), 1f));
        hyperBtn.setOnClickListener(v -> openHyperOsIconSettings());

        Button perAppBtn = makePillButton("Rozmiar per aplikacja");
        LinearLayout.LayoutParams plp = new LinearLayout.LayoutParams(0, dp(40), 1f);
        plp.setMargins(dp(8), 0, 0, 0);
        perAppBtn.setLayoutParams(plp);
        perAppBtn.setOnClickListener(v -> openPerAppResizePicker());

        qRow.addView(hyperBtn);
        qRow.addView(perAppBtn);
        quickCard.addView(qRow);
        root.addView(quickCard);

        // Live preview card
        LinearLayout previewBox = makeCard();
        previewBox.setGravity(Gravity.CENTER_HORIZONTAL);
        TextView prevLbl = new TextView(this);
        prevLbl.setText("PODGLAD NA ZYWO (IKONY + KAFELEK 2x1)");
        prevLbl.setTextColor(Color.rgb(0, 218, 255));
        prevLbl.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
        prevLbl.setTypeface(Typeface.DEFAULT_BOLD);
        prevLbl.setPadding(0, 0, 0, dp(10));
        previewBox.addView(prevLbl);

        previewRow = new LinearLayout(this);
        previewRow.setOrientation(LinearLayout.HORIZONTAL);
        previewRow.setGravity(Gravity.CENTER);
        previewRow.setMinimumHeight(dp(106));
        previewBox.addView(previewRow);

        tilePreviewView = new ImageView(this);
        LinearLayout.LayoutParams tlp = new LinearLayout.LayoutParams(dp(220), dp(108));
        tlp.setMargins(0, dp(10), 0, 0);
        tilePreviewView.setLayoutParams(tlp);
        tilePreviewView.setScaleType(ImageView.ScaleType.FIT_CENTER);
        previewBox.addView(tilePreviewView);
        root.addView(previewBox);

        // Icon scale + corner radius sliders
        LinearLayout sizeCard = makeCard();
        LinearLayout sizeHdr = new LinearLayout(this);
        sizeHdr.setOrientation(LinearLayout.HORIZONTAL);
        TextView sizeTitle = makeSectionTitle("Rozmiar ikon aplikacji");
        sizeTitle.setLayoutParams(new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f));
        sizeValText = new TextView(this);
        sizeValText.setTextColor(Color.rgb(0, 218, 255));
        sizeValText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        sizeValText.setTypeface(Typeface.DEFAULT_BOLD);
        sizeHdr.addView(sizeTitle);
        sizeHdr.addView(sizeValText);
        sizeCard.addView(sizeHdr);

        final SeekBar sizeSeek = new SeekBar(this);
        sizeSeek.setMax(90); // 60..150
        sizeSeek.setProgress(LauncherPrefs.getIconScale(this) - 60);
        sizeSeek.setPadding(0, dp(8), 0, dp(10));
        sizeSeek.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar sb, int progress, boolean fromUser) {
                LauncherPrefs.setIconScale(IconStyleActivity.this, 60 + progress);
                refreshPreview();
            }
            @Override public void onStartTrackingTouch(SeekBar sb) {}
            @Override public void onStopTrackingTouch(SeekBar sb) {}
        });
        sizeCard.addView(sizeSeek);

        LinearLayout cornerHdr = new LinearLayout(this);
        cornerHdr.setOrientation(LinearLayout.HORIZONTAL);
        TextView cornerTitle = makeSectionTitle("Zaokraglenie naroznikow (tryb Wlasny)");
        cornerTitle.setLayoutParams(new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f));
        cornerValText = new TextView(this);
        cornerValText.setTextColor(Color.rgb(0, 218, 255));
        cornerValText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        cornerValText.setTypeface(Typeface.DEFAULT_BOLD);
        cornerHdr.addView(cornerTitle);
        cornerHdr.addView(cornerValText);
        sizeCard.addView(cornerHdr);

        final SeekBar cornerSeek = new SeekBar(this);
        cornerSeek.setMax(100);
        cornerSeek.setProgress(LauncherPrefs.getCornerPct(this));
        cornerSeek.setPadding(0, dp(8), 0, dp(4));
        cornerSeek.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar sb, int progress, boolean fromUser) {
                LauncherPrefs.setCornerPct(IconStyleActivity.this, progress);
                if (fromUser && LauncherPrefs.getIconShape(IconStyleActivity.this) != LauncherPrefs.SHAPE_CUSTOM) {
                    LauncherPrefs.setIconShape(IconStyleActivity.this, LauncherPrefs.SHAPE_CUSTOM);
                }
                refreshPreview();
            }
            @Override public void onStartTrackingTouch(SeekBar sb) {}
            @Override public void onStopTrackingTouch(SeekBar sb) {}
        });
        sizeCard.addView(cornerSeek);
        root.addView(sizeCard);

        // Shape selector (all 6 shapes)
        LinearLayout shapeCard = makeCard();
        shapeCard.addView(makeSectionTitle("Ksztalt ikon (ColorOS 17 & HyperOS 4)"));
        final String[] shapeNames = {"Squircle", "HyperOS", "Pebble", "Kolo", "Kwadrat", "Wlasny"};
        final Button[] shapeBtns = new Button[6];
        for (int row = 0; row < 2; row++) {
            LinearLayout shapeRow = new LinearLayout(this);
            shapeRow.setOrientation(LinearLayout.HORIZONTAL);
            shapeRow.setPadding(0, dp(8), 0, 0);
            for (int col = 0; col < 3; col++) {
                final int sIdx = row * 3 + col;
                Button b = makePillButton(shapeNames[sIdx]);
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, dp(38), 1f);
                lp.setMargins(col == 0 ? 0 : dp(6), 0, 0, 0);
                b.setLayoutParams(lp);
                b.setOnClickListener(v -> {
                    LauncherPrefs.setIconShape(this, sIdx);
                    updateButtons(shapeBtns, sIdx);
                    refreshPreview();
                });
                shapeBtns[sIdx] = b;
                shapeRow.addView(b);
            }
            shapeCard.addView(shapeRow);
        }
        updateButtons(shapeBtns, LauncherPrefs.getIconShape(this));

        // Monet & Shadow toggles
        final Switch monetSw = addToggleRow(shapeCard, "Kolorystyka Monet (akcent tapety)", LauncherPrefs.getMonetTint(this), checked -> {
            LauncherPrefs.setMonetTint(this, checked);
            refreshPreview();
        });
        final Switch shadowSw = addToggleRow(shapeCard, "Miekki cien pod ikonami Flux", LauncherPrefs.getIconShadow(this), checked -> {
            LauncherPrefs.setIconShadow(this, checked);
            refreshPreview();
        });
        addToggleRow(shapeCard, "Dynamic Island: Zawsze wlaczony", LauncherPrefs.isDynamicIslandAlwaysOn(this), checked -> {
            LauncherPrefs.setDynamicIslandAlwaysOn(this, checked);
            Toast.makeText(this, checked ? "Dynamic Island: ZAWSZE WLACZONY" : "Dynamic Island: automatyczny", Toast.LENGTH_SHORT).show();
        });
        root.addView(shapeCard);

        // Labels + Label Size + Grid Columns
        LinearLayout layoutCard = makeCard();
        layoutCard.addView(makeSectionTitle("Siatka pulpitu i podpisy"));

        final Switch showSw = addToggleRow(layoutCard, "Pokazuj nazwy aplikacji", LauncherPrefs.getShowLabels(this), checked -> {
            LauncherPrefs.setShowLabels(this, checked);
            refreshPreview();
        });

        LinearLayout lblHdr = new LinearLayout(this);
        lblHdr.setOrientation(LinearLayout.HORIZONTAL);
        lblHdr.setPadding(0, dp(6), 0, 0);
        TextView lblTitle = new TextView(this);
        lblTitle.setText("Rozmiar podpisow");
        lblTitle.setTextColor(Color.rgb(200, 210, 232));
        lblTitle.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        lblTitle.setLayoutParams(new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f));
        labelValText = new TextView(this);
        labelValText.setTextColor(Color.rgb(0, 218, 255));
        labelValText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        lblHdr.addView(lblTitle);
        lblHdr.addView(labelValText);
        layoutCard.addView(lblHdr);

        final SeekBar lblSeek = new SeekBar(this);
        lblSeek.setMax(45); // 80..125
        lblSeek.setProgress(LauncherPrefs.getLabelScale(this) - 80);
        lblSeek.setPadding(0, dp(6), 0, dp(12));
        lblSeek.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar sb, int progress, boolean fromUser) {
                LauncherPrefs.setLabelScale(IconStyleActivity.this, 80 + progress);
                refreshPreview();
            }
            @Override public void onStartTrackingTouch(SeekBar sb) {}
            @Override public void onStopTrackingTouch(SeekBar sb) {}
        });
        layoutCard.addView(lblSeek);

        LinearLayout colRow = new LinearLayout(this);
        colRow.setOrientation(LinearLayout.HORIZONTAL);
        final Button b4 = makePillButton("Siatka 4 kolumny");
        final Button b5 = makePillButton("Siatka 5 kolumn");
        LinearLayout.LayoutParams lp4 = new LinearLayout.LayoutParams(0, dp(38), 1f);
        lp4.setMargins(0, 0, dp(6), 0);
        b4.setLayoutParams(lp4);
        b5.setLayoutParams(new LinearLayout.LayoutParams(0, dp(38), 1f));
        final Button[] colBtns = {b4, b5};
        b4.setOnClickListener(v -> {
            LauncherPrefs.setGridCols(this, 4);
            updateButtons(colBtns, 0);
        });
        b5.setOnClickListener(v -> {
            LauncherPrefs.setGridCols(this, 5);
            updateButtons(colBtns, 1);
        });
        updateButtons(colBtns, LauncherPrefs.getGridCols(this) == 5 ? 1 : 0);
        colRow.addView(b4);
        colRow.addView(b5);
        layoutCard.addView(colRow);
        root.addView(layoutCard);

        // Wallpaper selector (6 Flux themes)
        LinearLayout wallCard = makeCard();
        wallCard.addView(makeSectionTitle("Tapeta MysticalOS Flux"));
        for (int r = 0; r < 2; r++) {
            LinearLayout wallRow = new LinearLayout(this);
            wallRow.setOrientation(LinearLayout.HORIZONTAL);
            wallRow.setPadding(0, dp(8), 0, 0);
            for (int c = 0; c < 3; c++) {
                final int wIdx = r * 3 + c;
                Button wb = makePillButton(LauncherPrefs.wallpaperName(wIdx));
                int[] cols = LauncherPrefs.wallpaperColors(wIdx);
                GradientDrawable gd = new GradientDrawable(
                        GradientDrawable.Orientation.TL_BR, new int[]{cols[1], cols[2]});
                gd.setCornerRadius(dp(10));
                wb.setBackground(gd);
                wb.setTextColor(Color.WHITE);
                LinearLayout.LayoutParams wlp = new LinearLayout.LayoutParams(0, dp(42), 1f);
                wlp.setMargins(c == 0 ? 0 : dp(6), 0, 0, 0);
                wb.setLayoutParams(wlp);
                wb.setOnClickListener(v -> {
                    LauncherPrefs.setWallpaperIndex(this, wIdx);
                    boolean ok = LauncherPrefs.applyWallpaperBitmap(this, wIdx);
                    refreshPreview();
                    Toast.makeText(
                            this,
                            ok ? "Ustawiono tapete: " + LauncherPrefs.wallpaperName(wIdx) : "Zmieniono styl akcentu",
                            Toast.LENGTH_SHORT).show();
                });
                wallRow.addView(wb);
            }
            wallCard.addView(wallRow);
        }
        root.addView(wallCard);

        // Actions
        LinearLayout actRow = new LinearLayout(this);
        actRow.setOrientation(LinearLayout.HORIZONTAL);
        actRow.setPadding(0, dp(6), 0, 0);

        Button resetBtn = makePillButton("Reset domyslny");
        resetBtn.setLayoutParams(new LinearLayout.LayoutParams(0, dp(46), 1f));
        resetBtn.setOnClickListener(v -> {
            LauncherPrefs.resetAllLayout(this);
            sizeSeek.setProgress(LauncherPrefs.getIconScale(this) - 60);
            cornerSeek.setProgress(LauncherPrefs.getCornerPct(this));
            lblSeek.setProgress(LauncherPrefs.getLabelScale(this) - 80);
            showSw.setChecked(true);
            monetSw.setChecked(false);
            shadowSw.setChecked(true);
            updateButtons(shapeBtns, LauncherPrefs.getIconShape(this));
            refreshPreview();
            Toast.makeText(this, "Przywrocono domyslny uklad ColorOS 17", Toast.LENGTH_SHORT).show();
        });

        Button doneBtn = makeAccentButton("Zastosuj i zamknij");
        LinearLayout.LayoutParams dlp = new LinearLayout.LayoutParams(0, dp(46), 1f);
        dlp.setMargins(dp(10), 0, 0, 0);
        doneBtn.setLayoutParams(dlp);
        doneBtn.setOnClickListener(v -> finish());

        actRow.addView(resetBtn);
        actRow.addView(doneBtn);
        root.addView(actRow);

        setContentView(scroll);
        refreshPreview();
    }

    private void openHyperOsIconSettings() {
        Intent[] candidates = new Intent[]{
                new Intent().setComponent(new ComponentName("com.miui.home", "com.miui.home.settings.IconCustomizeActivity")),
                new Intent("com.miui.home.action.ICON_CUSTOMIZE"),
        };
        for (Intent it : candidates) {
            try {
                if (getPackageManager().resolveActivity(it, 0) != null) {
                    startActivity(it);
                    return;
                }
            } catch (Throwable ignored) {}
        }
        Toast.makeText(
                this,
                "Natywny modul IconCustomize HyperOS 4 dostepny po wgraniu pelnego ROM-u MysticalOS 1.0.",
                Toast.LENGTH_LONG).show();
    }

    private void openPerAppResizePicker() {
        if (allApps.isEmpty()) {
            allApps = AppRepository.loadAllApps(this);
        }
        if (allApps.isEmpty()) return;

        final String[] names = new String[allApps.size()];
        for (int i = 0; i < allApps.size(); i++) {
            AppRepository.AppEntry e = allApps.get(i);
            String span = LauncherPrefs.getTileSpanTag(this, e.componentKey);
            int customScale = LauncherPrefs.getAppIconScale(this, e.componentKey);
            names[i] = e.label + "  [" + span + (customScale > 0 ? ", " + customScale + "%" : "") + "]";
        }
        new AlertDialog.Builder(this)
                .setTitle("Wybierz aplikacje do zmiany rozmiaru")
                .setItems(names, (d, which) -> openSingleAppSizeDialog(allApps.get(which)))
                .setNegativeButton("Zamknij", null)
                .show();
    }

    private void openSingleAppSizeDialog(final AppRepository.AppEntry entry) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(18), dp(14), dp(18), dp(10));

        final TextView curInfo = new TextView(this);
        int curScale = LauncherPrefs.getEffectiveIconScale(this, entry.componentKey);
        curInfo.setText("Skala ikony: " + curScale + "% · Kafelek: " + LauncherPrefs.getTileSpanTag(this, entry.componentKey));
        curInfo.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        box.addView(curInfo);

        final SeekBar appSeek = new SeekBar(this);
        appSeek.setMax(90);
        appSeek.setProgress(curScale - 60);
        appSeek.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                int pct = 60 + progress;
                LauncherPrefs.setAppIconScale(IconStyleActivity.this, entry.componentKey, pct);
                curInfo.setText("Skala ikony: " + pct + "% · Kafelek: " + LauncherPrefs.getTileSpanTag(IconStyleActivity.this, entry.componentKey));
            }
            @Override public void onStartTrackingTouch(SeekBar seekBar) {}
            @Override public void onStopTrackingTouch(SeekBar seekBar) {}
        });
        box.addView(appSeek);

        final String[] spans = {"1x1", "2x1", "1x2", "2x2"};
        new AlertDialog.Builder(this)
                .setTitle(entry.label + " · Rozmiar ColorOS 17")
                .setView(box)
                .setItems(new String[]{
                        "Kafelek 1x1 (standardowy)",
                        "Kafelek 2x1 (szeroki)",
                        "Kafelek 1x2 (wysoki)",
                        "Kafelek 2x2 (duzy kafel)",
                        "Przypnij jako widget na pulpit HyperOS 4",
                        "Przywroc rozmiar globalny",
                }, (dlg, idx) -> {
                    if (idx < 4) {
                        LauncherPrefs.setTileSpan(this, entry.componentKey, spans[idx]);
                        Toast.makeText(this, entry.label + " -> " + spans[idx], Toast.LENGTH_SHORT).show();
                    } else if (idx == 4) {
                        Intent it = new Intent(this, ColorOsTileConfigActivity.class);
                        it.putExtra("pin_mode", true);
                        it.putExtra("component_key", entry.componentKey);
                        it.putExtra("span_hint", LauncherPrefs.getTileSpanTag(this, entry.componentKey));
                        startActivity(it);
                    } else {
                        LauncherPrefs.setTileSpan(this, entry.componentKey, "1x1");
                        LauncherPrefs.setAppIconScale(this, entry.componentKey, 0);
                        Toast.makeText(this, entry.label + ": przywrocono domyslny", Toast.LENGTH_SHORT).show();
                    }
                })
                .setNegativeButton("Gotowe", null)
                .show();
    }

    private void loadSamples() {
        PackageManager pm = getPackageManager();
        for (int i = 0; i < allApps.size() && sampleDrawables.size() < 4; i++) {
            AppRepository.AppEntry entry = allApps.get(i);
            sampleDrawables.add(entry.resolveInfo.loadIcon(pm));
            sampleLabels.add(entry.label);
        }
        while (sampleDrawables.size() < 4) {
            sampleDrawables.add(getDrawable(R.drawable.ic_mystical_launcher));
            sampleLabels.add("MysticalOS");
        }
    }

    private void refreshPreview() {
        int scale = LauncherPrefs.getIconScale(this);
        int cornerPct = LauncherPrefs.getCornerPct(this);
        int labelScale = LauncherPrefs.getLabelScale(this);
        int shape = LauncherPrefs.getIconShape(this);
        boolean showLabels = LauncherPrefs.getShowLabels(this);

        if (sizeValText != null) sizeValText.setText(scale + "%");
        if (cornerValText != null) cornerValText.setText(cornerPct + "%");
        if (labelValText != null) labelValText.setText(labelScale + "%");

        if (previewRow != null) {
            previewRow.removeAllViews();
            int iconPx = dp(Math.round(52 * (scale / 100f)));
            for (int i = 0; i < sampleDrawables.size(); i++) {
                LinearLayout cell = new LinearLayout(this);
                cell.setOrientation(LinearLayout.VERTICAL);
                cell.setGravity(Gravity.CENTER);
                LinearLayout.LayoutParams clp = new LinearLayout.LayoutParams(
                        0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f);
                cell.setLayoutParams(clp);

                ImageView iv = new ImageView(this);
                iv.setLayoutParams(new LinearLayout.LayoutParams(iconPx, iconPx));
                iv.setImageBitmap(FluxIconRenderer.renderAppIcon(this, sampleDrawables.get(i), iconPx, shape));
                cell.addView(iv);

                if (showLabels) {
                    TextView tv = new TextView(this);
                    tv.setText(sampleLabels.get(i));
                    tv.setTextColor(Color.WHITE);
                    tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f * (labelScale / 100f));
                    tv.setGravity(Gravity.CENTER);
                    tv.setSingleLine(true);
                    tv.setPadding(dp(2), dp(4), dp(2), 0);
                    cell.addView(tv);
                }
                previewRow.addView(cell);
            }
        }

        if (tilePreviewView != null && !sampleDrawables.isEmpty()) {
            tilePreviewView.setImageBitmap(FluxIconRenderer.renderFluxTileCard(
                    this,
                    sampleDrawables.get(0),
                    sampleLabels.get(0),
                    380,
                    180,
                    2,
                    1,
                    scale,
                    shape,
                    cornerPct,
                    showLabels,
                    LauncherPrefs.getWallpaperAccentColor(this)));
        }
    }

    private interface ToggleListener {
        void onToggle(boolean checked);
    }

    private Switch addToggleRow(LinearLayout parent, String label, boolean initial, final ToggleListener listener) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, dp(10), 0, dp(2));
        TextView tv = new TextView(this);
        tv.setText(label);
        tv.setTextColor(Color.WHITE);
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        tv.setLayoutParams(new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f));
        Switch sw = new Switch(this);
        sw.setChecked(initial);
        sw.setOnCheckedChangeListener((b, c) -> listener.onToggle(c));
        row.addView(tv);
        row.addView(sw);
        parent.addView(row);
        return sw;
    }

    private LinearLayout makeCard() {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        GradientDrawable gd = new GradientDrawable();
        gd.setColor(Color.rgb(19, 23, 39));
        gd.setCornerRadius(dp(18));
        gd.setStroke(dp(1), Color.argb(45, 255, 255, 255));
        card.setBackground(gd);
        int p = dp(14);
        card.setPadding(p, p, p, p);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.setMargins(0, 0, 0, dp(12));
        card.setLayoutParams(lp);
        return card;
    }

    private TextView makeSectionTitle(String text) {
        TextView tv = new TextView(this);
        tv.setText(text);
        tv.setTextColor(Color.WHITE);
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        tv.setTypeface(Typeface.DEFAULT_BOLD);
        return tv;
    }

    private Button makePillButton(String text) {
        Button b = new Button(this);
        b.setText(text);
        b.setAllCaps(false);
        b.setTextColor(Color.WHITE);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        GradientDrawable gd = new GradientDrawable();
        gd.setColor(Color.rgb(32, 37, 62));
        gd.setCornerRadius(dp(10));
        gd.setStroke(dp(1), Color.argb(40, 255, 255, 255));
        b.setBackground(gd);
        return b;
    }

    private Button makeAccentButton(String text) {
        Button b = makePillButton(text);
        GradientDrawable gd = new GradientDrawable(
                GradientDrawable.Orientation.LEFT_RIGHT,
                new int[]{Color.rgb(91, 60, 245), Color.rgb(0, 175, 225)});
        gd.setCornerRadius(dp(12));
        b.setBackground(gd);
        return b;
    }

    private void updateButtons(Button[] btns, int activeIdx) {
        for (int i = 0; i < btns.length; i++) {
            if (btns[i] == null) continue;
            boolean sel = (i == activeIdx);
            GradientDrawable gd = new GradientDrawable();
            gd.setColor(sel ? Color.rgb(91, 60, 245) : Color.rgb(32, 37, 62));
            gd.setCornerRadius(dp(10));
            gd.setStroke(dp(1), sel ? Color.rgb(0, 218, 255) : Color.argb(35, 255, 255, 255));
            btns[i].setBackground(gd);
        }
    }

    private int dp(int v) {
        return FluxIconRenderer.dpToPx(this, v);
    }
}
