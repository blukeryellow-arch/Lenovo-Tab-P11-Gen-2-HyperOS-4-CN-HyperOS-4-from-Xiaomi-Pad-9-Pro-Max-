#!/usr/bin/env python3
"""Eksperymentalny konwerter / scaffolder APK (AXML + DEX) -> projekt Rust (JNI + NativeActivity).

Co robi realnie:
1. Dekoduje binarny AndroidManifest.xml (AXML): pakiet, wersje, uprawnienia, Activity/Service.
2. Parsuje classes*.dex (format DEX 035-041): stringi, typy, pola, metody, klasy i bytecode Dalvik.
3. Dla prostych metod skalarnych/arytmetycznych Dalvik tlumaczy instrukcje bezposrednio na funkcje w Ruście.
4. Dla klas korzystajacych z API Android Framework / Java / Kotlin generuje mostek JNI (`#[no_mangle]`)
   oraz czytelny szkielet w Ruście z zachowaniem wspolpracy z ART (Java/Kotlin zostaja w APK).

Ograniczenie techniczne (uczciwie komunikowane):
Dowolna zlozona aplikacja Java/Kotlin (GUI View/Compose, refleksja, biblioteki AndroidX/Framework)
nie moze zostac w 100% automatycznie zamieniona na sam kod Rust bez maszyny ART i warstwy JNI.
"""

from __future__ import annotations

import argparse
import dataclasses
import re
import struct
import sys
import zipfile
from pathlib import Path


# ---------------------------------------------------------------------------
# Binary Android XML (AXML) parser
# ---------------------------------------------------------------------------

RES_STRING_POOL_TYPE = 0x0001
RES_XML_TYPE = 0x0003
RES_XML_START_ELEMENT_TYPE = 0x0102


def _read_uleb128(buf: bytes, off: int) -> tuple[int, int]:
    res = 0
    shift = 0
    while off < len(buf):
        b = buf[off]
        off += 1
        res |= (b & 0x7F) << shift
        if (b & 0x80) == 0:
            break
        shift += 7
    return res, off


def _decode_axml_string_pool(buf: bytes, chunk_off: int, chunk_size: int) -> list[str]:
    if chunk_off + 28 > len(buf):
        return []
    _hdr_size = struct.unpack_from("<H", buf, chunk_off + 2)[0]
    string_count, _style_count, flags, strings_start, _styles_start = struct.unpack_from(
        "<5I", buf, chunk_off + 8
    )
    is_utf8 = bool(flags & (1 << 8))
    offsets_base = chunk_off + 28
    data_base = chunk_off + strings_start
    strings: list[str] = []
    for i in range(string_count):
        if offsets_base + (i + 1) * 4 > len(buf):
            strings.append("")
            continue
        str_off = struct.unpack_from("<I", buf, offsets_base + i * 4)[0]
        p = data_base + str_off
        if p >= chunk_off + chunk_size:
            strings.append("")
            continue
        if is_utf8:
            # UTF-16 len then UTF-8 byte len
            _, p = _read_len8(buf, p)
            blen, p = _read_len8(buf, p)
            strings.append(buf[p : p + blen].decode("utf-8", errors="replace"))
        else:
            ulen, p = _read_len16(buf, p)
            strings.append(buf[p : p + ulen * 2].decode("utf-16le", errors="replace"))
    return strings


def _read_len8(buf: bytes, p: int) -> tuple[int, int]:
    v = buf[p]
    p += 1
    if v & 0x80:
        v = ((v & 0x7F) << 8) | buf[p]
        p += 1
    return v, p


def _read_len16(buf: bytes, p: int) -> tuple[int, int]:
    v = struct.unpack_from("<H", buf, p)[0]
    p += 2
    if v & 0x8000:
        v = ((v & 0x7FFF) << 16) | struct.unpack_from("<H", buf, p)[0]
        p += 2
    return v, p


@dataclasses.dataclass
class ManifestInfo:
    package: str = "com.example.converted"
    version_name: str = "1.0"
    version_code: int = 1
    min_sdk: int = 28
    target_sdk: int = 34
    permissions: list[str] = dataclasses.field(default_factory=list)
    activities: list[str] = dataclasses.field(default_factory=list)
    services: list[str] = dataclasses.field(default_factory=list)


