# Vestel Akıllı Tahta — Dokunmatik Tam Otomatik Düzeltme

> **Pardus 23 / ETAP 23 | Faz-1 & Faz-2 | AMD & Intel | Tek Script Çözüm**
>
> `xinput_calibrator` yerine `libinput Calibration Matrix` tabanlı modern çözüm

---

## Sorun Ne?

MEB okullarındaki Vestel akıllı tahtalara Pardus 23 kurulduğunda dokunmatik ekranla ilgili şu sorunlar yaşanıyor:

- Dokunmatik hiç çalışmıyor
- Dokunma noktası kayık (1-2 cm fark var)
- Bazen çalışıyor bazen çalışmıyor
- Çoklu dokunma (multitouch) çalışmıyor

**Neden `xinput_calibrator` işe yaramıyor?**

Pardus 23 artık `libinput` sürücüsünü kullanıyor. Eski `xinput_calibrator` ise `evdev` formatında çıktı veriyor (MinX/MaxX/MinY/MaxY). libinput bu formatı tanımıyor — onun yerine 3x3 "Calibration Matrix" istiyor. Yani ikisi farklı dil konuşuyor, bu yüzden `xinput_calibrator` ile ne yaparsanız yapın sonuç değişmiyor.

Bu script tamamen `libinput Calibration Matrix` tabanlı çalışıyor ve sorunu kökünden çözüyor.

---

## Nasıl Kullanılır?

### Tek Adım: USB Belleğe Kopyala → Tahtada Çift Tıkla

1. `vestel-dokunmatik-fix.sh` dosyasını USB belleğe kopyalayın
2. USB belleği tahtaya takın
3. Dosyaya çift tıklayın → **"Konsolda Çalıştır"** deyin
4. Script her şeyi otomatik yapar
5. Sonunda **"Yeniden başlatmak ister misiniz?"** diye sorar → **e** yazın

Hepsi bu kadar. `sudo` yazmaya, şifre girmeye gerek yok.

Alternatif olarak terminal açıp şunu da yazabilirsiniz:
```bash
bash vestel-dokunmatik-fix.sh
```

---

## Script Adım Adım Ne Yapıyor?

### Aşama 1 — Otomatik Yetki Alma

Script root yetkisi gerektiğini bilir ve kendisi halleder:

- Önce `etap+pardus!` şifresini dener
- Tutmazsa diğer bilinen ETAP şifrelerini dener (`etap+pardus`, `pardus`, `etapadmin`, `123456`, `pardus23`, `etap23`)
- `sudo` ile olmadıysa `su root` ile dener
- Hiçbiri tutmazsa 3 kere şifre sorar
- Hiçbir durumda takılıp kalmaz

### Aşama 2 — Sistem Teşhisi

- Tahtanın AMD mi Intel mi olduğunu tespit eder
- Pardus versiyonunu, kernel sürümünü kontrol eder
- Display server tipini (X11/Wayland) belirler

### Aşama 3 — USB Dokunmatik Cihaz Tespiti

- USB'ye bağlı tüm cihazları tarar
- Klavye ve mouse'u otomatik olarak atlar (USB'de takılı olsa bile sorun çıkarmaz)
- Sadece dokunmatik çipsetlerini bulur: eGalax, ILITEK, Weida, PixArt, ELAN, Goodix, SiS, Atmel, IRTOUCH, GeneralTouch
- Hiçbir bilinen çip bulamazsa genel HID cihazlara da bakar

### Aşama 4 — Sürücü ve Paket Kurulumu

Eksik olan her şeyi otomatik kurar:

- `xinput` — dokunmatik cihaz yönetimi
- `libinput-tools` — modern dokunmatik sürücü araçları
- `xserver-xorg-input-libinput` — X11 libinput sürücüsü
- `evtest` — dokunmatik test aracı

Kernel modüllerini yükler ve kalıcı yapar:

- `usbhid` — USB insan arabirimi sürücüsü
- `hid-multitouch` — çoklu dokunma desteği
- `hid-generic` — genel HID desteği

