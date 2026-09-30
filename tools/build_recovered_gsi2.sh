#!/usr/bin/env bash
set -euo pipefail

ROOT=${1:-work/recovered-gsi/system-root}
APKDIR=${2:-work/recovered-gsi/apks}
OUTDIR=${3:-work/recovered-gsi/output}
MKFS=${MKFS:-work/local-kit/bin/mkfs.erofs}
FSCK=${FSCK:-work/local-kit/bin/fsck.erofs}

T="$ROOT/system"
test -f "$T/build.prop"
test -f "$T/etc/selinux/plat_file_contexts"
for a in GmsCore.apk FakeStore.apk AuroraStore.apk; do
  test -s "$APKDIR/$a"
  unzip -t "$APKDIR/$a" >/dev/null
 done

# Named, audited AI removal only. Keep Android's on-device-intelligence boot JAR:
# it is part of the Android 17 boot class path and deleting it would prevent boot.
rm -rf "$T/app/AppSearchAiSealConfig"
rm -f "$T/bin/aisealhostservice" "$T/etc/init/aisealhostservice.rc"

# No Google GMS package is retained. Add microG, FakeStore and Aurora Store.
rm -rf "$T/priv-app/microG" "$T/priv-app/FakeStore" "$T/app/AuroraStore"
install -d "$T/priv-app/microG" "$T/priv-app/FakeStore" "$T/app/AuroraStore"
install -m 0644 "$APKDIR/GmsCore.apk" "$T/priv-app/microG/GmsCore.apk"
install -m 0644 "$APKDIR/FakeStore.apk" "$T/priv-app/FakeStore/FakeStore.apk"
install -m 0644 "$APKDIR/AuroraStore.apk" "$T/app/AuroraStore/AuroraStore.apk"

install -d "$T/etc/permissions" "$T/etc/default-permissions"
cat > "$T/etc/permissions/privapp-permissions-mystical.xml" <<'EOF'
<permissions>
    <privapp-permissions package="com.google.android.gms">
        <permission name="android.permission.FAKE_PACKAGE_SIGNATURE"/>
    </privapp-permissions>
    <privapp-permissions package="com.android.vending">
        <permission name="android.permission.FAKE_PACKAGE_SIGNATURE"/>
    </privapp-permissions>
</permissions>
EOF
cat > "$T/etc/default-permissions/mystical.xml" <<'EOF'
<exceptions>
    <exception package="com.google.android.gms">
        <permission name="android.permission.ACCESS_FINE_LOCATION" fixed="false" granted="true"/>
        <permission name="android.permission.ACCESS_COARSE_LOCATION" fixed="false" granted="true"/>
        <permission name="android.permission.ACCESS_BACKGROUND_LOCATION" fixed="false" granted="true"/>
        <permission name="android.permission.POST_NOTIFICATIONS" fixed="false" granted="true"/>
    </exception>
    <exception package="com.aurora.store">
        <permission name="android.permission.POST_NOTIFICATIONS" fixed="false" granted="true"/>
    </exception>
    <exception package="com.android.vending">
        <permission name="android.permission.POST_NOTIFICATIONS" fixed="false" granted="true"/>
    </exception>
</exceptions>
EOF
python3 - "$T" <<'PY'
import sys, xml.etree.ElementTree as ET
for p in ("etc/permissions/privapp-permissions-mystical.xml",
          "etc/default-permissions/mystical.xml"):
    ET.parse(sys.argv[1] + "/" + p)
PY

mkdir -p "$OUTDIR" "$OUTDIR/check"
rm -rf "$OUTDIR/check" "$OUTDIR/mysticalos_gsi2_system.img"
mkdir -p "$OUTDIR/check"
FC="$T/etc/selinux/plat_file_contexts"
python3 tools/fc_fixup.py --contexts "$FC" --root "$ROOT" --dry-run \
  --report "$OUTDIR/file-contexts-report.txt"
if grep -E 'MISS .*(priv-app/microG|priv-app/FakeStore|app/AuroraStore|permissions-mystical|default-permissions/mystical)' "$OUTDIR/file-contexts-report.txt"; then
  echo "Added path lacks a SELinux file-context rule" >&2
  exit 1
fi

"$MKFS" -zlz4 -T 0 -U 6d797374-6963-4000-8000-616c00000002 \
  --file-contexts="$FC" --mount-point=/ \
  "$OUTDIR/mysticalos_gsi2_system.img" "$ROOT"
"$FSCK" -p "$OUTDIR/mysticalos_gsi2_system.img"
"$FSCK" --extract="$OUTDIR/check" "$OUTDIR/mysticalos_gsi2_system.img" >/dev/null 2>&1
C="$OUTDIR/check/system"
for p in \
  priv-app/microG/GmsCore.apk \
  priv-app/FakeStore/FakeStore.apk \
  app/AuroraStore/AuroraStore.apk \
  etc/permissions/privapp-permissions-mystical.xml \
  etc/default-permissions/mystical.xml \
  bin/surfaceflinger build.prop; do
  test -s "$C/$p"
done
test ! -e "$C/app/AppSearchAiSealConfig"
test ! -e "$C/bin/aisealhostservice"
test ! -e "$C/etc/init/aisealhostservice.rc"

# Verify APK bytes survived the round trip unchanged.
for pair in \
  "GmsCore.apk priv-app/microG/GmsCore.apk" \
  "FakeStore.apk priv-app/FakeStore/FakeStore.apk" \
  "AuroraStore.apk app/AuroraStore/AuroraStore.apk"; do
  set -- $pair
  cmp "$APKDIR/$1" "$C/$2"
done

{
  echo "MysticalOS GSI-2 experimental recovery build"
  echo "Generated: 2026-09-30"
  echo "Target: Lenovo Tab P11 Gen 2 TB350FU (ARM64 A/B, Treble)"
  echo "Image: EROFS/LZ4 system partition"
  echo
  grep -E '^(ro.system.build.fingerprint|ro.system.build.version.release|ro.system.build.version.sdk|ro.build.version.security_patch)=' "$C/build.prop"
  echo
  echo "Included: microG GmsCore, FakeStore, Aurora Store"
  echo "Removed: AppSearchAiSealConfig and Xiaomi aisealhostservice"
  echo "Kept intentionally: framework-ondeviceintelligence-platform.jar (Android 17 boot class path)"
  echo
  echo "IMPORTANT: this recovery build comes from the verified Xiaomi missi system image"
  echo "available in the workspace, not the unavailable Google AOSP GSI archive. It retains"
  echo "Xiaomi framework code and therefore cannot be guaranteed to boot with Lenovo's Android"
  echo "14 vendor without an on-device test. Flash only from fastbootd after making a backup."
} > "$OUTDIR/README-FIRST.txt"

sha256sum "$OUTDIR/mysticalos_gsi2_system.img" "$APKDIR"/*.apk \
  > "$OUTDIR/SHA256SUMS.txt"
rm -rf "$OUTDIR/check"

echo "Build and round-trip verification complete"
cat "$OUTDIR/SHA256SUMS.txt"
