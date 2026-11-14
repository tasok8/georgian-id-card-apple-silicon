**English** | [ქართული](README.ka.md)

# Georgian ID Card for Apple silicon (unofficial)

**Unofficial** build recipe that makes the official
[Georgian ID Card](https://id.ge) macOS app (`ge.id.card.Georgian-ID-Card`, version 1.0 /
plugins 2.0.1) run natively on Apple silicon Macs, without Rosetta.

This repository contains **no PSDA code and no prebuilt app** – only a small launcher source, build
and verification scripts, and documentation. You rebuild the app from **your own installed copy** of
the official application.

> Not affiliated with or endorsed by the Public Service Development Agency (PSDA). For official
> software and support, use https://id.ge.

## The problem

The official macOS app is Intel-only. On Apple silicon it runs through Rosetta 2, and macOS warns
that it will no longer launch in macOS 28, as Apple phases out Rosetta.

## The finding

Only the packaging is Intel-specific. The application itself is 100 % Java (OSGi/Equinox + JavaFX).
Just two parts of the bundle are x86_64-only:

1. `Contents/MacOS/Georgian ID Card` – a tiny launcher that starts Java.
2. `Contents/Resources/jre` – a bundled x86_64 Java 14 + JavaFX 14 runtime.

Smart-card access uses `javax.smartcardio` → macOS `PCSC.framework` → Apple's built-in CCID driver,
so no vendor driver is involved. The only native smart-card piece is the JDK's own `libj2pcsc`,
which the new runtime ships for arm64. The JNA and proxy native libraries inside the plugins are only
used on Windows. Details: [docs/CHANGES.md](docs/CHANGES.md).

## The solution

| Change | Details |
|---|---|
| New launcher | ~60-line native arm64 C program ([`src/launcher/main.c`](src/launcher/main.c)), same behaviour as the original |
| New runtime | Azul Zulu 17 LTS + JavaFX 17 for macOS aarch64, SHA-256 pinned, `jlink`ed to the original module set |
| `Info.plist` | Minimum macOS 11, arm64 architecture priority |
| Signature | Ad-hoc (local use); Developer ID supported via `CODESIGN_IDENTITY` |
| **Unchanged** | **Every `.jar` is byte-for-byte identical to the official app** – no card, PIN, certificate or signing logic is touched |

## Repository contents

| Path | What it is |
|---|---|
| `src/launcher/main.c` | Source of the native arm64 launcher |
| `src/build.sh` | Builds the arm64 app from your official installation |
| `src/verify.sh` | Audit: proves all jars are identical and lists every other difference |
| `src/entitlements.plist` | Hardened-runtime entitlements for a Developer ID release |
| `src/tests/PcscProbe.java` | Read-only PC/SC reader probe (never talks to the card) |
| `docs/INSTALL.md` | Build and install instructions |
| `docs/CHANGES.md` | Investigation, changes, test results |
| `docs/RELEASE-CHECKLIST.md` | Permission, licences, signing and notarization needed for any official release |

## Requirements

- Apple silicon Mac, macOS 11 or newer
- Xcode Command Line Tools (`xcode-select --install`)
- The official app installed at `/Applications/Georgian ID Card.app` (read-only input)
- Internet access for the first build (Java runtime download from `cdn.azul.com`)

## Build and use

```bash
src/build.sh                     # -> build/Georgian ID Card.app
src/verify.sh                    # compare with /Applications/Georgian ID Card.app
```

Options: `ORIG_APP=…`, `JDK_HOME=…`, `CODESIGN_IDENTITY="Developer ID Application: …"`,
and `src/build.sh --dist` for a zip/DMG (for local or PSDA testing only – see below).
Installation and first launch: [docs/INSTALL.md](docs/INSTALL.md).

## Test results (summary)

Tested on two Apple silicon Macs (macOS 27.2.1 and 26.3.1). Full tables are in
[docs/CHANGES.md](docs/CHANGES.md); signing evidence in [docs/evidence](docs/evidence/README.md).

- **Passed:** All Mach-O files arm64; runs natively (not translated); all 16 OSGi bundles start; main window opens
- **Passed:** Quit, relaunch, second-launch re-activation; built-in update check against id.ge
- **Reported working by the card holder:** reader and card detection, card info, certificates, PIN verification, signing, web signer
- **Passed (second Mac, 2026-11-14):** fresh build from this repo, native launch, PDF signing with an ID card – validated independently as PAdES baseline LT with trusted timestamp
- **Known issue:** after accepting the in-app update dialog, the app once hung on "Please wait…"; force quit and relaunch fixed it
- **Not tested:** certificate update, eSeal card, PIN-pad readers, PIN change/PUK unblock, a second Mac, a clean user account, **macOS 28**

## Limitations

- **Unofficial and unsupported.** Use at your own risk; for official support contact PSDA.
- Ad-hoc signed and **not notarized**. Gatekeeper rejects it if it is downloaded rather than built locally.
- The app writes logs and settings inside its own bundle (same as the official app).
  `debug.log` can contain certificate details – don't share it.
- **Do not redistribute built apps.** The official application is proprietary
  (© 2019 Giorgi Giorkhelidze, distributed by PSDA). Any redistribution needs PSDA's permission;
  see [docs/RELEASE-CHECKLIST.md](docs/RELEASE-CHECKLIST.md). The intended route is for PSDA to ship
  an official Apple silicon build.

## Credits

- **Georgian ID Card** application: © 2019 Giorgi Giorkhelidze, distributed by the Public Service
  Development Agency of Georgia (PSDA, id.ge). None of its code is included here.
- Java runtime: Azul Zulu (OpenJDK + OpenJFX, GPLv2 with Classpath Exception), downloaded at build time.
- Project by Anastasia Kudzeshvili ([@tasok8](https://github.com/tasok8)): identified the problem,
  directed the investigation, built and tested the app on her Mac with the card holder, reviewed
  the changes and published this repository.
- **AI assistance:** the investigation, launcher, scripts and documentation were produced with
  the help of an AI assistant, then reviewed before publication.

## License

The files in this repository are released under the [MIT License](LICENSE). This does **not** apply
to the Georgian ID Card application or any third-party software it contains.
