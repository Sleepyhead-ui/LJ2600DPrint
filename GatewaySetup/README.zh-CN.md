# 光猫打印服务检测与安装

[English](README.md) | **简体中文**

`Manage-PrintGateway.ps1` 用于检测 Linux 光猫能否充当 USB 打印服务器，并生成兼容性报告。对于已经识别和验证的烽火固件，还可以在用户明确指定后安装可撤销的 LPD 守护服务。

默认动作仅检查，不会安装服务：

```powershell
.\GatewaySetup\Manage-PrintGateway.ps1
```

报告会分别列出 USB 打印设备、必要命令、可写持久分区、自启动机制、端口占用和已有服务。兼容性等级含义如下：

- **A 级**：支持自动安装；
- **B 级**：可以运行 LPD，但需要针对具体型号适配自启动；
- **C 级**：存在 `/dev/lp0`，可能只能临时进行原始数据转发；
- **D 级**：没有识别到 USB 打印字符设备。

仅凭 `/dev/lp0` 无法判断打印机语言是否兼容。无论检测等级如何，更换打印机后都必须使用对应配置进行真实打印测试。

## 安装和撤销

先预演安装。此命令只检查本机安装包，不开启 Telnet，也不修改光猫：

```powershell
.\GatewaySetup\Manage-PrintGateway.ps1 -Action Install -WhatIf
```

在 A 级光猫上安装 LPD 服务：

```powershell
.\GatewaySetup\Manage-PrintGateway.ps1 -Action Install
```

同时部署可选的局域网网页版，并设置 4 至 12 位数字 PIN：

```powershell
.\GatewaySetup\Manage-PrintGateway.ps1 -Action Install -IncludeWebPrint -Pin 123456
```

撤销由本工具管理的改动：

```powershell
.\GatewaySetup\Manage-PrintGateway.ps1 -Action Uninstall
```

安装时会备份原自启动配置、保留原 `/osgi/lj2600d-print` 目录、校验安装包 SHA-256，并在失败时自动回滚，最后验证 TCP 515。若安装前已有旧打印服务，卸载时会恢复旧服务；若原来没有服务，则撤销自启动改动并保留文件供检查。

## 登录和安全边界

已验证的烽火流程会从本机邻居表读取光猫 MAC，通过本地维护接口临时开启 Telnet，并使用固件的 MAC 派生 `admin` 凭据登录。无法自动读取邻居表时，可以显式传入 `-MacAddress`。只有由工具开启的 Telnet 才会在结束后自动关闭。

对于已经自行开启 Telnet 的其他 Linux 光猫，可以传入登录凭据进行检查：

```powershell
$credential = Get-Credential
.\GatewaySetup\Manage-PrintGateway.ps1 -Action Check -Credential $credential
```

遇到未知自启动格式时，工具只生成报告，不猜测修改 init、cron 或厂商配置。请仅在自己拥有或获准管理的设备上使用。兼容性报告不会记录完整 MAC、Telnet 密码、登录凭据或网页版 PIN。

当前实机验证环境为 ARMv7、Linux 4.1.52、BusyBox 1.30.1，具有 `/fhconf/process_start_list`、可写 `/osgi`、`tcpsvd`、`softlimit` 和 `lpd`；联想 LJ2600D 被识别为 `/dev/lp0`，USB ID 为 `17ef:5411`。
