# eta-touchdrv Sürücü Analizi & Çözüm Planı

> Vestel Akıllı Tahta (Faz-1 / Faz-2) — Pardus 23 Dokunmatik Sorunları
> 
> Analiz Tarihi: 2026-03-12
> İncelenen Paketler: eta-touchdrv 0.3.5, eta-touchdrv 0.4.0~beta1

---

## 1. Mimari: Dokunmatik Nasıl Çalışıyor?

Vestel akıllı tahtalardaki dokunmatik, standart USB dokunmatik panellerden farklı çalışır. Normal bir dokunmatik ekran USB HID protokolü ile "parmak şurada" diye koordinat gönderir ve Linux çekirdeği bunu direkt anlar. Vestel tahtalar ise **optik kamera sensörleri** kullanır — ekranın kenarlarındaki kızılötesi kameralar parmağın gölgesini algılar ve ham veriyi USB üzerinden gönderir.

Bu ham verinin dokunma koordinatına çevrilmesi için bir **userspace daemon** gerekir. İşte bu yüzden standart `hid-multitouch` veya `libinput` tek başına çalışmaz.

### Veri Akışı

```
Parmak dokunur
    ↓
IR kamera sensörleri ham ışık verisini toplar
    ↓
USB üzerinden bilgisayara gönderir (vendor-specific protokol)
    ↓
Kernel modülü (OpticalDrv veya OtdDrv) USB verisini okur
    → /dev/IRTouchOptical000 veya /dev/OtdUsbRaw device node oluşturur
    ↓
Userspace daemon (OpticalService veya OtdTouchServer) device node'u açar
    → Ham veriyi okur
    → Koordinat hesaplar (kalibrasyon parametrelerine göre)
    → ioctl() ile kernel modülüne multitouch event gönderir
    ↓
Kernel modülü Linux input subsystem'e raporlar
    → input_mt_slot() + ABS_MT_POSITION_X/Y
    ↓
libinput / X11 dokunma olayını alır
    ↓
Ekranda tıklama gerçekleşir
```

### İki Farklı Tahta Tipi

| Özellik | 2-Kameralı (Faz-1 siyah) | 4-Kameralı (Faz-2 gri) |
|---------|--------------------------|------------------------|
| Kernel modülü | `OpticalDrv.ko` | `OtdDrv.ko` |
| Userspace daemon | `OpticalService` | `OtdTouchServer` |
| Device node | `/dev/IRTouchOptical000` | `/dev/OtdUsbRaw` |
| Kalibrasyon aracı | `calibrationTools` | `OtdCalibrationTool` |
| USB Vendor ID | `6615` (IRTOUCH) | `2621` (bilinmeyen üretici) |
| USB Product ID'leri | `0084, 0085, 0086, 0087, 0088, 0c20` | `2201, 4501` |
| Multitouch | 2 parmak | 10 parmak |
| Koordinat aralığı | 0 – 32767 | 0 – 32767 |
| Input protokolü | MT Type B (slot tabanlı) | MT Type B (slot tabanlı) |

---

## 2. Tespit Edilen Sorunlar

### SORUN 1: Kernel API Uyumsuzlukları (Derleme Hatası)

**v0.4.0 beta** paketinde **3 kritik** kernel uyumsuzluğu var:

**1a) `raw_copy_from_user` / `raw_copy_to_user`**
Her iki modülde toplam 9 yerde kullanılmış. Bu fonksiyonlar kernel 5.x'te deprecate edildi. Pardus 23'ün kernel'ında (6.1.x) hâlâ derleniyor olabilir ama güvenli değil ve gelecek güncellemelerde kırılacak. Doğrusu `copy_from_user` / `copy_to_user`.

**1b) `strlcpy` — kernel 6.8+'da kaldırıldı**
Her iki modülde `strlcpy` ve `strlcat` kullanılmış. Kernel 6.8 ile tamamen kaldırıldı, yerine `strscpy` geldi. Pardus 23 kernel 6.1 kullandığı için şu an çalışıyor ama kernel güncellemesi ile kırılacak.

İlginç olan: **v0.3.5 paketinde** bu düzeltme yapılmış (`#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 8, 0)` ile `strlcpy` → `strscpy` değişimi var), ama **v0.4.0 beta'da bu düzeltme yok**. Yani v0.4.0 bu konuda v0.3.5'ten geriye gitmiş.

**1c) `class_create(THIS_MODULE, name)` — kernel 6.4+'da değişti**
`OtdDrv.c` (4-kameralı modül) `class_create` fonksiyonunu iki parametreyle çağırıyor. Kernel 6.4'ten itibaren `THIS_MODULE` parametresi kaldırıldı, tek parametre alıyor. Pardus 23'te kernel 6.1 olduğu için şimdilik çalışıyor ama riskli.

**1d) `asm/uaccess.h` — deprecated header**
Her iki modülde `#include <asm/uaccess.h>` var. Doğrusu `linux/uaccess.h`. Bazı kernel versiyonlarında uyarı, bazılarında hata verir.

### SORUN 2: DKMS Versiyon Placeholder

