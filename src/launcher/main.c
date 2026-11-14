/*
 * Georgian ID Card - native arm64 launcher
 *
 * Drop-in replacement for the original x86_64-only Swift/ObjC launcher
 * (Contents/MacOS/Georgian ID Card). Behaviour reconstructed from the original
 * binary:
 *
 *   1. chdir() to the bundle's Contents/Resources directory
 *      (the Java code uses relative paths: config.properties, plugins/,
 *       configuration/, debug.log ...)
 *   2. run  jre/bin/java
 *              -Dsun.security.smartcardio.library=<PCSC.framework>
 *              -cp org.eclipse.osgi.jar:geoeid-unitool.jar
 *              ge.id.card.unitool_container.Main  <all launcher argv>
 *      (the original passed NSProcessInfo.arguments, i.e. argv[0] included)
 *   3. if jre/bin/java is missing, show "Could not find java executable".
 *
 * Differences from the original (all deliberate, all small):
 *   - execv() instead of NSTask+terminate: one process instead of two, so the
 *     Dock/Quit behave like a normal app and a second Finder launch just
 *     re-activates the running app.
 *   - -Xdock:name / -Xdock:icon so the menu bar and Dock show the app name and
 *     icon instead of "java".
 *   - --add-exports java.desktop/com.apple.eawt: Main.setIconForMacos() uses
 *     com.apple.eawt reflectively; Java 14 allowed this by default, Java 17
 *     needs the export (otherwise it is only a logged, harmless failure).
 *   - macOS "-psn_*" process-serial-number arguments are filtered out.
 *
 * No security-relevant behaviour is changed: card access, PIN handling and
 * certificate handling are entirely inside the unmodified Java plugins.
 */
#include <CoreFoundation/CoreFoundation.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define PCSC_LIB "/System/Library/Frameworks/PCSC.framework/Versions/Current/PCSC"
#define APP_NAME "Georgian ID Card"

static void alert(const char *title, const char *msg) {
    CFStringRef t = CFStringCreateWithCString(NULL, title, kCFStringEncodingUTF8);
    CFStringRef m = CFStringCreateWithCString(NULL, msg, kCFStringEncodingUTF8);
    CFOptionFlags resp;
    CFUserNotificationDisplayAlert(0, kCFUserNotificationStopAlertLevel, NULL, NULL, NULL,
                                   t, m, NULL, NULL, NULL, &resp);
    CFRelease(t);
    CFRelease(m);
    fprintf(stderr, "%s: %s\n", title, msg);
}

int main(int argc, char *argv[]) {
    char res[PATH_MAX] = {0};

    CFBundleRef bundle = CFBundleGetMainBundle();
    CFURLRef url = bundle ? CFBundleCopyResourcesDirectoryURL(bundle) : NULL;
    if (url) {
        CFURLRef abs = CFURLCopyAbsoluteURL(url);
        CFURLGetFileSystemRepresentation(abs, true, (UInt8 *)res, sizeof(res));
        CFRelease(abs);
        CFRelease(url);
    }
    if (res[0] == '\0' || chdir(res) != 0) {
        alert("ERROR", "Could not locate application resources");
        return 1;
    }

    const char *java = "jre/bin/java";
    if (access(java, X_OK) != 0) {
        alert("ERROR", "Could not find java executable");
        return 1;
    }

    const char *fixed[] = {
        java,
        "-Dsun.security.smartcardio.library=" PCSC_LIB,
        "-Xdock:name=" APP_NAME,
        "-Xdock:icon=AppIcon.icns",
        "--add-exports=java.desktop/com.apple.eawt=ALL-UNNAMED",
        "-cp", "org.eclipse.osgi.jar:geoeid-unitool.jar",
        "ge.id.card.unitool_container.Main",
    };
    size_t nfixed = sizeof(fixed) / sizeof(fixed[0]);

    char **args = calloc(nfixed + (size_t)argc + 1, sizeof(char *));
    if (!args) return 1;
    size_t n = 0;
    for (size_t i = 0; i < nfixed; i++) args[n++] = (char *)fixed[i];
    for (int i = 0; i < argc; i++) {           /* argv[0] included, like the original */
        if (strncmp(argv[i], "-psn_", 5) == 0) continue;
        args[n++] = argv[i];
    }
    args[n] = NULL;

    execv(java, args);

    char buf[PATH_MAX + 64];
    snprintf(buf, sizeof(buf), "Failed to start %s/%s", res, java);
    alert("ERROR", buf);
    return 1;
}