Bu modüller Pardus 23'te bazen yüklü gelmiyor — script bunu halleder ve `/etc/modules` dosyasına ekleyerek her açılışta otomatik yüklenmesini sağlar.

### Aşama 5 — Giriş Cihazı Eşleştirme

İki farklı yöntemle dokunmatik cihazı bulur:

1. **xinput** — X11 seviyesinde dokunmatik cihazı arar
2. **/dev/input/event*** — Kernel seviyesinde ABS (absolute positioning) özelliği olan cihazları tarar

Bazen USB'de görünüyor ama X11'de tanınmıyor — her iki katmana da bakarak bu durumu yakalar.

### Aşama 6 — Yapılandırma Dosyaları

Üç kritik dosya oluşturur:

**X11 yapılandırma** (`/etc/X11/xorg.conf.d/99-vestel-touchscreen.conf`):
- Tüm dokunmatik cihazları libinput sürücüsüne bağlar
- eGalax, ILITEK, Goodix için ayrı ayrı özel kurallar tanımlar
- Kalibrasyon matrisini uygular

**udev kuralları** (`/etc/udev/rules.d/99-vestel-touchscreen.rules`):
- Vestel'in kullandığı 10+ farklı dokunmatik çipset üreticisini vendor ID'leriyle tanıtır
- Cihaz takıldığında otomatik olarak "dokunmatik" olarak işaretler
- Kalibrasyon matrisini udev seviyesinde uygular

**Kalibrasyon dosyası** (`/etc/vestel-touch-calibration.conf`):
- Dokunmatik kalibrasyon matrisini saklar
- Tüm diğer dosyalar bu merkezi dosyadan okur

### Aşama 7 — Kalıcı Açılış Servisi

"Bugün çalışıyor yarın çalışmıyor" sorununu çözmek için iki mekanizma kurar:

**systemd servisi** (`vestel-touch-fix.service`):
- Display manager başladıktan sonra çalışır
- Dokunmatik cihazı bulur ve kalibrasyon matrisini uygular
- İlk denemede bulamazsa HID modüllerini reload edip tekrar dener
- `/var/log/vestel-dokunmatik-fix.log` dosyasına kayıt tutar

**XDG autostart** (yedek mekanizma):
- Kullanıcı oturumu açıldığında da çalışır
- systemd servisi herhangi bir nedenle başarısız olursa devreye girer

Her iki mekanizma da sudoers kuralıyla parola sormadan çalışır.

### Aşama 8 — Anlık Düzeltme

Reboot beklemeden hemen dokunmatik ayarlarını uygular. Script bitmeden dokunup test edebilirsiniz.

### Aşama 9 — Masaüstü Kısayolları

Tüm kullanıcıların masaüstüne iki ikon bırakır:

- **"Dokunmatik Düzelt"** — ana scripti tekrar çalıştırır
- **"Dokunmatik Kalibrasyon"** — hızlı kalibrasyon komutunu açar

XFCE'deki "Güvenilmeyen uygulama" uyarısını da otomatik olarak atlar.

### Aşama 10 — Reboot

Script sonunda "Yeniden başlatmak ister misiniz?" diye sorar. "e" derseniz 3 saniyede reboot eder. İstemezseniz daha sonra kendiniz yeniden başlatabilirsiniz.

---

## Dokunmatik Hiç Çalışmıyorsa

Script şu sırayla çözmeye çalışır:

**1. USB'de cihaz var mı?** → `lsusb` ile kontrol eder. Yoksa donanım sorunudur, fiziksel kontrol gerekir (aşağıya bakın).

**2. USB'de var ama X11'de tanınmıyor mu?** → En yaygın Pardus 23 sorunu budur. Script `hid-multitouch` modülünü yükler, libinput sürücüsünü bağlar, udev kuralıyla cihazı dokunmatik olarak işaretler. Bu genellikle çözer.

**3. Bazen çalışıyor bazen çalışmıyor mu?** → Açılış servisi her boot'ta cihazı kontrol eder. İlk denemede bulamazsa USB HID modüllerini reload edip 5 saniye bekleyip tekrar dener.

### Fiziksel Kontroller (Script Çözemezse)

