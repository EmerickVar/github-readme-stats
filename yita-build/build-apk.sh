#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="/tmp/yita-perp-watchdog-build"
PROJECT_DIR="$BUILD_ROOT/project"
ANDROID_HOME="$BUILD_ROOT/android-sdk"
GRADLE_HOME="$BUILD_ROOT/gradle-8.11.1"
DIST_DIR="$ROOT_DIR/yita-build/dist"
LOG_FILE="$DIST_DIR/build.log"
STATUS_FILE="$DIST_DIR/build-status.txt"
APK_NAME="Yita-Perp-Watchdog-0.1.3.apk"

rm -rf "$DIST_DIR" "$BUILD_ROOT"
mkdir -p "$DIST_DIR" "$PROJECT_DIR" "$ANDROID_HOME/cmdline-tools"

exec > >(tee "$LOG_FILE") 2>&1

echo "Yita Perp Watchdog 0.1.3 Railway build"
echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "root=$ROOT_DIR"

BUILD_EXIT=0
(
  set -euxo pipefail

  command -v java
  java -version
  command -v curl
  command -v unzip
  command -v base64

  cat "$ROOT_DIR"/yita-build/source.part* | base64 --decode > "$BUILD_ROOT/source.zip"
  echo "602a4feedcef2b52e91c37e56f2186ea5d40f61662776d735e955ca6feeb5609  $BUILD_ROOT/source.zip" | sha256sum -c -
  unzip -q "$BUILD_ROOT/source.zip" -d "$PROJECT_DIR"
  test -f "$PROJECT_DIR/settings.gradle.kts"
  test -f "$PROJECT_DIR/app/src/main/AndroidManifest.xml"

  curl --fail --location --retry 5 --retry-all-errors \
    --connect-timeout 30 --max-time 600 \
    "https://downloads.gradle.org/distributions/gradle-8.11.1-bin.zip" \
    --output "$BUILD_ROOT/gradle.zip"
  unzip -q "$BUILD_ROOT/gradle.zip" -d "$BUILD_ROOT"
  test -x "$GRADLE_HOME/bin/gradle"

  curl --fail --location --retry 5 --retry-all-errors \
    --connect-timeout 30 --max-time 600 \
    "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" \
    --output "$BUILD_ROOT/android-commandline-tools.zip"
  unzip -q "$BUILD_ROOT/android-commandline-tools.zip" -d "$BUILD_ROOT/android-commandline-tools"
  mkdir -p "$ANDROID_HOME/cmdline-tools/latest"
  mv "$BUILD_ROOT/android-commandline-tools/cmdline-tools"/* "$ANDROID_HOME/cmdline-tools/latest/"

  export ANDROID_HOME
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
  export GRADLE_USER_HOME="$BUILD_ROOT/gradle-cache"
  export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

  yes | sdkmanager --licenses >/dev/null || true
  sdkmanager --install \
    "platform-tools" \
    "platforms;android-35" \
    "build-tools;35.0.0"

  "$GRADLE_HOME/bin/gradle" \
    --project-dir "$PROJECT_DIR" \
    --no-daemon \
    --stacktrace \
    :app:assembleDebug

  APK_SOURCE="$PROJECT_DIR/app/build/outputs/apk/debug/app-debug.apk"
  test -s "$APK_SOURCE"
  unzip -t "$APK_SOURCE"
  cp "$APK_SOURCE" "$DIST_DIR/$APK_NAME"
  sha256sum "$DIST_DIR/$APK_NAME" > "$DIST_DIR/$APK_NAME.sha256"

  base64 -w0 "$DIST_DIR/$APK_NAME" > "$BUILD_ROOT/apk.b64"
  split -b 16000 -d -a 2 "$BUILD_ROOT/apk.b64" "$DIST_DIR/apk.part"
  wc -c "$DIST_DIR/$APK_NAME" "$DIST_DIR"/apk.part*

  BUILD_TOOLS="$ANDROID_HOME/build-tools/35.0.0"
  "$BUILD_TOOLS/apksigner" verify --verbose --print-certs "$DIST_DIR/$APK_NAME" > "$DIST_DIR/signature-verification.txt"

  {
    echo "package=com.emerickvar.yitaperpwatchdog"
    echo "version=0.1.3"
    echo "apk=$APK_NAME"
    echo "apk_bytes=$(wc -c < "$DIST_DIR/$APK_NAME")"
    echo "apk_parts=$(find "$DIST_DIR" -maxdepth 1 -type f -name 'apk.part*' | wc -l)"
    echo "source_sha256=602a4feedcef2b52e91c37e56f2186ea5d40f61662776d735e955ca6feeb5609"
  } > "$DIST_DIR/build-info.txt"
) || BUILD_EXIT=$?

{
  echo "exit_code=$BUILD_EXIT"
  echo "finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [ "$BUILD_EXIT" -eq 0 ] && [ -s "$DIST_DIR/$APK_NAME" ]; then
    echo "status=success"
  else
    echo "status=failure"
  fi
} > "$STATUS_FILE"

cat "$STATUS_FILE"
# Deliberadamente devuelve 0 para que Railway publique el log incluso si el toolchain falla.
exit 0
