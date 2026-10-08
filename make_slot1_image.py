#!/usr/bin/env python3
"""Собирает образ OpenWrt для ВТОРОГО слота (Kernel 2, mtd5).

Берёт ядро OpenWrt из дампа mtd4 (слот 0) и пересобирает заголовок Sercomm
под адрес второго слота 0xa00100. Формат заголовка — из официального
scripts/sercomm-kernel-header.py OpenWrt.
"""
import binascii, struct, sys

KERNEL_HEADER_SIZE = 0x100
SLOT1_KERNEL_OFFSET = 0x00a00100   # 0xa00000 + 0x100
SLOT1_ROOTFS_OFFSET = 0x03000000   # File System 2

def gen_header(kernel, koff, rofs):
    h = bytearray([0xff] * KERNEL_HEADER_SIZE)
    struct.pack_into('<L', h, 0xc,  0xffffff02)
    struct.pack_into('<L', h, 0x1c, 0x0)
    struct.pack_into('<L', h, 0x34, 0x0)
    struct.pack_into('<L', h, 0x10, koff)
    struct.pack_into('<L', h, 0x28, rofs)
    fake = b"UBI#"
    struct.pack_into('<L', h, 0x2c, len(fake))
    struct.pack_into('<L', h, 0x30, binascii.crc32(fake) & 0xffffffff)
    struct.pack_into('<L', h, 0x14, len(kernel))
    struct.pack_into('<L', h, 0x4,  koff + len(kernel))
    struct.pack_into('<L', h, 0x18, binascii.crc32(kernel) & 0xffffffff)
    struct.pack_into('<L', h, 0x8,  binascii.crc32(bytes(h)) & 0xffffffff)
    struct.pack_into('<L', h, 0x0,  0x726553)
    return bytes(h)

src = sys.argv[1] if len(sys.argv) > 1 else 'backup/mtd4.bin'
d = open(src, 'rb').read()
print(f"источник: {src}")
koff0  = int.from_bytes(d[0x10:0x14], 'little')
ksize  = int.from_bytes(d[0x14:0x18], 'little')
kernel = d[0x100:0x100 + ksize]

if kernel[:4] != b'\x27\x05\x19\x56':
    sys.exit("ОШИБКА: в mtd4 нет uImage по ожидаемому смещению")

hdr = gen_header(kernel, SLOT1_KERNEL_OFFSET, SLOT1_ROOTFS_OFFSET)
img = hdr + kernel
open('slot1_openwrt_kernel.bin', 'wb').write(img)

print("Слот 0 (из дампа mtd4):")
print(f"  kernel_offset = 0x{koff0:08x}   kernel_size = 0x{ksize:x}")
print()
print("Собранный образ для слота 1:")
print(f"  kernel_offset = 0x{SLOT1_KERNEL_OFFSET:08x}")
print(f"  rootfs_offset = 0x{SLOT1_ROOTFS_OFFSET:08x}")
print(f"  размер образа = {len(img)} байт (0x{len(img):x})")
print(f"  файл          = slot1_openwrt_kernel.bin")
print()
print("  заголовок: " + hdr[:0x38].hex(' '))
print()
print("Самопроверка:")
print(f"  uImage magic в образе по 0x100: {img[0x100:0x104].hex(' ')} (ожидается 27 05 19 56)")
print(f"  имя uImage: {img[0x100+32:0x100+60].split(bytes([0]))[0].decode(errors='replace')}")
print(f"  crc32 ядра совпадает: {binascii.crc32(kernel)&0xffffffff == int.from_bytes(hdr[0x18:0x1c],'little')}")
