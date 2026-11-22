# Android ka generated project (flutter create) yahan theek hota hai.
# Do template sambhale jate hain:
#   * Kotlin DSL  (android/settings.gradle.kts, android/app/build.gradle.kts) — Flutter 3.29+ ka default
#   * Groovy      (android/settings.gradle,     android/app/build.gradle)     — purana (Flutter 3.24)
# Play Store (31 Aug 2026 se): naye apps / updates ka targetSdk 36 zaroori.
TARGET_SDK=36
# Play Store App ID (2026-11-10 faisla). Kabhi na badlein — badalne se nayi app ban jati hai.
# `namespace` (Kotlin/Java code ka package) jaan boojh kar wahi rehta hai; sirf applicationId badalta hai.
APP_ID="${APP_ID:-com.hannasolutions.fitness}"
MIN_SDK=23   # flutter_secure_storage (backup password); Flutter ka apna minimum is se zyada ho to wahi rehta hai

GRADLE=android/app/build.gradle
[ -f android/app/build.gradle.kts ] && GRADLE=android/app/build.gradle.kts
case "$GRADLE" in *.kts) KTS=1 ;; *) KTS=0 ;; esac
echo "=== Gradle file: $GRADLE (KTS=$KTS) ==="
[ -f "$GRADLE" ] || { echo "ERROR: $GRADLE nahi mili — pehle 'flutter create --platforms=android .' chalayein"; exit 1; }

if [ "$KTS" = 0 ]; then
  # --- Purana template: Kotlin 2.1.0 + AGP 8.7.3 + Gradle 8.9 (Firebase 23.x libs need Kotlin 2.1 metadata) ---
  sed -i -E 's/(org.jetbrains.kotlin.android" version )"[0-9.]+"/\1"2.1.0"/' android/settings.gradle
  sed -i -E 's/(com.android.application" version )"[0-9.]+"/\1"8.7.3"/' android/settings.gradle
  sed -i -E 's/gradle-[0-9.]+-(all|bin)/gradle-8.9-all/' android/gradle/wrapper/gradle-wrapper.properties
  echo "=== settings.gradle (verify versions) ==="
  cat android/settings.gradle
  grep -q '"org.jetbrains.kotlin.android" version "2.1.0"' android/settings.gradle || { echo "ERROR: Kotlin 2.1.0 not applied"; exit 1; }
  grep -q '"com.android.application" version "8.7.3"' android/settings.gradle || { echo "ERROR: AGP 8.7.3 not applied"; exit 1; }
  cat android/gradle/wrapper/gradle-wrapper.properties
  # NDK 25.1 (3.24 template 23.1 pin karta tha), compileSdk/targetSdk, minSdk.
  sed -i -E 's/ndkVersion[[:space:]]*=?[[:space:]]*flutter\.ndkVersion/ndkVersion = "25.1.8937393"/' "$GRADLE"
  sed -i -E "s/compileSdk(Version)?[[:space:]]*=?[[:space:]]*flutter\.compileSdkVersion/compileSdk = $TARGET_SDK/" "$GRADLE"
  sed -i -E "s/targetSdk(Version)?[[:space:]]*=?[[:space:]]*flutter\.targetSdkVersion/targetSdk = $TARGET_SDK/" "$GRADLE"
  sed -i -E "s/minSdk(Version)?[[:space:]]*=?[[:space:]]*flutter\.minSdkVersion/minSdk = $MIN_SDK/" "$GRADLE"
  sed -i -E "s/applicationId[[:space:]]*=?[[:space:]]*\"[^\"]*\"/applicationId = \"$APP_ID\"/" "$GRADLE"
else
  # --- Naya (KTS) template: Flutter khud naye AGP / Kotlin / Gradle deta hai. Sirf check: Kotlin >= 2.1 (Firebase). ---
  SETTINGS=android/settings.gradle.kts
  echo "=== $SETTINGS ==="; cat "$SETTINGS"
  KV=$(grep -oE 'org\.jetbrains\.kotlin\.android"\)[[:space:]]*version[[:space:]]*"[0-9.]+"' "$SETTINGS" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
  echo "Kotlin plugin: ${KV:-?}"
  case "$KV" in
    1.*|2.0.*) sed -i -E 's/(org\.jetbrains\.kotlin\.android"\)[[:space:]]*version[[:space:]]*)"[0-9.]+"/\1"2.1.0"/' "$SETTINGS"; echo "Kotlin -> 2.1.0" ;;
  esac
  cat android/gradle/wrapper/gradle-wrapper.properties