def parse_axml_manifest(raw: bytes) -> ManifestInfo:
    info = ManifestInfo()
    if len(raw) < 8:
        return info
    magic = struct.unpack_from("<H", raw, 0)[0]
    if magic != RES_XML_TYPE:
        # Plain text XML fallback (e.g. non-binary manifest)
        txt = raw.decode("utf-8", errors="replace")
        m_pkg = re.search(r'package="([^"]+)"', txt)
        if m_pkg:
            info.package = m_pkg.group(1)
        info.permissions = re.findall(r'<uses-permission[^>]+android:name="([^"]+)"', txt)
        info.activities = re.findall(r'<activity[^>]+android:name="([^"]+)"', txt)
        info.services = re.findall(r'<service[^>]+android:name="([^"]+)"', txt)
        return info

    total_size = struct.unpack_from("<I", raw, 4)[0]
    pos = struct.unpack_from("<H", raw, 2)[0]
    strings: list[str] = []

    while pos + 8 <= min(len(raw), total_size):
        ctype, hdr_size, csize = struct.unpack_from("<HHI", raw, pos)
        if csize < 8 or pos + csize > len(raw):
            break
        if ctype == RES_STRING_POOL_TYPE:
            strings = _decode_axml_string_pool(raw, pos, csize)
        elif ctype == RES_XML_START_ELEMENT_TYPE and pos + 36 <= len(raw):
            elem_off = pos + hdr_size
            if elem_off + 20 <= len(raw):
                _ns_idx, name_idx, attr_start, attr_size, attr_count = struct.unpack_from(
                    "<IIHHH", raw, elem_off
                )
                tag = strings[name_idx] if 0 <= name_idx < len(strings) else ""
                attrs: dict[str, tuple[int, int, str]] = {}
                a_off = elem_off + attr_start
                for i in range(attr_count):
                    if a_off + 20 > pos + csize:
                        break
                    _ans, aname_i, aval_s_i, _res_sz, _zero, val_type, val_data = struct.unpack_from(
                        "<IIIHBBI", raw, a_off
                    )
                    aname = strings[aname_i] if 0 <= aname_i < len(strings) else ""
                    aval = strings[aval_s_i] if 0 <= aval_s_i < len(strings) else ""
                    attrs[aname] = (val_type, val_data, aval)
                    a_off += max(attr_size, 20)

                if tag == "manifest":
                    if "package" in attrs and attrs["package"][2]:
                        info.package = attrs["package"][2]
                    if "versionName" in attrs and attrs["versionName"][2]:
                        info.version_name = attrs["versionName"][2]
                    if "versionCode" in attrs:
                        info.version_code = attrs["versionCode"][1]
                elif tag == "uses-sdk":
                    if "minSdkVersion" in attrs:
                        info.min_sdk = attrs["minSdkVersion"][1] or info.min_sdk
                    if "targetSdkVersion" in attrs:
                        info.target_sdk = attrs["targetSdkVersion"][1] or info.target_sdk
                elif tag == "uses-permission" and "name" in attrs and attrs["name"][2]:
                    info.permissions.append(attrs["name"][2])
                elif tag == "activity" and "name" in attrs and attrs["name"][2]:
                    info.activities.append(attrs["name"][2])
                elif tag == "service" and "name" in attrs and attrs["name"][2]:
                    info.services.append(attrs["name"][2])
        pos += csize
    return info


# ---------------------------------------------------------------------------
# Real DEX parser & minimal Dalvik -> Rust translator
# ---------------------------------------------------------------------------