`dkms.conf` dosyasında `PACKAGE_VERSION="__VERSION__"` yazıyor. Bu placeholder'ın paket oluşturma sırasında gerçek versiyonla değiştirilmesi gerekiyordu ama değiştirilmemiş. DKMS bu yüzden modülü yanlış versiyonla kaydedebilir veya hiç kaydedemeyebilir.

### SORUN 3: `touchdrv_install` Scripti Sorunları

**v0.4.0'da retry mekanizması kaldırılmış:** v0.3.5'te USB cihaz bulunamazsa 3 kere 0.5 saniye arayla deniyor. v0.4.0'da tek deneme var — USB tanıma gecikmeli olursa (özellikle boot sırasında) başarısız oluyor.

**Race condition:** Servis `Restart=always` ile çalışıyor. USB cihaz bulunamazsa script çıkıyor, systemd tekrar başlatıyor, tekrar bulamıyor — sonsuz döngüye giriyor. CPU ve log şişmesine neden olur.

**`set -e` ile `exec` kullanımı:** v0.3.5'te `exec /usr/bin/OtdTouchServer.$(uname -m)` ile daemon'u servis PID'si olarak başlatıyor (doğru). v0.4.0'da `exec` yok, daemon child process olarak başlıyor — servis daemon'u izleyemiyor.

### SORUN 4: Kalibrasyon Aracı Device Path Uyumsuzluğu

Kritik bir sorun: Kalibrasyon araçlarının beklediği device path'ler ile kernel modüllerinin oluşturduğu path'ler **farklı**:

| Araç | Beklediği Path | Kernel Modülünün Oluşturduğu Path |
|------|---------------|----------------------------------|
| `calibrationTools` | `/dev/optictouch` | `/dev/IRTouchOptical000` |
| `OtdCalibrationTool` | `/dev/OtdOpticTouch` | `/dev/OtdUsbRaw` |

Bu, kalibrasyon araçlarının "Error: No device found!" hatası vermesine ve çalışmamasına neden olur.

### SORUN 5: Kalibrasyon Kalıcılığı

`calibrationTools` kalibrasyon parametrelerini USB üzerinden `SET_CALIB_PARA_X/Y` ve `SET_DEVICE_CONFIG` ioctl'ları ile doğrudan sensör donanımına (firmware'e) yazıyor. Bu parametrelerin nereye kaydedildiği belirsiz:

- Sensörün kendi flash belleğine yazılıyorsa → kalıcıdır ama sensör reset olursa kaybolabilir
- RAM'de tutuluyorsa → her güç kesintisinde kaybolur
- `OtdTouchServer` kendi içinde `OtdStaticSaveFcbParameters` / `OtdStaticLoadCcbParameters` fonksiyonları var ama bunlar herhangi bir dosyaya yazmıyor (`/dev/OtdUsbRaw` dışında path referansı yok)

Bu, "kalibrasyon yapıyorum ama yeniden başlatınca bozuluyor" sorununun ana nedeni.

### SORUN 6: v0.3.5 ve v0.4.0 Arasındaki Karışıklık

v0.3.5 (Eylül 2025) bazı konularda v0.4.0 beta'dan (Nisan 2025) daha iyi:

| Özellik | v0.3.5 | v0.4.0 beta |
|---------|--------|-------------|
| strlcpy → strscpy fix | ✅ Var | ❌ Yok |
| linux/version.h include | ✅ Var | ❌ Yok |
| Retry mekanizması | ✅ 3 deneme | ❌ Tek deneme |
| OtdTouchServer | Statik linkli (978KB) | Dinamik linkli (88KB) |
| Servis After= | lightdm.service | Yok (race condition) |
| touchdrv_restart | ✅ Var | ❌ Kaldırılmış |

OtdTouchServer'ın v0.4.0'daki dinamik linkli versiyonu daha iyi (daha küçük, sistem kütüphanelerini kullanıyor) ama geri kalan her şey v0.3.5'te daha sağlam.

### SORUN 7: AMD vs Intel Farkı

Kaynak kodda AMD/Intel ayrımı yok — sürücü saf USB tabanlı, işlemciden bağımsız. Ama pratikte AMD tahtalarında sorun daha fazla çünkü:

- AMD'nin USB controller'ı farklı zamanlama yapıyor (USB enumeration daha yavaş)
- `touchdrv_install`'ın retry mekanizması yetersiz kalıyor
- Boot sırasında USB cihaz henüz hazır değilken servis başlıyor

---

## 3. Çözüm Planı

### A. Kernel Modüllerini Düzelt (Kaynak Kod Patch)

Her iki modüle (OpticalDrv.c ve OtdDrv.c) şu düzeltmeler uygulanacak:

1. `raw_copy_from_user` → `copy_from_user`
2. `raw_copy_to_user` → `copy_to_user`
3. `asm/uaccess.h` → `linux/uaccess.h`
4. `linux/version.h` ekleme + `strlcpy` → `strscpy` uyumluluk makrosu
5. `class_create` kernel 6.4+ uyumluluk makrosu
6. DKMS `__VERSION__` placeholder düzeltme

### B. `touchdrv_install` Scriptini Yeniden Yaz

