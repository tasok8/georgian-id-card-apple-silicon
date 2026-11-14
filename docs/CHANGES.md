# Change record – Georgian ID Card arm64 repack

Date: 2026-11-14 · Host: Apple silicon, macOS 27.2.1 · Input: `/Applications/Georgian ID Card.app`
(bundle 1.0, plugins 2.0.1, signed by "Public Service Development Agency" via DigiCert, no Apple
Team ID, not notarized). The original installation was only read; its launcher hash was verified
unchanged after the build.

## 1. Investigation summary

| Component | Arch / type | Needs change for arm64? |
|---|---|---|
| `MacOS/Georgian ID Card` launcher (Swift/ObjC, ~30 KB) | x86_64 only | **Yes** – rewritten |
| `Resources/jre` (Java 14.0.1 + JavaFX 14.0.1, 52 dylibs) | x86_64 only | **Yes** – replaced |
| `geoeid-unitool.jar` (container, log4j, JUnique), `org.eclipse.osgi.jar` 3.15.200 | Java | No |
| 14 OSGi plugins in `Resources/plugins` | Java | No |
| JNA 5.5.0 in `unitool-mainframe.jar` (darwin lib is i386/x86_64 only) | native, **Windows code paths only** | No (never loaded on macOS) |
| `network.jar` proxy DLLs | Windows only, optional | No |
| Smart-card stack | `javax.smartcardio` → `PCSC.framework` → Apple CCID driver (system) | No – JDK provides arm64 `libj2pcsc` |
| `configuration/org.eclipse.osgi` cache | records `osgi.arch=x86_64` | Removed; regenerated as `aarch64` |

Reconstructed original launch command (from the launcher binary):

```
cd Contents/Resources
jre/bin/java -Dsun.security.smartcardio.library=/System/Library/Frameworks/PCSC.framework/Versions/Current/PCSC \
     -cp org.eclipse.osgi.jar:geoeid-unitool.jar ge.id.card.unitool_container.Main <launcher argv>
```

## 2. Changes

1. **Launcher** – new native arm64 C program (`src/launcher/main.c`). Same working directory,
   classpath, main class, PC/SC library property and argument pass-through as the original. Small
   deliberate differences:
   - `execv` instead of spawn-and-exit → one process; macOS registers it as the app bundle,
     Quit works, a second launch re-activates the running app instead of starting a duplicate.
   - `-Xdock:name` / `-Xdock:icon` so the menu bar and Dock show "Georgian ID Card".
   - `--add-exports=java.desktop/com.apple.eawt=ALL-UNNAMED` so the app's own dock-icon code keeps
     working under Java 17 (Java 14 allowed it by default).
2. **Runtime** – Azul Zulu 17.0.21 LTS (build 17.70.113, JavaFX 17 bundled, macOS aarch64),
   SHA-256 pinned in `build.sh`, `jlink`ed to the original module set minus modules removed from
   Java (`jdk.aot`, `jdk.incubator.jpackage`, `jdk.scripting.nashorn`, `jdk.scripting.nashorn.shell` –
   none used by the app).
3. **Info.plist** – `LSMinimumSystemVersion` 10.10 → 11.0; added `LSArchitecturePriority=[arm64]`,
   `LSRequiresNativeExecution=true`, `CFBundleGetInfoString`. Bundle ID, name, version and URL
   scheme unchanged.
4. **Cleanup** – removed the stale `_CodeSignature`, the x86_64 OSGi cache, old `debug.log` /
   `logging.log` and `.DS_Store`. Dist build also resets `config.properties` to defaults.
5. **Signing** – ad-hoc (`codesign -s -`), inside-out. `codesign --verify --strict` passes.

**Not changed:** every `.jar` (verified byte-identical with `cmp`), all card, PIN, certificate,
signature and validation logic, trust stores, update mechanism, logging configuration.

## 3. Technical tests (build session, 2026-11-14, macOS 27.2.1)

