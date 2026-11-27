package org.mysticalos.launcher;

import android.app.Activity;
import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
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

import java.util.List;

public class ColorOsTileConfigActivity extends Activity {
    private int appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID;
    private boolean pinMode = false;
    private List<AppRepository.AppEntry> apps;
    private int selectedIdx = 0;
    private String selectedSpan = "2x1";
    private int scalePct = 112;
    private int shape = LauncherPrefs.SHAPE_FLUX_SQUIRCLE;
    private boolean showLabel = true;

    private ImageView previewImage;
    private TextView selectedAppText;
    private TextView scaleValText;
    private final Button[] spanBtns = new Button[4];

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        setResult(RESULT_CANCELED);

        Intent intent = getIntent();
        if (intent != null && intent.getExtras() != null) {
            appWidgetId = intent.getIntExtra(
                    AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID);
            pinMode = intent.getBooleanExtra("pin_mode", false);
        }
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            pinMode = true;
        }

        shape = LauncherPrefs.getIconShape(this);
        apps = AppRepository.loadAllApps(this);
        String preselectedKey = intent != null ? intent.getStringExtra("component_key") : null;
        if (preselectedKey != null && !preselectedKey.isEmpty()) {
            for (int i = 0; i < apps.size(); i++) {
                if (preselectedKey.equals(apps.get(i).componentKey)) {
                    selectedIdx = i;
                    break;
                }
            }
        }
        String preSpan = intent != null ? intent.getStringExtra("span_hint") : null;
        if ("1x1".equals(preSpan) || "2x1".equals(preSpan) || "1x2".equals(preSpan) || "2x2".equals(preSpan)) {
            selectedSpan = preSpan;
        }

        buildUi();
        refreshPreview();
    }

    private void buildUi() {
        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(Color.rgb(10, 12, 22));

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int p = dp(16);
        root.setPadding(p, dp(32), p, dp(28));
        scroll.addView(root);

        TextView title = new TextView(this);
        title.setText("Kafelek ColorOS 17 na pulpit HyperOS 4");
        title.setTextColor(Color.WHITE);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 20);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        root.addView(title);

        TextView sub = new TextView(this);
        sub.setText("Zmieniaj rozmiar pojedynczych ikon aplikacji (1x1, 2x1, 1x2, 2x2 i skala 60%-150%) bezposrednio na pulpicie HyperOS 4.");
        sub.setTextColor(Color.rgb(164, 176, 206));
        sub.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        sub.setPadding(0, dp(4), 0, dp(14));
        root.addView(sub);

        // Live tile preview
        LinearLayout prevCard = makeCard();
        prevCard.setGravity(Gravity.CENTER_HORIZONTAL);
        previewImage = new ImageView(this);
        LinearLayout.LayoutParams ilp = new LinearLayout.LayoutParams(dp(230), dp(148));
        previewImage.setLayoutParams(ilp);
        previewImage.setScaleType(ImageView.ScaleType.FIT_CENTER);
        prevCard.addView(previewImage);

        selectedAppText = new TextView(this);
        selectedAppText.setTextColor(Color.rgb(0, 218, 255));
        selectedAppText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        selectedAppText.setTypeface(Typeface.DEFAULT_BOLD);
        selectedAppText.setPadding(0, dp(8), 0, 0);
        prevCard.addView(selectedAppText);
        root.addView(prevCard);

        // Span selector (1x1 / 2x1 / 1x2 / 2x2)
        LinearLayout spanCard = makeCard();
        spanCard.addView(makeLabel("Rozmiar kafelka"));
        LinearLayout spanRow = new LinearLayout(this);
        spanRow.setOrientation(LinearLayout.HORIZONTAL);
        spanRow.setPadding(0, dp(8), 0, 0);
        final String[] spans = {"1x1", "2x1", "1x2", "2x2"};
        for (int i = 0; i < spans.length; i++) {
            final String sp = spans[i];
            Button b = makePillButton(sp);
            LinearLayout.LayoutParams blp = new LinearLayout.LayoutParams(0, dp(38), 1f);
            blp.setMargins(i == 0 ? 0 : dp(6), 0, 0, 0);
            b.setLayoutParams(blp);
            b.setOnClickListener(v -> {
                selectedSpan = sp;
                updateSpanButtons();
                refreshPreview();
            });
            spanBtns[i] = b;
            spanRow.addView(b);
        }
        spanCard.addView(spanRow);
        updateSpanButtons();

        // Scale inside tile
        LinearLayout scaleHdr = new LinearLayout(this);
        scaleHdr.setOrientation(LinearLayout.HORIZONTAL);
        scaleHdr.setPadding(0, dp(14), 0, 0);
        TextView scLbl = makeLabel("Rozmiar ikony wewnatrz kafelka");
        scLbl.setLayoutParams(new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f));
        scaleValText = new TextView(this);
        scaleValText.setTextColor(Color.rgb(0, 218, 255));
        scaleValText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        scaleValText.setTypeface(Typeface.DEFAULT_BOLD);
        scaleHdr.addView(scLbl);
        scaleHdr.addView(scaleValText);
        spanCard.addView(scaleHdr);

        SeekBar sb = new SeekBar(this);
        sb.setMax(90); // 60..150
        sb.setProgress(scalePct - 60);
        sb.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                scalePct = 60 + progress;
                refreshPreview();
            }
            @Override public void onStartTrackingTouch(SeekBar seekBar) {}
            @Override public void onStopTrackingTouch(SeekBar seekBar) {}
        });
        spanCard.addView(sb);

        LinearLayout lblRow = new LinearLayout(this);
        lblRow.setOrientation(LinearLayout.HORIZONTAL);
        lblRow.setGravity(Gravity.CENTER_VERTICAL);
        lblRow.setPadding(0, dp(8), 0, 0);
        TextView ltxt = makeLabel("Pokazuj nazwe i etykiete ColorOS 17");
        ltxt.setLayoutParams(new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f));
        Switch sw = new Switch(this);
        sw.setChecked(showLabel);
        sw.setOnCheckedChangeListener((buttonView, isChecked) -> {
            showLabel = isChecked;
            refreshPreview();
        });
        lblRow.addView(ltxt);
        lblRow.addView(sw);
        spanCard.addView(lblRow);
        root.addView(spanCard);

        // App picker list
        LinearLayout appCard = makeCard();
        appCard.addView(makeLabel("Wybierz aplikacje"));
        PackageManager pm = getPackageManager();
        for (int i = 0; i < apps.size(); i++) {
            final int idx = i;
            AppRepository.AppEntry entry = apps.get(i);
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            row.setGravity(Gravity.CENTER_VERTICAL);
            row.setPadding(dp(8), dp(8), dp(8), dp(8));
            GradientDrawable rbg = new GradientDrawable();
            rbg.setColor(Color.rgb(24, 30, 52));
            rbg.setCornerRadius(dp(12));
            row.setBackground(rbg);
            LinearLayout.LayoutParams rlp = new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
            rlp.setMargins(0, dp(6), 0, 0);
            row.setLayoutParams(rlp);

            ImageView iv = new ImageView(this);
            iv.setLayoutParams(new LinearLayout.LayoutParams(dp(36), dp(36)));
            iv.setImageBitmap(FluxIconRenderer.renderAppIcon(
                    this, entry.resolveInfo.loadIcon(pm), dp(36), shape));
            row.addView(iv);

            TextView tv = new TextView(this);
            tv.setText(entry.label + "  (" + entry.packageName + ")");
            tv.setTextColor(Color.WHITE);
            tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
            tv.setPadding(dp(10), 0, 0, 0);
            tv.setSingleLine(true);
            row.addView(tv);

            row.setOnClickListener(v -> {
                selectedIdx = idx;
                refreshPreview();
            });
            appCard.addView(row);
        }
        root.addView(appCard);

        Button applyBtn = makePillButton(pinMode ? "Przypnij kafelek na pulpit" : "Zastosuj kafelek");
        GradientDrawable dbg = new GradientDrawable(
                GradientDrawable.Orientation.LEFT_RIGHT,
                new int[]{Color.rgb(91, 60, 245), Color.rgb(0, 175, 225)});
        dbg.setCornerRadius(dp(14));
        applyBtn.setBackground(dbg);
        applyBtn.setLayoutParams(new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(48)));
        applyBtn.setOnClickListener(v -> applyAndFinish());
        root.addView(applyBtn);

        setContentView(scroll);
    }

    private void applyAndFinish() {
        if (apps.isEmpty()) {
            finish();
            return;
        }
        AppRepository.AppEntry chosen = apps.get(Math.min(selectedIdx, apps.size() - 1));
        LauncherPrefs.WidgetTileConfig cfg = new LauncherPrefs.WidgetTileConfig();
        cfg.componentKey = chosen.componentKey;
        cfg.spanHint = selectedSpan;
        cfg.scalePct = scalePct;
        cfg.shape = shape;
        cfg.showLabel = showLabel;

        // Also mirror per-app span/scale into LauncherPrefs for standalone launcher mode
        LauncherPrefs.setTileSpan(this, chosen.componentKey, selectedSpan);
        LauncherPrefs.setAppIconScale(this, chosen.componentKey, scalePct);

        AppWidgetManager awm = AppWidgetManager.getInstance(this);
        if (!pinMode && appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
            LauncherPrefs.saveWidgetTileConfig(this, appWidgetId, cfg);
            ColorOsTileWidgetProvider.updateAppWidget(this, awm, appWidgetId, awm.getAppWidgetOptions(appWidgetId));
            Intent result = new Intent();
            result.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId);
            setResult(RESULT_OK, result);
            finish();
            return;
        }

        // Request pinned widget directly onto HyperOS 4 / MIUI home screen
        if (Build.VERSION.SDK_INT >= 26 && awm.isRequestPinAppWidgetSupported()) {
            ComponentName provider = new ComponentName(this, ColorOsTileWidgetProvider.class);
            Bundle extras = new Bundle();
            extras.putString("component_key", cfg.componentKey);
            // Save fallback last-pinned key for receiver if launcher creates new ID without re-running config
            LauncherPrefs.prefs(this).edit()
                    .putString("last_pin_component", cfg.componentKey)
                    .putString("last_pin_span", cfg.spanHint)
                    .putInt("last_pin_scale", cfg.scalePct)
                    .apply();
            Intent cb = new Intent(this, ColorOsTileConfigActivity.class);
            PendingIntent successCb = PendingIntent.getActivity(
                    this, 707, cb, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            boolean ok = awm.requestPinAppWidget(provider, extras, successCb);
            Toast.makeText(
                    this,
                    ok ? "Wyslano kafelek " + chosen.label + " (" + selectedSpan + ") na pulpit!"
                       : "Dodaj widget 'Kafelek aplikacji ColorOS 17' z menu widgetow pulpitu.",
                    Toast.LENGTH_LONG).show();
            finish();
            return;
        }

        Toast.makeText(
                this,
                "Zapisano styl (" + selectedSpan + ", " + scalePct + "%). Dodaj widget 'Kafelek ColorOS 17' na pulpit!",
                Toast.LENGTH_LONG).show();
        finish();
    }

    private void refreshPreview() {
        if (scaleValText != null) {
            scaleValText.setText(scalePct + "%");
        }
        if (apps.isEmpty()) return;
        AppRepository.AppEntry entry = apps.get(Math.min(selectedIdx, apps.size() - 1));
        selectedAppText.setText(entry.label + " · " + selectedSpan + " (" + scalePct + "%)");

        int cols = ("2x1".equals(selectedSpan) || "2x2".equals(selectedSpan)) ? 2 : 1;
        int rows = ("1x2".equals(selectedSpan) || "2x2".equals(selectedSpan)) ? 2 : 1;
        int pw = cols == 2 ? 360 : 180;
        int ph = rows == 2 ? 260 : 140;
        Drawable d = entry.resolveInfo.loadIcon(getPackageManager());
        Bitmap bmp = FluxIconRenderer.renderFluxTileCard(
                this,
                d,
                entry.label,
                pw,
                ph,
                cols,
                rows,
                scalePct,
                shape,
                LauncherPrefs.getCornerPct(this),
                showLabel,
                LauncherPrefs.getWallpaperAccentColor(this));
        previewImage.setImageBitmap(bmp);
    }

    private void updateSpanButtons() {
        final String[] spans = {"1x1", "2x1", "1x2", "2x2"};
        for (int i = 0; i < spans.length; i++) {
            if (spanBtns[i] == null) continue;
            boolean sel = spans[i].equals(selectedSpan);
            GradientDrawable gd = new GradientDrawable();
            gd.setColor(sel ? Color.rgb(91, 60, 245) : Color.rgb(30, 36, 58));
            gd.setCornerRadius(dp(10));
            gd.setStroke(dp(1), sel ? Color.rgb(0, 218, 255) : Color.argb(40, 255, 255, 255));
            spanBtns[i].setBackground(gd);
        }
    }

    private LinearLayout makeCard() {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        GradientDrawable gd = new GradientDrawable();
        gd.setColor(Color.rgb(18, 22, 38));
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

    private TextView makeLabel(String s) {
        TextView tv = new TextView(this);
        tv.setText(s);
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
        return b;
    }

    private int dp(int v) {
        return FluxIconRenderer.dpToPx(this, v);
    }
}
