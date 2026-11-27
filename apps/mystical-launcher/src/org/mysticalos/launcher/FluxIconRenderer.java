package org.mysticalos.launcher;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapShader;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffColorFilter;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.graphics.drawable.AdaptiveIconDrawable;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.os.Build;
import android.text.TextPaint;
import android.text.TextUtils;

public final class FluxIconRenderer {
    private FluxIconRenderer() {}

    public static int dpToPx(Context ctx, float dp) {
        return Math.max(1, Math.round(dp * ctx.getResources().getDisplayMetrics().density));
    }

    public static Path buildShapePath(int shape, float size, int cornerPct) {
        Path p = new Path();
        float pad = size * 0.03f;
        float s = size - 2f * pad;
        RectF r = new RectF(pad, pad, pad + s, pad + s);

        if (shape == LauncherPrefs.SHAPE_CIRCLE) {
            p.addOval(r, Path.Direction.CW);
            return p;
        }
        if (shape == LauncherPrefs.SHAPE_ROUNDED) {
            float rad = s * 0.20f;
            p.addRoundRect(r, rad, rad, Path.Direction.CW);
            return p;
        }
        if (shape == LauncherPrefs.SHAPE_HYPEROS) {
            float rad = s * 0.29f;
            p.addRoundRect(r, rad, rad, Path.Direction.CW);
            return p;
        }
        if (shape == LauncherPrefs.SHAPE_PEBBLE) {
            float big = s * 0.46f;
            float small = s * 0.16f;
            float[] radii = new float[]{
                    big, big,
                    big, big,
                    small, small,
                    big, big
            };
            p.addRoundRect(r, radii, Path.Direction.CW);
            return p;
        }
        if (shape == LauncherPrefs.SHAPE_CUSTOM) {
            float pct = Math.max(0, Math.min(100, cornerPct)) / 100f;
            float rad = s * 0.50f * pct;
            p.addRoundRect(r, rad, rad, Path.Direction.CW);
            return p;
        }

        // SHAPE_FLUX_SQUIRCLE: ColorOS 17 continuous superellipse contour
        float cx = size * 0.5f;
        float half = s * 0.5f;
        float t = half * 0.86f;
        p.moveTo(cx, pad);
        p.cubicTo(cx + t, pad, pad + s, cx - t, pad + s, cx);
        p.cubicTo(pad + s, cx + t, cx + t, pad + s, cx, pad + s);
        p.cubicTo(cx - t, pad + s, pad, cx + t, pad, cx);
        p.cubicTo(pad, cx - t, cx - t, pad, cx, pad);
        p.close();
        return p;
    }

    public static Bitmap renderAppIcon(Context ctx, Drawable src, int targetPx, int shape) {
        return renderAppIcon(
                ctx,
                src,
                targetPx,
                shape,
                LauncherPrefs.getCornerPct(ctx),
                LauncherPrefs.getMonetTint(ctx),
                LauncherPrefs.getIconShadow(ctx),
                LauncherPrefs.getWallpaperAccentColor(ctx));
    }

    public static Bitmap renderAppIcon(
            Context ctx,
            Drawable src,
            int targetPx,
            int shape,
            int cornerPct,
            boolean monetTint,
            boolean withShadow,
            int accentColor) {
        int px = Math.max(48, Math.min(targetPx, 320));
        Bitmap raw = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888);
        Canvas rc = new Canvas(raw);

        if (Build.VERSION.SDK_INT >= 26 && src instanceof AdaptiveIconDrawable) {
            AdaptiveIconDrawable aid = (AdaptiveIconDrawable) src;
            int inset = Math.round(px * 0.20f);
            Drawable bg = aid.getBackground();
            Drawable fg = aid.getForeground();
            if (bg != null) {
                bg.setBounds(-inset, -inset, px + inset, px + inset);
                bg.draw(rc);
            } else {
                rc.drawColor(Color.rgb(34, 38, 58));
            }
            if (fg != null) {
                fg.setBounds(-inset, -inset, px + inset, px + inset);
                fg.draw(rc);
            }
        } else if (src != null) {
            rc.drawColor(Color.rgb(26, 32, 52));
            int pad = Math.round(px * 0.12f);
            src.setBounds(pad, pad, px - pad, px - pad);
            src.draw(rc);
        } else {
            rc.drawColor(Color.rgb(66, 80, 150));
        }

