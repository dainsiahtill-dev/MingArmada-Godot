import { inflateSync } from 'node:zlib';

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

// Inspect actual binary structures. PNG chunks, checksums, compressed raster and
// scanline lengths are checked; JPEG SOF and complete scan/end markers are read.
// Visual content, historical dress and full browser decoding need browser QA.
export function inspectImage(bytes) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (bytes.subarray(0, 8).equals(signature)) {
    let cursor = 8;
    let header;
    let complete = false;
    const idat = [];
    while (cursor < bytes.length) {
      if (cursor + 12 > bytes.length) throw new Error('Truncated PNG chunk.');
      const length = bytes.readUInt32BE(cursor);
      if (cursor + length + 12 > bytes.length) throw new Error('PNG chunk extends beyond file.');
      const kind = bytes.toString('ascii', cursor + 4, cursor + 8);
      const data = bytes.subarray(cursor + 8, cursor + 8 + length);
      const checksum = bytes.readUInt32BE(cursor + 8 + length);
      if (crc32(bytes.subarray(cursor + 4, cursor + 8 + length)) !== checksum) {
        throw new Error(`Invalid PNG ${kind} checksum.`);
      }
      if (!header && kind !== 'IHDR') throw new Error('PNG must start with IHDR.');
      if (kind === 'IHDR') {
        if (header || length !== 13) throw new Error('Invalid PNG IHDR.');
        header = { format: 'PNG', width: data.readUInt32BE(0), height: data.readUInt32BE(4),
          depth: data[8], color: data[9], compression: data[10], filter: data[11], interlace: data[12] };
      } else if (kind === 'IDAT') idat.push(data);
      else if (kind === 'IEND') {
        if (length !== 0 || cursor + 12 !== bytes.length) throw new Error('Invalid PNG end chunk.');
        complete = true;
        break;
      }
      cursor += length + 12;
    }
    if (!complete || !idat.length) throw new Error('PNG lacks raster data or end chunk.');
    if (header.compression !== 0 || header.filter !== 0 || ![0, 1].includes(header.interlace)) {
      throw new Error('Invalid PNG compression/filter/interlace.');
    }
    const channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[header.color];
    const depths = { 0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16] }[header.color];
    if (!channels || !depths.includes(header.depth) || header.width < 1 || header.height < 1) {
      throw new Error('Invalid PNG color model, depth or dimensions.');
    }
    const passes = header.interlace ? [[0, 0, 8, 8], [4, 0, 8, 8], [0, 4, 4, 8],
      [2, 0, 4, 4], [0, 2, 2, 4], [1, 0, 2, 2], [0, 1, 1, 2]] : [[0, 0, 1, 1]];
    const rows = [];
    let expectedLength = 0;
    for (const [x, y, dx, dy] of passes) {
      const columns = Math.max(0, Math.ceil((header.width - x) / dx));
      const count = Math.max(0, Math.ceil((header.height - y) / dy));
      if (!columns || !count) continue;
      const rowLength = Math.ceil(columns * channels * header.depth / 8) + 1;
      expectedLength += rowLength * count;
      rows.push({ count, rowLength });
    }
    if (expectedLength > 512 * 1024 * 1024) throw new Error('PNG raster exceeds 512 MiB limit.');
    const raster = inflateSync(Buffer.concat(idat), { maxOutputLength: expectedLength });
    if (raster.length !== expectedLength) throw new Error('PNG raster length does not match dimensions.');
    let offset = 0;
    for (const { count, rowLength } of rows) {
      for (let row = 0; row < count; row++) {
        if (raster[offset] > 4) throw new Error('Invalid PNG scanline filter.');
        offset += rowLength;
      }
    }
    return { format: header.format, width: header.width, height: header.height, rasterValidated: true };
  }
  if (bytes[0] === 0xff && bytes[1] === 0xd8) {
    let cursor = 2;
    let dimensions;
    let sawScan = false;
    let complete = false;
    const frameMarkers = new Set([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]);
    while (cursor < bytes.length) {
      if (bytes[cursor] !== 0xff) {
        if (!sawScan) throw new Error('Invalid JPEG marker.');
        cursor++;
        continue;
      }
      while (bytes[cursor] === 0xff) cursor++;
      const marker = bytes[cursor++];
      if (marker === 0x00 && sawScan) continue;
      if (marker === 0xd9) { complete = cursor === bytes.length; break; }
      if (marker >= 0xd0 && marker <= 0xd7) continue;
      if (cursor + 2 > bytes.length) throw new Error('Truncated JPEG segment.');
      const length = bytes.readUInt16BE(cursor);
      if (length < 2 || cursor + length > bytes.length) throw new Error('Invalid JPEG segment length.');
      if (frameMarkers.has(marker)) {
        if (length < 8) throw new Error('Invalid JPEG frame.');
        dimensions = { format: 'JPEG', height: bytes.readUInt16BE(cursor + 3), width: bytes.readUInt16BE(cursor + 5) };
      }
      if (marker === 0xda) sawScan = true;
      cursor += length;
    }
    if (!dimensions || !sawScan || !complete || dimensions.width < 1 || dimensions.height < 1) {
      throw new Error('JPEG lacks a complete frame, scan or end marker.');
    }
    return { ...dimensions, rasterValidated: false };
  }
  throw new Error('Image is neither PNG nor JPEG.');
}