DALVIK_SIMPLE_OPCODES = {
    0x00: ("nop", 1),
    0x01: ("move", 1),
    0x07: ("move-object", 1),
    0x0E: ("return-void", 1),
    0x0F: ("return", 1),
    0x10: ("return-wide", 1),
    0x11: ("return-object", 1),
    0x12: ("const/4", 1),
    0x13: ("const/16", 2),
    0x14: ("const", 3),
    0x1A: ("const-string", 2),
    0x28: ("goto", 1),
    0x29: ("goto/16", 2),
    0x32: ("if-eq", 2),
    0x33: ("if-ne", 2),
    0x34: ("if-lt", 2),
    0x35: ("if-ge", 2),
    0x36: ("if-gt", 2),
    0x37: ("if-le", 2),
    0x38: ("if-eqz", 2),
    0x39: ("if-nez", 2),
    0x6E: ("invoke-virtual", 3),
    0x6F: ("invoke-super", 3),
    0x70: ("invoke-direct", 3),
    0x71: ("invoke-static", 3),
    0x72: ("invoke-interface", 3),
    0x90: ("add-int", 2),
    0x91: ("sub-int", 2),
    0x92: ("mul-int", 2),
    0x93: ("div-int", 2),
    0x94: ("rem-int", 2),
    0x95: ("and-int", 2),
    0x96: ("or-int", 2),
    0x97: ("xor-int", 2),
    0x98: ("shl-int", 2),
    0x99: ("shr-int", 2),
    0xB0: ("add-int/2addr", 1),
    0xB1: ("sub-int/2addr", 1),
    0xB2: ("mul-int/2addr", 1),
    0xB3: ("div-int/2addr", 1),
    0xD0: ("add-int/lit16", 2),
    0xD1: ("rsub-int", 2),
    0xD2: ("mul-int/lit16", 2),
    0xD3: ("div-int/lit16", 2),
    0xD8: ("add-int/lit8", 2),
    0xD9: ("rsub-int/lit8", 2),
    0xDA: ("mul-int/lit8", 2),
    0xDB: ("div-int/lit8", 2),
}


@dataclasses.dataclass
class DexMethod:
    class_desc: str
    name: str
    params: list[str]
    ret_type: str
    access_flags: int
    registers_size: int
    ins_size: int
    insns: list[int]


@dataclasses.dataclass
class DexClass:
    descriptor: str
    super_desc: str
    methods: list[DexMethod]


def _java_type_to_rust(desc: str) -> str:
    return {
        "V": "()",
        "Z": "bool",
        "B": "i8",
        "S": "i16",
        "C": "u16",
        "I": "i32",
        "J": "i64",
        "F": "f32",
        "D": "f64",
    }.get(desc, "jni::sys::jobject /* " + desc + " */")


def _parse_dex_strings(buf: bytes, count: int, off: int) -> list[str]:
    out: list[str] = []
    for i in range(count):
        str_data_off = struct.unpack_from("<I", buf, off + i * 4)[0]
        _utf16_len, p = _read_uleb128(buf, str_data_off)
        end = buf.find(b"\x00", p)
        if end < 0:
            end = len(buf)
        out.append(buf[p:end].decode("utf-8", errors="replace"))
    return out


