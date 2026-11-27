package org.mysticalos.launcher;

import android.app.usage.UsageStats;
import android.app.usage.UsageStatsManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Bitmap;
import android.graphics.drawable.Drawable;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

public final class AppRepository {
    public static final int CAT_ALL = 0;
    public static final int CAT_COMM = 1;
    public static final int CAT_MEDIA = 2;
    public static final int CAT_TOOLS = 3;
    public static final int CAT_SYSTEM = 4;

    public static final class AppEntry {
        public String label;
        public String packageName;
        public String className;
        public String componentKey;
        public ResolveInfo resolveInfo;
        public int category;
        public int accentColor;
        public long lastUsedMs;
        public int localLaunches;
        public Drawable cachedRawIcon;
        public Bitmap cachedStyledIcon;
        public int cachedStyleSig;
    }

    private AppRepository() {}

    public static List<AppEntry> loadAllApps(Context ctx) {
        List<AppEntry> list = new ArrayList<>();
        PackageManager pm = ctx.getPackageManager();
        Intent main = new Intent(Intent.ACTION_MAIN);
        main.addCategory(Intent.CATEGORY_LAUNCHER);
        List<ResolveInfo> ris = pm.queryIntentActivities(main, 0);

        Map<String, Long> usageMap = readRecentUsageMap(ctx);
        Map<String, Integer> counts = LauncherPrefs.loadLaunchCounts(ctx);
        Set<String> seen = new HashSet<>();

        for (ResolveInfo ri : ris) {
            if (ri.activityInfo == null) continue;
            String pkg = ri.activityInfo.packageName;
            String cls = ri.activityInfo.name;
            if (ctx.getPackageName().equals(pkg) && MysticalHomeActivity.class.getName().equals(cls)) {
                continue;
            }
            String key = pkg + "/" + cls;
            if (!seen.add(key)) continue;

            AppEntry e = new AppEntry();
            e.label = String.valueOf(ri.loadLabel(pm));
            e.packageName = pkg;
            e.className = cls;
            e.componentKey = key;
            e.resolveInfo = ri;
            e.category = classify(pkg, e.label);
            e.lastUsedMs = usageMap.containsKey(pkg) ? usageMap.get(pkg) : 0L;
            e.localLaunches = counts.containsKey(key) ? counts.get(key) : 0;
            list.add(e);
        }

        Collections.sort(list, new Comparator<AppEntry>() {
            @Override
            public int compare(AppEntry a, AppEntry b) {
                return a.label.compareToIgnoreCase(b.label);
            }
        });
        return list;
    }

    public static List<AppEntry> topSuggestedApps(List<AppEntry> all, int maxCount) {
        List<AppEntry> sorted = new ArrayList<>(all);
        Collections.sort(sorted, new Comparator<AppEntry>() {
            @Override
            public int compare(AppEntry a, AppEntry b) {
                if (a.localLaunches != b.localLaunches) {
                    return Integer.compare(b.localLaunches, a.localLaunches);
                }
                if (a.lastUsedMs != b.lastUsedMs) {
                    return Long.compare(b.lastUsedMs, a.lastUsedMs);
                }
                return a.label.compareToIgnoreCase(b.label);
            }
        });
        List<AppEntry> res = new ArrayList<>();
        for (int i = 0; i < sorted.size() && res.size() < maxCount; i++) {
            res.add(sorted.get(i));
        }
        return res;
    }

    private static Map<String, Long> readRecentUsageMap(Context ctx) {
        Map<String, Long> map = new HashMap<>();
        try {
            UsageStatsManager usm = (UsageStatsManager) ctx.getSystemService(Context.USAGE_STATS_SERVICE);
            if (usm == null) return map;
            long now = System.currentTimeMillis();
            List<UsageStats> stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, now - 7L * 86400_000L, now);
            if (stats != null) {
                for (UsageStats us : stats) {
                    if (us == null) continue;
                    String pkg = us.getPackageName();
                    long t = us.getLastTimeUsed();
                    Long prev = map.get(pkg);
                    if (prev == null || t > prev) {
                        map.put(pkg, t);
                    }
                }
            }
        } catch (Throwable ignored) {}
        return map;
    }

    private static int classify(String pkg, String label) {
        String s = (pkg + " " + label).toLowerCase(Locale.ROOT);
        if (s.contains("phone") || s.contains("dialer") || s.contains("messag") || s.contains("mms")
                || s.contains("sms") || s.contains("contact") || s.contains("telegram")
                || s.contains("whatsapp") || s.contains("signal") || s.contains("mail")) {
            return CAT_COMM;
        }
        if (s.contains("camera") || s.contains("gallery") || s.contains("photo") || s.contains("music")
                || s.contains("video") || s.contains("youtube") || s.contains("fm") || s.contains("radio")
                || s.contains("sound") || s.contains("player") || s.contains("media")) {
            return CAT_MEDIA;
        }
        if (s.contains("settings") || s.contains("stk") || s.contains("gms") || s.contains("vending")
                || s.contains("package") || s.contains("mysticalos") || s.contains("rustmonitor")
                || s.contains("provision")) {
            return CAT_SYSTEM;
        }
        return CAT_TOOLS;
    }

    public static String categoryTitle(int cat) {
        switch (cat) {
            case CAT_COMM: return "Komunikacja";
            case CAT_MEDIA: return "Media";
            case CAT_TOOLS: return "Narzedzia";
            case CAT_SYSTEM: return "System";
            default: return "Wszystkie";
        }
    }
}
