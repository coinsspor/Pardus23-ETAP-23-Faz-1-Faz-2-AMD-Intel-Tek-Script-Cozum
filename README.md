# Vestel Akıllı Tahta — Dokunmatik Komple Çözüm

> **Pardus 23 / ETAP 23 | Faz-1 & Faz-2 | AMD & Intel | Tek Script**
>
> eta-touchdrv kurulum + kernel patch + kalibrasyon — hepsi otomatik

---

## Ne İşe Yarıyor?

MEB okullarındaki Vestel akıllı tahtalarda Pardus 23 ile yaşanan dokunmatik sorunlarını tek seferde çözer:

- Dokunmatik hiç çalışmıyor
- Bazen çalışıyor bazen çalışmıyor (özellikle AMD tahtalarda)
- Dokunma noktası kayık (1-2 cm offset)
- Çoklu dokunma çalışmıyor
- `xinput_calibrator` işe yaramıyor
- Kalibrasyon yaptım ama reboot'ta kayboluyor

---

## Hızlı Kurulum (2 Dakika)

### USB Belleğe Koy

```
USB Bellek/
├── vestel-dokunmatik-fix.sh       ← bu script
└── eta-touchdrv_X_X_X_amd64.deb  ← Pardus sürücü paketi (herhangi bir sürüm)
```

Sürücü paketi 0.3.5, 0.4.0, 0.5.0 veya hangi sürüm olursa olsun script otomatik tanır ve çalışır.

### Tahtada Çalıştır

USB belleği tak, dosyaya çift tıkla, "Konsolda Çalıştır" de. Hepsi bu.

Alternatif olarak terminal açıp:
```bash
bash vestel-dokunmatik-fix.sh
```

`sudo` yazmaya gerek yok. Script `etap+pardus!` ve diğer bilinen ETAP şifrelerini otomatik dener. Hiçbiri tutmazsa şifre sorar.

Sonunda "Reboot?" diye sorar → `e` yazın.

### Reboot Sonrası Dokunmatik Kayıksa

```bash
vestel-calibrate hafif       # 0.5-1 cm kayıklık
vestel-calibrate orta        # 1-2 cm kayıklık
vestel-calibrate buyuk       # 2+ cm kayıklık
vestel-calibrate sifirla     # sıfırla
vestel-calibrate donanim     # sensör GUI kalibrasyonu (4 noktaya dokun)
```

Bir kere ayarladınız mı kalıcıdır, her reboot'ta otomatik uygulanır.

---

## Script Ne Yapıyor? (8 Adım)

### 1. Sistem Tespiti
AMD mi Intel mi, hangi kernel, hangi Pardus sürümü, USB'de hangi dokunmatik sensör var — hepsini otomatik tespit eder.

### 2. Paket Kurulumu
USB bellekte veya sistemde bulunan `eta-touchdrv` `.deb` paketini kurar. Gerekli bağımlılıkları (`dkms`, `build-essential`, `linux-headers`, `xinput`) otomatik kurar. Eski sürüm kuruluysa önce temizler.

### 3. Kernel Modül Patch
Vestel'in sürücü paketindeki kernel modüllerinde birden fazla uyumluluk hatası var. Script kaynak kodu yerinde patch'ler:

- `raw_copy_from_user` → `copy_from_user` (deprecated API düzeltmesi)
- `raw_copy_to_user` → `copy_to_user`
- `asm/uaccess.h` → `linux/uaccess.h` (deprecated header)
- `strlcpy` → `strscpy` uyumluluk makrosu (kernel 6.8+ için)
- `class_create` tek parametre uyumluluğu (kernel 6.4+ için)
- DKMS `__VERSION__` placeholder düzeltmesi

Her patch uygulanmadan önce "zaten yapılmış mı" kontrol eder. v0.3.5'te bazı fix'ler zaten varsa onları atlar, v0.4.0'da eksik olanları ekler. Hangi sürüm olursa olsun doğru çalışır.

### 4. DKMS Derleme
Patch'lenmiş kaynak kodunu mevcut kernel için derler ve yükler. Kernel güncellendiğinde DKMS otomatik yeniden derler.

### 5. Servis Dosyaları
Vestel'in orijinal servis dosyalarındaki 3 kritik sorunu düzeltir:

**touchdrv_install yeniden yazıldı:**
- Orijinalde 1 deneme (v0.4.0) veya 3 deneme (v0.3.5) var — AMD'de USB geç tanınıyor, yetmiyor
- Düzeltilmiş: 15 deneme × 2 saniye = 30 saniye bekleme kapasitesi
- Device node oluşmasını da bekliyor (modprobe sonrası hemen daemon başlatmıyor)
- PID kilidi ile çift çalışma önleniyor

**systemd servisi düzeltildi:**
- `Restart=always` → `Restart=on-failure` (USB yoksa sonsuz döngü yapmaz)
- `StartLimitIntervalSec=120` + `StartLimitBurst=5` (rate limiting)
- `After=display-manager.service` (boot sırası düzeltildi)

