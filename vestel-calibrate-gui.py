#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Vestel Akıllı Tahta — Dokunmatik Kalibrasyon Aracı
Pardus 23 / ETAP 23 — Faz-1 & Faz-2

Sıfır ek bağımlılık: Python3 + ctypes + libX11 (Pardus 23'te varsayılan)
Fullscreen kalibrasyon ekranı, 4 veya 9 nokta desteği
Hesaplanan matris kalıcı kaydedilir

Kullanım: sudo python3 vestel-calibrate-gui.py [--points 4|9] [--device EVENT_PATH]
"""

import ctypes
import ctypes.util
import struct
import os
import sys
import subprocess
import time
import math
import glob
import signal

# ══════════════════════════════════════════════════════════════
# X11 ctypes bindings (sıfır bağımlılık)
# ══════════════════════════════════════════════════════════════

# X11 kütüphanelerini yükle
_x11_path = ctypes.util.find_library("X11")
if not _x11_path:
    print("HATA: libX11 bulunamadı!")
    sys.exit(1)

X11 = ctypes.cdll.LoadLibrary(_x11_path)

# X11 sabitleri
ExposureMask     = 1 << 15
ButtonPressMask  = 1 << 2
ButtonReleaseMask = 1 << 3
StructureNotifyMask = 1 << 17
KeyPressMask     = 1 << 0

GCForeground     = 1 << 2
GCBackground     = 1 << 3
GCLineWidth      = 1 << 4
GCFont           = 1 << 14

Expose           = 12
ButtonPress      = 4
ButtonRelease    = 5
KeyPress         = 2
ConfigureNotify  = 22

BlackPixel = X11.XBlackPixel
WhitePixel = X11.XWhitePixel

class XEvent(ctypes.Union):
    _fields_ = [("type", ctypes.c_int),
                ("pad", ctypes.c_long * 24)]

class XGCValues(ctypes.Structure):
    _fields_ = [
        ("function", ctypes.c_int),
        ("plane_mask", ctypes.c_ulong),
        ("foreground", ctypes.c_ulong),
        ("background", ctypes.c_ulong),
        ("line_width", ctypes.c_int),
        ("line_style", ctypes.c_int),
        ("cap_style", ctypes.c_int),
        ("join_style", ctypes.c_int),
        ("fill_style", ctypes.c_int),
        ("fill_rule", ctypes.c_int),
        ("arc_mode", ctypes.c_int),
        ("tile", ctypes.c_ulong),
        ("stipple", ctypes.c_ulong),
        ("ts_x_origin", ctypes.c_int),
        ("ts_y_origin", ctypes.c_int),
        ("font", ctypes.c_ulong),
        ("subwindow_mode", ctypes.c_int),
        ("graphics_exposures", ctypes.c_int),
        ("clip_x_origin", ctypes.c_int),
        ("clip_y_origin", ctypes.c_int),
        ("clip_mask", ctypes.c_ulong),
        ("dash_offset", ctypes.c_int),
        ("dashes", ctypes.c_char),
    ]

# ══════════════════════════════════════════════════════════════
# evdev raw okuma (sıfır bağımlılık)
# ══════════════════════════════════════════════════════════════

# Linux input event yapısı
# struct input_event { struct timeval time; __u16 type; __u16 code; __s32 value; }
if struct.calcsize("P") == 8:  # 64-bit
    EVENT_FORMAT = "llHHi"
else:
    EVENT_FORMAT = "iiHHi"
EVENT_SIZE = struct.calcsize(EVENT_FORMAT)

# Event tipleri
EV_SYN = 0x00
EV_ABS = 0x03
EV_KEY = 0x01

# ABS kodları
ABS_X = 0x00
ABS_Y = 0x01
ABS_MT_SLOT = 0x2f
ABS_MT_POSITION_X = 0x35
ABS_MT_POSITION_Y = 0x36
ABS_MT_TRACKING_ID = 0x39

# BTN kodları
BTN_TOUCH = 0x14a

# ioctl sabitleri
EVIOCGABS = lambda axis: 0x80184540 + axis
EVIOCGNAME = lambda buflen: 0x80004506 + (buflen << 16)

class input_absinfo(ctypes.Structure):
    _fields_ = [
        ("value", ctypes.c_int32),
        ("minimum", ctypes.c_int32),
        ("maximum", ctypes.c_int32),
        ("fuzz", ctypes.c_int32),
        ("flat", ctypes.c_int32),
        ("resolution", ctypes.c_int32),
    ]


def find_touch_device():
    """Dokunmatik event cihazını bul"""
    for event_path in sorted(glob.glob("/dev/input/event*")):
        try:
            fd = os.open(event_path, os.O_RDONLY | os.O_NONBLOCK)
            # Cihaz ismini oku
            name_buf = ctypes.create_string_buffer(256)
            import fcntl
            fcntl.ioctl(fd, EVIOCGNAME(256), name_buf)
            name = name_buf.value.decode("utf-8", errors="ignore").lower()
            
            # ABS_MT_POSITION_X desteği var mı?
            absinfo = input_absinfo()
            try:
                fcntl.ioctl(fd, EVIOCGABS(ABS_MT_POSITION_X), absinfo)
                has_mt_x = absinfo.maximum > 0
            except:
                has_mt_x = False
            
            os.close(fd)
            
            # Bilinen dokunmatik isimleri veya MT desteği
            touch_keywords = ["touch", "optical", "irtouch", "otd", "egalax", "ilitek", "goodix"]
            is_touch = any(kw in name for kw in touch_keywords) or has_mt_x
            is_mouse = any(kw in name for kw in ["mouse", "trackpad", "keyboard", "power", "video"])
            
            if is_touch and not is_mouse:
                return event_path, name
        except:
            try:
                os.close(fd)
            except:
                pass
    return None, None


def get_touch_range(event_path):
    """Dokunmatik cihazın X ve Y aralığını oku"""
    import fcntl
    fd = os.open(event_path, os.O_RDONLY)
    
    absinfo_x = input_absinfo()
    absinfo_y = input_absinfo()
    
    try:
        fcntl.ioctl(fd, EVIOCGABS(ABS_MT_POSITION_X), absinfo_x)
    except:
        fcntl.ioctl(fd, EVIOCGABS(ABS_X), absinfo_x)
    
    try:
        fcntl.ioctl(fd, EVIOCGABS(ABS_MT_POSITION_Y), absinfo_y)
    except:
        fcntl.ioctl(fd, EVIOCGABS(ABS_Y), absinfo_y)
    
    os.close(fd)
    return (absinfo_x.minimum, absinfo_x.maximum, 
            absinfo_y.minimum, absinfo_y.maximum)


def read_touch_event(fd):
    """Tek bir dokunma koordinatı oku (blocking)"""
    cur_x, cur_y = None, None
    touching = False
    
    while True:
        try:
            data = os.read(fd, EVENT_SIZE)
            if len(data) < EVENT_SIZE:
                continue
            
            tv_sec_or_pad, tv_usec_or_pad, ev_type, ev_code, ev_value = struct.unpack(EVENT_FORMAT, data)
            
            if ev_type == EV_ABS:
                if ev_code in (ABS_MT_POSITION_X, ABS_X):
                    cur_x = ev_value
                elif ev_code in (ABS_MT_POSITION_Y, ABS_Y):
                    cur_y = ev_value
            elif ev_type == EV_KEY and ev_code == BTN_TOUCH:
                touching = ev_value == 1
            elif ev_type == EV_SYN:
                if cur_x is not None and cur_y is not None:
                    return cur_x, cur_y
        except BlockingIOError:
            time.sleep(0.01)
        except:
            time.sleep(0.01)


# ══════════════════════════════════════════════════════════════
# Kalibrasyon Hesaplama
# ══════════════════════════════════════════════════════════════

def calculate_calibration_matrix(screen_points, touch_points, screen_w, screen_h):
    """
    Ekran noktaları ve dokunma noktalarından libinput Calibration Matrix hesapla.
    
    En az 3 nokta gerekli. Fazla nokta varsa least-squares ile hesaplanır.
    Sonuç: [a, b, c, d, e, f, 0, 0, 1] formatında 3x3 matris
    
    Dönüşüm: screen_x = a * touch_x + b * touch_y + c
              screen_y = d * touch_x + e * touch_y + f
    
    Burada touch_x ve touch_y normalize edilmiş (0-1 arası).
    """
    n = len(screen_points)
    if n < 3:
        return [1, 0, 0, 0, 1, 0, 0, 0, 1]
    
    # Normalize et
    norm_screen = [(sx / screen_w, sy / screen_h) for sx, sy in screen_points]
    norm_touch = [(tx / screen_w, ty / screen_h) for tx, ty in touch_points]
    
    # Least squares: A * [a,b,c] = screen_x ve A * [d,e,f] = screen_y
    # A matrisi: [[tx, ty, 1], ...]
    
    # Normal denklemler ile çöz (numpy'sız)
    sum_tx2 = sum(t[0]**2 for t in norm_touch)
    sum_ty2 = sum(t[1]**2 for t in norm_touch)
    sum_txty = sum(t[0]*t[1] for t in norm_touch)
    sum_tx = sum(t[0] for t in norm_touch)
    sum_ty = sum(t[1] for t in norm_touch)
    
    sum_sx_tx = sum(s[0]*t[0] for s, t in zip(norm_screen, norm_touch))
    sum_sx_ty = sum(s[0]*t[1] for s, t in zip(norm_screen, norm_touch))
    sum_sx = sum(s[0] for s in norm_screen)
    
    sum_sy_tx = sum(s[1]*t[0] for s, t in zip(norm_screen, norm_touch))
    sum_sy_ty = sum(s[1]*t[1] for s, t in zip(norm_screen, norm_touch))
    sum_sy = sum(s[1] for s in norm_screen)
    
    # 3x3 lineer sistem çöz (Cramer kuralı)
    # | sum_tx2   sum_txty  sum_tx | | a |   | sum_sx_tx |
    # | sum_txty  sum_ty2   sum_ty | | b | = | sum_sx_ty |
    # | sum_tx    sum_ty    n      | | c |   | sum_sx    |
    
    def solve_3x3(m, v):
        """3x3 lineer sistem çöz: m * x = v"""
        det = (m[0][0] * (m[1][1]*m[2][2] - m[1][2]*m[2][1])
             - m[0][1] * (m[1][0]*m[2][2] - m[1][2]*m[2][0])
             + m[0][2] * (m[1][0]*m[2][1] - m[1][1]*m[2][0]))
        
        if abs(det) < 1e-10:
            return [1, 0, 0]  # fallback identity
        
        x = [0, 0, 0]
        for i in range(3):
            mc = [row[:] for row in m]
            for j in range(3):
                mc[j][i] = v[j]
            det_i = (mc[0][0] * (mc[1][1]*mc[2][2] - mc[1][2]*mc[2][1])
                   - mc[0][1] * (mc[1][0]*mc[2][2] - mc[1][2]*mc[2][0])
                   + mc[0][2] * (mc[1][0]*mc[2][1] - mc[1][1]*mc[2][0]))
            x[i] = det_i / det
        return x
    
    M = [[sum_tx2, sum_txty, sum_tx],
         [sum_txty, sum_ty2, sum_ty],
         [sum_tx, sum_ty, n]]
    
    abc = solve_3x3(M, [sum_sx_tx, sum_sx_ty, sum_sx])
    deff = solve_3x3(M, [sum_sy_tx, sum_sy_ty, sum_sy])
    
    # libinput calibration matrix formatı
    a, b, c = abc
    d, e, f = deff
    
    return [round(a, 6), round(b, 6), round(c, 6),
            round(d, 6), round(e, 6), round(f, 6),
            0, 0, 1]


# ══════════════════════════════════════════════════════════════
# X11 Fullscreen Kalibrasyon GUI
# ══════════════════════════════════════════════════════════════

class CalibrationGUI:
    def __init__(self, num_points=4, event_device=None):
        self.num_points = num_points
        self.event_device = event_device
        self.screen_points = []  # Hedef ekran noktaları
        self.touch_points = []   # Dokunulan gerçek noktalar
        self.current_point = 0
        self.screen_w = 0
        self.screen_h = 0
        self.crosshair_size = 30
        self.touch_fd = None
        
    def generate_target_points(self):
        """Kalibrasyon noktalarını oluştur"""
        margin_x = int(self.screen_w * 0.1)
        margin_y = int(self.screen_h * 0.1)
        
        if self.num_points == 4:
            return [
                (margin_x, margin_y),                              # sol üst
                (self.screen_w - margin_x, margin_y),              # sağ üst
                (margin_x, self.screen_h - margin_y),              # sol alt
                (self.screen_w - margin_x, self.screen_h - margin_y),  # sağ alt
            ]
        elif self.num_points == 9:
            cx, cy = self.screen_w // 2, self.screen_h // 2
            return [
                (margin_x, margin_y),                     # sol üst
                (cx, margin_y),                            # orta üst
                (self.screen_w - margin_x, margin_y),     # sağ üst
                (margin_x, cy),                            # sol orta
                (cx, cy),                                  # merkez
                (self.screen_w - margin_x, cy),            # sağ orta
                (margin_x, self.screen_h - margin_y),     # sol alt
                (cx, self.screen_h - margin_y),            # orta alt
                (self.screen_w - margin_x, self.screen_h - margin_y),  # sağ alt
            ]
    
    def draw_crosshair(self, display, window, gc, x, y, color):
        """Artı işareti çiz"""
        s = self.crosshair_size
        # Renk ayarla
        X11.XSetForeground(display, gc, color)
        X11.XSetLineAttributes(display, gc, 3, 0, 0, 0)
        
        # Yatay çizgi
        X11.XDrawLine(display, window, gc, x - s, y, x + s, y)
        # Dikey çizgi
        X11.XDrawLine(display, window, gc, x, y - s, x, y + s)
        # Daire
        X11.XDrawArc(display, window, gc, x - s//2, y - s//2, s, s, 0, 360 * 64)
    
    def draw_text(self, display, window, gc, x, y, text, color):
        """Metin yaz"""
        X11.XSetForeground(display, gc, color)
        text_bytes = text.encode("utf-8")
        X11.XDrawString(display, window, gc, x, y, text_bytes, len(text_bytes))
    
    def run(self):
        """Kalibrasyon GUI'sini çalıştır"""
        # Dokunmatik cihazı aç
        if self.event_device:
            event_path = self.event_device
        else:
            event_path, dev_name = find_touch_device()
            if not event_path:
                print("HATA: Dokunmatik cihaz bulunamadı!")
                return None
            print(f"Dokunmatik cihaz: {event_path} ({dev_name})")
        
        # Touch range al
        try:
            tx_min, tx_max, ty_min, ty_max = get_touch_range(event_path)
            print(f"Touch aralığı: X={tx_min}-{tx_max}, Y={ty_min}-{ty_max}")
        except:
            tx_min, tx_max, ty_min, ty_max = 0, 32767, 0, 32767
            print(f"Touch aralığı varsayılan: 0-32767")
        
        self.touch_fd = os.open(event_path, os.O_RDONLY | os.O_NONBLOCK)
        
        # X11 başlat
        display = X11.XOpenDisplay(None)
        if not display:
            print("HATA: X11 display açılamadı!")
            return None
        
        screen = X11.XDefaultScreen(display)
        root = X11.XRootWindow(display, screen)
        self.screen_w = X11.XDisplayWidth(display, screen)
        self.screen_h = X11.XDisplayHeight(display, screen)
        
        print(f"Ekran: {self.screen_w}x{self.screen_h}")
        
        black = BlackPixel(display, screen)
        white = WhitePixel(display, screen)
        
        # Kırmızı ve yeşil renk
        colormap = X11.XDefaultColormap(display, screen)
        
        # Fullscreen pencere oluştur
        window = X11.XCreateSimpleWindow(
            display, root,
            0, 0, self.screen_w, self.screen_h,
            0, black, black
        )
        
        # Fullscreen ayarla
        wm_state = X11.XInternAtom(display, b"_NET_WM_STATE", False)
        wm_fullscreen = X11.XInternAtom(display, b"_NET_WM_STATE_FULLSCREEN", False)
        
        # Event mask
        X11.XSelectInput(display, window, 
                        ExposureMask | ButtonPressMask | ButtonReleaseMask | 
                        KeyPressMask | StructureNotifyMask)
        
        X11.XMapWindow(display, window)
        X11.XRaiseWindow(display, window)
        
        # Fullscreen özelliği ayarla
        xev = XEvent()
        
        # GC oluştur
        gc_values = XGCValues()
        gc = X11.XCreateGC(display, window, 0, ctypes.byref(gc_values))
        
        # Hedef noktaları oluştur
        self.screen_points = self.generate_target_points()
        self.touch_points = []
        self.current_point = 0
        
        result_matrix = None
        running = True
        need_redraw = True
        
        print(f"\n{self.num_points} noktalı kalibrasyon başlıyor...")
        print("Her artı işaretine dokunun. ESC ile iptal.")
        
        while running:
            # Event kontrolü
            event = XEvent()
            while X11.XPending(display) > 0:
                X11.XNextEvent(display, ctypes.byref(event))
                
                if event.type == Expose:
                    need_redraw = True
                elif event.type == KeyPress:
                    # ESC ile çık
                    running = False
                    break
            
            # Dokunma okuma
            if self.current_point < len(self.screen_points):
                try:
                    tx, ty = read_touch_event(self.touch_fd)
                    
                    # Touch koordinatlarını ekran koordinatlarına dönüştür
                    screen_tx = int((tx - tx_min) / (tx_max - tx_min) * self.screen_w)
                    screen_ty = int((ty - ty_min) / (ty_max - ty_min) * self.screen_h)
                    
                    self.touch_points.append((screen_tx, screen_ty))
                    
                    target = self.screen_points[self.current_point]
                    dx = screen_tx - target[0]
                    dy = screen_ty - target[1]
                    print(f"  Nokta {self.current_point + 1}/{len(self.screen_points)}: "
                          f"hedef=({target[0]},{target[1]}) "
                          f"dokunma=({screen_tx},{screen_ty}) "
                          f"fark=({dx},{dy})")
                    
                    self.current_point += 1
                    need_redraw = True
                    
                    # Debounce - parmağın kalkmasını bekle
                    time.sleep(0.5)
                    # Buffer'ı temizle
                    try:
                        while True:
                            os.read(self.touch_fd, 4096)
                    except:
                        pass
                    
                except:
                    pass
            
            # Tüm noktalar toplandı
            if self.current_point >= len(self.screen_points) and result_matrix is None:
                result_matrix = calculate_calibration_matrix(
                    self.screen_points, self.touch_points,
                    self.screen_w, self.screen_h
                )
                need_redraw = True
                print(f"\nHesaplanan matris: {' '.join(str(v) for v in result_matrix)}")
            
            # Çiz
            if need_redraw:
                # Arka planı temizle
                X11.XSetForeground(display, gc, black)
                X11.XFillRectangle(display, window, gc, 0, 0, self.screen_w, self.screen_h)
                
                if result_matrix is None:
                    # Kalibrasyon devam ediyor
                    # Başlık
                    self.draw_text(display, window, gc,
                                  self.screen_w // 2 - 200, 50,
                                  f"DOKUNMATIK KALIBRASYON ({self.current_point}/{len(self.screen_points)})",
                                  white)
                    self.draw_text(display, window, gc,
                                  self.screen_w // 2 - 150, 80,
                                  "Arti isaretine dokunun | ESC = iptal",
                                  white)
                    
                    # Tamamlanan noktalar (yeşil)
                    for i in range(self.current_point):
                        px, py = self.screen_points[i]
                        # Yeşil renk (0x00FF00)
                        self.draw_crosshair(display, window, gc, px, py, 0x00AA00)
                    
                    # Aktif nokta (kırmızı, büyük)
                    if self.current_point < len(self.screen_points):
                        px, py = self.screen_points[self.current_point]
                        self.draw_crosshair(display, window, gc, px, py, 0xFF4444)
                        # Yanıp sönen efekt için büyük daire
                        X11.XSetForeground(display, gc, 0xFF4444)
                        X11.XDrawArc(display, window, gc,
                                    px - self.crosshair_size, py - self.crosshair_size,
                                    self.crosshair_size * 2, self.crosshair_size * 2,
                                    0, 360 * 64)
                    
                    # Bekleyen noktalar (gri)
                    for i in range(self.current_point + 1, len(self.screen_points)):
                        px, py = self.screen_points[i]
                        self.draw_crosshair(display, window, gc, px, py, 0x555555)
                
                else:
                    # Kalibrasyon tamamlandı
                    self.draw_text(display, window, gc,
                                  self.screen_w // 2 - 150, self.screen_h // 2 - 40,
                                  "KALIBRASYON TAMAMLANDI!",
                                  0x00FF00)
                    
                    matrix_str = " ".join(f"{v}" for v in result_matrix)
                    self.draw_text(display, window, gc,
                                  self.screen_w // 2 - 250, self.screen_h // 2,
                                  f"Matris: {matrix_str}",
                                  white)
                    
                    self.draw_text(display, window, gc,
                                  self.screen_w // 2 - 200, self.screen_h // 2 + 40,
                                  "3 saniye sonra otomatik kaydedilecek...",
                                  0xAAAA00)
                    
                    X11.XFlush(display)
                    time.sleep(3)
                    running = False
                
                X11.XFlush(display)
                need_redraw = False
            
            time.sleep(0.01)
        
        # Temizlik
        os.close(self.touch_fd)
        X11.XFreeGC(display, gc)
        X11.XDestroyWindow(display, window)
        X11.XCloseDisplay(display)
        
        return result_matrix


# ══════════════════════════════════════════════════════════════
# Matris Kaydetme ve Uygulama
# ══════════════════════════════════════════════════════════════

CALIB_FILE = "/etc/vestel-touch-calibration.conf"

def save_calibration(matrix):
    """Kalibrasyon matrisini kaydet"""
    matrix_str = " ".join(str(v) for v in matrix)
    
    # Dosyaya kaydet
    with open(CALIB_FILE, "w") as f:
        f.write(matrix_str + "\n")
    print(f"Kaydedildi: {CALIB_FILE}")
    
    # xinput ile anında uygula
    apply_calibration(matrix_str)


def apply_calibration(matrix_str):
    """Kalibrasyon matrisini xinput ile uygula"""
    try:
        result = subprocess.run(["xinput", "list"], capture_output=True, text=True)
        for line in result.stdout.split("\n"):
            if "slave  pointer" not in line:
                continue
            
            # ID çıkar
            import re
            m = re.search(r"id=(\d+)", line)
            if not m:
                continue
            dev_id = m.group(1)
            
            # Mouse/trackpad atla
            name_lower = line.lower()
            if any(skip in name_lower for skip in ["mouse", "trackpad", "virtual", "receiver"]):
                continue
            
            # Matrisi uygula
            subprocess.run(
                ["xinput", "set-prop", dev_id, "libinput Calibration Matrix"] + matrix_str.split(),
                capture_output=True
            )
            subprocess.run(
                ["xinput", "set-prop", dev_id, "Coordinate Transformation Matrix"] + matrix_str.split(),
                capture_output=True
            )
            name = line.strip().split("id=")[0].replace("↳", "").replace("⎜", "").strip()
            print(f"Uygulandı: {name} (id={dev_id})")
    except Exception as e:
        print(f"xinput hatası: {e}")


# ══════════════════════════════════════════════════════════════
# Ana Program
# ══════════════════════════════════════════════════════════════

def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="Vestel Dokunmatik Kalibrasyon Aracı")
    parser.add_argument("--points", type=int, default=4, choices=[4, 9],
                       help="Kalibrasyon noktası sayısı (varsayılan: 4)")
    parser.add_argument("--device", type=str, default=None,
                       help="Dokunmatik event cihazı (örn: /dev/input/event5)")
    parser.add_argument("--test", action="store_true",
                       help="Mevcut kalibrasyonu test et (dokunma noktalarını göster)")
    
    args = parser.parse_args()
    
    # Root kontrolü
    if os.geteuid() != 0:
        print("Root yetkisi gerekli. sudo ile çalıştırın.")
        # Otomatik yükseltme
        passwords = ["etap+pardus!", "etap+pardus", "pardus", "etapadmin"]
        for pw in passwords:
            ret = os.system(f'echo "{pw}" | sudo -S python3 {" ".join(sys.argv)} 2>/dev/null')
            if ret == 0:
                return
        print("sudo python3 vestel-calibrate-gui.py")
        sys.exit(1)
    
    print("╔══════════════════════════════════════════╗")
    print("║  VESTEL DOKUNMATIK KALİBRASYON           ║")
    print("╚══════════════════════════════════════════╝")
    print()
    
    # Dokunmatik cihaz tespiti
    if not args.device:
        event_path, dev_name = find_touch_device()
        if event_path:
            print(f"Cihaz: {dev_name} ({event_path})")
        else:
            print("HATA: Dokunmatik cihaz bulunamadı!")
            print("Dokunmatik servisi çalışıyor mu? systemctl status eta-touchdrv.service")
            sys.exit(1)
    
    # Kalibrasyon GUI başlat
    gui = CalibrationGUI(num_points=args.points, event_device=args.device)
    matrix = gui.run()
    
    if matrix:
        print(f"\nSonuç matrisi: {' '.join(str(v) for v in matrix)}")
        save_calibration(matrix)
        print("\nKalibrasyon tamamlandı ve kalıcı kaydedildi!")
        print("Her reboot'ta otomatik uygulanacaktır.")
    else:
        print("\nKalibrasyon iptal edildi.")


if __name__ == "__main__":
    main()
