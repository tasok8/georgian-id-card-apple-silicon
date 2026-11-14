# Building and installing on your own Mac

> Unofficial. This builds an Apple silicon version of the official Georgian ID Card app **from your
> own installed copy**. The application code is unchanged; only the launcher and Java runtime are
> replaced. Official software and support: https://id.ge

## Requirements

- Mac with Apple silicon (M1 or later), macOS 11 Big Sur or newer
- Xcode Command Line Tools: `xcode-select --install`
- The official **Georgian ID Card** app from id.ge installed at `/Applications/Georgian ID Card.app`
  (used read-only as input)
- Internet access for the first build (downloads Azul Zulu 17 from `cdn.azul.com`, SHA-256 checked)
- For card use: a USB smart-card reader (CCID compliant – most readers; no driver needed on macOS)

## Build

```bash
git clone https://github.com/tasok8/georgian-id-card-apple-silicon.git
cd georgian-id-card-apple-silicon
src/build.sh
```

The result is `build/Georgian ID Card.app`. Your original app is not modified.

Check that only the launcher, runtime, `Info.plist` and signature differ from the official app:

```bash
src/verify.sh "/Applications/Georgian ID Card.app" "build/Georgian ID Card.app"
```

## Install

1. Quit the existing **Georgian ID Card** app if it is running.
2. Copy the build next to the original under a different name, so the Intel version stays as a fallback:

   ```bash
   ditto "build/Georgian ID Card.app" "/Applications/Georgian ID Card (Apple silicon).app"
   ```

3. Open it. Because you built it yourself it is not quarantined, so Gatekeeper normally does not
   block it. If macOS does block it, open **System Settings → Privacy & Security** and click
   **Open Anyway** once. Do not disable Gatekeeper globally.

## Check that it runs natively

Activity Monitor → CPU tab → the "Kind" column should show **Apple** for "Georgian ID Card".

## Using the card

1. Plug in the reader and insert the card.
2. The app should list the reader and the card. Enter your PIN **only** in the app's own PIN dialog.
3. Do not share `Contents/Resources/debug.log` publicly – it can contain certificate details.

## Uninstall / roll back

Move `Georgian ID Card (Apple silicon).app` to the Bin. The original Intel app is untouched
(it needs Rosetta 2, which Apple is phasing out).

## Troubleshooting

| Symptom | What to try |
|---|---|
| "Application is already open" | Another copy (e.g. the Intel one) is running – quit it. |
| No reader shown | Re-plug the reader; check System Information → Hardware → USB / SmartCards. |
| Card not detected | Reinsert the card; try another USB port or reader. |
| App does not start | Run `"/Applications/Georgian ID Card (Apple silicon).app/Contents/MacOS/Georgian ID Card"` in Terminal and look at the output (it contains no PIN). |