**udev kurallarına device symlink eklendi:**
- `/dev/optictouch` → `/dev/IRTouchOptical000` (2-kameralı kalibrasyon aracının beklediği path)
- `/dev/OtdOpticTouch` → `/dev/OtdUsbRaw` (4-kameralı kalibrasyon aracının beklediği path)
- Bu symlink'ler olmadan Vestel'in kalibrasyon araçları "Device not found" hatası veriyor

### 6. Servis Başlatma
Dokunmatik servisini başlatır ve çalıştığını doğrular.

### 7. Kalibrasyon Sistemi
İki katmanlı kalibrasyon:

**Katman 1 — Sensör kalibrasyonu (donanım):**
Vestel'in kendi kalibrasyon aracı (`calibrationTools` veya `OtdCalibrationTool`) ile 4 noktaya dokunarak yapılır. Paramtreler sensör firmware'ine yazılır.

**Katman 2 — Yazılım kalibrasyonu (libinput matrix):**
`xinput` üzerinden `libinput Calibration Matrix` uygulanır. Bu matris `/etc/vestel-touch-calibration.conf` dosyasına kaydedilir. Her boot'ta ayrı bir systemd servisi (`vestel-touch-calibrate.service`) bu matrisi otomatik uygular.

Bu ikili yaklaşım sayesinde sensör kalibrasyonu kaybolsa bile yazılım kalibrasyonu her zaman kalıcıdır.

### 8. Masaüstü Kısayolları
Tüm kullanıcıların masaüstüne iki ikon bırakır:
- **"Dokunmatik Düzelt"** → ana scripti tekrar çalıştırır
- **"Dokunmatik Kalibrasyon"** → sensör kalibrasyonu GUI'si açar

---

## Neden Dokunmatik Çalışmıyor?

### Vestel Tahtalar Neden Farklı?

Normal dokunmatik ekranlar USB HID protokolü ile doğrudan "parmak x,y koordinatında" diye rapor eder. Linux çekirdeği bunu standart `hid-multitouch` modülü ile direkt anlar.

Vestel akıllı tahtalar ise **optik kamera sensörleri** kullanır. Ekranın kenarlarındaki kızılötesi kameralar parmağın gölgesini algılar ve ham veriyi USB üzerinden gönderir. Bu ham ışık verisini x,y koordinatına çevirmek için Vestel'in kendi userspace daemon'u şart.

Bu yüzden:
- `hid-multitouch` modülü tek başına çalışmaz
- `libinput` dokunmatik cihazı görmez
- `xinput_calibrator` çalışmaz (cihaz HID olmadığı için tanımıyor)
- Standart Pardus kurulumunda dokunmatik sürücüsü yoksa hiç çalışmaz

### İki Tahta Tipi

| | 2-Kameralı (Faz-1 siyah) | 4-Kameralı (Faz-2 gri) |
|---|---|---|
| USB Vendor:Product | `6615:0084–0c20` (IRTOUCH) | `2621:2201, 2621:4501` |
| Kernel modülü | `OpticalDrv.ko` | `OtdDrv.ko` |
| Daemon | `OpticalService` | `OtdTouchServer` |
| Device node | `/dev/IRTouchOptical000` | `/dev/OtdUsbRaw` |
| Kalibrasyon aracı | `calibrationTools` | `OtdCalibrationTool` |
| Multitouch | 2 parmak | 10 parmak |

Script her iki tipi de otomatik tespit eder ve doğru modül + daemon'u başlatır.

### Neden Bazen Çalışıyor Bazen Çalışmıyor?

Özellikle AMD tahtalarda: USB controller farklı zamanlama yapıyor, boot sırasında USB dokunmatik sensörü geç tanınıyor. Orijinal `touchdrv_install` scripti 1 kere bakıp bulamayınca çıkıyor. Bu script 15 kere 2 saniye arayla deniyor.

### Neden `xinput_calibrator` Çalışmıyor?

İki nedeni var:

Birincisi, Pardus 23 artık `libinput` sürücüsünü kullanıyor. `xinput_calibrator` ise `evdev` formatında çıktı veriyor (MinX/MaxX/MinY/MaxY). `libinput` bu formatı tanımıyor, onun yerine 3x3 kalibrasyon matrisi bekliyor. Bu script `libinput Calibration Matrix` ile çalışıyor.

İkincisi, Vestel tahtalar HID dokunmatik olmadığı için `xinput_calibrator` cihazı hiç görmüyor.

---

## Kalibrasyon Detayları

### Yazılım Kalibrasyonu (Hızlı)

Dokunmatik çalışıyor ama parmağınız bastığınız yerden 1-2 cm kayıyorsa:

```bash
vestel-calibrate hafif       # küçük kayıklık düzeltme
vestel-calibrate orta        # orta kayıklık düzeltme
vestel-calibrate buyuk       # büyük kayıklık düzeltme
vestel-calibrate sifirla     # fabrika ayarına dön
vestel-calibrate ters-x      # X ekseni ters (sağ-sol ters)
vestel-calibrate ters-y      # Y ekseni ters (üst-alt ters)
vestel-calibrate swap-xy     # X-Y eksenleri değiştir
```

Manuel matris de girebilirsiniz:
```bash
vestel-calibrate 1.05 0 -0.025 0 1.05 -0.025 0 0 1
```

