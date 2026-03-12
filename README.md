# Vestel Akıllı Tahta — Dokunmatik Komple Çözüm

> **Pardus 23 / ETAP 23 | Faz-1 & Faz-2 | AMD & Intel | Tek Script**

Vestel akıllı tahtalardaki dokunmatik sorunlarını USB flash bellek ile tek seferde çözer. Sürücü kurulumu, kernel hata düzeltmeleri, 9 noktalı kalibrasyon ve kalıcı kayıt — hepsi otomatik.

---

## Flash Belleğe Ne Koyacağız?

```
USB Flash Bellek/
├── vestel-dokunmatik-fix.sh         ← ana script (zorunlu)
├── vestel-calibrate-gui.py          ← kalibrasyon GUI (zorunlu)
└── eta-touchdrv_X_X_X_amd64.deb    ← sürücü paketi (zorunlu)
```

Bu üç dosya yan yana olacak. Sürücü paketi hangi sürüm olursa olsun çalışır (0.3.5, 0.4.0, 0.5.0...).

---

## Tahtada Ne Yapacağız?

### Adım 1: Flash belleği tak

USB belleği tahtaya tak. Dosya yöneticisi açılırsa kapat.

### Adım 2: Script'i çalıştır

`vestel-dokunmatik-fix.sh` dosyasına **çift tıkla** → **"Konsolda Çalıştır"** de.

Veya terminal açıp:
```
bash /media/kullanici/FLASH/vestel-dokunmatik-fix.sh
```

### Adım 3: Şifre

Script root yetkisini **otomatik alır**. Şifre sorulmaz çünkü script bilinen ETAP şifrelerini kendisi dener:

- `etap+pardus!`
- `etap+pardus`
- `pardus`
- `etapadmin`
- `123456`
- `pardus23`
- `etap23`

Bu şifrelerden biri tutarsa direkt çalışır, ekranda sadece "Root olarak başlatılıyor..." yazar.

Hiçbiri tutmazsa 3 kere şifre sorar. Şifreyi girin, devam eder.

Yani: **çoğu tahtada şifre sorulmaz, otomatik geçer.**

### Adım 4: Kurulum (otomatik)

Script sırayla şunları yapar (1-2 dakika sürer):

1. Sistemi tespit eder (AMD/Intel, Faz-1/Faz-2)
2. Flash'taki `.deb` paketini kurar
3. Kernel modüllerindeki hataları düzeltir ve derler
4. Dokunmatik servisini kurar ve başlatır
5. Kalibrasyon GUI'yi sisteme kopyalar

Ekranda her adımda yeşil ✓ işaretleri görürsünüz. Hata olursa sarı ⚠ veya kırmızı ✗ ile bildirir.

### Adım 5: Kalibrasyon

Kurulum bitince sorar: **"Kalibrasyon yapmak ister misiniz? (e/h)"**

`e` yazın. Ekran siyaha döner, 9 tane artı işareti (+) çıkar:

```
  ×           ×           ×
  
  
  ×           ×           ×
  
  
  ×           ×           ×
```

Sırayla her artı işaretinin **tam ortasına parmağınızla dokunun**. Aktif nokta kırmızı ve büyük, dokunduğunuzda yeşil tik'e dönüyor. 9 noktanın hepsine dokunduktan sonra ekranda "KALİBRASYON TAMAMLANDI!" yazar ve otomatik kaydeder.

### Adım 6: Reboot

Kalibrasyon bittikten sonra sorar: **"Reboot? (e/h)"**

`e` yazın, tahta yeniden başlar. Açıldığında dokunmatik kalibrasyonlu çalışır.

**Hepsi bu kadar.**

---

## Yeniden Başlatınca Ne Olur?

Bir kere kurulum ve kalibrasyon yaptıktan sonra bir daha uğraşmaya gerek yok. Tahta her açıldığında otomatik olarak:

1. `eta-touchdrv.service` → dokunmatik sürücüsünü başlatır
2. `vestel-touch-calibrate.service` → kayıtlı kalibrasyon matrisini uygular

Kalibrasyon `/etc/vestel-touch-calibration.conf` dosyasında saklanır. Bu dosya silinmediği sürece kalıcıdır. Pardus güncellemesi bile silmez.