These were run during the AI-assisted build session on one Apple silicon Mac. Re-run
`src/verify.sh` on your own build to reproduce the code-identity and architecture checks.

| Test | Result |
|---|---|
| No x86_64 code left in bundle (all 67 Mach-O files arm64) | Pass |
| Launch from Finder/`open`, process Code Type | Pass – ARM64, not translated |
| Splash → OSGi framework start → all 16 bundles → main window | Pass – no WARN/ERROR in log |
| JavaFX rendering libs (`libglass`, `libprism_es2`) loaded | Pass |
| Built-in plugin update check against id.ge | Pass – all 16 plugin hashes match server |
| Second launch while running | Pass – re-activates existing window, no duplicate |
| Quit (Apple Event) | Pass – orderly bundle shutdown, process exits |
| Cold restart with regenerated OSGi cache (`osgi.arch=aarch64`) | Pass |
| PC/SC native binding from bundled runtime (`PcscProbe`) | Pass – SunPCSC provider loads; 0 readers (none attached at that time) |
| Visual check of the window by automation | not done (no Screen Recording permission was granted) |

## 4. Tests with reader and card

Done by the card holder on the installed build. Card data, PINs and certificates were never
accessed by anyone else, and nothing from the card is published here.

The card holder reported that the app worked for the checks below. Results were reported as a
whole, not recorded function by function, so treat this as a user report rather than a formal
test log.

| Function | Result |
|---|---|
| Reader detection | Reported working |
| Card detection / card info screen | Reported working |
| Certificate viewing | Reported working |
| PIN verification (PIN entered only in the app's dialog) | Reported working |
| Signing: PDF (PAdES), CMS file signing, visual signature, validation, extend signature (TSA) | Reported working |
| Web signer window (JavaFX WebView) | Reported working |
| Certificate update (online) | unknown – only applicable if used |
| eSeal card, PIN-pad readers | unknown – only applicable if used |
| PIN change / PUK unblock | not tested (deliberately – wrong attempts can block a card) |

## 5. Dist build (local only, not distributed)

`src/build.sh --dist` → `dist/GeorgianIDCard-1.0-arm64.dmg` (~231 MB), `.zip` (~222 MB), `.sha256`.
Factory-default `config.properties`, no logs, no OSGi cache.

| Test | Result |
|---|---|
| `hdiutil verify` DMG, `unzip -t` zip | Pass |
| App copied out of the mounted DMG: `codesign --verify --strict` | Pass |
| Launch of that copy: ARM64, main window, 0 WARN/ERROR, update check OK, Quit | Pass |
| `spctl -a` (Gatekeeper) | Fail – "rejected" – expected for an ad-hoc, non-notarized build. The original app also fails `spctl` ("sealed resource is missing or invalid"). |
| Install on a second Mac / clean user account with quarantine | not tested |
| macOS 28 | not tested |

## 6. Independent re-test on a second Mac (2026-11-14, macOS 26.3.1)

Fresh `git clone` of this repository on a different Apple silicon Mac, built with `src/build.sh`,
installed next to the official app as `/Applications/Georgian ID Card (Apple silicon).app`.

| Test | Result |
|---|---|
| Build from a clean clone | Pass – no errors |
| Azul Zulu download matches the SHA-256 pinned in `build.sh` | Pass |
| `codesign --verify --strict` of the built app | Pass |
| `verify.sh`: no changed or extra jars; all 67 Mach-O files arm64 | Pass (the first run also listed the original app's OSGi runtime cache as "missing" – a `verify.sh` bug, fixed) |
| Runs natively (Activity Monitor Kind = Apple) | Pass |
| Running next to the Intel app | Expected refusal: "can't run two copies" – quit one first |
| Card + PIN + PDF (PAdES) signing with visual stamp | Pass – see [evidence](evidence/README.md) |
| Independent validation of the signed PDF (`pdfsig`) | Pass – signature valid, SHA-256, RFC 3161 timestamp, DSS/OCSP data (PAdES baseline LT) |
