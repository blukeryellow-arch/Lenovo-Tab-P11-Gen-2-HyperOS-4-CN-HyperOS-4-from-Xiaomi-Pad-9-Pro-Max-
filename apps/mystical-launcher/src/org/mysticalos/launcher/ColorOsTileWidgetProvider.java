package org.mysticalos.launcher;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.drawable.Drawable;
import android.os.Build;
import android.os.Bundle;
import android.widget.RemoteViews;

public class ColorOsTileWidgetProvider extends AppWidgetProvider {
    @Override
    public void onUpdate(Context context, AppWidgetManager appWidgetManager, int[] appWidgetIds) {
        for (int appWidgetId : appWidgetIds) {
            Bundle opts = appWidgetManager.getAppWidgetOptions(appWidgetId);
            updateAppWidget(context, appWidgetManager, appWidgetId, opts);
        }
    }

    @Override
    public void onAppWidgetOptionsChanged(
            Context context, AppWidgetManager appWidgetManager, int appWidgetId, Bundle newOptions) {
        updateAppWidget(context, appWidgetManager, appWidgetId, newOptions);
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions);
    }

    @Override
    public void onDeleted(Context context, int[] appWidgetIds) {
        for (int id : appWidgetIds) {
            LauncherPrefs.deleteWidgetTileConfig(context, id);
        }
        super.onDeleted(context, appWidgetIds);
    }

    public static void updateAppWidget(
            Context context, AppWidgetManager mgr, int appWidgetId, Bundle opts) {
        LauncherPrefs.WidgetTileConfig cfg = LauncherPrefs.loadWidgetTileConfig(context, appWidgetId);
        if (cfg == null) {
            String pinComp = LauncherPrefs.prefs(context).getString("last_pin_component", "");
            if (pinComp != null && !pinComp.isEmpty()) {
                cfg = new LauncherPrefs.WidgetTileConfig();
                cfg.componentKey = pinComp;
                cfg.spanHint = LauncherPrefs.prefs(context).getString("last_pin_span", "2x1");
                cfg.scalePct = LauncherPrefs.prefs(context).getInt("last_pin_scale", 112);
                cfg.shape = LauncherPrefs.getIconShape(context);
                cfg.showLabel = LauncherPrefs.getShowLabels(context);
                LauncherPrefs.saveWidgetTileConfig(context, appWidgetId, cfg);
                LauncherPrefs.prefs(context).edit()
                        .remove("last_pin_component")
                        .remove("last_pin_span")
                        .remove("last_pin_scale")
                        .apply();
            }
        }
        if (cfg == null) {
            // Render clean placeholder directing user to configure tile
            RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.coloros_tile_widget);
            Bitmap bmp = FluxIconRenderer.renderFluxTileCard(
                    context,
                    context.getDrawable(R.drawable.ic_icon_style),
                    "Ikony ColorOS 17",
                    280,
                    160,
                    2,
                    1,
                    108,
                    LauncherPrefs.getIconShape(context),
                    LauncherPrefs.getCornerPct(context),
                    true,
                    LauncherPrefs.getWallpaperAccentColor(context));
            views.setImageViewBitmap(R.id.tile_image, bmp);
            Intent cfgIntent = new Intent(context, ColorOsTileConfigActivity.class);
            cfgIntent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId);
            cfgIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            int piFlags = PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE;
            views.setOnClickPendingIntent(
                    R.id.tile_root, PendingIntent.getActivity(context, appWidgetId, cfgIntent, piFlags));
            mgr.updateAppWidget(appWidgetId, views);
            return;
        }

        int minWdp = (opts != null) ? opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 110) : 110;
        int minHdp = (opts != null) ? opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110) : 110;
        if (minWdp <= 0) minWdp = 110;
        if (minHdp <= 0) minHdp = 110;

        int spanCols = minWdp >= 125 ? 2 : 1;
        int spanRows = minHdp >= 125 ? 2 : 1;
        if (opts == null || !opts.containsKey(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)) {
            if ("2x2".equals(cfg.spanHint)) {
                spanCols = 2;
                spanRows = 2;
            } else if ("2x1".equals(cfg.spanHint)) {
                spanCols = 2;
                spanRows = 1;
            } else if ("1x2".equals(cfg.spanHint)) {
                spanCols = 1;
                spanRows = 2;
            } else {
                spanCols = 1;
                spanRows = 1;
            }
        }

        int widthPx = Math.max(150, Math.min(520, FluxIconRenderer.dpToPx(context, minWdp)));
        int heightPx = Math.max(150, Math.min(520, FluxIconRenderer.dpToPx(context, minHdp)));

        PackageManager pm = context.getPackageManager();
        ComponentName cn = ComponentName.unflattenFromString(cfg.componentKey);
        Drawable icon = context.getDrawable(R.drawable.ic_mystical_launcher);
        String label = "Aplikacja";
        Intent launchIntent = null;

        if (cn != null) {
            try {
                ActivityInfo ai = pm.getActivityInfo(cn, 0);
                icon = ai.loadIcon(pm);
                label = String.valueOf(ai.loadLabel(pm));
                launchIntent = new Intent(Intent.ACTION_MAIN);
                launchIntent.addCategory(Intent.CATEGORY_LAUNCHER);
                launchIntent.setComponent(cn);
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
            } catch (Throwable ignored) {
                launchIntent = pm.getLaunchIntentForPackage(cn.getPackageName());
            }
        }
        if (launchIntent == null) {
            launchIntent = new Intent(context, IconStyleActivity.class);
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        }

        Bitmap bmp = FluxIconRenderer.renderFluxTileCard(
                context,
                icon,
                label,
                widthPx,
                heightPx,
                spanCols,
                spanRows,
                cfg.scalePct,
                cfg.shape,
                LauncherPrefs.getCornerPct(context),
                cfg.showLabel,
                LauncherPrefs.getWallpaperAccentColor(context));

        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.coloros_tile_widget);
        views.setImageViewBitmap(R.id.tile_image, bmp);
        int piFlags = PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE;
        views.setOnClickPendingIntent(
                R.id.tile_root,
                PendingIntent.getActivity(context, 10000 + appWidgetId, launchIntent, piFlags));
        mgr.updateAppWidget(appWidgetId, views);
    }
}
