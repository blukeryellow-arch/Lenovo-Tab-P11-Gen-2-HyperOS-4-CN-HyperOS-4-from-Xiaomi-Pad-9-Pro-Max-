#![allow(dead_code, unused_imports)]
use crate::state::{
    EmulatorState, HitAction, Rect, TextAlign, UiCommand, WIN_H, WIN_W,
};
use std::collections::HashMap;
use std::ffi::c_void;
use std::fs::File;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::ptr;

type HANDLE = *mut c_void;
type HWND = HANDLE;
type HDC = HANDLE;
type HBITMAP = HANDLE;
type HFONT = HANDLE;
type HGDIOBJ = HANDLE;
type HINSTANCE = HANDLE;
type HICON = HANDLE;
type HCURSOR = HANDLE;
type HBRUSH = HANDLE;
type HDROP = HANDLE;
type LRESULT = isize;
type WPARAM = usize;
type LPARAM = isize;
type UINT = u32;
type DWORD = u32;
type BOOL = i32;

#[repr(C)]
struct WNDCLASSEXW {
    cb_size: UINT,
    style: UINT,
    lpfn_wnd_proc: Option<unsafe extern "system" fn(HWND, UINT, WPARAM, LPARAM) -> LRESULT>,
    cb_cls_extra: i32,
    cb_wnd_extra: i32,
    h_instance: HINSTANCE,
    h_icon: HICON,
    h_cursor: HCURSOR,
    hbr_background: HBRUSH,
    lpsz_menu_name: *const u16,
    lpsz_class_name: *const u16,
    h_icon_sm: HICON,
}

#[repr(C)]
#[derive(Copy, Clone)]
struct POINT {
    x: i32,
    y: i32,
}

#[repr(C)]
struct MSG {
    hwnd: HWND,
    message: UINT,
    w_param: WPARAM,
    l_param: LPARAM,
    time: DWORD,
    pt: POINT,
}

#[repr(C)]
struct RECT {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
}

#[repr(C)]
struct PAINTSTRUCT {
    hdc: HDC,
    f_erase: BOOL,
    rc_paint: RECT,
    f_restore: BOOL,
    f_inc_update: BOOL,
    rgb_reserved: [u8; 32],
}

#[repr(C)]
struct BITMAPINFOHEADER {
    bi_size: DWORD,
    bi_width: i32,
    bi_height: i32,
    bi_planes: u16,
    bi_bit_count: u16,
    bi_compression: DWORD,
    bi_size_image: DWORD,
    bi_x_pels_per_meter: i32,
    bi_y_pels_per_meter: i32,
    bi_clr_used: DWORD,
    bi_clr_important: DWORD,
}

#[repr(C)]
struct BITMAPINFO {
    bmi_header: BITMAPINFOHEADER,
    bmi_colors: [DWORD; 1],
}

#[repr(C)]
struct SYSTEMTIME {
    w_year: u16,
    w_month: u16,
    w_day_of_week: u16,
    w_day: u16,
    w_hour: u16,
    w_minute: u16,
    w_second: u16,
    w_milliseconds: u16,
}

#[repr(C)]
struct OPENFILENAMEW {
    l_struct_size: DWORD,
    hwnd_owner: HWND,
    h_instance: HINSTANCE,
    lpstr_filter: *const u16,
    lpstr_custom_filter: *mut u16,
    n_max_cust_filter: DWORD,
    n_filter_index: DWORD,
    lpstr_file: *mut u16,
    n_max_file: DWORD,
    lpstr_file_title: *mut u16,
    n_max_file_title: DWORD,
    lpstr_initial_dir: *const u16,
    lpstr_title: *const u16,
    flags: DWORD,
    n_file_offset: u16,
    n_file_extension: u16,
    lpstr_def_ext: *const u16,
    l_cust_data: LPARAM,
    lpfn_hook: HANDLE,
    lp_template_name: *const u16,
    pv_reserved: *mut c_void,
    dw_reserved: DWORD,
    flags_ex: DWORD,
}

