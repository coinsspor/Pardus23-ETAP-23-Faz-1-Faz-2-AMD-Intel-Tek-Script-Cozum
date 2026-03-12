#!/bin/bash
#===============================================================================
#  VESTEL AKILLI TAHTA - DOKUNMATIK TAM OTOMATİK DÜZELTME
#  Pardus 23 / ETAP 23 - Faz-1 / Faz-2 (AMD & Intel)
#  
#  Tek script: Teşhis + Düzeltme + Kalibrasyon + Kalıcı Yapılandırma
#  USB'de klavye/mouse takılı olsa bile güvenle çalışır
#
#  Kullanım: bash vestel-dokunmatik-fix.sh
#  (sudo gerekmez — script yetkiyi otomatik alır)
#  
#  Yazar: Fatih (github.com/coinsspor)
#  Tarih: 2026-03-12
#===============================================================================

set -euo pipefail

# ─── Renkler ──────────────────────────────────────────────────
R='\033[0;31m'   G='\033[0;32m'   Y='\033[1;33m'
B='\033[0;34m'   C='\033[0;36m'   W='\033[1;37m'
NC='\033[0m'

# ─── Yardımcı fonksiyonlar ────────────────────────────────────
ok()   { echo -e "  ${G}✓${NC} $1"; }
warn() { echo -e "  ${Y}⚠${NC} $1"; }
fail() { echo -e "  ${R}✗${NC} $1"; }
info() { echo -e "  ${C}→${NC} $1"; }
header() { echo -e "\n${B}[$1]${NC} ${W}$2${NC}"; echo "  ────────────────────────────────────────────"; }

# ─── Otomatik Root Yetki Yükseltme ───────────────────────────
# Script root değilse kendini otomatik olarak root'a yükseltir
# Bilinen ETAP şifrelerini dener, olmazsa kullanıcıdan ister
if [ "$EUID" -ne 0 ]; then
    echo -e "${Y}Root yetkisi gerekiyor, otomatik yükseltme deneniyor...${NC}"
    
    # Bilinen ETAP / Pardus varsayılan admin şifreleri
    KNOWN_PASSWORDS=(
        'etap+pardus!'
        'etap+pardus'
        'pardus'
        'etapadmin'
        '123456'
        'pardus23'
        'etap23'
    )
    
    # Yöntem 1: Zaten sudo NOPASSWD yetkisi varsa direkt geç
    if sudo -n true 2>/dev/null; then
        echo -e "${G}  ✓ sudo yetkisi mevcut${NC}"
        exec sudo bash "$0" "$@"
    fi
    
    # Yöntem 2: Bilinen şifreleri sudo ile dene
    for pw in "${KNOWN_PASSWORDS[@]}"; do
        if echo "$pw" | sudo -S true 2>/dev/null; then
            echo -e "${G}  ✓ Şifre bulundu, root olarak başlatılıyor...${NC}"
            echo "$pw" | sudo -S bash "$0" "$@"
            exit $?
        fi
    done
    
    # Yöntem 3: Bilinen şifreleri su ile dene
    for pw in "${KNOWN_PASSWORDS[@]}"; do
        if echo "$pw" | su -c "echo ok" root 2>/dev/null | grep -q "ok"; then
            echo -e "${G}  ✓ root şifresi bulundu, yükseltiliyor...${NC}"
            echo "$pw" | su -c "bash '$(readlink -f "$0")' $*" root
            exit $?
        fi
    done
    
    # Yöntem 4: Hiçbiri tutmadı — kullanıcıdan iste (3 deneme)
    echo -e "${Y}  Otomatik şifre bulunamadı.${NC}"
    echo ""
    for attempt in 1 2 3; do
        echo -ne "  ${W}Admin/root şifresini girin (deneme $attempt/3):${NC} "
        read -rs USER_PW
        echo ""
        
        if [ -n "$USER_PW" ]; then
            # sudo dene
            if echo "$USER_PW" | sudo -S true 2>/dev/null; then
                echo -e "${G}  ✓ Şifre doğru, yükseltiliyor...${NC}"
                echo "$USER_PW" | sudo -S bash "$0" "$@"
                exit $?
            fi
            # su dene
            if echo "$USER_PW" | su -c "echo ok" root 2>/dev/null | grep -q "ok"; then
                echo -e "${G}  ✓ root şifresi doğru${NC}"
                echo "$USER_PW" | su -c "bash '$(readlink -f "$0")' $*" root
                exit $?
            fi
        fi
        echo -e "${R}  Şifre yanlış.${NC}"
    done
    
    echo ""
    echo -e "${R}  Yetki alınamadı. Çözüm:${NC}"
    echo -e "  ${C}sudo bash vestel-dokunmatik-fix.sh${NC}"
    exit 1
fi

# ─── Banner ───────────────────────────────────────────────────
clear
echo -e "${B}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${B}║                                                       ║${NC}"
echo -e "${B}║   ${W}VESTEL DOKUNMATIK TAM OTOMATİK DÜZELTME${B}            ║${NC}"
echo -e "${B}║   ${C}Pardus 23 / ETAP 23 — Faz-1 & Faz-2${B}               ║${NC}"
echo -e "${B}║   ${C}AMD & Intel — Tek Script Çözüm${B}                     ║${NC}"
echo -e "${B}║                                                       ║${NC}"
echo -e "${B}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""

LOG="/var/log/vestel-dokunmatik-fix.log"
BACKUP_DIR="/root/vestel-backup-$(date +%Y%m%d-%H%M%S)"
CALIB_FILE="/etc/vestel-touch-calibration.conf"
mkdir -p "$BACKUP_DIR"

echo "$(date): Script başlatıldı" > "$LOG"

# ═══════════════════════════════════════════════════════════════
# BÖLÜM 1: SİSTEM TEŞHİSİ
# ═══════════════════════════════════════════════════════════════
header "1/7" "Sistem Bilgisi"

