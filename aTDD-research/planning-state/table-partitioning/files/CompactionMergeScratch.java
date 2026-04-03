package scratch;

import jlsm.bloom.blocked.BlockedBloomFilter;
import jlsm.compaction.SpookyCompactor;
import jlsm.core.compaction.CompactionTask;
import jlsm.core.model.Entry;
import jlsm.core.model.Level;
import jlsm.core.model.SequenceNumber;
import jlsm.core.sstable.SSTableMetadata;
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

import java.io.IOException;
import java.lang.foreign.MemorySegment;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Scratch benchmark: SpookyCompactor merge cost.
 *
 * Hypothesis: compaction cost is dominated by N-way MergeIterator heap
 * operations (KeyComparator per poll/offer), SSTable read I/O, and
 * SSTable write (including redundant toArray allocations).
 *
 * One op = compact N overlapping SSTables into one output.
 */
@BenchmarkMode(Mode.Throughput)
@OutputTimeUnit(TimeUnit.SECONDS)
@State(Scope.Benchmark)
@Warmup(iterations = 2, time = 5)
@Measurement(iterations = 5, time = 5)
@Fork(1)
public class CompactionMergeScratch {

    @Param({"2", "4"})
    int numSSTables;

    @Param({"5000"})
    int entriesPerSSTable;

    private Path tempDir;
    private SpookyCompactor compactor;
    private List<SSTableMetadata> sourceMetas;
    private AtomicLong idCounter;
    private int runCounter;

    @Setup(org.openjdk.jmh.annotations.Level.Trial)
    public void setup() throws IOException {
        tempDir = Files.createTempDirectory("compaction-bench-");
        idCounter = new AtomicLong(100);
        runCounter = 0;

        compactor = SpookyCompactor.builder()
                .idSupplier(idCounter::getAndIncrement)
                .pathFn((id, level) -> tempDir.resolve("out-" + id + "-L" + level.index() + ".sst"))
                .targetBottomFileSizeBytes(256L * 1024 * 1024)
                .build();

        // Create overlapping SSTables at L0
        sourceMetas = new ArrayList<>();
        byte[] valBytes = new byte[128];
        java.util.Arrays.fill(valBytes, (byte) 0xAB);
        MemorySegment value = MemorySegment.ofArray(valBytes);

        for (int s = 0; s < numSSTables; s++) {
            long id = s + 1;
            Path sstPath = tempDir.resolve("src-" + id + ".sst");
            try (TrieSSTableWriter writer = new TrieSSTableWriter(id, Level.L0, sstPath)) {
                for (int i = 0; i < entriesPerSSTable; i++) {
                    // Overlapping key ranges: all SSTables cover same keys,
                    // different sequence numbers
                    String keyStr = String.format("key-%08d", i);
                    MemorySegment key = MemorySegment.ofArray(
                            keyStr.getBytes(StandardCharsets.UTF_8));
                    long seq = (long) s * entriesPerSSTable + i + 1;
                    writer.append(new Entry.Put(key, value, new SequenceNumber(seq)));
                }
                sourceMetas.add(writer.finish());
            }
        }
    }

    @TearDown(org.openjdk.jmh.annotations.Level.Trial)
    public void tearDown() throws IOException {
        if (compactor != null) compactor.close();
        if (tempDir != null && Files.exists(tempDir)) {
            try (var walk = Files.walk(tempDir)) {
                walk.sorted(Comparator.reverseOrder()).forEach(p -> {
                    try { Files.deleteIfExists(p); } catch (IOException ignored) {}
                });
            }
        }
    }

    @Benchmark
    public void compactOverlapping() throws IOException {
        // Build task: all sources → L1
        CompactionTask task = new CompactionTask(
                new ArrayList<>(sourceMetas), Level.L0, new Level(1));

        List<SSTableMetadata> results = compactor.compact(task);

        // Clean up output files so disk doesn't fill
        for (SSTableMetadata meta : results) {
            Files.deleteIfExists(meta.path());
        }
    }
}
