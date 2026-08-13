import { createServer } from "node:http";
import { createReadStream, existsSync } from "node:fs";
import { stat } from "node:fs/promises";
import { extname, join, normalize } from "node:path";

const root = normalize(join(import.meta.dirname, "..", "www"));
const port = Number(process.env.PORT || 4173);
const expectedPin = process.env.PRINT_PIN || "246810";
const mime = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".webmanifest": "application/manifest+json",
  ".png": "image/png"
};

createServer(async (request, response) => {
  const url = new URL(request.url, `http://${request.headers.host}`);
  if (url.pathname === "/cgi-bin/status.cgi") {
    return json(response, 200, { ok: true, printer: true, ready: true, version: "mock" });
  }
  if (url.pathname === "/cgi-bin/print.cgi") {
    if (request.method !== "POST") return json(response, 405, { ok: false, message: "只允许 POST 请求" });
    let length = 0;
    let bodyStart = Buffer.alloc(0);
    for await (const chunk of request) {
      length += chunk.length;
      if (bodyStart.length < 40) bodyStart = Buffer.concat([bodyStart, chunk]).subarray(0, 40);
    }
    const newline = bodyStart.indexOf(0x0a);
    const pin = newline > 0 ? bodyStart.subarray(0, newline).toString("ascii").match(/^PIN (\d{4,12})$/)?.[1] : null;
    if (pin !== expectedPin) return json(response, 401, { ok: false, message: "打印 PIN 不正确" });
    const header = bodyStart.subarray(newline + 1);
    if (!header.toString("latin1").startsWith("\x1b%-12345X@PJL ")) return json(response, 400, { ok: false, message: "无法识别打印数据" });
    return json(response, 200, { ok: true, bytes: length });
  }

  let pathname = decodeURIComponent(url.pathname);
  if (pathname === "/") pathname = "/index.html";
  const file = normalize(join(root, pathname));
  if (!file.startsWith(root) || !existsSync(file) || !(await stat(file)).isFile()) {
    response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    return response.end("Not found");
  }
  response.writeHead(200, { "Content-Type": mime[extname(file)] || "application/octet-stream", "Cache-Control": "no-store" });
  createReadStream(file).pipe(response);
}).listen(port, "127.0.0.1", () => {
  process.stdout.write(`Mock Web Print listening on http://127.0.0.1:${port}\n`);
});

function json(response, status, body) {
  response.writeHead(status, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
  response.end(JSON.stringify(body));
}
