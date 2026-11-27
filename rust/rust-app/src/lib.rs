#![allow(unused_imports)]
use std::ffi::{c_char, c_int, c_uint, c_void};
use std::fs;
#[cfg(target_os = "android")]
use std::ptr;
#[cfg(target_os = "android")]
use std::sync::atomic::{AtomicBool, Ordering};
#[cfg(target_os = "android")]
use std::sync::Arc;
#[cfg(target_os = "android")]
use std::thread;
#[cfg(target_os = "android")]
use std::time::Duration;

#[allow(dead_code)]
#[repr(C)]
pub struct ANativeActivity {
    pub callbacks: *mut ANativeActivityCallbacks,
    pub vm: *mut c_void,
    pub env: *mut c_void,
    pub clazz: *mut c_void,
    pub internal_data_path: *const c_char,
    pub external_data_path: *const c_char,
    pub sdk_version: i32,
    pub instance: *mut c_void,
    pub asset_manager: *mut c_void,
    pub obb_path: *const c_char,
}

#[allow(dead_code)]
#[repr(C)]
pub struct ANativeActivityCallbacks {
    pub on_start: Option<unsafe extern "C" fn(*mut ANativeActivity)>,
    pub on_resume: Option<unsafe extern "C" fn(*mut ANativeActivity)>,
    pub on_save_instance_state: Option<unsafe extern "C" fn(*mut ANativeActivity, *mut usize) -> *mut c_void>,
    pub on_pause: Option<unsafe extern "C" fn(*mut ANativeActivity)>,
    pub on_stop: Option<unsafe extern "C" fn(*mut ANativeActivity)>,
    pub on_destroy: Option<unsafe extern "C" fn(*mut ANativeActivity)>,
    pub on_window_focus_changed: Option<unsafe extern "C" fn(*mut ANativeActivity, c_int)>,
    pub on_native_window_created: Option<unsafe extern "C" fn(*mut ANativeActivity, *mut c_void)>,
    pub on_native_window_resized: Option<unsafe extern "C" fn(*mut ANativeActivity, *mut c_void)>,
    pub on_native_window_redraw_needed: Option<unsafe extern "C" fn(*mut ANativeActivity, *mut c_void)>,
    pub on_native_window_destroyed: Option<unsafe extern "C" fn(*mut ANativeActivity, *mut c_void)>,
    pub on_input_queue_created: Option<unsafe extern "C" fn(*mut ANativeActivity, *mut c_void)>,
    pub on_input_queue_destroyed: Option<unsafe extern "C" fn(*mut ANativeActivity, *mut c_void)>,
    pub on_content_rect_changed: Option<unsafe extern "C" fn(*mut ANativeActivity, *const c_void)>,
    pub on_configuration_changed: Option<unsafe extern "C" fn(*mut ANativeActivity)>,
    pub on_low_memory: Option<unsafe extern "C" fn(*mut ANativeActivity)>,
}

#[cfg(target_os = "android")]
type EGLDisplay = *mut c_void;
#[cfg(target_os = "android")]
type EGLConfig = *mut c_void;
#[cfg(target_os = "android")]
type EGLSurface = *mut c_void;
#[cfg(target_os = "android")]
type EGLContext = *mut c_void;

#[cfg(target_os = "android")]
#[link(name = "log")]
extern "C" {
    fn __android_log_write(prio: c_int, tag: *const c_char, text: *const c_char) -> c_int;
}

#[cfg(target_os = "android")]
#[link(name = "android")]
extern "C" {
    fn ANativeWindow_getWidth(window: *mut c_void) -> i32;
    fn ANativeWindow_getHeight(window: *mut c_void) -> i32;
}

#[cfg(target_os = "android")]
#[link(name = "EGL")]
extern "C" {
    fn eglGetDisplay(display_id: *mut c_void) -> EGLDisplay;
    fn eglInitialize(dpy: EGLDisplay, major: *mut c_int, minor: *mut c_int) -> c_uint;
    fn eglChooseConfig(
        dpy: EGLDisplay,
        attrib_list: *const c_int,
        configs: *mut EGLConfig,
        config_size: c_int,
        num_config: *mut c_int,
    ) -> c_uint;
    fn eglCreateWindowSurface(
        dpy: EGLDisplay,
        config: EGLConfig,
        win: *mut c_void,
        attrib_list: *const c_int,
    ) -> EGLSurface;
    fn eglCreateContext(
        dpy: EGLDisplay,
        config: EGLConfig,
        share_context: EGLContext,
        attrib_list: *const c_int,
    ) -> EGLContext;
    fn eglMakeCurrent(
        dpy: EGLDisplay,
        draw: EGLSurface,
        read: EGLSurface,
        ctx: EGLContext,
    ) -> c_uint;
    fn eglSwapBuffers(dpy: EGLDisplay, surface: EGLSurface) -> c_uint;
    fn eglDestroySurface(dpy: EGLDisplay, surface: EGLSurface) -> c_uint;
    fn eglDestroyContext(dpy: EGLDisplay, ctx: EGLContext) -> c_uint;
    fn eglTerminate(dpy: EGLDisplay) -> c_uint;
}

