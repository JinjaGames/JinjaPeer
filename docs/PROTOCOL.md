# JinjaPeer protokolü (v1)

Bu belge, ileride yazılacak **web istemcisinin** (toffeeshare.com benzeri) masaüstü ve
Android uygulamalarıyla aynı protokolü konuşabilmesi için kablo formatını tanımlar.
Web arayüzü henüz yok; bu yalnızca temel.

## 1. Taşıma

- WebRTC veri kanalı, etiket `jinjapeer`, `ordered: true`, yalnızca **ikili** mesajlar.
  Tarayıcılar bunu doğrudan destekler (`RTCPeerConnection.createDataChannel`).
- ICE: herkese açık STUN (`stun:stun.l.google.com:19302`, `stun:stun.cloudflare.com:3478`),
  isteğe bağlı TURN. ICE adayları SDP içine toplanır (trickle yok), en fazla 6 sn beklenir.
- Davet eden `offer`, katılan `answer` üretir.

## 2. Bağlantı kodları (sinyalleşme)

```
JP1I-<base64url(gzip(JSON{ "b": body, "s": base64url(Ed25519(body)) }))>   davet
JP1A-<…>                                                                   yanıt
```

`body` tam olarak imzalanan JSON metnidir:

| Alan | Açıklama |
| --- | --- |
| `app` | `"JinjaPeer"` |
| `v` | `1` |
| `k` | `"i"` davet, `"a"` yanıt |
| `sid` | 16 bayt oturum kimliği (base64url). Yanıt, davetin `sid`'ini kopyalar. |
| `sdp` | WebRTC SDP (ICE adayları dahil) |
| `ek` | 32 bayt X25519 geçici açık anahtar |
| `ik` | 32 bayt Ed25519 kimlik açık anahtarı |
| `n` | Görünen ad |
| `exp` | Son geçerlilik (Unix saniye). Davet ≤ 24 sa, yanıt 10 dk. |
| `pw` | Davet şifre istiyor mu |

Ayrıştırma kuralları: boşluk/satır sonları atılır; kodlanmış uzunluk ≤ 24 KiB;
açılmış uzunluk ≤ 96 KiB (gzip bombası koruması); imza `ik` ile doğrulanır.

**Web sürümü için not:** Web'de kod kopyala-yapıştır yerine bir "paylaşım bağlantısı"
kullanılacaksa, aynı JSON gövdeleri küçük bir sinyalleşme sunucusu ya da bağlantı
fragmanı (`#…`, sunucuya gitmez) üzerinden taşınabilir. Kriptografi ve çerçeve formatı
değişmeden kalır; yalnızca kodların taşınma yolu değişir.

## 3. Anahtar türetme

```
dh         = X25519(benim_ek_gizli, karşı_ek)
pw         = şifre varsa PBKDF2-HMAC-SHA256(şifre, salt = sid, 200000 tur, 32 bayt), yoksa boş
transcript = SHA-256("JinjaPeer/1 transcript" ‖ davet_body ‖ 0x00 ‖ yanıt_body)
okm        = HKDF-SHA256(ikm = dh ‖ pw, salt = transcript, info = "JinjaPeer/1 session keys", 64 bayt)
k_davet→yanıt = okm[0..32],  k_yanıt→davet = okm[32..64]
doğrulama  = Crockford-base32(HKDF-SHA256(dh, transcript, "JinjaPeer/1 verification", 10 bayt))[0..12]
             "XXXX-XXXX-XXXX" olarak gösterilir
```

## 4. Çerçeve

```
kablo:   [8 bayt sayaç, big-endian][ChaCha20 şifreli metin][16 bayt Poly1305 etiketi]
nonce:   4 sıfır bayt ‖ 8 bayt sayaç
```

Alıcı yalnızca tam olarak beklenen sonraki sayacı kabul eder. Tek bir hata bağlantıyı
kalıcı olarak kapatır. Çerçeve ≤ 160 KiB.

Düz metin:

| İlk bayt | İçerik |
| --- | --- |
| `0x01` | UTF-8 JSON kontrol mesajı |
| `0x02` | dosya parçası: `[16 bayt dosya kimliği][8 bayt konum, big-endian][veri ≤ 128 KiB]` |

**Web sürümü için not:** WebCrypto, X25519/Ed25519'u (modern tarayıcılarda) destekler
ama ChaCha20-Poly1305'i desteklemez. Web istemcisi `libsodium.js` (wasm) ile
`crypto_aead_chacha20poly1305_ietf` kullanmalıdır (aynı 12 baytlık nonce).

## 5. Kontrol mesajları

| `t` | Yön | Alanlar |
| --- | --- | --- |
| `hello` | iki yön | `v`, `name`, `app`. İlk başarılı çözülen çerçeve, anahtar onayıdır. |
| `ping` / `pong` | iki yön | `ts`. 5 sn'de bir; 40 sn yanıt yoksa bağlantı düşer. |
| `offer` | gönderen → alıcı | `req` (16 hex), `total`, `items: [{id (32 hex), name, dir, size}]` |
| `accept` / `reject` | alıcı → gönderen | `req`, `reason` (`user`, `busy`, `size`, `invalid`) |
| `fend` | gönderen → alıcı | `id`, `sha` (tüm parçaların SHA-256'sı, hex) |
| `fdone` | alıcı → gönderen | `id`, `ok`, `reason` (`hash`, `write`, `invalid`) |
| `cancel` | iki yön | `req`, isteğe bağlı `id` |
| `pause` / `resume` | iki yön | `req` |
| `bye` | iki yön | — |

Alıcı kuralları: en fazla 5 bekleyen istek/eş; istek başına ≤ 10 000 dosya; parçalar
sıralı gelmeli ve bildirilen boyutu aşmamalı; dosya adları ve klasörler temizlenir
(`lib/core/sanitize.dart`).

## 6. Platformdan bağımsız kod

| Modül | Web'de yeniden kullanılabilir mi? |
| --- | --- |
| `lib/core/crypto.dart`, `lib/core/secure_channel.dart` | Evet (saf Dart; web'de isolate yerine doğrudan çalıştırılır) |
| `lib/core/sanitize.dart`, `lib/core/format.dart` | Evet |
| `lib/core/codes.dart` | gzip için `dart:io` kullanır; web'de `package:archive` ile değiştirilmeli |
| `lib/services/peer_session.dart`, `transfer_service.dart` | Mantık aynı; dosya okuma/yazma (`dart:io`) web'de File API/indirme akışıyla değiştirilir |
| `lib/services/scanner.dart` | Sezgisel kontroller evet; Defender yok |
