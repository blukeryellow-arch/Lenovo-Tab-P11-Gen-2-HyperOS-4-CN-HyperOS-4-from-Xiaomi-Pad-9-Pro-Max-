#![allow(dead_code)]

use std::collections::HashMap;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::Path;

pub trait ReadAt {
    fn size(&self) -> u64;
    fn read_at(&mut self, offset: u64, buf: &mut [u8]) -> Result<(), String>;
}

#[derive(Clone, Debug)]
enum SparseChunkKind {
    Raw { file_off: u64 },
    Fill { val: u32 },
    DontCare,
}

#[derive(Clone, Debug)]
struct SparseExtent {
    virt_off: u64,
    len: u64,
    kind: SparseChunkKind,
}

pub struct SparseDisk {
    file: File,
    total_size: u64,
    extents: Vec<SparseExtent>,
    is_sparse: bool,
}

impl SparseDisk {
    pub fn open(path: &Path) -> Result<Self, String> {
        let mut file = File::open(path).map_err(|e| format!("Nie mozna otworzyc {}: {}", path.display(), e))?;
        let file_len = file.metadata().map_err(|e| format!("metadata: {}", e))?.len();
        if file_len < 28 {
            return Err("Plik jest za maly, aby byc obrazem partycji/super.img".into());
        }
        let mut hdr = [0u8; 28];
        file.read_exact(&mut hdr).map_err(|e| format!("read header: {}", e))?;
        let magic = u32_le(&hdr, 0);
        if magic != 0xED26FF3A {
            return Ok(Self {
                file,
                total_size: file_len,
                extents: Vec::new(),
                is_sparse: false,
            });
        }

        let major = u16_le(&hdr, 4);
        let file_hdr_sz = u16_le(&hdr, 8) as u64;
        let chunk_hdr_sz = u16_le(&hdr, 10) as u64;
        let blk_sz = u32_le(&hdr, 12) as u64;
        let total_blks = u32_le(&hdr, 16) as u64;
        let total_chunks = u32_le(&hdr, 20);
        if major != 1 || file_hdr_sz < 28 || chunk_hdr_sz < 12 || blk_sz == 0 {
            return Err(format!("Nieobslugiwany naglowek Android Sparse (major={}, blk={})", major, blk_sz));
        }

        let mut extents = Vec::with_capacity(total_chunks as usize);
        let mut pos = file_hdr_sz;
        let mut virt_off = 0u64;
        let mut chdr = [0u8; 12];

        for _ in 0..total_chunks {
            file.seek(SeekFrom::Start(pos)).map_err(|e| format!("seek chunk: {}", e))?;
            file.read_exact(&mut chdr).map_err(|e| format!("read chunk: {}", e))?;
            let ctype = u16_le(&chdr, 0);
            let chunk_blks = u32_le(&chdr, 4) as u64;
            let total_sz = u32_le(&chdr, 8) as u64;
            if total_sz < chunk_hdr_sz {
                return Err("Uszkodzony rozmiar chunka sparse".into());
            }
            let vlen = chunk_blks.saturating_mul(blk_sz);
            let data_off = pos + chunk_hdr_sz;
            let data_len = total_sz - chunk_hdr_sz;

            match ctype {
                0xCAC1 => {
                    // RAW
                    extents.push(SparseExtent {
                        virt_off,
                        len: vlen.min(data_len),
                        kind: SparseChunkKind::Raw { file_off: data_off },
                    });
                    virt_off += vlen;
                }
                0xCAC2 => {
                    // FILL
                    let mut fill_b = [0u8; 4];
                    if data_len >= 4 {
                        file.seek(SeekFrom::Start(data_off)).map_err(|e| format!("seek fill: {}", e))?;
                        file.read_exact(&mut fill_b).map_err(|e| format!("read fill: {}", e))?;
                    }
                    extents.push(SparseExtent {
                        virt_off,
                        len: vlen,
                        kind: SparseChunkKind::Fill { val: u32_le(&fill_b, 0) },
                    });
                    virt_off += vlen;
                }
                0xCAC3 => {
                    // DONT_CARE
                    extents.push(SparseExtent {
                        virt_off,
                        len: vlen,
                        kind: SparseChunkKind::DontCare,
                    });
                    virt_off += vlen;
                }
                0xCAC4 => {
                    // CRC32 (no virtual bytes)
                }
                other => {
                    return Err(format!("Nieznany typ chunka sparse: {:#x}", other));
                }
            }
            pos += total_sz;
        }

        let total_size = total_blks.saturating_mul(blk_sz).max(virt_off);
        Ok(Self {
            file,
            total_size,
            extents,
            is_sparse: true,
        })
    }

    pub fn is_sparse(&self) -> bool {
        self.is_sparse
    }
}

impl ReadAt for SparseDisk {
    fn size(&self) -> u64 {
        self.total_size
    }

    fn read_at(&mut self, offset: u64, buf: &mut [u8]) -> Result<(), String> {
        if offset >= self.total_size {
            buf.fill(0);
            return Ok(());
        }
        if !self.is_sparse {
            let avail = (self.total_size - offset).min(buf.len() as u64) as usize;
            self.file.seek(SeekFrom::Start(offset)).map_err(|e| format!("seek raw: {}", e))?;
            self.file.read_exact(&mut buf[..avail]).map_err(|e| format!("read raw: {}", e))?;
            if avail < buf.len() {
                buf[avail..].fill(0);
            }
            return Ok(());
        }

        let mut cursor = 0usize;
        while cursor < buf.len() {
            let cur_off = offset + cursor as u64;
            if cur_off >= self.total_size {
                buf[cursor..].fill(0);
                break;
            }
            let idx = match self.extents.binary_search_by(|e| {
                if cur_off < e.virt_off {
                    std::cmp::Ordering::Greater
                } else if cur_off >= e.virt_off + e.len {
                    std::cmp::Ordering::Less
                } else {
                    std::cmp::Ordering::Equal
                }
            }) {
                Ok(i) => i,
                Err(_) => {
                    buf[cursor] = 0;
                    cursor += 1;
                    continue;
                }
            };
            let ext = &self.extents[idx];
            let in_ext = cur_off - ext.virt_off;
            let take = ((ext.len - in_ext) as usize).min(buf.len() - cursor).max(1);
            match ext.kind {
                SparseChunkKind::Raw { file_off } => {
                    self.file
                        .seek(SeekFrom::Start(file_off + in_ext))
                        .map_err(|e| format!("seek raw ext: {}", e))?;
                    self.file
                        .read_exact(&mut buf[cursor..cursor + take])
                        .map_err(|e| format!("read raw ext: {}", e))?;
                }
                SparseChunkKind::Fill { val } => {
                    let fb = val.to_le_bytes();
                    for i in 0..take {
                        buf[cursor + i] = fb[((in_ext as usize) + i) & 3];
                    }
                }
                SparseChunkKind::DontCare => {
                    buf[cursor..cursor + take].fill(0);
                }
            }
            cursor += take;
        }
        Ok(())
    }
}

#[derive(Clone, Debug)]
pub struct LpExtentMap {
    pub virt_off: u64,
    pub phys_off: u64,
    pub len: u64,
}

#[derive(Clone, Debug)]
pub struct PartitionEntry {
    pub name: String,
    pub size: u64,
    pub fs_kind: String,
    pub extents: Vec<LpExtentMap>,
}

pub struct PartitionView<'a> {
    disk: &'a mut dyn ReadAt,
    size: u64,
    extents: Vec<LpExtentMap>,
}

impl<'a> PartitionView<'a> {
    pub fn new(disk: &'a mut dyn ReadAt, size: u64, extents: Vec<LpExtentMap>) -> Self {
        Self { disk, size, extents }
    }
}

impl<'a> ReadAt for PartitionView<'a> {
    fn size(&self) -> u64 {
        self.size
    }

    fn read_at(&mut self, offset: u64, buf: &mut [u8]) -> Result<(), String> {
        if offset >= self.size {
            buf.fill(0);
            return Ok(());
        }
        let mut cur = 0usize;
        while cur < buf.len() {
            let v = offset + cur as u64;
            if v >= self.size {
                buf[cur..].fill(0);
                break;
            }
            if let Some(ext) = self.extents.iter().find(|e| v >= e.virt_off && v < e.virt_off + e.len) {
                let delta = v - ext.virt_off;
                let take = ((ext.len - delta) as usize).min(buf.len() - cur).max(1);
                if ext.phys_off == u64::MAX {
                    buf[cur..cur + take].fill(0);
                } else {
                    self.disk.read_at(ext.phys_off + delta, &mut buf[cur..cur + take])?;
                }
                cur += take;
            } else {
                buf[cur] = 0;
                cur += 1;
            }
        }
        Ok(())
    }
}

pub fn detect_fs_kind(reader: &mut dyn ReadAt) -> String {
    let mut sb = [0u8; 4100];
    if reader.read_at(0, &mut sb).is_err() {
        return "unknown".into();
    }
    if u32_le(&sb, 1024) == 0xE0F5E1E2 {
        return "erofs".into();
    }
    if u16_le(&sb, 1080) == 0xEF53 {
        return "ext4".into();
    }
    if u32_le(&sb, 4096) == 0x616C4467 {
        return "super".into();
    }
    "unknown".into()
}