**Tekrar kalibrasyon sadece şu durumlarda gerekir:**
- Dokunmatik sensör değiştirildiyse
- Tahta duvardan indirilip farklı açıyla tekrar takıldıysa
- Pardus sıfırdan format atıldıysa

O zaman masaüstündeki **"Dokunmatik Kalibrasyon"** ikonuna çift tıklamak yeterli.

---

## Şifre / Root İzni Detayları

### İlk kurulumda (vestel-dokunmatik-fix.sh)

Root yetkisi gerekir çünkü script sürücü kuruyor, kernel modülü derliyor ve sistem dosyaları oluşturuyor. Ama kullanıcının `sudo` yazmasına gerek yok:

1. Önce şifresiz sudo dener (NOPASSWD ayarı varsa)
2. Sonra bilinen 7 ETAP şifresini sırayla dener
3. Hiçbiri tutmazsa `su root` ile de dener
4. O da olmazsa 3 kere şifre sorar
5. 3 denemede de yanlışsa hata verir ve çıkar

### Sonraki kullanımlarda (vestel-calibrate, kalibrasyon ikonu)

İlk kurulumda script sudoers kuralı ekler. Bu sayede sonraki kalibrasyon komutları da şifre sormaz:
```
ALL ALL=NOPASSWD: /usr/local/bin/vestel-touch-apply.sh, /usr/local/bin/vestel-calibrate, /usr/local/bin/vestel-dokunmatik-fix.sh
```

### Kalibrasyon GUI (vestel-calibrate-gui.py)

GUI'yi direkt çalıştırmaya gerek yok — `vestel-calibrate donanim` komutu veya masaüstü ikonu otomatik çalıştırır. Ama elle çalıştırmak isterseniz o da bilinen şifreleri otomatik dener.

**Özet: Hiçbir aşamada kullanıcıdan `sudo` yazması beklenmez.**

---

## Hızlı Kalibrasyon Komutları

Reboot sonrası dokunmatik çalışıyor ama hafif kayıksa, GUI'ye gerek yok:

```
vestel-calibrate hafif       # 0.5-1 cm kayıklık
vestel-calibrate orta        # 1-2 cm kayıklık
vestel-calibrate buyuk       # 2+ cm kayıklık
vestel-calibrate sifirla     # fabrika ayarı
vestel-calibrate ters-x      # sağ-sol ters
vestel-calibrate ters-y      # üst-alt ters
vestel-calibrate swap-xy     # X-Y eksenleri değiştir
vestel-calibrate donanim     # 9 noktalı GUI kalibrasyon
```

Bu komutlar da şifre sormaz (sudoers kuralı sayesinde).

---

## Tüm Okula Dağıtım

Aynı USB belleği tüm tahtalara götürün:

1. Flash'ı tak
2. Çift tıkla
3. `e` → kalibrasyon yap → `e` → reboot
4. Sonraki tahtaya geç

Her tahtada 3-4 dakika sürer.

---

## Sorun Giderme

### Script çalışmıyor / izin hatası
Dosya yöneticisinde çift tıklayıp "Konsolda Çalıştır" seçin. Olmazsa terminal açıp `bash /media/.../vestel-dokunmatik-fix.sh` yazın.

### "Kaynak dizin yok" hatası
Flash'a `.deb` dosyasını koymayı unuttunuz.

### "Derleme başarısız" hatası
İnternet bağlantısı lazım (ilk seferde `linux-headers` paketi indirmek için). Sonraki tahtalarda internet gerekmez.

### Dokunmatik hiç çalışmıyor (kurulumdan sonra bile)
1. `lsusb` ile USB sensör görünüyor mu bakın
2. Görünmüyorsa: tahtanın arkasındaki USB kabloyu çıkarıp takın
3. OPS modülünün üst kısmına hafifçe vurun
4. Güç kablosunu çekin, güç tuşuna 30 saniye basın, 5 dakika bekleyin

### Kalibrasyon GUI açılmıyor
Flash'a `vestel-calibrate-gui.py` koymayı unuttunuz. Koymadan script çalıştırdıysanız, dosyayı flash'a koyup `vestel-calibrate donanim` komutunu çalıştırın — otomatik bulur ve kurar.

### Dokunmatik çalışıyor ama kayık
`vestel-calibrate donanim` ile 9 noktalı kalibrasyon yapın. Daha basit çözüm: `vestel-calibrate orta` deneyin.

