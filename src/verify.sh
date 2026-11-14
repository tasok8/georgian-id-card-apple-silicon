#!/bin/bash
# Audit helper: compare the official app with an arm64 rebuild and show
# exactly what differs. Read-only; touches neither app.
#
# Usage: src/verify.sh [ORIGINAL.app] [REBUILT.app]
#   defaults: "/Applications/Georgian ID Card.app"  "build/Georgian ID Card.app"
#
# Expected result: every .jar identical; differences limited to
#   Contents/MacOS/Georgian ID Card   (new launcher, source: src/launcher/main.c)
#   Contents/Resources/jre/           (replaced runtime: Azul Zulu 17 FX aarch64)
#   Contents/Info.plist               (min macOS / arm64 keys)
#   Contents/_CodeSignature/          (new ad-hoc signature)
#   runtime state the app writes itself (debug.log, logging.log, config.properties,
#   configuration/org.eclipse.osgi)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
O="${1:-/Applications/Georgian ID Card.app}"
N="${2:-$ROOT/build/Georgian ID Card.app}"
[[ -d "$O" && -d "$N" ]] || { echo "usage: $0 ORIGINAL.app REBUILT.app" >&2; exit 2; }
fail=0

echo "== 1. Java code: all jars must be byte-identical (OSGi runtime cache excluded)"
while IFS= read -r -d '' j; do
  rel="${j#"$O"/}"
  if [[ ! -f "$N/$rel" ]]; then echo "  MISSING  $rel"; fail=1
  elif cmp -s "$j" "$N/$rel"; then printf '  same     %s  %s\n' "$(shasum -a 256 "$j" | cut -c1-16)" "$rel"
  else echo "  CHANGED  $rel"; fail=1; fi
done < <(find "$O/Contents/Resources" \( -path "*/jre" -o -path "*/configuration/org.eclipse.osgi" \) -prune -o -name '*.jar' -print0 | sort -z)
extra=$(cd "$N/Contents/Resources" && find . \( -path ./jre -o -path ./configuration/org.eclipse.osgi \) -prune -o -name '*.jar' -print | while read -r f; do [[ -f "$O/Contents/Resources/$f" ]] || echo "$f"; done)
[[ -n "$extra" ]] && { echo "  EXTRA jars in rebuild: $extra"; fail=1; }

echo; echo "== 2. All other differences (runtime folder summarised separately)"
diff -rq -x jre "$O" "$N" 2>&1 | sed "s|$O|ORIG|g; s|$N|NEW|g" | sed 's/^/  /'

echo; echo "== 3. Runtimes"
echo "  ORIG: $(grep JAVA_VERSION "$O/Contents/Resources/jre/release" 2>/dev/null)"
echo "  NEW : $(grep JAVA_VERSION "$N/Contents/Resources/jre/release")"

echo; echo "== 4. Architectures of all Mach-O files"
for b in "$O" "$N"; do
  tag=$([[ $b == "$O" ]] && echo ORIG || echo NEW)
  find "$b" -type f -print0 | xargs -0 file | grep 'Mach-O' | sed -E 's/.*Mach-O.* (executable|dynamically linked shared library|bundle) //' \
    | sort | uniq -c | sed "s/^/  $tag /"
done
if find "$N" -type f -print0 | xargs -0 file | grep 'Mach-O' | grep -vq arm64; then echo "  non-arm64 binary in rebuild!"; fail=1; fi

echo; echo "== 5. Launch command"
echo "  ORIG launcher strings:"; strings -a "$O/Contents/MacOS/Georgian ID Card" | grep -E '^(-D|-cp|jre/|org\.eclipse|ge\.id)' | sed 's/^/    /'
echo "  NEW launcher strings:";  strings -a "$N/Contents/MacOS/Georgian ID Card" | grep -E '^(-D|-X|--add|-cp|jre/|org\.eclipse|ge\.id)' | sed 's/^/    /'

echo; echo "== 6. Signatures"
for b in "$O" "$N"; do codesign -dvv "$b" 2>&1 | grep -E '^(Format|Authority|TeamIdentifier|Signature=)' | sed "s|^|  $(basename "$b" .app): |"; done

echo
if [[ $fail == 0 ]]; then echo "RESULT: OK - application code identical; only launcher, runtime, plist, signature and runtime state differ"; else echo "RESULT: UNEXPECTED DIFFERENCES - see above"; fi
exit $fail