Script donanımsal bir sorun tespit ederse ekrana şu önerileri verir:

1. **Sensör ışıkları** — Tahtanın kenarlarındaki IR sensör ışıkları yanıyor mu? Yanmıyorsa sensör arızalıdır, servis çağırın
2. **USB kablo** — Tahtanın arkasındaki OPS-USB kablosunu çıkarıp tekrar takın
3. **OPS üstü hafif vurma** — Tahtanın üst kısmına (OPS hizası) hafifçe vurun, USB temasını yeniden sağlayabilir
4. **Sensör temizliği** — Ekran kenarlarındaki sensörleri ıslak mendille silin
5. **Tahta gönyesi** — Duvar askısında eğri duruyorsa sağa-sola kaydırarak gönyeye oturtun
6. **Statik deşarj** — Güç kablosunu çekin, güç tuşuna 30 saniye basılı tutun, 5 dakika bekleyin, tekrar açın

---

## Dokunmatik Kayıksa (Offset Sorunu)

Dokunmatik çalışıyor ama parmağınızla bastığınız yer 1-2 cm yana kayıyorsa, kalibrasyon yapmanız gerekir.

### Hızlı Kalibrasyon

Terminalde veya masaüstündeki "Dokunmatik Kalibrasyon" ikonuyla:

```bash
vestel-calibrate hafif       # 0.5-1 cm kayıklık için
vestel-calibrate orta        # 1-2 cm kayıklık için
vestel-calibrate buyuk       # 2+ cm kayıklık için
vestel-calibrate sifirla     # her şeyi sıfırla (fabrika ayarı)
```

`sudo` yazmaya gerek yok — komut yetkiyi otomatik alır.

### Diğer Kalibrasyon Seçenekleri

```bash
vestel-calibrate ters-x      # X ekseni ters (sağ-sol ters)
vestel-calibrate ters-y      # Y ekseni ters (üst-alt ters)
vestel-calibrate swap-xy     # X-Y eksenleri değiştir
```

### Manuel Kalibrasyon (İleri Düzey)

Kendi matris değerlerinizi girebilirsiniz:

```bash
vestel-calibrate 1.05 0 -0.025 0 1.05 -0.025 0 0 1
```

Bu 9 sayı bir 3x3 matristir:

```
⎡ a  b  c ⎤       a = X ölçek (1.0 = normal, >1 = genişlet)
⎢ d  e  f ⎥       e = Y ölçek (1.0 = normal, >1 = genişlet)
⎣ 0  0  1 ⎦       c = X kaydırma (negatif = sola, pozitif = sağa)
                    f = Y kaydırma (negatif = yukarı, pozitif = aşağı)
```

Kalibrasyon anında uygulanır + kalıcı kaydedilir. Bir kere ayarladınız mı bir daha uğraşmazsınız, her açılışta aynı ayar otomatik gelir.

---

## Tüm Okula Dağıtım

### USB Bellek Yöntemi (En Kolay)

1. Bir tahtada scripti çalıştırın ve test edin
2. Aynı USB belleği diğer tahtalara götürün
3. Her tahtada çift tıklayın → "e" deyin → reboot
4. Kayıklık varsa `vestel-calibrate orta` çalıştırın

### SSH ile Toplu Dağıtım (İleri Düzey)

Tahtalar ağda erişilebilirse:

```bash
# Tüm tahta IP'lerini listele
TAHTALAR="192.168.1.101 192.168.1.102 192.168.1.103"

for IP in $TAHTALAR; do
    echo "=== $IP ==="
    scp vestel-dokunmatik-fix.sh root@$IP:/tmp/
    ssh root@$IP "bash /tmp/vestel-dokunmatik-fix.sh && reboot"
done
```

---

## Script Tarafından Oluşturulan Dosyalar

