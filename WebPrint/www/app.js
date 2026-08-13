"use strict";

const state = {
  file: null,
  type: null,
  pdf: null,
  image: null,
  pageCount: 0,
  currentPage: 1,
  copies: 1,
  online: false,
  busy: false,
  cancelled: false,
  worker: null,
  workerReject: null,
  uploadController: null,
  previewToken: 0
};

const $ = selector => document.querySelector(selector);
const elements = {};

document.addEventListener("DOMContentLoaded", async () => {
  Object.assign(elements, {
    fileInput: $("#fileInput"), chooseButton: $("#chooseButton"), replaceButton: $("#replaceButton"),
    emptyState: $("#emptyState"), documentState: $("#documentState"), documentName: $("#documentName"),
    documentMeta: $("#documentMeta"), previewCanvas: $("#previewCanvas"), previewLoading: $("#previewLoading"),
    paperPreview: $("#paperPreview"), previousPage: $("#previousPage"), nextPage: $("#nextPage"),
    currentPage: $("#currentPage"), totalPages: $("#totalPages"), pageRange: $("#pageRange"),
    rangeHelp: $("#rangeHelp"), scaling: $("#scaling"), contentMode: $("#contentMode"),
    lightness: $("#lightness"), resolution: $("#resolution"), duplex: $("#duplex"),
    decreaseCopies: $("#decreaseCopies"), increaseCopies: $("#increaseCopies"), copiesOutput: $("#copiesOutput"),
    accessPin: $("#accessPin"), rememberPin: $("#rememberPin"), connectionLabel: $("#connectionLabel"),
    refreshButton: $("#refreshButton"), settingsButton: $("#settingsButton"), closeSettingsButton: $("#closeSettingsButton"),
    settingsPanel: $("#settingsPanel"), settingsBackdrop: $("#settingsBackdrop"), printButton: $("#printButton"),
    jobSummary: $("#jobSummary"), jobStatus: $("#jobStatus"), progressDialog: $("#progressDialog"),
    progressTitle: $("#progressTitle"), progressDetail: $("#progressDetail"), progressBar: $("#progressBar"),
    cancelButton: $("#cancelButton"), toast: $("#toast")
  });

  if (window.pdfjsLib) {
    pdfjsLib.GlobalWorkerOptions.workerSrc = "vendor/pdf.worker.min.js";
  }
  if (window.lucide) lucide.createIcons();
  elements.accessPin.value = localStorage.getItem("lj2600d-web-pin") || "";
  bindEvents();
  updateSummary();
  await checkService();
  if (window.isSecureContext && "serviceWorker" in navigator) {
    navigator.serviceWorker.register("service-worker.js").catch(() => {});
  }
});

function bindEvents() {
  elements.chooseButton.addEventListener("click", () => elements.fileInput.click());
  elements.replaceButton.addEventListener("click", () => elements.fileInput.click());
  elements.fileInput.addEventListener("change", event => loadFile(event.target.files[0]));
  elements.previousPage.addEventListener("click", () => changePage(-1));
  elements.nextPage.addEventListener("click", () => changePage(1));
  elements.decreaseCopies.addEventListener("click", () => setCopies(state.copies - 1));
  elements.increaseCopies.addEventListener("click", () => setCopies(state.copies + 1));
  elements.refreshButton.addEventListener("click", checkService);
  elements.printButton.addEventListener("click", printDocument);
  elements.cancelButton.addEventListener("click", cancelPrint);
  elements.settingsButton.addEventListener("click", openSettings);
  elements.closeSettingsButton.addEventListener("click", closeSettings);
  elements.settingsBackdrop.addEventListener("click", closeSettings);
  elements.settingsBackdrop.addEventListener("touchmove", event => event.preventDefault(), { passive: false });
  containSettingsScroll();
  elements.pageRange.addEventListener("input", updateSummary);
  [elements.scaling, elements.contentMode, elements.lightness, elements.resolution, elements.duplex]
    .forEach(element => element.addEventListener("change", () => {
      updateSummary();
      if (state.file) renderPreview();
    }));
  document.querySelectorAll('input[name="orientation"]').forEach(input => input.addEventListener("change", () => {
    updateSummary();
    if (state.file) renderPreview();
  }));
}

