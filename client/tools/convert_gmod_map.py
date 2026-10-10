#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""
convert_gmod_map.py - Converts Valve Source Engine (.bsp) maps (e.g. Garry's Mod)
into complete, native backgrounds for Unciv VR.

Features:
  - Extracts 3D brush geometry & UV texture coordinates from VBSP v19/v20/v21.
  - Supports displacements (terrain/curved surfaces) when present.
  - Automatically identifies player spawn points (info_player_start) and centers
    the map at floor level (Y=0) facing the Unciv VR game table.
  - Extracts lighting from light_environment (sun pitch, yaw, color, energy, ambient).
  - Matches skyname to procedural sky color gradients.
  - Converts Source materials to glTF 2.0 PBR materials with reflectivity-matched
    albedos, metallic/roughness values, and embedded procedural texture patterns.
  - Generates scenery.glb and background.json ready for immediate use.
  - Optionally installs directly to ~/.unciv-vr/Backgrounds/<Name>/.
"""

import argparse
import io
import json
import math
import os
import re
import shutil
import struct
import sys
import tempfile
import zipfile
import numpy as np
from PIL import Image


def parse_bsp(bsp_path):
    with open(bsp_path, "rb") as f:
        ident = f.read(4)
        if ident != b"VBSP":
            raise ValueError(f"'{bsp_path}' is not a valid Source Engine BSP (magic={ident})")
        version = struct.unpack("<I", f.read(4))[0]
        if version not in (19, 20, 21):
            print(f"Warning: Untested BSP version {version} (expected 19, 20, or 21). Attempting parse anyway.")

        lumps = [struct.unpack("<IIII", f.read(16)) for _ in range(64)]

        # 1. ENTITIES (Lump 0)
        f.seek(lumps[0][0])
        ents_raw = f.read(lumps[0][1]).decode("latin1", errors="replace")
        entities = []
        for m in re.finditer(r"\{([^{}]*)\}", ents_raw):
            props = {}
            for line in m.group(1).strip().splitlines():
                line = line.strip()
                match = re.match(r'"([^"]+)"\s+"([^"]*)"', line)
                if match:
                    props[match.group(1).lower()] = match.group(2)
            if props:
                entities.append(props)

        # 2. PLANES (Lump 1)
        f.seek(lumps[1][0])
        p_data = f.read(lumps[1][1])
        planes = [struct.unpack("<ffffi", p_data[i * 20 : (i + 1) * 20]) for i in range(len(p_data) // 20)]

        # 3. VERTEXES (Lump 3)
        f.seek(lumps[3][0])
        v_data = f.read(lumps[3][1])
        verts = [struct.unpack("<fff", v_data[i * 12 : (i + 1) * 12]) for i in range(len(v_data) // 12)]

        # 3. EDGES (Lump 12)
        f.seek(lumps[12][0])
        e_data = f.read(lumps[12][1])
        edges = [struct.unpack("<HH", e_data[i * 4 : (i + 1) * 4]) for i in range(len(e_data) // 4)]

        # 4. SURFEDGES (Lump 13)
        f.seek(lumps[13][0])
        se_data = f.read(lumps[13][1])
        surfedges = [struct.unpack("<i", se_data[i * 4 : (i + 1) * 4])[0] for i in range(len(se_data) // 4)]

        # 5. STRING TABLE & STRING DATA (Lumps 44 & 43)
        str_data_off = lumps[43][0]
        f.seek(lumps[44][0])
        st_data = f.read(lumps[44][1])
        str_table = [struct.unpack("<i", st_data[i * 4 : (i + 1) * 4])[0] for i in range(len(st_data) // 4)]

        tex_names = []
        for s_idx in str_table:
            f.seek(str_data_off + s_idx)
            name_bytes = b""
            while True:
                c = f.read(1)
                if not c or c == b"\x00":
                    break
                name_bytes += c
            tex_names.append(name_bytes.decode("latin1"))

        # 6. TEXDATA (Lump 2)
        f.seek(lumps[2][0])
        td_data = f.read(lumps[2][1])
        texdatas = []
        for i in range(len(td_data) // 32):
            rx, ry, rz, str_id, tw, th, vw, vh = struct.unpack("<fffiiiii", td_data[i * 32 : (i + 1) * 32])
            tname = tex_names[str_id] if 0 <= str_id < len(tex_names) else ""
            texdatas.append({
                "name": tname,
                "width": max(1, tw),
                "height": max(1, th),
                "reflectivity": (rx, ry, rz),
            })

        # 7. TEXINFO (Lump 6)
        f.seek(lumps[6][0])
        ti_data = f.read(lumps[6][1])
        texinfos = []
        for i in range(len(ti_data) // 72):
            block = ti_data[i * 72 : (i + 1) * 72]
            s_vec = struct.unpack("<ffff", block[0:16])
            t_vec = struct.unpack("<ffff", block[16:32])
            flags, td_idx = struct.unpack("<ii", block[64:72])
            texinfos.append({
                "s_vec": s_vec,
                "t_vec": t_vec,
                "flags": flags,
                "texdata": td_idx,
            })

        # 8. FACES (Lump 7)
        f.seek(lumps[7][0])
        face_data = f.read(lumps[7][1])
        num_faces = len(face_data) // 56
        faces = []
        for i in range(num_faces):
            block = face_data[i * 56 : (i + 1) * 56]
            planenum = struct.unpack("<H", block[0:2])[0]
            firstedge = struct.unpack("<i", block[4:8])[0]
            numedges = struct.unpack("<h", block[8:10])[0]
            ti_idx = struct.unpack("<h", block[10:12])[0]
            disp_idx = struct.unpack("<h", block[12:14])[0]
            faces.append({
                "planenum": planenum,
                "firstedge": firstedge,
                "numedges": numedges,
                "texinfo": ti_idx,
                "dispinfo": disp_idx,
            })

        # 9. DISPINFO & DISP_VERTS (Lumps 26 & 33)
        disp_infos = []
        if lumps[26][1] > 0:
            f.seek(lumps[26][0])
            di_data = f.read(lumps[26][1])
            # Each ddispinfo_t is 176 bytes
            for i in range(len(di_data) // 176):
                dblock = di_data[i * 176 : (i + 1) * 176]
                sx, sy, sz = struct.unpack("<fff", dblock[0:12])
                vert_start, tri_start, power = struct.unpack("<iii", dblock[12:24])
                disp_infos.append({
                    "start_pos": (sx, sy, sz),
                    "vert_start": vert_start,
                    "power": power,
                })

        disp_verts = []
        if lumps[33][1] > 0:
            f.seek(lumps[33][0])
            dv_data = f.read(lumps[33][1])
            # Each ddispvert_t is 20 bytes (vec: 3 floats, dist: float, alpha: float)
            for i in range(len(dv_data) // 20):
                dv_block = dv_data[i * 20 : (i + 1) * 20]
                vx, vy, vz, dist, alpha = struct.unpack("<fffff", dv_block)
                disp_verts.append({
                    "vec": (vx, vy, vz),
                    "dist": dist,
                    "alpha": alpha,
                })

        # 10. PAKFILE (Lump 40)
        pak_data = b""
        if lumps[40][1] > 0:
            f.seek(lumps[40][0])
            pak_data = f.read(lumps[40][1])

    return {
        "version": version,
        "entities": entities,
        "planes": planes,
        "verts": verts,
        "edges": edges,
        "surfedges": surfedges,
        "texdatas": texdatas,
        "texinfos": texinfos,
        "faces": faces,
        "disp_infos": disp_infos,
        "disp_verts": disp_verts,
        "pak_data": pak_data,
    }


def generate_procedural_texture(category, base_rgb):
    """Generates a high-performance 256x256 seamless PBR albedo texture."""
    w, h = 256, 256
    arr = np.zeros((h, w, 3), dtype=np.float32) + np.array(base_rgb, dtype=np.float32)
    rng = np.random.RandomState(abs(hash(category)) % (2**31 - 1))

    if category == "concrete":
        noise = rng.normal(0, 9, (h, w, 1))
        arr = np.clip(arr + noise, 0, 255)
        # Expansion joint seam
        arr[0:2, :, :] *= 0.82
        arr[:, 0:2, :] *= 0.82

    elif category == "brick":
        brick_h, brick_w = 32, 64
        for y in range(h):
            row = y // brick_h
            is_m_y = (y % brick_h) < 3
            shift = (brick_w // 2) if (row % 2 == 1) else 0
            for x in range(w):
                is_m_x = ((x + shift) % brick_w) < 3
                if is_m_y or is_m_x:
                    arr[y, x] = [170, 170, 165]
                else:
                    arr[y, x] = np.clip(arr[y, x] + rng.uniform(-10, 10), 0, 255)

    elif category == "metal":
        streak = rng.normal(0, 7, (1, w, 1))
        streak = np.repeat(streak, h, axis=0)
        arr = np.clip(arr + streak + rng.normal(0, 3, (h, w, 1)), 0, 255)

    elif category == "wood":
        plank_h = 64
        for y in range(h):
            if (y % plank_h) < 2:
                arr[y, :] *= 0.55
            else:
                wave = np.sin(np.linspace(0, 8 * np.pi, w)) * 10
                arr[y, :, :] = np.clip(arr[y, :, :] + wave[:, np.newaxis], 0, 255)

    elif category == "glass":
        arr[:] = [180, 210, 230]

    else:
        noise = rng.normal(0, 6, (h, w, 1))
        arr = np.clip(arr + noise, 0, 255)

    img = Image.fromarray(arr.astype(np.uint8))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=85)
    return buf.getvalue()


def parse_vmt(vmt_text):
    """Simple KeyValues parser for Valve VMT material files and settings."""
    vmt_text = re.sub(r"//.*$", "", vmt_text, flags=re.MULTILINE)
    tokens = re.findall(r'"([^"]*)"|(\S+)', vmt_text)
    token_list = [t[0] if t[0] != "" else t[1] for t in tokens]
    
    props = {}
    i = 0
    while i < len(token_list):
        tok = token_list[i].lower()
        if tok in ("{", "}"):
            i += 1
            continue
        if i + 1 < len(token_list) and token_list[i + 1] not in ("{", "}"):
            props[tok] = token_list[i + 1]
            i += 2
            continue
        i += 1
    return props


def decode_dxt1_vectorized(raw_bytes, w, h):
    bx_count = (w + 3) // 4
    by_count = (h + 3) // 4
    num_blocks = bx_count * by_count
    data = np.frombuffer(raw_bytes[:num_blocks * 8], dtype=np.uint8).reshape((num_blocks, 8))
    c0 = data[:, 0].astype(np.uint16) | (data[:, 1].astype(np.uint16) << 8)
    c1 = data[:, 2].astype(np.uint16) | (data[:, 3].astype(np.uint16) << 8)
    
    r0 = (((c0 >> 11) & 0x1F) * 255 // 31).astype(np.uint8)
    g0 = (((c0 >> 5) & 0x3F) * 255 // 63).astype(np.uint8)
    b0 = ((c0 & 0x1F) * 255 // 31).astype(np.uint8)
    
    r1 = (((c1 >> 11) & 0x1F) * 255 // 31).astype(np.uint8)
    g1 = (((c1 >> 5) & 0x3F) * 255 // 63).astype(np.uint8)
    b1 = ((c1 & 0x1F) * 255 // 31).astype(np.uint8)
    
    pal = np.zeros((num_blocks, 4, 3), dtype=np.uint8)
    pal[:, 0, 0] = r0; pal[:, 0, 1] = g0; pal[:, 0, 2] = b0
    pal[:, 1, 0] = r1; pal[:, 1, 1] = g1; pal[:, 1, 2] = b1
    
    mask = c0 > c1
    c0_32 = pal[:, 0].astype(np.uint32)
    c1_32 = pal[:, 1].astype(np.uint32)
    
    col2_gt = ((2 * c0_32 + c1_32) // 3).astype(np.uint8)
    col3_gt = ((c0_32 + 2 * c1_32) // 3).astype(np.uint8)
    col2_le = ((c0_32 + c1_32) // 2).astype(np.uint8)
    col3_le = np.zeros_like(col2_le)
    
    pal[:, 2] = np.where(mask[:, None], col2_gt, col2_le)
    pal[:, 3] = np.where(mask[:, None], col3_gt, col3_le)
    
    lookups = data[:, 4].astype(np.uint32) | (data[:, 5].astype(np.uint32) << 8) | (data[:, 6].astype(np.uint32) << 16) | (data[:, 7].astype(np.uint32) << 24)
    shifts = np.arange(0, 32, 2, dtype=np.uint32)
    codes = (lookups[:, None] >> shifts[None, :]) & 0x03
    
    block_pixels = np.take_along_axis(pal, codes[:, :, None], axis=1)
    blocks_grid = block_pixels.reshape((by_count, bx_count, 4, 4, 3))
    img = blocks_grid.swapaxes(1, 2).reshape((by_count * 4, bx_count * 4, 3))
    return img[:h, :w]


def decode_dxt5_vectorized(raw_bytes, w, h):
    bx_count = (w + 3) // 4
    by_count = (h + 3) // 4
    num_blocks = bx_count * by_count
    data = np.frombuffer(raw_bytes[:num_blocks * 16], dtype=np.uint8).reshape((num_blocks, 16))
    
    a0 = data[:, 0].astype(np.uint16)
    a1 = data[:, 1].astype(np.uint16)
    a_bytes = data[:, 2:8]
    a_lookup = (
        a_bytes[:, 0].astype(np.uint64) |
        (a_bytes[:, 1].astype(np.uint64) << 8) |
        (a_bytes[:, 2].astype(np.uint64) << 16) |
        (a_bytes[:, 3].astype(np.uint64) << 24) |
        (a_bytes[:, 4].astype(np.uint64) << 32) |
        (a_bytes[:, 5].astype(np.uint64) << 40)
    )
    
    a_pal = np.zeros((num_blocks, 8), dtype=np.uint8)
    a_pal[:, 0] = a0.astype(np.uint8)
    a_pal[:, 1] = a1.astype(np.uint8)
    
    mask = a0 > a1
    for i in range(1, 7):
        val_gt = (((7 - i) * a0 + i * a1) // 7).astype(np.uint8)
        if i <= 4:
            val_le = (((5 - i) * a0 + i * a1) // 5).astype(np.uint8)
        elif i == 5:
            val_le = np.zeros(num_blocks, dtype=np.uint8)
        else:
            val_le = np.full(num_blocks, 255, dtype=np.uint8)
        a_pal[:, 1 + i] = np.where(mask, val_gt, val_le)
        
    shifts = np.arange(0, 48, 3, dtype=np.uint64)
    a_codes = ((a_lookup[:, None] >> shifts[None, :]) & 0x07).astype(np.int32)
    a_pixels = np.take_along_axis(a_pal, a_codes, axis=1)
    
    c_data = data[:, 8:16]
    c0 = c_data[:, 0].astype(np.uint16) | (c_data[:, 1].astype(np.uint16) << 8)
    c1 = c_data[:, 2].astype(np.uint16) | (c_data[:, 3].astype(np.uint16) << 8)
    
    r0 = (((c0 >> 11) & 0x1F) * 255 // 31).astype(np.uint8)
    g0 = (((c0 >> 5) & 0x3F) * 255 // 63).astype(np.uint8)
    b0 = ((c0 & 0x1F) * 255 // 31).astype(np.uint8)
    
    r1 = (((c1 >> 11) & 0x1F) * 255 // 31).astype(np.uint8)
    g1 = (((c1 >> 5) & 0x3F) * 255 // 63).astype(np.uint8)
    b1 = ((c1 & 0x1F) * 255 // 31).astype(np.uint8)
    
    c_pal = np.zeros((num_blocks, 4, 3), dtype=np.uint8)
    c_pal[:, 0, 0] = r0; c_pal[:, 0, 1] = g0; c_pal[:, 0, 2] = b0
    c_pal[:, 1, 0] = r1; c_pal[:, 1, 1] = g1; c_pal[:, 1, 2] = b1
    
    c0_32 = c_pal[:, 0].astype(np.uint32)
    c1_32 = c_pal[:, 1].astype(np.uint32)
    c_pal[:, 2] = ((2 * c0_32 + c1_32) // 3).astype(np.uint8)
    c_pal[:, 3] = ((c0_32 + 2 * c1_32) // 3).astype(np.uint8)
    
    c_lookups = c_data[:, 4].astype(np.uint32) | (c_data[:, 5].astype(np.uint32) << 8) | (c_data[:, 6].astype(np.uint32) << 16) | (c_data[:, 7].astype(np.uint32) << 24)
    c_shifts = np.arange(0, 32, 2, dtype=np.uint32)
    c_codes = (c_lookups[:, None] >> c_shifts[None, :]) & 0x03
    
    c_pixels = np.take_along_axis(c_pal, c_codes[:, :, None], axis=1)
    
    rgba_pixels = np.zeros((num_blocks, 16, 4), dtype=np.uint8)
    rgba_pixels[:, :, :3] = c_pixels
    rgba_pixels[:, :, 3] = a_pixels
    
    grid = rgba_pixels.reshape((by_count, bx_count, 4, 4, 4))
    img = grid.swapaxes(1, 2).reshape((by_count * 4, bx_count * 4, 4))
    return img[:h, :w]


def decode_vtf_stream(stream):
    """Decodes a VTF binary stream to a PIL Image."""
    hdr = stream.read(64)
    if len(hdr) < 64 or hdr[:4] != b"VTF\x00":
        return None
    magic, v_maj, v_min, hdr_size = struct.unpack("<4sIII", hdr[:16])
    w, h, flags, num_frames, first_frame = struct.unpack("<HHIHH", hdr[16:28])
    stream.seek(52)
    fmt_block = stream.read(11)
    if len(fmt_block) < 11:
        return None
    hi_fmt, mip_count, lo_fmt, lo_w, lo_h = struct.unpack("<IBIBB", fmt_block)
    
    is_cube = bool(flags & 0x00004000)
    num_faces = 6 if is_cube else 1
    
    stream.seek(hdr_size)
    if lo_fmt != 0xFFFFFFFF and lo_fmt != 0 and lo_w > 0 and lo_h > 0:
        if lo_fmt == 13: # DXT1
            lo_size = max(1, (lo_w + 3) // 4) * max(1, (lo_h + 3) // 4) * 8
        else:
            lo_size = lo_w * lo_h * 4
        stream.seek(lo_size, 1)
        
    mip_sizes = []
    for m in range(mip_count - 1, -1, -1):
        mw = max(1, w >> m)
        mh = max(1, h >> m)
        if hi_fmt in (13, 20): # DXT1
            msize = max(1, (mw + 3) // 4) * max(1, (mh + 3) // 4) * 8
        elif hi_fmt in (14, 15): # DXT3, DXT5
            msize = max(1, (mw + 3) // 4) * max(1, (mh + 3) // 4) * 16
        elif hi_fmt in (2, 3): # RGB888, BGR888
            msize = mw * mh * 3
        elif hi_fmt in (0, 1, 19): # RGBA, BGRA
            msize = mw * mh * 4
        else:
            msize = mw * mh * 4
        mip_sizes.append((m, mw, mh, msize))
        
    for m, mw, mh, msize in mip_sizes[:-1]:
        stream.seek(msize * max(1, num_frames) * num_faces, 1)
        
    m, mw, mh, msize = mip_sizes[-1]
    raw = stream.read(msize)
    if len(raw) < msize:
        return None
        
    if hi_fmt in (13, 20):
        arr = decode_dxt1_vectorized(raw, mw, mh)
        return Image.fromarray(arr, "RGB")
    elif hi_fmt == 15:
        arr = decode_dxt5_vectorized(raw, mw, mh)
        return Image.fromarray(arr, "RGBA")
    elif hi_fmt == 3: # BGR888
        arr = np.frombuffer(raw, dtype=np.uint8).reshape((mh, mw, 3))
        return Image.fromarray(arr[:, :, ::-1], "RGB")
    elif hi_fmt == 2: # RGB888
        arr = np.frombuffer(raw, dtype=np.uint8).reshape((mh, mw, 3))
        return Image.fromarray(arr, "RGB")
    elif hi_fmt == 19: # BGRA8888
        arr = np.frombuffer(raw, dtype=np.uint8).reshape((mh, mw, 4))
        return Image.fromarray(arr[:, :, [2, 1, 0, 3]], "RGBA")
    elif hi_fmt == 0: # RGBA8888
        arr = np.frombuffer(raw, dtype=np.uint8).reshape((mh, mw, 4))
        return Image.fromarray(arr, "RGBA")
    return None


class MaterialResolver:
    """Finds, parses, and decodes VMT materials and VTF textures from BSP pakfiles and directories."""
    def __init__(self, bsp_dir, pak_data=None, materials_dir=None):
        self.search_dirs = []
        if materials_dir and os.path.isdir(materials_dir):
            self.search_dirs.append(materials_dir)
        if bsp_dir:
            for cand in [
                os.path.join(bsp_dir, "materials"),
                os.path.join(bsp_dir, "..", "materials"),
                bsp_dir,
            ]:
                cand_abs = os.path.abspath(cand)
                if os.path.isdir(cand_abs) and cand_abs not in self.search_dirs:
                    self.search_dirs.append(cand_abs)

        self.pak_zip = None
        self.pak_files = {}
        if pak_data and len(pak_data) > 0:
            try:
                self.pak_zip = zipfile.ZipFile(io.BytesIO(pak_data))
                for fname in self.pak_zip.namelist():
                    norm = fname.replace("\\", "/").lower()
                    self.pak_files[norm] = fname
            except Exception as e:
                print(f"Warning: Failed to parse BSP pakfile: {e}")

        self.cache = {}
        self.vtf_loaded_count = 0

    def _find_pak_entry(self, subpath):
        norm = subpath.replace("\\", "/").lower().lstrip("/")
        return self.pak_files.get(norm)

    def _read_file_bytes(self, rel_path):
        pak_name = self._find_pak_entry(rel_path)
        if not pak_name:
            pak_name = self._find_pak_entry(f"materials/{rel_path}")
        if pak_name and self.pak_zip:
            try:
                return self.pak_zip.read(pak_name)
            except Exception:
                pass

        for sdir in self.search_dirs:
            for cand in [
                os.path.join(sdir, rel_path),
                os.path.join(sdir, f"materials/{rel_path}"),
                os.path.join(sdir, os.path.basename(rel_path)),
            ]:
                if os.path.isfile(cand):
                    try:
                        with open(cand, "rb") as f:
                            return f.read()
                    except Exception:
                        pass
        return None

    def resolve(self, mat_name, default_category, base_rgb):
        """Resolves material name to (img_bytes, mime_type, alpha_mode, metallic, roughness, is_vtf)."""
        clean_name = mat_name.strip().replace("\\", "/").lower()
        if clean_name in self.cache:
            return self.cache[clean_name]

        is_metal = default_category == "metal"
        is_glass = default_category == "glass"
        metallic = 0.85 if is_metal else 0.0
        roughness = 0.10 if is_glass else (0.35 if is_metal else 0.82)
        alpha_mode = "BLEND" if is_glass else "OPAQUE"

        # 1. Look for .vmt
        vmt_data = self._read_file_bytes(f"{clean_name}.vmt")
        base_tex_name = clean_name
        if vmt_data:
            try:
                vmt_text = vmt_data.decode("latin1", errors="replace")
                props = parse_vmt(vmt_text)
                if "include" in props:
                    inc_path = props["include"].replace("\\", "/").lower()
                    if inc_path.startswith("materials/"):
                        inc_path = inc_path[len("materials/"):]
                    inc_data = self._read_file_bytes(inc_path)
                    if inc_data:
                        inc_props = parse_vmt(inc_data.decode("latin1", errors="replace"))
                        inc_props.update(props)
                        props = inc_props

                if "$basetexture" in props:
                    base_tex_name = props["$basetexture"].replace("\\", "/").lower()
                if "$translucent" in props and props["$translucent"].strip() in ("1", "true"):
                    alpha_mode = "BLEND"
                elif "$alphatest" in props and props["$alphatest"].strip() in ("1", "true"):
                    alpha_mode = "MASK"
                if "$surfaceprop" in props:
                    sp = props["$surfaceprop"].lower()
                    if any(k in sp for k in ("metal", "chainlink", "iron")):
                        metallic = 0.85
                        roughness = 0.35
                    elif "glass" in sp:
                        alpha_mode = "BLEND"
                        roughness = 0.10
            except Exception as e:
                print(f"Warning: Error parsing VMT for {clean_name}: {e}")

        # 2. Look for .vtf
        if base_tex_name.endswith(".vtf"):
            base_tex_name = base_tex_name[:-4]
        vtf_data = self._read_file_bytes(f"{base_tex_name}.vtf")

        if vtf_data:
            try:
                img = decode_vtf_stream(io.BytesIO(vtf_data))
                if img:
                    if img.width > 1024 or img.height > 1024:
                        img = img.resize((min(1024, img.width), min(1024, img.height)), Image.Resampling.BILINEAR)

                    buf = io.BytesIO()
                    if img.mode == "RGBA" and alpha_mode in ("BLEND", "MASK"):
                        img.save(buf, format="PNG")
                        mime = "image/png"
                    else:
                        if img.mode != "RGB":
                            img = img.convert("RGB")
                        img.save(buf, format="JPEG", quality=85)
                        mime = "image/jpeg"
                    res = (buf.getvalue(), mime, alpha_mode, metallic, roughness, True)
                    self.cache[clean_name] = res
                    self.vtf_loaded_count += 1
                    return res
            except Exception as e:
                print(f"Warning: Failed decoding VTF {base_tex_name}: {e}")

        # 3. Fallback to procedural reflectivity-matched texture
        jpeg_bytes = generate_procedural_texture(default_category, [int(base_rgb[0]*255), int(base_rgb[1]*255), int(base_rgb[2]*255)])
        res = (jpeg_bytes, "image/jpeg", alpha_mode, metallic, roughness, False)
        self.cache[clean_name] = res
        return res


def find_main_floor_center(data):
    """Finds the bounding center and floor elevation of the largest upward-facing floor area."""
    verts = np.array(data["verts"])
    faces = data["faces"]
    edges = data["edges"]
    surfedges = data["surfedges"]
    texinfos = data["texinfos"]
    texdatas = data["texdatas"]
    planes = data["planes"]

    from collections import defaultdict
    z_areas = defaultdict(float)
    z_faces = defaultdict(list)

    for face in faces:
        ti = texinfos[face["texinfo"]]
        tname = texdatas[ti["texdata"]]["name"].lower()
        if any(k in tname for k in ("nodraw", "sky", "clip", "trigger", "invisible")):
            continue
        p = planes[face["planenum"]]
        nx, ny, nz, dist, _ = p
        if nz > 0.95:  # Upward-facing horizontal floor
            firstedge = face["firstedge"]
            numedges = face["numedges"]
            if numedges < 3:
                continue
            poly_v = [verts[edges[surfedges[firstedge + e]][0] if surfedges[firstedge + e] > 0 else edges[-surfedges[firstedge + e]][1]] for e in range(numedges)]
            poly_v = np.array(poly_v)
            # 2D polygon area
            area = 0.5 * abs(np.dot(poly_v[:, 0], np.roll(poly_v[:, 1], 1)) - np.dot(poly_v[:, 1], np.roll(poly_v[:, 0], 1)))
            z_lvl = round(dist, 0)
            z_areas[z_lvl] += area
            z_faces[z_lvl].append(poly_v)

    if not z_areas:
        return 0.0, 0.0, 0.0

    best_z = max(z_areas, key=z_areas.get)
    all_pts = np.concatenate(z_faces[best_z], axis=0)
    mins = all_pts.min(axis=0)
    maxs = all_pts.max(axis=0)
    center_x = (mins[0] + maxs[0]) / 2.0
    center_y = (mins[1] + maxs[1]) / 2.0
    return float(center_x), float(center_y), float(best_z)


def unpack_gma(gma_input, out_dir):
    """Unpacks a Garry's Mod Addon (.gma) archive to out_dir."""
    if isinstance(gma_input, (str, os.PathLike)):
        with open(gma_input, "rb") as f:
            data = f.read()
    else:
        data = gma_input

    if len(data) < 22 or data[:4] != b"GMAD":
        raise ValueError("Not a valid Garry's Mod Addon (GMA) file (magic != GMAD)")

    ver = data[4]
    idx = 5 + 16  # skip steamid (8) + timestamp (8)
    if ver > 1:
        idx += 1  # required_content
    # Skip title, desc, author
    idx = data.find(b"\x00", idx) + 1
    idx = data.find(b"\x00", idx) + 1
    idx = data.find(b"\x00", idx) + 1
    idx += 4  # addon_version

    files = []
    while True:
        fnum = struct.unpack("<I", data[idx:idx + 4])[0]
        idx += 4
        if fnum == 0:
            break
        fname_end = data.find(b"\x00", idx)
        fname = data[idx:fname_end].decode("utf-8", errors="replace")
        idx = fname_end + 1
        fsize = struct.unpack("<q", data[idx:idx + 8])[0]
        idx += 8
        crc = struct.unpack("<I", data[idx:idx + 4])[0]
        idx += 4
        files.append((fname, fsize))

    curr_off = idx
    extracted = []
    # An addon is a file from a stranger: never let a name like "../../x" or "C:/x" write outside out_dir
    # (os.path.join drops out_dir entirely for an absolute name)
    base = os.path.realpath(out_dir)
    for fname, fsize in files:
        if fsize < 0 or curr_off + fsize > len(data):
            raise ValueError(f"Corrupt GMA: '{fname}' runs past the end of the file")
        fbytes = data[curr_off:curr_off + fsize]
        curr_off += fsize
        target = os.path.realpath(os.path.join(base, fname.replace("\\", "/").lstrip("/")))
        if os.path.commonpath([base, target]) != base:
            print(f"Warning: skipping '{fname}' in the addon - it points outside the folder it's unpacked into")
            continue
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "wb") as out_f:
            out_f.write(fbytes)
        extracted.append(target)
    return extracted


