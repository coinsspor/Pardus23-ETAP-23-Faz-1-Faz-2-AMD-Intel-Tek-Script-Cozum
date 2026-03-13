#!/usr/bin/env python3
"""
VESTEL AKILLI TAHTA — DOKUNMATIK KALIBRASYON
Bagimsiz program — internetsiz calisir, tek basina her seyi yapar

Yaptiklarini:
1. Fullscreen 9 noktali kalibrasyon ekrani acar
2. Her noktaya dokunulunca koordinat kaydeder
3. Matris hesaplar
4. /etc/vestel-touch-calibration.conf dosyasina kaydeder
5. xinput ile aninda uygular
6. Boot servisi kurar (yoksa) — her restart'ta otomatik uygular

Kullanim: python3 vestel-calibrate-gui.py
"""
import os, sys, subprocess

# ═══════════════════════════════════════════════
# ROOT YETKİ
# ═══════════════════════════════════════════════
def get_root():
    if os.geteuid() == 0:
        return True
    passwords = ["etap+pardus!", "etap+pardus", "pardus", "etapadmin", "123456", "pardus23", "etap23"]
    for pw in passwords:
        ret = os.system(f'echo "{pw}" | sudo -S true 2>/dev/null')
        if ret == 0:
            script = os.path.abspath(sys.argv[0])
            args = " ".join(sys.argv[1:])
            os.system(f'echo "{pw}" | sudo -S python3 "{script}" {args}')
            sys.exit(0)
    print("Root yetkisi gerekli. Bilinen sifreler tutmadi.")
    print("sudo python3 vestel-calibrate-gui.py")
    sys.exit(1)

# ═══════════════════════════════════════════════
# MATRIS HESAPLAMA (least squares)
# ═══════════════════════════════════════════════
def calc_matrix(screen_pts, touch_pts, sw, sh):
    n = len(screen_pts)
    if n < 3:
        return [1, 0, 0, 0, 1, 0, 0, 0, 1]
    
    ns = [(x / sw, y / sh) for x, y in screen_pts]
    nt = [(x / sw, y / sh) for x, y in touch_pts]

    def solve3x3(M, v):
        det = (M[0][0] * (M[1][1] * M[2][2] - M[1][2] * M[2][1])
             - M[0][1] * (M[1][0] * M[2][2] - M[1][2] * M[2][0])
             + M[0][2] * (M[1][0] * M[2][1] - M[1][1] * M[2][0]))
        if abs(det) < 1e-10:
            return [1, 0, 0]
        r = [0, 0, 0]
        for i in range(3):
            mc = [row[:] for row in M]
            for j in range(3):
                mc[j][i] = v[j]
            di = (mc[0][0] * (mc[1][1] * mc[2][2] - mc[1][2] * mc[2][1])
                - mc[0][1] * (mc[1][0] * mc[2][2] - mc[1][2] * mc[2][0])
                + mc[0][2] * (mc[1][0] * mc[2][1] - mc[1][1] * mc[2][0]))
            r[i] = di / det
        return r

    s2x = sum(t[0]**2 for t in nt)
    s2y = sum(t[1]**2 for t in nt)
    sxy = sum(t[0] * t[1] for t in nt)
    sx = sum(t[0] for t in nt)
    sy = sum(t[1] for t in nt)
    M = [[s2x, sxy, sx], [sxy, s2y, sy], [sx, sy, n]]

    abc = solve3x3(M, [
        sum(s[0] * t[0] for s, t in zip(ns, nt)),
        sum(s[0] * t[1] for s, t in zip(ns, nt)),
        sum(s[0] for s in ns)
    ])
    deff = solve3x3(M, [
        sum(s[1] * t[0] for s, t in zip(ns, nt)),
        sum(s[1] * t[1] for s, t in zip(ns, nt)),
        sum(s[1] for s in ns)
    ])
    return [round(v, 6) for v in abc + deff + [0, 0, 1]]

# ═══════════════════════════════════════════════
# KAYDET + UYGULA + BOOT SERVİSİ KUR
# ═══════════════════════════════════════════════
CALIB_FILE = "/etc/vestel-touch-calibration.conf"
APPLY_SCRIPT = "/usr/local/bin/vestel-touch-apply.sh"
SERVICE_FILE = "/etc/systemd/system/vestel-touch-calibrate.service"

def save_calibration(matrix):
    """Matrisi dosyaya kaydet"""
    ms = " ".join(str(v) for v in matrix)
    with open(CALIB_FILE, "w") as f:
        f.write(ms + "\n")
    print(f"  Kaydedildi: {CALIB_FILE}")
    return ms

