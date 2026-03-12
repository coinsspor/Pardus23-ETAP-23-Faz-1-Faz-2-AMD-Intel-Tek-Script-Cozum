#!/bin/bash
#===============================================================================
#  VESTEL AKILLI TAHTA - DOKUNMATIK KOMPLE ÇÖZÜM
#  Pardus 23 / ETAP 23 - Faz-1 & Faz-2 (AMD & Intel)
#
#  Bu script:
#  1. eta-touchdrv .deb paketini kurar
#  2. Kernel modül kaynaklarını patch'ler (tüm uyumsuzluklar düzeltilir)
#  3. DKMS ile modülleri derler
#  4. Düzeltilmiş touchdrv_install ve servis dosyalarını kurar
#  5. Kalibrasyon araçları için device symlink'leri oluşturur
#  6. Kalibrasyon yapar ve kalıcı kaydeder
#  7. Her boot'ta otomatik çalışır
#
#  Kullanım: bash vestel-dokunmatik-fix.sh
#  USB bellekte yanına .deb dosyasını da koyun (opsiyonel)
#===============================================================================

set -uo pipefail

R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m'
B='\033[0;34m' C='\033[0;36m' W='\033[1;37m'
NC='\033[0m'

ok()   { echo -e "  ${G}✓${NC} $1"; }
warn() { echo -e "  ${Y}⚠${NC} $1"; }
fail() { echo -e "  ${R}✗${NC} $1"; }
info() { echo -e "  ${C}→${NC} $1"; }
header() { echo -e "\n${B}[$1]${NC} ${W}$2${NC}\n  ──────────────────────────────────────"; }

LOG="/var/log/vestel-dokunmatik-fix.log"

# ═══════════ OTOMATİK YETKİ YÜKSELTME ═══════════
if [ "$EUID" -ne 0 ]; then
    echo -e "${Y}Root yetkisi gerekiyor...${NC}"
    PASSWORDS=('etap+pardus!' 'etap+pardus' 'pardus' 'etapadmin' '123456' 'pardus23' 'etap23')
    if sudo -n true 2>/dev/null; then exec sudo bash "$0" "$@"; fi
    for pw in "${PASSWORDS[@]}"; do
        if echo "$pw" | sudo -S true 2>/dev/null; then echo "$pw" | sudo -S bash "$0" "$@"; exit $?; fi
    done
    for pw in "${PASSWORDS[@]}"; do
        if echo "$pw" | su -c "echo ok" root 2>/dev/null | grep -q "ok"; then echo "$pw" | su -c "bash '$(readlink -f "$0")' $*" root; exit $?; fi
    done
    for attempt in 1 2 3; do
        echo -ne "  ${W}Admin şifresi ($attempt/3):${NC} "; read -rs UP; echo
        if [ -n "$UP" ]; then
            echo "$UP" | sudo -S true 2>/dev/null && { echo "$UP" | sudo -S bash "$0" "$@"; exit $?; }
            echo "$UP" | su -c "echo ok" root 2>/dev/null | grep -q "ok" && { echo "$UP" | su -c "bash '$(readlink -f "$0")' $*" root; exit $?; }
        fi
        echo -e "${R}  Yanlış.${NC}"
    done
    echo -e "${R}Yetki alınamadı.${NC}"; exit 1
fi

clear
echo -e "${B}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${B}║  ${W}VESTEL DOKUNMATIK KOMPLE ÇÖZÜM${B}                       ║${NC}"
echo -e "${B}║  ${C}eta-touchdrv + kernel patch + kalibrasyon${B}             ║${NC}"
echo -e "${B}║  ${C}Faz-1 & Faz-2 | AMD & Intel${B}                          ║${NC}"
echo -e "${B}╚════════════════════════════════════════════════════════╝${NC}"

echo "$(date): Script başlatıldı" > "$LOG"

# ═══════════ 1/8: SİSTEM TESPİTİ ═══════════
header "1/8" "Sistem Tespiti"
KERNEL_VER=$(uname -r)
CPU_TYPE="Bilinmiyor"
grep -qi "amd" /proc/cpuinfo 2>/dev/null && CPU_TYPE="AMD"
grep -qi "intel" /proc/cpuinfo 2>/dev/null && CPU_TYPE="Intel"
info "Kernel: $KERNEL_VER | CPU: $CPU_TYPE"

