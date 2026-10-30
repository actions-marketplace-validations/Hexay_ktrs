import java.io.OutputStream;
import java.io.PrintStream;
import java.lang.reflect.InvocationTargetException;
import java.security.Permission;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/**
 * Warm-JVM baseline: runs a CLI's main() repeatedly in one JVM, so later iterations have no startup and a trained JIT.
 *
 *   java -Djava.security.manager=allow -cp JAR tools/bench/JvmWarm.java ITERATIONS TAIL MAIN_CLASS ARGS...
 *
 * Prints every iteration's seconds and the median of the last TAIL. See research/37-native-image-bench.md.
 */
public class JvmWarm {
  private static final class Exit extends SecurityException {}
  private static volatile boolean looping = true;

  public static void main(String[] argv) throws Exception {
    int iterations = Integer.parseInt(argv[0]);
    int tail = Integer.parseInt(argv[1]);
    var entry = Class.forName(argv[2]).getMethod("main", String[].class);
    String[] args = Arrays.copyOfRange(argv, 3, argv.length);

    // Gotcha: both CLIs end in System.exit, which would kill the loop.
    System.setSecurityManager(new SecurityManager() {
      @Override public void checkExit(int status) { if (looping) throw new Exit(); }
      @Override public void checkPermission(Permission perm) {}
    });
    PrintStream report = System.out;
    // Output size per iteration is the proof a fast iteration still did the work.
    long[] written = {0};
    PrintStream sink = new PrintStream(new OutputStream() {
      @Override public void write(int b) { written[0]++; }
      @Override public void write(byte[] b, int off, int len) { written[0] += len; }
    }, true);
    System.setOut(sink);
    System.setErr(sink);

    List<Double> seconds = new ArrayList<>();
    for (int i = 0; i < iterations; i++) {
      long start = System.nanoTime();
      try {
        entry.invoke(null, (Object) args);
      } catch (InvocationTargetException e) {
        if (!(e.getCause() instanceof Exit)) throw e;
      }
      double s = (System.nanoTime() - start) / 1e9;
      seconds.add(s);
      report.printf("%d\t%.3f s\t%d bytes%n", i + 1, s, written[0]);
      written[0] = 0;
    }
    List<Double> last = new ArrayList<>(seconds.subList(iterations - tail, iterations));
    Collections.sort(last);
    report.printf("first %.3f s, median of last %d: %.3f s%n", seconds.get(0), tail, last.get(tail / 2));
    report.flush();
    looping = false;
    Runtime.getRuntime().halt(0);
  }
}