- AMD için daha uzun retry (10 deneme, 2 saniye arayla)
- lsusb yerine `/sys/bus/usb/devices/` kontrolü (daha güvenilir)
- Daemon'u `exec` ile başlatma
- PID dosyası ile çift çalışma önleme
- USB hotplug desteği

### C. systemd Servisini Düzelt

- `After=display-manager.service` ekleme
- `Restart=on-failure` (always değil)
- `RestartSec=5s` (4s yerine)
- `StartLimitIntervalSec` ile sonsuz döngü önleme

### D. Device Path Symlink'leri Oluştur

Kalibrasyon araçlarının beklediği path'lere symlink:
- `/dev/optictouch` → `/dev/IRTouchOptical000`
- `/dev/OtdOpticTouch` → `/dev/OtdUsbRaw`

udev kuralı ile otomatik.

### E. Kendi Kalibrasyon Sistemimizi Yaz

Mevcut `calibrationTools` ve `OtdCalibrationTool` çalışsa bile kalibrasyon kalıcı olmuyor. Çözüm:

1. Kendi X11 kalibrasyon GUI'mizi yazacağız (Python + Xlib veya basit C)
2. 4/9/16 nokta kalibrasyon desteği
3. Hesaplanan matris `/etc/vestel-touch-calibration.conf` dosyasına kaydedilecek
4. Her boot'ta `xinput set-prop` ile matris uygulanacak
5. Ayrıca `OtdTouchServer`'ın koordinat dönüşümünü de patch'leyebiliriz

İki katmanlı kalibrasyon:
- **Katman 1 (donanım):** `calibrationTools` / `OtdCalibrationTool` ile sensör kalibrasyonu (çalışırsa)
- **Katman 2 (yazılım):** `libinput Calibration Matrix` ile Linux input seviyesinde düzeltme (her zaman çalışır, kalıcı)

### F. Tek Script Çözüm

Tüm yukarıdaki düzeltmeleri tek bir script'e entegre edeceğiz:

1. Sistemi teşhis et (AMD/Intel, tahta tipi, USB cihaz)
2. Kernel modül kaynaklarını patch'le ve DKMS ile derle
3. Düzeltilmiş `touchdrv_install` ve servis dosyalarını kur
4. Device symlink'leri oluştur
5. Kalibrasyon GUI'sini çalıştır
6. Kalibrasyon matrisini kaydet
7. Her boot'ta otomatik uygulama servisi kur

---

## 4. Dosya Referansı

### Kernel Modülleri (Kaynak Kod)
```
/usr/src/eta-touchdrv-VERSION/touch2/OpticalDrv.c    → 2-kameralı sürücü
/usr/src/eta-touchdrv-VERSION/touch2/OpticalDrv.h
/usr/src/eta-touchdrv-VERSION/touch4/OtdDrv.c        → 4-kameralı sürücü
/usr/src/eta-touchdrv-VERSION/touch4/OtdDrv.h
/usr/src/eta-touchdrv-VERSION/dkms.conf
```

### Binary Daemon'lar (Closed-source, Vestel tarafından sağlanmış)
```
/usr/bin/OpticalService          → 2-kameralı daemon (35KB, dinamik linkli)
/usr/bin/OtdTouchServer          → 4-kameralı daemon (88KB v0.4.0, 978KB v0.3.5)
/usr/bin/OtdCalibrationTool      → 4-kameralı kalibrasyon (93KB, X11 bağımlı)
/usr/bin/calibrationTools        → 2-kameralı kalibrasyon (44KB, X11 bağımlı)
/usr/bin/touchdrv_install        → Başlatma scripti
```

### Sistem Dosyaları
```
/lib/systemd/system/eta-touchdrv.service
/lib/udev/rules.d/60-eta-touchdrv.rules
```

### USB Device ID Tablosu
```
6615:0084  →  IRTOUCH 2-kamera tip 1
6615:0085  →  IRTOUCH 2-kamera tip 2
6615:0086  →  IRTOUCH 2-kamera tip 3
6615:0087  →  IRTOUCH 2-kamera tip 4
6615:0088  →  IRTOUCH 2-kamera tip 5
6615:0c20  →  IRTOUCH 2-kamera tip 6
2621:2201  →  4-kamera tip 1
2621:4501  →  4-kamera tip 2
```

---

## 5. Sonuç

Ana sorun şu: Vestel'in dokunmatik sensörleri standart HID değil, özel protokol kullanıyor. Bu yüzden `eta-touchdrv` paketi şart — ama paketin kendisi hem kernel uyumsuzlukları hem de mimari hatalar içeriyor. 

Scriptimiz hem bu paket sorunlarını düzeltecek, hem de kendi kalibrasyon sistemiyle kalıcı bir çözüm sağlayacak. Böylece USB bellekle tüm okuldaki tahtalara dağıtılabilir, AMD/Intel fark etmez, kernel güncellemelerinde kırılmaz.

---

*Hazırlayan: Fatih (coinsspor) & Claude*
*Kaynak: eta-touchdrv_0.3.5 ve eta-touchdrv_0.4.0~beta1 reverse engineering*
