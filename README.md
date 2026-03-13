# Vestel Akıllı Tahta — Dokunmatik Fix & Kalibrasyon

MEB okullarındaki Vestel akıllı tahtalarda (Faz-1 / Faz-2) Pardus 23 ile yaşanan dokunmatik sorunlarını çözer.

**İki bağımsız program:**
- **vestel-fix.sh** → Dokunmatik hiç çalışmıyorsa sürücü kurar
- **vestel-calibrate-gui.py** → Dokunmatik kayıksa 9 noktalı kalibrasyon yapar

İkisi birbirine bağımlı değil. Hangisine ihtiyacın varsa onu çalıştır. İnternetsiz çalışır.

---

## Flash Bellek İçeriği

```
USB Flash/
├── Dokunmatik-Fix.desktop           ← çift tıkla → sürücü kurulum
├── Dokunmatik-Kalibrasyon.desktop   ← çift tıkla → kalibrasyon
├── vestel-fix.sh                    ← sürücü kurulum scripti
├── vestel-calibrate-gui.py          ← kalibrasyon programı
└── eta-touchdrv_X_X_X_amd64.deb    ← Vestel sürücü paketi (herhangi sürüm)
```

---

## Dokunmatik Çalışmıyorsa (vestel-fix.sh)

### Ne Zaman Kullanılır?
Tahtada dokunmatik hiç tepki vermiyorsa.

### Nasıl Çalıştırılır?
Flash'taki **"Dokunmatik Fix"** ikonuna çift tıkla. Veya terminal açıp:
```bash
bash vestel-fix.sh
```

### Ne Yapar?
1. Flash'taki `.deb` paketini kurar
2. Kernel modüllerindeki hataları düzeltir ve derler (DKMS)
3. Servisi aktif eder
4. Reboot sorar → `e` yaz → dokunmatik gelir

