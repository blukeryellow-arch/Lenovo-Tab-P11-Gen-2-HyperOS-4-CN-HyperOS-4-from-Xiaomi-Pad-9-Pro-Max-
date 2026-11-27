package org.mysticalos.launcher;

import android.app.Activity;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.content.Intent;
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
    private TextView sizeValText;
    private TextView labelValText;
    private final List<Drawable> sampleDrawables = new ArrayList<>();
    private final List<String> sampleLabels = new ArrayList<>();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);

        loadSamples();

        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(Color.rgb(12, 14, 24));

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int p = dp(18);
        root.setPadding(p, dp(36), p, dp(28));
        scroll.addView(root);

        TextView title = new TextView(this);
        title.setText("Styl i rozmiar ikon · ColorOS 17");
        title.setTextColor(Color.WHITE);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        root.addView(title);

        TextView sub = new TextView(this);
        sub.setText("Dostosuj rozmiar ikon, ksztalt ColorOS Squircle oraz kafelki 1x1 / 2x1 / 1x2 / 2x2 na pulpicie MysticalOS.");
        sub.setTextColor(Color.rgb(168, 178, 206));
        sub.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        sub.setPadding(0, dp(4), 0, dp(16));
        root.addView(sub);

        // Live preview card
        LinearLayout previewBox = makeCard();
        previewBox.setOrientation(LinearLayout.VERTICAL);
        previewBox.setGravity(Gravity.CENTER_HORIZONTAL);
        TextView prevLbl = new TextView(this);
        prevLbl.setText("PODGLAD NA ZYWO");
        prevLbl.setTextColor(Color.rgb(0, 218, 255));
        prevLbl.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
        prevLbl.setTypeface(Typeface.DEFAULT_BOLD);
        prevLbl.setPadding(0, 0, 0, dp(12));
        previewBox.addView(prevLbl);

        previewRow = new LinearLayout(this);
        previewRow.setOrientation(LinearLayout.HORIZONTAL);
        previewRow.setGravity(Gravity.CENTER);
        previewRow.setMinimumHeight(dp(116));
        previewBox.addView(previewRow);
        root.addView(previewBox);

        // Icon size slider
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

        SeekBar sizeSeek = new SeekBar(this);
        sizeSeek.setMax(90); // 60..150
        sizeSeek.setProgress(LauncherPrefs.getIconScale(this) - 60);
        sizeSeek.setPadding(0, dp(10), 0, dp(4));
        sizeSeek.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar sb, int progress, boolean fromUser) {
                int pct = 60 + progress;
                LauncherPrefs.setIconScale(IconStyleActivity.this, pct);
                refreshPreview();
            }
            @Override public void onStartTrackingTouch(SeekBar sb) {}
            @Override public void onStopTrackingTouch(SeekBar sb) {}
        });
        sizeCard.addView(sizeSeek);

        TextView hintScale = new TextView(this);
        hintScale.setText("Przytrzymaj ikone na pulpicie, aby powiekszyc ja osobno do kafelka 2x1, 1x2 lub 2x2!");
        hintScale.setTextColor(Color.rgb(142, 154, 184));
        hintScale.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        hintScale.setPadding(0, dp(4), 0, 0);
        sizeCard.addView(hintScale);
        root.addView(sizeCard);

        // Shape selector
        LinearLayout shapeCard = makeCard();
        shapeCard.addView(makeSectionTitle("Ksztalt ikon (ColorOS 17 Flux)"));
        LinearLayout shapeRow = new LinearLayout(this);
        shapeRow.setOrientation(LinearLayout.HORIZONTAL);
        shapeRow.setPadding(0, dp(10), 0, 0);
        final String[] shapeNames = {"Squircle", "Kolo", "Kwadrat", "Kropla"};
        final Button[] shapeBtns = new Button[4];
        for (int i = 0; i < 4; i++) {
            final int sIdx = i;
            Button b = makePillButton(shapeNames[i]);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, dp(40), 1f);
            lp.setMargins(i == 0 ? 0 : dp(6), 0, 0, 0);
            b.setLayoutParams(lp);
            b.setOnClickListener(v -> {
                LauncherPrefs.setIconShape(this, sIdx);
                updateShapeButtons(shapeBtns, sIdx);
                refreshPreview();
            });
            shapeBtns[i] = b;
            shapeRow.addView(b);
        }
        updateShapeButtons(shapeBtns, LauncherPrefs.getIconShape(this));
        shapeCard.addView(shapeRow);
        root.addView(shapeCard);

        // Labels + Label Size + Grid Columns
        LinearLayout layoutCard = makeCard();
        layoutCard.addView(makeSectionTitle("Siatka pulpitu i podpisy"));

        LinearLayout showRow = new LinearLayout(this);
        showRow.setOrientation(LinearLayout.HORIZONTAL);
        showRow.setGravity(Gravity.CENTER_VERTICAL);
        showRow.setPadding(0, dp(10), 0, dp(6));
        TextView showLbl = new TextView(this);
        showLbl.setText("Pokazuj nazwy aplikacji");
        showLbl.setTextColor(Color.WHITE);
        showLbl.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        showLbl.setLayoutParams(new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f));
        Switch showSw = new Switch(this);
        showSw.setChecked(LauncherPrefs.getShowLabels(this));
        showSw.setOnCheckedChangeListener((btn, checked) -> {
            LauncherPrefs.setShowLabels(this, checked);
            refreshPreview();
        });
        showRow.addView(showLbl);
        showRow.addView(showSw);
        layoutCard.addView(showRow);

        LinearLayout lblHdr = new LinearLayout(this);
        lblHdr.setOrientation(LinearLayout.HORIZONTAL);
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

        SeekBar lblSeek = new SeekBar(this);
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
        LinearLayout.LayoutParams lp4 = new LinearLayout.LayoutParams(0, dp(40), 1f);
        lp4.setMargins(0, 0, dp(6), 0);
        b4.setLayoutParams(lp4);
        b5.setLayoutParams(new LinearLayout.LayoutParams(0, dp(40), 1f));
        final Button[] colBtns = {b4, b5};
        b4.setOnClickListener(v -> {
            LauncherPrefs.setGridCols(this, 4);
            updateShapeButtons(colBtns, 0);
        });
        b5.setOnClickListener(v -> {
            LauncherPrefs.setGridCols(this, 5);
            updateShapeButtons(colBtns, 1);
        });
        updateShapeButtons(colBtns, LauncherPrefs.getGridCols(this) == 5 ? 1 : 0);
        colRow.addView(b4);
        colRow.addView(b5);
        layoutCard.addView(colRow);
        root.addView(layoutCard);

        // Wallpaper selector
        LinearLayout wallCard = makeCard();
        wallCard.addView(makeSectionTitle("Tapeta MysticalOS Flux"));
        LinearLayout wallRow = new LinearLayout(this);
        wallRow.setOrientation(LinearLayout.HORIZONTAL);
        wallRow.setPadding(0, dp(10), 0, 0);
        final String[] wallNames = {"Indygo", "Szmaragd", "Rubin", "Noc"};
        for (int i = 0; i < 4; i++) {
            final int wIdx = i;
            Button wb = makePillButton(wallNames[i]);
            int[] cols = LauncherPrefs.wallpaperColors(i);
            GradientDrawable gd = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[]{cols[1], cols[2]});
            gd.setCornerRadius(dp(10));
            wb.setBackground(gd);
            wb.setTextColor(Color.WHITE);
            LinearLayout.LayoutParams wlp = new LinearLayout.LayoutParams(0, dp(44), 1f);
            wlp.setMargins(i == 0 ? 0 : dp(6), 0, 0, 0);
            wb.setLayoutParams(wlp);
            wb.setOnClickListener(v -> {
                LauncherPrefs.setWallpaperIndex(this, wIdx);
                boolean ok = LauncherPrefs.applyWallpaperBitmap(this, wIdx);
                Toast.makeText(this, ok ? "Ustawiono tapete: " + wallNames[wIdx] : "Zmieniono styl tla", Toast.LENGTH_SHORT).show();
            });
            wallRow.addView(wb);
        }
        wallCard.addView(wallRow);
        root.addView(wallCard);

        // Actions
        LinearLayout actRow = new LinearLayout(this);
        actRow.setOrientation(LinearLayout.HORIZONTAL);
        actRow.setPadding(0, dp(6), 0, 0);

        Button resetBtn = makePillButton("Reset kafelkow 1x1");
        resetBtn.setLayoutParams(new LinearLayout.LayoutParams(0, dp(46), 1f));
        resetBtn.setOnClickListener(v -> {
            LauncherPrefs.resetAllTileSpans(this);
            LauncherPrefs.setIconScale(this, 100);
            LauncherPrefs.setLabelScale(this, 100);
            LauncherPrefs.setIconShape(this, LauncherPrefs.SHAPE_SQUIRCLE);
            sizeSeek.setProgress(40);
            lblSeek.setProgress(20);
            showSw.setChecked(true);
            refreshPreview();
            Toast.makeText(this, "Przywrocono domyslny uklad MysticalOS", Toast.LENGTH_SHORT).show();
        });

        Button doneBtn = makePillButton("Zastosuj i wroc");
        GradientDrawable doneBg = new GradientDrawable();
        doneBg.setColor(Color.rgb(91, 60, 245));
        doneBg.setCornerRadius(dp(12));
        doneBtn.setBackground(doneBg);
        doneBtn.setTextColor(Color.WHITE);
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

    private void loadSamples() {
        PackageManager pm = getPackageManager();
        Intent main = new Intent(Intent.ACTION_MAIN);
        main.addCategory(Intent.CATEGORY_LAUNCHER);
        List<ResolveInfo> list = pm.queryIntentActivities(main, 0);
        for (int i = 0; i < list.size() && sampleDrawables.size() < 4; i++) {
            ResolveInfo ri = list.get(i);
            sampleDrawables.add(ri.loadIcon(pm));
            sampleLabels.add(String.valueOf(ri.loadLabel(pm)));
        }
        while (sampleDrawables.size() < 4) {
            sampleDrawables.add(getDrawable(R.drawable.ic_mystical_launcher));
            sampleLabels.add("MysticalOS");
        }
    }

    private void refreshPreview() {
        int pct = LauncherPrefs.getIconScale(this);
        int lPct = LauncherPrefs.getLabelScale(this);
        int shape = LauncherPrefs.getIconShape(this);
        boolean showLbl = LauncherPrefs.getShowLabels(this);

        sizeValText.setText(pct + "% (" + Math.round(52f * pct / 100f) + " dp)");
        labelValText.setText(lPct + "%");

        previewRow.removeAllViews();
        int iconDp = Math.round(52f * pct / 100f);
        int iconPx = dp(iconDp);

        for (int i = 0; i < 4; i++) {
            LinearLayout cell = new LinearLayout(this);
            cell.setOrientation(LinearLayout.VERTICAL);
            cell.setGravity(Gravity.CENTER_HORIZONTAL);
            cell.setLayoutParams(new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f));

            ImageView iv = new ImageView(this);
            iv.setImageBitmap(FluxIconRenderer.renderAppIcon(this, sampleDrawables.get(i), Math.max(iconPx, dp(72)), shape));
            iv.setLayoutParams(new LinearLayout.LayoutParams(iconPx, iconPx));
            cell.addView(iv);

            if (showLbl) {
                TextView tv = new TextView(this);
                tv.setText(sampleLabels.get(i));
                tv.setTextColor(Color.WHITE);
                tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f * lPct / 100f);
                tv.setSingleLine(true);
                tv.setGravity(Gravity.CENTER);
                tv.setPadding(dp(2), dp(6), dp(2), 0);
                cell.addView(tv);
            }
            previewRow.addView(cell);
        }
    }

    private LinearLayout makeCard() {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        GradientDrawable gd = new GradientDrawable();
        gd.setColor(Color.rgb(22, 26, 42));
        gd.setCornerRadius(dp(18));
        gd.setStroke(dp(1), Color.rgb(42, 49, 78));
        card.setBackground(gd);
        int pad = dp(14);
        card.setPadding(pad, pad, pad, pad);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.setMargins(0, 0, 0, dp(12));
        card.setLayoutParams(lp);
        return card;
    }

    private TextView makeSectionTitle(String text) {
        TextView tv = new TextView(this);
        tv.setText(text);
        tv.setTextColor(Color.WHITE);
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        tv.setTypeface(Typeface.DEFAULT_BOLD);
        return tv;
    }

    private Button makePillButton(String text) {
        Button b = new Button(this);
        b.setText(text);
        b.setAllCaps(false);
        b.setTextColor(Color.WHITE);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        b.setPadding(dp(6), dp(4), dp(6), dp(4));
        GradientDrawable gd = new GradientDrawable();
        gd.setColor(Color.rgb(34, 40, 64));
        gd.setCornerRadius(dp(12));
        b.setBackground(gd);
        return b;
    }

    private void updateShapeButtons(Button[] btns, int activeIdx) {
        for (int i = 0; i < btns.length; i++) {
            GradientDrawable gd = new GradientDrawable();
            gd.setCornerRadius(dp(12));
            if (i == activeIdx) {
                gd.setColor(Color.rgb(91, 60, 245));
                gd.setStroke(dp(1), Color.rgb(0, 218, 255));
            } else {
                gd.setColor(Color.rgb(34, 40, 64));
            }
            btns[i].setBackground(gd);
        }
    }

    private int dp(float v) {
        return FluxIconRenderer.dpToPx(this, v);
    }
}