const WS_OVERLAPPED: DWORD = 0x00000000;
const WS_CAPTION: DWORD = 0x00C00000;
const WS_SYSMENU: DWORD = 0x00080000;
const WS_MINIMIZEBOX: DWORD = 0x00020000;
const WS_VISIBLE: DWORD = 0x10000000;
const WS_STYLE: DWORD = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_VISIBLE;

const CW_USEDEFAULT: i32 = -0x80000000;
const WM_DESTROY: UINT = 0x0002;
const WM_PAINT: UINT = 0x000F;
const WM_ERASEBKGND: UINT = 0x0014;
const WM_TIMER: UINT = 0x0113;
const WM_MOUSEMOVE: UINT = 0x0200;
const WM_LBUTTONDOWN: UINT = 0x0201;
const WM_LBUTTONUP: UINT = 0x0202;
const WM_RBUTTONDOWN: UINT = 0x0204;
const WM_MOUSEWHEEL: UINT = 0x020A;
const WM_DROPFILES: UINT = 0x0233;

const OFN_OVERWRITEPROMPT: DWORD = 0x00000002;
const OFN_NOCHANGEDIR: DWORD = 0x00000008;
const OFN_PATHMUSTEXIST: DWORD = 0x00000800;
const OFN_FILEMUSTEXIST: DWORD = 0x00001000;

const TRANSPARENT: i32 = 1;
const SRCCOPY: DWORD = 0x00CC0020;
const DT_LEFT: UINT = 0x00000000;
const DT_CENTER: UINT = 0x00000001;
const DT_RIGHT: UINT = 0x00000002;
const DT_VCENTER: UINT = 0x00000004;
const DT_WORDBREAK: UINT = 0x00000010;
const DT_SINGLELINE: UINT = 0x00000020;
const DT_NOPREFIX: UINT = 0x00000800;
const DT_END_ELLIPSIS: UINT = 0x00008000;

const GWLP_USERDATA: i32 = -21;
const IDC_ARROW: usize = 32512;
const CLEARTYPE_QUALITY: DWORD = 5;

#[link(name = "kernel32")]
extern "system" {
    fn GetModuleHandleW(lp_module_name: *const u16) -> HINSTANCE;
    fn GetTickCount64() -> u64;
    fn GetLocalTime(lp_system_time: *mut SYSTEMTIME);
}

#[link(name = "user32")]
extern "system" {
    fn RegisterClassExW(lpwcx: *const WNDCLASSEXW) -> u16;
    fn CreateWindowExW(
        dw_ex_style: DWORD,
        lp_class_name: *const u16,
        lp_window_name: *const u16,
        dw_style: DWORD,
        x: i32,
        y: i32,
        n_width: i32,
        n_height: i32,
        h_wnd_parent: HWND,
        h_menu: HANDLE,
        h_instance: HINSTANCE,
        lp_param: *mut c_void,
    ) -> HWND;
    fn DefWindowProcW(h_wnd: HWND, msg: UINT, w_param: WPARAM, l_param: LPARAM) -> LRESULT;
    fn GetMessageW(lp_msg: *mut MSG, h_wnd: HWND, w_msg_filter_min: UINT, w_msg_filter_max: UINT) -> BOOL;
    fn TranslateMessage(lp_msg: *const MSG) -> BOOL;
    fn DispatchMessageW(lp_msg: *const MSG) -> LRESULT;
    fn PostQuitMessage(n_exit_code: i32);
    fn BeginPaint(h_wnd: HWND, lp_paint: *mut PAINTSTRUCT) -> HDC;
    fn EndPaint(h_wnd: HWND, lp_paint: *const PAINTSTRUCT) -> BOOL;
    fn InvalidateRect(h_wnd: HWND, lp_rect: *const RECT, b_erase: BOOL) -> BOOL;
    fn SetTimer(h_wnd: HWND, n_id_event: usize, u_elapse: UINT, lp_timer_func: HANDLE) -> usize;
    fn KillTimer(h_wnd: HWND, u_id_event: usize) -> BOOL;
    fn SetCapture(h_wnd: HWND) -> HWND;
    fn ReleaseCapture() -> BOOL;
    fn GetClientRect(h_wnd: HWND, lp_rect: *mut RECT) -> BOOL;
    fn AdjustWindowRectEx(lp_rect: *mut RECT, dw_style: DWORD, b_menu: BOOL, dw_ex_style: DWORD) -> BOOL;
    fn LoadCursorW(h_instance: HINSTANCE, lp_cursor_name: *const u16) -> HCURSOR;
    fn SetWindowLongPtrW(h_wnd: HWND, n_index: i32, dw_new_long: isize) -> isize;
    fn GetWindowLongPtrW(h_wnd: HWND, n_index: i32) -> isize;
    fn DrawTextW(hdc: HDC, lpch_text: *const u16, cch_text: i32, lprc: *mut RECT, format: UINT) -> i32;
}

