#![allow(dead_code)]
use crate::image_reader::{
    extract_named_partition, inspect_image_file, list_path_in_image, read_text_in_image, FsEntry,
    LoadedImageData,
};
use std::f32::consts::PI;
use std::path::Path;

pub const WIN_W: i32 = 1140;
pub const WIN_H: i32 = 860;

// Phone frame and inner screen geometry (720x1600 scaled 1:2 -> 360x800)
pub const PHONE_FRAME_X: i32 = 34;
pub const PHONE_FRAME_Y: i32 = 18;
pub const PHONE_FRAME_W: i32 = 392;
pub const PHONE_FRAME_H: i32 = 824;

pub const SCR_X: i32 = PHONE_FRAME_X + 16; // 50
pub const SCR_Y: i32 = PHONE_FRAME_Y + 12; // 30
pub const SCR_W: i32 = 360;
pub const SCR_H: i32 = 800;

pub const STATUS_H: i32 = 28;
pub const NAV_H: i32 = 32;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum IconShape {
    Squircle = 0,
    Circle = 1,
    Rounded = 2,
    Teardrop = 3,
}

impl IconShape {
    pub fn name(self) -> &'static str {
        match self {
            IconShape::Squircle => "Squircle",
            IconShape::Circle => "Kolo",
            IconShape::Rounded => "Kwadrat",
            IconShape::Teardrop => "Kropla",
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum TileSpan {
    S1x1,
    S2x1,
    S1x2,
    S2x2,
}

impl TileSpan {
    pub fn dims(self) -> (usize, usize) {
        match self {
            TileSpan::S1x1 => (1, 1),
            TileSpan::S2x1 => (2, 1),
            TileSpan::S1x2 => (1, 2),
            TileSpan::S2x2 => (2, 2),
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            TileSpan::S1x1 => "1x1",
            TileSpan::S2x1 => "2x1",
            TileSpan::S1x2 => "1x2",
            TileSpan::S2x2 => "2x2",
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum AppKind {
    IconStyle,
    Settings,
    Phone,
    Messages,
    Contacts,
    Camera,
    Gallery,
    Files,
    Clock,
    Calculator,
    DroidIfy,
    MicroG,
    RustMonitor,
    RomAudit,
    ImageExplorer,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum UiCommand {
    None,
    SaveScreenshot,
    OpenImageDialog,
    ExtractSystemImg,
}

#[derive(Clone, Debug)]
pub struct AppIcon {
    pub title: String,
    pub package: String,
    pub kind: AppKind,
    pub color1: u32,
    pub color2: u32,
    pub glyph: &'static str,
    pub span: TileSpan,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Screen {
    BootAnim,
    LockScreen,
    Home,
    IconEditor,
    ControlCenter,
    TileMenu(usize),
    App(AppKind),
}

#[derive(Clone, Debug)]
pub struct ManifestSummary {
    pub os_name: String,
    pub os_version: String,
    pub codename: String,
    pub market_name: String,
    pub android_version: String,
    pub kernel_version: String,
    pub base_rom: String,
    pub donor_rom: String,
    pub removed_count: u32,
    pub freed_mib: u32,
    pub removed_items: Vec<String>,
    pub app_labels: Vec<(String, String)>,
    pub services_spoof: String,
}

#[derive(Clone, Copy, Debug)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
}

impl Rect {
    pub fn contains(&self, px: i32, py: i32) -> bool {
        px >= self.x && px < self.x + self.w && py >= self.y && py < self.y + self.h
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum TextAlign {
    Left,
    Center,
    Right,
}

#[derive(Clone, Debug)]
pub struct TextDraw {
    pub rect: Rect,
    pub text: String,
    pub color: u32,
    pub size: i32,
    pub bold: bool,
    pub align: TextAlign,
    pub clip_to_screen: bool,
}

#[derive(Clone, Copy, Debug)]
pub enum HitAction {
    OpenApp(AppKind),
    OpenIconMenu(usize),
    SetTileSpan(usize, TileSpan),
    GoScreen(Screen),
    Back,
    Home,
    LockToggle,
    RestartBoot,
    SaveScreenshot,
    SetIconScale(i32),
    DragIconSlider(Rect),
    DragBrightnessSlider(Rect),
    SetShape(IconShape),
    SetGridCols(usize),
    ToggleLabels,
    SetWallpaper(usize),
    ResetTiles,
    ToggleDark,
    ToggleWifi,
    ToggleBt,
    ToggleFlashlight,
    ToggleNavGestures,
    ToggleRamVariant,
    CalcKey(char),
    CameraShutter,
    ScrollAudit(i32),
    OpenImageDialog,
    ExtractSystemImg,
    ExplorerSelectPartIdx(usize),
    ExplorerOpenEntry(usize),
    ExplorerUpDir,
    ExplorerClosePreview,
}

#[derive(Clone, Debug)]
pub struct HitRegion {
    pub rect: Rect,
    pub action: HitAction,
    pub long_press_app: Option<usize>,
}

#[derive(Clone, Debug)]
pub struct PlacedTile {
    pub app_idx: usize,
    pub rect: Rect,
    pub icon_rect: Rect,
    pub c_span: usize,
    pub r_span: usize,
}

pub struct EmulatorState {
    pub manifest: ManifestSummary,
    pub screen: Screen,
    pub prev_screen: Screen,
    pub apps: Vec<AppIcon>,
    pub icon_scale: i32, // 60..150
    pub icon_shape: IconShape,
    pub grid_cols: usize, // 4 or 5
    pub show_labels: bool,
    pub wallpaper_idx: usize,
    pub dark_mode: bool,
    pub wifi_on: bool,
    pub bt_on: bool,
    pub flashlight_on: bool,
    pub brightness: i32, // 30..100
    pub gesture_nav: bool,
    pub ram_3gb: bool,
    pub boot_ticks: u32,
    pub anim_tick: u32,
    pub clock_hh: u16,
    pub clock_mm: u16,
    pub date_str: String,
    pub audit_scroll: i32,
    pub camera_shots: u32,
    pub camera_flash_ticks: u32,
    pub toast: Option<(String, u32)>,
    // Calculator state
    pub calc_display: String,
    pub calc_acc: f64,
    pub calc_op: Option<char>,
    pub calc_fresh: bool,
    // Real super.img / system.img runtime state
    pub loaded_image: Option<LoadedImageData>,
    pub explorer_part: String,
    pub explorer_dir: String,
    pub explorer_entries: Vec<FsEntry>,
    pub explorer_file_preview: Option<(String, String)>,
    // Interactive state per frame
    pub hits: Vec<HitRegion>,
    pub active_slider: Option<HitAction>,
    pub pending_long_press: Option<(usize, u64)>,
    pub status_msg: String,
}

fn extract_json_str(src: &str, key: &str, default: &str) -> String {
    let pat = format!("\"{}\":", key);
    if let Some(pos) = src.find(&pat) {
        let rest = src[pos + pat.len()..].trim_start();
        if let Some(after_q) = rest.strip_prefix('"') {
            if let Some(end_q) = after_q.find('"') {
                return after_q[..end_q].to_string();
            }
        }
    }
    default.to_string()
}

fn extract_json_u32(src: &str, key: &str, default: u32) -> u32 {
    let pat = format!("\"{}\":", key);
    if let Some(pos) = src.find(&pat) {
        let rest = src[pos + pat.len()..].trim_start();
        let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
        if let Ok(v) = digits.parse::<u32>() {
            return v;
        }
    }
    default
}

fn extract_removed_items(src: &str) -> Vec<String> {
    let mut out = Vec::new();
    if let Some(pos) = src.find("\"removed_items\":") {
        let rest = &src[pos..];
        if let (Some(lb), Some(rb)) = (rest.find('['), rest.find(']')) {
            let inside = &rest[lb + 1..rb];
            for part in inside.split(',') {
                let s = part.trim().trim_matches('"');
                if !s.is_empty() {
                    out.push(s.to_string());
                }
            }
        }
    }
    out
}

fn extract_launchable_apps(src: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    if let Some(pos) = src.find("\"launchable_apps\":") {
        let rest = &src[pos..];
        let mut cur = rest;
        while let Some(lp) = cur.find("\"label\":") {
            let lbl = extract_json_str(&cur[lp..], "label", "");
            let pkg = extract_json_str(&cur[lp.saturating_sub(80)..], "package", "");
            if !lbl.is_empty() {
                out.push((lbl, pkg));
            }
            cur = &cur[lp + 8..];
        }
    }
    out
}

pub fn parse_manifest(src: &str) -> ManifestSummary {
    ManifestSummary {
        os_name: extract_json_str(src, "os_name", "MysticalOS"),
        os_version: extract_json_str(src, "os_version", "1.0"),
        codename: extract_json_str(src, "codename", "Flux17"),
        market_name: extract_json_str(src, "market_name", "Redmi 9C"),
        android_version: extract_json_str(src, "android_version", "17"),
        kernel_version: extract_json_str(src, "kernel_version", "4.19-blossom"),
        base_rom: extract_json_str(src, "base_rom", "EvolutionX 17.0 blossom"),
        donor_rom: extract_json_str(src, "donor_rom", "HyperOS 4.0.8.0 debloated"),
        removed_count: extract_json_u32(src, "removed_count", 80),
        freed_mib: extract_json_u32(src, "freed_mib", 5200),
        removed_items: extract_removed_items(src),
        app_labels: extract_launchable_apps(src),
        services_spoof: extract_json_str(src, "services_spoof", "services.jar spoof: checked"),
    }
}

pub fn default_app_icons() -> Vec<AppIcon> {
    vec![
        AppIcon {
            title: "Ikony ColorOS 17".into(),
            package: "org.mysticalos.launcher".into(),
            kind: AppKind::IconStyle,
            color1: 0x5B3CF5,
            color2: 0x00D6FF,
            glyph: "ICO",
            span: TileSpan::S2x1,
        },
        AppIcon {
            title: "Ustawienia".into(),
            package: "com.android.settings".into(),
            kind: AppKind::Settings,
            color1: 0x3A4A6B,
            color2: 0x627AA8,
            glyph: "SET",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Rust Monitor".into(),
            package: "org.redmi9c.rustmonitor".into(),
            kind: AppKind::RustMonitor,
            color1: 0xC8461E,
            color2: 0x26C472,
            glyph: "RAM",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Telefon".into(),
            package: "org.fossify.phone".into(),
            kind: AppKind::Phone,
            color1: 0x1B9E4B,
            color2: 0x3ED976,
            glyph: "TEL",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Wiadomosci".into(),
            package: "org.fossify.messages".into(),
            kind: AppKind::Messages,
            color1: 0x167EE6,
            color2: 0x45B3FF,
            glyph: "SMS",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Aparat".into(),
            package: "org.fossify.camera".into(),
            kind: AppKind::Camera,
            color1: 0x252B3B,
            color2: 0x5C6BC0,
            glyph: "CAM",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Galeria".into(),
            package: "org.fossify.gallery".into(),
            kind: AppKind::Gallery,
            color1: 0xE86A17,
            color2: 0xFFB02E,
            glyph: "IMG",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Pliki".into(),
            package: "org.fossify.filemanager".into(),
            kind: AppKind::Files,
            color1: 0xD9821E,
            color2: 0xF5B942,
            glyph: "DIR",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Zegar".into(),
            package: "org.fossify.clock".into(),
            kind: AppKind::Clock,
            color1: 0x2F3B5E,
            color2: 0x7A8EC2,
            glyph: "CLK",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Kalkulator".into(),
            package: "org.fossify.calculator".into(),
            kind: AppKind::Calculator,
            color1: 0x00897B,
            color2: 0x26D0BE,
            glyph: "123",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Kontakty".into(),
            package: "org.fossify.contacts".into(),
            kind: AppKind::Contacts,
            color1: 0x1E6AE6,
            color2: 0x62A4FF,
            glyph: "USR",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Droid-ify".into(),
            package: "com.looker.droidify".into(),
            kind: AppKind::DroidIfy,
            color1: 0x4A38D9,
            color2: 0x8F75FF,
            glyph: "APK",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "microG".into(),
            package: "com.google.android.gms".into(),
            kind: AppKind::MicroG,
            color1: 0x1E7E72,
            color2: 0x3FD6A4,
            glyph: "mG",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Audyt ROM".into(),
            package: "org.mysticalos.audit".into(),
            kind: AppKind::RomAudit,
            color1: 0x6B2FD9,
            color2: 0xFF5FA2,
            glyph: "ROM",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Obraz .img".into(),
            package: "org.mysticalos.imgexplorer".into(),
            kind: AppKind::ImageExplorer,
            color1: 0x0E7490,
            color2: 0x06B6D4,
            glyph: "IMG+",
            span: TileSpan::S1x1,
        },
    ]
}

impl EmulatorState {
    pub fn new(manifest_json: &str) -> Self {
        Self {
            manifest: parse_manifest(manifest_json),
            screen: Screen::BootAnim,
            prev_screen: Screen::Home,
            apps: default_app_icons(),
            icon_scale: 100,
            icon_shape: IconShape::Squircle,
            grid_cols: 4,
            show_labels: true,
            wallpaper_idx: 0,
            dark_mode: true,
            wifi_on: true,
            bt_on: false,
            flashlight_on: false,
            brightness: 88,
            gesture_nav: true,
            ram_3gb: false,
            boot_ticks: 0,
            anim_tick: 0,
            clock_hh: 14,
            clock_mm: 20,
            date_str: "czw, 26 lis".into(),
            audit_scroll: 0,
            camera_shots: 0,
            camera_flash_ticks: 0,
            toast: None,
            calc_display: "0".into(),
            calc_acc: 0.0,
            calc_op: None,
            calc_fresh: true,
            loaded_image: None,
            explorer_part: "system".into(),
            explorer_dir: "/".into(),
            explorer_entries: Vec::new(),
            explorer_file_preview: None,
            hits: Vec::new(),
            active_slider: None,
            pending_long_press: None,
            status_msg: "Brak otwartego super.img/system.img — uzyj 'Otworz super.img / system.img...' lub przeciagnij plik na okno.".into(),
        }
    }

    pub fn load_image_from_path(&mut self, path: &Path) -> Result<(), String> {
        let data = inspect_image_file(path)?;
        if let Some(rel) = data.props.get("ro.build.version.release") {
            self.manifest.android_version = rel.clone();
        }
        if let Some(m) = data.props.get("ro.product.system.model").or_else(|| data.props.get("ro.product.model")) {
            self.manifest.market_name = m.clone();
        }
        if let Some(v) = data.props.get("ro.mysticalos.version") {
            self.manifest.os_version = v.clone();
        }
        if let Some(disp) = data.props.get("ro.build.display.id") {
            self.manifest.base_rom = disp.clone();
        }
        if !data.services_spoof_verified.is_empty() {
            self.manifest.services_spoof = data.services_spoof_verified.clone();
        }
        if !data.apks.is_empty() {
            self.manifest.app_labels = data
                .apks
                .iter()
                .map(|a| (format!("{} [{}]", a.dir_name, a.partition), a.package.clone()))
                .collect();
        }

        let default_part = data
            .partitions
            .iter()
            .find(|p| p.name == "system" && (p.fs_kind == "erofs" || p.fs_kind == "ext4"))
            .or_else(|| data.partitions.iter().find(|p| p.fs_kind == "erofs" || p.fs_kind == "ext4"))
            .map(|p| p.name.clone())
            .unwrap_or_else(|| "system".into());

        let part_cnt = data.partitions.len();
        let apk_cnt = data.apks.len();
        let kind_s = data.container_kind.clone();
        self.loaded_image = Some(data);
        self.explorer_part = default_part;
        self.explorer_dir = "/".into();
        self.explorer_file_preview = None;
        self.audit_scroll = 0;
        self.refresh_explorer();
        self.status_msg = format!("Zaladowano {}: {} partycji, {} APK-ow z obrazu!", kind_s, part_cnt, apk_cnt);
        self.show_toast(&format!("Wczytano {} ({} APK)", kind_s, apk_cnt));
        Ok(())
    }

    pub fn refresh_explorer(&mut self) {
        self.explorer_entries.clear();
        if let Some(img) = &self.loaded_image {
            let p = Path::new(&img.file_path);
            if let Ok(mut list) = list_path_in_image(p, &self.explorer_part, &self.explorer_dir) {
                list.sort_by(|a, b| b.is_dir.cmp(&a.is_dir).then_with(|| a.name.cmp(&b.name)));
                self.explorer_entries = list;
            }
        }
    }

    pub fn extract_system_img_to(&mut self, out_path: &Path) -> Result<u64, String> {
        let src_str = self
            .loaded_image
            .as_ref()
            .map(|img| img.file_path.clone())
            .ok_or_else(|| "Najpierw otworz plik super.img".to_string())?;
        let src = Path::new(&src_str);
        let sz = extract_named_partition(src, "system", out_path)?;
        self.status_msg = format!(
            "Wyeksportowano system.img ({} MiB) do {}",
            sz / (1024 * 1024),
            out_path.display()
        );
        self.show_toast("Zapisano system.img z super.img!");
        Ok(sz)
    }

    pub fn tick(&mut self, hh: u16, mm: u16) {
        self.clock_hh = hh;
        self.clock_mm = mm;
        self.anim_tick = self.anim_tick.wrapping_add(1);
        if self.screen == Screen::BootAnim {
            self.boot_ticks += 1;
            if self.boot_ticks >= 66 {
                self.screen = Screen::LockScreen;
            }
        }
        if self.camera_flash_ticks > 0 {
            self.camera_flash_ticks -= 1;
        }
        if let Some((_, rem)) = &mut self.toast {
            if *rem <= 1 {
                self.toast = None;
            } else {
                *rem -= 1;
            }
        }
    }

    pub fn show_toast(&mut self, msg: &str) {
        self.toast = Some((msg.to_string(), 75));
    }

    pub fn compute_grid(&self) -> Vec<PlacedTile> {
        let cols = self.grid_cols.max(4).min(5);
        let grid_x = SCR_X + 12;
        let grid_y = SCR_Y + STATUS_H + 106;
        let grid_w = SCR_W - 24;
        let cell_w = grid_w / cols as i32;
        let base_icon = if cols == 5 { 36 } else { 42 };
        let icon_sz = ((base_icon * self.icon_scale) / 100).max(24).min(68);
        let unit_h = (icon_sz + 28).max(66);

        let mut occ = vec![vec![false; cols]; 40];
        let mut out = Vec::new();

        for (idx, app) in self.apps.iter().enumerate() {
            let (raw_c, raw_r) = app.span.dims();
            let c_span = raw_c.min(cols);
            let r_span = raw_r;

            let (mut found_r, mut found_c) = (0usize, 0usize);
            'outer: for r in 0..(occ.len() - r_span) {
                for c in 0..=(cols - c_span) {
                    let mut ok = true;
                    for dr in 0..r_span {
                        for dc in 0..c_span {
                            if occ[r + dr][c + dc] {
                                ok = false;
                                break;
                            }
                        }
                        if !ok {
                            break;
                        }
                    }
                    if ok {
                        found_r = r;
                        found_c = c;
                        break 'outer;
                    }
                }
            }
            for dr in 0..r_span {
                for dc in 0..c_span {
                    occ[found_r + dr][found_c + dc] = true;
                }
            }

            let rx = grid_x + (found_c as i32) * cell_w + 3;
            let ry = grid_y + (found_r as i32) * unit_h + 3;
            let rw = (c_span as i32) * cell_w - 6;
            let rh = (r_span as i32) * unit_h - 6;
            let rect = Rect { x: rx, y: ry, w: rw, h: rh };

            let scaled_icon = if c_span == 2 && r_span == 2 {
                ((icon_sz as f32 * 1.45) as i32).min(rw.min(rh) - 24)
            } else if c_span > 1 || r_span > 1 {
                ((icon_sz as f32 * 1.12) as i32).min(rh - 14)
            } else {
                icon_sz
            };

            let icon_rect = if c_span == 2 && r_span == 1 {
                Rect {
                    x: rx + 12,
                    y: ry + (rh - scaled_icon) / 2,
                    w: scaled_icon,
                    h: scaled_icon,
                }
            } else {
                let top_pad = if self.show_labels { 6 } else { (rh - scaled_icon) / 2 };
                Rect {
                    x: rx + (rw - scaled_icon) / 2,
                    y: ry + top_pad,
                    w: scaled_icon,
                    h: scaled_icon,
                }
            };

            out.push(PlacedTile {
                app_idx: idx,
                rect,
                icon_rect,
                c_span,
                r_span,
            });
        }
        out
    }

    pub fn apply_action(&mut self, action: HitAction) {
        match action {
            HitAction::OpenApp(kind) => {
                self.prev_screen = Screen::Home;
                if kind == AppKind::IconStyle {
                    self.screen = Screen::IconEditor;
                } else {
                    self.audit_scroll = 0;
                    self.screen = Screen::App(kind);
                }
            }
            HitAction::OpenIconMenu(idx) => {
                if idx < self.apps.len() {
                    self.screen = Screen::TileMenu(idx);
                }
            }
            HitAction::SetTileSpan(idx, span) => {
                if let Some(a) = self.apps.get_mut(idx) {
                    a.span = span;
                    let name = a.title.clone();
                    self.screen = Screen::Home;
                    self.show_toast(&format!("{}: kafelek {}", name, span.label()));
                }
            }
            HitAction::GoScreen(s) => {
                self.screen = s;
            }
            HitAction::Back => {
                self.screen = match self.screen {
                    Screen::BootAnim => Screen::LockScreen,
                    Screen::LockScreen => Screen::LockScreen,
                    Screen::Home => Screen::Home,
                    Screen::TileMenu(_) | Screen::IconEditor | Screen::ControlCenter | Screen::App(_) => Screen::Home,
                };
            }
            HitAction::Home => {
                if self.screen != Screen::BootAnim && self.screen != Screen::LockScreen {
                    self.screen = Screen::Home;
                } else if self.screen == Screen::LockScreen {
                    self.screen = Screen::Home;
                }
            }
            HitAction::LockToggle => {
                self.screen = if self.screen == Screen::LockScreen {
                    Screen::Home
                } else {
                    Screen::LockScreen
                };
            }
            HitAction::RestartBoot => {
                self.boot_ticks = 0;
                self.screen = Screen::BootAnim;
            }
            HitAction::SetIconScale(v) => {
                self.icon_scale = v.clamp(60, 150);
            }
            HitAction::SetShape(sh) => {
                self.icon_shape = sh;
                self.show_toast(&format!("Ksztalt: {}", sh.name()));
            }
            HitAction::SetGridCols(c) => {
                self.grid_cols = if c == 5 { 5 } else { 4 };
                self.show_toast(&format!("Siatka: {} kolumn", self.grid_cols));
            }
            HitAction::ToggleLabels => {
                self.show_labels = !self.show_labels;
            }
            HitAction::SetWallpaper(idx) => {
                self.wallpaper_idx = idx % 4;
            }
            HitAction::ResetTiles => {
                for a in &mut self.apps {
                    a.span = TileSpan::S1x1;
                }
                if let Some(first) = self.apps.get_mut(0) {
                    first.span = TileSpan::S2x1;
                }
                self.icon_scale = 100;
                self.icon_shape = IconShape::Squircle;
                self.show_labels = true;
                self.show_toast("Przywrocono domyslny uklad MysticalOS");
            }
            HitAction::ToggleDark => self.dark_mode = !self.dark_mode,
            HitAction::ToggleWifi => self.wifi_on = !self.wifi_on,
            HitAction::ToggleBt => self.bt_on = !self.bt_on,
            HitAction::ToggleFlashlight => self.flashlight_on = !self.flashlight_on,
            HitAction::ToggleNavGestures => self.gesture_nav = !self.gesture_nav,
            HitAction::ToggleRamVariant => self.ram_3gb = !self.ram_3gb,
            HitAction::ScrollAudit(delta) => {
                self.audit_scroll = (self.audit_scroll + delta).clamp(0, 600);
            }
            HitAction::CameraShutter => {
                self.camera_shots += 1;
                self.camera_flash_ticks = 6;
                self.show_toast(&format!("Zdjecie #{} (Fossify Camera)", self.camera_shots));
            }
            HitAction::CalcKey(ch) => self.handle_calc(ch),
            HitAction::ExplorerSelectPartIdx(idx) => {
                let pname = self
                    .loaded_image
                    .as_ref()
                    .and_then(|img| img.partitions.get(idx))
                    .map(|p| p.name.clone());
                if let Some(name) = pname {
                    self.explorer_part = name;
                    self.explorer_dir = "/".into();
                    self.explorer_file_preview = None;
                    self.audit_scroll = 0;
                    self.refresh_explorer();
                }
            }
            HitAction::ExplorerOpenEntry(idx) => {
                if let Some(ent) = self.explorer_entries.get(idx).cloned() {
                    let base = if self.explorer_dir == "/" {
                        String::new()
                    } else {
                        self.explorer_dir.clone()
                    };
                    let next_path = format!("{}/{}", base, ent.name);
                    if ent.is_dir {
                        self.explorer_dir = next_path;
                        self.explorer_file_preview = None;
                        self.audit_scroll = 0;
                        self.refresh_explorer();
                    } else if let Some(img_path) = self.loaded_image.as_ref().map(|i| i.file_path.clone()) {
                        let p = Path::new(&img_path);
                        let preview = match read_text_in_image(p, &self.explorer_part, &next_path, 8192) {
                            Ok(txt) => {
                                let clean: String = txt
                                    .chars()
                                    .map(|c| if c == '\n' || c == '\t' || (c >= ' ' && c <= '~') { c } else { '.' })
                                    .take(2200)
                                    .collect();
                                clean
                            }
                            Err(e) => format!("Blad odczytu pliku: {}", e),
                        };
                        self.explorer_file_preview = Some((next_path, preview));
                        self.audit_scroll = 0;
                    }
                }
            }
            HitAction::ExplorerUpDir => {
                self.explorer_file_preview = None;
                self.audit_scroll = 0;
                if self.explorer_dir != "/" {
                    if let Some(pos) = self.explorer_dir.rfind('/') {
                        self.explorer_dir = if pos == 0 {
                            "/".into()
                        } else {
                            self.explorer_dir[..pos].to_string()
                        };
                    } else {
                        self.explorer_dir = "/".into();
                    }
                    self.refresh_explorer();
                }
            }
            HitAction::ExplorerClosePreview => {
                self.explorer_file_preview = None;
                self.audit_scroll = 0;
            }
            HitAction::DragIconSlider(_)
            | HitAction::DragBrightnessSlider(_)
            | HitAction::SaveScreenshot
            | HitAction::OpenImageDialog
            | HitAction::ExtractSystemImg => {}
        }
    }

    fn handle_calc(&mut self, ch: char) {
        match ch {
            'C' => {
                self.calc_display = "0".into();
                self.calc_acc = 0.0;
                self.calc_op = None;
                self.calc_fresh = true;
            }
            '0'..='9' | '.' => {
                if self.calc_fresh {
                    self.calc_display = if ch == '.' { "0.".into() } else { ch.to_string() };
                    self.calc_fresh = false;
                } else if ch != '.' || !self.calc_display.contains('.') {
                    if self.calc_display == "0" && ch != '.' {
                        self.calc_display.clear();
                    }
                    if self.calc_display.len() < 12 {
                        self.calc_display.push(ch);
                    }
                }
            }
            '+' | '-' | '*' | '/' => {
                self.eval_pending();
                self.calc_op = Some(ch);
                self.calc_fresh = true;
            }
            '=' => {
                self.eval_pending();
                self.calc_op = None;
                self.calc_fresh = true;
            }
            _ => {}
        }
    }

    fn eval_pending(&mut self) {
        let cur: f64 = self.calc_display.parse().unwrap_or(0.0);
        let res = match self.calc_op {
            Some('+') => self.calc_acc + cur,
            Some('-') => self.calc_acc - cur,
            Some('*') => self.calc_acc * cur,
            Some('/') => {
                if cur.abs() < 1e-12 {
                    self.calc_display = "Blad".into();
                    self.calc_acc = 0.0;
                    return;
                }
                self.calc_acc / cur
            }
            _ => cur,
        };
        self.calc_acc = res;
        let s = if (res - res.round()).abs() < 1e-9 && res.abs() < 1e12 {
            format!("{}", res.round() as i64)
        } else {
            format!("{:.4}", res).trim_end_matches('0').trim_end_matches('.').to_string()
        };
        self.calc_display = s;
    }

    pub fn render(&mut self, fb: &mut [u32], width: i32, height: i32) -> Vec<TextDraw> {
        self.hits.clear();
        let mut texts: Vec<TextDraw> = Vec::new();

        // 1. Desktop window dark studio backdrop
        fill_gradient_v(fb, width, height, 0, 0, width, height, 0x0B0F1A, 0x13192B);

        // 2. Redmi 9C outer chassis + waterdrop frame
        fill_round_rect(fb, width, height, PHONE_FRAME_X, PHONE_FRAME_Y, PHONE_FRAME_W, PHONE_FRAME_H, 28, 0x1A1F2E);
        draw_round_border(fb, width, height, PHONE_FRAME_X, PHONE_FRAME_Y, PHONE_FRAME_W, PHONE_FRAME_H, 28, 0x3D4966);
        // Side hardware buttons (Volume & Power)
        fill_rect(fb, width, height, PHONE_FRAME_X + PHONE_FRAME_W, PHONE_FRAME_Y + 150, 4, 72, 0x4C5978);
        fill_rect(fb, width, height, PHONE_FRAME_X + PHONE_FRAME_W, PHONE_FRAME_Y + 245, 4, 48, 0x6277A8);
        self.hits.push(HitRegion {
            rect: Rect { x: PHONE_FRAME_X + PHONE_FRAME_W - 2, y: PHONE_FRAME_Y + 240, w: 12, h: 58 },
            action: HitAction::LockToggle,
            long_press_app: None,
        });

        // 3. Render phone screen contents
        self.render_phone_screen(fb, width, height, &mut texts);

        // Waterdrop notch on top of screen
        let notch_cx = SCR_X + SCR_W / 2;
        fill_circle(fb, width, height, notch_cx, SCR_Y + 11, 8, 0x090B12);
        fill_circle(fb, width, height, notch_cx, SCR_Y + 11, 3, 0x1B2742);

        // 4. Right-hand PC Control & Inspector Panel
        self.render_pc_panel(fb, width, height, &mut texts);

        texts
    }

    fn render_phone_screen(&mut self, fb: &mut [u32], w: i32, h: i32, texts: &mut Vec<TextDraw>) {
        // Wallpaper / background
        let (wc1, wc2) = match self.wallpaper_idx {
            1 => (0x081C24, 0x105666),
            2 => (0x240E22, 0x7A1E58),
            3 => (0x0E121C, 0x24345C),
            _ => (0x0E0A26, 0x3B238C),
        };
        fill_gradient_v(fb, w, h, SCR_X, SCR_Y, SCR_W, SCR_H, wc1, wc2);
        add_radial_glow(fb, w, h, SCR_X + 90, SCR_Y + 220, 180, if self.wallpaper_idx == 1 { 0x00D2B4 } else { 0x00D6FF }, 45);
        add_radial_glow(fb, w, h, SCR_X + 290, SCR_Y + 560, 170, 0x7251FF, 40);

        match self.screen {
            Screen::BootAnim => self.render_boot(fb, w, h, texts),
            Screen::LockScreen => self.render_lockscreen(fb, w, h, texts),
            Screen::Home => self.render_home(fb, w, h, texts),
            Screen::IconEditor => {
                self.render_home_bg_only(fb, w, h, texts);
                self.render_icon_editor(fb, w, h, texts);
            }
            Screen::ControlCenter => {
                self.render_home_bg_only(fb, w, h, texts);
                self.render_control_center(fb, w, h, texts);
            }
            Screen::TileMenu(idx) => {
                self.render_home(fb, w, h, texts);
                self.render_tile_menu(fb, w, h, idx, texts);
            }
            Screen::App(kind) => self.render_app_screen(fb, w, h, kind, texts),
        }

        // Flashlight screen tint simulation
        if self.flashlight_on && self.screen != Screen::BootAnim {
            add_radial_glow(fb, w, h, SCR_X + SCR_W / 2, SCR_Y + 100, 160, 0xFFF5CC, 50);
        }

        // Brightness dimming overlay
        if self.brightness < 100 {
            let dim = (((100 - self.brightness) as u32) * 180) / 100;
            blend_rect(fb, w, h, SCR_X, SCR_Y, SCR_W, SCR_H, 0x000000, dim);
        }

        // Status bar & navigation bar (except during bootanim)
        if self.screen != Screen::BootAnim {
            self.render_status_and_nav(fb, w, h, texts);
        }

        // Toast pill
        if let Some((msg, _)) = &self.toast {
            let tr = Rect { x: SCR_X + 36, y: SCR_Y + SCR_H - 96, w: SCR_W - 72, h: 32 };
            fill_round_rect_alpha(fb, w, h, tr.x, tr.y, tr.w, tr.h, 16, 0x101526, 225);
            draw_round_border(fb, w, h, tr.x, tr.y, tr.w, tr.h, 16, 0x00D6FF);
            texts.push(TextDraw {
                rect: tr,
                text: msg.clone(),
                color: 0xFFFFFF,
                size: 13,
                bold: false,
                align: TextAlign::Center,
                clip_to_screen: true,
            });
        }
    }

    fn render_boot(&mut self, fb: &mut [u32], w: i32, h: i32, texts: &mut Vec<TextDraw>) {
        if let Some(img) = &self.loaded_image {
            if !img.boot_frames.is_empty() {
                let frame_idx = (self.boot_ticks as usize) % img.boot_frames.len();
                let bf = &img.boot_frames[frame_idx];
                if bf.w > 0 && bf.h > 0 && bf.pixels.len() >= (bf.w * bf.h) as usize {
                    for dy in 0..SCR_H {
                        let sy = ((dy as u64 * bf.h as u64) / SCR_H as u64).min((bf.h - 1) as u64) as usize;
                        let dst_row = ((SCR_Y + dy) * w) as usize;
                        let src_row = sy * (bf.w as usize);
                        for dx in 0..SCR_W {
                            let sx = ((dx as u64 * bf.w as u64) / SCR_W as u64).min((bf.w - 1) as u64) as usize;
                            fb[dst_row + (SCR_X + dx) as usize] = bf.pixels[src_row + sx];
                        }
                    }
                    texts.push(TextDraw {
                        rect: Rect { x: SCR_X + 16, y: SCR_Y + 36, w: SCR_W - 32, h: 22 },
                        text: format!("BOOTANIMATION.ZIP Z {} (klatka {}/{})", img.container_kind, frame_idx + 1, img.boot_frames.len()),
                        color: 0x00E0FF,
                        size: 10,
                        bold: true,
                        align: TextAlign::Center,
                        clip_to_screen: true,
                    });
                    let skip = Rect { x: SCR_X + 115, y: SCR_Y + SCR_H - 72, w: 130, h: 32 };
                    fill_round_rect_alpha(fb, w, h, skip.x, skip.y, skip.w, skip.h, 16, 0x202742, 200);
                    texts.push(TextDraw {
                        rect: skip,
                        text: "Pomin start >".into(),
                        color: 0xC8D4F5,
                        size: 13,
                        bold: false,
                        align: TextAlign::Center,
                        clip_to_screen: true,
                    });
                    self.hits.push(HitRegion {
                        rect: skip,
                        action: HitAction::GoScreen(Screen::LockScreen),
                        long_press_app: None,
                    });
                    return;
                }
            }
        }
        fill_gradient_v(fb, w, h, SCR_X, SCR_Y, SCR_W, SCR_H, 0x050710, 0x0F1426);
        let cx = SCR_X + SCR_W / 2;
        let cy = SCR_Y + SCR_H * 44 / 100;
        let phase = (self.boot_ticks as f32) * 0.08;
        let ring_r = 76.0 + 4.0 * phase.sin();
        draw_glow_ring(fb, w, h, cx, cy, ring_r, 0x00D6FF, 0x6C4DF5);
        draw_diamond(fb, w, h, cx, cy, 46, 0x6640F5);
        draw_diamond(fb, w, h, cx, cy, 24, 0x12E1FF);

        texts.push(TextDraw {
            rect: Rect { x: SCR_X + 20, y: cy + 106, w: SCR_W - 40, h: 36 },
            text: "MYSTICAL OS".into(),
            color: 0xF4F8FF,
            size: 26,
            bold: true,
            align: TextAlign::Center,
            clip_to_screen: true,
        });
        texts.push(TextDraw {
            rect: Rect { x: SCR_X + 20, y: cy + 144, w: SCR_W - 40, h: 24 },
            text: "ANDROID 17 · FLUX17 · BLOSSOM".into(),
            color: 0x00E0FF,
            size: 12,
            bold: true,
            align: TextAlign::Center,
            clip_to_screen: true,
        });
        let skip = Rect { x: SCR_X + 115, y: SCR_Y + SCR_H - 72, w: 130, h: 32 };
        fill_round_rect_alpha(fb, w, h, skip.x, skip.y, skip.w, skip.h, 16, 0x202742, 200);
        texts.push(TextDraw {
            rect: skip,
            text: "Pomin start >".into(),
            color: 0xC8D4F5,
            size: 13,
            bold: false,
            align: TextAlign::Center,
            clip_to_screen: true,
        });
        self.hits.push(HitRegion {
            rect: skip,
            action: HitAction::GoScreen(Screen::LockScreen),
            long_press_app: None,
        });
    }

    fn render_lockscreen(&mut self, fb: &mut [u32], w: i32, h: i32, texts: &mut Vec<TextDraw>) {
        let time_s = format!("{:02}:{:02}", self.clock_hh, self.clock_mm);
        texts.push(TextDraw {
            rect: Rect { x: SCR_X + 20, y: SCR_Y + 95, w: SCR_W - 40, h: 74 },
            text: time_s,
            color: 0xFFFFFF,
            size: 64,
            bold: true,
            align: TextAlign::Center,
            clip_to_screen: true,
        });
        texts.push(TextDraw {
            rect: Rect { x: SCR_X + 20, y: SCR_Y + 172, w: SCR_W - 40, h: 26 },
            text: format!("{} · MysticalOS 1.0", self.date_str),
            color: 0xCBD8FF,
            size: 15,
            bold: false,
            align: TextAlign::Center,
            clip_to_screen: true,
        });

        // Lock screen Flux card
        let notif = Rect { x: SCR_X + 24, y: SCR_Y + 248, w: SCR_W - 48, h: 74 };
        fill_round_rect_alpha(fb, w, h, notif.x, notif.y, notif.w, notif.h, 18, 0x161B32, 190);
        draw_round_border(fb, w, h, notif.x, notif.y, notif.w, notif.h, 18, 0x4A63B8);
        texts.push(TextDraw {
            rect: Rect { x: notif.x + 14, y: notif.y + 12, w: notif.w - 28, h: 22 },
            text: "MysticalOS · Zero apek Xiaomi".into(),
            color: 0x00E0FF,
            size: 13,
            bold: true,
            align: TextAlign::Left,
            clip_to_screen: true,
        });
        texts.push(TextDraw {
            rect: Rect { x: notif.x + 14, y: notif.y + 36, w: notif.w - 28, h: 24 },
            text: format!("Usunieto {} pakietow bloat · r9c-memd OK", self.manifest.removed_count),
            color: 0xDDE5F8,
            size: 12,
            bold: false,
            align: TextAlign::Left,
            clip_to_screen: true,
        });

        let unlock_btn = Rect { x: SCR_X + 66, y: SCR_Y + SCR_H - 115, w: SCR_W - 132, h: 46 };
        fill_round_rect_alpha(fb, w, h, unlock_btn.x, unlock_btn.y, unlock_btn.w, unlock_btn.h, 23, 0x5B3CF5, 225);
        draw_round_border(fb, w, h, unlock_btn.x, unlock_btn.y, unlock_btn.w, unlock_btn.h, 23, 0x00D6FF);
        texts.push(TextDraw {
            rect: unlock_btn,
            text: "Odblokuj pulpit".into(),
            color: 0xFFFFFF,
            size: 15,
            bold: true,
            align: TextAlign::Center,
            clip_to_screen: true,
        });
        self.hits.push(HitRegion {
            rect: unlock_btn,
            action: HitAction::GoScreen(Screen::Home),
            long_press_app: None,
        });
    }

    fn render_home_bg_only(&self, fb: &mut [u32], w: i32, h: i32, texts: &mut Vec<TextDraw>) {
        // Header card
        let hdr = Rect { x: SCR_X + 12, y: SCR_Y + STATUS_H + 8, w: SCR_W - 24, h: 88 };
        fill_round_rect_alpha(fb, w, h, hdr.x, hdr.y, hdr.w, hdr.h, 20, 0x151A32, 205);
        draw_round_border(fb, w, h, hdr.x, hdr.y, hdr.w, hdr.h, 20, 0x45589E);

        let time_s = format!("{:02}:{:02}", self.clock_hh, self.clock_mm);
        texts.push(TextDraw {
            rect: Rect { x: hdr.x + 14, y: hdr.y + 10, w: 120, h: 34 },
            text: time_s,
            color: 0xFFFFFF,
            size: 28,
            bold: true,
            align: TextAlign::Left,
            clip_to_screen: true,
        });
        texts.push(TextDraw {
            rect: Rect { x: hdr.x + 14, y: hdr.y + 44, w: 185, h: 18 },
            text: format!("MysticalOS 1.0 · {}", self.date_str),
            color: 0xB8C7F0,
            size: 11,
            bold: false,
            align: TextAlign::Left,
            clip_to_screen: true,
        });
        let total_ram = if self.ram_3gb { 3072 } else { 2048 };
        let free_ram = if self.ram_3gb { 1640 } else { 980 };
        texts.push(TextDraw {
            rect: Rect { x: hdr.x + 14, y: hdr.y + 62, w: hdr.w - 28, h: 18 },
            text: format!("RAM {}/{} MiB wolne · Ikony {}% ({})", free_ram, total_ram, self.icon_scale, self.icon_shape.name()),
            color: 0x62F0B8,
            size: 11,
            bold: false,
            align: TextAlign::Left,
            clip_to_screen: true,
        });
    }

    fn render_home(&mut self, fb: &mut [u32], w: i32, h: i32, texts: &mut Vec<TextDraw>) {
        self.render_home_bg_only(fb, w, h, texts);

        // Quick pill button on header to open ColorOS 17 Icon Resizer
        let style_pill = Rect { x: SCR_X + SCR_W - 156, y: SCR_Y + STATUS_H + 22, w: 132, h: 30 };
        fill_gradient_h(fb, w, h, style_pill.x, style_pill.y, style_pill.w, style_pill.h, 0x5B3CF5, 0x00AEE0);
        round_mask_in_place(fb, w, h, style_pill, 15);
        texts.push(TextDraw {
            rect: style_pill,
            text: "Ikony ColorOS 17".into(),
            color: 0xFFFFFF,
            size: 12,
            bold: true,
            align: TextAlign::Center,
            clip_to_screen: true,
        });
        self.hits.push(HitRegion {
            rect: style_pill,
            action: HitAction::GoScreen(Screen::IconEditor),
            long_press_app: None,
        });

        let tiles = self.compute_grid();
        let max_y = SCR_Y + SCR_H - NAV_H - 76;

        for pt in tiles {
            if pt.rect.y + pt.rect.h > max_y {
                continue;
            }
            let app = self.apps[pt.app_idx].clone();
            let is_large = pt.c_span > 1 || pt.r_span > 1;
            if is_large {
                fill_round_rect_alpha(fb, w, h, pt.rect.x, pt.rect.y, pt.rect.w, pt.rect.h, 16, 0x1D2442, 200);
                draw_round_border(fb, w, h, pt.rect.x, pt.rect.y, pt.rect.w, pt.rect.h, 16, 0x00C8FF);
            }

            draw_shaped_app_icon(fb, w, h, pt.icon_rect, app.color1, app.color2, self.icon_shape);
            texts.push(TextDraw {
                rect: pt.icon_rect,
                text: app.glyph.into(),
                color: 0xFFFFFF,
                size: (pt.icon_rect.h / 3).clamp(10, 22),
                bold: true,
                align: TextAlign::Center,
                clip_to_screen: true,
            });

            if self.show_labels || is_large {
                let lbl_rect = if pt.c_span == 2 && pt.r_span == 1 {
                    Rect {
                        x: pt.icon_rect.x + pt.icon_rect.w + 8,
                        y: pt.rect.y + 4,
                        w: pt.rect.w - pt.icon_rect.w - 24,
                        h: pt.rect.h - 8,
                    }
                } else {
                    Rect {
                        x: pt.rect.x + 2,
                        y: pt.icon_rect.y + pt.icon_rect.h + 2,
                        w: pt.rect.w - 4,
                        h: 18,
                    }
                };
                texts.push(TextDraw {
                    rect: lbl_rect,
                    text: app.title.clone(),
                    color: 0xFFFFFF,
                    size: if is_large { 12 } else { 11 },
                    bold: is_large,
                    align: if pt.c_span == 2 && pt.r_span == 1 { TextAlign::Left } else { TextAlign::Center },
                    clip_to_screen: true,
                });
            }

            self.hits.push(HitRegion {
                rect: pt.rect,
                action: HitAction::OpenApp(app.kind),
                long_press_app: Some(pt.app_idx),
            });
        }

        // Bottom Dock
        let dock = Rect { x: SCR_X + 14, y: SCR_Y + SCR_H - NAV_H - 68, w: SCR_W - 28, h: 60 };
        fill_round_rect_alpha(fb, w, h, dock.x, dock.y, dock.w, dock.h, 22, 0x13182E, 215);
        draw_round_border(fb, w, h, dock.x, dock.y, dock.w, dock.h, 22, 0x4A60A8);

        let dock_indices = [3usize, 4, 5, 11]; // Telefon, Wiadomosci, Aparat, Droid-ify
        let slot_w = dock.w / 4;
        let dock_icon_sz = ((38 * self.icon_scale) / 100).clamp(24, 48);
        for (i, &app_idx) in dock_indices.iter().enumerate() {
            if let Some(app) = self.apps.get(app_idx) {
                let sx = dock.x + (i as i32) * slot_w;
                let ir = Rect {
                    x: sx + (slot_w - dock_icon_sz) / 2,
                    y: dock.y + (dock.h - dock_icon_sz) / 2,
                    w: dock_icon_sz,
                    h: dock_icon_sz,
                };
                draw_shaped_app_icon(fb, w, h, ir, app.color1, app.color2, self.icon_shape);
                texts.push(TextDraw {
                    rect: ir,
                    text: app.glyph.into(),
                    color: 0xFFFFFF,
                    size: (dock_icon_sz / 3).clamp(10, 16),
                    bold: true,
                    align: TextAlign::Center,
                    clip_to_screen: true,
                });
                self.hits.push(HitRegion {
                    rect: Rect { x: sx, y: dock.y, w: slot_w, h: dock.h },
                    action: HitAction::OpenApp(app.kind),
                    long_press_app: Some(app_idx),
                });
            }
        }
    }

    fn render_tile_menu(&mut self, fb: &mut [u32], w: i32, h: i32, idx: usize, texts: &mut Vec<TextDraw>) {
        blend_rect(fb, w, h, SCR_X, SCR_Y, SCR_W, SCR_H, 0x04060E, 175);
        let card = Rect { x: SCR_X + 26, y: SCR_Y + 210, w: SCR_W - 52, h: 315 };
        fill_round_rect(fb, w, h, card.x, card.y, card.w, card.h, 22, 0x181F38);
        draw_round_border(fb, w, h, card.x, card.y, card.w, card.h, 22, 0x00D6FF);

        let app = self.apps[idx].clone();
        texts.push(TextDraw {
            rect: Rect { x: card.x + 16, y: card.y + 14, w: card.w - 32, h: 24 },
            text: format!("{} · ColorOS 17", app.title),
            color: 0xFFFFFF,
            size: 16,
            bold: true,
            align: TextAlign::Center,
            clip_to_screen: true,
        });
        texts.push(TextDraw {
            rect: Rect { x: card.x + 16, y: card.y + 40, w: card.w - 32, h: 18 },
            text: "Wybierz rozmiar kafelka tej aplikacji:".into(),
            color: 0x9EB0E0,
            size: 12,
            bold: false,
            align: TextAlign::Center,
            clip_to_screen: true,
        });

        let spans = [TileSpan::S1x1, TileSpan::S2x1, TileSpan::S1x2, TileSpan::S2x2];
        let bw = (card.w - 48) / 2;
        for (i, sp) in spans.iter().enumerate() {
            let bx = card.x + 18 + (i as i32 % 2) * (bw + 12);
            let by = card.y + 68 + (i as i32 / 2) * 48;
            let br = Rect { x: bx, y: by, w: bw, h: 40 };
            let active = app.span == *sp;
            fill_round_rect(fb, w, h, br.x, br.y, br.w, br.h, 12, if active { 0x5B3CF5 } else { 0x263054 });
            if active {
                draw_round_border(fb, w, h, br.x, br.y, br.w, br.h, 12, 0x00E0FF);
            }
            texts.push(TextDraw {
                rect: br,
                text: format!("Kafelek {}", sp.label()),
                color: 0xFFFFFF,
                size: 13,
                bold: active,
                align: TextAlign::Center,
                clip_to_screen: true,
            });
            self.hits.push(HitRegion {
                rect: br,
                action: HitAction::SetTileSpan(idx, *sp),
                long_press_app: None,
            });
        }

        let ed_btn = Rect { x: card.x + 18, y: card.y + 174, w: card.w - 36, h: 38 };
        fill_round_rect(fb, w, h, ed_btn.x, ed_btn.y, ed_btn.w, ed_btn.h, 12, 0x1D5E7A);
        texts.push(TextDraw {
            rect: ed_btn,
            text: "Suwak rozmiaru wszystkich ikon...".into(),
            color: 0xFFFFFF,
            size: 13,
            bold: true,
            align: TextAlign::Center,
            clip_to_screen: true,
        });
        self.hits.push(HitRegion {
            rect: ed_btn,
            action: HitAction::GoScreen(Screen::IconEditor),
            long_press_app: None,
        });

        let open_btn = Rect { x: card.x + 18, y: card.y + 220, w: card.w - 36, h: 38 };
        fill_round_rect(fb, w, h, open_btn.x, open_btn.y, open_btn.w, open_btn.h, 12, 0x2A3458);
        texts.push(TextDraw {
            rect: open_btn,
            text: "Otworz aplikacje".into(),
            color: 0xFFFFFF,
            size: 13,
            bold: false,
            align: TextAlign::Center,
            clip_to_screen: true,
        });
        self.hits.push(HitRegion {
            rect: open_btn,
            action: HitAction::OpenApp(app.kind),
            long_press_app: None,
        });

        let close_btn = Rect { x: card.x + 18, y: card.y + 266, w: card.w - 36, h: 34 };
        fill_round_rect(fb, w, h, close_btn.x, close_btn.y, close_btn.w, close_btn.h, 12, 0x111629);
        texts.push(TextDraw {
            rect: close_btn,
            text: "Anuluj".into(),
            color: 0x9AA9D0,
            size: 13,
            bold: false,
            align: TextAlign::Center,
            clip_to_screen: true,
        });
        self.hits.push(HitRegion {
            rect: close_btn,
            action: HitAction::GoScreen(Screen::Home),
            long_press_app: None,
        });
    }

    fn render_icon_editor(&mut self, fb: &mut [u32], w: i32, h: i32, texts: &mut Vec<TextDraw>) {
        // Live icon preview strip above bottom sheet
        let prev_box = Rect { x: SCR_X + 16, y: SCR_Y + 132, w: SCR_W - 32, h: 112 };
        fill_round_rect_alpha(fb, w, h, prev_box.x, prev_box.y, prev_box.w, prev_box.h, 18, 0x101528, 225);
        draw_round_border(fb, w, h, prev_box.x, prev_box.y, prev_box.w, prev_box.h, 18, 0x00C8FF);
        texts.push(TextDraw {
            rect: Rect { x: prev_box.x + 10, y: prev_box.y + 6, w: prev_box.w - 20, h: 16 },
            text: format!("PODGLAD NA ZYWO ({}% · {})", self.icon_scale, self.icon_shape.name()),
            color: 0x00E0FF,
            size: 11,
            bold: true,
            align: TextAlign::Center,
            clip_to_screen: true,
        });
        let p_sz = ((42 * self.icon_scale) / 100).clamp(24, 64);
        for i in 0..4 {
            let app = &self.apps[i];
            let slot_w = prev_box.w / 4;
            let ix = prev_box.x + (i as i32) * slot_w + (slot_w - p_sz) / 2;
            let iy = prev_box.y + 24 + (62 - p_sz) / 2;
            let ir = Rect { x: ix, y: iy, w: p_sz, h: p_sz };
            draw_shaped_app_icon(fb, w, h, ir, app.color1, app.color2, self.icon_shape);
            texts.push(TextDraw {
                rect: ir,
                text: app.glyph.into(),
                color: 0xFFFFFF,
                size: (p_sz / 3).clamp(9, 18),
                bold: true,
                align: TextAlign::Center,
                clip_to_screen: true,
            });
            if self.show_labels {
                texts.push(TextDraw {
                    rect: Rect { x: prev_box.x + (i as i32) * slot_w + 2, y: prev_box.y + 88, w: slot_w - 4, h: 16 },
                    text: app.title.clone(),
                    color: 0xFFFFFF,
                    size: 10,
                    bold: false,
                    align: TextAlign::Center,
                    clip_to_screen: true,
                });
            }
        }

        // Bottom Sheet ColorOS 17 Customizer
        let sheet = Rect { x: SCR_X, y: SCR_Y + 256, w: SCR_W, h: SCR_H - 256 - NAV_H };
        fill_round_rect(fb, w, h, sheet.x, sheet.y, sheet.w, sheet.h + 24, 24, 0x14192D);
        draw_round_border(fb, w, h, sheet.x, sheet.y, sheet.w, sheet.h + 24, 24, 0x3F4F8A);

        texts.push(TextDraw {
            rect: Rect { x: sheet.x + 16, y: sheet.y + 12, w: sheet.w - 32, h: 24 },
            text: "Ikony ColorOS 17 · Personalizacja".into(),
            color: 0xFFFFFF,
            size: 16,
            bold: true,
            align: TextAlign::Left,
            clip_to_screen: true,
        });

        // Slider row
        texts.push(TextDraw {
            rect: Rect { x: sheet.x + 16, y: sheet.y + 46, w: 200, h: 20 },
            text: "Rozmiar ikon aplikacji:".into(),
            color: 0xDCE5FF,
            size: 13,
            bold: false,
            align: TextAlign::Left,
            clip_to_screen: true,
        });
        texts.push(TextDraw {
            rect: Rect { x: sheet.x + sheet.w - 90, y: sheet.y + 46, w: 74, h: 20 },
            text: format!("{}%", self.icon_scale),
            color: 0x00E0FF,
            size: 14,
            bold: true,
            align: TextAlign::Right,
            clip_to_screen: true,
        });

        let track = Rect { x: sheet.x + 20, y: sheet.y + 74, w: sheet.w - 40, h: 28 };
        draw_slider(fb, w, h, track, (self.icon_scale - 60) as f32 / 90.0, 0x00D6FF);
        self.hits.push(HitRegion {
            rect: track,
            action: HitAction::DragIconSlider(track),
            long_press_app: None,
        });

        // Shape row
        texts.push(TextDraw {
            rect: Rect { x: sheet.x + 16, y: sheet.y + 114, w: sheet.w - 32, h: 18 },
            text: "Ksztalt ikon:".into(),
            color: 0xDCE5FF,
            size: 12,
            bold: false,
            align: TextAlign::Left,
            clip_to_screen: true,
        });
        let shapes = [IconShape::Squircle, IconShape::Circle, IconShape::Rounded, IconShape::Teardrop];
        let sw = (sheet.w - 44) / 4;
        for (i, sh) in shapes.iter().enumerate() {
            let br = Rect { x: sheet.x + 16 + (i as i32) * (sw + 4), y: sheet.y + 136, w: sw, h: 34 };
            let act = self.icon_shape == *sh;
            fill_round_rect(fb, w, h, br.x, br.y, br.w, br.h, 10, if act { 0x5B3CF5 } else { 0x242C4A });
            if act {
                draw_round_border(fb, w, h, br.x, br.y, br.w, br.h, 10, 0x00E0FF);
            }
            texts.push(TextDraw {
                rect: br,
                text: sh.name().into(),
                color: 0xFFFFFF,
                size: 11,
                bold: act,
                align: TextAlign::Center,
                clip_to_screen: true,
            });
            self.hits.push(HitRegion {
                rect: br,
                action: HitAction::SetShape(*sh),
                long_press_app: None,
            });
        }

        // Grid + Labels
        let g4 = Rect { x: sheet.x + 16, y: sheet.y + 186, w: 100, h: 34 };
        let g5 = Rect { x: sheet.x + 122, y: sheet.y + 186, w: 100, h: 34 };
        let lbl_btn = Rect { x: sheet.x + 228, y: sheet.y + 186, w: sheet.w - 244, h: 34 };
        for (r, txt, act, ac) in [
            (g4, "Siatka 4x", self.grid_cols == 4, HitAction::SetGridCols(4)),
            (g5, "Siatka 5x", self.grid_cols == 5, HitAction::SetGridCols(5)),
            (lbl_btn, if self.show_labels { "Podpisy: WL" } else { "Podpisy: WYL" }, self.show_labels, HitAction::ToggleLabels),
        ] {
            fill_round_rect(fb, w, h, r.x, r.y, r.w, r.h, 10, if act { 0x1E658C } else { 0x242C4A });
            texts.push(TextDraw {
                rect: r,
                text: txt.into(),
                color: 0xFFFFFF,
                size: 11,
                bold: act,
                align: TextAlign::Center,
                clip_to_screen: true,
            });
            self.hits.push(HitRegion { rect: r, action: ac, long_press_app: None });
        }

        // Wallpapers
        texts.push(TextDraw {
            rect: Rect { x: sheet.x + 16, y: sheet.y + 234, w: sheet.w - 32, h: 18 },
            text: "Tapeta MysticalOS Flux:".into(),
            color: 0xDCE5FF,
            size: 12,
            bold: false,
            align: TextAlign::Left,
            clip_to_screen: true,
        });
        let wnames = ["Indygo", "Szmaragd", "Rubin", "Noc"];
        let wc = [0x4A2AB2, 0x105666, 0x7A1E58, 0x24345C];
        for i in 0..4 {
            let br = Rect { x: sheet.x + 16 + (i as i32) * (sw + 4), y: sheet.y + 256, w: sw, h: 36 };
            fill_round_rect(fb, w, h, br.x, br.y, br.w, br.h, 10, wc[i]);
            if self.wallpaper_idx == i {
                draw_round_border(fb, w, h, br.x, br.y, br.w, br.h, 10, 0x00E0FF);
            }
            texts.push(TextDraw {
                rect: br,
                text: wnames[i].into(),
                color: 0xFFFFFF,
                size: 11,
                bold: self.wallpaper_idx == i,
                align: TextAlign::Center,
                clip_to_screen: true,
            });
            self.hits.push(HitRegion {
                rect: br,
                action: HitAction::SetWallpaper(i),
                long_press_app: None,
            });
        }

        // Hint + Done button
        texts.push(TextDraw {
            rect: Rect { x: sheet.x + 16, y: sheet.y + 306, w: sheet.w - 32, h: 34 },
            text: "Wskazowka: przytrzymaj (lub PPM) dowolna ikone na pulpicie, aby zmienic ja na kafelek 2x1, 1x2 lub 2x2!".into(),
            color: 0x99A9D8,
            size: 11,
            bold: false,
            align: TextAlign::Left,
            clip_to_screen: true,
        });

        let rst = Rect { x: sheet.x + 16, y: sheet.y + sheet.h - 52, w: 140, h: 40 };
        let ok = Rect { x: sheet.x + 166, y: sheet.y + sheet.h - 52, w: sheet.w - 182, h: 40 };
        fill_round_rect(fb, w, h, rst.x, rst.y, rst.w, rst.h, 12, 0x283254);
        fill_round_rect(fb, w, h, ok.x, ok.y, ok.w, ok.h, 12, 0x5B3CF5);
        texts.push(TextDraw { rect: rst, text: "Resetuj".into(), color: 0xFFFFFF, size: 13, bold: false, align: TextAlign::Center, clip_to_screen: true });
        texts.push(TextDraw { rect: ok, text: "Zastosuj na pulpicie".into(), color: 0xFFFFFF, size: 13, bold: true, align: TextAlign::Center, clip_to_screen: true });
        self.hits.push(HitRegion { rect: rst, action: HitAction::ResetTiles, long_press_app: None });
        self.hits.push(HitRegion { rect: ok, action: HitAction::GoScreen(Screen::Home), long_press_app: None });
    }

    fn render_control_center(&mut self, fb: &mut [u32], w: i32, h: i32, texts: &mut Vec<TextDraw>) {
        blend_rect(fb, w, h, SCR_X, SCR_Y, SCR_W, SCR_H, 0x050812, 185);
        let box_r = Rect { x: SCR_X + 14, y: SCR_Y + STATUS_H + 14, w: SCR_W - 28, h: 280 };
        fill_round_rect(fb, w, h, box_r.x, box_r.y, box_r.w, box_r.h, 22, 0x161D36);
        draw_round_border(fb, w, h, box_r.x, box_r.y, box_r.w, box_r.h, 22, 0x4C62AC);

        texts.push(TextDraw {
            rect: Rect { x: box_r.x + 16, y: box_r.y + 12, w: box_r.w - 32, h: 22 },
            text: "Centrum Kontroli · MysticalOS".into(),
            color: 0xFFFFFF,
            size: 15,
            bold: true,
            align: TextAlign::Left,
            clip_to_screen: true,
        });

        let tiles = [
            ("Wi-Fi", self.wifi_on, HitAction::ToggleWifi),
            ("Bluetooth", self.bt_on, HitAction::ToggleBt),
            ("Tryb ciemny", self.dark_mode, HitAction::ToggleDark),
            ("Latarka", self.flashlight_on, HitAction::ToggleFlashlight),
        ];
        let bw = (box_r.w - 44) / 2;
        for (i, (lbl, on, ac)) in tiles.iter().enumerate() {
            let br = Rect {
                x: box_r.x + 16 + (i as i32 % 2) * (bw + 12),
                y: box_r.y + 46 + (i as i32 / 2) * 56,
                w: bw,
                h: 46,
            };
            fill_round_rect(fb, w, h, br.x, br.y, br.w, br.h, 14, if *on { 0x5B3CF5 } else { 0x263052 });
            texts.push(TextDraw {
                rect: br,
                text: format!("{}: {}", lbl, if *on { "WL" } else { "WYL" }),
                color: 0xFFFFFF,
                size: 13,
                bold: *on,
                align: TextAlign::Center,
                clip_to_screen: true,
            });
            self.hits.push(HitRegion { rect: br, action: *ac, long_press_app: None });
        }

        texts.push(TextDraw {
            rect: Rect { x: box_r.x + 16, y: box_r.y + 168, w: box_r.w - 32, h: 18 },
            text: format!("Jasnosc ekranu: {}%", self.brightness),
            color: 0xDCE5FF,
            size: 12,
            bold: false,
            align: TextAlign::Left,
            clip_to_screen: true,
        });
        let btrack = Rect { x: box_r.x + 18, y: box_r.y + 190, w: box_r.w - 36, h: 28 };
        draw_slider(fb, w, h, btrack, (self.brightness - 30) as f32 / 70.0, 0xFFD24C);
        self.hits.push(HitRegion {
            rect: btrack,
            action: HitAction::DragBrightnessSlider(btrack),
            long_press_app: None,
        });

        let close_b = Rect { x: box_r.x + 16, y: box_r.y + 230, w: box_r.w - 32, h: 36 };
        fill_round_rect(fb, w, h, close_b.x, close_b.y, close_b.w, close_b.h, 12, 0x232C4A);
        texts.push(TextDraw { rect: close_b, text: "Zamknij panel".into(), color: 0xFFFFFF, size: 13, bold: false, align: TextAlign::Center, clip_to_screen: true });
        self.hits.push(HitRegion { rect: close_b, action: HitAction::GoScreen(Screen::Home), long_press_app: None });
    }

    fn render_app_screen(&mut self, fb: &mut [u32], w: i32, h: i32, kind: AppKind, texts: &mut Vec<TextDraw>) {
        let bg = if self.dark_mode { 0x101424 } else { 0xEEF2FB };
        let fg = if self.dark_mode { 0xFFFFFF } else { 0x12182B };
        let sub = if self.dark_mode { 0xA8B6DF } else { 0x4E5B7E };
        let card_bg = if self.dark_mode { 0x1A213A } else { 0xFFFFFF };

        fill_rect(fb, w, h, SCR_X, SCR_Y, SCR_W, SCR_H - NAV_H, bg);
        let app_y = SCR_Y + STATUS_H;

        // App Header bar
        fill_rect(fb, w, h, SCR_X, app_y, SCR_W, 48, if self.dark_mode { 0x161B30 } else { 0xDCE3F6 });
        let back_r = Rect { x: SCR_X + 8, y: app_y + 8, w: 68, h: 32 };
        fill_round_rect(fb, w, h, back_r.x, back_r.y, back_r.w, back_r.h, 10, if self.dark_mode { 0x252E50 } else { 0xC6D2F0 });
        texts.push(TextDraw { rect: back_r, text: "< Pulpit".into(), color: fg, size: 12, bold: true, align: TextAlign::Center, clip_to_screen: true });
        self.hits.push(HitRegion { rect: back_r, action: HitAction::GoScreen(Screen::Home), long_press_app: None });

        let title_str = match kind {
            AppKind::Settings => "Ustawienia MysticalOS",
            AppKind::RomAudit => "Audyt pakietow ROM",
            AppKind::RustMonitor => "Redmi9C Rust Monitor",
            AppKind::Calculator => "Fossify Kalkulator",
            AppKind::Camera => "Fossify Aparat",
            AppKind::Gallery => "Fossify Galeria",
            AppKind::Files => "Fossify Pliki",
            AppKind::Phone => "Fossify Telefon",
            AppKind::Messages => "Fossify Wiadomosci",
            AppKind::Contacts => "Fossify Kontakty",
            AppKind::Clock => "Fossify Zegar",
            AppKind::DroidIfy => "Droid-ify (Sklep FOSS)",
            AppKind::MicroG => "microG Services Core",
            AppKind::IconStyle => "Ikony ColorOS 17",
            AppKind::ImageExplorer => "Eksplorator .img",
        };
        texts.push(TextDraw {
            rect: Rect { x: SCR_X + 84, y: app_y + 10, w: SCR_W - 96, h: 28 },
            text: title_str.into(),
            color: fg,
            size: 16,
            bold: true,
            align: TextAlign::Left,
            clip_to_screen: true,
        });

        let body_y = app_y + 56;
        match kind {
            AppKind::Settings => {
                let rows = [
                    ("Nazwa systemu", format!("{} {} ({})", self.manifest.os_name, self.manifest.os_version, self.manifest.codename)),
                    ("Urzadzenie", format!("{} (blossom / MT6765)", self.manifest.market_name)),
                    ("Wersja Android / Baza", format!("Android {} · {}", self.manifest.android_version, self.manifest.base_rom)),
                    ("Kernel / Daemon", format!("{} + r9c-memd", self.manifest.kernel_version)),
                    ("Apki Xiaomi", format!("USUNIETE ({} pakietow · -{} MiB)", self.manifest.removed_count, self.manifest.freed_mib)),
                    ("Rozmiar ikon (ColorOS 17)", format!("{}% · {} · Siatka {}x", self.icon_scale, self.icon_shape.name(), self.grid_cols)),
                    ("Uslugi / Spoof", self.manifest.services_spoof.clone()),
                ];
                for (i, (k, v)) in rows.iter().enumerate() {
                    let cy = body_y + (i as i32) * 64;
                    fill_round_rect(fb, w, h, SCR_X + 14, cy, SCR_W - 28, 56, 14, card_bg);
                    texts.push(TextDraw { rect: Rect { x: SCR_X + 26, y: cy + 8, w: SCR_W - 52, h: 18 }, text: (*k).into(), color: 0x00C8FF, size: 11, bold: true, align: TextAlign::Left, clip_to_screen: true });
                    texts.push(TextDraw { rect: Rect { x: SCR_X + 26, y: cy + 28, w: SCR_W - 52, h: 22 }, text: v.clone(), color: fg, size: 12, bold: false, align: TextAlign::Left, clip_to_screen: true });
                }
                let btn = Rect { x: SCR_X + 14, y: body_y + 7 * 64 + 4, w: SCR_W - 28, h: 44 };
                fill_round_rect(fb, w, h, btn.x, btn.y, btn.w, btn.h, 14, 0x5B3CF5);
                texts.push(TextDraw { rect: btn, text: "Otworz styl i rozmiar ikon ColorOS 17".into(), color: 0xFFFFFF, size: 13, bold: true, align: TextAlign::Center, clip_to_screen: true });
                self.hits.push(HitRegion { rect: btn, action: HitAction::GoScreen(Screen::IconEditor), long_press_app: None });
            }
            AppKind::RustMonitor => {
                fill_round_rect(fb, w, h, SCR_X + 14, body_y, SCR_W - 28, 180, 16, 0x141824);
                let wave = 0.48 + 0.08 * ((self.anim_tick as f32) * 0.12).sin();
                let bar = Rect { x: SCR_X + 36, y: body_y + 72, w: SCR_W - 72, h: 38 };
                fill_rect(fb, w, h, bar.x, bar.y, bar.w, bar.h, 0xD85224); // Rust orange used
                fill_rect(fb, w, h, bar.x, bar.y, ((bar.w as f32) * wave) as i32, bar.h, 0x29C773); // Emerald free
                texts.push(TextDraw { rect: Rect { x: SCR_X + 26, y: body_y + 18, w: SCR_W - 52, h: 22 }, text: "NativeActivity GLES2 (libredmi9c_rust.so)".into(), color: 0x00E0FF, size: 13, bold: true, align: TextAlign::Center, clip_to_screen: true });
                let tot = if self.ram_3gb { 3072 } else { 2048 };
                let free = ((tot as f32) * wave) as i32;
                texts.push(TextDraw { rect: Rect { x: SCR_X + 26, y: body_y + 126, w: SCR_W - 52, h: 24 }, text: format!("Wolny RAM: {} MiB / {} MiB ({:.0}%)", free, tot, wave * 100.0), color: 0xFFFFFF, size: 14, bold: true, align: TextAlign::Center, clip_to_screen: true });
                fill_round_rect(fb, w, h, SCR_X + 14, body_y + 196, SCR_W - 28, 120, 16, card_bg);
                texts.push(TextDraw { rect: Rect { x: SCR_X + 26, y: body_y + 210, w: SCR_W - 52, h: 90 }, text: "Daemon /system_ext/bin/r9c-memd:\n- PSI LMK progi 70ms / 500ms\n- zRAM lz4 + page-cluster=0\n- Aktywny w polityce SELinux r9c_memd".into(), color: sub, size: 13, bold: false, align: TextAlign::Left, clip_to_screen: true });
            }
            AppKind::Calculator => {
                fill_round_rect(fb, w, h, SCR_X + 14, body_y, SCR_W - 28, 110, 18, card_bg);
                texts.push(TextDraw { rect: Rect { x: SCR_X + 24, y: body_y + 34, w: SCR_W - 48, h: 52 }, text: self.calc_display.clone(), color: fg, size: 38, bold: true, align: TextAlign::Right, clip_to_screen: true });
                let keys = [
                    ['7', '8', '9', '/'],
                    ['4', '5', '6', '*'],
                    ['1', '2', '3', '-'],
                    ['C', '0', '=', '+'],
                ];
                let kw = (SCR_W - 52) / 4;
                for (r, row) in keys.iter().enumerate() {
                    for (c, ch) in row.iter().enumerate() {
                        let kr = Rect {
                            x: SCR_X + 14 + (c as i32) * (kw + 8),
                            y: body_y + 128 + (r as i32) * 76,
                            w: kw,
                            h: 64,
                        };
                        let col = if *ch == '=' { 0x00897B } else if *ch == 'C' { 0xB83B5E } else if "+-*/".contains(*ch) { 0x3D4E82 } else { card_bg };
                        fill_round_rect(fb, w, h, kr.x, kr.y, kr.w, kr.h, 16, col);
                        texts.push(TextDraw { rect: kr, text: ch.to_string(), color: if col == card_bg { fg } else { 0xFFFFFF }, size: 22, bold: true, align: TextAlign::Center, clip_to_screen: true });
                        self.hits.push(HitRegion { rect: kr, action: HitAction::CalcKey(*ch), long_press_app: None });
                    }
                }
            }
            AppKind::Camera => {
                fill_rect(fb, w, h, SCR_X, body_y, SCR_W, 470, if self.camera_flash_ticks > 0 { 0xD8EEFF } else { 0x162033 });
                fill_circle(fb, w, h, SCR_X + SCR_W / 2, body_y + 220, 62, 0x263554);
                draw_glow_ring(fb, w, h, SCR_X + SCR_W / 2, body_y + 220, 74.0, 0x00D6FF, 0x5B3CF5);
                texts.push(TextDraw { rect: Rect { x: SCR_X + 20, y: body_y + 20, w: SCR_W - 40, h: 24 }, text: format!("Fossify Camera · 13 MP · Zdjec: {}", self.camera_shots), color: 0xFFFFFF, size: 13, bold: true, align: TextAlign::Center, clip_to_screen: true });
                let shut = Rect { x: SCR_X + SCR_W / 2 - 36, y: body_y + 492, w: 72, h: 72 };
                fill_circle(fb, w, h, shut.x + 36, shut.y + 36, 34, 0xFFFFFF);
                fill_circle(fb, w, h, shut.x + 36, shut.y + 36, 26, 0x00C8FF);
                self.hits.push(HitRegion { rect: shut, action: HitAction::CameraShutter, long_press_app: None });
            }
            AppKind::RomAudit => {
                let mut lines: Vec<String> = Vec::new();
                if let Some(img) = &self.loaded_image {
                    lines.push(format!("OBRAZ: {}", img.container_kind));
                    lines.push(format!("services.jar: {}", img.services_spoof_verified));
                    lines.push(format!("r9c-memd: {}", if img.has_r9c_memd { "OBECNY" } else { "BRAK" }));
                    lines.push(format!("Pozostalosci Xiaomi: {}", if img.xiaomi_bloat_left.is_empty() { "0 (CZYSTO!)".into() } else { format!("{}", img.xiaomi_bloat_left.len()) }));
                    for p in &img.partitions {
                        lines.push(format!(" [part] {} ({} MiB, {})", p.name, p.size_mib, p.fs_kind));
                    }
                    lines.push(String::new());
                    lines.push(format!("Zainstalowane APK z obrazu ({}):", img.apks.len()));
                    for a in &img.apks {
                        lines.push(format!(" + {} ({}, {} KiB)", a.dir_name, a.package, a.size_kib));
                    }
                } else {
                    lines.push("Brak otwartego pliku .img — dane z wbudowanego manifestu:".into());
                    lines.push(format!("Zainstalowane apki FOSS/System ({}):", self.manifest.app_labels.len()));
                    for (lbl, pkg) in &self.manifest.app_labels {
                        lines.push(format!(" + {} ({})", lbl, pkg));
                    }
                }
                lines.push(String::new());
                lines.push(format!("Lista usuwanych pakietow Xiaomi / bloat ({}):", self.manifest.removed_items.len()));
                for rm in &self.manifest.removed_items {
                    lines.push(format!(" - {} [USUNIETO]", rm));
                }

                let up_b = Rect { x: SCR_X + 14, y: body_y, w: 158, h: 32 };
                let dn_b = Rect { x: SCR_X + SCR_W - 172, y: body_y, w: 158, h: 32 };
                fill_round_rect(fb, w, h, up_b.x, up_b.y, up_b.w, up_b.h, 10, 0x263154);
                fill_round_rect(fb, w, h, dn_b.x, dn_b.y, dn_b.w, dn_b.h, 10, 0x263154);
                texts.push(TextDraw { rect: up_b, text: "^ Przewin w gore".into(), color: 0xFFFFFF, size: 11, bold: false, align: TextAlign::Center, clip_to_screen: true });
                texts.push(TextDraw { rect: dn_b, text: "v Przewin w dol".into(), color: 0xFFFFFF, size: 11, bold: false, align: TextAlign::Center, clip_to_screen: true });
                self.hits.push(HitRegion { rect: up_b, action: HitAction::ScrollAudit(-5), long_press_app: None });
                self.hits.push(HitRegion { rect: dn_b, action: HitAction::ScrollAudit(5), long_press_app: None });

                let start = (self.audit_scroll as usize).min(lines.len().saturating_sub(1));
                for (row_i, ln) in lines[start..].iter().take(24).enumerate() {
                    let ly = body_y + 42 + (row_i as i32) * 24;
                    let col = if ln.starts_with(" -") { 0xFF7B95 } else if ln.starts_with(" +") { 0x62F0B8 } else if ln.starts_with(" [") { 0x00D6FF } else { fg };
                    texts.push(TextDraw {
                        rect: Rect { x: SCR_X + 16, y: ly, w: SCR_W - 32, h: 20 },
                        text: ln.clone(),
                        color: col,
                        size: 11,
                        bold: ln.ends_with(':') || ln.starts_with("OBRAZ:"),
                        align: TextAlign::Left,
                        clip_to_screen: true,
                    });
                }
            }
            AppKind::ImageExplorer => {
                if self.loaded_image.is_none() {
                    fill_round_rect(fb, w, h, SCR_X + 16, body_y + 12, SCR_W - 32, 220, 18, card_bg);
                    texts.push(TextDraw {
                        rect: Rect { x: SCR_X + 28, y: body_y + 28, w: SCR_W - 56, h: 120 },
                        text: "Nie wczytano jeszcze pliku super.img ani system.img.\n\nOtworz rozpakowany super.img lub system.img (EROFS/EXT4/Sparse), aby przegladac katalogi, build.prop, services.jar i aplikacje bezposrednio z obrazu.".into(),
                        color: fg,
                        size: 13,
                        bold: false,
                        align: TextAlign::Left,
                        clip_to_screen: true,
                    });
                    let ob = Rect { x: SCR_X + 28, y: body_y + 166, w: SCR_W - 56, h: 44 };
                    fill_round_rect(fb, w, h, ob.x, ob.y, ob.w, ob.h, 12, 0x0E7490);
                    texts.push(TextDraw { rect: ob, text: "Otworz super.img / system.img...".into(), color: 0xFFFFFF, size: 13, bold: true, align: TextAlign::Center, clip_to_screen: true });
                    self.hits.push(HitRegion { rect: ob, action: HitAction::OpenImageDialog, long_press_app: None });
                } else {
                    let parts_snap: Vec<(String, String)> = self
                        .loaded_image
                        .as_ref()
                        .unwrap()
                        .partitions
                        .iter()
                        .map(|p| (p.name.clone(), p.fs_kind.clone()))
                        .collect();
                    let mut px_cur = SCR_X + 10;
                    for (idx, (pname, fsk)) in parts_snap.iter().enumerate() {
                        if fsk != "erofs" && fsk != "ext4" {
                            continue;
                        }
                        let bw = 66;
                        if px_cur + bw > SCR_X + SCR_W - 8 {
                            break;
                        }
                        let active = *pname == self.explorer_part;
                        let pr = Rect { x: px_cur, y: body_y, w: bw, h: 28 };
                        fill_round_rect(fb, w, h, pr.x, pr.y, pr.w, pr.h, 8, if active { 0x5B3CF5 } else { 0x242C4A });
                        texts.push(TextDraw { rect: pr, text: pname.clone(), color: 0xFFFFFF, size: 10, bold: active, align: TextAlign::Center, clip_to_screen: true });
                        self.hits.push(HitRegion { rect: pr, action: HitAction::ExplorerSelectPartIdx(idx), long_press_app: None });
                        px_cur += bw + 4;
                    }

                    if let Some((fpath, content)) = self.explorer_file_preview.clone() {
                        let back_f = Rect { x: SCR_X + 12, y: body_y + 34, w: 120, h: 28 };
                        fill_round_rect(fb, w, h, back_f.x, back_f.y, back_f.w, back_f.h, 8, 0x253052);
                        texts.push(TextDraw { rect: back_f, text: "< Lista plikow".into(), color: 0xFFFFFF, size: 11, bold: true, align: TextAlign::Center, clip_to_screen: true });
                        self.hits.push(HitRegion { rect: back_f, action: HitAction::ExplorerClosePreview, long_press_app: None });

                        texts.push(TextDraw { rect: Rect { x: SCR_X + 140, y: body_y + 36, w: SCR_W - 152, h: 24 }, text: fpath, color: 0x00E0FF, size: 11, bold: true, align: TextAlign::Left, clip_to_screen: true });
                        fill_round_rect(fb, w, h, SCR_X + 10, body_y + 68, SCR_W - 20, SCR_H - NAV_H - body_y - 76, 12, 0x0D111E);
                        let lines: Vec<&str> = content.lines().collect();
                        let start = (self.audit_scroll as usize).min(lines.len().saturating_sub(1));
                        for (ri, ln) in lines[start..].iter().take(28).enumerate() {
                            texts.push(TextDraw {
                                rect: Rect { x: SCR_X + 16, y: body_y + 74 + (ri as i32) * 19, w: SCR_W - 32, h: 18 },
                                text: (*ln).into(),
                                color: 0xC6F2E0,
                                size: 10,
                                bold: false,
                                align: TextAlign::Left,
                                clip_to_screen: true,
                            });
                        }
                    } else {
                        let up_d = Rect { x: SCR_X + 12, y: body_y + 34, w: 68, h: 26 };
                        fill_round_rect(fb, w, h, up_d.x, up_d.y, up_d.w, up_d.h, 8, 0x253052);
                        texts.push(TextDraw { rect: up_d, text: ".. Wyzej".into(), color: 0xFFFFFF, size: 11, bold: true, align: TextAlign::Center, clip_to_screen: true });
                        self.hits.push(HitRegion { rect: up_d, action: HitAction::ExplorerUpDir, long_press_app: None });

                        texts.push(TextDraw {
                            rect: Rect { x: SCR_X + 86, y: body_y + 36, w: SCR_W - 166, h: 22 },
                            text: format!("/{}{}", self.explorer_part, if self.explorer_dir == "/" { "" } else { &self.explorer_dir }),
                            color: 0x00E0FF,
                            size: 11,
                            bold: true,
                            align: TextAlign::Left,
                            clip_to_screen: true,
                        });
                        let sc_up = Rect { x: SCR_X + SCR_W - 76, y: body_y + 34, w: 30, h: 26 };
                        let sc_dn = Rect { x: SCR_X + SCR_W - 42, y: body_y + 34, w: 30, h: 26 };
                        fill_round_rect(fb, w, h, sc_up.x, sc_up.y, sc_up.w, sc_up.h, 6, 0x253052);
                        fill_round_rect(fb, w, h, sc_dn.x, sc_dn.y, sc_dn.w, sc_dn.h, 6, 0x253052);
                        texts.push(TextDraw { rect: sc_up, text: "^".into(), color: 0xFFFFFF, size: 12, bold: true, align: TextAlign::Center, clip_to_screen: true });
                        texts.push(TextDraw { rect: sc_dn, text: "v".into(), color: 0xFFFFFF, size: 12, bold: true, align: TextAlign::Center, clip_to_screen: true });
                        self.hits.push(HitRegion { rect: sc_up, action: HitAction::ScrollAudit(-6), long_press_app: None });
                        self.hits.push(HitRegion { rect: sc_dn, action: HitAction::ScrollAudit(6), long_press_app: None });

                        let start = (self.audit_scroll as usize).min(self.explorer_entries.len().saturating_sub(1));
                        let entries_view: Vec<(usize, FsEntry)> = self
                            .explorer_entries
                            .iter()
                            .enumerate()
                            .skip(start)
                            .take(21)
                            .map(|(i, e)| (i, e.clone()))
                            .collect();
                        for (row_i, (orig_idx, ent)) in entries_view.into_iter().enumerate() {
                            let ry = body_y + 68 + (row_i as i32) * 28;
                            let rr = Rect { x: SCR_X + 12, y: ry, w: SCR_W - 24, h: 24 };
                            fill_round_rect(fb, w, h, rr.x, rr.y, rr.w, rr.h, 6, card_bg);
                            let tag = if ent.is_dir { "[DIR]" } else if ent.is_symlink { "[LNK]" } else { "[PLK]" };
                            let col = if ent.is_dir { 0xFFD24C } else if ent.is_symlink { 0x62F0B8 } else { fg };
                            let label = if ent.is_dir || ent.is_symlink {
                                format!("{} {}", tag, ent.name)
                            } else if ent.size >= 1024 * 1024 {
                                format!("{} {} ({:.1} MiB)", tag, ent.name, ent.size as f64 / (1024.0 * 1024.0))
                            } else {
                                format!("{} {} ({} B)", tag, ent.name, ent.size)
                            };
                            texts.push(TextDraw {
                                rect: Rect { x: rr.x + 8, y: rr.y + 2, w: rr.w - 16, h: 20 },
                                text: label,
                                color: col,
                                size: 11,
                                bold: ent.is_dir,
                                align: TextAlign::Left,
                                clip_to_screen: true,
                            });
                            if ent.is_dir || !ent.is_symlink {
                                self.hits.push(HitRegion { rect: rr, action: HitAction::ExplorerOpenEntry(orig_idx), long_press_app: None });
                            }
                        }
                    }
                }
            }
            _ => {
                fill_round_rect(fb, w, h, SCR_X + 14, body_y, SCR_W - 28, 240, 18, card_bg);
                let msg = match kind {
                    AppKind::Phone => "Fossify Phone (Open Source)\n\nZastepuje HyperPhone i Google Dialer.\nObsluguje dual-SIM MTK (MtkTeleService + Telecom) bez telemetrii Xiaomi.",
                    AppKind::Messages => "Fossify Messages (Open Source)\n\nZastepuje MiuiMmsGlobal oraz Wiadomosci Google.\nCzysta obsluga SMS/MMS bez reklam i chmury Xiaomi.",
                    AppKind::Gallery => "Fossify Gallery (Open Source)\n\nZastepuje MIUIGalleryGlobal (oszczednosc 107 MiB).\nSzybka przegladarka zdjec i wideo offline.",
                    AppKind::Files => "Fossify File Manager (Open Source)\n\nZastepuje MIUIFileExplorerGlobal.\nPrzegladanie pamieci wewnetrznej, karty SD i USB OTG.",
                    AppKind::Contacts => "Fossify Contacts (Open Source)\n\nZastepuje Kontakty Xiaomi i GoogleContacts.\nPelna prywatnosc lokalnej ksiazki adresowej.",
                    AppKind::Clock => "Fossify Clock (Open Source)\n\nAlarmy, minutnik, stoper i zegar swiatowy bez uslug Xiaomi.",
                    AppKind::DroidIfy => "Droid-ify (Sklep F-Droid)\n\nZastepuje GetApps / MiPicks oraz Sklep Play.\nInstalacja setek aplikacji Open Source bez konta.",
                    AppKind::MicroG => "microG Services Core (v0.3.18)\n\nOtwarty zamiennik Usług Google Play.\nZgodny z aplikacjami wymagajacymi powiadomien Push i lokalizacji.",
                    _ => "Aplikacja systemowa MysticalOS",
                };
                texts.push(TextDraw {
                    rect: Rect { x: SCR_X + 28, y: body_y + 24, w: SCR_W - 56, h: 190 },
                    text: msg.into(),
                    color: fg,
                    size: 13,
                    bold: false,
                    align: TextAlign::Left,
                    clip_to_screen: true,
                });
            }
        }
    }

    fn render_status_and_nav(&mut self, fb: &mut [u32], w: i32, h: i32, texts: &mut Vec<TextDraw>) {
        // Status bar top hit zone -> Control Center
        let sb = Rect { x: SCR_X, y: SCR_Y, w: SCR_W, h: STATUS_H };
        texts.push(TextDraw {
            rect: Rect { x: SCR_X + 14, y: SCR_Y + 5, w: 68, h: 18 },
            text: format!("{:02}:{:02}", self.clock_hh, self.clock_mm),
            color: 0xFFFFFF,
            size: 12,
            bold: true,
            align: TextAlign::Left,
            clip_to_screen: true,
        });
        // Always-On Dynamic Island pill
        let di = Rect { x: SCR_X + (SCR_W / 2) - 54, y: SCR_Y + 4, w: 108, h: 19 };
        fill_round_rect(fb, w, h, di.x, di.y, di.w, di.h, 9, 0x05070D);
        draw_round_border(fb, w, h, di.x, di.y, di.w, di.h, 9, 0x00D6FF);
        texts.push(TextDraw {
            rect: di,
            text: "● Island ON".into(),
            color: 0x9FF5FF,
            size: 10,
            bold: true,
            align: TextAlign::Center,
            clip_to_screen: true,
        });
        texts.push(TextDraw {
            rect: Rect { x: SCR_X + SCR_W - 118, y: SCR_Y + 5, w: 106, h: 18 },
            text: format!("{} 4G 94%", if self.wifi_on { "WiFi" } else { "--" }),
            color: 0xFFFFFF,
            size: 11,
            bold: false,
            align: TextAlign::Right,
            clip_to_screen: true,
        });
        self.hits.push(HitRegion {
            rect: sb,
            action: HitAction::GoScreen(if self.screen == Screen::ControlCenter { Screen::Home } else { Screen::ControlCenter }),
            long_press_app: None,
        });

        // Navigation bar bottom
        let ny = SCR_Y + SCR_H - NAV_H;
        fill_rect(fb, w, h, SCR_X, ny, SCR_W, NAV_H, 0x0A0D18);
        if self.gesture_nav {
            let pill = Rect { x: SCR_X + 110, y: ny + 13, w: SCR_W - 220, h: 5 };
            fill_round_rect(fb, w, h, pill.x, pill.y, pill.w, pill.h, 2, 0xD0DCFF);
            self.hits.push(HitRegion {
                rect: Rect { x: SCR_X, y: ny, w: SCR_W, h: NAV_H },
                action: HitAction::Home,
                long_press_app: None,
            });
        } else {
            let b_back = Rect { x: SCR_X + 32, y: ny + 2, w: 80, h: NAV_H - 4 };
            let b_home = Rect { x: SCR_X + 140, y: ny + 2, w: 80, h: NAV_H - 4 };
            let b_lock = Rect { x: SCR_X + 248, y: ny + 2, w: 80, h: NAV_H - 4 };
            texts.push(TextDraw { rect: b_back, text: "<".into(), color: 0xDCE5FF, size: 15, bold: true, align: TextAlign::Center, clip_to_screen: true });
            texts.push(TextDraw { rect: b_home, text: "O".into(), color: 0xDCE5FF, size: 14, bold: true, align: TextAlign::Center, clip_to_screen: true });
            texts.push(TextDraw { rect: b_lock, text: "||".into(), color: 0xDCE5FF, size: 13, bold: true, align: TextAlign::Center, clip_to_screen: true });
            self.hits.push(HitRegion { rect: b_back, action: HitAction::Back, long_press_app: None });
            self.hits.push(HitRegion { rect: b_home, action: HitAction::Home, long_press_app: None });
            self.hits.push(HitRegion { rect: b_lock, action: HitAction::LockToggle, long_press_app: None });
        }
    }

    fn render_pc_panel(&mut self, fb: &mut [u32], w: i32, h: i32, texts: &mut Vec<TextDraw>) {
        let px = 456;
        let pw = WIN_W - px - 24; // 660
        fill_round_rect(fb, w, h, px, 18, pw, WIN_H - 36, 22, 0x151B2E);
        draw_round_border(fb, w, h, px, 18, pw, WIN_H - 36, 22, 0x2F3B5E);

        texts.push(TextDraw {
            rect: Rect { x: px + 24, y: 34, w: pw - 48, h: 32 },
            text: format!("{} {} Emulator (Windows PC)", self.manifest.os_name, self.manifest.os_version),
            color: 0xFFFFFF,
            size: 22,
            bold: true,
            align: TextAlign::Left,
            clip_to_screen: false,
        });
        texts.push(TextDraw {
            rect: Rect { x: px + 24, y: 68, w: pw - 48, h: 22 },
            text: format!("{} · {} · Zero apek Xiaomi · Styl ikon ColorOS 17", self.manifest.market_name, self.manifest.base_rom),
            color: 0x00D6FF,
            size: 13,
            bold: false,
            align: TextAlign::Left,
            clip_to_screen: false,
        });

        // Hardware control row
        let hw_btns = [
            ("Pulpit (Home)", HitAction::Home),
            ("Wstecz (Back)", HitAction::Back),
            ("Blokada", HitAction::LockToggle),
            ("Restart Boot", HitAction::RestartBoot),
            ("Zrzut BMP", HitAction::SaveScreenshot),
        ];
        let bw = (pw - 48 - 32) / 5;
        for (i, (lbl, ac)) in hw_btns.iter().enumerate() {
            let br = Rect { x: px + 24 + (i as i32) * (bw + 8), y: 106, w: bw, h: 38 };
            fill_round_rect(fb, w, h, br.x, br.y, br.w, br.h, 10, 0x242E4C);
            draw_round_border(fb, w, h, br.x, br.y, br.w, br.h, 10, 0x455890);
            texts.push(TextDraw { rect: br, text: (*lbl).into(), color: 0xFFFFFF, size: 12, bold: true, align: TextAlign::Center, clip_to_screen: false });
            self.hits.push(HitRegion { rect: br, action: *ac, long_press_app: None });
        }

        // Image Engine Card (super.img / system.img loader + extractor)
        let img_card = Rect { x: px + 24, y: 154, w: pw - 48, h: 98 };
        fill_round_rect(fb, w, h, img_card.x, img_card.y, img_card.w, img_card.h, 14, 0x102233);
        draw_round_border(fb, w, h, img_card.x, img_card.y, img_card.w, img_card.h, 14, 0x06B6D4);

        let img_title = if let Some(img) = &self.loaded_image {
            format!("SILNIK OBRAZU: {} (AKTYWNY Z PLIKU)", img.container_kind)
        } else {
            "SILNIK OBRAZU super.img / system.img (wskaz plik lub upusc na okno)".into()
        };
        texts.push(TextDraw {
            rect: Rect { x: img_card.x + 14, y: img_card.y + 8, w: img_card.w - 28, h: 20 },
            text: img_title,
            color: if self.loaded_image.is_some() { 0x62F0B8 } else { 0xFFD24C },
            size: 13,
            bold: true,
            align: TextAlign::Left,
            clip_to_screen: false,
        });

        let open_img_b = Rect { x: img_card.x + 14, y: img_card.y + 34, w: 230, h: 32 };
        let ext_sys_b = Rect { x: img_card.x + 252, y: img_card.y + 34, w: 184, h: 32 };
        let exp_b = Rect { x: img_card.x + 444, y: img_card.y + 34, w: img_card.w - 458, h: 32 };
        fill_round_rect(fb, w, h, open_img_b.x, open_img_b.y, open_img_b.w, open_img_b.h, 9, 0x0E7490);
        fill_round_rect(fb, w, h, ext_sys_b.x, ext_sys_b.y, ext_sys_b.w, ext_sys_b.h, 9, if self.loaded_image.is_some() { 0x264B6E } else { 0x1B243B });
        fill_round_rect(fb, w, h, exp_b.x, exp_b.y, exp_b.w, exp_b.h, 9, 0x2D3C66);
        texts.push(TextDraw { rect: open_img_b, text: "Otworz super.img / system.img...".into(), color: 0xFFFFFF, size: 12, bold: true, align: TextAlign::Center, clip_to_screen: false });
        texts.push(TextDraw { rect: ext_sys_b, text: "Wypakuj system.img".into(), color: if self.loaded_image.is_some() { 0xFFFFFF } else { 0x7A88AD }, size: 12, bold: false, align: TextAlign::Center, clip_to_screen: false });
        texts.push(TextDraw { rect: exp_b, text: "Eksploruj .img".into(), color: 0xFFFFFF, size: 12, bold: true, align: TextAlign::Center, clip_to_screen: false });
        self.hits.push(HitRegion { rect: open_img_b, action: HitAction::OpenImageDialog, long_press_app: None });
        self.hits.push(HitRegion { rect: ext_sys_b, action: HitAction::ExtractSystemImg, long_press_app: None });
        self.hits.push(HitRegion { rect: exp_b, action: HitAction::OpenApp(AppKind::ImageExplorer), long_press_app: None });

        let img_sub = if let Some(img) = &self.loaded_image {
            let pnames: Vec<String> = img.partitions.iter().map(|p| format!("{}({}M/{})", p.name, p.size_mib, p.fs_kind)).collect();
            format!("Partycje: {}", pnames.join(", "))
        } else {
            "Uruchom po rozpakowaniu MysticalOS-Redmi9C.7z.001..005 (wykrywa super.img/system.img automatycznie).".into()
        };
        texts.push(TextDraw {
            rect: Rect { x: img_card.x + 14, y: img_card.y + 72, w: img_card.w - 28, h: 18 },
            text: img_sub,
            color: 0xB8D4EE,
            size: 11,
            bold: false,
            align: TextAlign::Left,
            clip_to_screen: false,
        });

        // ColorOS 17 Icon Resizer Control Card on PC panel
        let c1 = Rect { x: px + 24, y: 262, w: pw - 48, h: 176 };
        fill_round_rect(fb, w, h, c1.x, c1.y, c1.w, c1.h, 16, 0x1B233B);
        draw_round_border(fb, w, h, c1.x, c1.y, c1.w, c1.h, 16, 0x5B3CF5);
        texts.push(TextDraw {
            rect: Rect { x: c1.x + 16, y: c1.y + 10, w: c1.w - 32, h: 22 },
            text: format!("ColorOS 17 — Zmiana rozmiaru ikon na zywo ({}%)", self.icon_scale),
            color: 0xFFFFFF,
            size: 14,
            bold: true,
            align: TextAlign::Left,
            clip_to_screen: false,
        });

        let pc_track = Rect { x: c1.x + 18, y: c1.y + 38, w: c1.w - 36, h: 28 };
        draw_slider(fb, w, h, pc_track, (self.icon_scale - 60) as f32 / 90.0, 0x00D6FF);
        self.hits.push(HitRegion {
            rect: pc_track,
            action: HitAction::DragIconSlider(pc_track),
            long_press_app: None,
        });

        let shapes = [IconShape::Squircle, IconShape::Circle, IconShape::Rounded, IconShape::Teardrop];
        let sw = (c1.w - 60) / 4;
        for (i, sh) in shapes.iter().enumerate() {
            let br = Rect { x: c1.x + 18 + (i as i32) * (sw + 8), y: c1.y + 78, w: sw, h: 34 };
            let act = self.icon_shape == *sh;
            fill_round_rect(fb, w, h, br.x, br.y, br.w, br.h, 10, if act { 0x5B3CF5 } else { 0x263152 });
            texts.push(TextDraw { rect: br, text: format!("Ksztalt: {}", sh.name()), color: 0xFFFFFF, size: 12, bold: act, align: TextAlign::Center, clip_to_screen: false });
            self.hits.push(HitRegion { rect: br, action: HitAction::SetShape(*sh), long_press_app: None });
        }

        let nav_b = Rect { x: c1.x + 18, y: c1.y + 124, w: 190, h: 34 };
        let ram_b = Rect { x: c1.x + 218, y: c1.y + 124, w: 195, h: 34 };
        let rst_b = Rect { x: c1.x + 423, y: c1.y + 124, w: c1.w - 441, h: 34 };
        fill_round_rect(fb, w, h, nav_b.x, nav_b.y, nav_b.w, nav_b.h, 10, 0x263152);
        fill_round_rect(fb, w, h, ram_b.x, ram_b.y, ram_b.w, ram_b.h, 10, 0x263152);
        fill_round_rect(fb, w, h, rst_b.x, rst_b.y, rst_b.w, rst_b.h, 10, 0x2D3C66);
        texts.push(TextDraw { rect: nav_b, text: format!("Nawigacja: {}", if self.gesture_nav { "Gesty" } else { "3 przyciski" }), color: 0xFFFFFF, size: 12, bold: false, align: TextAlign::Center, clip_to_screen: false });
        texts.push(TextDraw { rect: ram_b, text: format!("Wariant: {}", if self.ram_3gb { "3 GB / 64 GB" } else { "2 GB / 32 GB" }), color: 0xFFFFFF, size: 12, bold: false, align: TextAlign::Center, clip_to_screen: false });
        texts.push(TextDraw { rect: rst_b, text: "Resetuj uklad".into(), color: 0xFFFFFF, size: 12, bold: true, align: TextAlign::Center, clip_to_screen: false });
        self.hits.push(HitRegion { rect: nav_b, action: HitAction::ToggleNavGestures, long_press_app: None });
        self.hits.push(HitRegion { rect: ram_b, action: HitAction::ToggleRamVariant, long_press_app: None });
        self.hits.push(HitRegion { rect: rst_b, action: HitAction::ResetTiles, long_press_app: None });

        // ROM Live Inspection / Build Details Card
        let c2 = Rect { x: px + 24, y: 450, w: pw - 48, h: 256 };
        fill_round_rect(fb, w, h, c2.x, c2.y, c2.w, c2.h, 16, 0x111728);
        draw_round_border(fb, w, h, c2.x, c2.y, c2.w, c2.h, 16, 0x2B385B);
        let hdr_c2 = if self.loaded_image.is_some() {
            "Odczyt na zywo z pliku super.img / system.img (Sparse + liblp + EROFS/EXT4)"
        } else {
            "Dane zbudowanego ROM-u (wbudowany manifest — otworz .img dla skanu na zywo)"
        };
        texts.push(TextDraw {
            rect: Rect { x: c2.x + 16, y: c2.y + 10, w: c2.w - 32, h: 22 },
            text: hdr_c2.into(),
            color: 0x62F0B8,
            size: 13,
            bold: true,
            align: TextAlign::Left,
            clip_to_screen: false,
        });

        let summary_lines = if let Some(img) = &self.loaded_image {
            let boot_info = if img.boot_frames.is_empty() {
                "brak PNG (albo obraz to sam system.img bez product.img)".into()
            } else {
                format!("zaladowano {} prawdziwych klatek PNG", img.boot_frames.len())
            };
            let bloat_info = if img.xiaomi_bloat_left.is_empty() {
                "0 wykrytych apek Xiaomi (czysto!)".into()
            } else {
                format!("WYKRYTO {}: {}", img.xiaomi_bloat_left.len(), img.xiaomi_bloat_left.join(", "))
            };
            format!(
                "Plik: {}\n\
                 Android (z build.prop): {} | Model: {} | Wersja: {}\n\
                 Weryfikacja services.jar: {}\n\
                 Daemon r9c-memd: {} | Bootanimation.zip: {}\n\
                 Apki wyciagniete z APK (AXML): {} pakietow | Bloat Xiaomi: {}\n\
                 Launcher HyperOS 4: {} | Dynamic Island: {}\n\
                 Wlasciwosci build.prop: {} wpisow\n\n\
                 Uzyj ikony 'Obraz .img' na ekranie lub przycisku 'Eksploruj .img' powyzej,\n\
                 aby przegladac katalogi /system, /product i podgladac pliki build.prop / .rc!",
                img.file_path,
                self.manifest.android_version,
                self.manifest.market_name,
                self.manifest.os_version,
                img.services_spoof_verified,
                if img.has_r9c_memd { "OBECNY" } else { "brak w tym obrazie" },
                boot_info,
                img.apks.len(),
                bloat_info,
                if img.has_hyperos4_launcher { "TAK (com.miui.home)" } else { "MysticalLauncher" },
                if img.has_dynamic_island_config { "ZAWSZE WLACZONY" } else { "brak w prop/xml" },
                img.props.len(),
            )
        } else {
            format!(
                "System: {} {} ({}) | Baza: {}\n\
                 Dawca UI: {}\n\
                 Usuniete apki Xiaomi / bloat: {} pozycji (zwolniono ~{} MiB)\n\
                 Spoof microG: {}\n\n\
                 Wskaz plik super.img lub system.img uzywajac przycisku powyzej lub przeciagajac go\n\
                 na okno — dekoder przeczyta na zywo partycje liblp, EROFS+LZ4, EXT4, build.prop,\n\
                 manifesty APK, services.jar (R9cMicrogSpoof) oraz klatki bootanimation.zip!",
                self.manifest.os_name,
                self.manifest.os_version,
                self.manifest.codename,
                self.manifest.base_rom,
                self.manifest.donor_rom,
                self.manifest.removed_count,
                self.manifest.freed_mib,
                self.manifest.services_spoof
            )
        };
        texts.push(TextDraw {
            rect: Rect { x: c2.x + 16, y: c2.y + 38, w: c2.w - 32, h: c2.h - 46 },
            text: summary_lines,
            color: 0xD2DCF5,
            size: 12,
            bold: false,
            align: TextAlign::Left,
            clip_to_screen: false,
        });

        // Honest technical note at bottom of PC panel
        let c3 = Rect { x: px + 24, y: 718, w: pw - 48, h: 104 };
        fill_round_rect(fb, w, h, c3.x, c3.y, c3.w, c3.h, 14, 0x191F33);
        texts.push(TextDraw {
            rect: Rect { x: c3.x + 16, y: c3.y + 10, w: c3.w - 32, h: 86 },
            text: format!(
                "UWAGA TECHNICZNA (GRANICA EMULACJI): Ten program czyta i weryfikuje prawdziwe obrazy super.img i system.img\n\
                 (Sparse + liblp + EROFS/LZ4 + EXT4 + AXML + bootanimation) oraz symuluje interfejs ColorOS 17 / MysticalOS.\n\
                 Samo zbootowanie pelnego jadra i SurfaceFlinger ARM64 MediaTek MT6765 na Windows x86_64 wymaga\n\
                 osobnej maszyny wirtualnej QEMU ARM64 z jadrem virtio/ranchu oraz wirtualnego vendor.img Android 17.\n\
                 Status: {}",
                self.status_msg
            ),
            color: 0x99AACF,
            size: 11,
            bold: false,
            align: TextAlign::Left,
            clip_to_screen: false,
        });
    }

    pub fn handle_left_down(&mut self, x: i32, y: i32, now_ms: u64) -> UiCommand {
        self.pending_long_press = None;
        let matched = self.hits.iter().rev().find(|h| h.rect.contains(x, y)).cloned();
        if let Some(hit) = matched {
            match hit.action {
                HitAction::DragIconSlider(r) => {
                    self.active_slider = Some(HitAction::DragIconSlider(r));
                    let t = ((x - r.x) as f32 / r.w.max(1) as f32).clamp(0.0, 1.0);
                    self.icon_scale = (60.0 + t * 90.0).round() as i32;
                    return UiCommand::None;
                }
                HitAction::DragBrightnessSlider(r) => {
                    self.active_slider = Some(HitAction::DragBrightnessSlider(r));
                    let t = ((x - r.x) as f32 / r.w.max(1) as f32).clamp(0.0, 1.0);
                    self.brightness = (30.0 + t * 70.0).round() as i32;
                    return UiCommand::None;
                }
                HitAction::SaveScreenshot => return UiCommand::SaveScreenshot,
                HitAction::OpenImageDialog => return UiCommand::OpenImageDialog,
                HitAction::ExtractSystemImg => return UiCommand::ExtractSystemImg,
                act => {
                    if let Some(app_idx) = hit.long_press_app {
                        self.pending_long_press = Some((app_idx, now_ms));
                        // Wait for mouse up (short click opens app) or long-press timer (420ms opens tile menu)
                        return UiCommand::None;
                    }
                    self.apply_action(act);
                    return UiCommand::None;
                }
            }
        }
        UiCommand::None
    }

    pub fn handle_mouse_move(&mut self, x: i32, _y: i32) {
        match self.active_slider {
            Some(HitAction::DragIconSlider(r)) => {
                let t = ((x - r.x) as f32 / r.w.max(1) as f32).clamp(0.0, 1.0);
                self.icon_scale = (60.0 + t * 90.0).round() as i32;
            }
            Some(HitAction::DragBrightnessSlider(r)) => {
                let t = ((x - r.x) as f32 / r.w.max(1) as f32).clamp(0.0, 1.0);
                self.brightness = (30.0 + t * 70.0).round() as i32;
            }
            _ => {}
        }
    }

    pub fn handle_left_up(&mut self, x: i32, y: i32) {
        self.active_slider = None;
        if let Some((app_idx, _)) = self.pending_long_press.take() {
            let act = self
                .hits
                .iter()
                .rev()
                .find(|h| h.long_press_app == Some(app_idx) && h.rect.contains(x, y))
                .map(|h| h.action);
            if let Some(a) = act {
                self.apply_action(a);
            }
        }
    }

    pub fn check_long_press(&mut self, now_ms: u64) {
        if let Some((app_idx, started)) = self.pending_long_press {
            if now_ms.saturating_sub(started) >= 420 {
                self.pending_long_press = None;
                self.apply_action(HitAction::OpenIconMenu(app_idx));
            }
        }
    }

    pub fn handle_right_down(&mut self, x: i32, y: i32) {
        let app_idx = self
            .hits
            .iter()
            .rev()
            .find(|h| h.long_press_app.is_some() && h.rect.contains(x, y))
            .and_then(|h| h.long_press_app);
        if let Some(idx) = app_idx {
            self.apply_action(HitAction::OpenIconMenu(idx));
        }
    }
}

// --- Software RGBA Pixel Rasterizer ---

#[inline]
fn blend_px(dst: u32, src: u32, alpha: u32) -> u32 {
    if alpha >= 255 {
        return src;
    }
    if alpha == 0 {
        return dst;
    }
    let inv = 255 - alpha;
    let sr = (src >> 16) & 0xFF;
    let sg = (src >> 8) & 0xFF;
    let sb = src & 0xFF;
    let dr = (dst >> 16) & 0xFF;
    let dg = (dst >> 8) & 0xFF;
    let db = dst & 0xFF;
    let r = (sr * alpha + dr * inv) / 255;
    let g = (sg * alpha + dg * inv) / 255;
    let b = (sb * alpha + db * inv) / 255;
    (r << 16) | (g << 8) | b
}

#[inline]
fn lerp_color(c1: u32, c2: u32, t: f32) -> u32 {
    let t = t.clamp(0.0, 1.0);
    let r1 = ((c1 >> 16) & 0xFF) as f32;
    let g1 = ((c1 >> 8) & 0xFF) as f32;
    let b1 = (c1 & 0xFF) as f32;
    let r2 = ((c2 >> 16) & 0xFF) as f32;
    let g2 = ((c2 >> 8) & 0xFF) as f32;
    let b2 = (c2 & 0xFF) as f32;
    let r = (r1 + (r2 - r1) * t) as u32;
    let g = (g1 + (g2 - g1) * t) as u32;
    let b = (b1 + (b2 - b1) * t) as u32;
    (r << 16) | (g << 8) | b
}

fn fill_rect(fb: &mut [u32], w: i32, h: i32, x: i32, y: i32, rw: i32, rh: i32, col: u32) {
    let x0 = x.max(0);
    let y0 = y.max(0);
    let x1 = (x + rw).min(w);
    let y1 = (y + rh).min(h);
    for yy in y0..y1 {
        let row = (yy * w) as usize;
        for xx in x0..x1 {
            fb[row + xx as usize] = col;
        }
    }
}

fn blend_rect(fb: &mut [u32], w: i32, h: i32, x: i32, y: i32, rw: i32, rh: i32, col: u32, alpha: u32) {
    let x0 = x.max(0);
    let y0 = y.max(0);
    let x1 = (x + rw).min(w);
    let y1 = (y + rh).min(h);
    for yy in y0..y1 {
        let row = (yy * w) as usize;
        for xx in x0..x1 {
            let p = row + xx as usize;
            fb[p] = blend_px(fb[p], col, alpha);
        }
    }
}

fn fill_gradient_v(fb: &mut [u32], w: i32, h: i32, x: i32, y: i32, rw: i32, rh: i32, c1: u32, c2: u32) {
    let x0 = x.max(0);
    let y0 = y.max(0);
    let x1 = (x + rw).min(w);
    let y1 = (y + rh).min(h);
    for yy in y0..y1 {
        let t = (yy - y) as f32 / rh.max(1) as f32;
        let col = lerp_color(c1, c2, t);
        let row = (yy * w) as usize;
        for xx in x0..x1 {
            fb[row + xx as usize] = col;
        }
    }
}

fn fill_gradient_h(fb: &mut [u32], w: i32, h: i32, x: i32, y: i32, rw: i32, rh: i32, c1: u32, c2: u32) {
    let x0 = x.max(0);
    let y0 = y.max(0);
    let x1 = (x + rw).min(w);
    let y1 = (y + rh).min(h);
    for xx in x0..x1 {
        let t = (xx - x) as f32 / rw.max(1) as f32;
        let col = lerp_color(c1, c2, t);
        for yy in y0..y1 {
            fb[(yy * w + xx) as usize] = col;
        }
    }
}

fn round_sdf(dx: f32, dy: f32, hw: f32, hh: f32, r: f32) -> f32 {
    let qx = dx.abs() - (hw - r);
    let qy = dy.abs() - (hh - r);
    let ox = qx.max(0.0);
    let oy = qy.max(0.0);
    (ox * ox + oy * oy).sqrt() + qx.max(qy).min(0.0) - r
}

fn fill_round_rect(fb: &mut [u32], w: i32, h: i32, x: i32, y: i32, rw: i32, rh: i32, r: i32, col: u32) {
    fill_round_rect_alpha(fb, w, h, x, y, rw, rh, r, col, 255);
}

fn fill_round_rect_alpha(fb: &mut [u32], w: i32, h: i32, x: i32, y: i32, rw: i32, rh: i32, r: i32, col: u32, alpha: u32) {
    let x0 = x.max(0);
    let y0 = y.max(0);
    let x1 = (x + rw).min(w);
    let y1 = (y + rh).min(h);
    let hw = rw as f32 * 0.5;
    let hh = rh as f32 * 0.5;
    let cx = x as f32 + hw;
    let cy = y as f32 + hh;
    let rad = (r as f32).min(hw).min(hh);
    for yy in y0..y1 {
        let dy = yy as f32 + 0.5 - cy;
        let row = (yy * w) as usize;
        for xx in x0..x1 {
            let dx = xx as f32 + 0.5 - cx;
            let d = round_sdf(dx, dy, hw, hh, rad);
            if d < 0.75 {
                let cov = (0.75 - d).clamp(0.0, 1.0);
                let a = ((alpha as f32) * cov) as u32;
                let p = row + xx as usize;
                fb[p] = blend_px(fb[p], col, a);
            }
        }
    }
}

fn round_mask_in_place(fb: &mut [u32], w: i32, h: i32, r: Rect, rad: i32) {
    let hw = r.w as f32 * 0.5;
    let hh = r.h as f32 * 0.5;
    let cx = r.x as f32 + hw;
    let cy = r.y as f32 + hh;
    let rr = (rad as f32).min(hw).min(hh);
    for yy in r.y.max(0)..(r.y + r.h).min(h) {
        for xx in r.x.max(0)..(r.x + r.w).min(w) {
            let d = round_sdf(xx as f32 + 0.5 - cx, yy as f32 + 0.5 - cy, hw, hh, rr);
            if d > 0.5 {
                fb[(yy * w + xx) as usize] = 0x151A32;
            }
        }
    }
}

fn draw_round_border(fb: &mut [u32], w: i32, h: i32, x: i32, y: i32, rw: i32, rh: i32, r: i32, col: u32) {
    let x0 = x.max(0);
    let y0 = y.max(0);
    let x1 = (x + rw).min(w);
    let y1 = (y + rh).min(h);
    let hw = rw as f32 * 0.5;
    let hh = rh as f32 * 0.5;
    let cx = x as f32 + hw;
    let cy = y as f32 + hh;
    let rad = (r as f32).min(hw).min(hh);
    for yy in y0..y1 {
        let dy = yy as f32 + 0.5 - cy;
        let row = (yy * w) as usize;
        for xx in x0..x1 {
            let dx = xx as f32 + 0.5 - cx;
            let d = round_sdf(dx, dy, hw, hh, rad);
            if (-1.3..=0.6).contains(&d) {
                let p = row + xx as usize;
                fb[p] = blend_px(fb[p], col, 175);
            }
        }
    }
}

fn fill_circle(fb: &mut [u32], w: i32, h: i32, cx: i32, cy: i32, r: i32, col: u32) {
    let x0 = (cx - r - 1).max(0);
    let y0 = (cy - r - 1).max(0);
    let x1 = (cx + r + 2).min(w);
    let y1 = (cy + r + 2).min(h);
    let rf = r as f32;
    for yy in y0..y1 {
        let dy = yy as f32 + 0.5 - cy as f32;
        for xx in x0..x1 {
            let dx = xx as f32 + 0.5 - cx as f32;
            let dist = (dx * dx + dy * dy).sqrt();
            if dist < rf + 0.75 {
                let cov = (rf + 0.75 - dist).clamp(0.0, 1.0);
                let p = (yy * w + xx) as usize;
                fb[p] = blend_px(fb[p], col, (cov * 255.0) as u32);
            }
        }
    }
}

fn add_radial_glow(fb: &mut [u32], w: i32, h: i32, cx: i32, cy: i32, r: i32, col: u32, max_alpha: u32) {
    let x0 = (cx - r).max(SCR_X);
    let y0 = (cy - r).max(SCR_Y);
    let x1 = (cx + r).min(SCR_X + SCR_W).min(w);
    let y1 = (cy + r).min(SCR_Y + SCR_H).min(h);
    let rf = r.max(1) as f32;
    for yy in y0..y1 {
        let dy = (yy - cy) as f32;
        let row = (yy * w) as usize;
        for xx in x0..x1 {
            let dx = (xx - cx) as f32;
            let d = (dx * dx + dy * dy).sqrt();
            if d < rf {
                let k = (1.0 - d / rf).powi(2);
                let a = (k * max_alpha as f32) as u32;
                let p = row + xx as usize;
                fb[p] = blend_px(fb[p], col, a);
            }
        }
    }
}

fn draw_glow_ring(fb: &mut [u32], w: i32, h: i32, cx: i32, cy: i32, r: f32, c1: u32, c2: u32) {
    let ir = (r + 14.0) as i32;
    let x0 = (cx - ir).max(SCR_X);
    let y0 = (cy - ir).max(SCR_Y);
    let x1 = (cx + ir).min(SCR_X + SCR_W).min(w);
    let y1 = (cy + ir).min(SCR_Y + SCR_H).min(h);
    for yy in y0..y1 {
        let dy = (yy - cy) as f32;
        for xx in x0..x1 {
            let dx = (xx - cx) as f32;
            let d = (dx * dx + dy * dy).sqrt();
            let diff = (d - r).abs();
            if diff < 10.0 {
                let ang = dy.atan2(dx) / (2.0 * PI) + 0.5;
                let col = lerp_color(c1, c2, ang);
                let k = (1.0 - diff / 10.0).powi(2);
                let p = (yy * w + xx) as usize;
                fb[p] = blend_px(fb[p], col, (k * 230.0) as u32);
            }
        }
    }
}

fn draw_diamond(fb: &mut [u32], w: i32, h: i32, cx: i32, cy: i32, rad: i32, col: u32) {
    let x0 = (cx - rad).max(SCR_X);
    let y0 = (cy - rad).max(SCR_Y);
    let x1 = (cx + rad + 1).min(SCR_X + SCR_W).min(w);
    let y1 = (cy + rad + 1).min(SCR_Y + SCR_H).min(h);
    let rf = rad as f32;
    for yy in y0..y1 {
        let dy = (yy - cy).abs() as f32;
        for xx in x0..x1 {
            let dx = (xx - cx).abs() as f32;
            let man = dx + dy;
            if man <= rf + 0.7 {
                let cov = (rf + 0.7 - man).clamp(0.0, 1.0);
                let p = (yy * w + xx) as usize;
                fb[p] = blend_px(fb[p], col, (cov * 245.0) as u32);
            }
        }
    }
}

fn draw_shaped_app_icon(fb: &mut [u32], w: i32, h: i32, r: Rect, c1: u32, c2: u32, shape: IconShape) {
    let x0 = r.x.max(0);
    let y0 = r.y.max(0);
    let x1 = (r.x + r.w).min(w);
    let y1 = (r.y + r.h).min(h);
    let hw = (r.w as f32 * 0.5).max(1.0);
    let hh = (r.h as f32 * 0.5).max(1.0);
    let cx = r.x as f32 + hw;
    let cy = r.y as f32 + hh;

    for yy in y0..y1 {
        let dy = (yy as f32 + 0.5 - cy) / hh;
        let ty = (yy - r.y) as f32 / r.h.max(1) as f32;
        let row = (yy * w) as usize;
        for xx in x0..x1 {
            let dx = (xx as f32 + 0.5 - cx) / hw;
            let tx = (xx - r.x) as f32 / r.w.max(1) as f32;
            let dist = match shape {
                IconShape::Circle => (dx * dx + dy * dy).sqrt() - 1.0,
                IconShape::Squircle => {
                    // Superellipse p = 3.2 (authentic ColorOS 17 squircle contour)
                    (dx.abs().powf(3.2) + dy.abs().powf(3.2)).powf(1.0 / 3.2) - 1.0
                }
                IconShape::Rounded => round_sdf(dx * hw, dy * hh, hw, hh, hw * 0.24) / hw,
                IconShape::Teardrop => {
                    if dx > 0.0 && dy > 0.0 {
                        round_sdf(dx * hw, dy * hh, hw, hh, hw * 0.16) / hw
                    } else {
                        (dx * dx + dy * dy).sqrt() - 1.0
                    }
                }
            };

            if dist < 0.04 {
                let cov = ((0.04 - dist) * hw).clamp(0.0, 1.0);
                let mut col = lerp_color(c1, c2, (tx + ty) * 0.5);
                if dist > -0.06 {
                    col = blend_px(col, 0xFFFFFF, 65);
                }
                let p = row + xx as usize;
                fb[p] = blend_px(fb[p], col, (cov * 255.0) as u32);
            }
        }
    }
}

fn draw_slider(fb: &mut [u32], w: i32, h: i32, r: Rect, norm: f32, accent: u32) {
    let t = norm.clamp(0.0, 1.0);
    let cy = r.y + r.h / 2;
    fill_round_rect(fb, w, h, r.x, cy - 4, r.w, 8, 4, 0x2B365A);
    let fill_w = ((r.w as f32) * t).round() as i32;
    if fill_w > 4 {
        fill_round_rect(fb, w, h, r.x, cy - 4, fill_w, 8, 4, accent);
    }
    let kx = r.x + fill_w;
    fill_circle(fb, w, h, kx, cy, 11, 0xFFFFFF);
    fill_circle(fb, w, h, kx, cy, 6, accent);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_manifest_and_icon_scale_layout() {
        let mut st = EmulatorState::new(include_str!("../default_manifest.json"));
        assert_eq!(st.manifest.os_name, "MysticalOS");
        assert!(st.manifest.removed_count >= 1);

        // Change icon scale from 60% to 150% -> icon rectangles must grow strictly
        st.apply_action(HitAction::SetIconScale(60));
        let small = st.compute_grid();
        let w_small = small[1].icon_rect.w;

        st.apply_action(HitAction::SetIconScale(150));
        let big = st.compute_grid();
        let w_big = big[1].icon_rect.w;
        assert!(w_big > w_small, "expected bigger icon at 150% ({} > {})", w_big, w_small);
    }

    #[test]
    fn test_coloros17_tile_collision_free() {
        let mut st = EmulatorState::new(include_str!("../default_manifest.json"));
        st.apply_action(HitAction::SetTileSpan(1, TileSpan::S2x2));
        st.apply_action(HitAction::SetTileSpan(2, TileSpan::S2x1));
        let placed = st.compute_grid();
        for i in 0..placed.len() {
            for j in (i + 1)..placed.len() {
                let a = placed[i].rect;
                let b = placed[j].rect;
                let overlap = a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
                assert!(!overlap, "tiles {} and {} overlapped: {:?} vs {:?}", i, j, a, b);
            }
        }
    }

    #[test]
    fn test_calculator_and_render_buffer() {
        let mut st = EmulatorState::new(include_str!("../default_manifest.json"));
        st.apply_action(HitAction::GoScreen(Screen::App(AppKind::Calculator)));
        for ch in ['1', '2', '+', '8', '='] {
            st.apply_action(HitAction::CalcKey(ch));
        }
        assert_eq!(st.calc_display, "20");

        let mut fb = vec![0u32; (WIN_W * WIN_H) as usize];
        let texts = st.render(&mut fb, WIN_W, WIN_H);
        assert!(!texts.is_empty());
        assert!(!st.hits.is_empty());

        st.apply_action(HitAction::OpenApp(AppKind::ImageExplorer));
        let exp_texts = st.render(&mut fb, WIN_W, WIN_H);
        assert!(exp_texts.iter().any(|t| t.text.contains("super.img")));

        st.apply_action(HitAction::OpenApp(AppKind::RomAudit));
        let aud_texts = st.render(&mut fb, WIN_W, WIN_H);
        assert!(!aud_texts.is_empty());
    }
}
