package org.mysticalos.launcher;

import android.app.WallpaperManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.RadialGradient;
import android.graphics.Shader;

public final class LauncherPrefs {
    public static final String PREF_NAME = "mystical_launcher_prefs";

    public static final String KEY_ICON_SCALE = "icon_scale";
    public static final String KEY_LABEL_SCALE = "label_scale";
    public static final String KEY_ICON_SHAPE = "icon_shape";
    public static final String KEY_GRID_COLS = "grid_cols";
    public static final String KEY_SHOW_LABELS = "show_labels";
    public static final String KEY_WALLPAPER = "wallpaper_idx";
    public static final String KEY_TILE_PREFIX = "tile_span_";

    public static final int SHAPE_SQUIRCLE = 0;
    public static final int SHAPE_CIRCLE = 1;
    public static final int SHAPE_ROUNDED = 2;
    public static final int SHAPE_TEARDROP = 3;

    private LauncherPrefs() {}

    public static SharedPreferences prefs(Context ctx) {
        return ctx.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
    }

    public static int getIconScale(Context ctx) {
        return clamp(prefs(ctx).getInt(KEY_ICON_SCALE, 100), 60, 150);
    }

    public static void setIconScale(Context ctx, int pct) {
        prefs(ctx).edit().putInt(KEY_ICON_SCALE, clamp(pct, 60, 150)).apply();
    }

    public static int getLabelScale(Context ctx) {
        return clamp(prefs(ctx).getInt(KEY_LABEL_SCALE, 100), 80, 125);
    }

    public static void setLabelScale(Context ctx, int pct) {
        prefs(ctx).edit().putInt(KEY_LABEL_SCALE, clamp(pct, 80, 125)).apply();
    }

    public static int getIconShape(Context ctx) {
        return clamp(prefs(ctx).getInt(KEY_ICON_SHAPE, SHAPE_SQUIRCLE), 0, 3);
    }

    public static void setIconShape(Context ctx, int shape) {
        prefs(ctx).edit().putInt(KEY_ICON_SHAPE, clamp(shape, 0, 3)).apply();
    }

    public static int getGridCols(Context ctx) {
        int c = prefs(ctx).getInt(KEY_GRID_COLS, 4);
        return (c == 5) ? 5 : 4;
    }

    public static void setGridCols(Context ctx, int cols) {
        prefs(ctx).edit().putInt(KEY_GRID_COLS, (cols == 5) ? 5 : 4).apply();
    }

    public static boolean getShowLabels(Context ctx) {
        return prefs(ctx).getBoolean(KEY_SHOW_LABELS, true);
    }

    public static void setShowLabels(Context ctx, boolean show) {
        prefs(ctx).edit().putBoolean(KEY_SHOW_LABELS, show).apply();
    }

    public static int getWallpaperIndex(Context ctx) {
        return clamp(prefs(ctx).getInt(KEY_WALLPAPER, 0), 0, 3);
    }

    public static void setWallpaperIndex(Context ctx, int idx) {
        prefs(ctx).edit().putInt(KEY_WALLPAPER, clamp(idx, 0, 3)).apply();
    }

    public static int[] getTileSpan(Context ctx, String componentKey) {
        String raw = prefs(ctx).getString(KEY_TILE_PREFIX + componentKey, "1x1");
        if ("2x2".equals(raw)) return new int[]{2, 2};
        if ("2x1".equals(raw)) return new int[]{2, 1};
        if ("1x2".equals(raw)) return new int[]{1, 2};
        return new int[]{1, 1};
    }

    public static String getTileSpanTag(Context ctx, String componentKey) {
        String raw = prefs(ctx).getString(KEY_TILE_PREFIX + componentKey, "1x1");
        if ("2x2".equals(raw) || "2x1".equals(raw) || "1x2".equals(raw)) return raw;
        return "1x1";
    }

    public static void setTileSpan(Context ctx, String componentKey, String spanTag) {
        if (!("2x2".equals(spanTag) || "2x1".equals(spanTag) || "1x2".equals(spanTag))) {
            spanTag = "1x1";
        }
        prefs(ctx).edit().putString(KEY_TILE_PREFIX + componentKey, spanTag).apply();
    }

    public static void resetAllTileSpans(Context ctx) {
        SharedPreferences sp = prefs(ctx);
        SharedPreferences.Editor ed = sp.edit();
        for (String k : sp.getAll().keySet()) {
            if (k.startsWith(KEY_TILE_PREFIX)) {
                ed.remove(k);
            }
        }
        ed.apply();
    }

    public static int[] wallpaperColors(int idx) {
        switch (idx) {
            case 1:
                return new int[]{Color.rgb(8, 28, 36), Color.rgb(16, 86, 102), Color.rgb(0, 210, 180)};
            case 2:
                return new int[]{Color.rgb(36, 14, 34), Color.rgb(122, 30, 88), Color.rgb(255, 118, 92)};
            case 3:
                return new int[]{Color.rgb(14, 18, 28), Color.rgb(36, 52, 92), Color.rgb(110, 168, 255)};
            case 0:
            default:
                return new int[]{Color.rgb(14, 10, 38), Color.rgb(74, 42, 178), Color.rgb(0, 214, 255)};
        }
    }

    public static boolean applyWallpaperBitmap(Context ctx, int idx) {
        try {
            int[] cols = wallpaperColors(idx);
            int w = 720;
            int h = 1600;
            Bitmap bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
            Canvas c = new Canvas(bmp);

            Paint bg = new Paint(Paint.ANTI_ALIAS_FLAG);
            bg.setShader(new LinearGradient(0, 0, w * 0.9f, h, cols[0], cols[1], Shader.TileMode.CLAMP));
            c.drawRect(0, 0, w, h, bg);

            Paint orb1 = new Paint(Paint.ANTI_ALIAS_FLAG);
            orb1.setShader(new RadialGradient(
                    w * 0.25f, h * 0.30f, w * 0.72f,
                    new int[]{Color.argb(140, Color.red(cols[2]), Color.green(cols[2]), Color.blue(cols[2])), Color.TRANSPARENT},
                    new float[]{0f, 1f},
                    Shader.TileMode.CLAMP));
            c.drawCircle(w * 0.25f, h * 0.30f, w * 0.72f, orb1);

            Paint orb2 = new Paint(Paint.ANTI_ALIAS_FLAG);
            orb2.setShader(new RadialGradient(
                    w * 0.80f, h * 0.72f, w * 0.68f,
                    new int[]{Color.argb(120, Color.red(cols[1]), Color.green(cols[1]), Color.blue(cols[1])), Color.TRANSPARENT},
                    new float[]{0f, 1f},
                    Shader.TileMode.CLAMP));
            c.drawCircle(w * 0.80f, h * 0.72f, w * 0.68f, orb2);

            WallpaperManager wm = WallpaperManager.getInstance(ctx);
            wm.setBitmap(bmp);
            bmp.recycle();
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    public static int clamp(int v, int lo, int hi) {
        return Math.max(lo, Math.min(hi, v));
    }
}
