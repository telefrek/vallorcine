package scratch;

import jlsm.core.model.Entry;
import jlsm.core.model.Level;
import jlsm.core.model.SequenceNumber;
import jlsm.sstable.TrieSSTableWriter;
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
import org.openjdk.jmh.annotations.Level;

import java.io.IOException;
import java.lang.foreign.MemorySegment;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.concurrent.TimeUnit;

/**
 * Scratch benchmark: TrieSSTableWriter append + finish cost.
 *
 * Hypothesis: per-entry append cost is dominated by redundant byte array
 * allocations (key.toArray called in append AND in EntryCodec.encode,
 * plus keyBytes.clone for stats). The finish() cost includes yet another
 * toArray per key in writeKeyIndex, plus bloom filter construction.
 *
 * Measures the full write-an-SSTable cycle: create writer, append N entries,
 * finish, close. Reports ops/s where one op = one complete SSTable write.
 */
@BenchmarkMode(Mode.Throughput)
@OutputTimeUnit(TimeUnit.SECONDS)
@State(Scope.Benchmark)
@Warmup(iterations = 3, time = 2)
@Measurement(iterations = 5, time = 3)
@Fork(1)
public class SSTableWriteScratch {

    @Param({"1000", "10000"})
    int entryCount;

    @Param({"128"})
    int valueSizeBytes;

    private Entry.Put[] entries;
    private Path tempDir;
    private int fileCounter;

    @Setup(Level.Trial)
    public void setup() throws IOException {
        tempDir = Files.createTempDirectory("sstable-write-bench-");
        fileCounter = 0;

        entries = new Entry.Put[entryCount];
        byte[] valBytes = new byte[valueSizeBytes];
        java.util.Arrays.fill(valBytes, (byte) 0xAB);
        MemorySegment value = MemorySegment.ofArray(valBytes);

        for (int i = 0; i < entryCount; i++) {
            String keyStr = String.format("key-%08d", i);
            MemorySegment key = MemorySegment.ofArray(keyStr.getBytes(StandardCharsets.UTF_8));
            entries[i] = new Entry.Put(key, value, new SequenceNumber(i + 1));
        }
    }

    @TearDown(Level.Trial)
    public void tearDown() throws IOException {
        if (tempDir != null && Files.exists(tempDir)) {
            try (var walk = Files.walk(tempDir)) {
                walk.sorted(Comparator.reverseOrder()).forEach(p -> {
                    try {
                        Files.deleteIfExists(p);
                    } catch (IOException ignored) {
                    }
                });
            }
        }
    }

    /**
     * Full SSTable write cycle: open writer, append all entries, finish, close.
     * One op = one complete SSTable file written.
     */
    @Benchmark
    public void writeSSTable() throws IOException {
        Path file = tempDir.resolve("sst-" + (fileCounter++) + ".sst");
        try (TrieSSTableWriter writer = new TrieSSTableWriter(fileCounter,
                new jlsm.core.model.Level(0), file)) {
            for (Entry.Put entry : entries) {
                writer.append(entry);
            }
            writer.finish();
        }
        Files.deleteIfExists(file);
    }
}