def convert_gmod_map(
    input_path=None,
    out_dir=None,
    bg_name=None,
    scale=0.0254,
    spawn_idx=0,
    table_pos=None,
    center_floor=False,
    table_yaw=None,
    table_offset=(0.0, 0.0, 0.0),
    materials_dir=None,
    map_name=None,
    install_user=True,
    bsp_path=None,
):
    if input_path is None:
        input_path = bsp_path
    if not input_path:
        raise ValueError("Must provide a .bsp map file, .gma addon, or .zip archive to convert.")

    input_path = os.path.abspath(input_path)

    # Check if input is a GMA addon file
    is_gma = input_path.lower().endswith(".gma")
    if not is_gma and os.path.isfile(input_path):
        try:
            with open(input_path, "rb") as test_f:
                if test_f.read(4) == b"GMAD":
                    is_gma = True
        except Exception:
            pass

    if is_gma:
        print(f"[*] Detected Garry's Mod Addon (.gma): {input_path}")
        with tempfile.TemporaryDirectory() as tmp_dir:
            extracted_files = unpack_gma(input_path, tmp_dir)
            bsp_candidates = [f for f in extracted_files if f.lower().endswith(".bsp")]
            if not bsp_candidates:
                raise ValueError(f"No .bsp map found inside GMA addon '{input_path}'")

            # Select map
            selected_bsp = bsp_candidates[0]
            if map_name:
                for cand in bsp_candidates:
                    if map_name.lower() in os.path.basename(cand).lower():
                        selected_bsp = cand
                        break
            else:
                bsp_candidates.sort(key=lambda x: os.path.getsize(x), reverse=True)
                selected_bsp = bsp_candidates[0]

            print(f"[*] Selected map from GMA: '{os.path.basename(selected_bsp)}'")
            zip_mat_dir = materials_dir or os.path.join(tmp_dir, "materials")
            if not os.path.isdir(zip_mat_dir):
                zip_mat_dir = None

            if not bg_name:
                b_name = os.path.splitext(os.path.basename(selected_bsp))[0]
                clean = re.sub(r"^(gm_|de_|cs_|dm_)", "", b_name)
                bg_name = clean.replace("_", " ").title()

            return convert_gmod_map(
                input_path=selected_bsp,
                out_dir=out_dir,
                bg_name=bg_name,
                scale=scale,
                spawn_idx=spawn_idx,
                table_pos=table_pos,
                center_floor=center_floor,
                table_yaw=table_yaw,
                table_offset=table_offset,
                materials_dir=zip_mat_dir,
                install_user=install_user,
            )

    # Check if input is a ZIP archive (exclude .bsp files which contain embedded pakfile zips)
    if not input_path.lower().endswith(".bsp") and (input_path.lower().endswith(".zip") or zipfile.is_zipfile(input_path)):
        print(f"[*] Detected ZIP archive: {input_path}")
        with zipfile.ZipFile(input_path, "r") as zf:
            print(f"[*] Extracting map archive to temporary workspace...")
            with tempfile.TemporaryDirectory() as tmp_dir:
                zf.extractall(tmp_dir)

                # Unpack any embedded .gma files found in the zip!
                gma_files = []
                for root, _, files in os.walk(tmp_dir):
                    for file in files:
                        if file.lower().endswith(".gma") and not file.startswith("._"):
                            gma_files.append(os.path.join(root, file))

                for gma_path in gma_files:
                    try:
                        print(f"[*] Unpacking embedded addon: {os.path.basename(gma_path)}...")
                        unpack_gma(gma_path, tmp_dir)
                    except Exception as e:
                        print(f"Warning: Failed unpacking {os.path.basename(gma_path)}: {e}")

                # Discover all .bsp map files in tmp_dir
                bsp_candidates = []
                for root, _, files in os.walk(tmp_dir):
                    for file in files:
                        if file.lower().endswith(".bsp") and not file.startswith("._"):
                            bsp_candidates.append(os.path.join(root, file))

                if not bsp_candidates:
                    raise ValueError(f"No .bsp map file found in ZIP archive '{input_path}'")

                # Select best candidate
                selected_bsp = bsp_candidates[0]
                if map_name:
                    for cand in bsp_candidates:
                        if map_name.lower() in os.path.basename(cand).lower():
                            selected_bsp = cand
                            break
                else:
                    def map_priority(p):
                        bname = os.path.basename(p).lower()
                        is_gm = 1 if bname.startswith("gm_") else 0
                        return (is_gm, os.path.getsize(p))

                    bsp_candidates.sort(key=map_priority, reverse=True)
                    selected_bsp = bsp_candidates[0]

                print(f"[*] Selected map: '{os.path.basename(selected_bsp)}' ({len(bsp_candidates)} map variants found)")

                zip_mat_dir = materials_dir
                if not zip_mat_dir:
                    cand_mat = os.path.join(tmp_dir, "materials")
                    if os.path.isdir(cand_mat):
                        zip_mat_dir = cand_mat
                    else:
                        for root, dirs, _ in os.walk(tmp_dir):
                            if "materials" in dirs:
                                zip_mat_dir = os.path.join(root, "materials")
                                break

                if not bg_name:
                    b_name = os.path.splitext(os.path.basename(selected_bsp))[0]
                    clean = re.sub(r"^(gm_|de_|cs_|dm_)", "", b_name)
                    bg_name = clean.replace("_", " ").title()

                return convert_gmod_map(
                    input_path=selected_bsp,
                    out_dir=out_dir,
                    bg_name=bg_name,
                    scale=scale,
                    spawn_idx=spawn_idx,
                    table_pos=table_pos,
                    center_floor=center_floor,
                    table_yaw=table_yaw,
                    table_offset=table_offset,
                    materials_dir=zip_mat_dir,
                    install_user=install_user,
                )

    bsp_path = input_path
    base_name = os.path.splitext(os.path.basename(bsp_path))[0]

    if not bg_name:
        # Generate friendly name: e.g. "gm_skatepark_v2" -> "Skatepark v2"
        clean = re.sub(r"^(gm_|de_|cs_|dm_)", "", base_name)
        bg_name = clean.replace("_", " ").title()

    if not out_dir:
        # Default to local user mod directory (~/.unciv-vr/Backgrounds/<Folder>) to keep repo clean of copyright
        safe_folder = re.sub(r"[^\w\-]", "", bg_name.replace(" ", ""))
        out_dir = os.path.expanduser(f"~/.unciv-vr/Backgrounds/{safe_folder}")

    out_dir = os.path.abspath(out_dir)
    os.makedirs(out_dir, exist_ok=True)

    print(f"==================================================")
    print(f" Converting Garry's Mod Map: {base_name}")
    print(f" Destination: {out_dir}")
    print(f" Scale Factor: {scale:.5f} m/unit")
    print(f"==================================================")

    data = parse_bsp(bsp_path)
    ents = data["entities"]

    # Initialize Material & Texture Resolver (VMT/VTF support)
    resolver = MaterialResolver(
        bsp_dir=os.path.dirname(bsp_path),
        pak_data=data.get("pak_data"),
        materials_dir=materials_dir,
    )

    # 1. Environment & Lighting
    worldspawn = next((e for e in ents if e.get("classname") == "worldspawn"), {})
    light_env = next((e for e in ents if e.get("classname") == "light_environment"), {})
    spawns = [e for e in ents if e.get("classname") in ("info_player_start", "info_player_deathmatch")]

    skyname = worldspawn.get("skyname", "sky_day01_01")
    print(f"[*] Map Skyname: '{skyname}'")
    print(f"[*] Found {len(spawns)} player spawn points")

    if spawns:
        sp = spawns[min(spawn_idx, len(spawns) - 1)]
        sp_orig = [float(x) for x in sp.get("origin", "0 0 0").split()]
        sp_ang = [float(x) for x in sp.get("angles", "0 0 0").split()]
    else:
        sp_orig = [0.0, 0.0, 0.0]
        sp_ang = [0.0, 0.0, 0.0]

    spawn_x, spawn_y, spawn_z = sp_orig[0], sp_orig[1], sp_orig[2]
    spawn_yaw = sp_ang[1]

    # Determine table anchor position and facing angle
    if table_pos is not None:
        table_x, table_y, table_z = float(table_pos[0]), float(table_pos[1]), float(table_pos[2])
        facing_yaw = float(table_yaw) if table_yaw is not None else 180.0
        forward_push = 0.0
        print(f"[*] Custom Table Position: ({table_x:.1f}, {table_y:.1f}, {table_z:.1f}), Facing Yaw={facing_yaw:.1f}°")
    elif center_floor:
        table_x, table_y, table_z = find_main_floor_center(data)
        facing_yaw = float(table_yaw) if table_yaw is not None else 180.0
        forward_push = 0.0
        print(f"[*] Auto-Centered Table in Middle of Floor: ({table_x:.1f}, {table_y:.1f}, {table_z:.1f}), Facing Yaw={facing_yaw:.1f}°")
    else:
        # Default: Spawn position (player stands at spawn, table 1m in front)
        facing_yaw = float(table_yaw) if table_yaw is not None else spawn_yaw
        table_x = spawn_x
        table_y = spawn_y
        table_z = spawn_z
        forward_push = 1.0
        print(f"[*] Table placed at Spawn #{spawn_idx}: ({table_x:.1f}, {table_y:.1f}, {table_z:.1f}), Facing Yaw={facing_yaw:.1f}°")

    # Coordinate transformation:
    # Rotate Source horizontal (dx, dy) by facing_yaw so facing direction points to -Z in Godot.
    # Player in Unciv VR stands at Z = 1.0 overlooking table at Z = 0.
    yaw_rad = math.radians(facing_yaw)
    cos_y = math.cos(yaw_rad)
    sin_y = math.sin(yaw_rad)
    off_x, off_y, off_z = table_offset

    def transform_point(x, y, z):
        dx = x - table_x
        dy = y - table_y
        dz = z - table_z
        gx = (dx * (-sin_y) + dy * cos_y) * scale + off_x
        gy = dz * scale + off_y
        gz = -(dx * cos_y + dy * sin_y) * scale + forward_push + off_z
        return (gx, gy, gz)

    # 2. Extract Geometry Faces
    verts = data["verts"]
    edges = data["edges"]
    surfedges = data["surfedges"]
    texdatas = data["texdatas"]
    texinfos = data["texinfos"]
    faces = data["faces"]

    materials_mesh = {}

    for face in faces:
        ti_idx = face["texinfo"]
        ti = texinfos[ti_idx]
        flags = ti["flags"]
        td = texdatas[ti["texdata"]]
        tname = td["name"].lower()

        # Filter tool textures & skybox
        if flags & 0x0080 or any(k in tname for k in ("toolsnodraw", "toolsclip", "toolstrigger", "playerclip", "blockbullets", "toolsinvisible")):
            continue
        if flags & 0x0004 or flags & 0x0002 or "toolsskybox" in tname:
            continue
        if face["numedges"] < 3:
            continue

        # Clean material name
        base_mat = re.sub(r"^maps/[^/]+/", "", tname)
        base_mat = re.sub(r"_-?\d+_-?\d+_-?\d+$", "", base_mat)

        # Polygon vertex indices
        firstedge = face["firstedge"]
        poly_v_idx = []
        for e_idx in range(face["numedges"]):
            se = surfedges[firstedge + e_idx]
            v_idx = edges[se][0] if se > 0 else edges[-se][1]
            poly_v_idx.append(v_idx)

        # 3D Positions & UVs
        poly_positions = []
        poly_uvs = []
        for vi in poly_v_idx:
            vx, vy, vz = verts[vi]
            gx, gy, gz = transform_point(vx, vy, vz)
            poly_positions.append((gx, gy, gz))

            u = (vx * ti["s_vec"][0] + vy * ti["s_vec"][1] + vz * ti["s_vec"][2] + ti["s_vec"][3]) / td["width"]
            v = (vx * ti["t_vec"][0] + vy * ti["t_vec"][1] + vz * ti["t_vec"][2] + ti["t_vec"][3]) / td["height"]
            poly_uvs.append((u, v))

        # Face normal
        p0 = np.array(poly_positions[0])
        p1 = np.array(poly_positions[1])
        p2 = np.array(poly_positions[2])
        n = np.cross(p1 - p0, p2 - p0)
        norm_len = np.linalg.norm(n)
        fn = (n / norm_len).tolist() if norm_len > 1e-6 else [0.0, 1.0, 0.0]

        if base_mat not in materials_mesh:
            materials_mesh[base_mat] = {
                "positions": [],
                "normals": [],
                "uvs": [],
                "indices": [],
                "reflectivity": td["reflectivity"],
            }

        group = materials_mesh[base_mat]
        base_idx = len(group["positions"])

        for pos, uv in zip(poly_positions, poly_uvs):
            group["positions"].append(pos)
            group["normals"].append(fn)
            group["uvs"].append(uv)

        # Fan triangulation
        for k in range(1, face["numedges"] - 1):
            group["indices"].extend([base_idx, base_idx + k, base_idx + k + 1])

    # 3. Handle Displacements (if present)
    disp_infos = data["disp_infos"]
    disp_verts = data["disp_verts"]
    if disp_infos and disp_verts:
        print(f"[*] Processing {len(disp_infos)} displacement surfaces...")
        for face in faces:
            disp_idx = face["dispinfo"]
            if disp_idx < 0 or disp_idx >= len(disp_infos):
                continue
            dinfo = disp_infos[disp_idx]
            ti = texinfos[face["texinfo"]]
            td = texdatas[ti["texdata"]]
            base_mat = re.sub(r"^maps/[^/]+/", "", td["name"].lower())
            base_mat = re.sub(r"_-?\d+_-?\d+_-?\d+$", "", base_mat)

            # 4 base corners
            firstedge = face["firstedge"]
            corner_verts = [verts[edges[surfedges[firstedge + e]][0] if surfedges[firstedge + e] > 0 else edges[-surfedges[firstedge + e]][1]] for e in range(4)]
            if len(corner_verts) < 4:
                continue

            power = dinfo["power"]
            grid_dim = (1 << power) + 1
            v_start = dinfo["vert_start"]

            grid_pos = []
            grid_uv = []
            for j in range(grid_dim):
                v_frac = float(j) / float(grid_dim - 1)
                for i in range(grid_dim):
                    u_frac = float(i) / float(grid_dim - 1)
                    # Bilinear interpolation
                    p_top = (1.0 - u_frac) * np.array(corner_verts[0]) + u_frac * np.array(corner_verts[1])
                    p_bot = (1.0 - u_frac) * np.array(corner_verts[3]) + u_frac * np.array(corner_verts[2])
                    base_p = (1.0 - v_frac) * p_top + v_frac * p_bot

                    dv = disp_verts[v_start + j * grid_dim + i]
                    disp_vec = np.array(dv["vec"]) * dv["dist"]
                    final_p = base_p + disp_vec

                    gx, gy, gz = transform_point(final_p[0], final_p[1], final_p[2])
                    grid_pos.append((gx, gy, gz))

                    u = (final_p[0] * ti["s_vec"][0] + final_p[1] * ti["s_vec"][1] + final_p[2] * ti["s_vec"][2] + ti["s_vec"][3]) / td["width"]
                    v = (final_p[0] * ti["t_vec"][0] + final_p[1] * ti["t_vec"][1] + final_p[2] * ti["t_vec"][2] + ti["t_vec"][3]) / td["height"]
                    grid_uv.append((u, v))

            if base_mat not in materials_mesh:
                materials_mesh[base_mat] = {
                    "positions": [], "normals": [], "uvs": [], "indices": [],
                    "reflectivity": td["reflectivity"]
                }
            group = materials_mesh[base_mat]
            base_idx = len(group["positions"])
            group["positions"].extend(grid_pos)
            group["uvs"].extend(grid_uv)
            # Up normal default for displacement
            group["normals"].extend([[0.0, 1.0, 0.0]] * len(grid_pos))

            for j in range(grid_dim - 1):
                for i in range(grid_dim - 1):
                    i0 = base_idx + j * grid_dim + i
                    i1 = i0 + 1
                    i2 = base_idx + (j + 1) * grid_dim + i
                    i3 = i2 + 1
                    group["indices"].extend([i0, i2, i1, i1, i2, i3])

    total_tris = sum(len(m["indices"]) // 3 for m in materials_mesh.values())
    print(f"[*] Extracted {len(materials_mesh)} materials with {total_tris:,} triangles")

    # 4. Build glTF 2.0 Binary (.glb)
    nodes = []
    meshes = []
    materials = []
    accessors = []
    buffer_views = []
    images = []
    textures = []
    samplers = [{
        "magFilter": 9729,  # LINEAR
        "minFilter": 9987,  # LINEAR_MIPMAP_LINEAR
        "wrapS": 10497,     # REPEAT
        "wrapT": 10497      # REPEAT
    }]
    bin_data = b""

    def pad4(b):
        pad = (4 - (len(b) % 4)) % 4
        return b + b"\x00" * pad

    # Category texture cache
    tex_cache = {}

    for mat_idx, (mname, mdata) in enumerate(materials_mesh.items()):
        pos_arr = np.array(mdata["positions"], dtype=np.float32)
        norm_arr = np.array(mdata["normals"], dtype=np.float32)
        uv_arr = np.array(mdata["uvs"], dtype=np.float32)
        idx_arr = np.array(mdata["indices"], dtype=np.uint32)

        if len(idx_arr) == 0:
            continue

        rx, ry, rz = mdata["reflectivity"]
        base_r = min(1.0, max(0.08, rx ** (1.0 / 2.2)))
        base_g = min(1.0, max(0.08, ry ** (1.0 / 2.2)))
        base_b = min(1.0, max(0.08, rz ** (1.0 / 2.2)))

        is_metal = any(k in mname for k in ("metal", "citadel", "combine", "pipe", "grate", "rail"))
        is_glass = any(k in mname for k in ("glass", "window"))
        is_wood = any(k in mname for k in ("wood", "plank", "shingles"))
        is_brick = any(k in mname for k in ("brick", "masonry"))
        is_concrete = any(k in mname for k in ("concrete", "plaster", "storefront", "building"))

        cat = "glass" if is_glass else ("metal" if is_metal else ("wood" if is_wood else ("brick" if is_brick else "concrete")))

        # Resolve material through MaterialResolver (checking PAKFILE, materials_dir, VMT, VTF)
        img_bytes, mime_type, alpha_mode, metallic, roughness, is_vtf = resolver.resolve(
            mname, cat, (base_r, base_g, base_b)
        )
        alpha_val = 0.40 if is_glass else 1.0

        # Generate / assign embedded texture
        tex_key = mname if is_vtf else f"{cat}_{int(base_r*255)}_{int(base_g*255)}_{int(base_b*255)}"
        if tex_key not in tex_cache:
            img_bv = len(buffer_views)
            img_off = len(bin_data)
            bin_data += pad4(img_bytes)
            buffer_views.append({"buffer": 0, "byteOffset": img_off, "byteLength": len(img_bytes)})
            img_idx = len(images)
            images.append({"bufferView": img_bv, "mimeType": mime_type})
            t_idx = len(textures)
            textures.append({"sampler": 0, "source": img_idx})
            tex_cache[tex_key] = t_idx

        mat_def = {
            "name": mname,
            "pbrMetallicRoughness": {
                "baseColorFactor": [1.0, 1.0, 1.0, float(alpha_val)],
                "baseColorTexture": {"index": tex_cache[tex_key]},
                "metallicFactor": float(metallic),
                "roughnessFactor": float(roughness),
            },
            "alphaMode": alpha_mode,
            "doubleSided": False,
        }
        materials.append(mat_def)
        curr_mat_idx = len(materials) - 1

        # Buffer views and Accessors
        pos_bytes = pos_arr.tobytes()
        norm_bytes = norm_arr.tobytes()
        uv_bytes = uv_arr.tobytes()
        idx_bytes = idx_arr.tobytes()

        # POS
        pos_bv = len(buffer_views)
        pos_off = len(bin_data)
        bin_data += pad4(pos_bytes)
        buffer_views.append({"buffer": 0, "byteOffset": pos_off, "byteLength": len(pos_bytes)})
        pos_acc = len(accessors)
        accessors.append({
            "bufferView": pos_bv, "componentType": 5126, "count": len(pos_arr),
            "type": "VEC3", "min": pos_arr.min(axis=0).tolist(), "max": pos_arr.max(axis=0).tolist(),
        })

        # NORM
        norm_bv = len(buffer_views)
        norm_off = len(bin_data)
        bin_data += pad4(norm_bytes)
        buffer_views.append({"buffer": 0, "byteOffset": norm_off, "byteLength": len(norm_bytes)})
        norm_acc = len(accessors)
        accessors.append({
            "bufferView": norm_bv, "componentType": 5126, "count": len(norm_arr),
            "type": "VEC3", "min": norm_arr.min(axis=0).tolist(), "max": norm_arr.max(axis=0).tolist(),
        })

        # UV
        uv_bv = len(buffer_views)
        uv_off = len(bin_data)
        bin_data += pad4(uv_bytes)
        buffer_views.append({"buffer": 0, "byteOffset": uv_off, "byteLength": len(uv_bytes)})
        uv_acc = len(accessors)
        accessors.append({
            "bufferView": uv_bv, "componentType": 5126, "count": len(uv_arr),
            "type": "VEC2", "min": uv_arr.min(axis=0).tolist(), "max": uv_arr.max(axis=0).tolist(),
        })

        # IDX
        idx_bv = len(buffer_views)
        idx_off = len(bin_data)
        bin_data += pad4(idx_bytes)
        buffer_views.append({"buffer": 0, "byteOffset": idx_off, "byteLength": len(idx_bytes)})
        idx_acc = len(accessors)
        accessors.append({
            "bufferView": idx_bv, "componentType": 5125, "count": len(idx_arr),
            "type": "SCALAR", "min": [int(idx_arr.min())], "max": [int(idx_arr.max())],
        })

        mesh_idx = len(meshes)
        meshes.append({
            "name": mname,
            "primitives": [{
                "attributes": {
                    "POSITION": pos_acc,
                    "NORMAL": norm_acc,
                    "TEXCOORD_0": uv_acc,
                },
                "indices": idx_acc,
                "material": curr_mat_idx,
            }],
        })
        node_idx = len(nodes)
        nodes.append({"name": mname, "mesh": mesh_idx})

    gltf = {
        "asset": {"version": "2.0", "generator": "unciv-vr-gmod-converter"},
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "scene": 0,
        "nodes": nodes,
        "meshes": meshes,
        "materials": materials,
        "textures": textures,
        "images": images,
        "samplers": samplers,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(bin_data)}],
    }

    json_str = json.dumps(gltf, separators=(",", ":"))
    json_bytes = json_str.encode("utf-8")
    json_pad = (4 - (len(json_bytes) % 4)) % 4
    json_bytes += b" " * json_pad

    bin_pad = (4 - (len(bin_data) % 4)) % 4
    bin_data += b"\x00" * bin_pad

    total_len = 12 + 8 + len(json_bytes) + 8 + len(bin_data)
    header = struct.pack("<4sII", b"glTF", 2, total_len)
    json_hdr = struct.pack("<II", len(json_bytes), 0x4E4F534A)
    bin_hdr = struct.pack("<II", len(bin_data), 0x004E4942)

    glb_path = os.path.join(out_dir, "scenery.glb")
    with open(glb_path, "wb") as out_f:
        out_f.write(header)
        out_f.write(json_hdr)
        out_f.write(json_bytes)
        out_f.write(bin_hdr)
        out_f.write(bin_data)
    print(f"[*] Wrote 3D scenery model: {glb_path} ({os.path.getsize(glb_path) / 1024:.1f} KB)")

    # 5. Extract Sun & Sky Configuration
    sun_pitch = -50.0
    sun_yaw = 45.0
    sun_color = [255, 248, 235]
    sun_energy = 1.6
    ambient_color = [185, 200, 220]
    ambient_energy = 0.65

    if light_env:
        if "pitch" in light_env:
            sun_pitch = float(light_env["pitch"])
        if "angles" in light_env:
            s_yaw = float(light_env["angles"].split()[1])
            sun_yaw = (s_yaw - facing_yaw + 180.0) % 360.0
        if "_light" in light_env:
            parts = light_env["_light"].split()
            if len(parts) >= 4:
                sun_color = [int(float(parts[0])), int(float(parts[1])), int(float(parts[2]))]
                sun_energy = round(float(parts[3]) / 450.0, 2)
        if "_ambient" in light_env:
            parts = light_env["_ambient"].split()
            if len(parts) >= 4:
                ambient_color = [int(float(parts[0])), int(float(parts[1])), int(float(parts[2]))]
                ambient_energy = round(float(parts[3]) / 80.0, 2)

    # Procedural sky matching Source skyname
    sky_preset = {
        "top": [90, 140, 220],
        "horizon": [200, 220, 240],
        "groundHorizon": [180, 195, 205],
        "groundBottom": [130, 140, 150],
        "sunSize": 15.0,
    }
    sky_lower = skyname.lower()
    if "night" in sky_lower:
        sky_preset = {
            "top": [10, 15, 30],
            "horizon": [30, 40, 60],
            "groundHorizon": [20, 25, 35],
            "groundBottom": [5, 8, 12],
            "sunSize": 25.0,
        }
    elif "sunset" in sky_lower or "dusk" in sky_lower:
        sky_preset = {
            "top": [70, 75, 130],
            "horizon": [245, 145, 90],
            "groundHorizon": [140, 90, 80],
            "groundBottom": [40, 30, 30],
            "sunSize": 22.0,
        }

    author_val = worldspawn.get("author")
    if not author_val:
        # Check settings/maps/<base_name>.txt
        settings_cand = os.path.join(os.path.dirname(bsp_path), "..", "settings", "maps", f"{base_name}.txt")
        if os.path.isfile(settings_cand):
            try:
                with open(settings_cand, "r", encoding="utf-8", errors="replace") as sf:
                    sprops = parse_vmt(sf.read())
                    if "credits" in sprops:
                        author_val = sprops["credits"]
            except Exception:
                pass
    if not author_val:
        author_val = "Valve / Community"

    bg_json = {
        "name": bg_name,
        "author": f"{author_val}",
        "description": f"Converted from Garry's Mod map {base_name}",
        "sky": sky_preset,
        "ambient": {"color": ambient_color, "energy": max(0.4, min(1.5, ambient_energy))},
        "sun": {
            "pitch": sun_pitch,
            "yaw": round(sun_yaw, 1),
            "color": sun_color,
            "energy": max(0.6, min(2.5, sun_energy)),
            "shadows": True,
        },
        "floor": True,
        "scenery": "scenery",
    }

    json_path = os.path.join(out_dir, "background.json")
    with open(json_path, "w", encoding="utf-8") as jf:
        json.dump(bg_json, jf, indent=4)
    print(f"[*] Wrote background configuration: {json_path}")
    print(f"[*] Textures resolved: {resolver.vtf_loaded_count} authentic VTF decoded, {len(materials_mesh) - resolver.vtf_loaded_count} procedural PBR fallbacks")

    # 6. Install to ~/.unciv-vr/Backgrounds/ (if out_dir was elsewhere)
    user_mod_dir = os.path.expanduser(f"~/.unciv-vr/Backgrounds/{os.path.basename(out_dir)}")
    if os.path.abspath(out_dir) != os.path.abspath(user_mod_dir) and install_user:
        os.makedirs(user_mod_dir, exist_ok=True)
        shutil.copy2(glb_path, os.path.join(user_mod_dir, "scenery.glb"))
        shutil.copy2(json_path, os.path.join(user_mod_dir, "background.json"))
        print(f"[*] Synced to user mod folder: {user_mod_dir}")

    print(f"\nSuccessfully converted '{base_name}' to background '{bg_name}'!")
    return out_dir