#[cfg(target_os = "android")]
#[link(name = "GLESv2")]
extern "C" {
    fn glViewport(x: i32, y: i32, width: i32, height: i32);
    fn glEnable(cap: c_uint);
    fn glDisable(cap: c_uint);
    fn glScissor(x: i32, y: i32, width: i32, height: i32);
    fn glClearColor(red: f32, green: f32, blue: f32, alpha: f32);
    fn glClear(mask: c_uint);
}

#[cfg(target_os = "android")]
fn log_info(msg: &str) {
    let mut buf = msg.as_bytes().to_vec();
    buf.push(0);
    unsafe {
        __android_log_write(4, b"Redmi9CRust\0".as_ptr() as *const c_char, buf.as_ptr() as *const c_char);
    }
}

pub fn parse_mem_ratio(raw: &str) -> (u64, u64, f32) {
    let mut total_kib = 0u64;
    let mut avail_kib = 0u64;
    for line in raw.lines() {
        let mut it = line.split_whitespace();
        match it.next() {
            Some("MemTotal:") => total_kib = it.next().and_then(|s| s.parse().ok()).unwrap_or(0),
            Some("MemAvailable:") => avail_kib = it.next().and_then(|s| s.parse().ok()).unwrap_or(0),
            _ => {}
        }
    }
    let free_ratio = if total_kib > 0 {
        (avail_kib as f32 / total_kib as f32).clamp(0.0, 1.0)
    } else {
        0.5
    };
    (total_kib / 1024, avail_kib / 1024, free_ratio)
}

pub fn read_mem_ratio() -> (u64, u64, f32) {
    let raw = fs::read_to_string("/proc/meminfo").unwrap_or_default();
    parse_mem_ratio(&raw)
}

#[cfg(target_os = "android")]
mod android_app {
    use super::*;

    type EGLDisplay = *mut c_void;
    type EGLConfig = *mut c_void;
    type EGLSurface = *mut c_void;
    type EGLContext = *mut c_void;

    const EGL_NO_DISPLAY: EGLDisplay = ptr::null_mut();
    const EGL_NO_CONTEXT: EGLContext = ptr::null_mut();
    const EGL_NO_SURFACE: EGLSurface = ptr::null_mut();
    const EGL_RED_SIZE: c_int = 0x3024;
    const EGL_GREEN_SIZE: c_int = 0x3023;
    const EGL_BLUE_SIZE: c_int = 0x3022;
    const EGL_RENDERABLE_TYPE: c_int = 0x3040;
    const EGL_OPENGL_ES2_BIT: c_int = 0x0004;
    const EGL_CONTEXT_CLIENT_VERSION: c_int = 0x3098;
    const EGL_NONE: c_int = 0x3038;
    const GL_COLOR_BUFFER_BIT: c_uint = 0x00004000;
    const GL_SCISSOR_TEST: c_uint = 0x0C11;

    struct AppState {
        running: Arc<AtomicBool>,
        render_thread: Option<thread::JoinHandle<()>>,
    }

    struct SendPtr(*mut c_void);
    unsafe impl Send for SendPtr {}