pub fn parse_super_partitions(disk: &mut dyn ReadAt) -> Result<Vec<PartitionEntry>, String> {
    // Check geometry @4096, metadata @12288 (or scan up to 512 KiB for 0x414C5030 'ALP0')
    let probe_len = disk.size().min(512 * 1024) as usize;
    let mut probe = vec![0u8; probe_len];
    disk.read_at(0, &mut probe)?;

    let mut m_off = None;
    for off in [12288usize, 8192, 4096, 0] {
        if off + 256 <= probe.len() && u32_le(&probe, off) == 0x414C5030 {
            m_off = Some(off);
            break;
        }
    }
    if m_off.is_none() {
        let mut p = 0usize;
        while p + 256 <= probe.len() {
            if u32_le(&probe, p) == 0x414C5030 {
                m_off = Some(p);
                break;
            }
            p += 4;
        }
    }
    let base = m_off.ok_or_else(|| "Brak metadanych liblp (ALP0) w super.img".to_string())?;
    let header_size = u32_le(&probe, base + 8) as usize;
    let tables_size = u32_le(&probe, base + 44) as usize;
    let tbase = base + header_size;
    if tbase + tables_size > probe.len() {
        return Err("Tablica metadanych liblp wykracza poza bufor".into());
    }

    let p_off = u32_le(&probe, base + 80) as usize;
    let p_cnt = u32_le(&probe, base + 84) as usize;
    let p_esz = u32_le(&probe, base + 88) as usize;

    let e_off = u32_le(&probe, base + 92) as usize;
    let e_cnt = u32_le(&probe, base + 96) as usize;
    let e_esz = u32_le(&probe, base + 100) as usize;

    let mut extents_raw = Vec::with_capacity(e_cnt);
    for i in 0..e_cnt {
        let ep = tbase + e_off + i * e_esz;
        if ep + 24 > probe.len() {
            break;
        }
        extents_raw.push((
            u64_le(&probe, ep),      // num_sectors
            u32_le(&probe, ep + 8),  // target_type (0=LINEAR, 1=ZERO)
            u64_le(&probe, ep + 12), // target_data (sector)
        ));
    }

    let mut parts = Vec::new();
    for i in 0..p_cnt {
        let pp = tbase + p_off + i * p_esz;
        if pp + 52 > probe.len() {
            break;
        }
        let name_end = probe[pp..pp + 36].iter().position(|&b| b == 0).unwrap_or(36);
        let name = String::from_utf8_lossy(&probe[pp..pp + name_end]).to_string();
        let first_ext = u32_le(&probe, pp + 40) as usize;
        let num_ext = u32_le(&probe, pp + 44) as usize;

        let mut ext_maps = Vec::new();
        let mut virt_cur = 0u64;
        for ei in first_ext..(first_ext + num_ext).min(extents_raw.len()) {
            let (sectors, ttype, tdata) = extents_raw[ei];
            let bytes = sectors.saturating_mul(512);
            let phys = if ttype == 0 { tdata.saturating_mul(512) } else { u64::MAX };
            ext_maps.push(LpExtentMap {
                virt_off: virt_cur,
                phys_off: phys,
                len: bytes,
            });
            virt_cur += bytes;
        }

        let mut pv = PartitionView::new(disk, virt_cur, ext_maps.clone());
        let fs_kind = if virt_cur > 0 { detect_fs_kind(&mut pv) } else { "empty".into() };
        parts.push(PartitionEntry {
            name,
            size: virt_cur,
            fs_kind,
            extents: ext_maps,
        });
    }

    Ok(parts)
}

pub fn extract_partition_to_file(
    disk: &mut dyn ReadAt,
    part: &PartitionEntry,
    out_path: &Path,
) -> Result<(), String> {
    let mut pv = PartitionView::new(disk, part.size, part.extents.clone());
    let mut out = File::create(out_path).map_err(|e| format!("create {}: {}", out_path.display(), e))?;
    let mut buf = vec![0u8; 1024 * 1024];
    let mut off = 0u64;
    while off < part.size {
        let chunk = ((part.size - off) as usize).min(buf.len());
        pv.read_at(off, &mut buf[..chunk])?;
        out.write_all(&buf[..chunk]).map_err(|e| format!("write: {}", e))?;
        off += chunk as u64;
    }
    Ok(())
}

// ---------------- EROFS + LZ4 Reader ----------------

#[derive(Clone, Debug)]
pub struct FsEntry {
    pub name: String,
    pub is_dir: bool,
    pub is_symlink: bool,
    pub size: u64,
    pub id: u64,
}

pub struct ErofsMeta {
    pub blk_sz: u64,
    pub blkszbits: u8,
    pub root_nid: u64,
    pub meta_blkaddr: u64,
    pub has_48bit: bool,
    pub volume_name: String,
}

#[derive(Clone, Debug)]
struct ErofsInode {
    nid: u64,
    mode: u16,
    datalayout: u8,
    size: u64,
    inode_sz: u64,
    xattr_sz: u64,
    startblk_or_blocks: u64,
}

impl ErofsMeta {
    pub fn parse(r: &mut dyn ReadAt) -> Result<Self, String> {
        let mut sb = [0u8; 256];
        r.read_at(1024, &mut sb)?;
        if u32_le(&sb, 0) != 0xE0F5E1E2 {
            return Err("Brak magic EROFS".into());
        }
        let blkszbits = sb[12];
        if !(9..=16).contains(&blkszbits) {
            return Err(format!("Niepoprawny blkszbits={}", blkszbits));
        }
        let blk_sz = 1u64 << blkszbits;
        let feature_incompat = u32_le(&sb, 80);
        let has_48bit = (feature_incompat & 0x80) != 0;
        let root_nid = if has_48bit {
            u64_le(&sb, 112)
        } else {
            u16_le(&sb, 14) as u64
        };
        let meta_blkaddr = u32_le(&sb, 40) as u64;
        let vname_end = sb[64..80].iter().position(|&b| b == 0).unwrap_or(16);
        let volume_name = String::from_utf8_lossy(&sb[64..64 + vname_end]).to_string();
        Ok(Self {
            blk_sz,
            blkszbits,
            root_nid,
            meta_blkaddr,
            has_48bit,
            volume_name,
        })
    }

    fn iloc(&self, nid: u64) -> u64 {
        self.meta_blkaddr * self.blk_sz + nid * 32
    }

    fn read_inode(&self, r: &mut dyn ReadAt, nid: u64) -> Result<ErofsInode, String> {
        let off = self.iloc(nid);
        let mut buf = [0u8; 64];
        r.read_at(off, &mut buf)?;
        let i_format = u16_le(&buf, 0);
        let extended = (i_format & 1) != 0;
        let datalayout = ((i_format >> 1) & 7) as u8;
        let xattr_icount = u16_le(&buf, 2);
        let xattr_sz = if xattr_icount == 0 {
            0
        } else {
            12 + ((xattr_icount as u64 - 1) * 4)
        };
        let mode = u16_le(&buf, 4);
        let nb = u16_le(&buf, 6) as u64;

        if !extended {
            let size = u32_le(&buf, 8) as u64;
            let iu = u32_le(&buf, 16) as u64;
            let hi = if self.has_48bit && (i_format & (1 << 4)) != 0 { nb << 32 } else { 0 };
            Ok(ErofsInode {
                nid,
                mode,
                datalayout,
                size,
                inode_sz: 32,
                xattr_sz,
                startblk_or_blocks: iu | hi,
            })
        } else {
            let size = u64_le(&buf, 8);
            let iu = u32_le(&buf, 16) as u64;
            let hi = if self.has_48bit { nb << 32 } else { 0 };
            Ok(ErofsInode {
                nid,
                mode,
                datalayout,
                size,
                inode_sz: 64,
                xattr_sz,
                startblk_or_blocks: iu | hi,
            })
        }
    }

    pub fn read_inode_bytes(&self, r: &mut dyn ReadAt, nid: u64, limit: usize) -> Result<Vec<u8>, String> {
        let ino = self.read_inode(r, nid)?;
        let target_len = (ino.size as usize).min(limit);
        if target_len == 0 {
            return Ok(Vec::new());
        }
        match ino.datalayout {
            0 => {
                // FLAT_PLAIN
                let mut out = vec![0u8; target_len];
                let data_off = ino.startblk_or_blocks * self.blk_sz;
                r.read_at(data_off, &mut out)?;
                Ok(out)
            }
            2 => {
                // FLAT_INLINE
                let mut out = vec![0u8; target_len];
                let full_blks = ino.size / self.blk_sz;
                let full_bytes = (full_blks * self.blk_sz) as usize;
                let head = full_bytes.min(target_len);
                if head > 0 {
                    r.read_at(ino.startblk_or_blocks * self.blk_sz, &mut out[..head])?;
                }
                if target_len > full_bytes {
                    let inline_off = self.iloc(nid) + ino.inode_sz + ino.xattr_sz;
                    r.read_at(inline_off, &mut out[full_bytes..target_len])?;
                }
                Ok(out)
            }
            1 | 3 => {
                // COMPRESSED_FULL (1) or COMPRESSED_COMPACT (3)
                self.read_compressed_inode(r, &ino, target_len)
            }
            other => Err(format!("Nieobslugiwany datalayout EROFS: {}", other)),
        }
    }