---

## Script Ne Düzeltiyor?

Vestel'in resmi `eta-touchdrv` paketinde şu sorunlar var, script hepsini otomatik düzeltir:

| Sorun | Açıklama | Düzeltme |
|-------|----------|----------|
| Kernel API hataları | `raw_copy_from_user` deprecated | `copy_from_user` ile değiştirilir |
| Header hatası | `asm/uaccess.h` eski | `linux/uaccess.h` ile değiştirilir |
| Kernel 6.8+ uyumsuzluk | `strlcpy` kaldırıldı | `strscpy` uyumluluk makrosu eklenir |
| Kernel 6.4+ uyumsuzluk | `class_create` parametre değişti | Versiyon kontrolü ile uyumlu hale getirilir |
| AMD'de dokunmatik gelmeme | `touchdrv_install` tek deneme | 15 deneme × 2 saniye retry eklenir |
| Sonsuz döngü | `Restart=always` | `Restart=on-failure` + rate limit |
| Kalibrasyon aracı hata | Device path uyumsuzluğu | udev symlink'leri eklenir |
| Kalibrasyon kaybolması | Matris kalıcı değil | Dosyaya kaydet + boot servisi |

---

## Dosya Listesi

### Flash'taki Dosyalar (3 adet)
| Dosya | Açıklama |
|-------|----------|
| `vestel-dokunmatik-fix.sh` | Ana kurulum scripti |
| `vestel-calibrate-gui.py` | 9 noktalı kalibrasyon GUI |
| `eta-touchdrv_X_X_X_amd64.deb` | Vestel dokunmatik sürücü paketi |

### Script'in Sisteme Kurduğu Dosyalar
| Dosya | Açıklama |
|-------|----------|
| `/usr/local/bin/vestel-dokunmatik-fix.sh` | Ana scriptin sistem kopyası |
| `/usr/local/bin/vestel-calibrate` | Hızlı kalibrasyon komutu |
| `/usr/local/bin/vestel-calibrate-gui.py` | Kalibrasyon GUI |
| `/usr/local/bin/vestel-touch-apply.sh` | Boot kalibrasyon uygulama |
| `/etc/vestel-touch-calibration.conf` | Kalibrasyon matrisi (kalıcı) |
| `/etc/systemd/system/vestel-touch-calibrate.service` | Boot kalibrasyon servisi |
| `/etc/sudoers.d/vestel-touch` | Şifresiz çalışma yetkisi |
| `/lib/systemd/system/eta-touchdrv.service` | Dokunmatik sürücü servisi (düzeltilmiş) |
| `/lib/udev/rules.d/60-eta-touchdrv.rules` | USB tanıma + device symlink'leri |
| `/usr/bin/touchdrv_install` | Sürücü başlatma scripti (düzeltilmiş) |
| `~/Masaüstü/dokunmatik-duzelt.desktop` | Masaüstü kısayolu |
| `~/Masaüstü/dokunmatik-kalibrasyon.desktop` | Kalibrasyon kısayolu |

---

## Uyumluluk

| | Durum |
|---|---|
| eta-touchdrv 0.3.5 | ✅ Çalışır |
| eta-touchdrv 0.4.0~beta1 | ✅ Çalışır |
| Gelecek sürümler | ✅ Çalışır (patch'ler "zaten yapılmış mı" kontrol eder) |
| Pardus 23 (kernel 6.1) | ✅ |
| Kernel 6.4+ güncellemeler | ✅ (class_create uyumluluk makrosu) |
| Kernel 6.8+ güncellemeler | ✅ (strlcpy→strscpy uyumluluk makrosu) |
| AMD işlemcili tahtalar | ✅ (15 deneme retry) |
| Intel işlemcili tahtalar | ✅ |
| Faz-1 siyah tahtalar (2 kamera) | ✅ |
| Faz-2 gri tahtalar (4 kamera) | ✅ |

---

## Lisans

MIT — Serbestçe kullanabilir, değiştirebilir ve dağıtabilirsiniz.

## İletişim

- **GitHub:** [coinsspor](https://github.com/coinsspor)
- **Twitter:** [@coinsspor](https://twitter.com/coinsspor)
- **Web:** [coinsspor.com](https://coinsspor.com)