PARDUS_VER=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "Bilinmiyor")
KERNEL_VER=$(uname -r)
CPU_TYPE="Bilinmiyor"
if grep -qi "amd" /proc/cpuinfo 2>/dev/null; then
    CPU_TYPE="AMD"
elif grep -qi "intel" /proc/cpuinfo 2>/dev/null; then
    CPU_TYPE="Intel"
fi
DISPLAY_SERVER="${XDG_SESSION_TYPE:-x11}"
DESKTOP="${XDG_CURRENT_DESKTOP:-XFCE}"

info "OS: $PARDUS_VER"
info "Kernel: $KERNEL_VER"
info "İşlemci: $CPU_TYPE"
info "Display: $DISPLAY_SERVER / $DESKTOP"

echo "Sistem: $PARDUS_VER | Kernel: $KERNEL_VER | CPU: $CPU_TYPE | Display: $DISPLAY_SERVER" >> "$LOG"

# ═══════════════════════════════════════════════════════════════
# BÖLÜM 2: USB DOKUNMATIK CİHAZ TESPİTİ
# ═══════════════════════════════════════════════════════════════
header "2/7" "USB Dokunmatik Cihaz Tespiti"

# Bilinen dokunmatik vendor ID'leri
# eGalax=0eef, ILITEK=222a, Weida=2575, PixArt=1926, ELAN=04f3
# Goodix=27c6, SiS=0457, Atmel=03eb, IRTOUCH=6615, GeneralTouch=0dfc
KNOWN_TOUCH_VENDORS="0eef|222a|2575|1926|04f3|27c6|0457|03eb|6615|0dfc"
KNOWN_TOUCH_NAMES="touch|egalax|ilitek|weida|pixart|eeti|finger|multi|goodix|silead|sis|atmel|irtouch|general.touch"

TOUCH_USB_VENDOR=""
TOUCH_USB_PRODUCT=""
TOUCH_USB_NAME=""
USB_TOUCH_COUNT=0

while IFS= read -r line; do
    vendor_id=$(echo "$line" | grep -oP 'ID \K[0-9a-f]{4}' || true)
    product_id=$(echo "$line" | grep -oP 'ID [0-9a-f]{4}:\K[0-9a-f]{4}' || true)
    
    if echo "$line" | grep -iqE "$KNOWN_TOUCH_NAMES" || echo "$vendor_id" | grep -iqE "$KNOWN_TOUCH_VENDORS"; then
        # Klavye ve mouse'u filtrele
        if ! echo "$line" | grep -iqE "keyboard|kbd|mouse|hub|storage|mass|audio|video|webcam|bluetooth|wifi|wireless|receiver"; then
            TOUCH_USB_VENDOR="$vendor_id"
            TOUCH_USB_PRODUCT="$product_id"
            TOUCH_USB_NAME=$(echo "$line" | sed 's/.*ID [0-9a-f:]*//; s/^ *//')
            USB_TOUCH_COUNT=$((USB_TOUCH_COUNT + 1))
            ok "USB dokunmatik: ${TOUCH_USB_NAME} (${vendor_id}:${product_id})"
        fi
    fi
done < <(lsusb 2>/dev/null)

# Hiç bulunamadıysa tüm HID cihazlara bak
if [ $USB_TOUCH_COUNT -eq 0 ]; then
    while IFS= read -r line; do
        vendor_id=$(echo "$line" | grep -oP 'ID \K[0-9a-f]{4}' || true)
        product_id=$(echo "$line" | grep -oP 'ID [0-9a-f]{4}:\K[0-9a-f]{4}' || true)
        
        if echo "$line" | grep -iqE "hid" && ! echo "$line" | grep -iqE "keyboard|kbd|mouse|hub|receiver"; then
            warn "Olası dokunmatik HID: $line"
            [ -z "$TOUCH_USB_VENDOR" ] && TOUCH_USB_VENDOR="$vendor_id"
            [ -z "$TOUCH_USB_PRODUCT" ] && TOUCH_USB_PRODUCT="$product_id"
        fi
    done < <(lsusb 2>/dev/null)
fi

if [ -z "$TOUCH_USB_VENDOR" ]; then
    warn "USB'de dokunmatik cihaz bulunamadı — I2C/dahili olabilir"
fi

# USB'de takılı diğer cihazlar (bilgi amaçlı)
OTHER_USB=$(lsusb 2>/dev/null | grep -icE "keyboard|mouse|kbd" || true)
if [ "$OTHER_USB" -gt 0 ]; then
    info "USB'de $OTHER_USB adet klavye/mouse bağlı (sorun değil, script bunları atlar)"
fi

echo "USB Touch: ${TOUCH_USB_VENDOR:-yok}:${TOUCH_USB_PRODUCT:-yok} | Diğer USB: $OTHER_USB" >> "$LOG"

# ═══════════════════════════════════════════════════════════════
# BÖLÜM 3: KERNEL MODÜL & PAKET KURULUMU
# ═══════════════════════════════════════════════════════════════
header "3/7" "Sürücü & Paket Kurulumu"

# Paketler
PACKAGES="xinput xserver-xorg-input-libinput libinput-tools"
MISSING=""
for pkg in $PACKAGES; do
    if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        MISSING="$MISSING $pkg"
    fi
done

if [ -n "$MISSING" ]; then
    info "Paketler kuruluyor:$MISSING"
    apt-get update -qq 2>/dev/null
    apt-get install -y -qq $MISSING 2>/dev/null && ok "Paketler kuruldu" || warn "Bazı paketler kurulamadı"
else
    ok "Gerekli paketler zaten yüklü"
fi

