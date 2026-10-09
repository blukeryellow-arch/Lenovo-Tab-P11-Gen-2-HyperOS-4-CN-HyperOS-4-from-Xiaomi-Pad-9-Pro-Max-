#!/usr/bin/env python3
"""Disasemblacja okolic adresu w ELF (arm64/x86_64) z adnotacjami symboli
z .dynsym/.symtab. Cel: odczytanie dokladnego miejsca crashu z stack trace
initu (pc z unwindera = offset wzgledem bazy modulu; przy PIE z baza 0
= vaddr).

Uzycie: disasm_propertyinit.py <elf> <start_hex> <end_hex> [out.txt]
Przyklad: disasm_propertyinit.py init 0x123800 0x123ad8
"""
import sys

from elftools.elf.elffile import ELFFile
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN, CS_ARCH_X86, CS_MODE_64


def load_symbols(elf):
    """map vaddr -> nazwa (dynsym + symtab, defined i undefined z PLT-ish)"""
    syms = {}
    for secname in (".dynsym", ".symtab"):
        sec = elf.get_section_by_name(secname)
        if sec is None:
            continue
        for s in sec.iter_symbols():
            if s.name and s["st_value"]:
                # zachowaj pierwszy (dynsym ma pierwszenstwo)
                syms.setdefault(s["st_value"], s.name)
    return syms


def vaddr_to_offset(elf, vaddr):
    for seg in elf.iter_segments():
        if seg["p_type"] != "PT_LOAD":
            continue
        if seg["p_vaddr"] <= vaddr < seg["p_vaddr"] + seg["p_filesz"]:
            return vaddr - seg["p_vaddr"] + seg["p_offset"]
    return None


def off_to_vaddr(elf, off):
    for seg in elf.iter_segments():
        if seg["p_type"] != "PT_LOAD":
            continue
        if seg["p_offset"] <= off < seg["p_offset"] + seg["p_filesz"]:
            return off - seg["p_offset"] + seg["p_vaddr"]
    return None


def find_string_xrefs(elf, cs, needle):
    """zwroc listę (string_vaddr, [bloki disasm wokol xref])"""
    f = elf.stream
    f.seek(0)
    data = f.read()
    nb = needle.encode()
    svaddrs = []
    pos = data.find(nb)
    while pos != -1 and len(svaddrs) < 16:
        v = off_to_vaddr(elf, pos)
        if v is not None:
            svaddrs.append(v)
        pos = data.find(nb, pos + 1)
    if not svaddrs:
        return [], ["string %r NIE znaleziony" % needle]
    tsec = elf.get_section_by_name(".text")
    tstart, tdata = tsec["sh_addr"], tsec.data()
    out = ["string %r @ vaddr: %s" % (needle, ", ".join(hex(v) for v in svaddrs))]
    # arm64: sciez adrp(xn,#page) potem add(xd,xn,#imm)
    reg_page, hits = {}, []
    insns = list(cs.disasm(tdata, tstart))
    for idx, i in enumerate(insns):
        if i.mnemonic == "adrp":
            try:
                reg, imm = i.op_str.split(", ")
                reg_page[reg] = int(imm.lstrip("#"), 16)
            except ValueError:
                pass
        elif i.mnemonic == "add":
            parts = [p.strip() for p in i.op_str.split(",")]
            if len(parts) == 3 and parts[0] == parts[1] and parts[1] in reg_page \
                    and parts[2].startswith("#"):
                try:
                    computed = reg_page[parts[1]] + int(parts[2][1:], 16)
                except ValueError:
                    continue
                if computed in svaddrs and idx > 3:
                    hits.append((idx, computed))
        elif i.mnemonic == "lea" and "rip" in i.op_str:
            # x86_64: lea rdi, [rip + 0x...] / [rip - 0x...]
            try:
                raw = i.op_str.split("rip")[1].split("]")[0].replace(" ", "")
                sign = 1
                if raw.startswith("+"):
                    raw = raw[1:]
                elif raw.startswith("-"):
                    sign, raw = -1, raw[1:]
                computed = i.address + i.size + sign * int(raw, 16)
                if computed in svaddrs and idx > 3:
                    hits.append((idx, computed))
            except ValueError:
                pass
    for idx, computed in hits:
        out.append("===== xref -> 0x%x (kontekst -40..+12) =====" % computed)
        for j in insns[max(0, idx - 40):idx + 12]:
            out.append("0x%08x  %-8s %s" % (j.address, j.mnemonic, j.op_str))
    if not hits:
        out.append("(brak xref w .text - sprawdz adrp+ldr lub inny segment)")
    return svaddrs, out


