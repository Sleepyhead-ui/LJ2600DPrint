# LJ2600D Web Print

无需安装 App 的局域网打印前端，目标浏览器为 iOS 16.5.1 至 iOS 27 Safari，以及现代 Android/桌面浏览器。浏览器负责解析 PDF/图片、生成 LJ2600D HBP 数据，烽火光猫只通过受限 CGI 将打印数据流式写入 USB 打印机。

iOS 16.5.1 是当前实机验证基线；iOS 26/27 属于兼容目标。实现不依赖新版 WebKit 独有 API，黑白化与 HBP 压缩在 Web Worker 中运行，因此同一版本可覆盖旧设备和新设备。上线后仍应分别在实际设备上完成一次单页测试。

## 第一版范围

- 单个 PDF 或多张 JPEG、PNG、WebP 图片导入，并按选择顺序逐页预览；
- 页码范围、自动/纵向/横向、适合/填满页面；
- 文字、图形、图片三种黑白处理及五档深浅；
- 300 dpi、份数和长边双面打印；
- 单次最多 24 页，较长文档可用页码范围分批打印；
- 4 至 12 位打印 PIN；
- 添加到 iOS 主屏幕后以独立窗口运行。

300 dpi 是移动 Safari 的稳定性选择。600 dpi A4 灰度画布需要约 125 MB 连续内存，后续需要实现分条渲染才能安全开放。

光猫使用 HTTP 提供页面。iOS 可以添加到主屏幕，但 Service Worker 离线缓存需要 HTTPS，因此首次打开和重新载入时必须连接家中 Wi-Fi。所有库均保存在光猫本地，不访问互联网。

## 光猫服务

- 地址：`http://192.168.1.1:8631/`
- 持久目录：`/osgi/lj2600d-web`
- 静态服务器：BusyBox `httpd`
- 状态接口：`GET /cgi-bin/status.cgi`
- 打印接口：`POST /cgi-bin/print.cgi`
- 最大任务：32 MB

打印接口只接受固定同源请求、正确 PIN、合法长度和带 LJ2600D PJL/HBP 文件头的数据。接口不提供命令执行、文件读取或光猫配置修改。任务通过 `/var/tmp` 互斥锁串行发送，数据不落盘。

## 部署

部署由仓库中的 `scripts/Deploy-LJ2600D-WebPrint.ps1` 完成。脚本临时开启 Telnet，优先让光猫从本机的一次性 HTTP 服务下载固定安装包；若局域网防火墙阻止连接，则自动改用较慢的 Telnet 分块上传。两种路径都会先校验 SHA-256，再执行安装，并在结束后关闭由脚本开启的 Telnet。

安装会备份现有 `/osgi/lj2600d-print/watch.sh`，并在其中启动独立网页守护进程；不会修改 80/8080 管理服务和现有 515 LPR 服务。更新时会继续保留最初备份；如果新版本安装失败，脚本会自动恢复上一个版本。

在 Windows PowerShell 中运行：

```powershell
.\WebPrint\scripts\Deploy-LJ2600D-WebPrint.ps1 -Pin 你的4至12位数字PIN
```

完成后，从同一家庭 Wi-Fi 中打开 `http://192.168.1.1:8631/`。iOS 可使用 Safari 的“添加到主屏幕”；由于页面由 HTTP 提供，重新载入时仍需连接家庭 Wi-Fi。

卸载脚本会停止 8631 服务并恢复原始 `watch.sh`，文件保留在 `/osgi/lj2600d-web` 供检查。完整删除应在确认恢复无误后手动执行。

第三方库及许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