async function loadFile(file) {
  if (!file) return;
  if (file.size > 80 * 1024 * 1024) return showToast("文件超过 80 MB，网页版本暂不支持");
  const isPDF = file.type === "application/pdf" || file.name.toLowerCase().endsWith(".pdf");
  const isImage = file.type.startsWith("image/");
  if (!isPDF && !isImage) return showToast("请选择 PDF、JPEG、PNG 或 WebP 文件");

  setPreviewLoading(true);
  try {
    cleanupDocument();
    state.file = file;
    state.type = isPDF ? "pdf" : "image";
    if (isPDF) {
      if (!window.pdfjsLib) throw new Error("PDF 组件未加载");
      const data = await file.arrayBuffer();
      state.pdf = await pdfjsLib.getDocument({ data }).promise;
      state.pageCount = state.pdf.numPages;
      elements.contentMode.value = "text";
      elements.lightness.value = "0";
    } else {
      state.image = await decodeImage(file);
      state.pageCount = 1;
      elements.contentMode.value = "photo";
      elements.lightness.value = "1";
    }
    state.currentPage = 1;
    elements.emptyState.hidden = true;
    elements.documentState.hidden = false;
    elements.documentName.textContent = file.name;
    elements.documentMeta.textContent = `${state.pageCount} 页 · ${formatBytes(file.size)}`;
    elements.totalPages.textContent = String(state.pageCount);
    elements.rangeHelp.textContent = `留空打印全部 ${state.pageCount} 页`;
    await renderPreview();
    updateSummary();
  } catch (error) {
    cleanupDocument();
    elements.emptyState.hidden = false;
    elements.documentState.hidden = true;
    showToast(error.message || "无法读取文档");
  } finally {
    elements.fileInput.value = "";
    setPreviewLoading(false);
  }
}

function cleanupDocument() {
  if (state.image && state.image.close) state.image.close();
  if (state.pdf) state.pdf.destroy().catch(() => {});
  state.pdf = null;
  state.image = null;
  state.file = null;
  state.pageCount = 0;
}

async function decodeImage(file) {
  const url = URL.createObjectURL(file);
  try {
    const image = new Image();
    image.src = url;
    await image.decode();
    return image;
  } finally {
    URL.revokeObjectURL(url);
  }
}

async function renderPreview() {
  if (!state.file) return;
  const token = ++state.previewToken;
  setPreviewLoading(true);
  try {
    const orientation = selectedOrientation();
    const sourceSize = await sourceDimensions(state.currentPage);
    const landscape = orientation === "landscape" || (orientation === "auto" && sourceSize.width > sourceSize.height);
    elements.paperPreview.classList.toggle("landscape", landscape);
    const maxWidth = landscape ? 760 : 540;
    const maxHeight = landscape ? 540 : 760;
    const scale = Math.min(maxWidth / sourceSize.width, maxHeight / sourceSize.height, 1.6);
    const width = Math.max(1, Math.round(sourceSize.width * scale));
    const height = Math.max(1, Math.round(sourceSize.height * scale));
    const canvas = elements.previewCanvas;
    canvas.width = landscape ? height : width;
    canvas.height = landscape ? width : height;
    const context = canvas.getContext("2d", { alpha: false, willReadFrequently: true });
    context.fillStyle = "white";
    context.fillRect(0, 0, canvas.width, canvas.height);
    if (landscape) {
      context.translate(0, canvas.height);
      context.rotate(-Math.PI / 2);
    }
    await drawSource(context, state.currentPage, width, height);
    if (token !== state.previewToken) return;
    applyPreviewTone(context, landscape ? height : width, landscape ? width : height);
    elements.currentPage.textContent = String(state.currentPage);
    elements.previousPage.disabled = state.currentPage <= 1;
    elements.nextPage.disabled = state.currentPage >= state.pageCount;
  } catch (error) {
    showToast(error.message || "无法生成预览");
  } finally {
    if (token === state.previewToken) setPreviewLoading(false);
  }
}

async function sourceDimensions(pageNumber) {
  if (state.type === "pdf") {
    const page = await state.pdf.getPage(pageNumber);
    const viewport = page.getViewport({ scale: 1 });
    return { width: viewport.width, height: viewport.height };
  }
  return { width: state.image.width, height: state.image.height };
}