def apply_calibration(ms):
    """xinput ile aninda uygula"""
    try:
        import re
        r = subprocess.run(["xinput", "list"], capture_output=True, text=True)
        applied = 0
        for line in r.stdout.split("\n"):
            if "slave  pointer" not in line:
                continue
            m = re.search(r"id=(\d+)", line)
            if not m:
                continue
            did = m.group(1)
            nl = line.lower()
            if any(s in nl for s in ["mouse", "trackpad", "virtual", "receiver", "keyboard", "power", "video"]):
                continue
            subprocess.run(["xinput", "set-prop", did, "libinput Calibration Matrix"] + ms.split(), capture_output=True)
            subprocess.run(["xinput", "set-prop", did, "Coordinate Transformation Matrix"] + ms.split(), capture_output=True)
            name = line.strip().split("id=")[0].replace("↳", "").replace("⎜", "").strip()
            print(f"  Uygulandi: {name} (id={did})")
            applied += 1
        if applied == 0:
            print("  Dokunmatik cihaz bulunamadi — reboot sonrasi uygulanacak")
    except Exception as e:
        print(f"  xinput hatasi: {e}")

def install_boot_service():
    """Her restart'ta kalibrasyonu otomatik uygulayan servisi kur"""

    # Apply script
    apply_script = '''#!/bin/bash
CALIB="/etc/vestel-touch-calibration.conf"
[ -f "$CALIB" ] || exit 0
M=$(cat "$CALIB" | xargs)
[ "$M" = "1 0 0 0 1 0 0 0 1" ] && exit 0

# X11 bekle
w=0; while [ $w -lt 90 ]; do
    DISPLAY=:0 xdpyinfo &>/dev/null && break
    sleep 2; w=$((w+2))
done
[ $w -ge 90 ] && exit 1
sleep 5

export DISPLAY=:0
for xa in /home/*/.Xauthority /root/.Xauthority; do
    [ -f "$xa" ] && export XAUTHORITY="$xa" && break
done

while IFS= read -r l; do
    echo "$l" | grep -q "slave  pointer" || continue
    id=$(echo "$l" | grep -oP 'id=\\K[0-9]+' || true)
    [ -z "$id" ] && continue
    n=$(echo "$l" | sed 's/[⎜↳│]//g' | awk -F'id=' '{print $1}' | xargs)
    echo "$n" | grep -iqE "mouse|trackpad|virtual|receiver|keyboard|power|video" && continue
    xinput set-prop "$id" "libinput Calibration Matrix" $M 2>/dev/null
    xinput set-prop "$id" "Coordinate Transformation Matrix" $M 2>/dev/null
done < <(xinput list 2>/dev/null)
'''

    service_unit = '''[Unit]
Description=Vestel Touch Calibration
After=display-manager.service eta-touchdrv.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/vestel-touch-apply.sh
RemainAfterExit=yes
TimeoutStartSec=120

[Install]
WantedBy=graphical.target
'''

    # Dosyalari yaz
    with open(APPLY_SCRIPT, "w") as f:
        f.write(apply_script)
    os.chmod(APPLY_SCRIPT, 0o755)

    if not os.path.exists(SERVICE_FILE):
        with open(SERVICE_FILE, "w") as f:
            f.write(service_unit)
        os.system("systemctl daemon-reload")
        os.system("systemctl enable vestel-touch-calibrate.service 2>/dev/null")
        print("  Boot servisi kuruldu — her restart'ta otomatik uygulanacak")
    else:
        print("  Boot servisi zaten kurulu")

    # sudoers
    sudoers = "/etc/sudoers.d/vestel-touch"
    if not os.path.exists(sudoers):
        with open(sudoers, "w") as f:
            f.write("ALL ALL=NOPASSWD: /usr/local/bin/vestel-touch-apply.sh\n")
        os.chmod(sudoers, 0o440)