# evtest (opsiyonel ama faydalı)
dpkg -l evtest 2>/dev/null | grep -q "^ii" || apt-get install -y -qq evtest 2>/dev/null || true

# Kernel modülleri
MODULES="usbhid hid-multitouch hid-generic"
for mod in $MODULES; do
    mod_underscore="${mod//-/_}"
    if ! lsmod | grep -q "^${mod_underscore}"; then
        modprobe "$mod" 2>/dev/null && ok "$mod yüklendi" || warn "$mod yüklenemedi (kernel'da olmayabilir)"
    else
        ok "$mod zaten yüklü"
    fi
done

# Açılışta modüllerin yüklenmesini garantile
for mod in $MODULES; do
    grep -q "^${mod}$" /etc/modules 2>/dev/null || echo "$mod" >> /etc/modules
done
ok "Modüller /etc/modules'a eklendi"

# ═══════════════════════════════════════════════════════════════
# BÖLÜM 4: INPUT CİHAZ TESPİTİ (XINPUT + EVDEV)
# ═══════════════════════════════════════════════════════════════
header "4/7" "Dokunmatik Giriş Cihazı Tespiti"

export DISPLAY="${DISPLAY:-:0}"
# XAUTHORITY bul
if [ -z "${XAUTHORITY:-}" ]; then
    for xa in /home/*/.Xauthority /root/.Xauthority /var/run/lightdm/root/:0; do
        if [ -f "$xa" ]; then
            export XAUTHORITY="$xa"
            break
        fi
    done
fi

TOUCH_XINPUT_ID=""
TOUCH_XINPUT_NAME=""
TOUCH_EVENT_DEV=""
TOUCH_EVENT_NAME=""

# xinput'tan dokunmatik bul (klavye/mouse olan cihazları atla)
if command -v xinput &>/dev/null; then
    while IFS= read -r line; do
        # Sadece pointer slave cihazlara bak
        if echo "$line" | grep -q "slave  pointer"; then
            id=$(echo "$line" | grep -oP 'id=\K[0-9]+' || true)
            name=$(echo "$line" | sed 's/[⎜↳│]//g' | awk -F'id=' '{print $1}' | xargs)
            
            # Bilinen dokunmatik isimlerine bak
            if echo "$name" | grep -iqE "$KNOWN_TOUCH_NAMES"; then
                TOUCH_XINPUT_ID="$id"
                TOUCH_XINPUT_NAME="$name"
                ok "xinput dokunmatik: '$name' (id=$id)"
            fi
        fi
    done < <(xinput list 2>/dev/null)
    
    # Bulunamadıysa: calibration matrix property'si olan pointer cihazları dene
    if [ -z "$TOUCH_XINPUT_ID" ]; then
        while IFS= read -r line; do
            if echo "$line" | grep -q "slave  pointer"; then
                id=$(echo "$line" | grep -oP 'id=\K[0-9]+' || true)
                name=$(echo "$line" | sed 's/[⎜↳│]//g' | awk -F'id=' '{print $1}' | xargs)
                
                # Mouse cihazlarını atla
                if echo "$name" | grep -iqE "mouse|trackpad|synaptics|logitech|receiver"; then
                    continue
                fi
                
                # Calibration property var mı?
                if xinput list-props "$id" 2>/dev/null | grep -qi "calibration\|ABS_X"; then
                    TOUCH_XINPUT_ID="$id"
                    TOUCH_XINPUT_NAME="$name"
                    warn "Olası dokunmatik (calibration özelliği var): '$name' (id=$id)"
                fi
            fi
        done < <(xinput list 2>/dev/null)
    fi
fi

# /dev/input/event* cihazlarından dokunmatik bul
for dev in /dev/input/event*; do
    [ -e "$dev" ] || continue
    basename_dev=$(basename "$dev")
    devname=$(cat "/sys/class/input/$basename_dev/device/name" 2>/dev/null || true)
    abs_caps=$(cat "/sys/class/input/$basename_dev/device/capabilities/abs" 2>/dev/null || true)
    
    # ABS capability olmayanları atla
    [ -z "$abs_caps" ] || [ "$abs_caps" = "0" ] && continue
    
    # Dokunmatik ismi veya büyük ABS bitmap (multitouch göstergesi)
    if echo "$devname" | grep -iqE "$KNOWN_TOUCH_NAMES"; then
        TOUCH_EVENT_DEV="$dev"
        TOUCH_EVENT_NAME="$devname"
        ok "Event cihazı: $dev → $devname"
    elif [ ${#abs_caps} -gt 10 ] && ! echo "$devname" | grep -iqE "mouse|keyboard|kbd|power|video|sleep|lid"; then
        # Büyük ABS bitmap = muhtemelen dokunmatik (multitouch ABS_MT_*)
        if [ -z "$TOUCH_EVENT_DEV" ]; then
            TOUCH_EVENT_DEV="$dev"
            TOUCH_EVENT_NAME="$devname"
            warn "Olası dokunmatik (büyük ABS bitmap): $dev → $devname"
        fi
    fi
done

# Sonuç
if [ -n "$TOUCH_XINPUT_ID" ]; then
    ok "Dokunmatik tespit edildi: '$TOUCH_XINPUT_NAME' (xinput id=$TOUCH_XINPUT_ID)"
elif [ -n "$TOUCH_EVENT_DEV" ]; then
    warn "Dokunmatik event cihazı var ama xinput'ta görünmüyor"
    info "Bu genellikle sürücü sorunu — düzeltme devam ediyor"
else
    fail "Dokunmatik cihaz bulunamadı!"
    echo ""
    echo -e "${Y}  FİZİKSEL KONTROL GEREKLİ:${NC}"
    echo "  1. Tahtanın kenarlarındaki sensör ışıkları yanıyor mu?"
    echo "  2. Tahtanın arkasındaki OPS-USB kablosunu çıkarıp takın"
    echo "  3. Tahtanın üst kısmına (OPS hizası) hafifçe vurun"
    echo "  4. Güç kablosunu çekin, güç tuşuna 30sn basılı tutun, 5dk bekleyin"
    echo "  5. Sensörleri ıslak mendille temizleyin"
    echo ""
    echo -e "${Y}  Bu adımlardan sonra scripti tekrar çalıştırın.${NC}"
    echo -e "${Y}  Script yine de yapılandırma dosyalarını oluşturacak.${NC}"
    echo ""
fi

echo "xinput: ${TOUCH_XINPUT_ID:-yok} '${TOUCH_XINPUT_NAME:-yok}' | event: ${TOUCH_EVENT_DEV:-yok}" >> "$LOG"

# ═══════════════════════════════════════════════════════════════
# BÖLÜM 5: YAPILANDIRMA DOSYALARI
# ═══════════════════════════════════════════════════════════════
header "5/7" "Yapılandırma Dosyaları Oluşturuluyor"

# ─── Mevcut dosyaları yedekle ─────────────────────────────────
for f in /etc/X11/xorg.conf.d/*touch* /etc/X11/xorg.conf.d/*calib* \
         /etc/X11/xorg.conf.d/*vestel* /etc/udev/rules.d/*vestel* \
         /etc/udev/rules.d/*touch* /etc/udev/rules.d/*calib*; do
    [ -f "$f" ] && cp "$f" "$BACKUP_DIR/" 2>/dev/null && info "Yedeklendi: $f"
done

# ─── Mevcut kalibrasyon matrisi (varsa koru) ──────────────────
if [ -f "$CALIB_FILE" ]; then
    MATRIX=$(cat "$CALIB_FILE" | xargs)
    info "Mevcut kalibrasyon korunuyor: $MATRIX"
else
    MATRIX="1 0 0 0 1 0 0 0 1"
fi

# ─── X11 yapılandırma ────────────────────────────────────────
mkdir -p /etc/X11/xorg.conf.d

cat > /etc/X11/xorg.conf.d/99-vestel-touchscreen.conf << EOF
# ═══════════════════════════════════════════════════════════
# Vestel Akıllı Tahta Dokunmatik - Pardus 23
# Otomatik oluşturuldu: $(date)
# Faz-1 / Faz-2 / AMD / Intel uyumlu
# ═══════════════════════════════════════════════════════════

# Ana dokunmatik kuralı — tüm dokunmatik cihazları yakalar
Section "InputClass"
    Identifier "Vestel Touchscreen All"
    MatchIsTouchscreen "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
    Option "Tapping" "on"
    Option "DisableWhileTyping" "false"
    Option "TransformationMatrix" "$MATRIX"
EndSection

# eGalax (Faz-1 siyah tahtalarda yaygın)
Section "InputClass"
    Identifier "eGalax Touch"
    MatchProduct "eGalax|EETI"
    MatchIsTouchscreen "on"
    Driver "libinput"
    Option "CalibrationMatrix" "$MATRIX"
    Option "TransformationMatrix" "$MATRIX"
EndSection

# ILITEK (Faz-2 gri tahtalarda yaygın)
Section "InputClass"
    Identifier "ILITEK Touch"
    MatchProduct "ILITEK|ILI"
    MatchIsTouchscreen "on"
    Driver "libinput"
    Option "CalibrationMatrix" "$MATRIX"
    Option "TransformationMatrix" "$MATRIX"
EndSection

# Goodix (bazı yeni tahtalarda)
Section "InputClass"
    Identifier "Goodix Touch"
    MatchProduct "Goodix|goodix"
    MatchIsTouchscreen "on"
    Driver "libinput"
    Option "CalibrationMatrix" "$MATRIX"
    Option "TransformationMatrix" "$MATRIX"
EndSection
EOF

ok "X11 yapılandırma: /etc/X11/xorg.conf.d/99-vestel-touchscreen.conf"

# ─── udev kuralları ───────────────────────────────────────────
cat > /etc/udev/rules.d/99-vestel-touchscreen.rules << EOF
# ═══════════════════════════════════════════════════════════
# Vestel Akıllı Tahta Dokunmatik udev Kuralları
# Otomatik oluşturuldu: $(date)
# ═══════════════════════════════════════════════════════════

# --- Bilinen dokunmatik çip üreticileri ---
# eGalax
SUBSYSTEM=="input", ATTRS{idVendor}=="0eef", ENV{LIBINPUT_CALIBRATION_MATRIX}="$MATRIX", ENV{ID_INPUT_TOUCHSCREEN}="1"
# ILITEK
SUBSYSTEM=="input", ATTRS{idVendor}=="222a", ENV{LIBINPUT_CALIBRATION_MATRIX}="$MATRIX", ENV{ID_INPUT_TOUCHSCREEN}="1"
# Weida
SUBSYSTEM=="input", ATTRS{idVendor}=="2575", ENV{LIBINPUT_CALIBRATION_MATRIX}="$MATRIX", ENV{ID_INPUT_TOUCHSCREEN}="1"
# PixArt
SUBSYSTEM=="input", ATTRS{idVendor}=="1926", ENV{LIBINPUT_CALIBRATION_MATRIX}="$MATRIX", ENV{ID_INPUT_TOUCHSCREEN}="1"
# ELAN
SUBSYSTEM=="input", ATTRS{idVendor}=="04f3", ENV{LIBINPUT_CALIBRATION_MATRIX}="$MATRIX", ENV{ID_INPUT_TOUCHSCREEN}="1"
# Goodix
SUBSYSTEM=="input", ATTRS{idVendor}=="27c6", ENV{LIBINPUT_CALIBRATION_MATRIX}="$MATRIX", ENV{ID_INPUT_TOUCHSCREEN}="1"
# SiS
SUBSYSTEM=="input", ATTRS{idVendor}=="0457", ENV{LIBINPUT_CALIBRATION_MATRIX}="$MATRIX", ENV{ID_INPUT_TOUCHSCREEN}="1"
# Atmel
SUBSYSTEM=="input", ATTRS{idVendor}=="03eb", ENV{LIBINPUT_CALIBRATION_MATRIX}="$MATRIX", ENV{ID_INPUT_TOUCHSCREEN}="1"
# IRTOUCH
SUBSYSTEM=="input", ATTRS{idVendor}=="6615", ENV{LIBINPUT_CALIBRATION_MATRIX}="$MATRIX", ENV{ID_INPUT_TOUCHSCREEN}="1"
# GeneralTouch
SUBSYSTEM=="input", ATTRS{idVendor}=="0dfc", ENV{LIBINPUT_CALIBRATION_MATRIX}="$MATRIX", ENV{ID_INPUT_TOUCHSCREEN}="1"

# Genel yakalama — yukarıdakilerle eşleşmeyen dokunmatikler için
SUBSYSTEM=="input", ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="$MATRIX"
EOF

# Tespit edilen cihaza özel kural
if [ -n "$TOUCH_USB_VENDOR" ] && [ -n "$TOUCH_USB_PRODUCT" ]; then
    cat >> /etc/udev/rules.d/99-vestel-touchscreen.rules << EOF

# --- Bu tahtaya özel (otomatik tespit) ---
SUBSYSTEM=="input", ATTRS{idVendor}=="$TOUCH_USB_VENDOR", ATTRS{idProduct}=="$TOUCH_USB_PRODUCT", ENV{LIBINPUT_CALIBRATION_MATRIX}="$MATRIX", ENV{ID_INPUT_TOUCHSCREEN}="1"
EOF
    ok "Cihaza özel udev kuralı eklendi (${TOUCH_USB_VENDOR}:${TOUCH_USB_PRODUCT})"
fi

ok "udev kuralları: /etc/udev/rules.d/99-vestel-touchscreen.rules"

udevadm control --reload-rules 2>/dev/null
udevadm trigger 2>/dev/null
ok "udev kuralları yeniden yüklendi"

# ═══════════════════════════════════════════════════════════════
# BÖLÜM 6: AÇILIŞ SERVİSİ
# ═══════════════════════════════════════════════════════════════
header "6/7" "Açılış Servisi Kuruluyor"

# ─── Ana düzeltme scripti ─────────────────────────────────────
cat > /usr/local/bin/vestel-touch-fix.sh << 'FIXSCRIPT'
#!/bin/bash
# Vestel Dokunmatik Açılış Düzeltme Servisi
# Her boot'ta otomatik çalışır

LOG="/var/log/vestel-dokunmatik-fix.log"
CALIB="/etc/vestel-touch-calibration.conf"
KNOWN_NAMES="touch|egalax|ilitek|weida|pixart|eeti|finger|multi|goodix|silead|sis|atmel|irtouch|general.touch"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG"; }
log "=== Servis başlatıldı ==="

# X11 hazır olana kadar bekle (max 90sn)
waited=0
while [ $waited -lt 90 ]; do
    if DISPLAY=:0 xdpyinfo &>/dev/null 2>&1; then
        break
    fi
    sleep 2
    waited=$((waited + 2))
done

if [ $waited -ge 90 ]; then
    log "X11 90sn içinde başlamadı, çıkılıyor"
    exit 1
fi

sleep 3

export DISPLAY=:0
# XAUTHORITY bul
for xa in /home/*/.Xauthority /root/.Xauthority /var/run/lightdm/root/:0; do
    [ -f "$xa" ] && export XAUTHORITY="$xa" && break