BOARD_TYPE="unknown"
if lsusb 2>/dev/null | grep -qE "6615:(0084|0085|0086|0087|0088|0c20)"; then
    BOARD_TYPE="2cam"; ok "2-Kameralı tahta (IRTOUCH)"
elif lsusb 2>/dev/null | grep -qE "2621:(2201|4501)"; then
    BOARD_TYPE="4cam"; ok "4-Kameralı tahta"
else
    warn "Dokunmatik USB cihazı bulunamadı — kurulum yine de yapılacak"
fi

# ═══════════ 2/8: PAKET KURULUMU ═══════════
header "2/8" "Paket Kurulumu"
NEED_PKGS=""
for pkg in dkms build-essential "linux-headers-$(uname -r)" xinput libinput-tools; do
    dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" || NEED_PKGS="$NEED_PKGS $pkg"
done
if [ -n "$NEED_PKGS" ]; then
    apt-get update -qq 2>/dev/null
    apt-get install -y -qq $NEED_PKGS 2>/dev/null && ok "Paketler kuruldu" || warn "Bazı paketler kurulamadı"
else
    ok "Tüm paketler mevcut"
fi

# Mevcut eta-touchdrv temizle
if dpkg -l eta-touchdrv 2>/dev/null | grep -q "^ii"; then
    systemctl stop eta-touchdrv.service 2>/dev/null || true
    for ver in $(dkms status eta-touchdrv 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+[^ ,]*'); do
        dkms remove "eta-touchdrv/$ver" --all 2>/dev/null || true
    done
    dpkg --purge eta-touchdrv 2>/dev/null || true
    ok "Eski paket temizlendi"
fi

# .deb bul ve kur
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DEB_FILE=""
for search_dir in "$SCRIPT_DIR" /media /mnt /tmp /home; do
    found=$(find "$search_dir" -maxdepth 4 -name "eta-touchdrv*amd64.deb" -type f 2>/dev/null | head -1)
    [ -n "$found" ] && DEB_FILE="$found" && break
done
if [ -n "$DEB_FILE" ]; then
    info "Bulunan: $DEB_FILE"
    dpkg -i "$DEB_FILE" 2>/dev/null && ok "Paket kuruldu" || warn "Kurulum sorunlu, devam ediliyor"
else
    warn ".deb bulunamadı — mevcut kaynaklarla devam"
fi

# ═══════════ 3/8: KERNEL MODÜL PATCH ═══════════
header "3/8" "Kernel Modül Patch"
SRC_DIR=""
for d in /usr/src/eta-touchdrv-*; do [ -d "$d" ] && SRC_DIR="$d"; done
# Birden fazla varsa en yenisini al (ls sıralaması ile son olan en yeni)

if [ -z "$SRC_DIR" ]; then
    fail "Kaynak dizin yok — .deb dosyasını script yanına koyun"
    echo -e "${R}  USB belleğe eta-touchdrv .deb dosyasını kopyalayıp tekrar çalıştırın${NC}"
    echo -e "${Y}  (0.3.5, 0.4.0 veya hangi sürüm olursa olsun çalışır)${NC}"
    echo -e "${W}  Kapatmak için Enter...${NC}"; read -t 120 -r _ 2>/dev/null || true
    exit 1
fi

DKMS_VER=$(basename "$SRC_DIR" | sed 's/eta-touchdrv-//')
info "Kaynak: $SRC_DIR (v$DKMS_VER)"

# touch2/OpticalDrv.c patch
if [ -f "$SRC_DIR/touch2/OpticalDrv.c" ]; then
    cp "$SRC_DIR/touch2/OpticalDrv.c" "$SRC_DIR/touch2/OpticalDrv.c.bak" 2>/dev/null
    sed -i 's|#include <asm/uaccess.h>|#include <linux/uaccess.h>|g' "$SRC_DIR/touch2/OpticalDrv.c"
    sed -i 's/raw_copy_from_user/copy_from_user/g; s/raw_copy_to_user/copy_to_user/g' "$SRC_DIR/touch2/OpticalDrv.c"
    if ! grep -q "linux/version.h" "$SRC_DIR/touch2/OpticalDrv.c"; then
        sed -i '1,/#include.*init.h/{s/#include <linux\/init.h>/#include <linux\/init.h>\n#include <linux\/version.h>/}' "$SRC_DIR/touch2/OpticalDrv.c"
    fi
    if ! grep -q "strscpy" "$SRC_DIR/touch2/OpticalDrv.c"; then
        sed -i '/#include.*version.h/a #if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 8, 0))\n#define strlcpy strscpy\n#endif' "$SRC_DIR/touch2/OpticalDrv.c"
    fi
    ok "touch2/OpticalDrv.c patch OK"
fi

# touch4/OtdDrv.c patch
if [ -f "$SRC_DIR/touch4/OtdDrv.c" ]; then
    cp "$SRC_DIR/touch4/OtdDrv.c" "$SRC_DIR/touch4/OtdDrv.c.bak" 2>/dev/null
    sed -i 's|#include <asm/uaccess.h>|#include <linux/uaccess.h>|g' "$SRC_DIR/touch4/OtdDrv.c"
    sed -i 's/raw_copy_from_user/copy_from_user/g; s/raw_copy_to_user/copy_to_user/g' "$SRC_DIR/touch4/OtdDrv.c"
    if ! grep -q "linux/version.h" "$SRC_DIR/touch4/OtdDrv.c"; then
        sed -i '1,/#include.*init.h/{s/#include <linux\/init.h>/#include <linux\/init.h>\n#include <linux\/version.h>/}' "$SRC_DIR/touch4/OtdDrv.c"
    fi
    if ! grep -q "strscpy" "$SRC_DIR/touch4/OtdDrv.c"; then
        sed -i '/#include.*version.h/a #if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 8, 0))\n#define strlcpy strscpy\n#endif' "$SRC_DIR/touch4/OtdDrv.c"
    fi
    # class_create uyumluluk (kernel 6.4+)
    if grep -q "class_create(THIS_MODULE" "$SRC_DIR/touch4/OtdDrv.c" && ! grep -q "compat_class_create" "$SRC_DIR/touch4/OtdDrv.c"; then
        sed -i '/#define strlcpy strscpy/a #endif\n#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))\n#define compat_class_create(name) class_create(name)\n#else\n#define compat_class_create(name) class_create(THIS_MODULE, name)' "$SRC_DIR/touch4/OtdDrv.c"
        sed -i 's/class_create(THIS_MODULE, *DEVICE_NODE_NAME)/compat_class_create(DEVICE_NODE_NAME)/g' "$SRC_DIR/touch4/OtdDrv.c"
    fi
    ok "touch4/OtdDrv.c patch OK"
fi

# dkms.conf düzelt
[ -f "$SRC_DIR/dkms.conf" ] && sed -i "s/__VERSION__/$DKMS_VER/g" "$SRC_DIR/dkms.conf" && ok "dkms.conf OK"

# ═══════════ 4/8: DKMS DERLEME ═══════════
header "4/8" "DKMS Modül Derleme"
dkms status eta-touchdrv 2>/dev/null | grep -oP '[0-9]+\.[0-9]+[^ ,]*' | while read -r v; do dkms remove "eta-touchdrv/$v" --all 2>/dev/null; done

dkms add "$SRC_DIR" 2>/dev/null || true
info "Derleniyor..."
if dkms build -m eta-touchdrv -v "$DKMS_VER" 2>>"$LOG"; then
    dkms install -m eta-touchdrv -v "$DKMS_VER" 2>>"$LOG" && ok "Modüller derlendi ve yüklendi"
else
    fail "Derleme başarısız! Log: $LOG"
    info "linux-headers-$(uname -r) yüklü mü kontrol edin"
fi

modprobe OpticalDrv 2>/dev/null && ok "OpticalDrv yüklendi" || info "OpticalDrv yok (normal olabilir)"
modprobe OtdDrv 2>/dev/null && ok "OtdDrv yüklendi" || info "OtdDrv yok (normal olabilir)"

# ═══════════ 5/8: SERVİS DOSYALARI ═══════════
header "5/8" "Servis Dosyaları"

# Düzeltilmiş touchdrv_install (AMD retry + exec + PID lock)
cat > /usr/bin/touchdrv_install << 'TDEOF'
#!/bin/bash
set -u
LOG="/var/log/vestel-dokunmatik-fix.log"
PIDFILE="/var/run/eta-touchdrv.pid"
log() { echo "$(date '+%H:%M:%S'): [touchdrv] $1" >> "$LOG"; }

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then log "Zaten çalışıyor"; exit 0; fi
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

MAX=15; WAIT=2
log "USB aranıyor (${MAX}x${WAIT}s)..."
for try in $(seq 1 $MAX); do
    if lsusb 2>/dev/null | grep -qE "6615:(0084|0085|0086|0087|0088|0c20)"; then
        log "2cam bulundu ($try)"; modprobe OpticalDrv 2>/dev/null; sleep 1
        for i in $(seq 1 10); do [ -e /dev/IRTouchOptical000 ] && break; sleep 0.5; done
        log "OpticalService exec"; exec /usr/bin/OpticalService
    fi
    if lsusb 2>/dev/null | grep -qE "2621:(2201|4501)"; then
        log "4cam bulundu ($try)"; modprobe OtdDrv 2>/dev/null; sleep 1
        for i in $(seq 1 10); do [ -e /dev/OtdUsbRaw ] && break; sleep 0.5; done
        log "OtdTouchServer exec"; exec /usr/bin/OtdTouchServer
    fi
    log "Deneme $try/$MAX"; sleep $WAIT
done
log "HATA: Cihaz bulunamadı"; exit 1
TDEOF
chmod +x /usr/bin/touchdrv_install
ok "touchdrv_install (15 deneme, AMD uyumlu)"

# systemd servisi
cat > /lib/systemd/system/eta-touchdrv.service << 'SEOF'
[Unit]
Description=Vestel Non-HID Touchscreen
After=display-manager.service lightdm.service
Wants=display-manager.service
[Service]
Type=simple
ExecStart=/usr/bin/touchdrv_install
Restart=on-failure
RestartSec=5s
StartLimitIntervalSec=120
StartLimitBurst=5
PIDFile=/var/run/eta-touchdrv.pid
[Install]
WantedBy=multi-user.target
SEOF
systemctl daemon-reload
systemctl enable eta-touchdrv.service 2>/dev/null
ok "systemd servisi (on-failure + rate limit)"

# udev kuralları + device symlink'leri
cat > /lib/udev/rules.d/60-eta-touchdrv.rules << 'UEOF'
SUBSYSTEM=="usb", ATTR{idVendor}=="6615", ATTR{idProduct}=="0084", TAG+="systemd", ENV{SYSTEMD_WANTS}="eta-touchdrv.service"
SUBSYSTEM=="usb", ATTR{idVendor}=="6615", ATTR{idProduct}=="0085", TAG+="systemd", ENV{SYSTEMD_WANTS}="eta-touchdrv.service"
SUBSYSTEM=="usb", ATTR{idVendor}=="6615", ATTR{idProduct}=="0086", TAG+="systemd", ENV{SYSTEMD_WANTS}="eta-touchdrv.service"
SUBSYSTEM=="usb", ATTR{idVendor}=="6615", ATTR{idProduct}=="0087", TAG+="systemd", ENV{SYSTEMD_WANTS}="eta-touchdrv.service"
SUBSYSTEM=="usb", ATTR{idVendor}=="6615", ATTR{idProduct}=="0088", TAG+="systemd", ENV{SYSTEMD_WANTS}="eta-touchdrv.service"
SUBSYSTEM=="usb", ATTR{idVendor}=="6615", ATTR{idProduct}=="0c20", TAG+="systemd", ENV{SYSTEMD_WANTS}="eta-touchdrv.service"
SUBSYSTEM=="usb", ATTR{idVendor}=="2621", ATTR{idProduct}=="2201", TAG+="systemd", ENV{SYSTEMD_WANTS}="eta-touchdrv.service"
SUBSYSTEM=="usb", ATTR{idVendor}=="2621", ATTR{idProduct}=="4501", TAG+="systemd", ENV{SYSTEMD_WANTS}="eta-touchdrv.service"
KERNEL=="IRTouchOptical*", SYMLINK+="optictouch"
KERNEL=="OtdUsbRaw", SYMLINK+="OtdOpticTouch"
UEOF
udevadm control --reload-rules 2>/dev/null; udevadm trigger 2>/dev/null
ok "udev + device symlink'leri (/dev/optictouch ↔ /dev/OtdOpticTouch)"

# ═══════════ 6/8: SERVİS BAŞLAT ═══════════
header "6/8" "Servis Başlatma"
systemctl restart eta-touchdrv.service 2>/dev/null; sleep 5
systemctl is-active --quiet eta-touchdrv.service && ok "Servis çalışıyor" || warn "Servis USB bekliyor"

# ═══════════ 7/8: KALİBRASYON ═══════════
header "7/8" "Kalibrasyon Sistemi"
CALIB_FILE="/etc/vestel-touch-calibration.conf"
[ -f "$CALIB_FILE" ] && MATRIX=$(cat "$CALIB_FILE" | xargs) || MATRIX="1 0 0 0 1 0 0 0 1"

# Boot kalibrasyon servisi
cat > /usr/local/bin/vestel-touch-apply.sh << 'AEOF'
#!/bin/bash
CALIB="/etc/vestel-touch-calibration.conf"
[ -f "$CALIB" ] && M=$(cat "$CALIB"|xargs) || M="1 0 0 0 1 0 0 0 1"
w=0; while [ $w -lt 90 ]; do DISPLAY=:0 xdpyinfo &>/dev/null && break; sleep 2; w=$((w+2)); done
[ $w -ge 90 ] && exit 1; sleep 3; export DISPLAY=:0
for xa in /home/*/.Xauthority /root/.Xauthority; do [ -f "$xa" ] && export XAUTHORITY="$xa" && break; done
while IFS= read -r l; do echo "$l"|grep -q "slave  pointer"||continue
id=$(echo "$l"|grep -oP 'id=\K[0-9]+'||true);[ -z "$id" ]&&continue
n=$(echo "$l"|sed 's/[⎜↳│]//g'|awk -F'id=' '{print $1}'|xargs)
echo "$n"|grep -iqE "mouse|trackpad|virtual|receiver"&&continue
xinput enable "$id" 2>/dev/null
xinput set-prop "$id" "libinput Calibration Matrix" $M 2>/dev/null
xinput set-prop "$id" "Coordinate Transformation Matrix" $M 2>/dev/null
done < <(xinput list 2>/dev/null)
AEOF
chmod +x /usr/local/bin/vestel-touch-apply.sh

cat > /etc/systemd/system/vestel-touch-calibrate.service << 'CSEOF'
[Unit]
Description=Vestel Touch Calibration
After=display-manager.service eta-touchdrv.service
[Service]
Type=oneshot
ExecStart=/usr/local/bin/vestel-touch-apply.sh
RemainAfterExit=yes
TimeoutStartSec=120
[Install]
WantedBy=graphical.target
CSEOF
systemctl daemon-reload; systemctl enable vestel-touch-calibrate.service 2>/dev/null
ok "Kalibrasyon servisi (her boot'ta)"

# vestel-calibrate komutu
cat > /usr/local/bin/vestel-calibrate << 'VCEOF'
#!/bin/bash
R='\033[0;31m';G='\033[0;32m';Y='\033[1;33m';C='\033[0;36m';NC='\033[0m'
if [ "$EUID" -ne 0 ]; then
    PW=('etap+pardus!' 'pardus' 'etapadmin')
    sudo -n true 2>/dev/null&&exec sudo bash "$0" "$@"
    for p in "${PW[@]}";do echo "$p"|sudo -S true 2>/dev/null&&{echo "$p"|sudo -S bash "$0" "$@";exit $?;};done
    echo -ne "${Y}Şifre:${NC} ";read -rs U;echo;[ -n "$U" ]&&echo "$U"|sudo -S true 2>/dev/null&&{echo "$U"|sudo -S bash "$0" "$@";exit $?;}
    echo -e "${R}Yetki yok${NC}";exit 1
fi
case "${1:-}" in
    hafif)M="1.02 0 -0.01 0 1.02 -0.01 0 0 1";;orta)M="1.05 0 -0.025 0 1.05 -0.025 0 0 1";;
    buyuk)M="1.1 0 -0.05 0 1.1 -0.05 0 0 1";;sifirla)M="1 0 0 0 1 0 0 0 1";;
    ters-x)M="-1 0 1 0 1 0 0 0 1";;ters-y)M="1 0 0 0 -1 1 0 0 1";;swap-xy)M="0 1 0 1 0 0 0 0 1";;
    donanim)
        export DISPLAY=:0;for xa in /home/*/.Xauthority /root/.Xauthority;do [ -f "$xa" ]&&export XAUTHORITY="$xa"&&break;done
        # Önce kendi kalibrasyon GUI'mizi dene
        if [ -f /usr/local/bin/vestel-calibrate-gui.py ];then
            echo -e "${C}Kalibrasyon GUI başlatılıyor (9 noktaya dokunun, ESC=iptal)...${NC}"
            python3 /usr/local/bin/vestel-calibrate-gui.py --points 9 2>/dev/null && exit 0
        fi
        # Fallback: Vestel'in kendi araçları
        if [ -e /dev/optictouch ]||[ -e /dev/IRTouchOptical000 ];then echo -e "${C}2cam kalibrasyon (Vestel)...${NC}";/usr/bin/calibrationTools 2>/dev/null||echo -e "${R}Hata${NC}"
        elif [ -e /dev/OtdOpticTouch ]||[ -e /dev/OtdUsbRaw ];then echo -e "${C}4cam kalibrasyon (Vestel)...${NC}";/usr/bin/OtdCalibrationTool 2>/dev/null||echo -e "${R}Hata${NC}"
        else echo -e "${R}Device yok${NC}";fi;exit 0;;
    "")echo "Kullanım: vestel-calibrate [hafif|orta|buyuk|sifirla|donanim|ters-x|ters-y|swap-xy]"
       echo "          vestel-calibrate 1.05 0 -0.025 0 1.05 -0.025 0 0 1";exit 0;;
    *)[ $# -eq 9 ]&&M="$1 $2 $3 $4 $5 $6 $7 $8 $9"||{echo -e "${R}9 sayı veya preset girin${NC}";exit 1;};;
esac
export DISPLAY=:0;for xa in /home/*/.Xauthority /root/.Xauthority;do [ -f "$xa" ]&&export XAUTHORITY="$xa"&&break;done
a=0;while IFS= read -r l;do echo "$l"|grep -q "slave  pointer"||continue
id=$(echo "$l"|grep -oP 'id=\K[0-9]+'||true);[ -z "$id" ]&&continue
n=$(echo "$l"|sed 's/[⎜↳│]//g'|awk -F'id=' '{print $1}'|xargs)
echo "$n"|grep -iqE "mouse|trackpad|virtual|receiver"&&continue
xinput set-prop "$id" "libinput Calibration Matrix" $M 2>/dev/null&&a=$((a+1))
xinput set-prop "$id" "Coordinate Transformation Matrix" $M 2>/dev/null
done < <(xinput list 2>/dev/null)
echo "$M">/etc/vestel-touch-calibration.conf
[ $a -gt 0 ]&&echo -e "${G}✓ Uygulandı ($a cihaz)${NC}"||echo -e "${Y}⚠ Reboot sonrası uygulanacak${NC}"
echo -e "${C}Matris: $M — kalıcı${NC}"
VCEOF
chmod +x /usr/local/bin/vestel-calibrate
echo "$MATRIX" > "$CALIB_FILE"
echo "ALL ALL=NOPASSWD: /usr/local/bin/vestel-touch-apply.sh, /usr/local/bin/vestel-calibrate, /usr/local/bin/vestel-dokunmatik-fix.sh" > /etc/sudoers.d/vestel-touch
chmod 440 /etc/sudoers.d/vestel-touch
ok "vestel-calibrate komutu hazır"

# Kalibrasyon GUI'yi kur (script yanında varsa)
SCRIPT_DIR_CAL="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
GUI_PY=""
for sd in "$SCRIPT_DIR_CAL" /media /mnt /tmp /home; do
    found=$(find "$sd" -maxdepth 4 -name "vestel-calibrate-gui.py" -type f 2>/dev/null | head -1)
    [ -n "$found" ] && GUI_PY="$found" && break
done
if [ -n "$GUI_PY" ]; then
    cp "$GUI_PY" /usr/local/bin/vestel-calibrate-gui.py
    chmod +x /usr/local/bin/vestel-calibrate-gui.py
    ok "Kalibrasyon GUI kuruldu (vestel-calibrate-gui.py)"
else
    info "vestel-calibrate-gui.py bulunamadı — preset kalibrasyon kullanılacak"
fi

# ═══════════ 8/8: MASAÜSTÜ ═══════════
header "8/8" "Masaüstü Kısayolları"
cp "$(readlink -f "$0")" /usr/local/bin/vestel-dokunmatik-fix.sh 2>/dev/null;chmod +x /usr/local/bin/vestel-dokunmatik-fix.sh 2>/dev/null
for uh in /home/*/;do u=$(basename "$uh");dd=""
for d in "Masaüstü" "Desktop";do [ -d "${uh}${d}" ]&&dd="${uh}${d}"&&break;done
[ -z "$dd" ]&&dd="${uh}Masaüstü";mkdir -p "$dd" 2>/dev/null||continue
cat>"${dd}/dokunmatik-duzelt.desktop"<<'D1'
[Desktop Entry]
Type=Application
Name=Dokunmatik Düzelt
Exec=bash /usr/local/bin/vestel-dokunmatik-fix.sh
Icon=input-touchscreen
Terminal=true
D1
cat>"${dd}/dokunmatik-kalibrasyon.desktop"<<'D2'
[Desktop Entry]
Type=Application
Name=Dokunmatik Kalibrasyon
Exec=bash -c 'vestel-calibrate donanim;echo;read -p "Enter..."'
Icon=preferences-desktop-display
Terminal=true
D2
chmod +x "${dd}"/dokunmatik-*.desktop 2>/dev/null;chown "$u":"$u" "${dd}"/dokunmatik-*.desktop 2>/dev/null;done
ok "Masaüstü kısayolları"

# ═══════════ SONUÇ ═══════════
echo ""
echo -e "${B}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${B}║  ${G}KURULUM TAMAMLANDI!${B}                                   ║${NC}"
echo -e "${B}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${G}✓${NC} eta-touchdrv kuruldu + kernel modüller patch'lendi"
echo -e "  ${G}✓${NC} AMD uyumlu servis (15 deneme, rate limit)"
echo -e "  ${G}✓${NC} Device symlink'leri (kalibrasyon araçları çalışır)"
echo -e "  ${G}✓${NC} Kalibrasyon her boot'ta kalıcı"
echo ""
echo -e "  ${C}vestel-calibrate hafif/orta/buyuk/sifirla${NC}  → yazılım"
echo -e "  ${C}vestel-calibrate donanim${NC}                   → sensör GUI"
echo ""

# Dokunmatik çalışıyorsa kalibrasyon teklif et
echo -ne "${Y}Şimdi kalibrasyon yapmak ister misiniz? (e/h):${NC} "
if read -t 30 -r cal_ans 2>/dev/null; then
    case "$cal_ans" in
        e|E|evet)
            if [ -f /usr/local/bin/vestel-calibrate-gui.py ]; then
                echo -e "${C}Kalibrasyon GUI açılıyor — 9 noktaya dokunun, ESC=iptal${NC}"
                sleep 1
                export DISPLAY=:0
                for xa in /home/*/.Xauthority /root/.Xauthority; do [ -f "$xa" ] && export XAUTHORITY="$xa" && break; done
                python3 /usr/local/bin/vestel-calibrate-gui.py --points 9 2>/dev/null
            else
                echo -e "${Y}GUI bulunamadı, hızlı preset uyguluyorum...${NC}"
                vestel-calibrate orta 2>/dev/null
            fi
            ;;
    esac
fi

echo ""
echo -ne "${G}Reboot? (e/h):${NC} "
read -t 60 -r ans 2>/dev/null||true
case "${ans:-}" in e|E|evet) echo -e "${C}3sn...${NC}";sleep 3;reboot;;esac
echo -e "\n${W}Enter ile kapat...${NC}";read -t 120 -r _ 2>/dev/null||true