### Ne Yapmaz?
- `touchdrv_install` ve `eta-touchdrv.service` dosyalarına **dokunmaz** (orijinali korur)
- `dpkg --purge` **yapmaz** (mevcut binary'leri silmez)
- Zaten kuruluysa tekrar kurmaz, zaten derlenmişse tekrar derlemez

### Kernel Patch Detayları
Vestel'in sürücü paketinde şu hatalar var, script otomatik düzeltir:

| Hata | Düzeltme |
|------|----------|
| `raw_copy_from_user` (deprecated) | `copy_from_user` |
| `asm/uaccess.h` (eski header) | `linux/uaccess.h` |
| `strlcpy` (kernel 6.8+'da kaldırıldı) | `strscpy` uyumluluk makrosu |
| `class_create` (kernel 6.4+ değişti) | Versiyon kontrollü makro |
| `dkms.conf` `__VERSION__` placeholder | Gerçek versiyon |

---

## Dokunmatik Kayıksa (vestel-calibrate-gui.py)

### Ne Zaman Kullanılır?
Dokunmatik çalışıyor ama parmağını bastığın yer ile imleç farklı yerde.

### Nasıl Çalıştırılır?
Flash'taki **"Dokunmatik Kalibrasyon"** ikonuna çift tıkla. Veya terminal açıp:
```bash
python3 vestel-calibrate-gui.py
```

### Kalibrasyon Ekranı

Siyah fullscreen ekran açılır, 9 artı işareti görünür:

```
  ×           ×           ×

  ×           ×           ×

  ×           ×           ×
```

- **Kırmızı büyük +** → aktif nokta, buraya dokun
- **Yeşil tik ✓** → tamamlanan nokta
- **Gri küçük +** → bekleyen nokta
- Üstte ilerleme çubuğu
- Dokunduğunda yeşil halka geri bildirimi
- 9 nokta tamamlanınca "TAMAMLANDI!" ekranı → otomatik kaydeder

### Teknik Detaylar

- **tkinter** tabanlı GUI — ek paket gerektirmez (python3-tk yoksa otomatik kurar)
- Dokunma verisini tkinter `<Button-1>` event'inden alır (evdev/raw okuma yok)
- **Kalibrasyon başlamadan önce matrisi otomatik sıfırlar** — bozuk matris üzerinden bozuk veri gelmesini önler
- **ESC ile iptal edilirse** önceki kayıtlı kalibrasyonu geri yükler
- Matris least-squares yöntemi ile hesaplanır (3x3 affine transformation)
- Koordinat aralığı: 0-65535 (Vestel optik sensör)

### Kalibrasyon Nereye Kaydedilir?

```
/etc/vestel-touch-calibration.conf    ← matris değerleri
```

Bu dosya `dpkg -i` ile bile silinmez. Pardus güncellemesi dokunmaz.

### Reboot Sonrası Ne Olur?

Program ilk çalıştırıldığında boot servisi kurar:

```
/usr/local/bin/vestel-touch-apply.sh           ← kalibrasyon uygulama scripti
/etc/systemd/system/vestel-touch-calibrate.service  ← boot servisi
```

Her açılışta otomatik olarak kaydedilmiş matrisi `xinput` ile uygular. Bir kere kalibrasyon yaptın mı bir daha uğraşmazsın.

### Tekrar Kalibrasyon Ne Zaman Gerekir?
- Dokunmatik sensör değiştirildiyse
- Tahta duvardan indirilip farklı açıyla takıldıysa
- Pardus sıfırdan format atıldıysa

---

## Şifre / Root İzni

Her iki program da root yetkisi gerektirir. Ama `sudo` yazmana gerek yok — bilinen ETAP şifrelerini otomatik dener:

`etap+pardus!` · `etap+pardus` · `pardus` · `etapadmin` · `123456` · `pardus23` · `etap23`

Hiçbiri tutmazsa şifre sorar (3 deneme). Çoğu tahtada şifre sorulmaz.

---

## Çift Tıklama

Flash'taki `.desktop` dosyaları sayesinde konsol açmadan çift tıkla çalıştırılır. İlk seferde XFCE "Güvenilmeyen uygulama" uyarısı çıkarsa "Çalıştır" de.

---

## Desteklenen Tahtalar

| | Durum |
|---|---|
| Faz-1 siyah tahtalar (2 kamera, USB `6615:xxxx`) | ✅ |
| Faz-2 gri tahtalar (4 kamera, USB `2621:xxxx`) | ✅ |
| AMD işlemcili tahtalar | ✅ |
| Intel işlemcili tahtalar | ✅ |
| eta-touchdrv 0.3.5 | ✅ |
| eta-touchdrv 0.4.0 ve sonrası | ✅ |
| Pardus 23 kernel 6.1 – 6.12+ | ✅ |

---

## Tüm Okula Dağıtım

1. Flash'ı tak
2. "Dokunmatik Fix" çift tıkla → `e` → reboot
3. Gerekiyorsa "Dokunmatik Kalibrasyon" çift tıkla → 9 noktaya dokun
4. Sonraki tahtaya geç

Her tahta 3-5 dakika.

---

## Neden Standart Araçlar Çalışmıyor?

Vestel tahtalar standart USB HID dokunmatik değil — optik kamera sensörleri kullanıyor. Ham ışık verisini koordinata çevirmek için Vestel'in kendi daemon'u (`OtdTouchServer` / `OpticalService`) şart. Bu yüzden:

- `hid-multitouch` tek başına çalışmaz
- `xinput_calibrator` cihazı görmez
- `libinput` dokunmatik olarak tanımaz

`eta-touchdrv` paketi kernel modülü (USB iletişim) + userspace daemon (koordinat hesaplama) sağlar. Bizim scriptimiz bu paketi kurar, kernel uyumluluk hatalarını düzeltir ve kalibrasyon yapabilmemizi sağlar.

---

## Dosya Listesi

### Flash'taki Dosyalar
| Dosya | Boyut | Açıklama |
|-------|-------|----------|
| `vestel-fix.sh` | ~4 KB | Sürücü kurulum scripti |
| `vestel-calibrate-gui.py` | ~14 KB | Kalibrasyon GUI programı |
| `eta-touchdrv_*.deb` | ~1 MB | Vestel sürücü paketi |
| `Dokunmatik-Fix.desktop` | ~0.3 KB | Çift tıklama ikonu (fix) |
| `Dokunmatik-Kalibrasyon.desktop` | ~0.3 KB | Çift tıklama ikonu (kalibrasyon) |
| `README.md` | — | Bu dosya |

### Kalibrasyon Programının Sisteme Kurduğu Dosyalar
| Dosya | Açıklama |
|-------|----------|
| `/etc/vestel-touch-calibration.conf` | Kalibrasyon matrisi (kalıcı) |
| `/usr/local/bin/vestel-touch-apply.sh` | Boot'ta kalibrasyon uygulama scripti |
| `/etc/systemd/system/vestel-touch-calibrate.service` | Boot servisi |
| `/etc/sudoers.d/vestel-touch` | Şifresiz çalışma yetkisi |

---

## Lisans

MIT — Serbestçe kullanabilir, değiştirebilir ve dağıtabilirsiniz.

## İletişim

- **GitHub:** [coinsspor](https://github.com/coinsspor)
- **Twitter:** [@coinsspor](https://twitter.com/coinsspor)
- **Web:** [coinsspor.com](https://coinsspor.com)