def main():
    parser = argparse.ArgumentParser(
        description="Convert a Garry's Mod / Source Engine map (.bsp) into an Unciv VR background."
    )
    parser.add_argument("input_path", help="Path to a .bsp map file, .gma addon, or .zip archive containing maps")
    parser.add_argument("--name", "-n", help="Name for the background (defaults to map name)")
    parser.add_argument("--map", help="Specific map name to extract if archive contains multiple maps (e.g. gm_peachs_castle)")
    parser.add_argument("--out", "-o", help="Output directory (defaults to ~/.unciv-vr/Backgrounds/<Name>/)")
    parser.add_argument("--scale", "-s", type=float, default=0.0254, help="Scale factor from Hammer units to meters (default: 0.0254)")
    parser.add_argument("--table-pos", nargs=3, type=float, metavar=("X", "Y", "Z"),
                        help="Custom table position in Source Hammer coordinates (e.g. --table-pos 5796 0 -240)")
    parser.add_argument("--center", "--middle", dest="center_floor", action="store_true",
                        help="Automatically place table in the center/middle of the map's main floor area")
    parser.add_argument("--table-yaw", type=float, default=None,
                        help="Facing direction angle in degrees (0=East, 90=North, 180=West, 270=South). Default: 180° for center, or spawn yaw")
    parser.add_argument("--table-offset", nargs=3, type=float, default=[0.0, 0.0, 0.0], metavar=("OX", "OY", "OZ"),
                        help="Fine-tune offset in Godot meters [X, Y, Z] (default: 0 0 0)")
    parser.add_argument("--materials-dir", "-m", help="Path to custom materials/ folder containing .vmt and .vtf files")
    parser.add_argument("--spawn-idx", type=int, default=0, help="Index of player spawn point to align to (default: 0, ignored if --table-pos or --center is used)")
    parser.add_argument("--no-install", action="store_true", help="Do not install to ~/.unciv-vr/Backgrounds/")

    args = parser.parse_args()
    convert_gmod_map(
        input_path=args.input_path,
        out_dir=args.out,
        bg_name=args.name,
        scale=args.scale,
        spawn_idx=args.spawn_idx,
        table_pos=args.table_pos,
        center_floor=args.center_floor,
        table_yaw=args.table_yaw,
        table_offset=tuple(args.table_offset),
        materials_dir=args.materials_dir,
        map_name=args.map,
        install_user=not args.no_install,
    )


if __name__ == "__main__":
    main()
