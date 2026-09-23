# play_store — sab kuch jo Play Console mein chahiye

| File | Kahan lagani hai |
|---|---|
| `graphics/01_app_icon_512.png` | Main store listing → App icon |
| `graphics/02_feature_graphic_1024x500.png` | Main store listing → Feature graphic |
| `graphics/03_phone_screenshot_1..5_1080x1920.png` | Main store listing → Phone screenshots |
| `STORE_LISTING.txt` | App name, short + full description, category, URLs, release notes |
| `DATA_SAFETY.md` | App content → Data safety ke exact jawab |
| `../PLAY_STORE_RELEASE.md` | Poora upload process (keystore, .aab, testing, release) |

## Screenshots ke baare mein zaroori baat

Yeh screenshots aap ki purani screenshots se banaye gaye hain. Google ka usool hai
ke screenshot mein wohi dikhe jo app mein asal mein hai — design badal jaye to
screenshot bhi badalna hoga. In mein abhi kuch jagah test data hai
("0 nearby", rating 0.00), is liye behtar yeh hai ke nayi app se taza screenshots
lein aur dobara bana lein.

## Naye screenshots se dobara banane ka tareeqa

1. Phone par app chalayein aur 5 screens ki screenshots lein (home, vehicle choice,
   coaster/group, destination, driver offer).
2. Un ko `_source_for_regeneration/` mein `s1_home.png` … `s5_offer.png` naamon se
   replace karein.
3. Us folder mein yeh chalayein:

   ```
   npm i playwright
   node render.js
   ```

   Nayi files `out/` mein bun jayen gi. Captions `render.js` ke upar `shots` array
   mein hain — wahan se text badal sakte hain.

`_source_for_regeneration/` sirf banane ke liye hai; Play Console par sirf
`graphics/` wali files upload hoti hain.
