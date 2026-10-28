"""Reject damaged or accidentally replaced app icons before Xcode compiles them."""
import hashlib
import struct
import zlib
from pathlib import Path

path = Path(__file__).resolve().parents[1] / 'Due/Assets.xcassets/AppIcon.appiconset/AppIcon.png'
data = path.read_bytes()
assert hashlib.sha256(data).hexdigest() == 'c999364908842b167b17566ac8349977f122e10dafad4372bbc2e7c116092983', 'Icon does not match the verified original'
assert data[:8] == b'\x89PNG\r\n\x1a\n', 'Invalid PNG signature'
offset = 8
compressed = bytearray()
finished = False
while offset < len(data):
    length = struct.unpack('>I', data[offset:offset + 4])[0]
    kind = data[offset + 4:offset + 8]
    payload = data[offset + 8:offset + 8 + length]
    crc = struct.unpack('>I', data[offset + 8 + length:offset + 12 + length])[0]
    assert zlib.crc32(kind + payload) & 0xffffffff == crc, f'Damaged {kind!r} chunk'
    if kind == b'IHDR':
        assert struct.unpack('>IIBBBBB', payload) == (1024, 1024, 8, 2, 0, 0, 0), 'Expected opaque 1024px RGB icon'
    if kind == b'IDAT':
        compressed.extend(payload)
    offset += length + 12
    if kind == b'IEND':
        finished = True
        break
assert finished and offset == len(data), 'Incomplete PNG'
pixels = zlib.decompress(compressed)
assert len(pixels) == 1024 * (1 + 1024 * 3), 'Incomplete pixel data'
assert all(pixels[row * 3073] in range(5) for row in range(1024)), 'Invalid PNG filter'
print('Icon verified: SHA-256, PNG chunk checksums, and all 1024 pixel rows passed.')
