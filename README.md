# Altıgen Sıralama · Hexa Sort

**Game Studio 100 · #100 · Rahatlatıcı ve Casual** · Flutter · Android · iOS · Web

Renkleri yığ, birleştir, on tanesinde patlat!

## Oyun

Altıgen tahtaya renkli yığınlar yerleştir; komşu yığınlarda üstteki aynı renkler kendiliğinden toplanır.

- Aynı renkten 10 olan yığın patlar
- Zincirleme birleşmeler ve tahtayı rahatlatan patlamalar
- Tahta dolarsa oyun biter; kapalı hücreler ileri bölümlerde
- Bölüm hedefi: belirli sayıda altıgen temizle
- Her bölüm otomatik pilotla oynanıp hedefe ulaşılarak doğrulanır

## Bütün oyunlarda ortak sistemler

| Sistem | Durum | Dosya |
|---|---|---|
| 50.000 bölüm + sonsuz bölüm (seed ile deterministik, her bölüm çözülebilirlik testinden geçer) | ✅ | `lib/core/level_plan.dart`, `lib/game/rules.dart` |
| 500 dünya, her 10 bölümde zorluk, her 50 bölümde yeni mekanik kombinasyonu, her 100 bölümde tema, her 1000 bölümde özel ödül | ✅ | `lib/core/level_plan.dart` |
| Oyuncu performansına göre zorluk ayarı | ✅ | `AdaptiveDifficulty` |
| Modlar: Macera, Sonsuz, Zamana karşı, Zen, Günün bölümü, Haftanın bölümü, 150 meydan okuma | ✅ | `lib/app/screens/home.dart` |
| Günlük giriş ödülü (7 günlük döngü), seri, şans çarkı, günlük sürpriz, geri dönen oyuncu ödülü | ✅ | `lib/core/daily.dart` |
| 4 günlük + 7 haftalık görev (tarihe göre otomatik yenilenir), günlük rekor, haftalık kişisel hedef | ✅ | `lib/core/missions.dart` |
| 200+ başarım (50+ gizli) | ✅ | `lib/core/achievements.dart` |
| Oyuncu seviyesi 1-500, 5 kademe (Başlangıç → Efsane) | ✅ | `lib/core/progression.dart` |
| 236 koleksiyon parçası: tema, görünüm, rozet, avatar, çerçeve, efekt | ✅ | `lib/core/collection.dart` |
| İnternetsiz oyun, otomatik kayıt, 3 yedek + yarım kalan yazmayı kurtarma, checksum, sürüm geçişi, yedek kodu ile dışa/içe aktarma | ✅ | `lib/core/save_store.dart`, `lib/core/save_data.dart` |
| Uygulama kapanınca bölüme kaldığı yerden devam | ✅ | `resume` |
| Saat manipülasyonu koruması | ✅ | `lib/core/clock.dart` |
| Çökme döngüsü algılama → güvenli mod, hata günlüğü, performans ölçümü | ✅ | `lib/core/telemetry.dart` |
| Acil durum yapılandırması (reklam/satın alma/analitik kapatma) | ✅ | `assets/config/emergency.json` |
| İzinli, çevrimdışı kuyruklu analitik | ✅ | `AnalyticsQueue` |
| AdMob: ödüllü + geçiş reklamı, sıklık sınırı, UMP/GDPR rızası, yaş kontrolü | ✅ (test kimlikleri) | `lib/app/services/ads_mobile.dart` |
| Satın alma: reklamsız, premium, altın, ipucu, başlangıç paketi; doğrulama, geri yükleme, iade, tekrar koruması | ✅ (ürünler mağazada açılmalı) | `lib/core/monetization.dart` |
| 5 dil (TR, EN, DE, ES, FR), renk körü modu, animasyon azaltma, yazı boyutu, solak düzen, titreşim | ✅ | `lib/core/strings.dart`, Ayarlar |
| Özgün ikon, splash, ses efektleri, müzik, mağaza görselleri (kodla üretilir) | ✅ | `tool/generate_assets.py` |
| CI: analiz, testler, APK + AAB, Web; iOS (manuel); haftalık 10.000 bölüm + 24 ay simülasyonu | ✅ | `.github/workflows/` |

## Çalıştırma

```bash
pip install pillow && python tool/generate_assets.py   # ikon, splash, ses, mağaza görselleri
flutter create --platforms=android,ios,web --org com.gamestudio100 --project-name game_100_hexa_sort .
python tool/patch_platforms.py                         # AdMob id, izinler, uygulama adı
flutter pub get
dart run flutter_launcher_icons && dart run flutter_native_splash:create
flutter test
flutter run                                            # veya: flutter run -d chrome
```

Uzun testler: `flutter test --dart-define=LONG=true test/long_run_test.dart test/soak_test.dart`

## Yayın öncesi yapılacaklar

`docs/RELEASE.md` dosyasına bak: AdMob kimlikleri, mağaza ürünleri, imzalama anahtarları, gizlilik politikası adresi.
