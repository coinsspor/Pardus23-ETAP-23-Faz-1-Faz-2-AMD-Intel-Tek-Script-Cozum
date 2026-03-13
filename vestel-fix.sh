#!/bin/bash
#===============================================================================
#  VESTEL AKILLI TAHTA - SURUCU KURULUM
#  Pardus 23 / ETAP 23 — Faz-1 & Faz-2 — AMD & Intel
#
#  SADECE surucu kurar, kernel modulu derler, servisi aktif eder
#  Orijinal touchdrv_install ve servis dosyasina DOKUNMAZ
#  Kalibrasyon AYRI program (vestel-calibrate-gui.py)
#===============================================================================

set -uo pipefail

R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m'
B='\033[0;34m' C='\033[0;36m' W='\033[1;37m' NC='\033[0m'

ok()   { echo -e "  ${G}✓${NC} $1"; }
warn() { echo -e "  ${Y}⚠${NC} $1"; }
fail() { echo -e "  ${R}✗${NC} $1"; }
info() { echo -e "  ${C}→${NC} $1"; }
step() { echo -e "\n${B}[$1]${NC} ${W}$2${NC}\n  ─────────────────────────────────────"; }

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

# ═══ ROOT YETKİ ═══
if [ "$EUID" -ne 0 ]; then
    PW=('etap+pardus!' 'etap+pardus' 'pardus' 'etapadmin' '123456' 'pardus23' 'etap23')
    if sudo -n true 2>/dev/null; then exec sudo bash "$0" "$@"; fi
    for p in "${PW[@]}"; do
        if echo "$p" | sudo -S true 2>/dev/null; then echo "$p" | sudo -S bash "$0" "$@"; exit $?; fi
    done
    for p in "${PW[@]}"; do
        echo "$p" | su -c "echo ok" root 2>/dev/null | grep -q "ok" && { echo "$p" | su -c "bash '$(readlink -f "$0")' $*" root; exit $?; }
    done
    for i in 1 2 3; do
        echo -ne "  ${W}Sifre ($i/3):${NC} "; read -rs UP </dev/tty; echo
        [ -n "$UP" ] && echo "$UP" | sudo -S true 2>/dev/null && { echo "$UP" | sudo -S bash "$0" "$@"; exit $?; }
        echo -e "${R}  Yanlis.${NC}"
    done
    echo -e "${R}Yetki alinamadi.${NC}"; exit 1
fi

clear
echo -e "${B}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${B}║  ${W}VESTEL DOKUNMATIK SURUCU KURULUM${B}             ║${NC}"
echo -e "${B}║  ${C}Pardus 23 — Faz-1 & Faz-2 — AMD & Intel${B}    ║${NC}"
echo -e "${B}╚═══════════════════════════════════════════════╝${NC}"

# ═══ 1/4: SİSTEM TESPİT ═══
step "1/4" "Sistem Tespit"
KVER=$(uname -r)
CPU="?"; grep -qi amd /proc/cpuinfo && CPU="AMD"; grep -qi intel /proc/cpuinfo && CPU="Intel"
info "Kernel: $KVER | CPU: $CPU"

if lsusb 2>/dev/null | grep -qE "6615:(0084|0085|0086|0087|0088|0c20)"; then
    ok "2-Kamerali tahta (IRTOUCH)"
elif lsusb 2>/dev/null | grep -qE "2621:(2201|4501)"; then
    ok "4-Kamerali tahta"
else
    warn "Dokunmatik USB cihazi bulunamadi — kablo kontrol edin"
fi

# ═══ 2/4: PAKET KURULUM ═══
step "2/4" "Paket Kurulum"

# Gerekli paketler
NEED=""
for pkg in dkms build-essential "linux-headers-$KVER" xinput python3-tk; do
    dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" || NEED="$NEED $pkg"
done
if [ -n "$NEED" ]; then
    info "Eksik paketler:$NEED"
    apt-get update -qq 2>/dev/null
    apt-get install -y -qq $NEED 2>/dev/null && ok "Paketler kuruldu" || warn "Bazi paketler kurulamadi"
else
    ok "Sistem paketleri tamam"
fi

# eta-touchdrv
if dpkg -l eta-touchdrv 2>/dev/null | grep -q "^ii"; then
    ok "eta-touchdrv zaten kurulu"