#[link(name = "gdi32")]
extern "system" {
    fn CreateCompatibleDC(hdc: HDC) -> HDC;
    fn DeleteDC(hdc: HDC) -> BOOL;
    fn CreateDIBSection(
        hdc: HDC,
        pbmi: *const BITMAPINFO,
        usage: UINT,
        ppv_bits: *mut *mut c_void,
        h_section: HANDLE,
        offset: DWORD,
    ) -> HBITMAP;
    fn SelectObject(hdc: HDC, h: HGDIOBJ) -> HGDIOBJ;
    fn DeleteObject(ho: HGDIOBJ) -> BOOL;
    fn BitBlt(
        hdc: HDC,
        x: i32,
        y: i32,
        cx: i32,
        cy: i32,
        hdc_src: HDC,
        x1: i32,
        y1: i32,
        rop: DWORD,
    ) -> BOOL;
    fn GdiFlush() -> BOOL;
    fn SetBkMode(hdc: HDC, mode: i32) -> i32;
    fn SetTextColor(hdc: HDC, color: DWORD) -> DWORD;
    fn CreateFontW(
        c_height: i32,
        c_width: i32,
        c_escapement: i32,
        c_orientation: i32,
        c_weight: i32,
        b_italic: DWORD,
        b_underline: DWORD,
        b_strike_out: DWORD,
        i_char_set: DWORD,
        i_out_precision: DWORD,
        i_clip_precision: DWORD,
        i_quality: DWORD,
        i_pitch_and_family: DWORD,
        psz_face_name: *const u16,
    ) -> HFONT;
}

#[link(name = "comdlg32")]
extern "system" {
    fn GetOpenFileNameW(lpofn: *mut OPENFILENAMEW) -> BOOL;
    fn GetSaveFileNameW(lpofn: *mut OPENFILENAMEW) -> BOOL;
}

#[link(name = "shell32")]
extern "system" {
    fn DragAcceptFiles(h_wnd: HWND, f_accept: BOOL);
    fn DragQueryFileW(h_drop: HDROP, i_file: UINT, lpsz_file: *mut u16, cch: UINT) -> UINT;
    fn DragFinish(h_drop: HDROP);
}

fn to_wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

fn to_colorref(rgb: u32) -> DWORD {
    let r = (rgb >> 16) & 0xFF;
    let g = (rgb >> 8) & 0xFF;
    let b = rgb & 0xFF;
    (b << 16) | (g << 8) | r
}

unsafe fn open_image_file_dialog(hwnd: HWND) -> Option<PathBuf> {
    let mut file_buf = vec![0u16; 4096];
    let filter: Vec<u16> = "Obrazy Android (super.img, system.img)\0*.img\0Wszystkie pliki (*.*)\0*.*\0\0"
        .encode_utf16()
        .collect();
    let title = to_wide("Wybierz super.img lub system.img MysticalOS");
    let mut ofn: OPENFILENAMEW = std::mem::zeroed();
    ofn.l_struct_size = std::mem::size_of::<OPENFILENAMEW>() as DWORD;
    ofn.hwnd_owner = hwnd;
    ofn.lpstr_filter = filter.as_ptr();
    ofn.lpstr_file = file_buf.as_mut_ptr();
    ofn.n_max_file = file_buf.len() as DWORD;
    ofn.lpstr_title = title.as_ptr();
    ofn.flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST | OFN_NOCHANGEDIR;
    if GetOpenFileNameW(&mut ofn) != 0 {
        let len = file_buf.iter().position(|&c| c == 0).unwrap_or(0);
        if len > 0 {
            return Some(PathBuf::from(String::from_utf16_lossy(&file_buf[..len])));
        }
    }
    None
}