def parse_dex_bytes(buf: bytes) -> tuple[list[DexClass], list[tuple[str, str, str]]]:
    if len(buf) < 112 or not buf.startswith(b"dex\n"):
        raise ValueError("Nieprawidlowy naglowek pliku DEX")

    (
        string_ids_size,
        string_ids_off,
        type_ids_size,
        type_ids_off,
        proto_ids_size,
        proto_ids_off,
        _field_ids_size,
        _field_ids_off,
        method_ids_size,
        method_ids_off,
        class_defs_size,
        class_defs_off,
    ) = struct.unpack_from("<12I", buf, 56)

    strings = _parse_dex_strings(buf, string_ids_size, string_ids_off)
    types = [
        strings[struct.unpack_from("<I", buf, type_ids_off + i * 4)[0]]
        for i in range(type_ids_size)
    ]

    protos: list[tuple[list[str], str]] = []
    for i in range(proto_ids_size):
        _shorty, ret_idx, params_off = struct.unpack_from("<III", buf, proto_ids_off + i * 12)
        ret = types[ret_idx]
        params: list[str] = []
        if params_off != 0 and params_off + 4 <= len(buf):
            plen = struct.unpack_from("<I", buf, params_off)[0]
            for j in range(plen):
                tidx = struct.unpack_from("<H", buf, params_off + 4 + j * 2)[0]
                params.append(types[tidx])
        protos.append((params, ret))

    methods_table: list[tuple[str, str, list[str], str]] = []
    for i in range(method_ids_size):
        cidx, pidx, nidx = struct.unpack_from("<HHI", buf, method_ids_off + i * 8)
        params, ret = protos[pidx]
        methods_table.append((types[cidx], strings[nidx], params, ret))

    classes: list[DexClass] = []
    for i in range(class_defs_size):
        (
            c_idx,
            _acc,
            sup_idx,
            _if_off,
            _src_idx,
            _ann_off,
            cdata_off,
            _stat_off,
        ) = struct.unpack_from("<8I", buf, class_defs_off + i * 32)
        cdesc = types[c_idx]
        sdesc = types[sup_idx] if sup_idx != 0xFFFFFFFF and sup_idx < len(types) else ""
        cmethods: list[DexMethod] = []

        if cdata_off != 0 and cdata_off < len(buf):
            p = cdata_off
            sf_sz, p = _read_uleb128(buf, p)
            if_sz, p = _read_uleb128(buf, p)
            dm_sz, p = _read_uleb128(buf, p)
            vm_sz, p = _read_uleb128(buf, p)
            for _ in range(sf_sz + if_sz):
                _, p = _read_uleb128(buf, p)
                _, p = _read_uleb128(buf, p)

            for list_sz in (dm_sz, vm_sz):
                mid = 0
                for _ in range(list_sz):
                    diff, p = _read_uleb128(buf, p)
                    acc, p = _read_uleb128(buf, p)
                    code_off, p = _read_uleb128(buf, p)
                    mid += diff
                    mcls, mname, mparams, mret = methods_table[mid]
                    regs, ins, insns = 0, 0, []
                    if code_off != 0 and code_off + 16 <= len(buf):
                        regs, ins, _outs, _tries, _dbg, insns_sz = struct.unpack_from(
                            "<HHHHI I".replace(" ", ""), buf, code_off
                        )
                        insns_base = code_off + 16
                        if insns_base + insns_sz * 2 <= len(buf):
                            insns = list(struct.unpack_from(f"<{insns_sz}H", buf, insns_base))
                    cmethods.append(
                        DexMethod(
                            class_desc=mcls,
                            name=mname,
                            params=mparams,
                            ret_type=mret,
                            access_flags=acc,
                            registers_size=regs,
                            ins_size=ins,
                            insns=insns,
                        )
                    )
        classes.append(DexClass(descriptor=cdesc, super_desc=sdesc, methods=cmethods))

    all_methods = [(c, n, r) for c, n, _p, r in methods_table]
    return classes, all_methods