# ═══════════════════════════════════════════════
# tkinter KALİBRASYON GUI
# ═══════════════════════════════════════════════
def reset_matrix():
    """Kalibrasyon oncesi matrisi identity'ye sifirla — 
    boylece dokunma verileri ham/dogru gelir"""
    import re
    identity = "1 0 0 0 1 0 0 0 1"
    try:
        r = subprocess.run(["xinput", "list"], capture_output=True, text=True)
        for line in r.stdout.split("\n"):
            if "slave  pointer" not in line:
                continue
            m = re.search(r"id=(\d+)", line)
            if not m:
                continue
            did = m.group(1)
            nl = line.lower()
            if any(s in nl for s in ["mouse", "trackpad", "virtual", "receiver", "keyboard", "power", "video"]):
                continue
            subprocess.run(["xinput", "set-prop", did, "libinput Calibration Matrix"] + identity.split(), capture_output=True)
            subprocess.run(["xinput", "set-prop", did, "Coordinate Transformation Matrix"] + identity.split(), capture_output=True)
        print("  Matris sifirlandi (kalibrasyon icin)")
    except:
        pass

def run_calibration(num_points=9):
    import tkinter as tk
    import time

    # KRITIK: Kalibrasyon oncesi matrisi sifirla
    # Yoksa bozuk matris uzerinden bozuk veri gelir
    reset_matrix()

    root = tk.Tk()
    root.attributes("-fullscreen", True)
    root.configure(bg="black", cursor="none")
    root.title("Vestel Kalibrasyon")

    canvas = tk.Canvas(root, bg="black", highlightthickness=0)
    canvas.pack(fill="both", expand=True)

    root.update_idletasks()
    sw = root.winfo_screenwidth()
    sh = root.winfo_screenheight()

    # Hedef noktalar (%10 margin)
    mx, my = int(sw * 0.1), int(sh * 0.1)
    cx, cy = sw // 2, sh // 2
    if num_points == 9:
        targets = [
            (mx, my), (cx, my), (sw - mx, my),
            (mx, cy), (cx, cy), (sw - mx, cy),
            (mx, sh - my), (cx, sh - my), (sw - mx, sh - my),
        ]
    else:
        targets = [(mx, my), (sw - mx, my), (mx, sh - my), (sw - mx, sh - my)]

    touches = []
    state = {"cur": 0, "result": None, "locked": False}
    CS = 40

    def draw():
        canvas.delete("all")
        cur = state["cur"]
        total = len(targets)

        if state["result"] is None:
            # Üst bilgi
            canvas.create_rectangle(0, 0, sw, 55, fill="#1a1a2e", outline="")
            canvas.create_text(sw // 2, 18,
                text=f"DOKUNMATIK KALIBRASYON  [{cur}/{total}]",
                fill="white", font=("Arial", 14, "bold"))
            canvas.create_text(sw // 2, 40,
                text="Kirmizi + isaretinin TAM ORTASINA parmagini bas  |  ESC = iptal",
                fill="#AAAAAA", font=("Arial", 11))

            # İlerleme çubuğu
            pw = int((cur / total) * (sw - 40))
            canvas.create_rectangle(20, 52, sw - 20, 56, fill="#003300", outline="")
            if pw > 0:
                canvas.create_rectangle(20, 52, 20 + pw, 56, fill="#00CC00", outline="")

            # Tamamlanan — yeşil tik
            for i in range(cur):
                px, py = targets[i]
                canvas.create_line(px - 15, py, px - 5, py + 15, fill="#00CC00", width=4)
                canvas.create_line(px - 5, py + 15, px + 20, py - 12, fill="#00CC00", width=4)
                canvas.create_text(px + 25, py - 20, text=f"{i+1}",
                    fill="#00AA00", font=("Arial", 11))

            # Aktif — kırmızı büyük +
            if cur < total:
                px, py = targets[cur]
                canvas.create_oval(px-CS*1.5, py-CS*1.5, px+CS*1.5, py+CS*1.5,
                    outline="#FF4444", width=2, dash=(6, 4))
                canvas.create_oval(px-CS*0.7, py-CS*0.7, px+CS*0.7, py+CS*0.7,
                    outline="#FF6666", width=3)
                canvas.create_line(px - CS, py, px + CS, py, fill="#FF4444", width=4)
                canvas.create_line(px, py - CS, px, py + CS, fill="#FF4444", width=4)
                canvas.create_text(px + CS + 18, py - CS, text=str(cur + 1),
                    fill="#FF4444", font=("Arial", 20, "bold"))
                canvas.create_text(px, py + CS + 25, text="BURAYA DOKUN",
                    fill="#FF6666", font=("Arial", 11, "bold"))

            # Bekleyen — gri +
            for i in range(cur + 1, total):
                px, py = targets[i]
                canvas.create_line(px - 15, py, px + 15, py, fill="#333333", width=1)
                canvas.create_line(px, py - 15, px, py + 15, fill="#333333", width=1)
                canvas.create_text(px + 20, py - 15, text=str(i + 1),
                    fill="#333333", font=("Arial", 10))
        else:
            # Tamamlandı
            canvas.create_rectangle(sw//4, sh//4, sw*3//4, sh*3//4,
                outline="#00CC00", width=4)
            canvas.create_line(sw//2-50, sh//2-10, sw//2-15, sh//2+30,
                fill="#00FF00", width=8)
            canvas.create_line(sw//2-15, sh//2+30, sw//2+60, sh//2-50,
                fill="#00FF00", width=8)
            canvas.create_text(sw//2, sh//2+70,
                text="KALIBRASYON TAMAMLANDI!",
                fill="#00FF00", font=("Arial", 26, "bold"))
            ms = " ".join(str(v) for v in state["result"])
            canvas.create_text(sw//2, sh//2+110, text=f"Matris: {ms}",
                fill="white", font=("Arial", 12))
            canvas.create_text(sw//2, sh//2+145,
                text="Kaydediliyor ve uygulanıyor...",
                fill="#CCCC00", font=("Arial", 14))

    def on_touch(event):
        if state["locked"] or state["result"] is not None:
            return
        cur = state["cur"]
        if cur >= len(targets):
            return

        state["locked"] = True
        tx, ty = event.x, event.y
        touches.append((tx, ty))

        target = targets[cur]
        dx, dy = tx - target[0], ty - target[1]
        print(f"  [{cur+1}/{len(targets)}] hedef=({target[0]},{target[1]}) "
              f"dokunma=({tx},{ty}) fark=({dx},{dy})")

        # Yeşil halka geri bildirimi
        px, py = target
        for r in [15, 30, 45]:
            canvas.create_oval(px-r, py-r, px+r, py+r, outline="#00FF00", width=3)
        canvas.update()

        state["cur"] += 1

        if state["cur"] >= len(targets):
            root.after(400, do_finish)
        else:
            root.after(500, unlock_and_redraw)

    def unlock_and_redraw():
        state["locked"] = False
        draw()

    def do_finish():
        state["result"] = calc_matrix(targets, touches, sw, sh)
        print(f"\n  Matris: {' '.join(str(v) for v in state['result'])}")
        draw()
        root.after(3000, close_window)

    def close_window():
        root.destroy()

    def on_escape(event):
        state["result"] = None
        root.destroy()

    canvas.bind("<Button-1>", on_touch)
    root.bind("<Escape>", on_escape)
    draw()

    try:
        root.mainloop()
    except:
        pass

    return state.get("result")