unsafe fn save_system_img_dialog(hwnd: HWND) -> Option<PathBuf> {
    let mut file_buf = vec![0u16; 4096];
    for (i, c) in "system.img".encode_utf16().enumerate() {
        file_buf[i] = c;
    }
    let filter: Vec<u16> = "Obraz partycji Android (*.img)\0*.img\0Wszystkie pliki (*.*)\0*.*\0\0"
        .encode_utf16()
        .collect();
    let title = to_wide("Zapisz wypakowany obraz system.img");
    let def_ext = to_wide("img");
    let mut ofn: OPENFILENAMEW = std::mem::zeroed();
    ofn.l_struct_size = std::mem::size_of::<OPENFILENAMEW>() as DWORD;
    ofn.hwnd_owner = hwnd;
    ofn.lpstr_filter = filter.as_ptr();
    ofn.lpstr_file = file_buf.as_mut_ptr();
    ofn.n_max_file = file_buf.len() as DWORD;
    ofn.lpstr_title = title.as_ptr();
    ofn.lpstr_def_ext = def_ext.as_ptr();
    ofn.flags = OFN_OVERWRITEPROMPT | OFN_NOCHANGEDIR;
    if GetSaveFileNameW(&mut ofn) != 0 {
        let len = file_buf.iter().position(|&c| c == 0).unwrap_or(0);
        if len > 0 {
            return Some(PathBuf::from(String::from_utf16_lossy(&file_buf[..len])));
        }
    }
    None
}

struct WindowCtx {
    state: EmulatorState,
    mem_dc: HDC,
    dib: HBITMAP,
    pixels: *mut u32,
    fonts: HashMap<(i32, bool), HFONT>,
}

impl WindowCtx {
    unsafe fn get_font(&mut self, px: i32, bold: bool) -> HFONT {
        let key = (px, bold);
        if let Some(&f) = self.fonts.get(&key) {
            return f;
        }
        let face = to_wide("Segoe UI");
        let f = CreateFontW(
            -px,
            0,
            0,
            0,
            if bold { 700 } else { 400 },
            0,
            0,
            0,
            1, // DEFAULT_CHARSET
            0,
            0,
            CLEARTYPE_QUALITY,
            0,
            face.as_ptr(),
        );
        self.fonts.insert(key, f);
        f
    }

    unsafe fn paint(&mut self, hwnd: HWND) {
        let mut ps: PAINTSTRUCT = std::mem::zeroed();
        let hdc = BeginPaint(hwnd, &mut ps);
        if self.mem_dc.is_null() || self.pixels.is_null() {
            EndPaint(hwnd, &ps);
            return;
        }

        let fb = std::slice::from_raw_parts_mut(self.pixels, (WIN_W * WIN_H) as usize);
        let texts = self.state.render(fb, WIN_W, WIN_H);
        GdiFlush();

        SetBkMode(self.mem_dc, TRANSPARENT);
        for td in texts {
            let font = self.get_font(td.size, td.bold);
            let old = SelectObject(self.mem_dc, font);
            SetTextColor(self.mem_dc, to_colorref(td.color));
            let mut rc = RECT {
                left: td.rect.x,
                top: td.rect.y,
                right: td.rect.x + td.rect.w,
                bottom: td.rect.y + td.rect.h,
            };
            let mut fmt = DT_NOPREFIX;
            fmt |= match td.align {
                TextAlign::Left => DT_LEFT,
                TextAlign::Center => DT_CENTER,
                TextAlign::Right => DT_RIGHT,
            };
            if td.text.contains('\n') || td.rect.h > td.size * 2 + 6 {
                fmt |= DT_WORDBREAK;
            } else {
                fmt |= DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS;
            }
            let wide: Vec<u16> = td.text.encode_utf16().collect();
            DrawTextW(self.mem_dc, wide.as_ptr(), wide.len() as i32, &mut rc, fmt);
            SelectObject(self.mem_dc, old);
        }

        BitBlt(hdc, 0, 0, WIN_W, WIN_H, self.mem_dc, 0, 0, SRCCOPY);
        EndPaint(hwnd, &ps);
    }

