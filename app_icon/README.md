# Hanna Fitness — app icon

Hanna Software Series: matte black `#121215`, safed **H**, beech mein gold **dumbbell** `#D9B45A`.

- `hanna_fitness_icon.svg` — poora icon (master). `hanna_fitness_foreground.svg` — bina background (Android adaptive).
- `android/` — CI `android/app/src/main/res/` mein copy karta hai (background `#121215`).
- `ios/icon_<px>.png` — CI AppIcon.appiconset ki har PNG isi size se badalta hai (alpha nahi).
- Windows: `../windows_assets/app_icon.ico`. App ke andar logo: `../assets/images/logo.png`.

Icon badalna ho to SVG badal kar PNG/ICO dobara banayein (rsvg-convert + ImageMagick).