async function drawSource(context, pageNumber, width, height) {
  if (state.type === "pdf") {
    const page = await state.pdf.getPage(pageNumber);
    const base = page.getViewport({ scale: 1 });
    const viewport = page.getViewport({ scale: width / base.width });
    await page.render({ canvasContext: context, viewport }).promise;
  } else {
    context.drawImage(state.image, 0, 0, width, height);
  }
}

function applyPreviewTone(context, width, height) {
  const image = context.getImageData(0, 0, width, height);
  const mode = elements.contentMode.value;
  const lightness = Number(elements.lightness.value);
  const contrast = mode === "text" ? 1.45 : mode === "graphics" ? 1.08 : .88;
  const brightness = lightness * 8 + (mode === "photo" ? 15 : mode === "graphics" ? 7 : 0);
  for (let i = 0; i < image.data.length; i += 4) {
    const gray = .2126 * image.data[i] + .7152 * image.data[i + 1] + .0722 * image.data[i + 2];
    const value = Math.max(0, Math.min(255, (gray - 128) * contrast + 128 + brightness));
    image.data[i] = image.data[i + 1] = image.data[i + 2] = value;
  }
  context.putImageData(image, 0, 0);
}

function changePage(delta) {
  const next = Math.max(1, Math.min(state.pageCount, state.currentPage + delta));
  if (next === state.currentPage) return;
  state.currentPage = next;
  renderPreview();
}

async function checkService() {
  elements.connectionLabel.className = "";
  elements.connectionLabel.textContent = "正在检查打印服务";
  elements.jobStatus.textContent = "打印服务状态检查中";
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 3500);
  try {
    const response = await fetch("cgi-bin/status.cgi", { cache: "no-store", signal: controller.signal });
    const data = await response.json();
    if (!response.ok || !data.ok) throw new Error(data.message || "服务不可用");
    state.online = Boolean(data.printer && data.ready);
    elements.connectionLabel.textContent = state.online ? "打印服务在线" : "打印机未就绪";
    elements.connectionLabel.className = state.online ? "online" : "offline";
    elements.jobStatus.textContent = state.online ? "网页打印桥已就绪" : "请检查打印机连接";
  } catch (_) {
    state.online = false;
    elements.connectionLabel.textContent = "网页打印桥未连接";
    elements.connectionLabel.className = "offline";
    elements.jobStatus.textContent = "请确认光猫上的网页服务已启动";
  } finally {
    clearTimeout(timeout);
  }
  updateSummary();
}

async function printDocument() {
  if (!state.file || state.busy) return;
  const pin = elements.accessPin.value.trim();
  if (!/^\d{4,12}$/.test(pin)) {
    openSettings();
    elements.accessPin.focus();
    return showToast("请输入 4 至 12 位打印 PIN");
  }
  let pages;
  try {
    pages = parsePageRange(elements.pageRange.value, state.pageCount);
  } catch (error) {
    openSettings();
    elements.pageRange.focus();
    return showToast(error.message);
  }
  if (pages.length > 24) {
    openSettings();
    elements.pageRange.focus();
    return showToast("单次最多打印 24 页，请用页码范围分批打印");
  }
  state.busy = true;
  state.cancelled = false;
  closeSettings();
  showProgress("正在生成打印数据", `准备第 1/${pages.length} 页`, 0);
  try {
    const rasterPages = [];
    for (let index = 0; index < pages.length; index += 1) {
      if (state.cancelled) throw new DOMException("已取消", "AbortError");
      updateProgress("正在生成打印数据", `渲染第 ${index + 1}/${pages.length} 页`, index / (pages.length + 1));
      rasterPages.push(await renderPrintPage(pages[index]));
      await nextFrame();
    }

    const hbp = await encodePages(rasterPages, pages.length);
    if (state.cancelled) throw new DOMException("已取消", "AbortError");
    updateProgress("正在发送到打印机", `${formatBytes(hbp.byteLength)} · 请保持页面打开`, .9);
    state.uploadController = new AbortController();
    const requestBody = new Blob([`PIN ${pin}\n`, hbp], { type: "application/octet-stream" });
    const response = await fetch("cgi-bin/print.cgi", {
      method: "POST",
      headers: { "Content-Type": "application/octet-stream" },
      body: requestBody,
      signal: state.uploadController.signal
    });
    const result = await response.json().catch(() => ({}));
    if (!response.ok || !result.ok) {
      const error = new Error(result.message || `打印服务返回 ${response.status}`);
      error.status = response.status;
      throw error;
    }
    if (elements.rememberPin.checked) localStorage.setItem("lj2600d-web-pin", pin);
    else localStorage.removeItem("lj2600d-web-pin");
    updateProgress("任务已发送", `${pages.length} 页已交给打印机`, 1);
    await delay(700);
    hideProgress();
    showToast("打印任务已发送");
  } catch (error) {
    hideProgress();
    if (error.status === 401) {
      localStorage.removeItem("lj2600d-web-pin");
      openSettings();
      requestAnimationFrame(() => { elements.accessPin.focus(); elements.accessPin.select(); });
      showToast("打印 PIN 不正确，请重新输入");
    } else {
      showToast(error.name === "AbortError" ? "打印已取消" : (error.message || "打印失败"));
    }
  } finally {
    state.busy = false;
    if (state.worker) { state.worker.terminate(); state.worker = null; }
    state.workerReject = null;
    state.uploadController = null;
  }
}