    unsafe fn save_bmp(&self) -> Result<String, ()> {
        let fb = std::slice::from_raw_parts(self.pixels, (WIN_W * WIN_H) as usize);
        let row_bytes = (WIN_W as usize) * 3;
        let pad = (4 - (row_bytes % 4)) % 4;
        let stride = row_bytes + pad;
        let img_size = stride * (WIN_H as usize);
        let file_size = 54 + img_size;

        let mut buf = Vec::with_capacity(file_size);
        buf.extend_from_slice(b"BM");
        buf.extend_from_slice(&(file_size as u32).to_le_bytes());
        buf.extend_from_slice(&0u32.to_le_bytes());
        buf.extend_from_slice(&54u32.to_le_bytes());

        buf.extend_from_slice(&40u32.to_le_bytes());
        buf.extend_from_slice(&(WIN_W as i32).to_le_bytes());
        buf.extend_from_slice(&(WIN_H as i32).to_le_bytes());
        buf.extend_from_slice(&1u16.to_le_bytes());
        buf.extend_from_slice(&24u16.to_le_bytes());
        buf.extend_from_slice(&0u32.to_le_bytes());
        buf.extend_from_slice(&(img_size as u32).to_le_bytes());
        buf.extend_from_slice(&2835i32.to_le_bytes());
        buf.extend_from_slice(&2835i32.to_le_bytes());
        buf.extend_from_slice(&0u32.to_le_bytes());
        buf.extend_from_slice(&0u32.to_le_bytes());

        for y in (0..WIN_H).rev() {
            let row = (y * WIN_W) as usize;
            for x in 0..WIN_W {
                let p = fb[row + x as usize];
                buf.push((p & 0xFF) as u8);
                buf.push(((p >> 8) & 0xFF) as u8);
                buf.push(((p >> 16) & 0xFF) as u8);
            }
            for _ in 0..pad {
                buf.push(0);
            }
        }
        let fname = "mysticalos_screenshot.bmp";
        let mut f = File::create(fname).map_err(|_| ())?;
        f.write_all(&buf).map_err(|_| ())?;
        Ok(fname.to_string())
    }
}

unsafe fn map_mouse(hwnd: HWND, l_param: LPARAM) -> (i32, i32) {
    let raw_x = (l_param & 0xFFFF) as i16 as i32;
    let raw_y = ((l_param >> 16) & 0xFFFF) as i16 as i32;
    let mut rc = std::mem::zeroed::<RECT>();
    GetClientRect(hwnd, &mut rc);
    let cw = (rc.right - rc.left).max(1);
    let ch = (rc.bottom - rc.top).max(1);
    ((raw_x * WIN_W) / cw, (raw_y * WIN_H) / ch)
}