else
    DEB=$(find "$SCRIPT_DIR" /media /mnt /home -maxdepth 4 -name "eta-touchdrv*amd64.deb" -type f 2>/dev/null | head -1)
    if [ -n "$DEB" ]; then
        info "Kuruluyor: $DEB"
        dpkg -i "$DEB" 2>/dev/null && ok "Paket kuruldu" || warn "Kurulum sorunlu"
    else
        fail "Flash'ta .deb bulunamadi!"; echo -e "\n${W}Enter...${NC}"; read -t 120 -r _ </dev/tty 2>/dev/null || true; exit 1
    fi
fi

# ═══ 3/4: KERNEL MODÜL ═══
step "3/4" "Kernel Modul"

if dkms status 2>/dev/null | grep -q "eta-touchdrv.*$KVER.*installed"; then
    ok "Modul zaten derlenip yuklu"
else
    SRC=""
    for d in /usr/src/eta-touchdrv-*; do [ -d "$d" ] && SRC="$d"; done
    if [ -n "$SRC" ]; then
        VER=$(basename "$SRC" | sed 's/eta-touchdrv-//')
        
        # Patch (sadece gerekli olanlar)
        for f in "$SRC/touch2/OpticalDrv.c" "$SRC/touch4/OtdDrv.c"; do
            [ ! -f "$f" ] && continue
            grep -q "asm/uaccess.h" "$f" && sed -i 's|#include <asm/uaccess.h>|#include <linux/uaccess.h>|g' "$f"
            grep -q "raw_copy_from_user" "$f" && sed -i 's/raw_copy_from_user/copy_from_user/g; s/raw_copy_to_user/copy_to_user/g' "$f"
            grep -q "linux/version.h" "$f" || sed -i '/#include <linux\/init.h>/a #include <linux/version.h>' "$f"
            grep -q "strlcpy" "$f" && ! grep -q "strscpy" "$f" && sed -i '/#include.*version.h/a #if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 8, 0))\n#define strlcpy strscpy\n#endif' "$f"
            echo "$f" | grep -q "OtdDrv" && grep -q "class_create(THIS_MODULE" "$f" && ! grep -q "compat_class_create" "$f" && {
                sed -i '/strlcpy strscpy/a #endif\n#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))\n#define compat_class_create(name) class_create(name)\n#else\n#define compat_class_create(name) class_create(THIS_MODULE, name)' "$f"
                sed -i 's/class_create(THIS_MODULE, *DEVICE_NODE_NAME)/compat_class_create(DEVICE_NODE_NAME)/g' "$f"
            }
        done
        [ -f "$SRC/dkms.conf" ] && sed -i "s/__VERSION__/$VER/g" "$SRC/dkms.conf"
        
        info "Derleniyor..."
        dkms add "$SRC" 2>/dev/null || true
        dkms build -m eta-touchdrv -v "$VER" 2>/dev/null && dkms install -m eta-touchdrv -v "$VER" 2>/dev/null && ok "Modul derlendi" || fail "Derleme basarisiz"
    else
        fail "Kaynak dizin yok"
    fi
fi

lsmod | grep -q "OtdDrv" || modprobe OtdDrv 2>/dev/null
lsmod | grep -q "OpticalDrv" || modprobe OpticalDrv 2>/dev/null

# ═══ 4/4: SERVİS ═══
step "4/4" "Servis"

systemctl enable eta-touchdrv.service 2>/dev/null
ok "Servis enabled"

if ! systemctl is-active --quiet eta-touchdrv.service; then
    systemctl restart eta-touchdrv.service 2>/dev/null
    sleep 5
fi
systemctl is-active --quiet eta-touchdrv.service && ok "Servis calisiyor" || warn "Servis baslamadi"

# Sonuç
echo ""
echo -e "${B}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${B}║  ${G}SURUCU KURULUMU TAMAMLANDI${B}                   ║${NC}"
echo -e "${B}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${Y}Kalibrasyon icin ayri programi calistirin:${NC}"
echo -e "  ${C}python3 vestel-calibrate-gui.py${NC}"
echo ""
echo -ne "${G}Reboot? (e/h):${NC} "
read -t 60 -r ans </dev/tty 2>/dev/null || true
case "${ans:-}" in e|E|evet) echo -e "${C}3sn...${NC}";sleep 3;reboot;;esac
echo -e "\n${W}Enter...${NC}"; read -t 120 -r _ </dev/tty 2>/dev/null || true
