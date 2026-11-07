# JinjaPeer güvenlik modeli

Bu belge "araya kimse girebilir mi, deneye deneye girilebilir mi?" sorusunu ve
her iddiayı doğrulayan otomatik testi listeler.

## Kısa cevap

- **Kod olmadan bağlanmak imkânsız.** Ortada dinleyen bir sunucu ya da açık port
  yok. Bir cihaza ulaşmak için o anki, süreli ve tek kullanımlık koddaki rastgele
  WebRTC kimlik bilgilerine (ICE ufrag/pwd, DTLS parmak izi) ihtiyaç var.
  Tahmin edilecek bir "giriş ekranı" olmadığı için **çevrimiçi deneme yanılma
  yapılamaz.**
- **Kodu çalan biri de bağlantıyı ele geçiremez.** Davet tek kullanımlıktır; ilk
  yapıştırılan geçerli yanıttan sonra başka yanıt kabul edilmez. Yanıt kodları
  davete (oturum kimliği) bağlıdır.
- **Araya giren (MITM), iki ekranda aynı doğrulama kodunu gösteremez.** 60 bitlik
  doğrulama kodu (`ABCD-EFGH-JKMN`) iki kodun tamamından türetilir. Kodları
  kendi kodlarıyla değiştiren bir saldırgan, iki tarafın aynı kodu görmesi için
  yaklaşık 2⁶⁰ (≈10¹⁸) deneme yapmak zorundadır. Bu, kodun 15 dakikalık süresi
  içinde pratikte imkânsızdır.
- **Kayıtlı kişiler taklit edilemez.** Kişiler Ed25519 kimlik anahtarıyla
  tanınır. Aynı adı kullanan farklı anahtarlı biri görünür biçimde uyarılır.
- **Şifre (opsiyonel) ek bir kat.** Yanlış şifre el sıkışmayı bozar. Şifreye
  karşı çevrimdışı tahmin yalnızca iki kodu birden ele geçirmiş *ve* doğrulama
  kodu uyuşmazlığını görmezden gelmiş bir saldırgan için mümkündür. Buna karşı
  PBKDF2-SHA256 (200 000 tur) kullanılır.

## Katmanlar

| Katman | Görev |
| --- | --- |
| Ed25519 imza | Her kod imzalı; tek bir bayt değişse reddedilir. |
| X25519 (her bağlantıda yeni) | İleriye dönük gizlilik; düşük dereceli/sıfır anahtarlar reddedilir. |
| HKDF-SHA256 | Anahtarlar iki kodun tamamına (SDP + DTLS parmak izleri dahil) bağlıdır; yön başına ayrı anahtar. |
| ChaCha20-Poly1305 | Her çerçeve şifreli ve doğrulanmış; sayaç nonce'u. Tekrar edilen, sırası bozulan, değiştirilen ya da aşırı büyük tek bir paket bağlantıyı keser. |
| WebRTC DTLS | Altta ikinci, bağımsız şifreleme. |
| SHA-256 | Her dosya uçtan uca doğrulanır; tutmazsa kaydedilmez. |
| Alıcı kuralları | Onaysız yazma yok; dosya adı temizliği; klasör dışına yazma engeli; üzerine yazmama; `.jppart` + doğrulama sonrası yeniden adlandırma; istek/boyut sınırları. |
| Virüs taraması | JinjaPeer kontrolleri (her platform) + Microsoft Defender (Windows) + isteğe bağlı VirusTotal özet sorgusu. Tehdit varsa dosya karantinada, karar kullanıcının. |

## Testlerle kanıt

| İddia | Test |
| --- | --- |
| Değiştirilmiş / sahte imzalı kod reddedilir | `test/core_test.dart` → *a code signed by someone else…*, *round trip, signature and tamper detection* |
| MITM iki tarafa aynı kodu gösteremez | `test/core_test.dart` → *man-in-the-middle cannot make both sides show the same code* |
| Tekrar / kurcalanmış çerçeve reddedilir | `test/core_test.dart` → *keys match…*, *tampered frame is rejected* |
| Düşük dereceli anahtar, gzip bombası reddedilir | `test/core_test.dart` → *attack scenarios* |
| Çalınan davet ikinci kez kullanılamaz, başka davetin yanıtı geçmez | `integration_test/p2p_test.dart` → *stolen / replayed codes cannot hijack a connection* |
| Yanlış şifre bağlanamaz | `integration_test/p2p_test.dart` → *wrong password is refused* |
| Yol aşımı, Windows ayrılmış adları, RTL hilesi temizlenir | `test/core_test.dart` → *sanitize*, `test/ui_test.dart` → *incoming request…* |
| Spam / sınır / bozuk istekler reddedilir | `test/ui_test.dart` → *protocol limits* |
| Bağlantı koparsa yarım dosya kalmaz | `integration_test/p2p_test.dart` → *pause/resume and disconnect…* |
| Gizlenmiş program karantinaya alınır | `integration_test/p2p_test.dart` → *photos arrive bit-identical…*, `test/scanner_test.dart` |
| Defender gerçekten tarıyor | `integration_test/p2p_test.dart` → *Microsoft Defender engine flags the EICAR test file* |
| Fotoğraflar orijinal kalitede gider | `integration_test/p2p_test.dart` (EXIF dahil bayt bayt), `integration_test/cross_device_test.dart` (Windows → Android) |

## Bilinen sınırlar (dürüst liste)

- **Doğrulama kodu karşılaştırılmazsa** ve kodları taşıyan kanal (ör. ele geçirilmiş
  bir mesajlaşma hesabı) saldırganın kontrolündeyse araya girme mümkündür. Bu
  yüzden yeni kişilerde kodun sesli/yüz yüze karşılaştırılması önerilir. Kayıtlı
  kişilerde anahtar otomatik doğrulanır.
- Kimlik anahtarı cihazda uygulama klasöründe saklanır. Cihazın kendisi ele
  geçirilirse anahtar da ele geçer.
- Android'de ücretsiz yerel bir antivirüs motoru yoktur. Orada JinjaPeer
  kontrolleri ve (anahtar girilirse) VirusTotal özet sorgusu çalışır.
- Simetrik NAT arkasındaki iki cihaz TURN olmadan bağlanamayabilir. TURN
  kullanılsa bile veri uçtan uca şifreli kalır.