    fn read_compressed_inode(&self, r: &mut dyn ReadAt, ino: &ErofsInode, target_len: usize) -> Result<Vec<u8>, String> {
        let base_after = self.iloc(ino.nid) + ino.inode_sz + ino.xattr_sz;
        let mhdr_off = align_up(base_after, 8);
        let mut mhdr = [0u8; 8];
        r.read_at(mhdr_off, &mut mhdr)?;
        let advise = u16_le(&mhdr, 4);
        let alg_byte = mhdr[6];
        let cl_byte = mhdr[7];
        let alg_h1 = alg_byte & 0x0F;
        let alg_h2 = (alg_byte >> 4) & 0x0F;
        let lclusterbits = self.blkszbits + (cl_byte & 0x07);
        let lcluster_sz = 1u64 << lclusterbits;
        let totalidx = ((ino.size + lcluster_sz - 1) / lcluster_sz) as usize;
        if totalidx == 0 {
            return Ok(Vec::new());
        }

        let bigpcl1 = (advise & 2) != 0;
        let bigpcl2 = (advise & 4) != 0;
        let big_pcluster = bigpcl1;
        let compacted_2b = (advise & 1) != 0;
        let ebase = mhdr_off + 8;

        // Read all metadata bytes covering all lcluster indexes
        let max_meta = if ino.datalayout == 1 {
            totalidx * 8 + 16
        } else {
            totalidx * 4 + 64
        };
        let mut meta_buf = vec![0u8; max_meta];
        r.read_at(ebase, &mut meta_buf)?;

        let compacted_4b_initial = (((32 - (ebase % 32)) / 4) & 7) as usize;
        let c2b_cnt = if compacted_2b && compacted_4b_initial < totalidx {
            ((totalidx - compacted_4b_initial) / 16) * 16
        } else {
            0
        };

        let load_lcluster = |lcn: usize| -> Result<(u8, u16, u16, u64, u64), String> {
            // returns (type, clusterofs, delta0_or_1, blkaddr_pblk, cblkcnt)
            if ino.datalayout == 1 {
                let o = lcn * 8;
                let adv = u16_le(&meta_buf, o);
                let ltype = (adv & 3) as u8;
                let cofs = u16_le(&meta_buf, o + 2);
                let raw4 = u32_le(&meta_buf, o + 4);
                if ltype == 2 {
                    let d0 = u16_le(&meta_buf, o + 4);
                    let d1 = u16_le(&meta_buf, o + 6);
                    if (d0 & 0x0800) != 0 {
                        Ok((ltype, lcluster_sz as u16, 1, 0, (d0 & !0x0800) as u64))
                    } else {
                        Ok((ltype, lcluster_sz as u16, d0, 0, d1 as u64))
                    }
                } else {
                    Ok((ltype, cofs, 0, raw4 as u64, 0))
                }
            } else {
                // COMPACT
                let (pack_off, shift, vcnt, idx_in_pack) = if lcn < compacted_4b_initial {
                    ( (lcn / 2) * 8, 2usize, 2usize, lcn % 2 )
                } else if lcn - compacted_4b_initial < c2b_cnt {
                    let k = lcn - compacted_4b_initial;
                    ( compacted_4b_initial * 4 + (k / 16) * 32, 1usize, 16usize, k % 16 )
                } else {
                    let k = lcn - compacted_4b_initial - c2b_cnt;
                    ( compacted_4b_initial * 4 + c2b_cnt * 2 + (k / 2) * 8, 2usize, 2usize, k % 2 )
                };
                let pack_sz = vcnt << shift;
                let pack = &meta_buf[pack_off..pack_off + pack_sz];
                let lobits = (lclusterbits as usize).max(12);
                let encodebits = ((pack_sz - 4) * 8) / vcnt;
                let decode_item = |ii: usize| -> (u16, u8) {
                    let bit_pos = encodebits * ii;
                    let byte_pos = bit_pos / 8;
                    let mut tmp = [0u8; 4];
                    let avail = (pack.len() - byte_pos).min(4);
                    tmp[..avail].copy_from_slice(&pack[byte_pos..byte_pos + avail]);
                    let v = u32::from_le_bytes(tmp) >> (bit_pos & 7);
                    let lo = (v & ((1u32 << lobits) - 1)) as u16;
                    let tp = ((v >> lobits) & 3) as u8;
                    (lo, tp)
                };
                let (lo, ltype) = decode_item(idx_in_pack);
                if ltype == 2 {
                    if (lo & 0x0800) != 0 {
                        return Ok((ltype, lcluster_sz as u16, 1, 0, (lo & !0x0800) as u64));
                    }
                    let d0 = if idx_in_pack + 1 != vcnt {
                        lo
                    } else if idx_in_pack > 0 {
                        let (plo, ptp) = decode_item(idx_in_pack - 1);
                        let adj = if ptp != 2 { 0 } else if (plo & 0x0800) != 0 { 1 } else { plo };
                        adj + 1
                    } else {
                        1
                    };
                    return Ok((ltype, lcluster_sz as u16, d0, 0, 0));
                }
                let base_blk = u32_le(pack, pack_sz - 4) as u64;
                let mut nblk = 0u64;
                if !big_pcluster {
                    nblk = 1;
                    let mut j = idx_in_pack as isize;
                    while j > 0 {
                        j -= 1;
                        let (jlo, jtp) = decode_item(j as usize);
                        if jtp == 2 {
                            j -= jlo as isize;
                        }
                        if j >= 0 {
                            nblk += 1;
                        }
                    }
                } else {
                    let mut j = idx_in_pack as isize;
                    while j > 0 {
                        j -= 1;
                        let (jlo, jtp) = decode_item(j as usize);
                        if jtp == 2 {
                            if (jlo & 0x0800) != 0 {
                                j -= 1;
                                nblk += (jlo & !0x0800) as u64;
                                continue;
                            }
                            if jlo > 1 {
                                j -= (jlo as isize) - 2;
                            }
                            continue;
                        }
                        nblk += 1;
                    }
                }
                Ok((ltype, lo, 0, base_blk + nblk, 0))
            }
        };

        // Reconstruct compressed extents across [0..target_len]
        let mut out = vec![0u8; target_len];
        let mut lcn = 0usize;
        while lcn < totalidx {
            let (lt, cofs, _, pblk, _) = load_lcluster(lcn)?;
            if lt == 2 {
                lcn += 1;
                continue;
            }
            let la = ((lcn as u64) << lclusterbits) + cofs as u64;
            if la as usize >= target_len {
                break;
            }

            // Find next HEAD lcluster to determine decompressed length
            let mut next_lcn = lcn + 1;
            let mut cblks = 1u64;
            let is_big = (lt == 1 && bigpcl1) || ((lt == 0 || lt == 3) && bigpcl2);
            if next_lcn < totalidx && ((next_lcn as u64) << lclusterbits) < ino.size {
                let (nlt, _, _, _, ncblk) = load_lcluster(next_lcn)?;
                if nlt == 2 && ncblk > 0 && is_big {
                    cblks = ncblk;
                }
            }
            let mut llen = ino.size - la;
            let mut is_last_cluster = true;
            while next_lcn < totalidx {
                let (nlt, ncofs, _, _, _) = load_lcluster(next_lcn)?;
                if nlt != 2 {
                    llen = (((next_lcn as u64) << lclusterbits) + ncofs as u64) - la;
                    is_last_cluster = false;
                    break;
                }
                next_lcn += 1;
            }

            let idata_size = if (advise & 0x0008) != 0 { u16_le(&mhdr, 2) as usize } else { 0 };
            let raw_p = if is_last_cluster && idata_size > 0 {
                // Inline tailpacking payload sits right after the lcluster index array
                let end_idx_off = if ino.datalayout == 1 {
                    totalidx * 8
                } else if totalidx <= compacted_4b_initial {
                    ((totalidx + 1) / 2) * 8
                } else {
                    let rem = totalidx.saturating_sub(compacted_4b_initial + c2b_cnt);
                    compacted_4b_initial * 4 + c2b_cnt * 2 + ((rem + 1) / 2) * 8
                };
                let mut il = vec![0u8; idata_size];
                r.read_at(ebase + end_idx_off as u64, &mut il)?;
                il
            } else {
                let plen = (cblks * self.blk_sz) as usize;
                let mut buf = vec![0u8; plen];
                r.read_at(pblk * self.blk_sz, &mut buf)?;
                buf
            };

            let alg = if lt == 3 { alg_h2 } else { alg_h1 };
            let decompressed = if lt == 0 {
                // PLAIN
                raw_p[..(llen as usize).min(raw_p.len())].to_vec()
            } else if alg == 0 {
                // LZ4 with 0PADDING
                let margin = raw_p.iter().position(|&b| b != 0).unwrap_or(raw_p.len());
                if margin >= raw_p.len() {
                    vec![0u8; llen as usize]
                } else {
                    lz4_decompress_block(&raw_p[margin..], llen as usize)?
                }
            } else {
                return Err(format!("Nieobslugiwany algorytm EROFS: {}", alg));
            };

            let copy_end = ((la as usize) + decompressed.len()).min(target_len);
            if copy_end > la as usize {
                let take = copy_end - (la as usize);
                out[la as usize..copy_end].copy_from_slice(&decompressed[..take]);
            }
            lcn = next_lcn;
        }
        Ok(out)
    }

    pub fn list_dir(&self, r: &mut dyn ReadAt, nid: u64) -> Result<Vec<FsEntry>, String> {
        let ino = self.read_inode(r, nid)?;
        if (ino.mode & 0xF000) != 0x4000 {
            return Err("Nie jest katalogiem".into());
        }
        let data = self.read_inode_bytes(r, nid, ino.size as usize)?;
        let mut out = Vec::new();
        let blksz = self.blk_sz as usize;
        let mut blk_off = 0usize;
        while blk_off < data.len() {
            let end = (blk_off + blksz).min(data.len());
            let blk = &data[blk_off..end];
            if blk.len() < 12 {
                break;
            }
            let first_nameoff = u16_le(blk, 8) as usize;
            if first_nameoff < 12 || first_nameoff > blk.len() {
                break;
            }
            let count = first_nameoff / 12;
            for i in 0..count {
                let eoff = i * 12;
                let cnid = u64_le(blk, eoff) & ((1u64 << 63) - 1);
                let nameoff = u16_le(blk, eoff + 8) as usize;
                let ftype = blk[eoff + 10];
                if nameoff >= blk.len() {
                    continue;
                }
                let next_off = if i + 1 < count {
                    (u16_le(blk, (i + 1) * 12 + 8) as usize).min(blk.len())
                } else {
                    blk.len()
                };
                if next_off < nameoff {
                    continue;
                }
                let slice = &blk[nameoff..next_off];
                let z = slice.iter().position(|&b| b == 0).unwrap_or(slice.len());
                let name = String::from_utf8_lossy(&slice[..z]).to_string();
                if name.is_empty() || name == "." || name == ".." {
                    continue;
                }
                let (sz, is_dir, is_sym) = if ftype == 2 {
                    (0, true, false)
                } else if ftype == 7 {
                    (0, false, true)
                } else {
                    let s = self.read_inode(r, cnid).map(|ci| ci.size).unwrap_or(0);
                    (s, false, false)
                };
                out.push(FsEntry {
                    name,
                    is_dir,
                    is_symlink: is_sym,
                    size: sz,
                    id: cnid,
                });
            }
            blk_off += blksz;
        }
        Ok(out)
    }
}

// ---------------- EXT4 Reader ----------------