async function renderPrintPage(pageNumber) {
  const resolution = Number(elements.resolution.value);
  const target = { width: 4800 * resolution / 600, height: 6814 * resolution / 600 };
  const sourceSize = await sourceDimensions(pageNumber);
  const orientation = selectedOrientation();
  const rotate = orientation === "landscape" || (orientation === "auto" && sourceSize.width > sourceSize.height);
  const logical = rotate ? { width: target.height, height: target.width } : target;
  const scale = elements.scaling.value === "fill"
    ? Math.max(logical.width / sourceSize.width, logical.height / sourceSize.height)
    : Math.min(logical.width / sourceSize.width, logical.height / sourceSize.height);
  const drawWidth = sourceSize.width * scale;
  const drawHeight = sourceSize.height * scale;
  const canvas = document.createElement("canvas");
  canvas.width = target.width;
  canvas.height = target.height;
  const context = canvas.getContext("2d", { alpha: false, willReadFrequently: true });
  context.fillStyle = "white";
  context.fillRect(0, 0, target.width, target.height);
  context.save();
  if (rotate) {
    context.translate(0, target.height);
    context.rotate(-Math.PI / 2);
  }
  context.translate((logical.width - drawWidth) / 2, (logical.height - drawHeight) / 2);
  await drawSource(context, pageNumber, drawWidth, drawHeight);
  context.restore();
  const image = context.getImageData(0, 0, target.width, target.height);
  return packMonochromeInWorker(image, target.width, target.height, state.type === "pdf");
}

function packMonochromeInWorker(image, width, height, reverseHorizontally) {
  return runWorker("pack", {
    data: image.data,
    width,
    height,
    reverseHorizontally,
    mode: elements.contentMode.value,
    lightness: Number(elements.lightness.value)
  }, [image.data.buffer]);
}

function encodePages(pages, total) {
  return runWorker("encode", {
    pages,
    jobName: "Web Print",
    copies: state.copies,
    duplex: elements.duplex.checked,
    resolution: Number(elements.resolution.value)
  }, pages.map(page => page.data.buffer), message => {
    updateProgress("正在压缩打印数据", `编码第 ${message.completed}/${message.total} 页`, .7 + .18 * message.completed / total);
  });
}

function runWorker(type, payload, transfer, onProgress) {
  return new Promise((resolve, reject) => {
    const worker = new Worker("encoder-worker.js");
    state.worker = worker;
    state.workerReject = reject;
    worker.onmessage = event => {
      const message = event.data;
      if (message.type === "progress") {
        if (onProgress) onProgress(message);
        return;
      }
      worker.terminate();
      if (state.worker === worker) state.worker = null;
      state.workerReject = null;
      if (message.type === "complete") resolve(message.bytes);
      else if (message.type === "packed") resolve(message.page);
      else if (message.type === "cancelled") reject(new DOMException("已取消", "AbortError"));
      else reject(new Error(message.message || "编码器异常"));
    };
    worker.onerror = event => {
      worker.terminate();
      if (state.worker === worker) state.worker = null;
      state.workerReject = null;
      reject(new Error(event.message || "编码器异常"));
    };
    worker.postMessage({ type, payload }, transfer);
  });
}