unsafe extern "system" fn wnd_proc(hwnd: HWND, msg: UINT, w_param: WPARAM, l_param: LPARAM) -> LRESULT {
    let ptr = GetWindowLongPtrW(hwnd, GWLP_USERDATA) as *mut WindowCtx;
    if ptr.is_null() {
        return DefWindowProcW(hwnd, msg, w_param, l_param);
    }
    let ctx = &mut *ptr;

    match msg {
        WM_ERASEBKGND => 1,
        WM_PAINT => {
            ctx.paint(hwnd);
            0
        }
        WM_TIMER => {
            let mut st = std::mem::zeroed::<SYSTEMTIME>();
            GetLocalTime(&mut st);
            let now = GetTickCount64();
            ctx.state.tick(st.w_hour, st.w_minute);
            ctx.state.check_long_press(now);
            InvalidateRect(hwnd, ptr::null(), 0);
            0
        }
        WM_DROPFILES => {
            let hdrop = w_param as HDROP;
            let mut path_buf = vec![0u16; 2048];
            let n = DragQueryFileW(hdrop, 0, path_buf.as_mut_ptr(), path_buf.len() as UINT);
            if n > 0 {
                let p = PathBuf::from(String::from_utf16_lossy(&path_buf[..n as usize]));
                if let Err(e) = ctx.state.load_image_from_path(&p) {
                    ctx.state.status_msg = format!("Blad ładowania {}: {}", p.display(), e);
                    ctx.state.show_toast("Blad odczytu obrazu .img");
                }
            }
            DragFinish(hdrop);
            InvalidateRect(hwnd, ptr::null(), 0);
            0
        }
        WM_LBUTTONDOWN => {
            let (x, y) = map_mouse(hwnd, l_param);
            SetCapture(hwnd);
            let now = GetTickCount64();
            match ctx.state.handle_left_down(x, y, now) {
                UiCommand::SaveScreenshot => match ctx.save_bmp() {
                    Ok(f) => {
                        ctx.state.status_msg = format!("Zapisano zrzut: {}", f);
                        ctx.state.show_toast("Zapisano zrzut ekranu");
                    }
                    Err(_) => ctx.state.status_msg = "Nie udalo sie zapisac zrzutu".into(),
                },
                UiCommand::OpenImageDialog => {
                    ReleaseCapture();
                    if let Some(path) = open_image_file_dialog(hwnd) {
                        if let Err(e) = ctx.state.load_image_from_path(&path) {
                            ctx.state.status_msg = format!("Blad: {}", e);
                            ctx.state.show_toast("Nie udalo sie wczytac pliku .img");
                        }
                    }
                }
                UiCommand::ExtractSystemImg => {
                    ReleaseCapture();
                    if let Some(out) = save_system_img_dialog(hwnd) {
                        if let Err(e) = ctx.state.extract_system_img_to(&out) {
                            ctx.state.status_msg = format!("Blad eksportu: {}", e);
                            ctx.state.show_toast("Blad zapisu system.img");
                        }
                    }
                }
                UiCommand::None => {}
            }
            InvalidateRect(hwnd, ptr::null(), 0);
            0
        }
        WM_MOUSEMOVE => {
            if ctx.state.active_slider.is_some() {
                let (x, y) = map_mouse(hwnd, l_param);
                ctx.state.handle_mouse_move(x, y);
                InvalidateRect(hwnd, ptr::null(), 0);
            }
            0
        }
        WM_LBUTTONUP => {
            ReleaseCapture();
            let (x, y) = map_mouse(hwnd, l_param);
            ctx.state.handle_left_up(x, y);
            InvalidateRect(hwnd, ptr::null(), 0);
            0
        }
        WM_RBUTTONDOWN => {
            let (x, y) = map_mouse(hwnd, l_param);
            ctx.state.handle_right_down(x, y);
            InvalidateRect(hwnd, ptr::null(), 0);
            0
        }
        WM_MOUSEWHEEL => {
            let delta = ((w_param >> 16) & 0xFFFF) as i16 as i32;
            ctx.state.apply_action(HitAction::ScrollAudit(if delta < 0 { 3 } else { -3 }));
            InvalidateRect(hwnd, ptr::null(), 0);
            0
        }
        WM_DESTROY => {
            KillTimer(hwnd, 1);
            PostQuitMessage(0);
            0
        }
        _ => DefWindowProcW(hwnd, msg, w_param, l_param),
    }
}

