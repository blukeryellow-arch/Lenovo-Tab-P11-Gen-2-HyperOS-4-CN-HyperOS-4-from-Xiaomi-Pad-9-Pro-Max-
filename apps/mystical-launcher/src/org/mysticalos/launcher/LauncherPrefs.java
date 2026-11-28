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

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public final class LauncherPrefs {
    public static final String PREF_NAME = "mystical_launcher_prefs";

    public static final String KEY_ICON_SCALE = "icon_scale";
    public static final String KEY_CORNER_PCT = "icon_corner_pct";
    public static final String KEY_LABEL_SCALE = "label_scale";
    public static final String KEY_ICON_SHAPE = "icon_shape";
    public static final String KEY_MONET_TINT = "icon_monet_tint";
    public static final String KEY_ICON_SHADOW = "icon_shadow";
    public static final String KEY_GRID_COLS = "grid_cols";
    public static final String KEY_GRID_ROWS = "grid_rows";
    public static final String KEY_SHOW_LABELS = "show_labels";
    public static final String KEY_WALLPAPER = "wallpaper_idx";
    public static final String KEY_HOME_MODE = "home_mode";
    public static final String KEY_SWIPE_DOWN = "swipe_down_action";
    public static final String KEY_TRANSITION = "page_transition";
    public static final String KEY_WIDGET_CLOCK = "widget_clock";
    public static final String KEY_WIDGET_STATS = "widget_stats";
    public static final String KEY_SEARCH_PILL = "search_pill";
    public static final String KEY_PAGE_COUNT = "page_count";

    public static final String KEY_TILE_PREFIX = "tile_span_";
    public static final String KEY_APP_SCALE_PREFIX = "app_scale_";
    public static final String KEY_WIDGET_TILE_PREFIX = "widget_tile_cfg_";
    public static final String KEY_DYNAMIC_ISLAND_ALWAYS = "dynamic_island_always";
    public static final String KEY_ITEM_PAGE_PREFIX = "item_page_";
    public static final String KEY_FOLDERS_JSON = "folders_json_v2";
    public static final String KEY_DOCK_JSON = "dock_json_v2";
    public static final String KEY_ORDER_JSON = "order_json_v2";
    public static final String KEY_LAUNCH_COUNTS = "launch_counts_v2";
    public static final String KEY_INIT_LAYOUT = "layout_initialized_v2";

    public static final int SHAPE_FLUX_SQUIRCLE = 0;
    public static final int SHAPE_HYPEROS = 1;
    public static final int SHAPE_PEBBLE = 2;
    public static final int SHAPE_CIRCLE = 3;
    public static final int SHAPE_ROUNDED = 4;
    public static final int SHAPE_CUSTOM = 5;

    public static final int HOME_MODE_DRAWER = 0;
    public static final int HOME_MODE_CLASSIC = 1;

    public static final int SWIPE_DOWN_NOTIFICATIONS = 0;
    public static final int SWIPE_DOWN_SEARCH = 1;

    public static final int TRANSITION_DEFAULT = 0;
    public static final int TRANSITION_DEPTH = 1;
    public static final int TRANSITION_CASCADE = 2;
    public static final int TRANSITION_TILT = 3;

    public static final class FolderModel {
        public String id;
        public String title;
        public String span; // "1x1" or "2x2"
        public int page;
        public final List<String> items = new ArrayList<>();
    }

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

    public static int getCornerPct(Context ctx) {
        return clamp(prefs(ctx).getInt(KEY_CORNER_PCT, 36), 0, 100);
    }

    public static void setCornerPct(Context ctx, int pct) {
        prefs(ctx).edit().putInt(KEY_CORNER_PCT, clamp(pct, 0, 100)).apply();
    }

    public static int getLabelScale(Context ctx) {
        return clamp(prefs(ctx).getInt(KEY_LABEL_SCALE, 100), 80, 125);
    }

    public static void setLabelScale(Context ctx, int pct) {
        prefs(ctx).edit().putInt(KEY_LABEL_SCALE, clamp(pct, 80, 125)).apply();
    }

    public static int getIconShape(Context ctx) {
        return clamp(prefs(ctx).getInt(KEY_ICON_SHAPE, SHAPE_HYPEROS), 0, 5);
    }

    public static void setIconShape(Context ctx, int shape) {
        prefs(ctx).edit().putInt(KEY_ICON_SHAPE, clamp(shape, 0, 5)).apply();
    }

    public static boolean getMonetTint(Context ctx) {
        return prefs(ctx).getBoolean(KEY_MONET_TINT, false);
    }

    public static void setMonetTint(Context ctx, boolean enabled) {
        prefs(ctx).edit().putBoolean(KEY_MONET_TINT, enabled).apply();
    }

    public static boolean getIconShadow(Context ctx) {
        return prefs(ctx).getBoolean(KEY_ICON_SHADOW, true);
    }

    public static void setIconShadow(Context ctx, boolean enabled) {
        prefs(ctx).edit().putBoolean(KEY_ICON_SHADOW, enabled).apply();
    }

    public static int getGridCols(Context ctx) {
        int c = prefs(ctx).getInt(KEY_GRID_COLS, 4);
        return (c == 5) ? 5 : 4;
    }

    public static void setGridCols(Context ctx, int cols) {
        prefs(ctx).edit().putInt(KEY_GRID_COLS, (cols == 5) ? 5 : 4).apply();
    }

    public static int getGridRows(Context ctx) {
        int r = prefs(ctx).getInt(KEY_GRID_ROWS, 6);
        return (r == 7) ? 7 : (r == 5 ? 5 : 6);
    }

    public static void setGridRows(Context ctx, int rows) {
        int r = (rows == 7) ? 7 : (rows == 5 ? 5 : 6);
        prefs(ctx).edit().putInt(KEY_GRID_ROWS, r).apply();
    }

    public static boolean getShowLabels(Context ctx) {
        return prefs(ctx).getBoolean(KEY_SHOW_LABELS, true);
    }

    public static void setShowLabels(Context ctx, boolean show) {
        prefs(ctx).edit().putBoolean(KEY_SHOW_LABELS, show).apply();
    }

    public static int getHomeMode(Context ctx) {
        return prefs(ctx).getInt(KEY_HOME_MODE, HOME_MODE_DRAWER) == HOME_MODE_CLASSIC
                ? HOME_MODE_CLASSIC : HOME_MODE_DRAWER;
    }

    public static void setHomeMode(Context ctx, int mode) {
        prefs(ctx).edit().putInt(KEY_HOME_MODE, mode == HOME_MODE_CLASSIC ? HOME_MODE_CLASSIC : HOME_MODE_DRAWER).apply();
    }

    public static int getSwipeDownAction(Context ctx) {
        return prefs(ctx).getInt(KEY_SWIPE_DOWN, SWIPE_DOWN_NOTIFICATIONS) == SWIPE_DOWN_SEARCH
                ? SWIPE_DOWN_SEARCH : SWIPE_DOWN_NOTIFICATIONS;
    }

    public static void setSwipeDownAction(Context ctx, int action) {
        prefs(ctx).edit().putInt(KEY_SWIPE_DOWN, action == SWIPE_DOWN_SEARCH ? SWIPE_DOWN_SEARCH : SWIPE_DOWN_NOTIFICATIONS).apply();
    }

    public static int getTransitionStyle(Context ctx) {
        return clamp(prefs(ctx).getInt(KEY_TRANSITION, TRANSITION_DEPTH), 0, 3);
    }

    public static void setTransitionStyle(Context ctx, int style) {
        prefs(ctx).edit().putInt(KEY_TRANSITION, clamp(style, 0, 3)).apply();
    }

    public static boolean getShowClockWidget(Context ctx) {
        return prefs(ctx).getBoolean(KEY_WIDGET_CLOCK, true);
    }

    public static void setShowClockWidget(Context ctx, boolean v) {
        prefs(ctx).edit().putBoolean(KEY_WIDGET_CLOCK, v).apply();
    }

    public static boolean getShowStatsWidget(Context ctx) {
        return prefs(ctx).getBoolean(KEY_WIDGET_STATS, true);
    }

    public static void setShowStatsWidget(Context ctx, boolean v) {
        prefs(ctx).edit().putBoolean(KEY_WIDGET_STATS, v).apply();
    }

    public static boolean getShowSearchPill(Context ctx) {
        return prefs(ctx).getBoolean(KEY_SEARCH_PILL, true);
    }

    public static void setShowSearchPill(Context ctx, boolean v) {
        prefs(ctx).edit().putBoolean(KEY_SEARCH_PILL, v).apply();
    }

    public static int getMinPageCount(Context ctx) {
        return clamp(prefs(ctx).getInt(KEY_PAGE_COUNT, 2), 1, 6);
    }

    public static void setMinPageCount(Context ctx, int cnt) {
        prefs(ctx).edit().putInt(KEY_PAGE_COUNT, clamp(cnt, 1, 6)).apply();
    }

    public static int getWallpaperIndex(Context ctx) {
        return clamp(prefs(ctx).getInt(KEY_WALLPAPER, 0), 0, 5);
    }

    public static void setWallpaperIndex(Context ctx, int idx) {
        prefs(ctx).edit().putInt(KEY_WALLPAPER, clamp(idx, 0, 5)).apply();
    }

    public static int getWallpaperAccentColor(Context ctx) {
        return wallpaperColors(getWallpaperIndex(ctx))[2];
    }

    public static int[] getTileSpan(Context ctx, String key) {
        String raw = prefs(ctx).getString(KEY_TILE_PREFIX + key, "1x1");
        if ("2x2".equals(raw)) return new int[]{2, 2};
        if ("2x1".equals(raw)) return new int[]{2, 1};
        if ("1x2".equals(raw)) return new int[]{1, 2};
        return new int[]{1, 1};
    }

    public static String getTileSpanTag(Context ctx, String key) {
        String raw = prefs(ctx).getString(KEY_TILE_PREFIX + key, "1x1");
        if ("2x2".equals(raw) || "2x1".equals(raw) || "1x2".equals(raw)) return raw;
        return "1x1";
    }

    public static void setTileSpan(Context ctx, String key, String spanTag) {
        if (!("2x2".equals(spanTag) || "2x1".equals(spanTag) || "1x2".equals(spanTag))) {
            spanTag = "1x1";
        }
        prefs(ctx).edit().putString(KEY_TILE_PREFIX + key, spanTag).apply();
    }

    public static int getItemPage(Context ctx, String key, int defPage) {
        return clamp(prefs(ctx).getInt(KEY_ITEM_PAGE_PREFIX + key, defPage), 0, 5);
    }

    public static void setItemPage(Context ctx, String key, int page) {
        prefs(ctx).edit().putInt(KEY_ITEM_PAGE_PREFIX + key, clamp(page, 0, 5)).apply();
    }

    public static void resetAllLayout(Context ctx) {
        SharedPreferences sp = prefs(ctx);
        SharedPreferences.Editor ed = sp.edit();
        for (String k : sp.getAll().keySet()) {
            if (k.startsWith(KEY_TILE_PREFIX)
                    || k.startsWith(KEY_ITEM_PAGE_PREFIX)
                    || k.startsWith(KEY_APP_SCALE_PREFIX)) {
                ed.remove(k);
            }
        }
        ed.remove(KEY_FOLDERS_JSON);
        ed.remove(KEY_DOCK_JSON);
        ed.remove(KEY_ORDER_JSON);
        ed.remove(KEY_INIT_LAYOUT);
        ed.putInt(KEY_ICON_SCALE, 100);
        ed.putInt(KEY_CORNER_PCT, 36);
        ed.putInt(KEY_LABEL_SCALE, 100);
        ed.putInt(KEY_ICON_SHAPE, SHAPE_HYPEROS);
        ed.putBoolean(KEY_SHOW_LABELS, true);
        ed.putBoolean(KEY_MONET_TINT, false);
        ed.putBoolean(KEY_ICON_SHADOW, true);
        ed.apply();
    }

    public static int getAppIconScale(Context ctx, String key) {
        int v = prefs(ctx).getInt(KEY_APP_SCALE_PREFIX + key, 0);
        return v == 0 ? 0 : clamp(v, 60, 150);
    }

    public static void setAppIconScale(Context ctx, String key, int pct) {
        if (pct <= 0) {
            prefs(ctx).edit().remove(KEY_APP_SCALE_PREFIX + key).apply();
        } else {
            prefs(ctx).edit().putInt(KEY_APP_SCALE_PREFIX + key, clamp(pct, 60, 150)).apply();
        }
    }

    public static int getEffectiveIconScale(Context ctx, String key) {
        int custom = getAppIconScale(ctx, key);
        return custom > 0 ? custom : getIconScale(ctx);
    }

    public static boolean isDynamicIslandAlwaysOn(Context ctx) {
        return prefs(ctx).getBoolean(KEY_DYNAMIC_ISLAND_ALWAYS, true);
    }

    public static void setDynamicIslandAlwaysOn(Context ctx, boolean alwaysOn) {
        prefs(ctx).edit().putBoolean(KEY_DYNAMIC_ISLAND_ALWAYS, alwaysOn).apply();
    }

    public static final class WidgetTileConfig {
        public String componentKey = "";
        public String spanHint = "2x1";
        public int scalePct = 108;
        public int shape = SHAPE_FLUX_SQUIRCLE;
        public boolean showLabel = true;
    }

    public static void saveWidgetTileConfig(Context ctx, int appWidgetId, WidgetTileConfig cfg) {
        try {
            JSONObject o = new JSONObject();
            o.put("componentKey", cfg.componentKey == null ? "" : cfg.componentKey);
            o.put("spanHint", cfg.spanHint == null ? "2x1" : cfg.spanHint);
            o.put("scalePct", clamp(cfg.scalePct, 60, 150));
            o.put("shape", clamp(cfg.shape, 0, 5));
            o.put("showLabel", cfg.showLabel);
            prefs(ctx).edit().putString(KEY_WIDGET_TILE_PREFIX + appWidgetId, o.toString()).apply();
        } catch (Throwable ignored) {}
    }

    public static WidgetTileConfig loadWidgetTileConfig(Context ctx, int appWidgetId) {
        String raw = prefs(ctx).getString(KEY_WIDGET_TILE_PREFIX + appWidgetId, "");
        if (raw == null || raw.isEmpty()) return null;
        try {
            JSONObject o = new JSONObject(raw);
            WidgetTileConfig cfg = new WidgetTileConfig();
            cfg.componentKey = o.optString("componentKey", "");
            cfg.spanHint = o.optString("spanHint", "2x1");
            cfg.scalePct = clamp(o.optInt("scalePct", 108), 60, 150);
            cfg.shape = clamp(o.optInt("shape", SHAPE_FLUX_SQUIRCLE), 0, 5);
            cfg.showLabel = o.optBoolean("showLabel", true);
            return cfg.componentKey.isEmpty() ? null : cfg;
        } catch (Throwable ignored) {
            return null;
        }
    }

    public static void deleteWidgetTileConfig(Context ctx, int appWidgetId) {
        prefs(ctx).edit().remove(KEY_WIDGET_TILE_PREFIX + appWidgetId).apply();
    }

    public static List<FolderModel> loadFolders(Context ctx) {
        List<FolderModel> out = new ArrayList<>();
        String raw = prefs(ctx).getString(KEY_FOLDERS_JSON, "");
        if (raw == null || raw.isEmpty()) return out;
        try {
            JSONArray arr = new JSONArray(raw);
            for (int i = 0; i < arr.length(); i++) {
                JSONObject o = arr.getJSONObject(i);
                FolderModel fm = new FolderModel();
                fm.id = o.optString("id", "folder_" + i);
                fm.title = o.optString("title", "Folder");
                fm.span = o.optString("span", "2x2");
                fm.page = clamp(o.optInt("page", 0), 0, 5);
                JSONArray items = o.optJSONArray("items");
                if (items != null) {
                    for (int j = 0; j < items.length(); j++) {
                        String ck = items.optString(j, "");
                        if (!ck.isEmpty()) fm.items.add(ck);
                    }
                }
                if (!fm.items.isEmpty()) out.add(fm);
            }
        } catch (Throwable ignored) {}
        return out;
    }

    public static void saveFolders(Context ctx, List<FolderModel> folders) {
        try {
            JSONArray arr = new JSONArray();
            for (FolderModel fm : folders) {
                if (fm.items.isEmpty()) continue;
                JSONObject o = new JSONObject();
                o.put("id", fm.id);
                o.put("title", fm.title);
                o.put("span", ("2x2".equals(fm.span)) ? "2x2" : "1x1");
                o.put("page", clamp(fm.page, 0, 5));
                JSONArray items = new JSONArray();
                for (String ck : fm.items) items.put(ck);
                o.put("items", items);
                arr.put(o);
            }
            prefs(ctx).edit().putString(KEY_FOLDERS_JSON, arr.toString()).apply();
        } catch (Throwable ignored) {}
    }

    public static List<String> loadDockKeys(Context ctx) {
        return loadStringArray(ctx, KEY_DOCK_JSON);
    }

    public static void saveDockKeys(Context ctx, List<String> keys) {
        saveStringArray(ctx, KEY_DOCK_JSON, keys);
    }

    public static List<String> loadOrderKeys(Context ctx) {
        return loadStringArray(ctx, KEY_ORDER_JSON);
    }

    public static void saveOrderKeys(Context ctx, List<String> keys) {
        saveStringArray(ctx, KEY_ORDER_JSON, keys);
    }

    private static List<String> loadStringArray(Context ctx, String prefKey) {
        List<String> out = new ArrayList<>();
        String raw = prefs(ctx).getString(prefKey, "");
        if (raw == null || raw.isEmpty()) return out;
        try {
            JSONArray arr = new JSONArray(raw);
            for (int i = 0; i < arr.length(); i++) {
                String v = arr.optString(i, "");
                if (!v.isEmpty()) out.add(v);
            }
        } catch (Throwable ignored) {}
        return out;
    }

    private static void saveStringArray(Context ctx, String prefKey, List<String> keys) {
        try {
            JSONArray arr = new JSONArray();
            for (String k : keys) arr.put(k);
            prefs(ctx).edit().putString(prefKey, arr.toString()).apply();
        } catch (Throwable ignored) {}
    }

    public static Map<String, Integer> loadLaunchCounts(Context ctx) {
        Map<String, Integer> out = new HashMap<>();
        String raw = prefs(ctx).getString(KEY_LAUNCH_COUNTS, "");
        if (raw == null || raw.isEmpty()) return out;
        try {
            JSONObject obj = new JSONObject(raw);
            JSONArray names = obj.names();
            if (names != null) {
                for (int i = 0; i < names.length(); i++) {
                    String k = names.getString(i);
                    out.put(k, obj.optInt(k, 0));
                }
            }
        } catch (Throwable ignored) {}
        return out;
    }

    public static void recordLaunch(Context ctx, String componentKey) {
        try {
            Map<String, Integer> m = loadLaunchCounts(ctx);
            int cur = m.containsKey(componentKey) ? m.get(componentKey) : 0;
            m.put(componentKey, cur + 1);
            JSONObject obj = new JSONObject();
            for (Map.Entry<String, Integer> e : m.entrySet()) {
                obj.put(e.getKey(), e.getValue());
            }
            prefs(ctx).edit().putString(KEY_LAUNCH_COUNTS, obj.toString()).apply();
        } catch (Throwable ignored) {}
    }

    public static int[] wallpaperColors(int idx) {
        switch (idx) {
            case 1:
                // HyperOS 4 Szmaragd / Jadeit
                return new int[]{Color.rgb(208, 248, 236), Color.rgb(34, 152, 146), Color.rgb(16, 114, 128)};
            case 2:
                // HyperOS 4 Jedwabny Zachod
                return new int[]{Color.rgb(255, 224, 212), Color.rgb(224, 112, 154), Color.rgb(88, 54, 142)};
            case 3:
                // HyperOS 4 Obsydian (Noc)
                return new int[]{Color.rgb(18, 24, 42), Color.rgb(38, 62, 118), Color.rgb(92, 168, 255)};
            case 4:
                // Zloty Bursztyn
                return new int[]{Color.rgb(255, 238, 206), Color.rgb(218, 138, 56), Color.rgb(142, 74, 28)};
            case 5:
                // Indygo Flux
                return new int[]{Color.rgb(12, 10, 36), Color.rgb(66, 38, 168), Color.rgb(0, 214, 255)};
            case 0:
            default:
                // HyperOS 4 Horizon (Liquid Glass)
                return new int[]{Color.rgb(214, 236, 255), Color.rgb(106, 168, 248), Color.rgb(38, 92, 204)};
        }
    }

    public static String wallpaperName(int idx) {
        switch (idx) {
            case 1: return "Jadeit";
            case 2: return "Zachod";
            case 3: return "Obsydian";
            case 4: return "Bursztyn";
            case 5: return "Flux Indygo";
            default: return "HyperOS 4 Szklo";
        }
    }

    public static Bitmap buildWallpaperBitmap(int idx, int w, int h) {
        int[] cols = wallpaperColors(idx);
        Bitmap bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
        Canvas c = new Canvas(bmp);

        Paint bg = new Paint(Paint.ANTI_ALIAS_FLAG);
        bg.setShader(new LinearGradient(0, 0, w * 0.85f, h, cols[0], cols[1], Shader.TileMode.CLAMP));
        c.drawRect(0, 0, w, h, bg);

        Paint orb1 = new Paint(Paint.ANTI_ALIAS_FLAG);
        orb1.setShader(new RadialGradient(
                w * 0.22f, h * 0.28f, w * 0.88f,
                new int[]{Color.argb(165, Color.red(cols[2]), Color.green(cols[2]), Color.blue(cols[2])), Color.TRANSPARENT},
                new float[]{0f, 1f},
                Shader.TileMode.CLAMP));
        c.drawCircle(w * 0.22f, h * 0.28f, w * 0.88f, orb1);

        Paint orb2 = new Paint(Paint.ANTI_ALIAS_FLAG);
        orb2.setShader(new RadialGradient(
                w * 0.82f, h * 0.68f, w * 0.78f,
                new int[]{Color.argb(145, Color.red(cols[1]), Color.green(cols[1]), Color.blue(cols[1])), Color.TRANSPARENT},
                new float[]{0f, 1f},
                Shader.TileMode.CLAMP));
        c.drawCircle(w * 0.82f, h * 0.68f, w * 0.78f, orb2);

        // Subtle luminous Flux arc
        Paint arc = new Paint(Paint.ANTI_ALIAS_FLAG);
        arc.setShader(new RadialGradient(
                w * 0.55f, h * 0.46f, w * 0.65f,
                new int[]{Color.argb(65, 255, 255, 255), Color.argb(35, Color.red(cols[2]), Color.green(cols[2]), Color.blue(cols[2])), Color.TRANSPARENT},
                new float[]{0f, 0.52f, 1f},
                Shader.TileMode.CLAMP));
        c.drawCircle(w * 0.55f, h * 0.46f, w * 0.65f, arc);
        return bmp;
    }

    public static boolean applyWallpaperBitmap(Context ctx, int idx) {
        try {
            Bitmap bmp = buildWallpaperBitmap(idx, 720, 1600);
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