### Donanım Kalibrasyonu (Sensör GUI)

```bash
vestel-calibrate donanim
```

Ekranda 4 nokta çıkar, sırayla dokunursunuz. Parametreler sensör firmware'ine yazılır.

Bu komut Vestel'in kendi araçlarını kullanır (`calibrationTools` veya `OtdCalibrationTool`). Script'in eklediği device symlink'leri sayesinde artık "Device not found" hatası vermez.

### Matris Nasıl Çalışıyor?

```
⎡ a  b  c ⎤       a = X ölçek (1.0 = normal)
⎢ d  e  f ⎥       e = Y ölçek (1.0 = normal)
⎣ 0  0  1 ⎦       c = X kaydırma (negatif = sola)
                    f = Y kaydırma (negatif = yukarı)
```

Fabrika ayarı (identity matrix): `1 0 0 0 1 0 0 0 1`

Kalibrasyon `/etc/vestel-touch-calibration.conf` dosyasına kaydedilir ve her reboot'ta systemd servisi tarafından otomatik uygulanır.

---

## Tüm Okula Dağıtım

### USB Bellek ile (Kolay)

1. Bir tahtada çalıştırın ve test edin
2. Aynı USB belleği diğer tahtalara götürün
3. Her tahtada çift tıkla → `e` → reboot
4. Kayıklık varsa `vestel-calibrate orta`

### SSH ile Toplu (İleri Düzey)

```bash
TAHTALAR="192.168.1.101 192.168.1.102 192.168.1.103"
for IP in $TAHTALAR; do
    scp vestel-dokunmatik-fix.sh eta-touchdrv*.deb root@$IP:/tmp/
    ssh root@$IP "bash /tmp/vestel-dokunmatik-fix.sh && reboot"
done
```

---

## Oluşturulan Dosyalar

| Dosya | Açıklama |
|-------|----------|
| `/usr/src/eta-touchdrv-*/touch2/OpticalDrv.c` | Patch'lenmiş 2-kameralı kernel modülü |
| `/usr/src/eta-touchdrv-*/touch4/OtdDrv.c` | Patch'lenmiş 4-kameralı kernel modülü |
| `/usr/bin/touchdrv_install` | Düzeltilmiş başlatma scripti |
| `/lib/systemd/system/eta-touchdrv.service` | Düzeltilmiş dokunmatik servisi |
| `/lib/udev/rules.d/60-eta-touchdrv.rules` | udev kuralları + device symlink'leri |
| `/etc/vestel-touch-calibration.conf` | Kalibrasyon matrisi |
| `/usr/local/bin/vestel-calibrate` | Hızlı kalibrasyon komutu |
| `/usr/local/bin/vestel-touch-apply.sh` | Boot kalibrasyon uygulama scripti |
| `/etc/systemd/system/vestel-touch-calibrate.service` | Kalibrasyon servisi |
| `/usr/local/bin/vestel-dokunmatik-fix.sh` | Ana scriptin sistem kopyası |
| `~/Masaüstü/dokunmatik-duzelt.desktop` | Masaüstü kısayolu |
| `~/Masaüstü/dokunmatik-kalibrasyon.desktop` | Kalibrasyon kısayolu |

---

## Sorun Giderme

### "Kaynak dizin yok" hatası
Script yanına `.deb` dosyasını koymayı unuttunuz. `eta-touchdrv_X_X_X_amd64.deb` dosyasını USB belleğe script ile yanyana koyun.

### "Derleme başarısız" hatası
Kernel headers eksik. İnternet bağlantısı varsa script otomatik kurar, yoksa:
```bash
apt install linux-headers-$(uname -r)
```

### Dokunmatik hala çalışmıyor
1. `lsusb` ile USB'de dokunmatik cihaz görünüyor mu kontrol edin
2. Görünmüyorsa fiziksel kontrol: USB kablo, OPS modülü, sensör ışıkları
3. `systemctl status eta-touchdrv.service` ile servis durumunu kontrol edin
4. `cat /var/log/vestel-dokunmatik-fix.log` ile log'a bakın

### Dokunmatik çalışıyor ama kayık
```bash
vestel-calibrate orta
```
Olmadıysa `buyuk` deneyin. Hala düzelmiyorsa:
```bash
vestel-calibrate donanim
```

### Reboot sonrası kalibrasyon kayboluyor
Normalde olmaması lazım çünkü iki servis var. Kontrol:
```bash
systemctl status vestel-touch-calibrate.service
cat /etc/vestel-touch-calibration.conf
```

---

## Versiyon Uyumluluğu

| | Destekleniyor |
|---|---|
| eta-touchdrv 0.3.5 | ✅ |
| eta-touchdrv 0.4.0~beta1 | ✅ |
| Gelecek sürümler (0.5.0, 1.0.0 vs.) | ✅ (patch'ler "zaten yapılmış mı" kontrol eder) |
| Pardus 23 (kernel 6.1.x) | ✅ |
| Pardus kernel güncellemeleri (6.5, 6.8+) | ✅ (uyumluluk makroları ile) |
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
