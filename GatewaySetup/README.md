# Print Gateway Setup

[English](README.md) | [简体中文](README.zh-CN.md)

`Manage-PrintGateway.ps1` checks whether a Linux-based optical gateway can act
as a raw USB print server. On a recognized FiberHome firmware it can install a
reversible LPD watchdog after explicit approval.

The default action is read-only:

```powershell
.\GatewaySetup\Manage-PrintGateway.ps1
```

The generated report separates USB detection, required commands, writable
persistent storage, startup support, listening ports, and existing services.
Compatibility grades mean:

- **A**: automatic installation is supported;
- **B**: LPD can run, but startup needs model-specific adaptation;
- **C**: `/dev/lp0` exists, so temporary raw forwarding may work;
- **D**: no USB printer character device was detected.

Printer-language compatibility cannot be inferred from `/dev/lp0`. It always
requires a real print test with the selected printer profile.

## Install and revert

Preview the operation without opening Telnet or changing the gateway:

```powershell
.\GatewaySetup\Manage-PrintGateway.ps1 -Action Install -WhatIf
```

Install the LPD service on a grade A gateway:

```powershell
.\GatewaySetup\Manage-PrintGateway.ps1 -Action Install
```

Install LPD and then deploy the optional local Web Print client:

```powershell
.\GatewaySetup\Manage-PrintGateway.ps1 -Action Install -IncludeWebPrint -Pin 123456
```

Revert only changes managed by this tool:

```powershell
.\GatewaySetup\Manage-PrintGateway.ps1 -Action Uninstall
```

The installer saves the pre-install startup configuration, retains the
previous `/osgi/lj2600d-print` directory, verifies the archive SHA-256, rolls
back after a failed install, and checks TCP port 515. The verified FiberHome
firmware reads its process list from a read-only ROM volume, so the installer
uses the vendor's OSGi lifecycle instead. A small auto-start bundle waits for
Felix, temporarily enables the local maintenance shell, starts the root print
watchdog, and closes the shell again. The original `/osgi/install.conf` and any
bundle at the target path are backed up and restored by uninstall.

## Access and safety

The verified FiberHome path discovers the gateway MAC from the local neighbor
table, temporarily enables Telnet through the local maintenance endpoint, and
uses the firmware's MAC-derived `admin` credential. Supply `-MacAddress` when
neighbor discovery is unavailable. Telnet is closed afterward only when the
tool opened it.

For another gateway with an already enabled Telnet server, pass a credential:

```powershell
$credential = Get-Credential
.\GatewaySetup\Manage-PrintGateway.ps1 -Action Check -Credential $credential
```

Unknown startup formats are report-only. The tool does not guess at init files
or modify unsupported firmware. Use it only on equipment you own or are
authorized to administer. Reports never include the MAC, Telnet password,
credential, or Web Print PIN.

The currently verified gateway is ARMv7/Linux 4.1.52 with BusyBox 1.30.1,
the FiberHome OSGi lifecycle, writable `/osgi`, `tcpsvd`, `softlimit`, `lpd`,
and a Lenovo LJ2600D exposed as `/dev/lp0` (USB `17ef:5411`).