    pub unsafe extern "C" fn on_window_created(activity: *mut ANativeActivity, window: *mut c_void) {
        if activity.is_null() || (*activity).instance.is_null() || window.is_null() {
            return;
        }
        let state = &mut *((*activity).instance as *mut AppState);
        if let Some(h) = state.render_thread.take() {
            state.running.store(false, Ordering::SeqCst);
            let _ = h.join();
        }
        state.running.store(true, Ordering::SeqCst);
        let running = Arc::clone(&state.running);
        let win_wrap = SendPtr(window);

        log_info("Rust NativeActivity window created - starting GLES2 monitor");
        state.render_thread = Some(thread::spawn(move || {
            let win = win_wrap.0;
            let dpy = eglGetDisplay(ptr::null_mut());
            if dpy == EGL_NO_DISPLAY || eglInitialize(dpy, ptr::null_mut(), ptr::null_mut()) == 0 {
                log_info("EGL init failed");
                return;
            }
            let attribs = [
                EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
                EGL_RED_SIZE, 8,
                EGL_GREEN_SIZE, 8,
                EGL_BLUE_SIZE, 8,
                EGL_NONE,
            ];
            let mut cfg: EGLConfig = ptr::null_mut();
            let mut num_cfg: c_int = 0;
            if eglChooseConfig(dpy, attribs.as_ptr(), &mut cfg, 1, &mut num_cfg) == 0 || num_cfg < 1 {
                eglTerminate(dpy);
                return;
            }
            let surface = eglCreateWindowSurface(dpy, cfg, win, ptr::null());
            let ctx_attribs = [EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE];
            let ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctx_attribs.as_ptr());
            if surface == EGL_NO_SURFACE || ctx == EGL_NO_CONTEXT || eglMakeCurrent(dpy, surface, surface, ctx) == 0 {
                eglTerminate(dpy);
                return;
            }

            let mut tick: u32 = 0;
            while running.load(Ordering::SeqCst) {
                let w = ANativeWindow_getWidth(win).max(1);
                let h = ANativeWindow_getHeight(win).max(1);
                let (total_mib, avail_mib, free_ratio) = read_mem_ratio();
                if tick % 30 == 0 {
                    log_info(&format!("Rust APK live RAM: free={}MiB / total={}MiB ({}x{})", avail_mib, total_mib, w, h));
                }
                tick = tick.wrapping_add(1);

                glDisable(GL_SCISSOR_TEST);
                glViewport(0, 0, w, h);
                glClearColor(0.08, 0.10, 0.14, 1.0);
                glClear(GL_COLOR_BUFFER_BIT);

                // Draw live RAM health bar using GLES2 scissor clear (Rust orange vs emerald free RAM)
                glEnable(GL_SCISSOR_TEST);
                let bar_w = (w * 4) / 5;
                let bar_x = (w - bar_w) / 2;
                let bar_h = (h / 14).max(24);
                let bar_y = h / 2 - bar_h / 2;
                glScissor(bar_x, bar_y, bar_w, bar_h);
                glClearColor(0.85, 0.32, 0.14, 1.0);
                glClear(GL_COLOR_BUFFER_BIT);

                let free_w = ((bar_w as f32) * free_ratio) as i32;
                if free_w > 0 {
                    glScissor(bar_x, bar_y, free_w, bar_h);
                    glClearColor(0.16, 0.78, 0.45, 1.0);
                    glClear(GL_COLOR_BUFFER_BIT);
                }
                glDisable(GL_SCISSOR_TEST);

                eglSwapBuffers(dpy, surface);
                thread::sleep(Duration::from_millis(66));
            }

            eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
            eglDestroySurface(dpy, surface);
            eglDestroyContext(dpy, ctx);
            eglTerminate(dpy);
        }));
    }

    pub unsafe extern "C" fn on_window_destroyed(activity: *mut ANativeActivity, _window: *mut c_void) {
        if activity.is_null() || (*activity).instance.is_null() {
            return;
        }
        let state = &mut *((*activity).instance as *mut AppState);
        state.running.store(false, Ordering::SeqCst);
        if let Some(h) = state.render_thread.take() {
            let _ = h.join();
        }
    }

    pub unsafe extern "C" fn on_destroy(activity: *mut ANativeActivity) {
        if activity.is_null() || (*activity).instance.is_null() {
            return;
        }
        let mut boxed = Box::from_raw((*activity).instance as *mut AppState);
        boxed.running.store(false, Ordering::SeqCst);
        if let Some(h) = boxed.render_thread.take() {
            let _ = h.join();
        }
        (*activity).instance = ptr::null_mut();
    }

    pub unsafe fn create(activity: *mut ANativeActivity) {
        log_info("ANativeActivity_onCreate (pure Rust aarch64 APK)");
        let state = Box::new(AppState {
            running: Arc::new(AtomicBool::new(false)),
            render_thread: None,
        });
        (*activity).instance = Box::into_raw(state) as *mut c_void;
        let cb = &mut *(*activity).callbacks;
        cb.on_native_window_created = Some(on_window_created);
        cb.on_native_window_destroyed = Some(on_window_destroyed);
        cb.on_destroy = Some(on_destroy);
    }
}

#[cfg(target_os = "android")]
#[no_mangle]
pub unsafe extern "C" fn ANativeActivity_onCreate(
    activity: *mut ANativeActivity,
    _saved_state: *mut c_void,
    _saved_state_size: usize,
) {
    if !activity.is_null() {
        android_app::create(activity);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_mem_ratio() {
        let (tot, avail, ratio) = parse_mem_ratio("MemTotal: 2048000 kB\nMemAvailable: 512000 kB\n");
        assert_eq!(tot, 2000);
        assert_eq!(avail, 500);
        assert!((ratio - 0.25).abs() < 0.01);
    }
}
