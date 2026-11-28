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
    FolderView,
    HomeEdit,
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
    OpenFolder,
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
    DragVolumeSlider(Rect),
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
    ToggleIsland,
    ToggleIslandPlay,
    ToggleIslandAlwaysOn,
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
    pub volume: i32,     // 0..100
    pub gesture_nav: bool,
    pub ram_3gb: bool,
    pub island_always_on: bool,
    pub island_expanded: bool,
    pub island_playing: bool,
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
            title: "Narzedzia".into(),
            package: "com.miui.home.folder".into(),
            kind: AppKind::IconStyle,
            color1: 0xEEF4FF,
            color2: 0xDCE7FB,
            glyph: "FLD",
            span: TileSpan::S2x2,
        },
        AppIcon {
            title: "Ustawienia".into(),
            package: "com.android.settings".into(),
            kind: AppKind::Settings,
            color1: 0x62738D,
            color2: 0x3D4C66,
            glyph: "SET",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Galeria".into(),
            package: "org.fossify.gallery".into(),
            kind: AppKind::Gallery,
            color1: 0xFFFFFF,
            color2: 0xF1F5FA,
            glyph: "IMG",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Zegar".into(),
            package: "org.fossify.clock".into(),
            kind: AppKind::Clock,
            color1: 0x262D3D,
            color2: 0x161B26,
            glyph: "CLK",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Kalkulator".into(),
            package: "org.fossify.calculator".into(),
            kind: AppKind::Calculator,
            color1: 0xF8FAFC,
            color2: 0xE5EBF3,
            glyph: "123",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Ikony ColorOS".into(),
            package: "org.mysticalos.launcher".into(),
            kind: AppKind::IconStyle,
            color1: 0x4A6CF7,
            color2: 0x16BFFD,
            glyph: "ICO",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Pliki".into(),
            package: "org.fossify.filemanager".into(),
            kind: AppKind::Files,
            color1: 0xFFA726,
            color2: 0xFB8C00,
            glyph: "DIR",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Rust Monitor".into(),
            package: "org.redmi9c.rustmonitor".into(),
            kind: AppKind::RustMonitor,
            color1: 0xE65100,
            color2: 0x2E7D32,
            glyph: "RAM",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Obraz .img".into(),
            package: "org.mysticalos.imgexplorer".into(),
            kind: AppKind::ImageExplorer,
            color1: 0x0EA5E9,
            color2: 0x0369A1,
            glyph: "IMG+",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Audyt ROM".into(),
            package: "org.mysticalos.audit".into(),
            kind: AppKind::RomAudit,
            color1: 0x7C3AED,
            color2: 0xEC4899,
            glyph: "ROM",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Kontakty".into(),
            package: "org.fossify.contacts".into(),
            kind: AppKind::Contacts,
            color1: 0x38BDF8,
            color2: 0x2563EB,
            glyph: "USR",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "microG".into(),
            package: "com.google.android.gms".into(),
            kind: AppKind::MicroG,
            color1: 0x10B981,
            color2: 0x047857,
            glyph: "mG",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Telefon".into(),
            package: "org.fossify.phone".into(),
            kind: AppKind::Phone,
            color1: 0x22C55E,
            color2: 0x16A34A,
            glyph: "TEL",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Wiadomosci".into(),
            package: "org.fossify.messages".into(),
            kind: AppKind::Messages,
            color1: 0x38BDF8,
            color2: 0x0284C7,
            glyph: "SMS",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Droid-ify".into(),
            package: "com.looker.droidify".into(),
            kind: AppKind::DroidIfy,
            color1: 0x4F46E5,
            color2: 0x7C3AED,
            glyph: "APK",
            span: TileSpan::S1x1,
        },
        AppIcon {
            title: "Aparat".into(),
            package: "org.fossify.camera".into(),
            kind: AppKind::Camera,
            color1: 0x333B4D,
            color2: 0x1A1F2B,
            glyph: "CAM",
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
            icon_shape: IconShape::Rounded,
            grid_cols: 4,
            show_labels: true,
            wallpaper_idx: 0,
            dark_mode: false,
            wifi_on: true,
            bt_on: false,
            flashlight_on: false,
            brightness: 92,
            volume: 68,
            gesture_nav: true,
            ram_3gb: false,
            island_always_on: true,
            island_expanded: false,
            island_playing: true,
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
        let grid_x = SCR_X + 14;
        let grid_y = SCR_Y + STATUS_H + 106;
        let grid_w = SCR_W - 28;
        let cell_w = grid_w / cols as i32;
        let base_icon = if cols == 5 { 38 } else { 44 };
        let icon_sz = ((base_icon * self.icon_scale) / 100).max(24).min(68);
        let unit_h = (icon_sz + 26).max(66);

        let mut occ = vec![vec![false; cols]; 48];
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
                self.island_expanded = false;
                if kind == AppKind::IconStyle {
                    self.screen = Screen::IconEditor;
                } else {
                    self.audit_scroll = 0;
                    self.screen = Screen::App(kind);
                }
            }
            HitAction::OpenFolder => {
                self.island_expanded = false;
                self.screen = Screen::FolderView;
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
                self.island_expanded = false;
                self.screen = s;
            }
            HitAction::Back => {
                if self.island_expanded {
                    self.island_expanded = false;
                    return;
                }
                self.screen = match self.screen {
                    Screen::BootAnim => Screen::LockScreen,
                    Screen::LockScreen => Screen::LockScreen,
                    Screen::Home => Screen::Home,
                    Screen::FolderView
                    | Screen::HomeEdit
                    | Screen::TileMenu(_)
                    | Screen::IconEditor
                    | Screen::ControlCenter
                    | Screen::App(_) => Screen::Home,
                };
            }
            HitAction::Home => {
                self.island_expanded = false;
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
                    first.span = TileSpan::S2x2;
                }
                self.icon_scale = 100;
                self.icon_shape = IconShape::Rounded;
                self.show_labels = true;
                self.show_toast("Przywrocono domyslny uklad HyperOS 4");
            }
            HitAction::ToggleDark => self.dark_mode = !self.dark_mode,
            HitAction::ToggleWifi => self.wifi_on = !self.wifi_on,
            HitAction::ToggleBt => self.bt_on = !self.bt_on,
            HitAction::ToggleFlashlight => self.flashlight_on = !self.flashlight_on,
            HitAction::ToggleNavGestures => self.gesture_nav = !self.gesture_nav,
            HitAction::ToggleRamVariant => self.ram_3gb = !self.ram_3gb,
            HitAction::ToggleIsland => {
                self.island_expanded = !self.island_expanded;
            }
            HitAction::ToggleIslandPlay => {
                self.island_playing = !self.island_playing;
            }
            HitAction::ToggleIslandAlwaysOn => {
                self.island_always_on = !self.island_always_on;
                if !self.island_always_on {
                    self.island_expanded = false;
                }
                self.show_toast(if self.island_always_on {
                    "HyperIsland: ZAWSZE WLACZONY"
                } else {
                    "HyperIsland: ukryty"
                });
            }
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
            | HitAction::DragVolumeSlider(_)
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

        // 3. Render phone screen contents (camera lens lives cleanly inside HyperIsland pill)
        self.render_phone_screen(fb, width, height, &mut texts);

        // 4. Right-hand PC Control & Inspector Panel
        self.render_pc_panel(fb, width, height, &mut texts);

        texts
    }

    fn render_phone_screen(&mut self, fb: &mut [u32], w: i32, h: i32, texts: &mut Vec<TextDraw>) {
        // HyperOS 4 Liquid Glass / Horizon wallpaper
        draw_hyperos_wallpaper(fb, w, h, self.wallpaper_idx);

        match self.screen {
            Screen::BootAnim => self.render_boot(fb, w, h, texts),
            Screen::LockScreen => self.render_lockscreen(fb, w, h, texts),
            Screen::Home => self.render_home(fb, w, h, texts),
            Screen::FolderView => {
                self.render_home_bg_only(fb, w, h, texts);
                self.render_folder_view(fb, w, h, texts);
            }
            Screen::HomeEdit => self.render_home_edit(fb, w, h, texts),
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

        // Status bar, HyperIsland & navigation bar (except during bootanim)
        if self.screen != Screen::BootAnim {
            self.render_status_and_nav(fb, w, h, texts);
        }

        // Toast pill
        if let Some((msg, _)) = &self.toast {
            let tr = Rect { x: SCR_X + 36, y: SCR_Y + SCR_H - 96, w: SCR_W - 72, h: 32 };
            fill_round_rect_alpha(fb, w, h, tr.x, tr.y, tr.w, tr.h, 16, 0x101526, 225);
            draw_round_border(fb, w, h, tr.x, tr.y, tr.w, tr.h, 16, 0x99C8FF);
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
        let main_col = if self.wallpaper_idx == 3 { 0xFFFFFF } else { 0xFFFFFF };
        let sub_col = if self.wallpaper_idx == 3 { 0xD2DDF8 } else { 0xF0F6FF };

        push_shadow_text(
            texts,
            Rect { x: SCR_X + 20, y: SCR_Y + 62, w: SCR_W - 40, h: 24 },
            &format!("{}  ·  18°C Slonecznie", self.date_str),
            sub_col,
            14,
            false,
            TextAlign::Center,
        );
        push_shadow_text(
            texts,
            Rect { x: SCR_X + 20, y: SCR_Y + 86, w: SCR_W - 40, h: 86 },
            &time_s,
            main_col,
            72,
            false,
            TextAlign::Center,
        );

        // HyperOS 4 Magazine frosted notification card
        let notif = Rect { x: SCR_X + 20, y: SCR_Y + 468, w: SCR_W - 40, h: 74 };
        fill_round_rect_alpha(fb, w, h, notif.x, notif.y, notif.w, notif.h, 22, 0xF5F8FF, 195);
        draw_round_border(fb, w, h, notif.x, notif.y, notif.w, notif.h, 22, 0xFFFFFF);
        fill_round_rect(fb, w, h, notif.x + 14, notif.y + 18, 36, 36, 11, 0x2563EB);
        draw_hyperos_app_artwork(fb, w, h, Rect { x: notif.x + 14, y: notif.y + 18, w: 36, h: 36 }, AppKind::RomAudit);
        texts.push(TextDraw {
            rect: Rect { x: notif.x + 60, y: notif.y + 13, w: notif.w - 74, h: 20 },
            text: "HyperOS 4 · System_launcher 8.01".into(),
            color: 0x111827,
            size: 13,
            bold: true,
            align: TextAlign::Left,
            clip_to_screen: true,
        });
        texts.push(TextDraw {
            rect: Rect { x: notif.x + 60, y: notif.y + 35, w: notif.w - 74, h: 24 },
            text: format!("MysticalOS 1.0 · {} usunietych apek · r9c-memd", self.manifest.removed_count),
            color: 0x374151,
            size: 11,
            bold: false,
            align: TextAlign::Left,
            clip_to_screen: true,
        });

        // Bottom quick lockscreen buttons (Flashlight & Camera) + swipe pill
        let torch_btn = Rect { x: SCR_X + 28, y: SCR_Y + SCR_H - 94, w: 42, h: 42 };
        fill_round_rect_alpha(fb, w, h, torch_btn.x, torch_btn.y, torch_btn.w, torch_btn.h, 21, 0xFFFFFF, if self.flashlight_on { 220 } else { 95 });
        fill_round_rect(fb, w, h, torch_btn.x + 17, torch_btn.y + 12, 8, 18, 3, if self.flashlight_on { 0xF59E0B } else { 0xFFFFFF });
        self.hits.push(HitRegion { rect: torch_btn, action: HitAction::ToggleFlashlight, long_press_app: None });

        let cam_btn = Rect { x: SCR_X + SCR_W - 70, y: SCR_Y + SCR_H - 94, w: 42, h: 42 };
        fill_round_rect_alpha(fb, w, h, cam_btn.x, cam_btn.y, cam_btn.w, cam_btn.h, 21, 0xFFFFFF, 95);
        fill_circle(fb, w, h, cam_btn.x + 21, cam_btn.y + 21, 9, 0xFFFFFF);
        fill_circle(fb, w, h, cam_btn.x + 21, cam_btn.y + 21, 5, 0x1F2937);
        self.hits.push(HitRegion { rect: cam_btn, action: HitAction::OpenApp(AppKind::Camera), long_press_app: None });

        let unlock_btn = Rect { x: SCR_X + 84, y: SCR_Y + SCR_H - 94, w: SCR_W - 168, h: 42 };
        fill_round_rect_alpha(fb, w, h, unlock_btn.x, unlock_btn.y, unlock_btn.w, unlock_btn.h, 21, 0xFFFFFF, 105);
        draw_round_border(fb, w, h, unlock_btn.x, unlock_btn.y, unlock_btn.w, unlock_btn.h, 21, 0xFFFFFF);
        push_shadow_text(
            texts,
            unlock_btn,
            "Odblokuj >",
            0xFFFFFF,
            14,
            true,
            TextAlign::Center,
        );
        self.hits.push(HitRegion {
            rect: unlock_btn,
            action: HitAction::GoScreen(Screen::Home),
            long_press_app: None,
        });
    }

    fn render_home_bg_only(&self, fb: &mut [u32], w: i32, h: i32, texts: &mut Vec<TextDraw>) {
        // Authentic borderless HyperOS 4 Weather & Clock widget (no heavy dark box / RAM header)
        let wx = SCR_X + 20;
        let wy = SCR_Y + STATUS_H + 14;
        let time_s = format!("{:02}:{:02}", self.clock_hh, self.clock_mm);

        push_shadow_text(
            texts,
            Rect { x: wx, y: wy, w: 150, h: 48 },
            &time_s,
            0xFFFFFF,
            42,
            false,
            TextAlign::Left,
        );
        push_shadow_text(
            texts,
            Rect { x: wx + 2, y: wy + 50, w: 180, h: 18 },
            &format!("{}  ·  Poznan", self.date_str),
            0xF4F8FF,
            12,
            false,
            TextAlign::Left,
        );

        // Right-side weather icon + temp
        draw_weather_sun_cloud(fb, w, h, SCR_X + SCR_W - 76, wy + 8);
        push_shadow_text(
            texts,
            Rect { x: SCR_X + SCR_W - 126, y: wy + 44, w: 106, h: 24 },
            "18°C Slonecznie",
            0xFFFFFF,
            12,
            true,
            TextAlign::Right,
        );
    }

    fn render_home(&mut self, fb: &mut [u32], w: i32, h: i32, texts: &mut Vec<TextDraw>) {
        self.render_home_bg_only(fb, w, h, texts);

        let tiles = self.compute_grid();
        let max_y = SCR_Y + SCR_H - NAV_H - 108;
        let dock_kinds = [AppKind::Phone, AppKind::Messages, AppKind::DroidIfy, AppKind::Camera];

        for pt in tiles {
            let app = self.apps[pt.app_idx].clone();
            // Keep dock apps in dock only unless user resized them as big tile
            if dock_kinds.contains(&app.kind) && pt.c_span == 1 && pt.r_span == 1 {
                continue;
            }
            if pt.rect.y + pt.rect.h > max_y {
                continue;
            }

            if pt.app_idx == 0 && pt.c_span == 2 && pt.r_span == 2 {
                // Authentic HyperOS 4 2x2 Enlarged Super Folder (3x3 mini-icons inside frosted glass)
                fill_round_rect_alpha(fb, w, h, pt.rect.x, pt.rect.y, pt.rect.w, pt.rect.h, 24, 0xF2F7FF, 165);
                draw_round_border(fb, w, h, pt.rect.x, pt.rect.y, pt.rect.w, pt.rect.h, 24, 0xFFFFFF);

                let pad = 10;
                let inner_w = pt.rect.w - pad * 2;
                let inner_h = pt.rect.h - 28;
                let cw = inner_w / 3;
                let ch = inner_h / 3;
                let mini_sz = ((cw.min(ch) - 6) * self.icon_scale / 100).clamp(16, 36);
                let folder_indices = [5usize, 6, 7, 8, 9, 10, 11, 1];
                for slot in 0..9 {
                    let sc = (slot as i32) % 3;
                    let sr = (slot as i32) / 3;
                    let mx = pt.rect.x + pad + sc * cw + (cw - mini_sz) / 2;
                    let my = pt.rect.y + 8 + sr * ch + (ch - mini_sz) / 2;
                    let mr = Rect { x: mx, y: my, w: mini_sz, h: mini_sz };
                    if slot < folder_indices.len() {
                        if let Some(sub) = self.apps.get(folder_indices[slot]) {
                            draw_shaped_app_icon(fb, w, h, mr, sub.color1, sub.color2, self.icon_shape);
                            draw_hyperos_app_artwork(fb, w, h, mr, sub.kind);
                        }
                    } else {
                        // 9th mini slot shows 2x2 sub-dots like HyperOS 4 folder expand badge
                        fill_round_rect_alpha(fb, w, h, mr.x, mr.y, mr.w, mr.h, 8, 0xCBD5E1, 190);
                        let d_sz = (mini_sz / 4).max(3);
                        for dr in 0..2 {
                            for dc in 0..2 {
                                fill_circle(
                                    fb,
                                    w,
                                    h,
                                    mr.x + mr.w / 3 + dc * (mr.w / 3),
                                    mr.y + mr.h / 3 + dr * (mr.h / 3),
                                    d_sz / 2 + 1,
                                    0x475569,
                                );
                            }
                        }
                    }
                }
                if self.show_labels {
                    push_shadow_text(
                        texts,
                        Rect { x: pt.rect.x + 4, y: pt.rect.y + pt.rect.h - 19, w: pt.rect.w - 8, h: 16 },
                        &app.title,
                        0xFFFFFF,
                        11,
                        false,
                        TextAlign::Center,
                    );
                }
                self.hits.push(HitRegion {
                    rect: pt.rect,
                    action: HitAction::OpenFolder,
                    long_press_app: Some(pt.app_idx),
                });
                continue;
            }

            let is_large = pt.c_span > 1 || pt.r_span > 1;
            if is_large {
                fill_round_rect_alpha(fb, w, h, pt.rect.x, pt.rect.y, pt.rect.w, pt.rect.h, 20, 0xF2F7FF, 165);
                draw_round_border(fb, w, h, pt.rect.x, pt.rect.y, pt.rect.w, pt.rect.h, 20, 0xFFFFFF);
            }

            draw_shaped_app_icon(fb, w, h, pt.icon_rect, app.color1, app.color2, self.icon_shape);
            draw_hyperos_app_artwork(fb, w, h, pt.icon_rect, app.kind);

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
                        x: pt.rect.x - 2,
                        y: pt.icon_rect.y + pt.icon_rect.h + 2,
                        w: pt.rect.w + 4,
                        h: 18,
                    }
                };
                push_shadow_text(
                    texts,
                    lbl_rect,
                    &app.title,
                    if is_large { 0x111827 } else { 0xFFFFFF },
                    if is_large { 12 } else { 11 },
                    is_large,
                    if pt.c_span == 2 && pt.r_span == 1 { TextAlign::Left } else { TextAlign::Center },
                );
            }

            self.hits.push(HitRegion {
                rect: pt.rect,
                action: HitAction::OpenApp(app.kind),
                long_press_app: Some(pt.app_idx),
            });
        }

        // Page indicator dots + frosted HyperOS 4 Search / Edit pills above dock
        let pill_y = SCR_Y + SCR_H - NAV_H - 102;
        fill_circle(fb, w, h, SCR_X + SCR_W / 2 - 12, pill_y - 7, 3, 0xFFFFFF);
        fill_circle(fb, w, h, SCR_X + SCR_W / 2, pill_y - 7, 2, 0xBFD7FF);
        fill_circle(fb, w, h, SCR_X + SCR_W / 2 + 12, pill_y - 7, 2, 0xBFD7FF);

        let search_pill = Rect { x: SCR_X + SCR_W / 2 - 86, y: pill_y, w: 84, h: 22 };
        fill_round_rect_alpha(fb, w, h, search_pill.x, search_pill.y, search_pill.w, search_pill.h, 11, 0xFFFFFF, 115);
        draw_round_border(fb, w, h, search_pill.x, search_pill.y, search_pill.w, search_pill.h, 11, 0xFFFFFF);
        push_shadow_text(texts, search_pill, "Szukaj", 0xFFFFFF, 11, false, TextAlign::Center);
        self.hits.push(HitRegion { rect: search_pill, action: HitAction::OpenApp(AppKind::RomAudit), long_press_app: None });

        let edit_pill = Rect { x: SCR_X + SCR_W / 2 + 4, y: pill_y, w: 84, h: 22 };
        fill_round_rect_alpha(fb, w, h, edit_pill.x, edit_pill.y, edit_pill.w, edit_pill.h, 11, 0xFFFFFF, 115);
        draw_round_border(fb, w, h, edit_pill.x, edit_pill.y, edit_pill.w, edit_pill.h, 11, 0xFFFFFF);
        push_shadow_text(texts, edit_pill, "Edytuj", 0xFFFFFF, 11, false, TextAlign::Center);
        self.hits.push(HitRegion { rect: edit_pill, action: HitAction::GoScreen(Screen::HomeEdit), long_press_app: None });

        // Authentic HyperOS 4 Frosted Glass Pill Dock (4 icons, no text labels)
        let dock = Rect { x: SCR_X + 14, y: SCR_Y + SCR_H - NAV_H - 72, w: SCR_W - 28, h: 64 };
        fill_round_rect_alpha(fb, w, h, dock.x, dock.y, dock.w, dock.h, 24, 0xF5FAFF, 115);
        draw_round_border(fb, w, h, dock.x, dock.y, dock.w, dock.h, 24, 0xFFFFFF);

        let dock_indices = [12usize, 13, 14, 15]; // Telefon, Wiadomosci, Droid-ify, Aparat
        let slot_w = dock.w / 4;
        let dock_icon_sz = ((42 * self.icon_scale) / 100).clamp(24, 50);
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
                draw_hyperos_app_artwork(fb, w, h, ir, app.kind);
                self.hits.push(HitRegion {
                    rect: Rect { x: sx, y: dock.y, w: slot_w, h: dock.h },
                    action: HitAction::OpenApp(app.kind),
                    long_press_app: Some(app_idx),
                });
            }
        }
    }

    fn render_folder_view(&mut self, fb: &mut [u32], w: i32, h: i32, texts: &mut Vec<TextDraw>) {
        blend_rect(fb, w, h, SCR_X, SCR_Y, SCR_W, SCR_H, 0x0B1528, 125);
        push_shadow_text(
            texts,
            Rect { x: SCR_X + 20, y: SCR_Y + 150, w: SCR_W - 40, h: 34 },
            "Narzedzia HyperOS",
            0xFFFFFF,
            22,
            false,
            TextAlign::Center,
        );

        let card = Rect { x: SCR_X + 26, y: SCR_Y + 196, w: SCR_W - 52, h: 310 };
        fill_round_rect_alpha(fb, w, h, card.x, card.y, card.w, card.h, 28, 0xF4F8FF, 205);
        draw_round_border(fb, w, h, card.x, card.y, card.w, card.h, 28, 0xFFFFFF);

        let folder_indices = [5usize, 6, 7, 8, 9, 10, 11, 1, 2];
        let cw = (card.w - 24) / 3;
        let ch = (card.h - 24) / 3;
        let isz = ((44 * self.icon_scale) / 100).clamp(28, 56);
        for (slot, &app_idx) in folder_indices.iter().enumerate() {
            if let Some(app) = self.apps.get(app_idx).cloned() {
                let c = (slot as i32) % 3;
                let r = (slot as i32) / 3;
                let rx = card.x + 12 + c * cw;
                let ry = card.y + 12 + r * ch;
                let ir = Rect { x: rx + (cw - isz) / 2, y: ry + 8, w: isz, h: isz };
                draw_shaped_app_icon(fb, w, h, ir, app.color1, app.color2, self.icon_shape);
                draw_hyperos_app_artwork(fb, w, h, ir, app.kind);
                texts.push(TextDraw {
                    rect: Rect { x: rx + 2, y: ry + isz + 12, w: cw - 4, h: 18 },
                    text: app.title,
                    color: 0x1E293B,
                    size: 11,
                    bold: false,
                    align: TextAlign::Center,
                    clip_to_screen: true,
                });
                self.hits.push(HitRegion {
                    rect: Rect { x: rx, y: ry, w: cw, h: ch },
                    action: HitAction::OpenApp(app.kind),
                    long_press_app: Some(app_idx),
                });
            }
        }

        let close_b = Rect { x: SCR_X + 100, y: SCR_Y + 528, w: SCR_W - 200, h: 36 };
        fill_round_rect_alpha(fb, w, h, close_b.x, close_b.y, close_b.w, close_b.h, 18, 0xFFFFFF, 170);
        texts.push(TextDraw { rect: close_b, text: "Zamknij folder".into(), color: 0x1E293B, size: 12, bold: true, align: TextAlign::Center, clip_to_screen: true });
        self.hits.push(HitRegion { rect: close_b, action: HitAction::GoScreen(Screen::Home), long_press_app: None });
    }

    fn render_home_edit(&mut self, fb: &mut [u32], w: i32, h: i32, texts: &mut Vec<TextDraw>) {
        // Authentic HyperOS 4 Home Pinch/Edit Mode: scaled preview card + 4 bottom tools
        blend_rect(fb, w, h, SCR_X, SCR_Y, SCR_W, SCR_H, 0x091124, 95);
        push_shadow_text(
            texts,
            Rect { x: SCR_X + 20, y: SCR_Y + STATUS_H + 14, w: SCR_W - 40, h: 24 },
            "Edycja ekranu glownego · HyperOS 4",
            0xFFFFFF,
            14,
            true,
            TextAlign::Center,
        );

        let card = Rect { x: SCR_X + 54, y: SCR_Y + 86, w: SCR_W - 108, h: 492 };
        draw_hyperos_wallpaper_rect(fb, w, h, card, self.wallpaper_idx);
        draw_round_border(fb, w, h, card.x, card.y, card.w, card.h, 26, 0xFFFFFF);
        push_shadow_text(
            texts,
            Rect { x: card.x + 16, y: card.y + 20, w: 120, h: 34 },
            &format!("{:02}:{:02}", self.clock_hh, self.clock_mm),
            0xFFFFFF,
            28,
            false,
            TextAlign::Left,
        );
        // Mini 2x2 folder + 4x4 grid preview inside edit card
        fill_round_rect_alpha(fb, w, h, card.x + 16, card.y + 82, 102, 102, 18, 0xF2F7FF, 175);
        for s in 0..4 {
            let ix = card.x + 128 + (s % 2) * 52;
            let iy = card.y + 86 + (s / 2) * 50;
            let ir = Rect { x: ix, y: iy, w: 38, h: 38 };
            if let Some(app) = self.apps.get(1 + s as usize) {
                draw_shaped_app_icon(fb, w, h, ir, app.color1, app.color2, self.icon_shape);
                draw_hyperos_app_artwork(fb, w, h, ir, app.kind);
            }
        }
        let mini_dock = Rect { x: card.x + 14, y: card.y + card.h - 54, w: card.w - 28, h: 40 };
        fill_round_rect_alpha(fb, w, h, mini_dock.x, mini_dock.y, mini_dock.w, mini_dock.h, 16, 0xFFFFFF, 115);

        self.hits.push(HitRegion { rect: card, action: HitAction::GoScreen(Screen::Home), long_press_app: None });

        // Bottom 4-item HyperOS 4 Edit Toolbar
        let bar = Rect { x: SCR_X + 12, y: SCR_Y + SCR_H - NAV_H - 92, w: SCR_W - 24, h: 76 };
        fill_round_rect_alpha(fb, w, h, bar.x, bar.y, bar.w, bar.h, 22, 0xF4F7FF, 225);
        let bw = bar.w / 4;
        let items = [
            ("Tapety", HitAction::SetWallpaper((self.wallpaper_idx + 1) % 4), 0x3B82F6),
            ("Widzety", HitAction::OpenIconMenu(0), 0x10B981),
            ("Ikony", HitAction::GoScreen(Screen::IconEditor), 0x6366F1),
            ("Gotowe", HitAction::GoScreen(Screen::Home), 0x0EA5E9),
        ];
        for (i, (lbl, act, col)) in items.iter().enumerate() {
            let bx = bar.x + (i as i32) * bw;
            let ic = Rect { x: bx + (bw - 34) / 2, y: bar.y + 10, w: 34, h: 34 };
            fill_round_rect(fb, w, h, ic.x, ic.y, ic.w, ic.h, 12, *col);
            texts.push(TextDraw {
                rect: Rect { x: bx + 2, y: bar.y + 48, w: bw - 4, h: 20 },
                text: (*lbl).into(),
                color: 0x1E293B,
                size: 11,
                bold: true,
                align: TextAlign::Center,
                clip_to_screen: true,
            });
            self.hits.push(HitRegion {
                rect: Rect { x: bx, y: bar.y, w: bw, h: bar.h },
                action: *act,
                long_press_app: None,
            });
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
        // Live icon preview strip above bottom sheet (shows authentic HyperOS artwork icons)
        let prev_box = Rect { x: SCR_X + 16, y: SCR_Y + 124, w: SCR_W - 32, h: 112 };
        fill_round_rect_alpha(fb, w, h, prev_box.x, prev_box.y, prev_box.w, prev_box.h, 22, 0xF3F7FF, 185);
        draw_round_border(fb, w, h, prev_box.x, prev_box.y, prev_box.w, prev_box.h, 22, 0xFFFFFF);
        texts.push(TextDraw {
            rect: Rect { x: prev_box.x + 10, y: prev_box.y + 6, w: prev_box.w - 20, h: 16 },
            text: format!("PODGLAD IKON ({}% · {})", self.icon_scale, self.icon_shape.name()),
            color: 0x1D4ED8,
            size: 11,
            bold: true,
            align: TextAlign::Center,
            clip_to_screen: true,
        });
        let p_sz = ((42 * self.icon_scale) / 100).clamp(24, 64);
        let preview_indices = [1usize, 2, 12, 15]; // Ustawienia, Galeria, Telefon, Aparat
        for (i, &app_idx) in preview_indices.iter().enumerate() {
            let app = &self.apps[app_idx];
            let slot_w = prev_box.w / 4;
            let ix = prev_box.x + (i as i32) * slot_w + (slot_w - p_sz) / 2;
            let iy = prev_box.y + 24 + (62 - p_sz) / 2;
            let ir = Rect { x: ix, y: iy, w: p_sz, h: p_sz };
            draw_shaped_app_icon(fb, w, h, ir, app.color1, app.color2, self.icon_shape);
            draw_hyperos_app_artwork(fb, w, h, ir, app.kind);
            if self.show_labels {
                texts.push(TextDraw {
                    rect: Rect { x: prev_box.x + (i as i32) * slot_w + 2, y: prev_box.y + 88, w: slot_w - 4, h: 16 },
                    text: app.title.clone(),
                    color: 0x1E293B,
                    size: 10,
                    bold: false,
                    align: TextAlign::Center,
                    clip_to_screen: true,
                });
            }
        }

        // Bottom Sheet HyperOS 4 + ColorOS 17 Customizer
        let sheet = Rect { x: SCR_X, y: SCR_Y + 248, w: SCR_W, h: SCR_H - 248 - NAV_H };
        let sh_bg = if self.dark_mode { 0x161D30 } else { 0xF5F7FC };
        let sh_fg = if self.dark_mode { 0xFFFFFF } else { 0x111827 };
        let sh_sub = if self.dark_mode { 0xA8B8DE } else { 0x475569 };
        let sh_pill = if self.dark_mode { 0x26314D } else { 0xE2E8F5 };
        fill_round_rect(fb, w, h, sheet.x, sheet.y, sheet.w, sheet.h + 24, 26, sh_bg);
        draw_round_border(fb, w, h, sheet.x, sheet.y, sheet.w, sheet.h + 24, 26, 0xFFFFFF);

        texts.push(TextDraw {
            rect: Rect { x: sheet.x + 16, y: sheet.y + 12, w: sheet.w - 32, h: 24 },
            text: "Ikony HyperOS 4 & ColorOS 17".into(),
            color: sh_fg,
            size: 16,
            bold: true,
            align: TextAlign::Left,
            clip_to_screen: true,
        });

        // Slider row
        texts.push(TextDraw {
            rect: Rect { x: sheet.x + 16, y: sheet.y + 46, w: 200, h: 20 },
            text: "Rozmiar ikon aplikacji:".into(),
            color: sh_sub,
            size: 13,
            bold: false,
            align: TextAlign::Left,
            clip_to_screen: true,
        });
        texts.push(TextDraw {
            rect: Rect { x: sheet.x + sheet.w - 90, y: sheet.y + 46, w: 74, h: 20 },
            text: format!("{}%", self.icon_scale),
            color: 0x2563EB,
            size: 14,
            bold: true,
            align: TextAlign::Right,
            clip_to_screen: true,
        });

        let track = Rect { x: sheet.x + 20, y: sheet.y + 74, w: sheet.w - 40, h: 28 };
        draw_slider(fb, w, h, track, (self.icon_scale - 60) as f32 / 90.0, 0x2563EB);
        self.hits.push(HitRegion {
            rect: track,
            action: HitAction::DragIconSlider(track),
            long_press_app: None,
        });

        // Shape row
        texts.push(TextDraw {
            rect: Rect { x: sheet.x + 16, y: sheet.y + 114, w: sheet.w - 32, h: 18 },
            text: "Ksztalt ikon:".into(),
            color: sh_sub,
            size: 12,
            bold: false,
            align: TextAlign::Left,
            clip_to_screen: true,
        });
        let shapes = [IconShape::Rounded, IconShape::Squircle, IconShape::Circle, IconShape::Teardrop];
        let sw = (sheet.w - 44) / 4;
        for (i, sh) in shapes.iter().enumerate() {
            let br = Rect { x: sheet.x + 16 + (i as i32) * (sw + 4), y: sheet.y + 136, w: sw, h: 34 };
            let act = self.icon_shape == *sh;
            fill_round_rect(fb, w, h, br.x, br.y, br.w, br.h, 12, if act { 0x2563EB } else { sh_pill });
            texts.push(TextDraw {
                rect: br,
                text: sh.name().into(),
                color: if act { 0xFFFFFF } else { sh_fg },
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
            fill_round_rect(fb, w, h, r.x, r.y, r.w, r.h, 12, if act { 0x2563EB } else { sh_pill });
            texts.push(TextDraw {
                rect: r,
                text: txt.into(),
                color: if act { 0xFFFFFF } else { sh_fg },
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
            text: "Tapeta HyperOS 4 Liquid Glass:".into(),
            color: sh_sub,
            size: 12,
            bold: false,
            align: TextAlign::Left,
            clip_to_screen: true,
        });
        let wnames = ["Szklo", "Szmaragd", "Zachod", "Obsydian"];
        let wc = [0x4A88E8, 0x20888A, 0xC85A82, 0x1E2944];
        for i in 0..4 {
            let br = Rect { x: sheet.x + 16 + (i as i32) * (sw + 4), y: sheet.y + 256, w: sw, h: 36 };
            fill_round_rect(fb, w, h, br.x, br.y, br.w, br.h, 12, wc[i]);
            if self.wallpaper_idx == i {
                draw_round_border(fb, w, h, br.x, br.y, br.w, br.h, 12, 0xFFFFFF);
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
            text: "Przytrzymaj (lub kliknij PPM) ikone lub folder na pulpicie, aby zmienic kafelek na 1x1, 2x1, 1x2 lub 2x2.".into(),
            color: sh_sub,
            size: 11,
            bold: false,
            align: TextAlign::Left,
            clip_to_screen: true,
        });

        let rst = Rect { x: sheet.x + 16, y: sheet.y + sheet.h - 52, w: 140, h: 40 };
        let ok = Rect { x: sheet.x + 166, y: sheet.y + sheet.h - 52, w: sheet.w - 182, h: 40 };
        fill_round_rect(fb, w, h, rst.x, rst.y, rst.w, rst.h, 14, sh_pill);
        fill_round_rect(fb, w, h, ok.x, ok.y, ok.w, ok.h, 14, 0x2563EB);
        texts.push(TextDraw { rect: rst, text: "Resetuj".into(), color: sh_fg, size: 13, bold: false, align: TextAlign::Center, clip_to_screen: true });
        texts.push(TextDraw { rect: ok, text: "Zastosuj na pulpicie".into(), color: 0xFFFFFF, size: 13, bold: true, align: TextAlign::Center, clip_to_screen: true });
        self.hits.push(HitRegion { rect: rst, action: HitAction::ResetTiles, long_press_app: None });
        self.hits.push(HitRegion { rect: ok, action: HitAction::GoScreen(Screen::Home), long_press_app: None });
    }

    fn render_control_center(&mut self, fb: &mut [u32], w: i32, h: i32, texts: &mut Vec<TextDraw>) {
        // Authentic HyperOS 4 Asymmetric Frosted Glass Control Center
        blend_rect(fb, w, h, SCR_X, SCR_Y, SCR_W, SCR_H, 0x0B152B, 175);

        push_shadow_text(
            texts,
            Rect { x: SCR_X + 20, y: SCR_Y + STATUS_H + 14, w: 220, h: 28 },
            &format!("{:02}:{:02} · {}", self.clock_hh, self.clock_mm, self.date_str),
            0xFFFFFF,
            18,
            true,
            TextAlign::Left,
        );
        let edit_ic = Rect { x: SCR_X + SCR_W - 88, y: SCR_Y + STATUS_H + 12, w: 70, h: 28 };
        fill_round_rect_alpha(fb, w, h, edit_ic.x, edit_ic.y, edit_ic.w, edit_ic.h, 14, 0xFFFFFF, 75);
        texts.push(TextDraw { rect: edit_ic, text: "Zamknij".into(), color: 0xFFFFFF, size: 11, bold: true, align: TextAlign::Center, clip_to_screen: true });
        self.hits.push(HitRegion { rect: edit_ic, action: HitAction::GoScreen(Screen::Home), long_press_app: None });

        let top_y = SCR_Y + STATUS_H + 54;
        let left_w = 176;
        // Left Column: Wi-Fi & Bluetooth big pills + Media player card
        let wifi_r = Rect { x: SCR_X + 16, y: top_y, w: left_w, h: 58 };
        fill_round_rect_alpha(fb, w, h, wifi_r.x, wifi_r.y, wifi_r.w, wifi_r.h, 20, if self.wifi_on { 0x3B82F6 } else { 0xFFFFFF }, if self.wifi_on { 235 } else { 65 });
        texts.push(TextDraw {
            rect: Rect { x: wifi_r.x + 14, y: wifi_r.y + 10, w: wifi_r.w - 28, h: 20 },
            text: "WLAN".into(),
            color: 0xFFFFFF,
            size: 13,
            bold: true,
            align: TextAlign::Left,
            clip_to_screen: true,
        });
        texts.push(TextDraw {
            rect: Rect { x: wifi_r.x + 14, y: wifi_r.y + 30, w: wifi_r.w - 28, h: 18 },
            text: if self.wifi_on { "Dom 5 GHz · Polaczono" } else { "Wylaczone" }.into(),
            color: 0xE5F0FF,
            size: 11,
            bold: false,
            align: TextAlign::Left,
            clip_to_screen: true,
        });
        self.hits.push(HitRegion { rect: wifi_r, action: HitAction::ToggleWifi, long_press_app: None });

        let bt_r = Rect { x: SCR_X + 16, y: top_y + 68, w: left_w, h: 58 };
        fill_round_rect_alpha(fb, w, h, bt_r.x, bt_r.y, bt_r.w, bt_r.h, 20, if self.bt_on { 0x2563EB } else { 0xFFFFFF }, if self.bt_on { 235 } else { 65 });
        texts.push(TextDraw {
            rect: Rect { x: bt_r.x + 14, y: bt_r.y + 10, w: bt_r.w - 28, h: 20 },
            text: "Bluetooth".into(),
            color: 0xFFFFFF,
            size: 13,
            bold: true,
            align: TextAlign::Left,
            clip_to_screen: true,
        });
        texts.push(TextDraw {
            rect: Rect { x: bt_r.x + 14, y: bt_r.y + 30, w: bt_r.w - 28, h: 18 },
            text: if self.bt_on { "Wlaczony · Gotowy" } else { "Wylaczony" }.into(),
            color: 0xE5F0FF,
            size: 11,
            bold: false,
            align: TextAlign::Left,
            clip_to_screen: true,
        });
        self.hits.push(HitRegion { rect: bt_r, action: HitAction::ToggleBt, long_press_app: None });

        // Music player card below Wi-Fi/BT
        let media_r = Rect { x: SCR_X + 16, y: top_y + 136, w: left_w, h: 72 };
        fill_round_rect_alpha(fb, w, h, media_r.x, media_r.y, media_r.w, media_r.h, 20, 0x1E293B, 210);
        texts.push(TextDraw {
            rect: Rect { x: media_r.x + 12, y: media_r.y + 10, w: media_r.w - 24, h: 18 },
            text: "MysticalOS Audio".into(),
            color: 0xFFFFFF,
            size: 12,
            bold: true,
            align: TextAlign::Left,
            clip_to_screen: true,
        });
        texts.push(TextDraw {
            rect: Rect { x: media_r.x + 12, y: media_r.y + 28, w: media_r.w - 24, h: 16 },
            text: if self.island_playing { "Odtwarzanie · HyperIsland" } else { "Wstrzymano" }.into(),
            color: 0x93C5FD,
            size: 10,
            bold: false,
            align: TextAlign::Left,
            clip_to_screen: true,
        });
        let play_b = Rect { x: media_r.x + 12, y: media_r.y + 46, w: 68, h: 20 };
        fill_round_rect_alpha(fb, w, h, play_b.x, play_b.y, play_b.w, play_b.h, 10, 0x3B82F6, 220);
        texts.push(TextDraw { rect: play_b, text: if self.island_playing { "|| Pauza" } else { "> Graj" }.into(), color: 0xFFFFFF, size: 10, bold: true, align: TextAlign::Center, clip_to_screen: true });
        self.hits.push(HitRegion { rect: media_r, action: HitAction::ToggleIslandPlay, long_press_app: None });

        // Right Column: Two Vertical HyperOS 4 Glass Pill Sliders (Brightness & Volume)
        let pill_w = 64;
        let pill_h = 208;
        let btrack = Rect { x: SCR_X + 204, y: top_y, w: pill_w, h: pill_h };
        let vtrack = Rect { x: SCR_X + 278, y: top_y, w: pill_w, h: pill_h };

        draw_vertical_glass_pill(fb, w, h, btrack, (self.brightness - 30) as f32 / 70.0, 0xFFFFFF);
        fill_circle(fb, w, h, btrack.x + pill_w / 2, btrack.y + pill_h - 24, 8, 0xF59E0B);
        texts.push(TextDraw { rect: Rect { x: btrack.x, y: btrack.y + 10, w: pill_w, h: 18 }, text: format!("{}%", self.brightness), color: 0x1E293B, size: 11, bold: true, align: TextAlign::Center, clip_to_screen: true });
        self.hits.push(HitRegion { rect: btrack, action: HitAction::DragBrightnessSlider(btrack), long_press_app: None });

        draw_vertical_glass_pill(fb, w, h, vtrack, self.volume as f32 / 100.0, 0xFFFFFF);
        fill_round_rect(fb, w, h, vtrack.x + pill_w / 2 - 6, vtrack.y + pill_h - 30, 12, 12, 3, 0x2563EB);
        texts.push(TextDraw { rect: Rect { x: vtrack.x, y: vtrack.y + 10, w: pill_w, h: 18 }, text: format!("{}%", self.volume), color: 0x1E293B, size: 11, bold: true, align: TextAlign::Center, clip_to_screen: true });
        self.hits.push(HitRegion { rect: vtrack, action: HitAction::DragVolumeSlider(vtrack), long_press_app: None });

        // Round quick toggle row below (4 circles like HyperOS 4)
        let quick_y = top_y + 226;
        let quick_items = [
            ("Ciemny", self.dark_mode, HitAction::ToggleDark),
            ("Latarka", self.flashlight_on, HitAction::ToggleFlashlight),
            ("Island", self.island_always_on, HitAction::ToggleIslandAlwaysOn),
            ("Ikony", false, HitAction::GoScreen(Screen::IconEditor)),
        ];
        let qslot = (SCR_W - 32) / 4;
        for (i, (lbl, on, act)) in quick_items.iter().enumerate() {
            let cx = SCR_X + 16 + (i as i32) * qslot + qslot / 2;
            let cy = quick_y + 26;
            fill_circle(fb, w, h, cx, cy, 24, if *on { 0x3B82F6 } else { 0x334155 });
            texts.push(TextDraw {
                rect: Rect { x: cx - 34, y: cy + 30, w: 68, h: 16 },
                text: (*lbl).into(),
                color: 0xFFFFFF,
                size: 11,
                bold: *on,
                align: TextAlign::Center,
                clip_to_screen: true,
            });
            self.hits.push(HitRegion {
                rect: Rect { x: cx - 28, y: cy - 26, w: 56, h: 68 },
                action: *act,
                long_press_app: None,
            });
        }

        // Bottom tap anywhere outside to close
        let close_b = Rect { x: SCR_X + 64, y: SCR_Y + SCR_H - 96, w: SCR_W - 128, h: 36 };
        fill_round_rect_alpha(fb, w, h, close_b.x, close_b.y, close_b.w, close_b.h, 18, 0xFFFFFF, 85);
        texts.push(TextDraw { rect: close_b, text: "Zamknij Centrum Kontroli".into(), color: 0xFFFFFF, size: 12, bold: true, align: TextAlign::Center, clip_to_screen: true });
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
        push_shadow_text(
            texts,
            Rect { x: SCR_X + 16, y: SCR_Y + 5, w: 60, h: 18 },
            &format!("{:02}:{:02}", self.clock_hh, self.clock_mm),
            0xFFFFFF,
            12,
            true,
            TextAlign::Left,
        );

        // Right status icons (signal, WiFi, HyperOS 4 battery pill [94])
        let bat_r = Rect { x: SCR_X + SCR_W - 42, y: SCR_Y + 7, w: 26, h: 14 };
        fill_round_rect_alpha(fb, w, h, bat_r.x, bat_r.y, bat_r.w, bat_r.h, 5, 0xFFFFFF, 210);
        texts.push(TextDraw {
            rect: bat_r,
            text: "94".into(),
            color: 0x111827,
            size: 10,
            bold: true,
            align: TextAlign::Center,
            clip_to_screen: true,
        });
        push_shadow_text(
            texts,
            Rect { x: SCR_X + SCR_W - 114, y: SCR_Y + 5, w: 68, h: 18 },
            if self.wifi_on { "5G WiFi" } else { "5G" },
            0xFFFFFF,
            10,
            true,
            TextAlign::Right,
        );

        self.hits.push(HitRegion {
            rect: sb,
            action: HitAction::GoScreen(if self.screen == Screen::ControlCenter { Screen::Home } else { Screen::ControlCenter }),
            long_press_app: None,
        });

        // HyperOS 4 Super Island (Dynamic Island) pill with embedded camera lens on left
        if self.island_always_on {
            if self.island_expanded {
                let card = Rect { x: SCR_X + 14, y: SCR_Y + 4, w: SCR_W - 28, h: 98 };
                fill_round_rect(fb, w, h, card.x, card.y, card.w, card.h, 24, 0x0A0D14);
                draw_round_border(fb, w, h, card.x, card.y, card.w, card.h, 24, 0x334155);

                // Camera lens tucked cleanly in top center-left + album art badge
                fill_round_rect(fb, w, h, card.x + 14, card.y + 16, 46, 46, 12, 0x2563EB);
                fill_circle(fb, w, h, card.x + 37, card.y + 39, 12, 0x60A5FA);
                fill_circle(fb, w, h, card.x + 37, card.y + 39, 5, 0xFFFFFF);

                texts.push(TextDraw {
                    rect: Rect { x: card.x + 70, y: card.y + 14, w: 170, h: 20 },
                    text: "MysticalOS Audio".into(),
                    color: 0xFFFFFF,
                    size: 13,
                    bold: true,
                    align: TextAlign::Left,
                    clip_to_screen: true,
                });
                texts.push(TextDraw {
                    rect: Rect { x: card.x + 70, y: card.y + 34, w: 180, h: 16 },
                    text: "HyperIsland Always-On · 94%".into(),
                    color: 0x93C5FD,
                    size: 10,
                    bold: false,
                    align: TextAlign::Left,
                    clip_to_screen: true,
                });

                let play_r = Rect { x: card.x + 70, y: card.y + 58, w: 86, h: 26 };
                fill_round_rect(fb, w, h, play_r.x, play_r.y, play_r.w, play_r.h, 13, 0x1E293B);
                texts.push(TextDraw {
                    rect: play_r,
                    text: if self.island_playing { "|| Pauza" } else { "> Odtworz" }.into(),
                    color: 0xFFFFFF,
                    size: 11,
                    bold: true,
                    align: TextAlign::Center,
                    clip_to_screen: true,
                });

                let ico_r = Rect { x: card.x + 164, y: card.y + 58, w: 88, h: 26 };
                fill_round_rect(fb, w, h, ico_r.x, ico_r.y, ico_r.w, ico_r.h, 13, 0x2563EB);
                texts.push(TextDraw {
                    rect: ico_r,
                    text: "Ikony >".into(),
                    color: 0xFFFFFF,
                    size: 11,
                    bold: true,
                    align: TextAlign::Center,
                    clip_to_screen: true,
                });

                let close_r = Rect { x: card.x + card.w - 64, y: card.y + 14, w: 48, h: 22 };
                fill_round_rect(fb, w, h, close_r.x, close_r.y, close_r.w, close_r.h, 11, 0x1E293B);
                texts.push(TextDraw { rect: close_r, text: "Zwin".into(), color: 0xCBD5E1, size: 10, bold: true, align: TextAlign::Center, clip_to_screen: true });

                self.hits.push(HitRegion { rect: card, action: HitAction::ToggleIsland, long_press_app: None });
                self.hits.push(HitRegion { rect: play_r, action: HitAction::ToggleIslandPlay, long_press_app: None });
                self.hits.push(HitRegion { rect: ico_r, action: HitAction::GoScreen(Screen::IconEditor), long_press_app: None });
                self.hits.push(HitRegion { rect: close_r, action: HitAction::ToggleIsland, long_press_app: None });
            } else {
                let di = Rect { x: SCR_X + (SCR_W / 2) - 62, y: SCR_Y + 4, w: 124, h: 20 };
                fill_round_rect(fb, w, h, di.x, di.y, di.w, di.h, 10, 0x080B10);
                // Camera lens on left side inside capsule + active music ring + animated equalizer bars
                fill_circle(fb, w, h, di.x + 13, di.y + 10, 5, 0x161E2E);
                fill_circle(fb, w, h, di.x + 13, di.y + 10, 2, 0x38BDF8);
                fill_circle(fb, w, h, di.x + 26, di.y + 10, 4, 0x22C55E);
                for b in 0..3 {
                    let bh = if self.island_playing {
                        4 + (((self.anim_tick / 3 + b as u32 * 2) % 4) as i32) * 2
                    } else {
                        3
                    };
                    fill_rect(fb, w, h, di.x + di.w - 22 + b * 4, di.y + 15 - bh, 2, bh, 0x38BDF8);
                }
                texts.push(TextDraw {
                    rect: Rect { x: di.x + 32, y: di.y, w: di.w - 58, h: di.h },
                    text: "HyperIsland".into(),
                    color: 0xE2E8F0,
                    size: 10,
                    bold: true,
                    align: TextAlign::Center,
                    clip_to_screen: true,
                });
                self.hits.push(HitRegion { rect: di, action: HitAction::ToggleIsland, long_press_app: None });
            }
        } else {
            // Subtle waterdrop lens when island hidden
            fill_circle(fb, w, h, SCR_X + SCR_W / 2, SCR_Y + 11, 7, 0x090B12);
            fill_circle(fb, w, h, SCR_X + SCR_W / 2, SCR_Y + 11, 3, 0x1D2942);
        }

        // Navigation bar bottom (transparent pill over wallpaper on Home, solid in apps)
        let ny = SCR_Y + SCR_H - NAV_H;
        let transparent_nav = self.gesture_nav
            && matches!(
                self.screen,
                Screen::Home | Screen::LockScreen | Screen::FolderView | Screen::HomeEdit | Screen::ControlCenter
            );
        if !transparent_nav {
            fill_rect(fb, w, h, SCR_X, ny, SCR_W, NAV_H, if self.dark_mode { 0x0A0D18 } else { 0x1E293B });
        }
        if self.gesture_nav {
            let pill = Rect { x: SCR_X + 116, y: ny + 15, w: SCR_W - 232, h: 4 };
            fill_round_rect_alpha(fb, w, h, pill.x, pill.y, pill.w, pill.h, 2, 0xFFFFFF, 220);
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
            text: format!("{} · {} · HyperOS 4 Launcher 8.01 + Dynamic Island + ColorOS 17", self.manifest.market_name, self.manifest.base_rom),
            color: 0x00D6FF,
            size: 13,
            bold: false,
            align: TextAlign::Left,
            clip_to_screen: false,
        });

        // Hardware & HyperOS Launcher control row
        let hw_btns = [
            ("Pulpit (Home)", HitAction::Home),
            ("Edytuj Pulpit", HitAction::GoScreen(Screen::HomeEdit)),
            ("HyperIsland", HitAction::ToggleIsland),
            ("Blokada", HitAction::LockToggle),
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
                    let t = (if r.h > r.w {
                        1.0 - ((y - r.y) as f32 / r.h.max(1) as f32)
                    } else {
                        (x - r.x) as f32 / r.w.max(1) as f32
                    })
                    .clamp(0.0, 1.0);
                    self.brightness = (30.0 + t * 70.0).round() as i32;
                    return UiCommand::None;
                }
                HitAction::DragVolumeSlider(r) => {
                    self.active_slider = Some(HitAction::DragVolumeSlider(r));
                    let t = (if r.h > r.w {
                        1.0 - ((y - r.y) as f32 / r.h.max(1) as f32)
                    } else {
                        (x - r.x) as f32 / r.w.max(1) as f32
                    })
                    .clamp(0.0, 1.0);
                    self.volume = (t * 100.0).round() as i32;
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

    pub fn handle_mouse_move(&mut self, x: i32, y: i32) {
        match self.active_slider {
            Some(HitAction::DragIconSlider(r)) => {
                let t = ((x - r.x) as f32 / r.w.max(1) as f32).clamp(0.0, 1.0);
                self.icon_scale = (60.0 + t * 90.0).round() as i32;
            }
            Some(HitAction::DragBrightnessSlider(r)) => {
                let t = (if r.h > r.w {
                    1.0 - ((y - r.y) as f32 / r.h.max(1) as f32)
                } else {
                    (x - r.x) as f32 / r.w.max(1) as f32
                })
                .clamp(0.0, 1.0);
                self.brightness = (30.0 + t * 70.0).round() as i32;
            }
            Some(HitAction::DragVolumeSlider(r)) => {
                let t = (if r.h > r.w {
                    1.0 - ((y - r.y) as f32 / r.h.max(1) as f32)
                } else {
                    (x - r.x) as f32 / r.w.max(1) as f32
                })
                .clamp(0.0, 1.0);
                self.volume = (t * 100.0).round() as i32;
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
                IconShape::Rounded => round_sdf(dx * hw, dy * hh, hw, hh, hw * 0.28) / hw,
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
                if dist > -0.05 {
                    col = blend_px(col, 0xFFFFFF, 55);
                }
                let p = row + xx as usize;
                fb[p] = blend_px(fb[p], col, (cov * 255.0) as u32);
            }
        }
    }
}

fn push_shadow_text(
    texts: &mut Vec<TextDraw>,
    rect: Rect,
    text: &str,
    color: u32,
    size: i32,
    bold: bool,
    align: TextAlign,
) {
    texts.push(TextDraw {
        rect: Rect { x: rect.x, y: rect.y + 1, w: rect.w, h: rect.h },
        text: text.to_string(),
        color: 0x1E2F4F,
        size,
        bold,
        align,
        clip_to_screen: true,
    });
    texts.push(TextDraw {
        rect,
        text: text.to_string(),
        color,
        size,
        bold,
        align,
        clip_to_screen: true,
    });
}

fn draw_hyperos_wallpaper(fb: &mut [u32], w: i32, h: i32, idx: usize) {
    draw_hyperos_wallpaper_rect(
        fb,
        w,
        h,
        Rect { x: SCR_X, y: SCR_Y, w: SCR_W, h: SCR_H },
        idx,
    );
}

fn draw_hyperos_wallpaper_rect(fb: &mut [u32], w: i32, h: i32, r: Rect, idx: usize) {
    let (top_c, mid_c, bot_c, glow_c) = match idx {
        1 => (0xC9F4E8, 0x4BC0B8, 0x16566C, 0xFFFFFF),
        2 => (0xFFE2D4, 0xE882A8, 0x4A2E7C, 0xFFF3EC),
        3 => (0x141C30, 0x263B6B, 0x0C1120, 0x5B8CFF),
        _ => (0xCEE7FF, 0x6AA8F8, 0x224EB3, 0xFFFFFF),
    };

    let x0 = r.x.max(0);
    let y0 = r.y.max(0);
    let x1 = (r.x + r.w).min(w);
    let y1 = (r.y + r.h).min(h);
    let is_card = r.w < SCR_W - 20;

    for yy in y0..y1 {
        let ty = (yy - r.y) as f32 / r.h.max(1) as f32;
        let row = (yy * w) as usize;
        for xx in x0..x1 {
            if is_card {
                let dx = xx as f32 - (r.x as f32 + r.w as f32 * 0.5);
                let dy = yy as f32 - (r.y as f32 + r.h as f32 * 0.5);
                if round_sdf(dx, dy, r.w as f32 * 0.5, r.h as f32 * 0.5, 26.0) > 0.5 {
                    continue;
                }
            }
            let tx = (xx - r.x) as f32 / r.w.max(1) as f32;
            let base = if ty < 0.54 {
                lerp_color(top_c, mid_c, ty / 0.54)
            } else {
                lerp_color(mid_c, bot_c, (ty - 0.54) / 0.46)
            };

            // Organic HyperOS 4 Liquid Glass horizon wave ribbons
            let wave1 = 0.42 + 0.08 * (tx * 3.8 + 0.5).sin();
            let d1 = (ty - wave1).abs();
            let mut col = base;
            if d1 < 0.22 {
                let k = ((1.0 - d1 / 0.22).powi(2) * 140.0) as u32;
                col = blend_px(col, glow_c, k);
            }
            let wave2 = 0.66 + 0.09 * (tx * 3.2 + 2.4).cos();
            let d2 = (ty - wave2).abs();
            if d2 < 0.18 {
                let k = ((1.0 - d2 / 0.18).powi(2) * 90.0) as u32;
                col = blend_px(col, top_c, k);
            }
            fb[row + xx as usize] = col;
        }
    }
}

fn draw_weather_sun_cloud(fb: &mut [u32], w: i32, h: i32, x: i32, y: i32) {
    // Warm HyperOS Weather Sun + fluffy cloud
    fill_circle(fb, w, h, x + 32, y + 14, 11, 0xFBBF24);
    fill_circle(fb, w, h, x + 32, y + 14, 7, 0xFDE68A);
    fill_circle(fb, w, h, x + 16, y + 20, 9, 0xFFFFFF);
    fill_circle(fb, w, h, x + 26, y + 17, 10, 0xFFFFFF);
    fill_circle(fb, w, h, x + 36, y + 21, 8, 0xFFFFFF);
    fill_round_rect(fb, w, h, x + 9, y + 19, 34, 11, 5, 0xFFFFFF);
}

fn draw_vertical_glass_pill(fb: &mut [u32], w: i32, h: i32, r: Rect, norm: f32, fill_col: u32) {
    let t = norm.clamp(0.0, 1.0);
    fill_round_rect_alpha(fb, w, h, r.x, r.y, r.w, r.h, 24, 0xE2E8F0, 95);
    let fh = ((r.h as f32) * t).round() as i32;
    if fh > 16 {
        let fy = r.y + r.h - fh;
        fill_round_rect_alpha(fb, w, h, r.x, fy, r.w, fh, 24, fill_col, 235);
    }
    draw_round_border(fb, w, h, r.x, r.y, r.w, r.h, 24, 0xFFFFFF);
}

fn draw_line_thick(fb: &mut [u32], w: i32, h: i32, x0: f32, y0: f32, x1: f32, y1: f32, rad: f32, col: u32) {
    let min_x = (x0.min(x1) - rad - 1.0).floor().max(0.0) as i32;
    let max_x = (x0.max(x1) + rad + 2.0).ceil().min(w as f32) as i32;
    let min_y = (y0.min(y1) - rad - 1.0).floor().max(0.0) as i32;
    let max_y = (y0.max(y1) + rad + 2.0).ceil().min(h as f32) as i32;
    let vx = x1 - x0;
    let vy = y1 - y0;
    let len2 = (vx * vx + vy * vy).max(0.0001);
    for yy in min_y..max_y {
        let py = yy as f32 + 0.5;
        let row = (yy * w) as usize;
        for xx in min_x..max_x {
            let px = xx as f32 + 0.5;
            let t = (((px - x0) * vx + (py - y0) * vy) / len2).clamp(0.0, 1.0);
            let dx = px - (x0 + vx * t);
            let dy = py - (y0 + vy * t);
            let d = (dx * dx + dy * dy).sqrt();
            if d < rad + 0.7 {
                let cov = (rad + 0.7 - d).clamp(0.0, 1.0);
                let p = row + xx as usize;
                fb[p] = blend_px(fb[p], col, (cov * 255.0) as u32);
            }
        }
    }
}

fn draw_ring(fb: &mut [u32], w: i32, h: i32, cx: f32, cy: f32, r: f32, thick: f32, col: u32) {
    let min_x = (cx - r - thick - 1.0).floor().max(0.0) as i32;
    let max_x = (cx + r + thick + 2.0).ceil().min(w as f32) as i32;
    let min_y = (cy - r - thick - 1.0).floor().max(0.0) as i32;
    let max_y = (cy + r + thick + 2.0).ceil().min(h as f32) as i32;
    let half_t = thick * 0.5;
    for yy in min_y..max_y {
        let dy = yy as f32 + 0.5 - cy;
        let row = (yy * w) as usize;
        for xx in min_x..max_x {
            let dx = xx as f32 + 0.5 - cx;
            let d = ((dx * dx + dy * dy).sqrt() - r).abs();
            if d < half_t + 0.7 {
                let cov = (half_t + 0.7 - d).clamp(0.0, 1.0);
                let p = row + xx as usize;
                fb[p] = blend_px(fb[p], col, (cov * 255.0) as u32);
            }
        }
    }
}

fn draw_hyperos_app_artwork(fb: &mut [u32], w: i32, h: i32, r: Rect, kind: AppKind) {
    if r.w < 12 || r.h < 12 {
        return;
    }
    let s = r.w.min(r.h) as f32;
    let cx = r.x as f32 + r.w as f32 * 0.5;
    let cy = r.y as f32 + r.h as f32 * 0.5;
    let lw = (s * 0.085).max(1.4);

    match kind {
        AppKind::Phone => {
            // White HyperOS handset curve
            draw_line_thick(fb, w, h, cx - s * 0.22, cy - s * 0.14, cx - s * 0.05, cy + s * 0.12, lw * 1.1, 0xFFFFFF);
            draw_line_thick(fb, w, h, cx - s * 0.05, cy + s * 0.12, cx + s * 0.22, cy + s * 0.24, lw * 1.1, 0xFFFFFF);
            fill_circle(fb, w, h, (cx - s * 0.18) as i32, (cy - s * 0.20) as i32, (s * 0.11).max(2.0) as i32, 0xFFFFFF);
            fill_circle(fb, w, h, (cx + s * 0.21) as i32, (cy + s * 0.19) as i32, (s * 0.11).max(2.0) as i32, 0xFFFFFF);
        }
        AppKind::Messages => {
            // White speech bubble with 3 cyan dots
            let bw = (s * 0.62) as i32;
            let bh = (s * 0.46) as i32;
            fill_round_rect(fb, w, h, (cx - bw as f32 * 0.5) as i32, (cy - bh as f32 * 0.55) as i32, bw, bh, (bh / 2).max(3), 0xFFFFFF);
            draw_line_thick(fb, w, h, cx - s * 0.18, cy + s * 0.14, cx - s * 0.24, cy + s * 0.28, lw * 0.9, 0xFFFFFF);
            let dot_r = (s * 0.045).max(1.2) as i32;
            for dx in [-1, 0, 1] {
                fill_circle(fb, w, h, (cx + (dx as f32) * s * 0.13) as i32, (cy - s * 0.02) as i32, dot_r, 0x0284C7);
            }
        }
        AppKind::Camera => {
            // Dark lens + metallic rings + Leica-inspired red/gold dot
            draw_ring(fb, w, h, cx, cy, s * 0.27, lw * 0.9, 0xE2E8F0);
            fill_circle(fb, w, h, cx as i32, cy as i32, (s * 0.19).max(2.0) as i32, 0x0F172A);
            draw_ring(fb, w, h, cx, cy, s * 0.12, lw * 0.6, 0x38BDF8);
            fill_circle(fb, w, h, (cx - s * 0.04) as i32, (cy - s * 0.04) as i32, (s * 0.05).max(1.2) as i32, 0xBAE6FD);
            fill_circle(fb, w, h, (cx + s * 0.27) as i32, (cy - s * 0.25) as i32, (s * 0.055).max(1.3) as i32, 0xF97316);
        }
        AppKind::Gallery => {
            // HyperOS 6-petal colorful rosette on white background
            let colors = [0xEF4444, 0xF97316, 0xEAB308, 0x22C55E, 0x3B82F6, 0xA855F7];
            let pr = (s * 0.12).max(2.0) as i32;
            for (i, &col) in colors.iter().enumerate() {
                let ang = (i as f32) * (PI / 3.0) - PI * 0.5;
                let px = cx + ang.cos() * (s * 0.20);
                let py = cy + ang.sin() * (s * 0.20);
                fill_circle(fb, w, h, px as i32, py as i32, pr, col);
            }
            fill_circle(fb, w, h, cx as i32, cy as i32, (s * 0.08).max(1.5) as i32, 0xFFFFFF);
        }
        AppKind::Settings => {
            // Crisp 8-tooth white gear
            for i in 0..8 {
                let ang = (i as f32) * (PI / 4.0);
                draw_line_thick(
                    fb,
                    w,
                    h,
                    cx + ang.cos() * (s * 0.16),
                    cy + ang.sin() * (s * 0.16),
                    cx + ang.cos() * (s * 0.31),
                    cy + ang.sin() * (s * 0.31),
                    lw * 1.15,
                    0xFFFFFF,
                );
            }
            draw_ring(fb, w, h, cx, cy, s * 0.20, lw * 1.35, 0xFFFFFF);
            fill_circle(fb, w, h, cx as i32, cy as i32, (s * 0.09).max(1.5) as i32, 0x475569);
        }
        AppKind::Clock => {
            // Analog clock dial + hour/minute hands + orange second hand
            fill_circle(fb, w, h, cx as i32, cy as i32, (s * 0.34).max(3.0) as i32, 0xFFFFFF);
            draw_line_thick(fb, w, h, cx, cy, cx - s * 0.12, cy - s * 0.11, lw * 0.85, 0x1E293B);
            draw_line_thick(fb, w, h, cx, cy, cx + s * 0.18, cy - s * 0.16, lw * 0.70, 0x1E293B);
            draw_line_thick(fb, w, h, cx, cy, cx + s * 0.06, cy + s * 0.21, (lw * 0.45).max(1.0), 0xEF4444);
            fill_circle(fb, w, h, cx as i32, cy as i32, (s * 0.045).max(1.2) as i32, 0xEF4444);
        }
        AppKind::Calculator => {
            // Clean math pads + HyperOS orange '=' pill
            let bs = (s * 0.26).max(3.0) as i32;
            let off = (s * 0.18) as i32;
            fill_round_rect(fb, w, h, cx as i32 - off - bs / 2, cy as i32 - off - bs / 2, bs, bs, 3, 0xCBD5E1);
            fill_round_rect(fb, w, h, cx as i32 + off - bs / 2, cy as i32 - off - bs / 2, bs, bs, 3, 0xCBD5E1);
            fill_round_rect(fb, w, h, cx as i32 - off - bs / 2, cy as i32 + off - bs / 2, bs, bs, 3, 0xCBD5E1);
            fill_round_rect(fb, w, h, cx as i32 + off - bs / 2, cy as i32 + off - bs / 2, bs, bs, 3, 0xF97316);
            draw_line_thick(fb, w, h, cx - s * 0.24, cy - s * 0.18, cx - s * 0.12, cy - s * 0.18, 1.2, 0x334155);
            draw_line_thick(fb, w, h, cx - s * 0.18, cy - s * 0.24, cx - s * 0.18, cy - s * 0.12, 1.2, 0x334155);
            draw_line_thick(fb, w, h, cx + s * 0.12, cy - s * 0.18, cx + s * 0.24, cy - s * 0.18, 1.2, 0x334155);
            draw_line_thick(fb, w, h, cx + s * 0.12, cy + s * 0.14, cx + s * 0.24, cy + s * 0.14, 1.2, 0xFFFFFF);
            draw_line_thick(fb, w, h, cx + s * 0.12, cy + s * 0.22, cx + s * 0.24, cy + s * 0.22, 1.2, 0xFFFFFF);
        }
        AppKind::Files => {
            // Clean white folder silhouette
            let fw = (s * 0.58) as i32;
            let fh = (s * 0.42) as i32;
            fill_round_rect(fb, w, h, (cx - fw as f32 * 0.5) as i32, (cy - fh as f32 * 0.58) as i32, fw / 2, fh / 3 + 3, 3, 0xFFF7ED);
            fill_round_rect(fb, w, h, (cx - fw as f32 * 0.5) as i32, (cy - fh as f32 * 0.35) as i32, fw, fh, 5, 0xFFFFFF);
        }
        AppKind::Contacts => {
            // Person avatar glyph
            fill_circle(fb, w, h, cx as i32, (cy - s * 0.14) as i32, (s * 0.14).max(2.0) as i32, 0xFFFFFF);
            fill_round_rect(fb, w, h, (cx - s * 0.26) as i32, (cy + s * 0.05) as i32, (s * 0.52) as i32, (s * 0.24) as i32, (s * 0.12) as i32, 0xFFFFFF);
        }
        AppKind::DroidIfy => {
            // App store bag + down arrow
            let bw = (s * 0.50) as i32;
            let bh = (s * 0.46) as i32;
            fill_round_rect(fb, w, h, (cx - bw as f32 * 0.5) as i32, (cy - bh as f32 * 0.30) as i32, bw, bh, 5, 0xFFFFFF);
            draw_ring(fb, w, h, cx, cy - s * 0.18, s * 0.13, lw * 0.75, 0xFFFFFF);
            draw_line_thick(fb, w, h, cx, cy - s * 0.06, cx, cy + s * 0.20, lw * 0.85, 0x4F46E5);
        }
        AppKind::IconStyle => {
            // 2x2 Flux/ColorOS resizeable tiles icon
            let ts = (s * 0.24).max(3.0) as i32;
            let d = (s * 0.16) as i32;
            fill_round_rect(fb, w, h, cx as i32 - d - ts / 2, cy as i32 - d - ts / 2, ts * 2, ts, 4, 0xFFFFFF);
            fill_round_rect(fb, w, h, cx as i32 - d - ts / 2, cy as i32 + d - ts / 2, ts, ts, 4, 0xE0F2FE);
            fill_round_rect(fb, w, h, cx as i32 + d - ts / 2, cy as i32 + d - ts / 2, ts, ts, 4, 0xFDE047);
        }
        AppKind::RustMonitor => {
            // CPU chip square + memory bar
            let cs = (s * 0.48) as i32;
            fill_round_rect(fb, w, h, (cx - cs as f32 * 0.5) as i32, (cy - cs as f32 * 0.5) as i32, cs, cs, 4, 0xFFFFFF);
            fill_round_rect(fb, w, h, (cx - s * 0.15) as i32, (cy - s * 0.06) as i32, (s * 0.30) as i32, (s * 0.12) as i32, 3, 0x22C55E);
        }
        AppKind::MicroG => {
            draw_ring(fb, w, h, cx, cy, s * 0.26, lw * 1.15, 0xFFFFFF);
            draw_line_thick(fb, w, h, cx, cy, cx + s * 0.25, cy, lw * 1.1, 0xFFFFFF);
        }
        AppKind::RomAudit => {
            // Magnifier + check badge
            draw_ring(fb, w, h, cx - s * 0.05, cy - s * 0.05, s * 0.21, lw * 1.0, 0xFFFFFF);
            draw_line_thick(fb, w, h, cx + s * 0.10, cy + s * 0.10, cx + s * 0.28, cy + s * 0.28, lw * 1.15, 0xFFFFFF);
        }
        AppKind::ImageExplorer => {
            // Layered disk/partition stack
            for dy in [-0.17_f32, 0.0, 0.17] {
                fill_round_rect(
                    fb,
                    w,
                    h,
                    (cx - s * 0.26) as i32,
                    (cy + s * dy - s * 0.06) as i32,
                    (s * 0.52) as i32,
                    (s * 0.12).max(2.0) as i32,
                    3,
                    0xFFFFFF,
                );
            }
        }
    }
}

fn draw_slider(fb: &mut [u32], w: i32, h: i32, r: Rect, norm: f32, accent: u32) {
    let t = norm.clamp(0.0, 1.0);
    let cy = r.y + r.h / 2;
    fill_round_rect(fb, w, h, r.x, cy - 4, r.w, 8, 4, 0x94A3B8);
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

    #[test]
    fn test_hyperos4_screens_and_island() {
        let mut st = EmulatorState::new(include_str!("../default_manifest.json"));
        let mut fb = vec![0u32; (WIN_W * WIN_H) as usize];

        for scr in [
            Screen::LockScreen,
            Screen::Home,
            Screen::FolderView,
            Screen::HomeEdit,
            Screen::IconEditor,
            Screen::ControlCenter,
        ] {
            st.apply_action(HitAction::GoScreen(scr));
            let t = st.render(&mut fb, WIN_W, WIN_H);
            assert!(!t.is_empty());
        }

        st.apply_action(HitAction::GoScreen(Screen::Home));
        assert!(!st.island_expanded);
        st.apply_action(HitAction::ToggleIsland);
        assert!(st.island_expanded);
        let t_isl = st.render(&mut fb, WIN_W, WIN_H);
        assert!(t_isl.iter().any(|x| x.text.contains("HyperIsland Always-On")));
    }
}
