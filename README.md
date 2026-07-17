# LJ2600D Print

Experimental iOS 16 app for sending PDF/image documents to the Lenovo LJ2600D
through the optical gateway's LPD service.

The app is designed for installation with TrollStore. It does not depend on
AirPrint discovery: the gateway address and LPR queue are entered manually.

The first prototype contains:

- PDF and image selection with Core Graphics rendering;
- a minimal Brother/Lenovo HBP raster encoder;
- an RFC 1179 LPR client over `192.168.1.1:515`;
- an unsigned IPA build workflow for GitHub Actions.

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