        if (monetTint) {
            int tint = Color.argb(68, Color.red(accentColor), Color.green(accentColor), Color.blue(accentColor));
            rc.drawColor(tint, PorterDuff.Mode.SRC_ATOP);
        }

        Bitmap out = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888);
        Canvas oc = new Canvas(out);
        Path shapePath = buildShapePath(shape, px, cornerPct);

        if (withShadow) {
            Paint sh = new Paint(Paint.ANTI_ALIAS_FLAG);
            sh.setColor(Color.argb(58, 0, 0, 0));
            oc.save();
            oc.translate(0f, px * 0.025f);
            oc.drawPath(shapePath, sh);
            oc.restore();
        }

        Paint shaderPaint = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
        shaderPaint.setShader(new BitmapShader(raw, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP));
        if (monetTint) {
            shaderPaint.setColorFilter(new PorterDuffColorFilter(
                    Color.argb(26, Color.red(accentColor), Color.green(accentColor), Color.blue(accentColor)),
                    PorterDuff.Mode.SRC_ATOP));
        }
        oc.drawPath(shapePath, shaderPaint);

        Paint rim = new Paint(Paint.ANTI_ALIAS_FLAG);
        rim.setStyle(Paint.Style.STROKE);
        rim.setStrokeWidth(Math.max(1.5f, px * 0.022f));
        rim.setColor(Color.argb(72, 255, 255, 255));
        oc.drawPath(shapePath, rim);

        raw.recycle();
        return out;
    }

    public static Drawable renderAppIconDrawable(Context ctx, Drawable src, int targetPx, int shape) {
        return new BitmapDrawable(ctx.getResources(), renderAppIcon(ctx, src, targetPx, shape));
    }

    public static int extractDominantColor(Drawable d, int fallbackColor) {
        if (d == null) return fallbackColor;
        try {
            int sz = 24;
            Bitmap b = Bitmap.createBitmap(sz, sz, Bitmap.Config.ARGB_8888);
            Canvas c = new Canvas(b);
            d.setBounds(0, 0, sz, sz);
            d.draw(c);
            long rSum = 0;
            long gSum = 0;
            long bSum = 0;
            long n = 0;
            for (int y = 4; y < sz - 4; y += 2) {
                for (int x = 4; x < sz - 4; x += 2) {
                    int px = b.getPixel(x, y);
                    int a = Color.alpha(px);
                    if (a < 180) continue;
                    int r = Color.red(px);
                    int g = Color.green(px);
                    int bl = Color.blue(px);
                    int maxC = Math.max(r, Math.max(g, bl));
                    int minC = Math.min(r, Math.min(g, bl));
                    int w = (maxC - minC > 24) ? 3 : 1;
                    rSum += (long) r * w;
                    gSum += (long) g * w;
                    bSum += (long) bl * w;
                    n += w;
                }
            }
            b.recycle();
            if (n == 0) return fallbackColor;
            int r = (int) Math.min(255, Math.max(24, rSum / n));
            int g = (int) Math.min(255, Math.max(24, gSum / n));
            int bl = (int) Math.min(255, Math.max(24, bSum / n));
            return Color.rgb(r, g, bl);
        } catch (Throwable ignored) {
            return fallbackColor;
        }
    }

    public static Bitmap renderFluxTileCard(
            Context ctx,
            Drawable src,
            String label,
            int widthPx,
            int heightPx,
            int spanCols,
            int spanRows,
            int iconScalePct,
            int shape,
            int cornerPct,
            boolean showLabel,
            int accentColor) {
        int w = Math.max(120, Math.min(widthPx, 640));
        int h = Math.max(120, Math.min(heightPx, 640));
        Bitmap bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
        Canvas c = new Canvas(bmp);

        int dom = extractDominantColor(src, accentColor);
        int topCol = blendColors(dom, Color.rgb(20, 24, 46), 0.56f);
        int botCol = blendColors(accentColor, Color.rgb(12, 16, 34), 0.62f);

        float rad = Math.min(w, h) * (shape == LauncherPrefs.SHAPE_CIRCLE ? 0.36f
                : shape == LauncherPrefs.SHAPE_ROUNDED ? 0.16f
                : shape == LauncherPrefs.SHAPE_CUSTOM ? Math.max(0.04f, 0.34f * (cornerPct / 100f))
                : 0.24f);
        RectF card = new RectF(4f, 4f, w - 4f, h - 4f);

        Paint bg = new Paint(Paint.ANTI_ALIAS_FLAG);
        bg.setShader(new LinearGradient(0f, 0f, w, h, topCol, botCol, Shader.TileMode.CLAMP));
        c.drawRoundRect(card, rad, rad, bg);

        Paint border = new Paint(Paint.ANTI_ALIAS_FLAG);
        border.setStyle(Paint.Style.STROKE);
        border.setStrokeWidth(Math.max(2f, Math.min(w, h) * 0.015f));
        border.setColor(Color.argb(90, 255, 255, 255));
        c.drawRoundRect(card, rad, rad, border);

        float scaleF = Math.max(0.6f, Math.min(1.5f, iconScalePct / 100f));
        int baseIcon = Math.round(Math.min(w, h) * (spanCols == 1 && spanRows == 1 ? 0.56f : 0.48f) * scaleF);
        baseIcon = Math.max(48, Math.min(baseIcon, Math.min(w, h) - 24));
        Bitmap iconBmp = renderAppIcon(ctx, src, baseIcon, shape, cornerPct, false, true, accentColor);

        boolean wide = (spanCols >= 2 && spanRows == 1) || w > h * 1.35f;
        TextPaint tp = new TextPaint(Paint.ANTI_ALIAS_FLAG);
        tp.setColor(Color.WHITE);
        tp.setTypeface(Typeface.DEFAULT_BOLD);

        if (wide) {
            float leftPad = w * 0.08f;
            float iconY = (h - iconBmp.getHeight()) * 0.5f;
            c.drawBitmap(iconBmp, leftPad, iconY, null);

            if (showLabel && label != null) {
                float textLeft = leftPad + iconBmp.getWidth() + w * 0.06f;
                float availW = Math.max(30f, w - textLeft - w * 0.06f);
                tp.setTextSize(Math.max(20f, h * 0.18f));
                String ell = TextUtils.ellipsize(label, tp, availW, TextUtils.TruncateAt.END).toString();
                c.drawText(ell, textLeft, h * 0.48f, tp);

                tp.setTextSize(Math.max(15f, h * 0.12f));
                tp.setTypeface(Typeface.DEFAULT);
                tp.setColor(Color.argb(200, 145, 232, 255));
                c.drawText("ColorOS 17 · " + spanCols + "x" + spanRows + " (" + iconScalePct + "%)", textLeft, h * 0.68f, tp);
            }
        } else {
            float iconX = (w - iconBmp.getWidth()) * 0.5f;
            float iconY = showLabel ? (h - iconBmp.getHeight()) * 0.36f : (h - iconBmp.getHeight()) * 0.5f;
            c.drawBitmap(iconBmp, iconX, iconY, null);

            if (showLabel && label != null) {
                tp.setTextAlign(Paint.Align.CENTER);
                tp.setTextSize(Math.max(18f, Math.min(w, h) * (spanCols >= 2 ? 0.11f : 0.13f)));
                float availW = w * 0.84f;
                String ell = TextUtils.ellipsize(label, tp, availW, TextUtils.TruncateAt.END).toString();
                c.drawText(ell, w * 0.5f, h * 0.82f, tp);

                if (spanCols >= 2 || spanRows >= 2) {
                    tp.setTextSize(Math.max(14f, Math.min(w, h) * 0.075f));
                    tp.setTypeface(Typeface.DEFAULT);
                    tp.setColor(Color.argb(190, 145, 232, 255));
                    c.drawText(spanCols + "x" + spanRows + " · " + iconScalePct + "%", w * 0.5f, h * 0.92f, tp);
                }
            }
        }

        iconBmp.recycle();
        return bmp;
    }

    public static int blendColors(int c1, int c2, float ratioC2) {
        float t = Math.max(0f, Math.min(1f, ratioC2));
        float s = 1f - t;
        int r = Math.round(Color.red(c1) * s + Color.red(c2) * t);
        int g = Math.round(Color.green(c1) * s + Color.green(c2) * t);
        int b = Math.round(Color.blue(c1) * s + Color.blue(c2) * t);
        return Color.rgb(r, g, b);
    }
}
