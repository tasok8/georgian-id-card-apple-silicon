import java.util.List;
import javax.smartcardio.CardTerminal;
import javax.smartcardio.CardTerminals;
import javax.smartcardio.TerminalFactory;

/**
 * Minimal PC/SC probe for the bundled runtime. Read-only and privacy-safe:
 * it lists reader names and whether a card is present. It never connects to
 * a card, sends APDUs, or reads ATR/certificates/personal data.
 *
 * Run with the app's own runtime (from the app's Contents/Resources dir):
 *   jre/bin/java -Dsun.security.smartcardio.library=/System/Library/Frameworks/PCSC.framework/Versions/Current/PCSC \
 *       PcscProbe.java [waitSeconds]
 */
public class PcscProbe {
    public static void main(String[] args) throws Exception {
        System.out.println("java " + System.getProperty("java.version") + " / " + System.getProperty("os.arch"));
        TerminalFactory f = TerminalFactory.getDefault();
        System.out.println("TerminalFactory: " + f.getType() + " provider=" + f.getProvider().getName());
        if ("None".equals(f.getType())) {
            System.out.println("PC/SC binding FAILED: no PC/SC provider (check -Dsun.security.smartcardio.library)");
            System.exit(1);
        }
        CardTerminals terms = f.terminals();
        int wait = args.length > 0 ? Integer.parseInt(args[0]) : 0;
        long end = System.currentTimeMillis() + wait * 1000L;
        do {
            List<CardTerminal> list;
            try {
                list = terms.list();
            } catch (Exception e) {
                // macOS returns SCARD_E_NO_READERS_AVAILABLE / NO_SERVICE when no reader is attached
                System.out.println("readers: none (" + rootMsg(e) + ")");
                list = List.of();
            }
            for (CardTerminal t : list) {
                System.out.println("reader: \"" + t.getName() + "\"  cardPresent=" + t.isCardPresent());
            }
            if (!list.isEmpty() || System.currentTimeMillis() >= end) break;
            Thread.sleep(1000);
        } while (true);
        System.out.println("PC/SC binding OK");
    }

    private static String rootMsg(Throwable e) {
        while (e.getCause() != null) e = e.getCause();
        return e.getClass().getSimpleName() + ": " + e.getMessage();
    }
}
