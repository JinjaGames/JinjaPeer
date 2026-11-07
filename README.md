# JinjaPeer

Sunucusuz, uçtan uca şifreli, eşler arası (P2P) dosya aktarımı. Flutter ile yazıldı. Windows ve Android'de test edildi; macOS ve iOS ayarları hazır ama henüz derlenmedi.

## Nasıl çalışır?

1. **Davet et:** A kişisi bir davet kodu (`JP1I-…`) oluşturur ve istediği yoldan (WhatsApp, Discord, e-posta…) B'ye gönderir.
2. **Katıl:** B kodu yapıştırır; uygulama bir yanıt kodu (`JP1A-…`) üretir ve B bunu A'ya geri gönderir.
3. **Bağlan:** A yanıt kodunu yapıştırır ve iki cihaz doğrudan bağlanır. Dosyalar hiçbir sunucuya uğramaz.

Kodlar uzundur, çünkü içlerinde iki cihazın birbirini bulması için gereken ağ bilgileri (WebRTC SDP), tek kullanımlık şifreleme anahtarı ve imza bulunur.

> NAT arkasındaki cihazlar kendi genel adreslerini öğrenmek için herkese açık **STUN** sunucularını kullanır (Google, Cloudflare). Bu sunucular yalnızca "senin IP'n şu" der; dosya ya da kod içeriği **geçmez**. Çok kısıtlı ağlarda (simetrik NAT) doğrudan bağlantı kurulamazsa Ayarlar > Ağ bölümünden kendi TURN sunucunu ekleyebilirsin. Veri TURN üzerinden de uçtan uca şifreli kalır.

## Güvenlik

| Katman | Ne yapar |
| --- | --- |
| Ed25519 kimlik | Her kurulumun kalıcı anahtarı. Her kodu imzalar; değiştirilmiş kod reddedilir. Kayıtlı kişiler anahtarla tanınır; adlarını kullanan başka biri için uyarı çıkar. |
| X25519 geçici anahtar | Her bağlantıda yeni anahtar üretilir (ileriye dönük gizlilik). |
| HKDF-SHA256 | Oturum anahtarları iki kodun tamamına bağlanır; her yön için ayrı anahtar kullanılır. |
| Opsiyonel şifre | PBKDF2 (200 000 tur) ile anahtar türetmeye katılır. Yanlış şifre girilirse bağlantı kurulamaz. |
| ChaCha20-Poly1305 | Her paket ayrıca şifrelenir. Tekrarlanan, sırası bozuk, değiştirilmiş ya da aşırı büyük tek bir paket bile bağlantıyı keser. |
| WebRTC DTLS | Altta ikinci, bağımsız şifreleme katmanı. |
| Doğrulama kodu | 60 bitlik `ABCD-EFGH-JKMN` kodu. İki ekranda aynıysa araya giren yoktur. |
| Alıcı koruması | Onaysız hiçbir şey yazılmaz. Dosya adları temizlenir, klasör dışına yazma engellenir, mevcut dosyaların üzerine yazılmaz. Dosya `.jppart` olarak iner, SHA-256 ile doğrulanır. Dosyalar asla otomatik açılmaz. |
| Virüs taraması | JinjaPeer kontrolleri (her platform), Microsoft Defender (Windows) ve isteğe bağlı VirusTotal özet sorgusu. Tehdit bulunursa dosya karantinaya alınır, kaydetmek ya da silmek kullanıcıya sorulur. |

Her iddianın hangi testle kanıtlandığı ve bilinen sınırlar: [docs/SECURITY.md](docs/SECURITY.md).
Kablo protokolü (ileride yazılacak web istemcisi için): [docs/PROTOCOL.md](docs/PROTOCOL.md).

## Özellikler

- Her türlü dosya ve klasör (klasör yapısı korunur), sürükle-bırak
- **Orijinal kalite:** Fotoğraf ve videolar yeniden sıkıştırılmaz; dosya bayt bayt aynı ulaşır, EXIF bilgisi de korunur.
- Gelen istekleri onayla, reddet ya da farklı klasöre kaydet (masaüstü)
- Duraklat, devam et, dosya bazında iptal; canlı hız ve kalan süre
- Aktif aktarımlar, Aktardıklarım, Aldıklarım ve aranabilir Geçmiş
- "Aç" ve "Klasörde göster"; Android'de ayrıca "Paylaş" ve "İndirilenler'de göster"
- Android'de dosyalar telefonun genel **İndirilenler › JinjaPeer** klasörüne iner; ekran kapalıyken de aktarım sürer (bildirimli ön plan servisi)
- Kişilerim: kaydet, favorile, güvenilir olarak işaretle (otomatik kabul), istatistikler
- Koyu ve açık tema, hareketleri azaltma seçeneği, klavye kısayolları (Ctrl+N, Ctrl+J, Ctrl+1…7)

## Geliştirme

```bash
flutter pub get
flutter run -d windows
```

### Testler

Birim ve arayüz testleri (kripto, kodlar, tarayıcı, dosya adı güvenliği, tüm sayfalar):

```bash
flutter test
```

Gerçek WebRTC ile uçtan uca testler: aktarım, saldırı senaryoları, karantina, Defender:

```bash
flutter test integration_test/p2p_test.dart -d windows
```

Android yerel köprüsü (emülatör ya da telefon):

```bash
flutter test integration_test/android_test.dart -d emulator-5554
```

İki farklı cihaz arasında test (Windows ↔ Android, gerçek STUN ile; kodları betik taşır):

```bash
powershell -ExecutionPolicy Bypass -File tools/cross_device.ps1 -AndroidDevice emulator-5554
```

Aynı makinede iki kopya çalıştırmak için (farklı kimliklerle):

```bash
JINJAPEER_PROFILE=ikinci flutter run -d windows
```

### Sürüm derlemesi

```bash
flutter build windows --release
```

```bash
flutter build apk --release
```

Çıktılar: `build/windows/x64/runner/Release/JinjaPeer.exe` ve `build/app/outputs/flutter-apk/app-release.apk`.

## Klasör yapısı

```
lib/core/       kripto, bağlantı kodları, şifreli kanal, dosya adı güvenliği, biçimlendirme
lib/services/   WebRTC oturumu, aktarım protokolü, virüs tarayıcı, Android köprüsü, depolama, denetleyici
lib/models/     kayıt, kişi ve ayar modelleri
lib/ui/         liquid-glass tasarım sistemi, kabuk ve sayfalar
android/        MainActivity.kt (İndirilenler, aç/paylaş), TransferService.kt (arka plan aktarımı)
docs/           SECURITY.md, PROTOCOL.md
test/           birim ve arayüz testleri
integration_test/  WebRTC, Android ve iki cihaz testleri
tools/          cross_device.ps1
```