| Dosya | Açıklama |
|-------|----------|
| `/etc/X11/xorg.conf.d/99-vestel-touchscreen.conf` | X11 dokunmatik yapılandırma |
| `/etc/udev/rules.d/99-vestel-touchscreen.rules` | USB dokunmatik tanıma kuralları |
| `/usr/local/bin/vestel-touch-fix.sh` | Açılış düzeltme scripti |
| `/etc/systemd/system/vestel-touch-fix.service` | systemd servisi |
| `/etc/xdg/autostart/vestel-touch-fix.desktop` | XDG autostart (yedek) |
| `/etc/vestel-touch-calibration.conf` | Kalibrasyon matrisi |
| `/etc/sudoers.d/vestel-touch` | Parolasız çalışma yetkisi |
| `/usr/local/bin/vestel-calibrate` | Hızlı kalibrasyon komutu |
| `/usr/local/bin/vestel-dokunmatik-fix.sh` | Ana scriptin sistem kopyası |
| `~/Masaüstü/vestel-dokunmatik-duzelt.desktop` | Masaüstü kısayolu |
| `~/Masaüstü/vestel-kalibrasyon.desktop` | Kalibrasyon kısayolu |

---

## Sorun Giderme

### "Dokunmatik cihaz bulunamadı" hatası
- `lsusb` ile USB cihazları kontrol edin
- OPS modülünü çıkarıp takın
- Tahtanın üst kısmına hafifçe vurun
- Statik deşarj yapın (fişi çek, güç tuşuna 30sn bas, 5dk bekle)

### "Çalışıyor ama her açılışta bozuluyor"
- Servis durumunu kontrol edin: `systemctl status vestel-touch-fix.service`
- Log dosyasına bakın: `cat /var/log/vestel-dokunmatik-fix.log`

### "Dokunmatik çalışıyor ama kayık"
- `vestel-calibrate orta` deneyin
- Olmadıysa `vestel-calibrate buyuk` deneyin
- Hala olmadıysa manuel matris ile deneme yapın

### "Çoklu dokunma çalışmıyor"
- `lsmod | grep multitouch` ile modül kontrolü yapın
- Bazı eski Faz-1 (siyah) tahtalarda multitouch donanımsal olarak desteklenmez

### "Script çalışmıyor / izin hatası"
- `chmod +x vestel-dokunmatik-fix.sh` ile çalıştırma izni verin
- Veya `bash vestel-dokunmatik-fix.sh` ile çalıştırın (chmod gerekmez)

---

## Teknik Bilgi

### Neden libinput Calibration Matrix?

Pardus 23 (Debian 12 tabanlı) X.Org server'da giriş cihazlarını `libinput` ile yönetir. Eski `evdev` sürücüsü hâlâ kurulabilir ama varsayılan değildir. `xinput_calibrator` projesinin bakımı, libinput ortaya çıkmadan önce durmuştur ve bu araç libinput'un beklediği matris formatında çıktı üretemez.

### Desteklenen Dokunmatik Çipsetler

| Üretici | Vendor ID | Tahtalar |
|---------|-----------|----------|
| eGalax / EETI | 0eef | Faz-1 siyah tahtalarda yaygın |
| ILITEK | 222a | Faz-2 gri tahtalarda yaygın |
| Weida | 2575 | Bazı Faz-2 modelleri |
| PixArt | 1926 | Çeşitli modeller |
| ELAN | 04f3 | Yeni nesil tahtalar |
| Goodix | 27c6 | Yeni nesil tahtalar |
| SiS | 0457 | Bazı modeller |
| Atmel | 03eb | Bazı modeller |
| IRTOUCH | 6615 | IR dokunmatik paneller |
| GeneralTouch | 0dfc | Genel dokunmatik |

---

## Gereksinimler

- Pardus 23 veya ETAP 23 kurulu Vestel akıllı tahta
- USB bellek (scripti taşımak için)
- İnternet bağlantısı (ilk kurulumda paket indirmek için, sonra gerekmez)
- USB klavye (dokunmatik çalışmıyorsa terminale komut yazmak için)

---

## Lisans

MIT — Serbestçe kullanabilir, değiştirebilir ve dağıtabilirsiniz.

---

## İletişim

- **GitHub:** [coinsspor](https://github.com/coinsspor)
- **Twitter:** [@coinsspor](https://twitter.com/coinsspor)
- **Web:** [coinsspor.com](https://coinsspor.com)