pub struct Ext4Meta {
    pub blk_sz: u64,
    pub inodes_per_group: u32,
    pub inode_size: u16,
    pub desc_size: u16,
    pub block_groups_off: u64,
}

impl Ext4Meta {
    pub fn parse(r: &mut dyn ReadAt) -> Result<Self, String> {
        let mut sb = [0u8; 256];
        r.read_at(1024, &mut sb)?;
        if u16_le(&sb, 56) != 0xEF53 {
            return Err("Brak magic EXT4".into());
        }
        let log_blk = u32_le(&sb, 24);
        let blk_sz = 1024u64 << log_blk;
        let inodes_per_group = u32_le(&sb, 40);
        let rev = u32_le(&sb, 76);
        let inode_size = if rev >= 1 { u16_le(&sb, 88) } else { 128 }.max(128);
        let desc_size = if (u32_le(&sb, 96) & 0x80) != 0 {
            u16_le(&sb, 254).max(32)
        } else {
            32
        };
        let block_groups_off = if blk_sz == 1024 { 2048 } else { blk_sz };
        Ok(Self {
            blk_sz,
            inodes_per_group,
            inode_size,
            desc_size,
            block_groups_off,
        })
    }

    fn read_inode_raw(&self, r: &mut dyn ReadAt, ino: u64) -> Result<Vec<u8>, String> {
        if ino == 0 {
            return Err("Inode 0".into());
        }
        let grp = (ino - 1) / self.inodes_per_group as u64;
        let idx = (ino - 1) % self.inodes_per_group as u64;
        let gd_off = self.block_groups_off + grp * self.desc_size as u64;
        let mut gd = vec![0u8; self.desc_size as usize];
        r.read_at(gd_off, &mut gd)?;
        let itable_lo = u32_le(&gd, 8) as u64;
        let itable_hi = if gd.len() >= 44 { u32_le(&gd, 40) as u64 } else { 0 };
        let itable_blk = itable_lo | (itable_hi << 32);
        let ino_off = itable_blk * self.blk_sz + idx * self.inode_size as u64;
        let mut ibuf = vec![0u8; self.inode_size as usize];
        r.read_at(ino_off, &mut ibuf)?;
        Ok(ibuf)
    }

    fn walk_extents(&self, r: &mut dyn ReadAt, node: &[u8], out: &mut Vec<(u64, u64, u64)>) -> Result<(), String> {
        if node.len() < 12 || u16_le(node, 0) != 0xF30A {
            return Ok(());
        }
        let entries = u16_le(node, 2) as usize;
        let depth = u16_le(node, 6);
        for i in 0..entries {
            let eo = 12 + i * 12;
            if eo + 12 > node.len() {
                break;
            }
            if depth == 0 {
                let lblk = u32_le(node, eo) as u64;
                let len_raw = u16_le(node, eo + 4);
                let len = (len_raw & 0x7FFF) as u64;
                let hi = u16_le(node, eo + 6) as u64;
                let lo = u32_le(node, eo + 8) as u64;
                let pblk = lo | (hi << 32);
                out.push((lblk, pblk, len));
            } else {
                let lo = u32_le(node, eo + 4) as u64;
                let hi = u16_le(node, eo + 8) as u64;
                let child_blk = lo | (hi << 32);
                let mut child = vec![0u8; self.blk_sz as usize];
                r.read_at(child_blk * self.blk_sz, &mut child)?;
                self.walk_extents(r, &child, out)?;
            }
        }
        Ok(())
    }

    pub fn read_inode_bytes(&self, r: &mut dyn ReadAt, ino: u64, limit: usize) -> Result<Vec<u8>, String> {
        let ibuf = self.read_inode_raw(r, ino)?;
        let mode = u16_le(&ibuf, 0);
        let size_lo = u32_le(&ibuf, 4) as u64;
        let size_hi = if (mode & 0xF000) == 0x8000 { u32_le(&ibuf, 108) as u64 } else { 0 };
        let size = size_lo | (size_hi << 32);
        let flags = u32_le(&ibuf, 32);
        let target_len = (size as usize).min(limit);
        if target_len == 0 {
            return Ok(Vec::new());
        }

        // Fast symlink inline
        if (mode & 0xF000) == 0xA000 && size < 60 {
            return Ok(ibuf[40..40 + target_len].to_vec());
        }

        let mut out = vec![0u8; target_len];
        if (flags & 0x80000) != 0 {
            let mut exts = Vec::new();
            self.walk_extents(r, &ibuf[40..100], &mut exts)?;
            for (lblk, pblk, len_blks) in exts {
                let vstart = (lblk * self.blk_sz) as usize;
                if vstart >= target_len {
                    continue;
                }
                let avail = ((len_blks * self.blk_sz) as usize).min(target_len - vstart);
                if pblk > 0 {
                    r.read_at(pblk * self.blk_sz, &mut out[vstart..vstart + avail])?;
                }
            }
        } else {
            // Direct blocks 0..11
            for i in 0..12usize {
                let pblk = u32_le(&ibuf, 40 + i * 4) as u64;
                let vstart = i * (self.blk_sz as usize);
                if vstart >= target_len {
                    break;
                }
                if pblk > 0 {
                    let take = (self.blk_sz as usize).min(target_len - vstart);
                    r.read_at(pblk * self.blk_sz, &mut out[vstart..vstart + take])?;
                }
            }
        }
        Ok(out)
    }

    pub fn list_dir(&self, r: &mut dyn ReadAt, ino: u64) -> Result<Vec<FsEntry>, String> {
        let ibuf = self.read_inode_raw(r, ino)?;
        let mode = u16_le(&ibuf, 0);
        if (mode & 0xF000) != 0x4000 {
            return Err("Nie jest katalogiem EXT4".into());
        }
        let data = self.read_inode_bytes(r, ino, 4 * 1024 * 1024)?;
        let mut out = Vec::new();
        let mut pos = 0usize;
        while pos + 8 <= data.len() {
            let cino = u32_le(&data, pos) as u64;
            let rec_len = u16_le(&data, pos + 4) as usize;
            let name_len = data[pos + 6] as usize;
            let ftype = data[pos + 7];
            if rec_len < 8 || pos + rec_len > data.len() {
                break;
            }
            if cino != 0 && name_len > 0 && pos + 8 + name_len <= pos + rec_len {
                let name = String::from_utf8_lossy(&data[pos + 8..pos + 8 + name_len]).to_string();
                if name != "." && name != ".." {
                    let is_dir = ftype == 2;
                    let is_sym = ftype == 7;
                    let sz = if is_dir {
                        0
                    } else {
                        self.read_inode_raw(r, cino)
                            .map(|cb| u32_le(&cb, 4) as u64)
                            .unwrap_or(0)
                    };
                    out.push(FsEntry {
                        name,
                        is_dir,
                        is_symlink: is_sym,
                        size: sz,
                        id: cino,
                    });
                }
            }
            pos += rec_len;
        }
        Ok(out)
    }
}

pub enum ImageVolume {
    Erofs(ErofsMeta),
    Ext4(Ext4Meta),
}

impl ImageVolume {
    pub fn open(r: &mut dyn ReadAt) -> Result<Self, String> {
        let mut sb = [0u8; 2048];
        r.read_at(0, &mut sb)?;
        if u32_le(&sb, 1024) == 0xE0F5E1E2 {
            Ok(Self::Erofs(ErofsMeta::parse(r)?))
        } else if u16_le(&sb, 1080) == 0xEF53 {
            Ok(Self::Ext4(Ext4Meta::parse(r)?))
        } else {
            Err("Nieznany format partycji (oczekiwano EROFS lub EXT4)".into())
        }
    }

    pub fn root_id(&self) -> u64 {
        match self {
            Self::Erofs(m) => m.root_nid,
            Self::Ext4(_) => 2,
        }
    }

    pub fn kind_name(&self) -> &'static str {
        match self {
            Self::Erofs(_) => "EROFS",
            Self::Ext4(_) => "EXT4",
        }
    }

    pub fn list_dir(&self, r: &mut dyn ReadAt, id: u64) -> Result<Vec<FsEntry>, String> {
        match self {
            Self::Erofs(m) => m.list_dir(r, id),
            Self::Ext4(m) => m.list_dir(r, id),
        }
    }

    pub fn read_file(&self, r: &mut dyn ReadAt, id: u64, limit: usize) -> Result<Vec<u8>, String> {
        match self {
            Self::Erofs(m) => m.read_inode_bytes(r, id, limit),
            Self::Ext4(m) => m.read_inode_bytes(r, id, limit),
        }
    }

    pub fn resolve_path(&self, r: &mut dyn ReadAt, path: &str) -> Result<FsEntry, String> {
        self.resolve_path_depth(r, path, 0)
    }

    fn resolve_path_depth(&self, r: &mut dyn ReadAt, path: &str, depth: usize) -> Result<FsEntry, String> {
        if depth > 16 {
            return Err("Zbyt gleboki symlink".into());
        }
        let mut cur_id = self.root_id();
        let parts: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
        if parts.is_empty() {
            return Ok(FsEntry {
                name: "/".into(),
                is_dir: true,
                is_symlink: false,
                size: 0,
                id: cur_id,
            });
        }
        for (idx, part) in parts.iter().enumerate() {
            let entries = self.list_dir(r, cur_id)?;
            let found = entries
                .into_iter()
                .find(|e| e.name == *part)
                .ok_or_else(|| format!("Nie znaleziono sciezki: {}", path))?;
            if found.is_symlink {
                let target_b = self.read_file(r, found.id, 1024)?;
                let target = String::from_utf8_lossy(&target_b).trim().to_string();
                let mut combined = String::new();
                if target.starts_with('/') {
                    combined.push_str(&target);
                } else {
                    for p in &parts[..idx] {
                        combined.push('/');
                        combined.push_str(p);
                    }
                    combined.push('/');
                    combined.push_str(&target);
                }
                for p in &parts[idx + 1..] {
                    combined.push('/');
                    combined.push_str(p);
                }
                return self.resolve_path_depth(r, &combined, depth + 1);
            }
            if idx + 1 == parts.len() {
                return Ok(found);
            }
            cur_id = found.id;
        }
        Err(format!("Nie znaleziono {}", path))
    }

    pub fn read_path(&self, r: &mut dyn ReadAt, path: &str, limit: usize) -> Result<Vec<u8>, String> {
        let ent = self.resolve_path(r, path)?;
        self.read_file(r, ent.id, limit)
    }
}

