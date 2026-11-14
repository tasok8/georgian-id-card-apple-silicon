# Before any public release of a built app

Status: **only the source/recipe (this repository) is public. No built app, DMG or Java runtime has
been distributed.** This checklist is for whoever produces an official or redistributable build –
ideally PSDA itself (see §6).

## 1. Permission (blocking)

- The application is proprietary: "Copyright © 2019 Giorgi Giorkhelidze", distributed and signed by
  the **Public Service Development Agency (PSDA / id.ge)**. No licence file grants redistribution.
- Get **written permission from PSDA** (or have PSDA ship the build themselves – preferred, see §6)
  before giving a built app to anyone else.
- If a third party ever distributes it: use a **different bundle ID and name** (e.g. "Georgian ID Card
  – unofficial arm64 build"), do not use PSDA branding as if official, and say clearly who built it.

## 2. Licences of components (redistributable, with notices)

| Component | Licence | Obligation |
|---|---|---|
| Azul Zulu OpenJDK 17 + OpenJFX 17 | GPLv2 + Classpath Exception | Keep `Contents/Resources/jre/legal/` (included by jlink); offer source pointer (openjdk.org / Azul) |
| Eclipse Equinox 3.15 | EPL-2.0 | Notice; source available from Eclipse |
| BouncyCastle | MIT | Notice |
| EU DSS 5.11, JasperReports, jmrtd, scuba, JUnique, JFreeChart, jcommon | LGPL | Unmodified jars – keep notices, allow replacement |
| JNA 5.5 | Apache-2.0 / LGPL-2.1 | Notice |
| PDFBox, Log4j, Commons, Gson, Jackson, HttpClient, Castor | Apache-2.0 | NOTICE files |
| ecj | EPL | Notice |

Add a `THIRD-PARTY-NOTICES` file to any release collecting these.

## 3. Code signing (required for a smooth install)

- Apple Developer Program membership → **Developer ID Application** certificate (ideally PSDA's own team).
- Build with: `CODESIGN_IDENTITY="Developer ID Application: <Team> (<TEAMID>)" src/build.sh --dist`
  – signs every runtime binary, launcher and bundle with hardened runtime, secure timestamp and
  `src/entitlements.plist` (JIT, unsigned executable memory, disable library validation – standard for a JVM).
- macOS permissions: none beyond defaults. PC/SC needs no entitlement (app is not sandboxed);
  network access is outgoing only (id.ge updates, OCSP/CRL, timestamping).

## 4. Notarization (required for Gatekeeper on downloaded apps)

```bash
xcrun notarytool submit dist/GeorgianIDCard-1.0-arm64.dmg --keychain-profile <profile> --wait
xcrun stapler staple dist/GeorgianIDCard-1.0-arm64.dmg
spctl -a -vv -t open --context context:primary-signature dist/GeorgianIDCard-1.0-arm64.dmg
```

Known notarization blockers to fix first:

1. **Unsigned Intel binary inside a jar**: `plugins/unitool-mainframe.jar` → `jna-5.5.0.jar` →
   `com/sun/jna/darwin/libjnidispatch.jnilib` (i386/x86_64, unsigned). The notary service inspects
   nested archives. Fix in the plugin's Maven build: upgrade JNA to a current 5.x (which also adds
   `darwin-aarch64`) and sign the extracted jnilib, or exclude the darwin library (JNA is only used on Windows).
2. **The app writes inside its own bundle** (`debug.log`, `config.properties`, `configuration/` OSGi
   cache, plugin updates downloaded from id.ge into `plugins/`). This breaks the sealed signature
   after first run (the current official app already shows "a sealed resource is missing or
   invalid"). Fix: move writable state to `~/Library/Application Support/Georgian ID Card/`
   (launcher can `chdir` there after seeding it, or pass `-Dosgi.configuration.area` and change the
   relative paths in `Main`).
3. Lower the default log level from DEBUG and keep logs outside the bundle – DEBUG logs can contain
   certificate details.

## 5. Tests required before release

Run on at least: one M-series Mac on the oldest supported macOS (11) and one on the current
release; one generic CCID reader and one PIN-pad reader; current ID card generation(s) and eSeal card.

- Install from DMG on a clean user account with Gatekeeper on (no "Open Anyway" after notarization).
- Launch, reader hot-plug, card insert/remove, card info, certificate view/export.
- PIN verify, PIN change, PUK unblock (test cards only), PIN-pad reader entry.
- PDF/PAdES sign + validate in Adobe Acrobat, CMS sign/verify, visual signature, extend signature
  (TSA), web signer, certificate update, plugin auto-update from id.ge, language switch ka/en.
- Coexistence/upgrade over the Intel app; uninstall.
- `codesign --verify --deep --strict`, `spctl -a -vv`, notarization log has no warnings.

## 6. Recommended route for the maintainer

The cleanest fix is upstream: PSDA builds the same app with an arm64 (or universal) runtime via
`jpackage` or this repo's `build.sh`, signs with their Developer ID, notarizes, and publishes on
id.ge. The changes needed are exactly the ones in `docs/CHANGES.md` plus §4 items 1–3.