done

# Kalibrasyon matrisini oku
[ -f "$CALIB" ] && MATRIX=$(cat "$CALIB" | xargs) || MATRIX="1 0 0 0 1 0 0 0 1"

# Dokunmatik cihazı bul ve ayarla (birden fazla olabilir)
FIXED=0
while IFS= read -r line; do
    echo "$line" | grep -q "slave  pointer" || continue
    
    id=$(echo "$line" | grep -oP 'id=\K[0-9]+' || true)
    [ -z "$id" ] && continue
    
    name=$(echo "$line" | sed 's/[⎜↳│]//g' | awk -F'id=' '{print $1}' | xargs)
    
    # Mouse/keyboard atla
    echo "$name" | grep -iqE "mouse|trackpad|synaptics|logitech|receiver|virtual" && continue
    
    # Dokunmatik mı? (isim veya calibration property kontrolü)
    is_touch=0
    echo "$name" | grep -iqE "$KNOWN_NAMES" && is_touch=1
    [ $is_touch -eq 0 ] && xinput list-props "$id" 2>/dev/null | grep -qi "calibration" && is_touch=1
    
    [ $is_touch -eq 0 ] && continue
    
    # Etkinleştir
    xinput enable "$id" 2>/dev/null
    
    # Matrisi uygula
    if xinput list-props "$id" 2>/dev/null | grep -q "libinput Calibration Matrix"; then
        xinput set-prop "$id" "libinput Calibration Matrix" $MATRIX 2>/dev/null
        log "libinput matrix ayarlandı: id=$id name='$name' matrix=$MATRIX"
        FIXED=$((FIXED + 1))
    fi
    
    if xinput list-props "$id" 2>/dev/null | grep -q "Coordinate Transformation Matrix"; then
        xinput set-prop "$id" "Coordinate Transformation Matrix" $MATRIX 2>/dev/null
        log "CTM ayarlandı: id=$id name='$name' matrix=$MATRIX"
        FIXED=$((FIXED + 1))
    fi
    