// ---------------- Pure-Rust LZ4 Block & RFC 1951 Deflate + ZIP + AXML ----------------

pub fn lz4_decompress_block(src: &[u8], expected_out: usize) -> Result<Vec<u8>, String> {
    let mut dst = Vec::with_capacity(expected_out);
    let mut ip = 0usize;
    while ip < src.len() && dst.len() < expected_out {
        let token = src[ip];
        ip += 1;
        let mut lit_len = (token >> 4) as usize;
        if lit_len == 15 {
            loop {
                if ip >= src.len() {
                    break;
                }
                let b = src[ip] as usize;
                ip += 1;
                lit_len += b;
                if b != 255 {
                    break;
                }
            }
        }
        let lit_take = lit_len.min(src.len() - ip).min(expected_out - dst.len());
        dst.extend_from_slice(&src[ip..ip + lit_take]);
        ip += lit_len;
        if dst.len() >= expected_out || ip >= src.len() {
            break;
        }
        if ip + 2 > src.len() {
            break;
        }
        let offset = u16::from_le_bytes([src[ip], src[ip + 1]]) as usize;
        ip += 2;
        if offset == 0 || offset > dst.len() {
            return Err("Niepoprawny offset LZ4".into());
        }
        let mut match_len = (token & 0x0F) as usize + 4;
        if (token & 0x0F) == 15 {
            loop {
                if ip >= src.len() {
                    break;
                }
                let b = src[ip] as usize;
                ip += 1;
                match_len += b;
                if b != 255 {
                    break;
                }
            }
        }
        let take_m = match_len.min(expected_out - dst.len());
        for _ in 0..take_m {
            let b = dst[dst.len() - offset];
            dst.push(b);
        }
    }
    Ok(dst)
}

struct BitReader<'a> {
    data: &'a [u8],
    byte_pos: usize,
    bit_pos: u8,
}

impl<'a> BitReader<'a> {
    fn new(data: &'a [u8]) -> Self {
        Self { data, byte_pos: 0, bit_pos: 0 }
    }

    fn read_bits(&mut self, n: u8) -> Result<u32, String> {
        let mut val = 0u32;
        for i in 0..n {
            if self.byte_pos >= self.data.len() {
                return Err("Koniec danych deflate".into());
            }
            let b = (self.data[self.byte_pos] >> self.bit_pos) & 1;
            val |= (b as u32) << i;
            self.bit_pos += 1;
            if self.bit_pos == 8 {
                self.bit_pos = 0;
                self.byte_pos += 1;
            }
        }
        Ok(val)
    }

    fn align_byte(&mut self) {
        if self.bit_pos != 0 {
            self.bit_pos = 0;
            self.byte_pos += 1;
        }
    }

    fn read_u16_aligned(&mut self) -> Result<u16, String> {
        self.align_byte();
        if self.byte_pos + 2 > self.data.len() {
            return Err("EOF u16 deflate".into());
        }
        let v = u16::from_le_bytes([self.data[self.byte_pos], self.data[self.byte_pos + 1]]);
        self.byte_pos += 2;
        Ok(v)
    }
}

struct HuffTable {
    max_bits: usize,
    counts: [u16; 16],
    symbols: Vec<u16>,
}

impl HuffTable {
    fn build(lengths: &[u8]) -> Result<Self, String> {
        let mut counts = [0u16; 16];
        let mut max_bits = 0usize;
        for &l in lengths {
            if l > 0 {
                let lu = l as usize;
                if lu > 15 {
                    return Err("Huff len > 15".into());
                }
                counts[lu] += 1;
                if lu > max_bits {
                    max_bits = lu;
                }
            }
        }
        let mut offs = [0u16; 16];
        let mut total = 0u16;
        for bits in 1..16 {
            offs[bits] = total;
            total += counts[bits];
        }
        let mut symbols = vec![0u16; total as usize];
        for (sym, &l) in lengths.iter().enumerate() {
            if l > 0 {
                let lu = l as usize;
                symbols[offs[lu] as usize] = sym as u16;
                offs[lu] += 1;
            }
        }
        Ok(Self { max_bits, counts, symbols })
    }

    fn decode(&self, br: &mut BitReader) -> Result<u16, String> {
        let mut code = 0i32;
        let mut first = 0i32;
        let mut index = 0i32;
        for len in 1..=self.max_bits {
            code |= br.read_bits(1)? as i32;
            let count = self.counts[len] as i32;
            if code - count < first {
                return Ok(self.symbols[(index + (code - first)) as usize]);
            }
            index += count;
            first += count;
            first <<= 1;
            code <<= 1;
        }
        Err("Nieprawidlowy symbol Huffmana".into())
    }
}

pub fn inflate_raw(src: &[u8]) -> Result<Vec<u8>, String> {
    let mut br = BitReader::new(src);
    let mut out = Vec::new();
    let len_base = [3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258];
    let len_ext  = [0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0];
    let dst_base = [1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577];
    let dst_ext  = [0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13];
    let cl_ord   = [16usize,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15];

    loop {
        let bfinal = br.read_bits(1)?;
        let btype = br.read_bits(2)?;
        if btype == 0 {
            let len = br.read_u16_aligned()? as usize;
            let _nlen = br.read_u16_aligned()?;
            if br.byte_pos + len > br.data.len() {
                return Err("EOF stored deflate".into());
            }
            out.extend_from_slice(&br.data[br.byte_pos..br.byte_pos + len]);
            br.byte_pos += len;
        } else if btype == 1 || btype == 2 {
            let (lit_tab, dist_tab) = if btype == 1 {
                let mut ll = vec![0u8; 288];
                for i in 0..=143 { ll[i] = 8; }
                for i in 144..=255 { ll[i] = 9; }
                for i in 256..=279 { ll[i] = 7; }
                for i in 280..=287 { ll[i] = 8; }
                let dl = vec![5u8; 32];
                (HuffTable::build(&ll)?, HuffTable::build(&dl)?)
            } else {
                let hlit = br.read_bits(5)? as usize + 257;
                let hdist = br.read_bits(5)? as usize + 1;
                let hclen = br.read_bits(4)? as usize + 4;
                let mut cl_lens = [0u8; 19];
                for i in 0..hclen {
                    cl_lens[cl_ord[i]] = br.read_bits(3)? as u8;
                }
                let cl_tab = HuffTable::build(&cl_lens)?;
                let mut lens = Vec::with_capacity(hlit + hdist);
                while lens.len() < hlit + hdist {
                    let sym = cl_tab.decode(&mut br)? as usize;
                    if sym < 16 {
                        lens.push(sym as u8);
                    } else if sym == 16 {
                        let rep = br.read_bits(2)? as usize + 3;
                        let prev = *lens.last().unwrap_or(&0);
                        for _ in 0..rep { lens.push(prev); }
                    } else if sym == 17 {
                        let rep = br.read_bits(3)? as usize + 3;
                        for _ in 0..rep { lens.push(0); }
                    } else {
                        let rep = br.read_bits(7)? as usize + 11;
                        for _ in 0..rep { lens.push(0); }
                    }
                }
                (HuffTable::build(&lens[..hlit])?, HuffTable::build(&lens[hlit..hlit + hdist])?)
            };

            loop {
                let sym = lit_tab.decode(&mut br)? as usize;
                if sym < 256 {
                    out.push(sym as u8);
                } else if sym == 256 {
                    break;
                } else {
                    let li = sym - 257;
                    if li >= len_base.len() {
                        return Err("Zly len symbol".into());
                    }
                    let l = len_base[li] + br.read_bits(len_ext[li])? as usize;
                    let di = dist_tab.decode(&mut br)? as usize;
                    if di >= dst_base.len() {
                        return Err("Zly dist symbol".into());
                    }
                    let d = dst_base[di] + br.read_bits(dst_ext[di])? as usize;
                    if d == 0 || d > out.len() {
                        return Err("Zly back-ref deflate".into());
                    }
                    for _ in 0..l {
                        let b = out[out.len() - d];
                        out.push(b);
                    }
                }
            }
        } else {
            return Err("Zarezerwowany btype deflate".into());
        }
        if bfinal != 0 {
            break;
        }
    }
    Ok(out)
}

pub fn zip_list_entries(zip_bytes: &[u8]) -> Vec<String> {
    let mut names = Vec::new();
    let eocd_pos = (0..=zip_bytes.len().saturating_sub(22))
        .rev()
        .find(|&i| zip_bytes[i..i + 4] == [0x50, 0x4B, 0x05, 0x06]);
    let Some(ep) = eocd_pos else { return names };
    let cd_cnt = u16_le(zip_bytes, ep + 10) as usize;
    let cd_off = u32_le(zip_bytes, ep + 16) as usize;
    let mut p = cd_off;
    for _ in 0..cd_cnt {
        if p + 46 > zip_bytes.len() || zip_bytes[p..p + 4] != [0x50, 0x4B, 0x01, 0x02] {
            break;
        }
        let nlen = u16_le(zip_bytes, p + 28) as usize;
        let xlen = u16_le(zip_bytes, p + 30) as usize;
        let clen = u16_le(zip_bytes, p + 32) as usize;
        if p + 46 + nlen <= zip_bytes.len() {
            names.push(String::from_utf8_lossy(&zip_bytes[p + 46..p + 46 + nlen]).to_string());
        }
        p += 46 + nlen + xlen + clen;
    }
    names
}