def parse_plt_map(elf):
    """map: adres stuba PLT -> nazwa importu.
    AArch64 PLT stub: adrp x16,#page; ldr x17,[x16,#off]; add x16,x16,#off; br x17
    GOT wpis = page+off; z .rela.plt (r_offset) bierzemy symbol."""
    from capstone import Cs, CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN
    if elf.header["e_machine"] not in ("EM_AARCH64",):
        return {}
    # relocs: GOT vaddr -> nazwa
    import struct as _struct
    reloc = {}
    for secname in (".rela.plt", ".rela.dyn"):
        sec = elf.get_section_by_name(secname)
        if sec is None:
            continue
        symtab = elf.get_section(sec["sh_link"])
        data = sec.data()
        # Elf64_Rela: r_offset, r_info, r_addend (24 B); recznie - sekcja moze
        # byc SHT_ANDROID_RELA i pyelftools zwroci zwykla Section bez API
        for i in range(len(data) // 24):
            r_offset, r_info = _struct.unpack_from("<QQ", data, i * 24)
            rtype = r_info & 0xFFFFFFFF
            if rtype not in (1026, 1025):  # JUMP_SLOT / GLOB_DAT
                continue
            try:
                sym = symtab.get_symbol(r_info >> 32)
            except Exception:
                sym = None
            if sym is not None and sym.name:
                reloc[r_offset] = sym.name
    plt = elf.get_section_by_name(".plt")
    if plt is None:
        return {}
    cs = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)
    out = {}
    base, data = plt["sh_addr"], plt.data()
    page = None
    stub_start = None
    for i in cs.disasm(data, base):
        if i.mnemonic == "adrp":
            try:
                reg, imm = i.op_str.split(", ")
                if reg == "x16":
                    page = int(imm.lstrip("#"), 16)
                    stub_start = i.address
            except ValueError:
                pass
        elif i.mnemonic == "ldr" and page is not None and "x17" in i.op_str:
            try:
                off = int(i.op_str.split("#")[1].rstrip("]"), 16)
                got = page + off
                if got in reloc and stub_start is not None:
                    out[stub_start] = reloc[got]
            except (ValueError, IndexError):
                pass
    return out


def list_imports(elf):
    out = []
    for secname in (".dynsym",):
        sec = elf.get_section_by_name(secname)
        if sec is None:
            continue
        for s in sec.iter_symbols():
            if s.name and s["st_shndx"] == "SHN_UNDEF":
                out.append(s.name)
    return sorted(set(out))