done < <(xinput list 2>/dev/null)

if [ $FIXED -eq 0 ]; then
    log "İlk denemede dokunmatik bulunamadı, HID reload deneniyor..."
    
    modprobe -r usbhid 2>/dev/null; sleep 1
    modprobe usbhid 2>/dev/null
    modprobe hid-multitouch 2>/dev/null
    sleep 5
    
    # Tekrar dene
    while IFS= read -r line; do
        echo "$line" | grep -q "slave  pointer" || continue
        id=$(echo "$line" | grep -oP 'id=\K[0-9]+' || true)
        [ -z "$id" ] && continue
        name=$(echo "$line" | sed 's/[⎜↳│]//g' | awk -F'id=' '{print $1}' | xargs)
        echo "$name" | grep -iqE "mouse|trackpad|virtual|receiver" && continue
        
        xinput enable "$id" 2>/dev/null
        xinput set-prop "$id" "libinput Calibration Matrix" $MATRIX 2>/dev/null && FIXED=$((FIXED + 1))
        xinput set-prop "$id" "Coordinate Transformation Matrix" $MATRIX 2>/dev/null
        log "Retry: id=$id name='$name'"
    done < <(xinput list 2>/dev/null)
fi

log "Servis tamamlandı. Düzeltilen cihaz sayısı: $FIXED"
FIXSCRIPT

