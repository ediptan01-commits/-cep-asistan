# CepAsistan güncelleme kiti

Bu kit mevcut `cep-asistan` deposundaki `lib/main.dart` ve GitHub Actions iş akışları için başlangıç sürümüdür. Özellikler: cihazda saklanan notlar/görevler/hatırlatıcılar/bütçe kayıtları, yerel bildirimler, fotoğraftan PDF oluşturup paylaşma, hesaplama araçları, AI istemcisi ve mağaza ürünlerini sorgulayan Pro ekranı.

## GitHub'a aktarma
1. Depoda `lib/main.dart` dosyasını aç, içeriğini bu paketteki `lib/main.dart` ile değiştir ve commit et.
2. `.github/workflows/build-android.yml` dosyasını aynı adlı dosyayla değiştir.
3. `.github/workflows/build-ios.yml` dosyasını yeni dosya olarak ekle.
4. `server/` klasörünü de depoya ekle.
5. Actions > CepAsistan Android APK > Run workflow ile Android test APK'sı üret.

İş akışları Flutter projesini sunucuda oluşturduğu için `pubspec.yaml` repoda tutulmuyor; paketler iş akışında ekleniyor.

## AI sunucusu
`server/` dizininde:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export AI_API_KEY='SAĞLAYICININ_API_ANAHTARI'
export AI_MODEL='gpt-4o-mini'
uvicorn main:app --host 0.0.0.0 --port 8000
```

Sunucuyu HTTPS arkasında internete dağıtın; `AI_API_KEY` yalnızca sunucu ortam değişkeni olarak kalmalı. Ardından `.github/workflows/build-android.yml` ve `build-ios.yml` dosyalarındaki `AI_ENDPOINT` değerini `https://SUNUCU-ADRESINIZ/chat` olarak değiştirin. Ücretsiz kota örnekte günlük 5, Pro için 100 olarak taslaklanmıştır. **Bu sunucu örneği üretim için tek başına yeterli değildir:** kota bellekte tutulur ve `x-user-id` istemciden geldiği için kolayca taklit edilebilir. Üretimde kullanıcı kimlik doğrulaması, veritabanı/Redis tabanlı kota, hız sınırlama, abuse koruması, gizlilik politikası ve izleme ekleyin. Pro durumu istemciden gelen `pro` alanına güvenerek verilmemeli; mağaza makbuzu sunucuda doğrulanmalıdır.

## Bildirimler ve depolama
- İlk sürüm verileri cihazdaki SharedPreferences içinde tutar. Uygulama kaldırılırsa yerel kayıtlar kaybolabilir; cihazlar arası senkronizasyon yoktur.
- Android 13+ bildirim izni gerekir. Üretim sürümünde yeniden başlatma sonrası bildirimlerin sürdürülmesi ve pil optimizasyonları gerçek cihazlarda test edilmelidir.
- Bu örnek Türkiye saat dilimi (`Europe/Istanbul`) kullanır. Başka bölgeler için dinamik saat dilimi algılama ekleyin.

## Gerçek Pro satın alma
Ürün kimlikleri örnek olarak `cepasistan_pro_monthly` ve `cepasistan_pro_yearly` kullanır. Bunları Google Play Console ve App Store Connect'te oluşturup abonelik/base plan ayarlarını yapın. StoreKit/Play test kullanıcılarıyla satın alma, iptal, bekleyen işlem, geri yükleme, yenileme ve iade senaryolarını test edin. Kod, mağazadan ürünleri sorgular ve satın alma akışını başlatır; **güvenli Pro yetkilendirmesi için sunucu taraflı makbuz doğrulaması eklenmeden uygulamayı ücretli özellikler için yayınlamayın.**

## iOS derlemesi
`build-ios.yml` imzasız simülatör derlemesi üretir; bu iPhone'a doğrudan yüklenebilir IPA değildir. Gerçek iPhone/Store yayını için Apple Developer hesabı, sertifika/provisioning, App Store Connect ve imzalı archive/export adımları gerekir.

## Test listesi
1. Not ekle/sil ve uygulamayı yeniden aç.
2. Görev ekle, tamamla, sil.
3. Gelecekteki bir saat için hatırlatıcı kur; izni ver ve bildirimi kontrol et.
4. Gelir/gider ekle; bakiye hesabını doğrula.
5. Fotoğraf seçip PDF oluştur ve paylaş.
6. Hesap makinesinde sıfıra bölme ve ondalık girişini dene.
7. AI sunucusu yokken kullanıcıya açık hata gösterildiğini; sunucu bağlanınca yanıt ve kota davranışını kontrol et.
8. Play/App Store sandbox satın alma ve geri yükleme testlerini yap.