pub fn zip_read_entry(zip_bytes: &[u8], target: &str) -> Result<Vec<u8>, String> {
    let eocd_pos = (0..=zip_bytes.len().saturating_sub(22))
        .rev()
        .find(|&i| zip_bytes[i..i + 4] == [0x50, 0x4B, 0x05, 0x06])
        .ok_or_else(|| "Brak EOCD ZIP".to_string())?;
    let cd_cnt = u16_le(zip_bytes, eocd_pos + 10) as usize;
    let cd_off = u32_le(zip_bytes, eocd_pos + 16) as usize;
    let mut p = cd_off;
    for _ in 0..cd_cnt {
        if p + 46 > zip_bytes.len() || zip_bytes[p..p + 4] != [0x50, 0x4B, 0x01, 0x02] {
            break;
        }
        let method = u16_le(zip_bytes, p + 10);
        let comp_sz = u32_le(zip_bytes, p + 20) as usize;
        let nlen = u16_le(zip_bytes, p + 28) as usize;
        let xlen = u16_le(zip_bytes, p + 30) as usize;
        let clen = u16_le(zip_bytes, p + 32) as usize;
        let lfh_off = u32_le(zip_bytes, p + 42) as usize;
        if p + 46 + nlen <= zip_bytes.len() {
            let name = String::from_utf8_lossy(&zip_bytes[p + 46..p + 46 + nlen]);
            if name == target {
                if lfh_off + 30 > zip_bytes.len() {
                    return Err("LFH poza plikiem".into());
                }
                let ln = u16_le(zip_bytes, lfh_off + 26) as usize;
                let lx = u16_le(zip_bytes, lfh_off + 28) as usize;
                let d_off = lfh_off + 30 + ln + lx;
                if d_off + comp_sz > zip_bytes.len() {
                    return Err("Dane wpisu ZIP uciete".into());
                }
                let payload = &zip_bytes[d_off..d_off + comp_sz];
                return match method {
                    0 => Ok(payload.to_vec()),
                    8 => inflate_raw(payload),
                    m => Err(format!("Nieobslugiwana kompresja ZIP: {}", m)),
                };
            }
        }
        p += 46 + nlen + xlen + clen;
    }
    Err(format!("Brak {} w ZIP", target))
}

pub fn axml_extract_package_and_launcher(axml: &[u8]) -> (String, bool) {
    // Parse AXML StringPool + XML_START_ELEMENT tokens to find package="..." and LAUNCHER/HOME
    if axml.len() < 16 || u16_le(axml, 0) != 0x0003 {
        return (String::new(), false);
    }
    let mut strings: Vec<String> = Vec::new();
    let mut off = 8usize;
    let mut pkg = String::new();
    let mut is_launcher = false;

    while off + 8 <= axml.len() {
        let ctype = u16_le(axml, off);
        let chdr = u16_le(axml, off + 2) as usize;
        let csz = u32_le(axml, off + 4) as usize;
        if csz < 8 || off + csz > axml.len() {
            break;
        }
        if ctype == 0x0001 && off + 28 <= axml.len() {
            // STRING_POOL
            let scount = u32_le(axml, off + 8) as usize;
            let flags = u32_le(axml, off + 16);
            let is_utf8 = (flags & (1 << 8)) != 0;
            let sstart = off + u32_le(axml, off + 20) as usize;
            for i in 0..scount {
                if off + chdr + i * 4 + 4 > axml.len() {
                    break;
                }
                let so = sstart + u32_le(axml, off + chdr + i * 4) as usize;
                if so >= axml.len() {
                    strings.push(String::new());
                    continue;
                }
                if is_utf8 {
                    let mut p = so;
                    if p < axml.len() && (axml[p] & 0x80) != 0 { p += 2; } else { p += 1; }
                    let blen = if p < axml.len() && (axml[p] & 0x80) != 0 {
                        let v = (((axml[p] & 0x7F) as usize) << 8) | (*axml.get(p + 1).unwrap_or(&0) as usize);
                        p += 2;
                        v
                    } else if p < axml.len() {
                        let v = axml[p] as usize;
                        p += 1;
                        v
                    } else { 0 };
                    let end = (p + blen).min(axml.len());
                    strings.push(String::from_utf8_lossy(&axml[p..end]).to_string());
                } else if so + 2 <= axml.len() {
                    let mut p = so;
                    let clen = u16_le(axml, p) as usize;
                    p += 2;
                    let mut u16s = Vec::with_capacity(clen);
                    for j in 0..clen {
                        if p + j * 2 + 2 <= axml.len() {
                            u16s.push(u16_le(axml, p + j * 2));
                        }
                    }
                    strings.push(String::from_utf16_lossy(&u16s));
                }
            }
        } else if ctype == 0x0102 && off + chdr + 20 <= axml.len() {
            // START_ELEMENT
            let name_idx = u32_le(axml, off + chdr + 4) as usize;
            let attr_start = u16_le(axml, off + chdr + 8) as usize;
            let attr_size = (u16_le(axml, off + chdr + 10) as usize).max(20);
            let attr_cnt = u16_le(axml, off + chdr + 12) as usize;
            let elem = strings.get(name_idx).map(|s| s.as_str()).unwrap_or("");
            let a_base = off + chdr + attr_start;
            for i in 0..attr_cnt {
                let ap = a_base + i * attr_size;
                if ap + 20 > off + csz {
                    break;
                }
                let aname_idx = u32_le(axml, ap + 4) as usize;
                let rval_idx = u32_le(axml, ap + 8) as usize;
                let aname = strings.get(aname_idx).map(|s| s.as_str()).unwrap_or("");
                let aval = strings.get(rval_idx).map(|s| s.as_str()).unwrap_or("");
                if elem == "manifest" && aname == "package" && !aval.is_empty() {
                    pkg = aval.to_string();
                }
                if aval == "android.intent.category.LAUNCHER" || aval == "android.intent.category.HOME" {
                    is_launcher = true;
                }
            }
        }
        off += csz;
    }
    (pkg, is_launcher)
}

pub fn decode_png_rgba(png: &[u8]) -> Result<(u32, u32, Vec<u32>), String> {
    if png.len() < 33 || &png[0..8] != b"\x89PNG\r\n\x1a\n" {
        return Err("Niepoprawny naglowek PNG".into());
    }
    let mut pos = 8usize;
    let mut w = 0u32;
    let mut h = 0u32;
    let mut color_type = 6u8;
    let mut idat = Vec::new();
    while pos + 12 <= png.len() {
        let len = u32::from_be_bytes([png[pos], png[pos + 1], png[pos + 2], png[pos + 3]]) as usize;
        let ctype = &png[pos + 4..pos + 8];
        if pos + 12 + len > png.len() {
            break;
        }
        let data = &png[pos + 8..pos + 8 + len];
        if ctype == b"IHDR" && data.len() >= 13 {
            w = u32::from_be_bytes([data[0], data[1], data[2], data[3]]);
            h = u32::from_be_bytes([data[4], data[5], data[6], data[7]]);
            color_type = data[9];
        } else if ctype == b"IDAT" {
            idat.extend_from_slice(data);
        } else if ctype == b"IEND" {
            break;
        }
        pos += 12 + len;
    }
    if w == 0 || h == 0 || idat.len() < 6 {
        return Err("Brak IHDR/IDAT".into());
    }
    if (idat[1] & 0x20) != 0 {
        return Err("PNG zlib z FDICT nieobslugiwany".into());
    }
    let raw = inflate_raw(&idat[2..idat.len() - 4])?;
    let bpp = match color_type {
        2 => 3usize,
        6 => 4usize,
        _ => return Err(format!("Nieobslugiwany color_type PNG: {}", color_type)),
    };
    let stride = (w as usize) * bpp;
    let mut recon = vec![0u8; (h as usize) * stride];
    let mut rp = 0usize;
    for y in 0..h as usize {
        if rp >= raw.len() {
            break;
        }
        let filt = raw[rp];
        rp += 1;
        let row_start = y * stride;
        for x in 0..stride {
            let x_val = *raw.get(rp).unwrap_or(&0);
            rp += 1;
            let a = if x >= bpp { recon[row_start + x - bpp] } else { 0 };
            let b = if y > 0 { recon[row_start - stride + x] } else { 0 };
            let c = if x >= bpp && y > 0 { recon[row_start - stride + x - bpp] } else { 0 };
            let p_val = match filt {
                0 => x_val,
                1 => x_val.wrapping_add(a),
                2 => x_val.wrapping_add(b),
                3 => x_val.wrapping_add((((a as u16) + (b as u16)) / 2) as u8),
                4 => {
                    let pa = ((b as i32) - (c as i32)).abs();
                    let pb = ((a as i32) - (c as i32)).abs();
                    let pc = ((a as i32) + (b as i32) - 2 * (c as i32)).abs();
                    let pr = if pa <= pb && pa <= pc { a } else if pb <= pc { b } else { c };
                    x_val.wrapping_add(pr)
                }
                _ => x_val,
            };
            recon[row_start + x] = p_val;
        }
    }
    let mut pixels = vec![0u32; (w as usize) * (h as usize)];
    for i in 0..pixels.len() {
        let o = i * bpp;
        let r = recon[o] as u32;
        let g = recon[o + 1] as u32;
        let b = recon[o + 2] as u32;
        pixels[i] = (r << 16) | (g << 8) | b;
    }
    Ok((w, h, pixels))
}

// ---------------- High-level super.img / system.img Inspector ----------------

#[derive(Clone, Debug)]
pub struct ImgPartitionSummary {
    pub name: String,
    pub size_mib: u32,
    pub fs_kind: String,
}

#[derive(Clone, Debug)]
pub struct ImgApkEntry {
    pub dir_name: String,
    pub package: String,
    pub partition: String,
    pub path: String,
    pub size_kib: u32,
    pub is_launcher: bool,
}

#[derive(Clone, Debug)]
pub struct BootAnimFrame {
    pub w: u32,
    pub h: u32,
    pub pixels: Vec<u32>,
}

#[derive(Clone, Debug)]
pub struct LoadedImageData {
    pub file_path: String,
    pub container_kind: String, // "super.img (sparse+liblp)" | "system.img (EROFS)" ...
    pub partitions: Vec<ImgPartitionSummary>,
    pub props: HashMap<String, String>,
    pub apks: Vec<ImgApkEntry>,
    pub has_r9c_memd: bool,
    pub services_spoof_verified: String,
    pub xiaomi_bloat_left: Vec<String>,
    pub boot_frames: Vec<BootAnimFrame>,
    pub sys_entries: Vec<(String, String, bool, u64)>, // (partition, path, is_dir, size)
}