fi
echo "android.suppressUnsupportedCompileSdk=$TARGET_SDK" >> android/gradle.properties

MANIFEST=android/app/src/main/AndroidManifest.xml

# App ka naam (phone par icon ke neeche): Hanna Fitness.
sed -i -E 's/android:label="[^"]*"/android:label="Hanna Fitness"/' "$MANIFEST"
grep -q 'android:label="Hanna Fitness"' "$MANIFEST" || { echo "ERROR: app label not set"; exit 1; }

# Member phone: contact picker (flutter_contacts) — READ_CONTACTS, sirf tab jodo jab pehle se na ho.
if ! grep -q "READ_CONTACTS" "$MANIFEST"; then
  sed -i '0,/<manifest[^>]*>/s//&\n    <uses-permission android:name="android.permission.READ_CONTACTS" \/>/' "$MANIFEST"
fi
grep -n "uses-permission" "$MANIFEST"

# --- R8 rules file (build.gradle isay parhta hai; abhi koi khaas rule nahi chahiye). ---
cat > android/app/proguard-rules.pro <<'EOF'
# Hanna Fitness: no extra rules.
EOF

# --- Production signing is mandatory: never publish a release APK signed with the debug key. ---
: "${KEYSTORE_BASE64:=}"
: "${KEYSTORE_PASSWORD:=}"
: "${KEY_PASSWORD:=}"
[ -n "$KEYSTORE_BASE64" ] || { echo "ERROR: KEYSTORE_BASE64 secret missing; refusing an update-incompatible debug-signed release."; exit 1; }
[ -n "$KEYSTORE_PASSWORD" ] || { echo "ERROR: KEYSTORE_PASSWORD secret missing."; exit 1; }
[ -n "$KEY_PASSWORD" ] || { echo "ERROR: KEY_PASSWORD secret missing."; exit 1; }
printf '%s' "$KEYSTORE_BASE64" | base64 -d > android/app/upload.jks || { echo "ERROR: KEYSTORE_BASE64 is not valid base64."; exit 1; }
[ -s android/app/upload.jks ] || { echo "ERROR: decoded keystore is empty."; exit 1; }
keytool -list -keystore android/app/upload.jks -storepass "$KEYSTORE_PASSWORD" -alias ahkey >/dev/null 2>&1 || { echo "ERROR: keystore is invalid or alias 'ahkey' / store password is incorrect."; exit 1; }
# Firebase / Play ke liye signing fingerprints (public hain, secret nahi) — Firebase Console > Android app > SHA.
echo "=== Signing key fingerprints (Firebase Console mein Android app ke saath lagayein) ==="
keytool -list -v -keystore android/app/upload.jks -storepass "$KEYSTORE_PASSWORD" -alias ahkey 2>/dev/null | grep -E "SHA1:|SHA256:" || true

if [ "$KTS" = 0 ]; then
  # Release buildType mein proguard file jodo (`signingConfig signingConfigs.debug` ke baad).
  sed -i -E "s/^([[:space:]]*)signingConfig[[:space:]]*=?[[:space:]]*signingConfigs\.debug/&\n\1proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'/" "$GRADLE"
  sed -i -E "s/^([[:space:]]*)buildTypes[[:space:]]*\{/\1signingConfigs {\n\1    release {\n\1        storeFile file('upload.jks')\n\1        storePassword System.getenv('KEYSTORE_PASSWORD')\n\1        keyAlias 'ahkey'\n\1        keyPassword System.getenv('KEY_PASSWORD')\n\1    }\n\1}\n\1buildTypes {/" "$GRADLE"
  sed -i -E 's/signingConfig[[:space:]]*=?[[:space:]]*signingConfigs\.debug/signingConfig signingConfigs.release/' "$GRADLE"
else
  # KTS: template ke text par sed ke bajaye aakhir mein ek aur `android {}` block. Gradle mein blocks jurte hain
  # aur baad wali value jeet'ti hai — template ki wording badle tab bhi ye chalta hai.
  cat >> "$GRADLE" <<KTS

