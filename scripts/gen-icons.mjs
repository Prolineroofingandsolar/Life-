// Generates the PWA icons (no external deps) — a white "L" on the brand colour.
import { writeFileSync } from 'node:fs'
import { deflateSync } from 'node:zlib'

function png(size, draw) {
  const ch = 4
  const raw = Buffer.alloc(size * (size * ch + 1))
  for (let y = 0; y < size; y++) {
    raw[y * (size * ch + 1)] = 0 // filter byte: none
    for (let x = 0; x < size; x++) {
      const [r, g, b, a] = draw(x, y)
      const o = y * (size * ch + 1) + 1 + x * ch
      raw[o] = r
      raw[o + 1] = g
      raw[o + 2] = b
      raw[o + 3] = a
    }
  }
  const crc = (buf) => {
    let c = ~0
    for (let i = 0; i < buf.length; i++) {
      c ^= buf[i]
      for (let k = 0; k < 8; k++) c = c & 1 ? (c >>> 1) ^ 0xedb88320 : c >>> 1
    }
    return ~c >>> 0
  }
  const chunk = (type, data) => {
    const t = Buffer.from(type, 'ascii')
    const len = Buffer.alloc(4)
    len.writeUInt32BE(data.length)
    const body = Buffer.concat([t, data])
    const c = Buffer.alloc(4)
    c.writeUInt32BE(crc(body))
    return Buffer.concat([len, body, c])
  }
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])
  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(size, 0)
  ihdr.writeUInt32BE(size, 4)
  ihdr[8] = 8 // bit depth
  ihdr[9] = 6 // RGBA
  return Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', deflateSync(raw)), chunk('IEND', Buffer.alloc(0))])
}

function draw(size) {
  return (x, y) => {
    // Brand gradient (indigo -> violet) on the diagonal.
    const t = (x + y) / (2 * size)
    const r = Math.round(124 + t * (157 - 124))
    const g = Math.round(131 + t * (124 - 131))
    const b = Math.round(255)
    // White "L" glyph.
    const u = x / size
    const v = y / size
    const stem = u > 0.34 && u < 0.46 && v > 0.26 && v < 0.74
    const foot = v > 0.62 && v < 0.74 && u > 0.34 && u < 0.68
    if (stem || foot) return [255, 255, 255, 255]
    return [r, g, b, 255]
  }
}

for (const size of [192, 512]) {
  writeFileSync(new URL(`../public/icon-${size}.png`, import.meta.url), png(size, draw(size)))
  console.log(`wrote public/icon-${size}.png`)
}