fn find_initial_image() -> Option<PathBuf> {
    if let Some(arg) = std::env::args_os().nth(1) {
        let p = PathBuf::from(arg);
        if p.is_file() {
            return Some(p);
        }
    }
    let mut dirs = Vec::new();
    if let Ok(cwd) = std::env::current_dir() {
        dirs.push(cwd);
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(parent) = exe.parent() {
            dirs.push(parent.to_path_buf());
        }
    }
    for dir in dirs {
        for cand in ["super.img", "system.img", "package/super.img", "images/super.img", "images/system.img"] {
            let p = dir.join(cand);
            if p.is_file() {
                return Some(p);
            }
        }
    }
    None
}

pub fn run_windows_emulator(manifest_json: &str) {
    unsafe {
        let hinst = GetModuleHandleW(ptr::null());
        let cls_name = to_wide("MysticalOSEmulatorWnd");
        let title = to_wide("MysticalOS 1.0 (Flux17) - super.img / system.img Emulator");

        let wc = WNDCLASSEXW {
            cb_size: std::mem::size_of::<WNDCLASSEXW>() as UINT,
            style: 0,
            lpfn_wnd_proc: Some(wnd_proc),
            cb_cls_extra: 0,
            cb_wnd_extra: 0,
            h_instance: hinst,
            h_icon: ptr::null_mut(),
            h_cursor: LoadCursorW(ptr::null_mut(), IDC_ARROW as *const u16),
            hbr_background: ptr::null_mut(),
            lpsz_menu_name: ptr::null(),
            lpsz_class_name: cls_name.as_ptr(),
            h_icon_sm: ptr::null_mut(),
        };
        RegisterClassExW(&wc);

        let mut win_rc = RECT { left: 0, top: 0, right: WIN_W, bottom: WIN_H };
        AdjustWindowRectEx(&mut win_rc, WS_STYLE, 0, 0);

        let hwnd = CreateWindowExW(
            0,
            cls_name.as_ptr(),
            title.as_ptr(),
            WS_STYLE,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            win_rc.right - win_rc.left,
            win_rc.bottom - win_rc.top,
            ptr::null_mut(),
            ptr::null_mut(),
            hinst,
            ptr::null_mut(),
        );
        if hwnd.is_null() {
            return;
        }
        DragAcceptFiles(hwnd, 1);

        let mem_dc = CreateCompatibleDC(ptr::null_mut());
        let bmi = BITMAPINFO {
            bmi_header: BITMAPINFOHEADER {
                bi_size: std::mem::size_of::<BITMAPINFOHEADER>() as DWORD,
                bi_width: WIN_W,
                bi_height: -WIN_H,
                bi_planes: 1,
                bi_bit_count: 32,
                bi_compression: 0, // BI_RGB
                bi_size_image: 0,
                bi_x_pels_per_meter: 0,
                bi_y_pels_per_meter: 0,
                bi_clr_used: 0,
                bi_clr_important: 0,
            },
            bmi_colors: [0],
        };
        let mut bits: *mut c_void = ptr::null_mut();
        let dib = CreateDIBSection(mem_dc, &bmi, 0, &mut bits, ptr::null_mut(), 0);
        let old_bmp = SelectObject(mem_dc, dib);

        let mut state = EmulatorState::new(manifest_json);
        if let Some(p) = find_initial_image() {
            if let Err(e) = state.load_image_from_path(&p) {
                state.status_msg = format!("Auto-odczyt {}: {}", p.display(), e);
            }
        }

        let ctx = Box::new(WindowCtx {
            state,
            mem_dc,
            dib,
            pixels: bits as *mut u32,
            fonts: HashMap::new(),
        });

        let raw_ctx = Box::into_raw(ctx);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, raw_ctx as isize);
        SetTimer(hwnd, 1, 33, ptr::null_mut());

        let mut msg = std::mem::zeroed::<MSG>();
        while GetMessageW(&mut msg, ptr::null_mut(), 0, 0) > 0 {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }

        SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
        let ctx_box = Box::from_raw(raw_ctx);
        for (_, f) in &ctx_box.fonts {
            DeleteObject(*f);
        }
        SelectObject(ctx_box.mem_dc, old_bmp);
        DeleteObject(ctx_box.dib);
        DeleteDC(ctx_box.mem_dc);
    }
}