def try_translate_dalvik_to_rust(method: DexMethod, method_ids: list[tuple[str, str, str]]) -> tuple[bool, list[str]]:
    """Translate pure scalar Dalvik bytecode to Rust; emit annotated JNI/ART fallback when framework APIs appear."""
    insns = method.insns
    if not insns:
        return False, ["    // brak bytecode (abstrakcyjna lub juz natywna JNI)"]

    # Only translate pure primitive/void linear scalar routines cleanly without branches/objects
    rust_lines: list[str] = []
    if method.registers_size > 0:
        inits = []
        first_param_reg = max(0, method.registers_size - method.ins_size)
        is_static = bool(method.access_flags & 0x0008)
        arg_reg = first_param_reg + (0 if is_static else 1)
        for r in range(method.registers_size):
            if r >= arg_reg and (r - arg_reg) < len(method.params):
                idx = r - arg_reg
                pdesc = method.params[idx]
                if pdesc in ("I", "S", "B", "C", "Z"):
                    inits.append(f"    let mut v{r}: i32 = arg{idx} as i32;")
                    continue
            inits.append(f"    let mut v{r}: i32 = 0;")
        rust_lines.extend(inits)

    pc = 0
    pure_ok = True
    while pc < len(insns):
        w0 = insns[pc]
        op = w0 & 0xFF
        a = (w0 >> 8) & 0xF
        b = (w0 >> 12) & 0xF
        aa = (w0 >> 8) & 0xFF

        if op == 0x00:  # nop
            pc += 1
        elif op == 0x01:  # move vA, vB
            rust_lines.append(f"    v{a} = v{b};")
            pc += 1
        elif op == 0x0E:  # return-void
            rust_lines.append("    return;")
            pc += 1
        elif op == 0x0F:  # return vAA
            if method.ret_type in ("I", "S", "B", "C"):
                rust_lines.append(f"    return v{aa};")
            elif method.ret_type == "Z":
                rust_lines.append(f"    return v{aa} != 0;")
            else:
                pure_ok = False
                rust_lines.append(f"    // return v{aa} (typ {method.ret_type})")
            pc += 1
        elif op == 0x12:  # const/4 vA, #+B
            imm = b - 16 if b >= 8 else b
            rust_lines.append(f"    v{a} = {imm};")
            pc += 1
        elif op == 0x13 and pc + 1 < len(insns):  # const/16 vAA, #+BBBB
            imm = struct.unpack("<h", struct.pack("<H", insns[pc + 1]))[0]
            rust_lines.append(f"    v{aa} = {imm};")
            pc += 2
        elif op == 0x14 and pc + 2 < len(insns):  # const vAA, #+BBBBBBBB
            imm = struct.unpack("<i", struct.pack("<HH", insns[pc + 1], insns[pc + 2]))[0]
            rust_lines.append(f"    v{aa} = {imm};")
            pc += 3
        elif op in (0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97) and pc + 1 < len(insns):
            w1 = insns[pc + 1]
            vB, vC = w1 & 0xFF, (w1 >> 8) & 0xFF
            sym = {0x90: "+", 0x91: "-", 0x92: "*", 0x93: "/", 0x94: "%", 0x95: "&", 0x96: "|", 0x97: "^"}[op]
            if sym in ("/", "%"):
                rust_lines.append(f"    v{aa} = if v{vC} != 0 {{ v{vB} {sym} v{vC} }} else {{ 0 }};")
            else:
                rust_lines.append(f"    v{aa} = v{vB}.wrapping_{'add' if sym=='+' else 'sub' if sym=='-' else 'mul'}(v{vC});" if sym in "+-*" else f"    v{aa} = v{vB} {sym} v{vC};")
            pc += 2
        elif op in (0xB0, 0xB1, 0xB2, 0xB3):
            fn = {0xB0: "wrapping_add", 0xB1: "wrapping_sub", 0xB2: "wrapping_mul", 0xB3: "wrapping_div"}[op]
            rust_lines.append(f"    v{a} = v{a}.{fn}(v{b});")
            pc += 1
        elif op in (0xD0, 0xD2, 0xD3) and pc + 1 < len(insns):
            imm = struct.unpack("<h", struct.pack("<H", insns[pc + 1]))[0]
            fn = {0xD0: "wrapping_add", 0xD2: "wrapping_mul", 0xD3: "wrapping_div"}[op]
            rust_lines.append(f"    v{a} = v{b}.{fn}({imm});")
            pc += 2
        elif op in (0xD8, 0xDA, 0xDB) and pc + 1 < len(insns):
            w1 = insns[pc + 1]
            vB = w1 & 0xFF
            imm = struct.unpack("<b", bytes([(w1 >> 8) & 0xFF]))[0]
            fn = {0xD8: "wrapping_add", 0xDA: "wrapping_mul", 0xDB: "wrapping_div"}[op]
            rust_lines.append(f"    v{aa} = v{vB}.{fn}({imm});")
            pc += 2
        elif op in (0x6E, 0x6F, 0x70, 0x71, 0x72) and pc + 2 < len(insns):
            pure_ok = False
            mid = insns[pc + 1]
            target = method_ids[mid] if mid < len(method_ids) else ("?", "?", "?")
            rust_lines.append(f"    // Dalvik invoke ({DALVIK_SIMPLE_OPCODES[op][0]}): {target[0]}->{target[1]} -> wymaga ART/JNI")
            pc += 3
        else:
            pure_ok = False
            name, width = DALVIK_SIMPLE_OPCODES.get(op, (f"op_0x{op:02x}", 1))
            rust_lines.append(f"    // Nieprzetlumaczony opcode Dalvik @pc={pc}: {name} (wymaga recznego portu lub pozostawienia w Java/Kotlin)")
            pc += width

    if not pure_ok:
        rust_lines.append("    unimplemented!(\"Metoda korzysta z obiektow/API Androida — zostaw klase w Java/Kotlin i wywoluj przez JNI\")")
    return pure_ok, rust_lines


def _safe_ident(s: str) -> str:
    out = re.sub(r"[^a-zA-Z0-9_]", "_", s).strip("_")
    if not out or out[0].isdigit():
        out = "m_" + out
    if out in ("type", "match", "fn", "impl", "mod", "pub", "use", "self", "super", "in", "loop", "ref"):
        out = out + "_fn"
    return out


