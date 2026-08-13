"use strict";

let cancelled = false;

self.onmessage = event => {
  const { type, payload } = event.data;
  if (type === "cancel") {
    cancelled = true;
    return;
  }
  cancelled = false;
  try {
    if (type === "pack") {
      const page = packMonochrome(payload);
      self.postMessage({ type: "packed", page }, [page.data.buffer]);
      return;
    }
    if (type !== "encode") return;
    const bytes = encodeJob(payload);
    self.postMessage({ type: "complete", bytes }, [bytes.buffer]);
  } catch (error) {
    self.postMessage({ type: cancelled ? "cancelled" : "error", message: error.message || String(error) });
  }
};

function packMonochrome(payload) {
  const { data, width, height, mode, lightness } = payload;
  const bytesPerRow = Math.ceil(width / 8);
  const bitmap = new Uint8Array(bytesPerRow * height);
  const bayer8 = [0,48,12,60,3,51,15,63,32,16,44,28,35,19,47,31,8,56,4,52,11,59,7,55,40,24,36,20,43,27,39,23,2,50,14,62,1,49,13,61,34,18,46,30,33,17,45,29,10,58,6,54,9,57,5,53,42,26,38,22,41,25,37,21];
  const threshold = Math.max(96, Math.min(208, 160 - lightness * 20));
  let currentError = new Int32Array(width + 2);
  let nextError = new Int32Array(width + 2);

  for (let y = 0; y < height; y += 1) {
    if ((y & 127) === 0) checkCancelled();
    for (let x = 0; x < width; x += 1) {
      const offset = (y * width + x) * 4;
      const gray = .2126 * data[offset] + .7152 * data[offset + 1] + .0722 * data[offset + 2];
      let black = false;
      if (mode === "text") {
        black = gray < threshold;
      } else if (mode === "graphics") {
        const tone = toneValue(gray, .8, inkScale(lightness));
        black = tone < bayer8[(y & 7) * 8 + (x & 7)] * 4 + 2;
      } else {
        const tone = toneValue(gray, .55, inkScale(lightness));
        const adjusted = Math.max(0, Math.min(255, tone + currentError[x + 1] / 16));
        const output = adjusted < 128 ? 0 : 255;
        black = output === 0;
        const error = adjusted - output;
        currentError[x + 2] += error * 7;
        nextError[x] += error * 3;
        nextError[x + 1] += error * 5;
        nextError[x + 2] += error;
      }
      if (black) {
        bitmap[y * bytesPerRow + Math.floor(x / 8)] |= 0x80 >> (x & 7);
      }
    }
    if (mode === "photo") {
      const swap = currentError; currentError = nextError; nextError = swap; nextError.fill(0);
    }
  }
  return { width, height, bytesPerRow, data: bitmap };
}

function toneValue(gray, gamma, scale) {
  if (gray <= 8) return 0;
  if (gray >= 248) return 255;
  const curved = Math.pow(gray / 255, gamma) * 255;
  return Math.max(0, Math.min(255, Math.round(255 - (255 - curved) * scale)));
}

function inkScale(lightness) {
  return ({ "-2": 1.2, "-1": 1.05, "0": .9, "1": .72, "2": .55 })[String(lightness)] || .9;
}

function encodeJob(payload) {
  const { pages, jobName, copies, duplex, resolution } = payload;
  if (!pages || !pages.length) throw new Error("没有可打印页面");
  const writer = new ByteWriter();
  writer.ascii("\x1b%-12345X@PJL \n");
  writer.ascii(`@PJL JOB NAME="${safeName(jobName)}"\n`);
  writer.ascii("@PJL SET ECONOMODE=OFF\n");
  writer.ascii("@PJL SET MEDIATYPE=REGULAR\n");
  writer.ascii(`@PJL SET RESOLUTION=${resolution}\n`);
  writer.ascii("@PJL ENTER LANGUAGE=PCL\n");

  pages.forEach((page, index) => {
    checkCancelled();
    encodePage(writer, page, index === 0, copies, duplex, resolution);
    self.postMessage({ type: "progress", completed: index + 1, total: pages.length });
  });

  writer.ascii(`\x1b%-12345X@PJL EOJ NAME="${safeName(jobName)}"\n`);
  writer.ascii("\x1b%-12345X\n");
  return writer.finish();
}