pub fn inspect_image_file(path: &Path) -> Result<LoadedImageData, String> {
    let mut disk = SparseDisk::open(path)?;
    let top_kind = detect_fs_kind(&mut disk);
    let mut partitions_list: Vec<PartitionEntry> = Vec::new();
    let container_kind: String;

    if top_kind == "super" || (top_kind == "unknown" && parse_super_partitions(&mut disk).is_ok()) {
        partitions_list = parse_super_partitions(&mut disk)?;
        container_kind = if disk.is_sparse() {
            "super.img (Android Sparse + liblp)".into()
        } else {
            "super.img (RAW + liblp)".into()
        };
    } else if top_kind == "erofs" || top_kind == "ext4" {
        let sz = disk.size();
        container_kind = format!(
            "{} ({})",
            path.file_name().and_then(|n| n.to_str()).unwrap_or("system.img"),
            top_kind.to_uppercase()
        );
        partitions_list.push(PartitionEntry {
            name: if path.to_string_lossy().to_lowercase().contains("product") {
                "product".into()
            } else if path.to_string_lossy().to_lowercase().contains("system_ext") {
                "system_ext".into()
            } else {
                "system".into()
            },
            size: sz,
            fs_kind: top_kind,
            extents: vec![LpExtentMap {
                virt_off: 0,
                phys_off: 0,
                len: sz,
            }],
        });
    } else {
        return Err(format!("Nierozpoznany format obrazu: {} ({})", path.display(), top_kind));
    }

    let part_summaries: Vec<ImgPartitionSummary> = partitions_list
        .iter()
        .map(|p| ImgPartitionSummary {
            name: p.name.clone(),
            size_mib: (p.size / (1024 * 1024)) as u32,
            fs_kind: p.fs_kind.clone(),
        })
        .collect();

    let mut props: HashMap<String, String> = HashMap::new();
    let mut apks: Vec<ImgApkEntry> = Vec::new();
    let mut has_r9c_memd = false;
    let mut services_spoof_verified = "brak services.jar w otwartym obrazie".to_string();
    let mut xiaomi_bloat_left = Vec::new();
    let mut boot_frames = Vec::new();
    let mut sys_entries = Vec::new();

    for part in &partitions_list {
        if part.fs_kind != "erofs" && part.fs_kind != "ext4" {
            continue;
        }
        let mut pv = PartitionView::new(&mut disk, part.size, part.extents.clone());
        let Ok(vol) = ImageVolume::open(&mut pv) else {
            continue;
        };

        // 1. Collect top-level and system root directory entries for Explorer
        if let Ok(root_ents) = vol.list_dir(&mut pv, vol.root_id()) {
            for e in &root_ents {
                sys_entries.push((part.name.clone(), format!("/{}", e.name), e.is_dir, e.size));
            }
        }

        // 2. Read build.prop files
        for prop_p in [
            "/build.prop",
            "/system/build.prop",
            "/etc/build.prop",
            "/system/etc/build.prop",
        ] {
            if let Ok(bytes) = vol.read_path(&mut pv, prop_p, 512 * 1024) {
                let txt = String::from_utf8_lossy(&bytes);
                for ln in txt.lines() {
                    let s = ln.trim();
                    if s.is_empty() || s.starts_with('#') {
                        continue;
                    }
                    if let Some((k, v)) = s.split_once('=') {
                        props.insert(k.trim().to_string(), v.trim().to_string());
                    }
                }
            }
        }

        // 3. Check r9c-memd daemon
        if part.name == "system_ext" || part.name == "system" {
            if vol.resolve_path(&mut pv, "/bin/r9c-memd").is_ok()
                || vol.resolve_path(&mut pv, "/system_ext/bin/r9c-memd").is_ok()
            {
                has_r9c_memd = true;
            }
        }

        // 4. Verify services.jar R9cMicrogSpoof directly inside system.img
        for sj_path in ["/framework/services.jar", "/system/framework/services.jar"] {
            if let Ok(sj) = vol.read_path(&mut pv, sj_path, 48 * 1024 * 1024) {
                let entries = zip_list_entries(&sj);
                let dexes: Vec<String> = entries.into_iter().filter(|n| n.ends_with(".dex")).collect();
                let mut found_spoof = false;
                for dn in &dexes {
                    if let Ok(dex_b) = zip_read_entry(&sj, dn) {
                        if dex_b.windows(b"R9cMicrogSpoof".len()).any(|w| w == b"R9cMicrogSpoof") {
                            found_spoof = true;
                            break;
                        }
                    }
                }
                services_spoof_verified = if found_spoof {
                    format!("AKTYWNY w services.jar (R9cMicrogSpoof obecny wsrod {} DEX)", dexes.len())
                } else {
                    format!("BRAK R9cMicrogSpoof w services.jar ({} DEX)", dexes.len())
                };
            }
        }

        // 5. Scan app & priv-app directories + inspect APKs
        let roots_to_scan = if part.name == "system" {
            vec!["/system/priv-app", "/system/app", "/priv-app", "/app"]
        } else {
            vec!["/priv-app", "/app"]
        };
        let xiaomi_check = [
            "MiuiHome",
            "MiLauncherGlobal",
            "MiuiCamera",
            "MIUIGalleryGlobal",
            "MIUIFileExplorerGlobal",
            "MIUISecurityCenterGlobal",
            "MIUIThemeManagerGlobal",
            "MIUIXiaomiAccountGlobal",
            "MIUICloudServiceGlobal",
            "HyperPhone",
            "MiuiMmsGlobal",
            "MISettings",
            "MIBrowserGlobal",
            "MSA-Global",
            "AnalyticsCore",
        ];

        let mut seen_dir_ids = std::collections::HashSet::new();
        for sub_path in roots_to_scan {
            let Ok(dir_ent) = vol.resolve_path(&mut pv, sub_path) else {
                continue;
            };
            if dir_ent.is_symlink || !dir_ent.is_dir || !seen_dir_ids.insert(dir_ent.id) {
                continue;
            }
            let Ok(app_dirs) = vol.list_dir(&mut pv, dir_ent.id) else {
                continue;
            };
            for ad in app_dirs {
                if !ad.is_dir {
                    continue;
                }
                let full_dir = format!("{}/{}", sub_path, ad.name);
                sys_entries.push((part.name.clone(), full_dir.clone(), true, ad.size));
                if xiaomi_check.iter().any(|x| ad.name.eq_ignore_ascii_case(x)) {
                    xiaomi_bloat_left.push(format!("{}:{}", part.name, full_dir));
                }
                if let Ok(files) = vol.list_dir(&mut pv, ad.id) {
                    if let Some(apk_f) = files.into_iter().find(|f| !f.is_dir && f.name.ends_with(".apk")) {
                        let apk_path = format!("{}/{}", full_dir, apk_f.name);
                        let mut pkg_id = ad.name.clone();
                        let mut is_launcher = false;
                        // Read APK manifest (cap at 55 MiB)
                        if apk_f.size > 0 && apk_f.size < 180 * 1024 * 1024 {
                            if let Ok(apk_b) = vol.read_file(&mut pv, apk_f.id, apk_f.size as usize) {
                                if let Ok(axml) = zip_read_entry(&apk_b, "AndroidManifest.xml") {
                                    let (p, l) = axml_extract_package_and_launcher(&axml);
                                    if !p.is_empty() {
                                        pkg_id = p;
                                    }
                                    is_launcher = l;
                                }
                            }
                        }
                        apks.push(ImgApkEntry {
                            dir_name: ad.name,
                            package: pkg_id,
                            partition: part.name.clone(),
                            path: apk_path,
                            size_kib: (apk_f.size / 1024) as u32,
                            is_launcher,
                        });
                    }
                }
            }
        }

        // 6. Decode first few frames from product/media/bootanimation.zip
        if boot_frames.is_empty() {
            for bpath in ["/media/bootanimation.zip", "/system/media/bootanimation.zip"] {
                if let Ok(bz) = vol.read_path(&mut pv, bpath, 8 * 1024 * 1024) {
                    let entries = zip_list_entries(&bz);
                    for ename in entries
                        .into_iter()
                        .filter(|n| n.ends_with(".png"))
                        .take(12)
                    {
                        if let Ok(png_b) = zip_read_entry(&bz, &ename) {
                            if let Ok((w, h, pixels)) = decode_png_rgba(&png_b) {
                                boot_frames.push(BootAnimFrame { w, h, pixels });
                            }
                        }
                    }
                    break;
                }
            }
        }
    }

    Ok(LoadedImageData {
        file_path: path.display().to_string(),
        container_kind,
        partitions: part_summaries,
        props,
        apks,
        has_r9c_memd,
        services_spoof_verified,
        xiaomi_bloat_left,
        boot_frames,
        sys_entries,
    })
}

pub fn list_path_in_image(path: &Path, part_name: &str, dir_path: &str) -> Result<Vec<FsEntry>, String> {
    let mut disk = SparseDisk::open(path)?;
    let top_kind = detect_fs_kind(&mut disk);
    if top_kind == "super" || (top_kind == "unknown" && parse_super_partitions(&mut disk).is_ok()) {
        let parts = parse_super_partitions(&mut disk)?;
        let part = parts
            .into_iter()
            .find(|p| p.name == part_name)
            .ok_or_else(|| format!("Brak partycji {}", part_name))?;
        let mut pv = PartitionView::new(&mut disk, part.size, part.extents);
        let vol = ImageVolume::open(&mut pv)?;
        let ent = vol.resolve_path(&mut pv, dir_path)?;
        return vol.list_dir(&mut pv, ent.id);
    }
    let vol = ImageVolume::open(&mut disk)?;
    let ent = vol.resolve_path(&mut disk, dir_path)?;
    vol.list_dir(&mut disk, ent.id)
}