def convert_apk(apk_path: Path, out_dir: Path, max_classes: int = 80) -> dict[str, int]:
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "src").mkdir(parents=True, exist_ok=True)

    manifest = ManifestInfo()
    all_classes: list[DexClass] = []
    all_methods_ref: list[tuple[str, str, str]] = []
    abis: list[str] = []

    with zipfile.ZipFile(apk_path, "r") as zf:
        names = zf.namelist()
        if "AndroidManifest.xml" in names:
            manifest = parse_axml_manifest(zf.read("AndroidManifest.xml"))
        for n in sorted(names):
            if n.startswith("lib/") and n.endswith(".so"):
                parts = n.split("/")
                if len(parts) >= 3 and parts[1] not in abis:
                    abis.append(parts[1])
            if re.fullmatch(r"classes\d*\.dex", n):
                c_list, m_ref = parse_dex_bytes(zf.read(n))
                all_classes.extend(c_list)
                all_methods_ref.extend(m_ref)

    pkg_rust = _safe_ident(manifest.package.replace(".", "_"))
    translated_pure = 0
    jni_stubs = 0
    mod_lines = [
        "// Wygenerowano automatycznie przez tools/apk2rust.py",
        f"// Zrodlo APK: {apk_path.name} (pakiet {manifest.package} v{manifest.version_name})",
        "#![allow(dead_code, unused_variables, unused_mut, non_snake_case)]",
        "",
    ]

    user_classes = [
        c for c in all_classes
        if not c.descriptor.startswith(("Landroid/", "Landroidx/", "Ljava/", "Lkotlin/", "Lkotlinx/"))
    ][:max_classes]

    for cls in user_classes:
        cls_name = cls.descriptor.strip("L;").replace("/", "_")
        mod_lines.append(f"pub mod {_safe_ident(cls_name)} {{")
        for m in cls.methods:
            if m.name in ("<init>", "<clinit>"):
                continue
            ok, body = try_translate_dalvik_to_rust(m, all_methods_ref)
            # Only emit pure scalar functions directly as callable Rust functions; keep others commented/JNI
            if ok and all(p in ("I", "S", "B", "C", "Z") for p in m.params) and m.ret_type in ("V", "I", "S", "B", "C", "Z"):
                translated_pure += 1
                p_sig = ", ".join(f"arg{idx}: i32" for idx, _ in enumerate(m.params))
                r_sig = "bool" if m.ret_type == "Z" else ("()" if m.ret_type == "V" else "i32")
                mod_lines.append(f"    pub fn {_safe_ident(m.name)}({p_sig}) -> {r_sig} {{")
                for ln in body:
                    mod_lines.append("    " + ln)
                mod_lines.append("    }")
            else:
                jni_stubs += 1
                jni_sym = f"Java_{cls_name.replace('_', '_1')}_{m.name.replace('_', '_1')}"
                mod_lines.append(f"    // Klasa zachowana po stronie Java/Kotlin; mostek JNI: {jni_sym}")
                mod_lines.append(f"    // Sygnatura DEX: ({''.join(m.params)}){m.ret_type}")
                for ln in body[:8]:
                    mod_lines.append(f"    // {ln.strip()}")
        mod_lines.append("}")
        mod_lines.append("")

    (out_dir / "src" / "dex_translated.rs").write_text("\n".join(mod_lines) + "\n", encoding="utf-8")

    lib_rs = f'''#![allow(non_snake_case)]
use std::ffi::c_void;

pub mod dex_translated;

/// Punkt wejscia dla apki hybrydowej (Java/Kotlin zostaje jako warstwa UI + wywoluje logike w Ruście przez JNI)
#[no_mangle]
pub extern "C" fn Java_{pkg_rust}_RustBridge_nativeInit(_env: *mut c_void, _obj: *mut c_void) -> i32 {{
    1
}}

/// Punkt wejscia dla trybu czystego Rust NativeActivity (jesli aplikacja nie uzywa UI Javy)
#[no_mangle]
pub extern "C" fn ANativeActivity_onCreate(
    _activity: *mut c_void,
    _saved_state: *mut c_void,
    _saved_state_size: usize,
) {{
}}
'''
    (out_dir / "src" / "lib.rs").write_text(lib_rs, encoding="utf-8")

    cargo_toml = f'''[package]
name = "{pkg_rust}"
version = "0.1.0"
edition = "2021"

[lib]
name = "{pkg_rust}"
crate-type = ["cdylib"]

[profile.release]
opt-level = "z"
lto = true
strip = true
'''
    (out_dir / "Cargo.toml").write_text(cargo_toml, encoding="utf-8")

    perms = "\n".join(f'    <uses-permission android:name="{p}" />' for p in manifest.permissions[:40])
    manifest_xml = f'''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="{manifest.package}.rust"
    android:versionCode="{manifest.version_code}"
    android:versionName="{manifest.version_name}">
    <uses-sdk android:minSdkVersion="{manifest.min_sdk}" android:targetSdkVersion="{manifest.target_sdk}" />
{perms}
    <application android:label="{manifest.package} (Rust)">
        <activity android:name="android.app.NativeActivity" android:exported="true">
            <meta-data android:name="android.app.lib_name" android:value="{pkg_rust}" />
        </activity>
    </application>
</manifest>
'''
    (out_dir / "AndroidManifest.xml").write_text(manifest_xml, encoding="utf-8")

    report = f"""# Raport konwersji APK -> Rust (`tools/apk2rust.py`)

- **APK:** `{apk_path.name}`
- **Pakiet:** `{manifest.package}` (v{manifest.version_name}, SDK {manifest.min_sdk}..{manifest.target_sdk})
- **Natywne ABI w APK:** `{', '.join(abis) if abis else 'brak (czysta Java/Kotlin)'}`
- **Klasy uzytkownika przeanalizowane:** {len(user_classes)} (z {len(all_classes)} wszystkich klas DEX)
- **Metody skalarne przetlumaczone automatycznie na Rust:** {translated_pure}
- **Metody z API Androida wymagajace warstwy Java/Kotlin + JNI:** {jni_stubs}

## Jak uzyc wygenerowanego projektu
1. Jesli aplikacja ma UI w Javie/Kotlinie: zostaw klasy UI po stronie APK i przenies ciezka logike z `src/dex_translated.rs` do biblioteki `lib{pkg_rust}.so` ladowanej przez `System.loadLibrary("{pkg_rust}")`.
2. Zbuduj na Androida (`arm64-v8a`): `cargo build --release --target aarch64-linux-android` (z linkerem NDK).
"""
    (out_dir / "CONVERSION-REPORT.md").write_text(report, encoding="utf-8")
    return {
        "total_classes": len(all_classes),
        "user_classes": len(user_classes),
        "translated_pure": translated_pure,
        "jni_stubs": jni_stubs,
    }


