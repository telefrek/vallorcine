package scratch;

import jlsm.core.model.Entry;
import jlsm.core.model.SequenceNumber;
import jlsm.wal.local.LocalWriteAheadLog;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.BenchmarkMode;
import org.openjdk.jmh.annotations.Fork;
import org.openjdk.jmh.annotations.Measurement;
import org.openjdk.jmh.annotations.Mode;
import org.openjdk.jmh.annotations.OutputTimeUnit;
import org.openjdk.jmh.annotations.Param;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.Setup;
import org.openjdk.jmh.annotations.State;
import org.openjdk.jmh.annotations.TearDown;
import org.openjdk.jmh.annotations.Warmup;
import org.openjdk.jmh.infra.Blackhole;

import java.io.IOException;
import java.lang.foreign.MemorySegment;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.concurrent.TimeUnit;

/**
 * Scratch benchmark: LocalWriteAheadLog append throughput.
 *
 * Hypothesis: per-append cost is dominated by mappedBuffer.force() (fsync),
 * with secondary costs from writeLock contention, WalRecord.encode(),
 * and bufferPool.acquire()/release().
 */
@BenchmarkMode(Mode.Throughput)
@OutputTimeUnit(TimeUnit.SECONDS)
@State(Scope.Benchmark)
@Warmup(iterations = 3, time = 2)
@Measurement(iterations = 5, time = 3)
@Fork(1)
public class WalAppendScratch {

    @Param({"128", "1024"})
    int valueSizeBytes;

    private LocalWriteAheadLog wal;
    private MemorySegment[] keys;
    private MemorySegment value;
    private int keyMask;
    private int opIndex;
    private Path tempDir;

    @Setup(org.openjdk.jmh.annotations.Level.Trial)
    public void setup() throws IOException {
        tempDir = Files.createTempDirectory("wal-bench-");

        int poolSize = 1024;
        keyMask = poolSize - 1;
        keys = new MemorySegment[poolSize];
        for (int i = 0; i < poolSize; i++) {
            keys[i] = MemorySegment.ofArray(
                    String.format("key-%08d", i).getBytes(StandardCharsets.UTF_8));
        }

        byte[] valBytes = new byte[valueSizeBytes];
        java.util.Arrays.fill(valBytes, (byte) 0xAB);
        value = MemorySegment.ofArray(valBytes);

        // Use small segments to trigger rollover faster
        wal = LocalWriteAheadLog.builder()
                .directory(tempDir)
                .segmentSize(4L * 1024 * 1024) // 4 MiB
                .build();

        opIndex = 0;
    }

    @TearDown(org.openjdk.jmh.annotations.Level.Trial)
    public void tearDown() throws IOException {
        if (wal != null) wal.close();
        if (tempDir != null && Files.exists(tempDir)) {
            try (var walk = Files.walk(tempDir)) {
                walk.sorted(Comparator.reverseOrder()).forEach(p -> {
                    try { Files.deleteIfExists(p); } catch (IOException ignored) {}
                });
            }
        }
    }

    /**
     * Single WAL append. Entry has a dummy sequence number that gets
     * replaced by the WAL's internal counter.
     */
    @Benchmark
    public void append(Blackhole bh) throws IOException {
        int idx = opIndex++ & keyMask;
        bh.consume(wal.append(new Entry.Put(keys[idx], value, SequenceNumber.ZERO)));
    }
}