chmod +x /usr/local/bin/vestel-touch-fix.sh
ok "Düzeltme scripti: /usr/local/bin/vestel-touch-fix.sh"

# ─── systemd servisi ──────────────────────────────────────────
cat > /etc/systemd/system/vestel-touch-fix.service << 'EOF'
[Unit]
Description=Vestel Akilli Tahta Dokunmatik Duzeltme
After=display-manager.service
Wants=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/vestel-touch-fix.sh
RemainAfterExit=yes
TimeoutStartSec=120

[Install]
WantedBy=graphical.target
EOF

systemctl daemon-reload
systemctl enable vestel-touch-fix.service 2>/dev/null
ok "systemd servisi etkinleştirildi"

# ─── XDG autostart (yedek mekanizma) ─────────────────────────
mkdir -p /etc/xdg/autostart
cat > /etc/xdg/autostart/vestel-touch-fix.desktop << EOF
[Desktop Entry]
Type=Application
Name=Vestel Dokunmatik
Comment=Dokunmatik ekran duzeltme
Exec=/bin/bash -c "sleep 8 && sudo /usr/local/bin/vestel-touch-fix.sh"
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
X-MATE-Autostart-enabled=true
X-XFCE-Autostart-enabled=true
EOF
ok "XDG autostart oluşturuldu"

# ─── sudoers (parola sormadan çalışsın) ──────────────────────
echo "ALL ALL=NOPASSWD: /usr/local/bin/vestel-touch-fix.sh" > /etc/sudoers.d/vestel-touch
chmod 440 /etc/sudoers.d/vestel-touch
ok "sudoers kuralı eklendi"

# ─── Kalibrasyon dosyası ──────────────────────────────────────
echo "$MATRIX" > "$CALIB_FILE"
ok "Kalibrasyon: $CALIB_FILE ($MATRIX)"