def _build_synthetic_dex_for_selftest() -> bytes:
    """Build a valid minimal DEX 035 containing class Lapp/Calc; with static method add(II)I."""
    def uleb(n: int) -> bytes:
        out = bytearray()
        while True:
            b = n & 0x7F
            n >>= 7
            if n:
                out.append(b | 0x80)
            else:
                out.append(b)
                break
        return bytes(out)

    strings = ["I", "II", "Lapp/Calc;", "Ljava/lang/Object;", "add"]
    # code_item: regs=2, ins=2, outs=0, tries=0, debug=0, insns_size=2 (add-int v0, v0, v1; return v0)
    code_item = struct.pack("<HHHHI I".replace(" ", ""), 2, 2, 0, 0, 0, 2) + struct.pack("<HH", 0x0090, 0x0100) + struct.pack("<H", 0x000F)
    # Wait: add-int vAA, vBB, vCC is 2 words: 0x0090 (AA=0), 0x0100 (BB=0, CC=1), return v0 is 0x000F -> 3 words!
    code_item = struct.pack("<HHHHII", 2, 2, 0, 0, 0, 3) + struct.pack("<HHH", 0x0090, 0x0100, 0x000F)

    # Assemble sequentially after 112-byte header
    body = bytearray()
    base = 112

    # string_ids (5 * 4), type_ids (2 * 4), proto_ids (1 * 12), method_ids (1 * 8), class_defs (1 * 32)
    str_ids_off = base
    type_ids_off = str_ids_off + len(strings) * 4
    types_list = [0, 2, 3]  # "I", "Lapp/Calc;", "Ljava/lang/Object;"
    proto_ids_off = type_ids_off + len(types_list) * 4
    method_ids_off = proto_ids_off + 12
    class_defs_off = method_ids_off + 8
    data_off = class_defs_off + 32

    cur = data_off
    str_offs = []
    str_blobs = bytearray()
    for s in strings:
        str_offs.append(cur)
        enc = s.encode("utf-8")
        entry = uleb(len(s)) + enc + b"\x00"
        str_blobs.extend(entry)
        cur += len(entry)

    # align 4 for type_list, code_item
    while cur % 4:
        str_blobs.append(0)
        cur += 1
    type_list_off = cur
    type_list_blob = struct.pack("<IHH", 2, 0, 0)  # 2 params: I, I
    cur += len(type_list_blob)
    while cur % 4:
        type_list_blob += b"\x00"
        cur += 1

    code_off = cur
    code_blob = code_item
    cur += len(code_blob)

    cdata_off = cur
    # 0 static fields, 0 inst fields, 1 direct method (static public add -> diff=0, acc=0x0009, code_off), 0 virtual
    cdata_blob = uleb(0) + uleb(0) + uleb(1) + uleb(0) + uleb(0) + uleb(0x0009) + uleb(code_off)
    cur += len(cdata_blob)

    str_ids_blob = b"".join(struct.pack("<I", o) for o in str_offs)
    type_ids_blob = b"".join(struct.pack("<I", i) for i in types_list)
    proto_ids_blob = struct.pack("<III", 1, 0, type_list_off)  # shorty="II"? wait strings[1]="II", ret=type 0 ("I")
    method_ids_blob = struct.pack("<HHI", 1, 0, 4)  # class=type 1 (Lapp/Calc;), proto=0, name=str 4 ("add")
    class_defs_blob = struct.pack("<8I", 1, 0x0001, 2, 0, 0xFFFFFFFF, 0, cdata_off, 0)

    body = str_ids_blob + type_ids_blob + proto_ids_blob + method_ids_blob + class_defs_blob + str_blobs + type_list_blob + code_blob + cdata_blob
    file_size = base + len(body)
    header = struct.pack(
        "<8sI20sIIIIIIIIIIIIIIIIIIII",
        b"dex\n035\x00",
        0,
        b"\x00" * 20,
        file_size,
        112,
        0x12345678,
        0,
        0,
        0,
        len(strings),
        str_ids_off,
        len(types_list),
        type_ids_off,
        1,
        proto_ids_off,
        0,
        0,
        1,
        method_ids_off,
        1,
        class_defs_off,
        len(body) - (data_off - base),
        data_off,
    )
    return header + body


