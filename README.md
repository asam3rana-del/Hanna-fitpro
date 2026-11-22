# Hanna Fitness — Premium Gym Management

**Hanna Solutions** ka gym software (Android + Windows PC + iPhone/iPad). Matte black + gold premium design,
English / اردو, offline-first, aur **online sync (mobile + PC, multiple devices)**.

## Kya kya hai
- **Dashboard** — active members, aaj ki haazri, aaj / mahine ki wasooli, jald khatam hone wali memberships, baqaya, munafa.
- **Members** — photo, Member ID (GM-0001), phone (contacts se), CNIC, timing (morning/evening/ladies), goal, trainer,
  blood group, emergency contact, notes. Search + filters (Active / Expiring / Expired / Dues / No plan / Inactive), CSV export.
- **Memberships / Packages** — Monthly, Quarterly, 6 Months, Yearly, Personal Training, Day Pass (badal sakte hain);
  admission fee, discount, advance renewal (pichhli khatam hote hi nayi shuru), freeze / extend, cancel.
- **Fees** — partial payment, baqaya hisaab, Cash / JazzCash / Easypaisa / Bank / Card, receipt (80mm print / PDF / WhatsApp).
- **Check-in** — Member ID / naam / phone likhein ya **QR member card** scan karein (USB / Bluetooth scanner); check-out;
  expired / baqaya par foran warning + Renew.
- **Member ID card** — ATM card size PDF, photo + QR code.
- **Reminders** — expiring / expired / dues ki list, ek tap par tayyar WhatsApp message (Settings se message badlein).
- **Trainers** — salary, PT commission %, assigned members.
- **Expenses** — rent, bijli, salaries, equipment… mahine ke hisaab se.
- **Reports** — aamdani, kharcha, net profit, 6 mahine ka chart, plan / payment method / expense breakdown.
- **Body progress** — weight, body fat, chest, waist, arms, thigh, BMI.
- **Staff logins** — Owner / Manager / Reception roles, fingerprint login + app lock.
- **Backup** — roz khud-kaar backup (7 din), Export / Restore file.
- **Online sync** — Firebase Firestore; har phone / PC par same Gym Code => sab devices par ek hi data. Internet na ho
  to bhi poori app chalti hai; net aate hi khud sync.

## Build (GitHub Actions)
1. GitHub par **naya repo** banayein (maslan `Hanna-Fitness`), default branch `main`.
2. Is folder ka sab kuch (`.github` samait) repo mein push / upload karein.
3. Actions > **Build** khud chalega: `android-apk`, `android-aab`, `windows-build` (exe + installer), `ios-build`.
4. Android signing: repo Secrets mein `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD` (Hanna POS wale hi chal jayenge).
5. Pehli build ke baad Actions se artifact **`pubspec-lock`** download kar ke `pubspec.lock` repo ke root mein commit karein
   (is ke baad har build bilkul same package versions se banegi).

App ID: `com.hannasolutions.fitness` (Hanna POS ke saath alag install hoti hai). App ka naam: `lib/app_info.dart`,
`tools/android_fix.sh`, `.github/workflows/build.yml`.

## Online sync setup (ek dafa)
1. console.firebase.google.com par naya project.
2. **Firestore Database** > Create > **Rules** mein `firebase/firestore.rules` paste > Publish.
3. **Authentication** > Sign-in method > **Anonymous** ON.
4. Project settings > Android app add karein (`com.hannasolutions.fitness`) > `google-services.json` download.
5. App mein: More > Settings > **Cloud sync setup** > JSON paste > **Gym Code** (maslan `GYM-BHIKHI`) > Save & Sync.
6. Doosre phone / PC par: pehli screen par **"Join an existing gym"** > wahi JSON + wahi Gym Code.

## Folder
- `lib/db` — SQLite (har table sync-ready: id, updated_at, deleted, dirty)
- `lib/sync/gym_sync.dart` — Firestore push / pull
- `lib/screens` — saari screens; `lib/widgets/ui.dart` — premium design parts
- `app_icon/` — Hanna Fitness icon (SVG + Android / iOS PNG); `windows_assets/app_icon.ico`