// ---- tools/android_fix.sh (CI) ----
android {
    compileSdk = maxOf(flutter.compileSdkVersion, $TARGET_SDK)
    defaultConfig {
        applicationId = "$APP_ID"
        minSdk = maxOf(flutter.minSdkVersion, $MIN_SDK)
        targetSdk = $TARGET_SDK
    }
    compileOptions {
        // flutter_local_notifications (DueAlertService)
        isCoreLibraryDesugaringEnabled = true
    }
    signingConfigs {
        create("release") {
            storeFile = file("upload.jks")
            storePassword = System.getenv("KEYSTORE_PASSWORD")
            keyAlias = "ahkey"
            keyPassword = System.getenv("KEY_PASSWORD")
        }
    }
    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            // proguardFiles yahan NAHI: Flutter ka Gradle plugin release mein khud
            // proguard-android-optimize.txt + android/app/proguard-rules.pro jorta hai. Naya AGP purani
            // `proguard-android.txt` par build hi rok deta hai.
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
KTS
fi
# --- Purane plugins (e.g. file_picker 8.x: compileSdk 34) ko bhi compileSdk >= TARGET_SDK par compile karo. ---
# Naye AndroidX libraries (flutter_plugin_android_lifecycle) 35+ maangti hain, warna checkReleaseAarMetadata fail.
# `finalizeDsl` AGP ka rasmi hook hai (plugin ki apni build.gradle ke BAAD, DSL lock hone se PEHLE chalta hai).
# Root build file ke SHURU mein, taake koi plugin project is se pehle evaluate na ho.
ROOT_KTS=android/build.gradle.kts
if [ "$KTS" = 1 ] && [ -f "$ROOT_KTS" ] && ! grep -q "ah-compile-sdk-floor" "$ROOT_KTS"; then
  { cat <<ROOTKTS
// ---- tools/android_fix.sh (CI): ah-compile-sdk-floor ----
subprojects {
    pluginManager.withPlugin("com.android.library") {
        extensions.configure<com.android.build.api.variant.LibraryAndroidComponentsExtension> {
            finalizeDsl { ext ->
                if ((ext.compileSdk ?: 0) < $TARGET_SDK) ext.compileSdk = $TARGET_SDK
            }
        }
    }
}

ROOTKTS
    cat "$ROOT_KTS"; } > "$ROOT_KTS.new" && mv "$ROOT_KTS.new" "$ROOT_KTS"
  echo "=== $ROOT_KTS ==="; cat "$ROOT_KTS"
fi

echo "=== app gradle (verify sdk / signing / proguard) ==="
grep -n "compileSdk\|targetSdk\|minSdk\|ndkVersion\|signingConfig\|upload.jks\|proguard" "$GRADLE"
if [ "$KTS" = 0 ]; then
  grep -q "proguard-rules.pro" "$GRADLE" || { echo "ERROR: proguard rules not wired into build gradle"; exit 1; }
else
  [ -s android/app/proguard-rules.pro ] || { echo "ERROR: android/app/proguard-rules.pro missing"; exit 1; }
fi
grep -q 'signingConfigs.release\|signingConfigs.getByName("release")' "$GRADLE" || { echo "ERROR: release signing not applied"; exit 1; }
grep -q "targetSdk = $TARGET_SDK" "$GRADLE" || { echo "ERROR: targetSdk $TARGET_SDK not applied"; exit 1; }
grep -q "applicationId = \"$APP_ID\"" "$GRADLE" || { echo "ERROR: applicationId $APP_ID not applied"; exit 1; }
echo "App ID: $APP_ID"

# --- Security: Android auto-backup band (DeviceTag/sync prefs doosre phone par copy na hon). ---
if ! grep -q 'android:allowBackup' "$MANIFEST"; then
  sed -i '0,/<application/s//<application android:allowBackup="false"/' "$MANIFEST"
else
  sed -i -E 's/android:allowBackup="true"/android:allowBackup="false"/' "$MANIFEST"
fi
grep -q 'android:allowBackup="false"' "$MANIFEST" || { echo "ERROR: allowBackup=false not applied"; exit 1; }

# --- Fingerprint (local_auth) Android requirements. Inke bina BiometricPrompt khulta hi nahi aur
# authenticate() PlatformException (no_fragment_activity) deta hai => hamesha "Fingerprint not verified". ---
# 1) USE_BIOMETRIC permission
if ! grep -q "USE_BIOMETRIC" "$MANIFEST"; then
  sed -i '0,/<manifest[^>]*>/s//&\n    <uses-permission android:name="android.permission.USE_BIOMETRIC" \/>/' "$MANIFEST"
fi
grep -n "USE_BIOMETRIC" "$MANIFEST" || { echo "ERROR: USE_BIOMETRIC not added"; exit 1; }

# 2) MainActivity must extend FlutterFragmentActivity
MAIN=$(find android/app/src/main -name "MainActivity.kt" -o -name "MainActivity.java" | head -1)
echo "MainActivity: $MAIN"
sed -i 's/io\.flutter\.embedding\.android\.FlutterActivity\b/io.flutter.embedding.android.FlutterFragmentActivity/; s/: FlutterActivity()/: FlutterFragmentActivity()/; s/extends FlutterActivity/extends FlutterFragmentActivity/' "$MAIN"
cat "$MAIN"
grep -q "FlutterFragmentActivity" "$MAIN" || { echo "ERROR: MainActivity not switched to FlutterFragmentActivity"; exit 1; }

# 3) Themes must be AppCompat based (BiometricPrompt requirement)
for f in android/app/src/main/res/values/styles.xml android/app/src/main/res/values-night/styles.xml; do
  [ -f "$f" ] || continue
  sed -i 's#@android:style/Theme.Light.NoTitleBar#Theme.AppCompat.Light.NoActionBar#g; s#@android:style/Theme.Black.NoTitleBar#Theme.AppCompat.DayNight.NoActionBar#g' "$f"
  echo "=== $f ==="; cat "$f"
done

# WhatsApp ko queries mein (Android 11+ package visibility) — sirf tab jodo jab <queries> pehle se na ho.
if ! grep -q 'com.whatsapp' "$MANIFEST"; then
  if grep -q '<queries>' "$MANIFEST"; then
    sed -i 's#<queries>#<queries>\n        <package android:name="com.whatsapp" />\n        <package android:name="com.whatsapp.w4b" />#' "$MANIFEST"
  else
    sed -i '0,/<application/s##<queries>\n        <package android:name="com.whatsapp" />\n        <package android:name="com.whatsapp.w4b" />\n    </queries>\n    <application#' "$MANIFEST"
  fi
fi
grep -q 'com.whatsapp' "$MANIFEST" || { echo "ERROR: WhatsApp queries not added"; exit 1; }



# --- Core library desugaring (kuch plugins ke liye; nuqsan nahi). ---
if ! grep -q "coreLibraryDesugaring" "$GRADLE"; then
  case "$GRADLE" in
    *.kts)
      sed -i -E 's/^([[:space:]]*)compileOptions[[:space:]]*\{/&\n\1    isCoreLibraryDesugaringEnabled = true/' "$GRADLE"
      printf '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")\n}\n' >> "$GRADLE"
      ;;
    *)
      sed -i -E 's/^([[:space:]]*)compileOptions[[:space:]]*\{/&\n\1    coreLibraryDesugaringEnabled true/' "$GRADLE"
      printf '\ndependencies {\n    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.0.4"\n}\n' >> "$GRADLE"
      ;;
  esac
fi
grep -n "esugar" "$GRADLE"
grep -q "esugar" "$GRADLE" || { echo "ERROR: core library desugaring not applied"; exit 1; }

# --- App icon: Hanna Fitness icon (app_icon/android). ---
# Yahan is liye bhi ke "Import zip" workflow .github/ (build.yml) ko repo mein nahi daalta,
# magar tools/ aur app_icon/ daal deta hai — icon build.yml badle baghair bhi lag jaye.
if [ -d app_icon/android ]; then
  RES=android/app/src/main/res
  cp -R app_icon/android/. "$RES/"
  rm -f "$RES"/mipmap-anydpi-v26/ic_launcher_round.xml
  echo "App icon: Hanna Fitness"; ls "$RES"/mipmap-xxxhdpi
else
  echo "WARNING: app_icon/android nahi mila — purana (Flutter) icon rahega"
fi