pub fn read_text_in_image(path: &Path, part_name: &str, file_path: &str, max_bytes: usize) -> Result<String, String> {
    let mut disk = SparseDisk::open(path)?;
    let top_kind = detect_fs_kind(&mut disk);
    if top_kind == "super" || (top_kind == "unknown" && parse_super_partitions(&mut disk).is_ok()) {
        let parts = parse_super_partitions(&mut disk)?;
        let part = parts
            .into_iter()
            .find(|p| p.name == part_name)
            .ok_or_else(|| format!("Brak partycji {}", part_name))?;
        let mut pv = PartitionView::new(&mut disk, part.size, part.extents);
        let vol = ImageVolume::open(&mut pv)?;
        let bytes = vol.read_path(&mut pv, file_path, max_bytes)?;
        return Ok(String::from_utf8_lossy(&bytes).to_string());
    }
    let vol = ImageVolume::open(&mut disk)?;
    let bytes = vol.read_path(&mut disk, file_path, max_bytes)?;
    Ok(String::from_utf8_lossy(&bytes).to_string())
}

pub fn extract_named_partition(super_path: &Path, part_name: &str, out_path: &Path) -> Result<u64, String> {
    let mut disk = SparseDisk::open(super_path)?;
    let parts = parse_super_partitions(&mut disk)?;
    let part = parts
        .into_iter()
        .find(|p| p.name == part_name)
        .ok_or_else(|| format!("Nie znaleziono partycji {} w {}", part_name, super_path.display()))?;
    extract_partition_to_file(&mut disk, &part, out_path)?;
    Ok(part.size)
}

#[inline]
fn u16_le(b: &[u8], o: usize) -> u16 {
    u16::from_le_bytes([b[o], b[o + 1]])
}

#[inline]
fn u32_le(b: &[u8], o: usize) -> u32 {
    u32::from_le_bytes([b[o], b[o + 1], b[o + 2], b[o + 3]])
}

#[inline]
fn u64_le(b: &[u8], o: usize) -> u64 {
    u64::from_le_bytes([
        b[o], b[o + 1], b[o + 2], b[o + 3], b[o + 4], b[o + 5], b[o + 6], b[o + 7],
    ])
}

#[inline]
fn align_up(v: u64, a: u64) -> u64 {
    (v + a - 1) & !(a - 1)
}

#[cfg(test)]
mod tests {
    use super::*;

    struct MemDisk(Vec<u8>);
    impl ReadAt for MemDisk {
        fn size(&self) -> u64 {
            self.0.len() as u64
        }
        fn read_at(&mut self, offset: u64, buf: &mut [u8]) -> Result<(), String> {
            let s = offset as usize;
            for (i, b) in buf.iter_mut().enumerate() {
                *b = *self.0.get(s + i).unwrap_or(&0);
            }
            Ok(())
        }
    }

    #[test]
    fn test_lz4_and_deflate() {
        // Raw LZ4 block: literal "Hello " (6 bytes) -> token 0x60 + "Hello "
        let src = [0x60u8, b'H', b'e', b'l', b'l', b'o', b'!'];
        let out = lz4_decompress_block(&src, 6).expect("lz4");
        assert_eq!(&out, b"Hello!");

        // Stored RFC 1951 deflate block for "Mystical"
        let def = [0x01u8, 0x08, 0x00, 0xF7, 0xFF, b'M', b'y', b's', b't', b'i', b'c', b'a', b'l'];
        let inf = inflate_raw(&def).expect("inflate");
        assert_eq!(&inf, b"Mystical");
    }

    #[test]
    fn test_sparse_roundtrip() {
        let dir = std::env::temp_dir();
        let p = dir.join("r9c_sparse_test.img");
        // Sparse 1 block RAW ("ABCD...") + 1 block FILL (0x11223344)
        let mut raw_file = Vec::new();
        // Header 28B
        raw_file.extend_from_slice(&0xED26FF3Au32.to_le_bytes());
        raw_file.extend_from_slice(&1u16.to_le_bytes());
        raw_file.extend_from_slice(&0u16.to_le_bytes());
        raw_file.extend_from_slice(&28u16.to_le_bytes());
        raw_file.extend_from_slice(&12u16.to_le_bytes());
        raw_file.extend_from_slice(&4096u32.to_le_bytes());
        raw_file.extend_from_slice(&2u32.to_le_bytes()); // 2 blocks
        raw_file.extend_from_slice(&2u32.to_le_bytes()); // 2 chunks
        raw_file.extend_from_slice(&0u32.to_le_bytes());
        // Chunk 1: RAW 1 block
        raw_file.extend_from_slice(&0xCAC1u16.to_le_bytes());
        raw_file.extend_from_slice(&0u16.to_le_bytes());
        raw_file.extend_from_slice(&1u32.to_le_bytes());
        raw_file.extend_from_slice(&(12u32 + 4096).to_le_bytes());
        let mut blk0 = vec![0x5Au8; 4096];
        blk0[0..8].copy_from_slice(b"MYSTICAL");
        raw_file.extend_from_slice(&blk0);
        // Chunk 2: FILL 1 block
        raw_file.extend_from_slice(&0xCAC2u16.to_le_bytes());
        raw_file.extend_from_slice(&0u16.to_le_bytes());
        raw_file.extend_from_slice(&1u32.to_le_bytes());
        raw_file.extend_from_slice(&16u32.to_le_bytes());
        raw_file.extend_from_slice(&0x44332211u32.to_le_bytes());

        std::fs::write(&p, &raw_file).unwrap();
        let mut sd = SparseDisk::open(&p).unwrap();
        assert_eq!(sd.size(), 8192);
        let mut out = vec![0u8; 16];
        sd.read_at(0, &mut out[..8]).unwrap();
        assert_eq!(&out[..8], b"MYSTICAL");
        sd.read_at(4096, &mut out[..4]).unwrap();
        assert_eq!(&out[..4], &[0x11, 0x22, 0x33, 0x44]);
        let _ = std::fs::remove_file(p);
    }

    #[test]
    fn test_synthetic_erofs_dir_symlink_and_detect() {
        // Build tiny 12KB EROFS image:
        // root_nid=0 (dir at blk 2), nid=1 (inline "ro.os=Mystical"), nid=2 (symlink "/build.prop")
        let mut img = vec![0u8; 12288];
        // Superblock @1024
        img[1024..1028].copy_from_slice(&0xE0F5E1E2u32.to_le_bytes());
        img[1024 + 12] = 12; // 4096 blk
        img[1024 + 14..1024 + 16].copy_from_slice(&0u16.to_le_bytes()); // root_nid = 0
        img[1024 + 40..1024 + 44].copy_from_slice(&1u32.to_le_bytes()); // meta_blkaddr = 1 (off 4096)

        // Compact inode 0 @ 4096: mode=0x41ED (dir), datalayout=0 (FLAT_PLAIN), size=48, startblk=2
        img[4096..4098].copy_from_slice(&0x0000u16.to_le_bytes());
        img[4096 + 4..4096 + 6].copy_from_slice(&0x41EDu16.to_le_bytes());
        img[4096 + 8..4096 + 12].copy_from_slice(&48u32.to_le_bytes());
        img[4096 + 16..4096 + 20].copy_from_slice(&2u32.to_le_bytes());

        // nid 1 at 4096 + 32 = 4128: regular file, datalayout=2 (FLAT_INLINE -> i_format=4), size=14
        img[4128..4130].copy_from_slice(&0x0004u16.to_le_bytes());
        img[4128 + 4..4128 + 6].copy_from_slice(&0x81A4u16.to_le_bytes());
        img[4128 + 8..4128 + 12].copy_from_slice(&14u32.to_le_bytes());
        img[4128 + 32..4128 + 46].copy_from_slice(b"ro.os=Mystical");

        // nid 2 at 4096 + 64 = 4160: symlink -> "/build.prop", datalayout=2, size=11
        img[4160..4162].copy_from_slice(&0x0004u16.to_le_bytes());
        img[4160 + 4..4160 + 6].copy_from_slice(&0xA1FFu16.to_le_bytes());
        img[4160 + 8..4160 + 12].copy_from_slice(&11u32.to_le_bytes());
        img[4160 + 32..4160 + 43].copy_from_slice(b"/build.prop");

        // Dir block 2 @ 8192: 2 dirents (24 bytes header table, then names)
        // entry 0: nid=1, nameoff=24 ("build.prop", 10B -> ends at 34)
        img[8192..8200].copy_from_slice(&1u64.to_le_bytes());
        img[8192 + 8..8192 + 10].copy_from_slice(&24u16.to_le_bytes());
        img[8192 + 10] = 1; // REG_FILE
        // entry 1: nid=2, nameoff=34 ("alias.prop", 10B -> ends at 44)
        img[8192 + 12..8192 + 20].copy_from_slice(&2u64.to_le_bytes());
        img[8192 + 20..8192 + 22].copy_from_slice(&34u16.to_le_bytes());
        img[8192 + 22] = 7; // SYMLINK
        img[8192 + 24..8192 + 34].copy_from_slice(b"build.prop");
        img[8192 + 34..8192 + 44].copy_from_slice(b"alias.prop");

        let mut md = MemDisk(img);
        assert_eq!(detect_fs_kind(&mut md), "erofs");
        let vol = ImageVolume::open(&mut md).unwrap();
        let data = vol.read_path(&mut md, "/build.prop", 1024).unwrap();
        assert_eq!(&data, b"ro.os=Mystical");
        // Final-component symlink must also resolve to target file
        let alias_data = vol.read_path(&mut md, "/alias.prop", 1024).unwrap();
        assert_eq!(&alias_data, b"ro.os=Mystical");

        // Verify detect_fs_kind recognizes liblp geometry magic at offset 4096
        let mut sup = vec![0u8; 8192];
        sup[4096..4100].copy_from_slice(&0x616C4467u32.to_le_bytes());
        let mut smd = MemDisk(sup);
        assert_eq!(detect_fs_kind(&mut smd), "super");
    }
}