# ═══════════════════════════════════════════════
# ANA PROGRAM
# ═══════════════════════════════════════════════
def main():
    import argparse
    p = argparse.ArgumentParser(description="Vestel Dokunmatik Kalibrasyon")
    p.add_argument("--points", type=int, default=9, choices=[4, 9],
                   help="Kalibrasyon noktasi sayisi (varsayilan: 9)")
    a = p.parse_args()

    # Root kontrol
    get_root()

    # tkinter kontrol
    try:
        import tkinter
    except ImportError:
        print("python3-tk kuruluyor...")
        os.system("apt-get install -y python3-tk 2>/dev/null")
        try:
            import tkinter
        except ImportError:
            print("HATA: python3-tk kurulamadi!")
            print("Internet baglantisi ile: sudo apt install python3-tk")
            sys.exit(1)

    print()
    print("=" * 46)
    print("  VESTEL DOKUNMATIK KALIBRASYON")
    print("  9 noktaya sirayla dokunun | ESC = iptal")
    print("=" * 46)
    print()

    # Kalibrasyon GUI
    matrix = run_calibration(a.points)

    if matrix:
        print()
        ms = save_calibration(matrix)
        apply_calibration(ms)
        install_boot_service()
        print()
        print("  Kalibrasyon tamamlandi!")
        print("  Her restart'ta otomatik uygulanacak.")
        print()
    else:
        # İptal edildi — eski kalibrasyonu geri yükle
        print("\n  Kalibrasyon iptal edildi.")
        if os.path.exists(CALIB_FILE):
            with open(CALIB_FILE) as f:
                old_ms = f.read().strip()
            if old_ms and old_ms != "1 0 0 0 1 0 0 0 1":
                apply_calibration(old_ms)
                print("  Onceki kalibrasyon geri yuklendi.\n")
            else:
                print("  Identity matris aktif.\n")
        else:
            print()

if __name__ == "__main__":
    main()