function cancelPrint() {
  state.cancelled = true;
  if (state.worker) {
    state.worker.terminate();
    state.worker = null;
  }
  if (state.workerReject) {
    state.workerReject(new DOMException("已取消", "AbortError"));
    state.workerReject = null;
  }
  if (state.uploadController) state.uploadController.abort();
  elements.progressDetail.textContent = "正在取消";
}

function parsePageRange(value, count) {
  const trimmed = value.replace(/\s/g, "");
  if (!trimmed) return Array.from({ length: count }, (_, index) => index + 1);
  const pages = new Set();
  trimmed.split(",").forEach(part => {
    if (/^\d+$/.test(part)) pages.add(Number(part));
    else {
      const match = part.match(/^(\d+)-(\d+)$/);
      if (!match || Number(match[1]) > Number(match[2])) throw new Error("页码格式不正确，例如 1-3,5");
      for (let page = Number(match[1]); page <= Number(match[2]); page += 1) pages.add(page);
    }
  });
  const result = [...pages].sort((a, b) => a - b);
  if (!result.length || result.some(page => page < 1 || page > count)) throw new Error(`页码超出文档范围（共 ${count} 页）`);
  return result;
}

function selectedOrientation() {
  return document.querySelector('input[name="orientation"]:checked').value;
}

function setCopies(value) {
  state.copies = Math.max(1, Math.min(20, value));
  elements.copiesOutput.textContent = String(state.copies);
  updateSummary();
}

function updateSummary() {
  let pageCount = state.pageCount;
  if (state.file) {
    try { pageCount = parsePageRange(elements.pageRange.value, state.pageCount).length; } catch (_) {}
  }
  elements.jobSummary.textContent = state.file ? `${pageCount} 页 · ${elements.duplex.checked ? "双面" : "单面"} · ${state.copies} 份` : "尚未选择文档";
  elements.printButton.disabled = !state.file || !state.online || state.busy;
}

function setPreviewLoading(loading) { elements.previewLoading.hidden = !loading; }
function openSettings() {
  document.body.classList.add("settings-open");
  elements.settingsPanel.classList.add("open");
  elements.settingsBackdrop.hidden = false;
}
function closeSettings() {
  document.body.classList.remove("settings-open");
  elements.settingsPanel.classList.remove("open");
  elements.settingsBackdrop.hidden = true;
}

function containSettingsScroll() {
  let previousY = 0;
  elements.settingsPanel.addEventListener("touchstart", event => {
    if (event.touches.length === 1) previousY = event.touches[0].clientY;
  }, { passive: true });
  elements.settingsPanel.addEventListener("touchmove", event => {
    if (event.touches.length !== 1) return;
    const currentY = event.touches[0].clientY;
    const movingDown = currentY > previousY;
    const atTop = elements.settingsPanel.scrollTop <= 0;
    const atBottom = elements.settingsPanel.scrollTop + elements.settingsPanel.clientHeight >= elements.settingsPanel.scrollHeight - 1;
    if ((atTop && movingDown) || (atBottom && !movingDown)) event.preventDefault();
    previousY = currentY;
  }, { passive: false });
}
function showProgress(title, detail, fraction) { elements.progressDialog.hidden = false; updateProgress(title, detail, fraction); }
function updateProgress(title, detail, fraction) { elements.progressTitle.textContent = title; elements.progressDetail.textContent = detail; elements.progressBar.style.width = `${Math.max(0, Math.min(1, fraction)) * 100}%`; }
function hideProgress() { elements.progressDialog.hidden = true; }
function formatBytes(bytes) { return new Intl.NumberFormat("zh-CN", { style: "unit", unit: bytes >= 1048576 ? "megabyte" : "kilobyte", maximumFractionDigits: 1 }).format(bytes / (bytes >= 1048576 ? 1048576 : 1024)); }
function delay(milliseconds) { return new Promise(resolve => setTimeout(resolve, milliseconds)); }
function nextFrame() { return new Promise(resolve => requestAnimationFrame(() => resolve())); }
let toastTimer;
function showToast(message) { clearTimeout(toastTimer); elements.toast.textContent = message; elements.toast.hidden = false; toastTimer = setTimeout(() => { elements.toast.hidden = true; }, 3200); }