function encodePage(writer, page, isFirst, copies, duplex, resolution) {
  const copyCount = Math.max(1, Math.min(Number(copies) || 1, 20));
  if (isFirst) {
    writer.ascii(`\x1b&u${resolution}D\x1b*t${resolution}R\x1b&n8WdRegular\x1b&l7H`);
    writer.ascii(duplex ? "\x1b&l1S" : "\x1b&l0S");
    writer.ascii(`\x1b&l${copyCount}X`);
  }
  writer.ascii("\x1b&l0O");
  writer.ascii("\x1b&l4096a26a6d1E\x1b&l0U\x1b&l0Z");
  writer.ascii("\x1b*p0X\x1b*p0Y\x1b*b1030m");

  let block = new ByteWriter();
  let lineCount = { value: 0 };
  let reference = new Uint8Array(page.bytesPerRow);
  for (let lineIndex = 0; lineIndex < page.height; lineIndex += 1) {
    if ((lineIndex & 127) === 0) checkCancelled();
    const start = lineIndex * page.bytesPerRow;
    const line = page.data.subarray(start, start + page.bytesPerRow);
    let encoded;

    if (lineIndex % 128 === 0) {
      appendBlock(writer, block, lineCount.value);
      block = new ByteWriter();
      lineCount.value = 0;
      encoded = encodeLine(line, null);
    } else {
      encoded = encodeLine(line, reference);
      if (block.length + encoded.length >= 16350) {
        appendBlock(writer, block, lineCount.value);
        block = new ByteWriter();
        lineCount.value = 0;
        encoded = encodeLine(line, null);
      }
    }

    block.bytes(encoded);
    lineCount.value += 1;
    reference.set(line);
  }
  appendBlock(writer, block, lineCount.value);
  writer.ascii("1030M");
  writer.byte(0x0c);
}

function encodeLine(line, reference) {
  let hasInk = false;
  for (let i = 0; i < line.length; i += 1) {
    if (line[i] !== 0) { hasInk = true; break; }
  }
  if (!hasInk) return Uint8Array.of(0xff);

  const output = [];
  if (!reference) {
    output.push(1);
    writeSubstitute(0, line, 0, line.length, output);
    return Uint8Array.from(output);
  }

  let end = line.length;
  while (end > 0 && line[end - 1] === reference[end - 1]) end -= 1;
  output.push(0);
  let edits = 0;
  let position = 0;
  while (position < end) {
    let mismatch = position;
    while (mismatch < end && line[mismatch] === reference[mismatch]) mismatch += 1;
    const offset = mismatch - position;
    position = mismatch;
    if (position === end) break;

    edits += 1;
    if (edits === 254) {
      writeSubstitute(offset, line, position, end, output);
      position = end;
      break;
    }

    const count = substituteLength(line, reference, position, end);
    if (count > 0) {
      writeSubstitute(offset, line, position, position + count, output);
      position += count;
    } else {
      const repeat = repeatLength(line, position, end);
      writeRepeat(offset, repeat, line[position], output);
      position += repeat;
    }
  }
  output[0] = edits;
  return Uint8Array.from(output);
}

function appendBlock(output, block, lineCount) {
  if (!block.length) return;
  const bytes = block.finish();
  output.ascii(`${bytes.length + 2}w`);
  output.byte(0);
  output.byte(Math.max(0, Math.min(lineCount, 255)));
  output.bytes(bytes);
}

function writeSubstitute(offset, line, start, end, output) {
  const count = end - start - 1;
  output.push((Math.min(offset, 15) << 3) | Math.min(count, 7));
  writeOverflow(offset - 15, output);
  writeOverflow(count - 7, output);
  for (let i = start; i < end; i += 1) output.push(line[i]);
}

function writeRepeat(offset, count, value, output) {
  const encodedCount = count - 2;
  output.push(0x80 | (Math.min(offset, 3) << 5) | Math.min(encodedCount, 31));
  writeOverflow(offset - 3, output);
  writeOverflow(encodedCount - 31, output);
  output.push(value);
}

function writeOverflow(value, output) {
  if (value < 0) return;
  while (value >= 255) {
    output.push(255);
    value -= 255;
  }
  output.push(value);
}

function repeatLength(line, start, end) {
  let next = start + 1;
  while (next < end && line[next] === line[start]) next += 1;
  return next - start;
}

function substituteLength(line, reference, start, end) {
  if (start >= end) return 0;
  let current = start;
  let next = start + 1;
  let previous = start;
  while (next < end) {
    if (line[current] === reference[current] && line[next] === reference[next]) return current - start;
    if (line[current] === line[next] && line[current] === line[previous]) return previous - start;
    previous = current;
    current = next;
    next += 1;
  }
  return end - start;
}

function safeName(value) {
  return String(value || "Web Print")
    .replace(/[^\x20-\x7e]|["\\]/g, " ")
    .slice(0, 79);
}

function checkCancelled() {
  if (cancelled) throw new Error("已取消");
}

class ByteWriter {
  constructor() {
    this.chunks = [];
    this.length = 0;
  }

  byte(value) {
    this.bytes(Uint8Array.of(value));
  }

  ascii(value) {
    const bytes = new Uint8Array(value.length);
    for (let i = 0; i < value.length; i += 1) bytes[i] = value.charCodeAt(i) & 0xff;
    this.bytes(bytes);
  }

  bytes(value) {
    if (!value.length) return;
    this.chunks.push(value);
    this.length += value.length;
  }

  finish() {
    const output = new Uint8Array(this.length);
    let offset = 0;
    this.chunks.forEach(chunk => {
      output.set(chunk, offset);
      offset += chunk.length;
    });
    return output;
  }
}
