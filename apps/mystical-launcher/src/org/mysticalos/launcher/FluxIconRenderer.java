package org.mysticalos.launcher;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapShader;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.drawable.AdaptiveIconDrawable;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.os.Build;

public final class FluxIconRenderer {
    private FluxIconRenderer() {}

    public static int dpToPx(Context ctx, float dp) {
        return Math.max(1, Math.round(dp * ctx.getResources().getDisplayMetrics().density));
    }

    public static Path buildShapePath(int shape, float size) {
        Path p = new Path();
        float pad = size * 0.03f;
        float s = size - 2f * pad;
        RectF r = new RectF(pad, pad, pad + s, pad + s);

        if (shape == LauncherPrefs.SHAPE_CIRCLE) {
            p.addOval(r, Path.Direction.CW);
            return p;
        }
        if (shape == LauncherPrefs.SHAPE_ROUNDED) {
            float rad = s * 0.22f;
            p.addRoundRect(r, rad, rad, Path.Direction.CW);
            return p;
        }
        if (shape == LauncherPrefs.SHAPE_TEARDROP) {
            float big = s * 0.48f;
            float small = s * 0.14f;
            float[] radii = new float[]{
                    big, big,
                    big, big,
                    small, small,
                    big, big
            };
            p.addRoundRect(r, radii, Path.Direction.CW);
            return p;
        }

        // ColorOS 17 Squircle (continuous superellipse-like cubic bezier contour)
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
        int px = Math.max(48, Math.min(targetPx, 256));
        Bitmap raw = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888);
        Canvas rc = new Canvas(raw);

        if (Build.VERSION.SDK_INT >= 26 && src instanceof AdaptiveIconDrawable) {
            AdaptiveIconDrawable aid = (AdaptiveIconDrawable) src;
            // AdaptiveIconDrawable expects 108dp canvas with safe 72dp inner zone
            int inset = Math.round(px * 0.20f);
            Drawable bg = aid.getBackground();
            Drawable fg = aid.getForeground();
            if (bg != null) {
                bg.setBounds(-inset, -inset, px + inset, px + inset);
                bg.draw(rc);
            } else {
                rc.drawColor(Color.rgb(34, 38, 56));
            }
            if (fg != null) {
                fg.setBounds(-inset, -inset, px + inset, px + inset);
                fg.draw(rc);
            }
        } else if (src != null) {
            // Give non-adaptive icon a clean translucent Flux backing if transparent
            rc.drawColor(Color.rgb(28, 32, 48));
            int pad = Math.round(px * 0.12f);
            src.setBounds(pad, pad, px - pad, px - pad);
            src.draw(rc);
        } else {
            rc.drawColor(Color.rgb(66, 80, 150));
        }

        Bitmap out = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888);
        Canvas oc = new Canvas(out);
        Path shapePath = buildShapePath(shape, px);

        Paint shaderPaint = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
        shaderPaint.setShader(new BitmapShader(raw, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP));
        oc.drawPath(shapePath, shaderPaint);

        // Subtle ColorOS 17 specular rim
        Paint rim = new Paint(Paint.ANTI_ALIAS_FLAG);
        rim.setStyle(Paint.Style.STROKE);
        rim.setStrokeWidth(Math.max(1.5f, px * 0.022f));
        rim.setColor(Color.argb(65, 255, 255, 255));
        oc.drawPath(shapePath, rim);

        raw.recycle();
        return out;
    }

    public static Drawable renderAppIconDrawable(Context ctx, Drawable src, int targetPx, int shape) {
        return new BitmapDrawable(ctx.getResources(), renderAppIcon(ctx, src, targetPx, shape));
    }
}