# ─── Masaüstü kısayolları (çift tıkla çalıştır) ──────────────
# Tüm kullanıcıların masaüstüne "Dokunmatik Düzelt" ikonu koy
for user_home in /home/*/; do
    username=$(basename "$user_home")
    
    # Masaüstü dizinini bul (Türkçe/İngilizce)
    desktop_dir=""
    for d in "Masaüstü" "Desktop" "masa üstü"; do
        [ -d "${user_home}${d}" ] && desktop_dir="${user_home}${d}" && break
    done
    # xdg-user-dirs'den de kontrol et
    if [ -z "$desktop_dir" ] && [ -f "${user_home}.config/user-dirs.dirs" ]; then
        desktop_dir=$(grep XDG_DESKTOP_DIR "${user_home}.config/user-dirs.dirs" 2>/dev/null | cut -d'"' -f2 | sed "s|\$HOME|${user_home%/}|")
    fi
    [ -z "$desktop_dir" ] && desktop_dir="${user_home}Masaüstü"
    
    mkdir -p "$desktop_dir" 2>/dev/null || continue
    
    # Ana script'i /usr/local/bin'e de kopyala (her yerden erişilebilir olsun)
    cp "$(readlink -f "$0")" /usr/local/bin/vestel-dokunmatik-fix.sh 2>/dev/null || true
    chmod +x /usr/local/bin/vestel-dokunmatik-fix.sh 2>/dev/null || true
    
    # Düzeltme kısayolu
    cat > "${desktop_dir}/vestel-dokunmatik-duzelt.desktop" << 'DTOP1'
[Desktop Entry]
Version=1.0
Type=Application
Name=Dokunmatik Düzelt
Comment=Vestel akıllı tahta dokunmatik sorunlarını düzeltir
Exec=bash /usr/local/bin/vestel-dokunmatik-fix.sh
Icon=input-touchscreen
Terminal=true
Categories=System;Settings;
StartupNotify=false
DTOP1
    
    # Kalibrasyon kısayolu
    cat > "${desktop_dir}/vestel-kalibrasyon.desktop" << 'DTOP2'
[Desktop Entry]
Version=1.0
Type=Application
Name=Dokunmatik Kalibrasyon
Comment=Dokunmatik ekran kayıklığını düzeltir
Exec=bash -c '/usr/local/bin/vestel-calibrate || read -p "Enter a basın..."'
Icon=preferences-desktop-display
Terminal=true
Categories=System;Settings;
StartupNotify=false
DTOP2
    
    # Çalıştırılabilir yap
    chmod +x "${desktop_dir}/vestel-dokunmatik-duzelt.desktop" 2>/dev/null
    chmod +x "${desktop_dir}/vestel-kalibrasyon.desktop" 2>/dev/null
    chown "$username":"$username" "${desktop_dir}/vestel-dokunmatik-duzelt.desktop" 2>/dev/null
    chown "$username":"$username" "${desktop_dir}/vestel-kalibrasyon.desktop" 2>/dev/null
    
    # XFCE'de "güvenilir" olarak işaretle (çift tıklama uyarısını atla)
    if command -v gio &>/dev/null; then
        su - "$username" -c "gio set '${desktop_dir}/vestel-dokunmatik-duzelt.desktop' metadata::trusted true" 2>/dev/null || true
        su - "$username" -c "gio set '${desktop_dir}/vestel-kalibrasyon.desktop' metadata::trusted true" 2>/dev/null || true
    fi
done

ok "Masaüstü kısayolları oluşturuldu (Dokunmatik Düzelt + Kalibrasyon)"

# ═══════════════════════════════════════════════════════════════
# BÖLÜM 7: ANLIK DÜZELTME & TEST
# ═══════════════════════════════════════════════════════════════
header "7/7" "Anlık Düzeltme Uygulanıyor"

if [ -n "$TOUCH_XINPUT_ID" ]; then
    xinput enable "$TOUCH_XINPUT_ID" 2>/dev/null
    
    xinput set-prop "$TOUCH_XINPUT_ID" "libinput Calibration Matrix" $MATRIX 2>/dev/null && \
        ok "libinput Calibration Matrix uygulandı" || true
    
    xinput set-prop "$TOUCH_XINPUT_ID" "Coordinate Transformation Matrix" $MATRIX 2>/dev/null && \
        ok "Coordinate Transformation Matrix uygulandı" || true
    
    echo ""
    info "Mevcut dokunmatik özellikleri:"
    xinput list-props "$TOUCH_XINPUT_ID" 2>/dev/null | grep -iE "calibration|transformation|enabled" | while read -r prop; do
        info "  $prop"
    done
else
    warn "xinput'ta dokunmatik yok — reboot sonrası servis otomatik deneyecek"
fi

# ═══════════════════════════════════════════════════════════════
# SONUÇ
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${B}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${B}║  ${G}KURULUM TAMAMLANDI!${B}                                  ║${NC}"
echo -e "${B}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${W}Oluşturulan dosyalar:${NC}"
echo "  /etc/X11/xorg.conf.d/99-vestel-touchscreen.conf"
echo "  /etc/udev/rules.d/99-vestel-touchscreen.rules"
echo "  /usr/local/bin/vestel-touch-fix.sh"
echo "  /etc/systemd/system/vestel-touch-fix.service"
echo "  /etc/xdg/autostart/vestel-touch-fix.desktop"
echo "  /etc/vestel-touch-calibration.conf"
echo "  /etc/sudoers.d/vestel-touch"
echo ""
echo -e "${W}Şimdi ne yapmalı:${NC}"
echo -e "  ${G}1.${NC} Tahtayı yeniden başlatın: ${C}sudo reboot${NC}"
echo -e "  ${G}2.${NC} Dokunmatik çalışıyorsa → tamamdır!"
echo -e "  ${G}3.${NC} Dokunmatik kayıksa → şu komutla hızlı ayar yapın:"
echo ""
echo -e "     ${C}# Hafif kayık düzeltme:${NC}"
echo -e "     ${W}vestel-calibrate hafif${NC}"
echo ""
echo -e "     ${C}# Orta kayık düzeltme:${NC}"
echo -e "     ${W}vestel-calibrate orta${NC}"
echo ""
echo -e "     ${C}# Büyük kayık düzeltme:${NC}"
echo -e "     ${W}vestel-calibrate buyuk${NC}"
echo ""
echo -e "     ${C}# Manuel matris (9 sayı):${NC}"
echo -e "     ${W}vestel-calibrate 1.05 0 -0.025 0 1.05 -0.025 0 0 1${NC}"
echo ""
echo -e "     ${C}# Sıfırla:${NC}"
echo -e "     ${W}vestel-calibrate sifirla${NC}"
echo ""
echo -e "${Y}Yedek: $BACKUP_DIR${NC}"
echo -e "${Y}Log:   $LOG${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════
# BONUS: Hızlı kalibrasyon komutu oluştur
# ═══════════════════════════════════════════════════════════════
cat > /usr/local/bin/vestel-calibrate << 'CALSCRIPT'
#!/bin/bash
# vestel-calibrate — hızlı dokunmatik kalibrasyon komutu
# Kullanım: vestel-calibrate [hafif|orta|buyuk|sifirla|MATRIX]
# sudo gerekmez — otomatik yetki alır

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; NC='\033[0m'
CALIB="/etc/vestel-touch-calibration.conf"

# Otomatik root yetki yükseltme
if [ "$EUID" -ne 0 ]; then
    PASSWORDS=('etap+pardus!' 'etap+pardus' 'pardus' 'etapadmin' '123456' 'pardus23' 'etap23')
    # NOPASSWD sudo
    if sudo -n true 2>/dev/null; then exec sudo bash "$0" "$@"; fi
    # Bilinen şifreler
    for pw in "${PASSWORDS[@]}"; do
        if echo "$pw" | sudo -S true 2>/dev/null; then
            echo "$pw" | sudo -S bash "$0" "$@"; exit $?
        fi
    done
    # Manuel
    echo -ne "${Y}Admin şifresi:${NC} "; read -rs UP; echo
    if [ -n "$UP" ]; then
        echo "$UP" | sudo -S true 2>/dev/null && { echo "$UP" | sudo -S bash "$0" "$@"; exit $?; }
    fi
    echo -e "${R}Yetki alınamadı. sudo vestel-calibrate ile deneyin.${NC}"; exit 1
fi

case "${1:-}" in
    hafif)   MATRIX="1.02 0 -0.01 0 1.02 -0.01 0 0 1" ;;
    orta)    MATRIX="1.05 0 -0.025 0 1.05 -0.025 0 0 1" ;;
    buyuk)   MATRIX="1.1 0 -0.05 0 1.1 -0.05 0 0 1" ;;
    sifirla) MATRIX="1 0 0 0 1 0 0 0 1" ;;
    ters-x)  MATRIX="-1 0 1 0 1 0 0 0 1" ;;
    ters-y)  MATRIX="1 0 0 0 -1 1 0 0 1" ;;
    swap-xy) MATRIX="0 1 0 1 0 0 0 0 1" ;;
    "")
        echo -e "${C}Kullanım:${NC}"
        echo "  vestel-calibrate hafif     → Hafif kayık düzeltme"
        echo "  vestel-calibrate orta      → Orta kayık düzeltme"
        echo "  vestel-calibrate buyuk     → Büyük kayık düzeltme"
        echo "  vestel-calibrate sifirla   → Fabrika ayarı"
        echo "  vestel-calibrate ters-x    → X ekseni ters"
        echo "  vestel-calibrate ters-y    → Y ekseni ters"
        echo "  vestel-calibrate swap-xy   → X-Y eksen değiştir"
        echo "  vestel-calibrate 1.05 0 -0.025 0 1.05 -0.025 0 0 1  → Manuel"
        exit 0
        ;;
    *)
        # Manuel matris — 9 argüman bekleniyor
        if [ $# -eq 9 ]; then
            MATRIX="$1 $2 $3 $4 $5 $6 $7 $8 $9"
        else
            echo -e "${R}Hata: 9 sayı girin veya preset seçin (hafif/orta/buyuk/sifirla)${NC}"
            exit 1
        fi
        ;;
esac

export DISPLAY=:0
for xa in /home/*/.Xauthority /root/.Xauthority; do [ -f "$xa" ] && export XAUTHORITY="$xa" && break; done