def main():
    if len(sys.argv) >= 3 and sys.argv[2] == "plt":
        path = sys.argv[1]
        out_path = sys.argv[3] if len(sys.argv) > 3 else None
        elf = ELFFile(open(path, "rb"))
        m = parse_plt_map(elf)
        text = "\n".join("0x%x  %s" % (a, n) for a, n in sorted(m.items()))
        text = "PLT stubow: %d\n" % len(m) + text
        print(text)
        if out_path:
            open(out_path, "w").write(text + "\n")
        return 0
    if len(sys.argv) >= 5 and sys.argv[2] == "data":
        # data <start_hex> <end_hex> [out]
        path, start_s, end_s = sys.argv[1], sys.argv[3], sys.argv[4]
        start, end = int(start_s, 16), int(end_s, 16)
        f = open(path, "rb"); elf = ELFFile(f)
        o = vaddr_to_offset(elf, start)
        f.seek(o); blob = f.read(end - start)
        lines = []
        for p in range(0, len(blob), 16):
            chunk = blob[p:p+16]
            hx = " ".join("%02x" % b for b in chunk)
            asc = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
            lines.append("0x%08x  %-48s  %s" % (start+p, hx, asc))
        text = "\n".join(lines)
        print(text)
        if len(sys.argv) > 5:
            open(sys.argv[5], "w").write(text + "\n")
        return 0
    if len(sys.argv) >= 3 and sys.argv[2] == "imports":
        # tryb: disasm_propertyinit.py <elf> imports [out.txt]
        path = sys.argv[1]
        out_path = sys.argv[3] if len(sys.argv) > 3 else None
        elf = ELFFile(open(path, "rb"))
        text = "\n".join(list_imports(elf))
        print(text)
        if out_path:
            open(out_path, "w").write(text + "\n")
        return 0
    if len(sys.argv) >= 4 and sys.argv[2] == "find":
        # tryb: disasm_propertyinit.py <elf> find "<string>" [out.txt]
        path, needle = sys.argv[1], sys.argv[3]
        out_path = sys.argv[4] if len(sys.argv) > 4 else None
        f = open(path, "rb")
        elf = ELFFile(f)
        machine = elf.header["e_machine"]
        if machine in ("EM_AARCH64",):
            cs = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)
        else:
            cs = Cs(CS_ARCH_X86, CS_MODE_64)
        _, blocks = find_string_xrefs(elf, cs, needle)
        text = "\n".join(blocks)
        print(text)
        if out_path:
            open(out_path, "w").write(text + "\n")
        return 0
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    path, start_s, end_s = sys.argv[1], sys.argv[2], sys.argv[3]
    out_path = sys.argv[4] if len(sys.argv) > 4 else None
    start, end = int(start_s, 16), int(end_s, 16)

    f = open(path, "rb")
    elf = ELFFile(f)
    machine = elf.header["e_machine"]
    if machine in ("EM_AARCH64",):
        cs = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)
    elif machine in ("EM_X86_64",):
        cs = Cs(CS_ARCH_X86, CS_MODE_64)
    else:
        print("nieznana arch: %s" % machine)
        return 1
    syms = load_symbols(elf)
    try:
        plt_map = parse_plt_map(elf)
    except Exception:
        plt_map = {}

    lines = []
    lines.append("# %s [%s]; zakres 0x%x-0x%x; symboli: %d"
                 % (path, machine, start, end, len(syms)))
    off = vaddr_to_offset(elf, start)
    if off is None:
        lines.append("BLAD: vaddr 0x%x poza segmentami PT_LOAD" % start)
        print("\n".join(lines))
        return 1
    f.seek(off)
    code = f.read(end - start)
    for i in cs.disasm(code, start):
        note = ""
        # adnotuj cele bl/b (arm64) i call (x86)
        tgt = None
        if i.mnemonic in ("bl", "b", "call"):
            ops = i.op_str.lstrip("#").strip()
            try:
                tgt = int(ops, 16)
            except ValueError:
                pass
        if tgt is not None:
            if plt_map and tgt in plt_map:
                note = "  ; -> PLT:%s" % plt_map[tgt]
            elif tgt in syms:
                note = "  ; -> %s" % syms[tgt]
            else:
                # sprobuj najblizszego symbolu (PLT stub -> GOT -> import)
                near = [v for v in syms if v <= tgt and tgt - v < 0x40]
                if near:
                    note = "  ; ~ %s+0x%x" % (syms[max(near)], tgt - max(near))
        lines.append("0x%08x  %-8s %s%s" % (i.address, i.mnemonic, i.op_str, note))

    text = "\n".join(lines)
    print(text)
    if out_path:
        open(out_path, "w").write(text + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
