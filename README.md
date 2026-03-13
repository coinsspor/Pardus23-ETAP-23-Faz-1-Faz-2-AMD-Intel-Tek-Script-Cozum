# Vestel Akıllı Tahta — Dokunmatik Fix & Kalibrasyon

## Flash Bellek İçeriği

```
USB Flash/
├── vestel-fix.sh                  ← Sürücü kurulum (dokunmatik çalışmıyorsa)
├── vestel-calibrate-gui.py        ← Kalibrasyon (kayıklık varsa)
├── eta-touchdrv_X_X_X_amd64.deb  ← Sürücü paketi
└── README.md
```

## İki Ayrı Program

### 1. vestel-fix.sh — Sürücü Kurulum

Dokunmatik **hiç çalışmıyorsa** bunu çalıştır.

```
bash vestel-fix.sh
```

Ne yapar: `.deb` paketini kurar, kernel modülünü derler, servisi aktif eder. Orijinal sistem dosyalarına dokunmaz. Reboot sonrası dokunmatik gelir.

### 2. vestel-calibrate-gui.py — Kalibrasyon

Dokunmatik **çalışıyor ama kayık** ise bunu çalıştır.

```
python3 vestel-calibrate-gui.py
```

Ne yapar: Fullscreen siyah ekranda 9 artı işareti gösterir. Sırayla her birine dokun. Matris hesaplar, kaydeder, boot servisi kurar. Bir daha uğraşmazsın.

**İnternetsiz çalışır. Bağımsız program — vestel-fix.sh'a ihtiyacı yok.**

## Şifre

Her iki program da bilinen ETAP şifrelerini otomatik dener. Çoğu tahtada şifre sorulmaz.

## Reboot Sonrası

Kalibrasyon kalıcıdır. Her açılışta otomatik uygulanır.

## İletişim

- GitHub: [coinsspor](https://github.com/coinsspor)
- Twitter: [@coinsspor](https://twitter.com/coinsspor)