# Tüm dokunmatik cihazlara uygula
NAMES="touch|egalax|ilitek|weida|pixart|eeti|finger|multi|goodix|silead|sis|atmel|irtouch"
applied=0
while IFS= read -r line; do
    echo "$line" | grep -q "slave  pointer" || continue
    id=$(echo "$line" | grep -oP 'id=\K[0-9]+' || true)
    [ -z "$id" ] && continue
    name=$(echo "$line" | sed 's/[⎜↳│]//g' | awk -F'id=' '{print $1}' | xargs)
    echo "$name" | grep -iqE "mouse|trackpad|virtual|receiver" && continue
    
    is_touch=0
    echo "$name" | grep -iqE "$NAMES" && is_touch=1
    [ $is_touch -eq 0 ] && xinput list-props "$id" 2>/dev/null | grep -qi "calibration" && is_touch=1
    [ $is_touch -eq 0 ] && continue
    
    xinput set-prop "$id" "libinput Calibration Matrix" $MATRIX 2>/dev/null && applied=$((applied+1))
    xinput set-prop "$id" "Coordinate Transformation Matrix" $MATRIX 2>/dev/null
done < <(xinput list 2>/dev/null)

# Kaydet
echo "$MATRIX" > "$CALIB"

# udev ve X11 conf güncelle
sed -i "s/LIBINPUT_CALIBRATION_MATRIX=\"[^\"]*\"/LIBINPUT_CALIBRATION_MATRIX=\"$MATRIX\"/g" \
    /etc/udev/rules.d/99-vestel-touchscreen.rules 2>/dev/null
sed -i "s/\"CalibrationMatrix\" \"[^\"]*\"/\"CalibrationMatrix\" \"$MATRIX\"/g; \
        s/\"TransformationMatrix\" \"[^\"]*\"/\"TransformationMatrix\" \"$MATRIX\"/g" \
    /etc/X11/xorg.conf.d/99-vestel-touchscreen.conf 2>/dev/null
udevadm control --reload-rules 2>/dev/null

if [ $applied -gt 0 ]; then
    echo -e "${G}✓ Kalibrasyon uygulandı ($applied cihaz)${NC}"
else
    echo -e "${Y}⚠ Dokunmatik cihaz bulunamadı — reboot sonrası otomatik uygulanacak${NC}"
fi
echo -e "${C}Matris: $MATRIX${NC}"
echo -e "${C}Kalıcı kaydedildi. Reboot'a gerek yok.${NC}"
CALSCRIPT

chmod +x /usr/local/bin/vestel-calibrate
ok "Hızlı kalibrasyon komutu: vestel-calibrate"

echo "$(date): Script tamamlandı" >> "$LOG"

# ═══════════════════════════════════════════════════════════════
# Çift tıklama ile çalıştırma desteği
# Script bitmeden konsol kapanmasın + reboot seçeneği sun
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${W}────────────────────────────────────────────────────${NC}"
echo ""
echo -ne "${G}Şimdi yeniden başlatmak ister misiniz? (e/h):${NC} "

# 60 saniye bekle, cevap gelmezse devam et (cron/ssh durumu için)
if read -t 60 -r REBOOT_ANSWER 2>/dev/null; then
    case "$REBOOT_ANSWER" in
        e|E|evet|Evet|EVET)
            echo -e "${C}Tahta 3 saniye içinde yeniden başlatılacak...${NC}"
            sleep 3
            reboot
            ;;
        *)
            echo -e "${Y}Yeniden başlatma atlandı.${NC}"
            echo -e "${C}Daha sonra 'sudo reboot' ile yeniden başlatabilirsiniz.${NC}"
            ;;
    esac
else
    echo ""
    echo -e "${Y}Zaman aşımı — yeniden başlatma atlandı.${NC}"
fi

echo ""
echo -e "${W}Kapatmak için Enter'a basın...${NC}"
read -t 120 -r _ 2>/dev/null || true
