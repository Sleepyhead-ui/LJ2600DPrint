# LJ2600D Print

**English** | [简体中文](README.zh-CN.md)

Experimental iOS 16 app for sending PDF/image documents to the Lenovo LJ2600D
through the optical gateway's LPD service.

Devices that cannot install the app can use the local-network web client in
[`WebPrint`](WebPrint/README.zh-CN.md). It targets Safari on iOS 16.5.1 through
iOS 27, plus current Android and desktop browsers, and requires no app install.
The iOS 26/27 range is a compatibility target; real-device printing has so far
been verified on iOS 16.5.1.

The app is designed for installation with TrollStore. It does not depend on
AirPrint discovery: the gateway address and LPR queue are entered manually.

[`GatewaySetup`](GatewaySetup/README.md) provides a read-only compatibility
probe and a reversible LPD installer for recognized FiberHome gateways. It
reports unsupported devices without guessing at vendor startup configuration.

The current app includes:

- PDF and image import through a UIKit copy-mode document picker;
- Core Graphics document rendering;
- a minimal Brother/Lenovo HBP raster encoder;
- an RFC 1179 LPR client over `192.168.1.1:515`;
- an in-app service health check and recovery flow for supported FiberHome gateways;
- recent successful print history with retained source files and saved settings;
- quick reprint or reopen-and-adjust actions from a native history detail view;
- 1-up, 2-up, and 4-up sheet imposition with an optional printed page border;
- privacy-sanitized diagnostics, read-only port checks, and text report export;
- a TrollStore IPA build workflow for GitHub Actions.

Print history is limited to 20 jobs and 250 MB. Its retained source files are
stored in Application Support, excluded from device backups, and removed with
their history entries.

## Print service recovery

The print-service settings page checks TCP port 515 before a job is rendered.
If the service is offline, the user can enter the gateway MAC address and start
a recovery. The app uses the gateway's local FiberHome maintenance endpoint,
logs in with the MAC-derived Telnet credential, checks `/dev/lp0`, and starts
the installed reversible watchdog or a temporary LPD fallback. Telnet is closed
afterward when the app opened it.

The MAC address is stored only in the app's local preferences. It is not built
into this public repository or transmitted outside the local network.

The encoder is intentionally marked experimental. The Windows driver files
indicate that LJ2600D is closely related to Brother HL-2240D, but the exact
compatibility must be confirmed with a real print job.

## GitHub Actions build

Push this directory to a GitHub repository and run **Build TrollStore IPA**.
The workflow generates the Xcode project, builds for `iphoneos` without an
Apple developer certificate, applies an ad-hoc `ldid` signature, and uploads
`LJ2600DPrint.ipa` as an artifact. Download the artifact and install it with
TrollStore.

This project uses the public brlaser line/block format as a reference. If the
encoder is distributed beyond personal use, retain the GPL notice and source
availability required by brlaser.