def run_selftest() -> int:
    import tempfile
    dex = _build_synthetic_dex_for_selftest()
    with tempfile.TemporaryDirectory() as td:
        td_p = Path(td)
        apk = td_p / "sample.apk"
        with zipfile.ZipFile(apk, "w") as zf:
            zf.writestr("AndroidManifest.xml", '<manifest package="app.calc"><uses-permission android:name="android.permission.INTERNET"/></manifest>')
            zf.writestr("classes.dex", dex)
            zf.writestr("lib/arm64-v8a/libnative.so", b"\x7fELF")
        out = td_p / "rust_out"
        stats = convert_apk(apk, out)
        code = (out / "src" / "dex_translated.rs").read_text(encoding="utf-8")
        assert stats["translated_pure"] == 1, stats
        assert "wrapping_add" in code, code
        assert (out / "Cargo.toml").is_file()
        assert (out / "src" / "lib.rs").is_file()
        print("apk2rust selftest OK:", stats)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Konwerter/scaffolder APK (AXML + DEX) -> projekt Rust")
    ap.add_argument("--apk", help="Sciezka do pliku .apk")
    ap.add_argument("--out", help="Katalog wyjsciowy projektu Rust")
    ap.add_argument("--max-classes", type=int, default=80)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        return run_selftest()
    if not args.apk or not args.out:
        ap.error("Wymagane --apk i --out (albo --selftest)")
    stats = convert_apk(Path(args.apk), Path(args.out), max_classes=args.max_classes)
    print(f"apk2rust OK: {stats}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
