package scratch;

import jlsm.bloom.blocked.BlockedBloomFilter;
import jlsm.core.model.Entry;
import jlsm.core.model.SequenceNumber;
import jlsm.sstable.TrieSSTableReader;
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
import org.openjdk.jmh.infra.Blackhole;

import java.io.IOException;
import java.lang.foreign.MemorySegment;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.Iterator;
import java.util.concurrent.TimeUnit;

/**
 * Scratch benchmark: TrieSSTableReader point lookup and scan cost.
 *
 * Hypothesis: get() cost is dominated by bloom filter check + KeyIndex trie
 * lookup + readDataAt arraycopy. Scan cost by DataRegionIterator block parsing.
 */
@BenchmarkMode(Mode.Throughput)
@OutputTimeUnit(TimeUnit.SECONDS)
@State(Scope.Benchmark)
@Warmup(iterations = 3, time = 2)
@Measurement(iterations = 5, time = 2)
@Fork(2)
public class SSTableReadScratch {

    @Param({"10000"})
    int entryCount;

    private TrieSSTableReader reader;
    private MemorySegment[] hitKeys;
    private MemorySegment[] missKeys;
    private int keyMask;
    private int opIndex;
    private Path tempDir;

    @Setup(org.openjdk.jmh.annotations.Level.Trial)
    public void setup() throws IOException {
        tempDir = Files.createTempDirectory("sstable-read-bench-");
        Path sstPath = tempDir.resolve("test.sst");

        int poolSize = Integer.highestOneBit(entryCount);
        if (poolSize < entryCount) poolSize <<= 1;
        keyMask = poolSize - 1;

        hitKeys = new MemorySegment[poolSize];
        missKeys = new MemorySegment[poolSize];

        // Write the SSTable
        try (TrieSSTableWriter writer = new TrieSSTableWriter(1,
                new jlsm.core.model.Level(0), sstPath)) {
            byte[] valBytes = new byte[128];
            java.util.Arrays.fill(valBytes, (byte) 0xAB);
            MemorySegment value = MemorySegment.ofArray(valBytes);

            for (int i = 0; i < entryCount; i++) {
                String keyStr = String.format("key-%08d", i);
                byte[] kb = keyStr.getBytes(StandardCharsets.UTF_8);
                hitKeys[i] = MemorySegment.ofArray(kb);
                missKeys[i] = MemorySegment.ofArray(
                        String.format("zzz-%08d", i).getBytes(StandardCharsets.UTF_8));
                writer.append(new Entry.Put(MemorySegment.ofArray(kb), value,
                        new SequenceNumber(i + 1)));
            }
            // Fill remaining pool slots
            for (int i = entryCount; i < poolSize; i++) {
                hitKeys[i] = hitKeys[i % entryCount];
                missKeys[i] = missKeys[i % entryCount];
            }
            writer.finish();
        }

        reader = TrieSSTableReader.open(sstPath, BlockedBloomFilter.deserializer());
        opIndex = 0;
    }

    @TearDown(org.openjdk.jmh.annotations.Level.Trial)
    public void tearDown() throws IOException {
        if (reader != null) reader.close();
        if (tempDir != null && Files.exists(tempDir)) {
            try (var walk = Files.walk(tempDir)) {
                walk.sorted(Comparator.reverseOrder()).forEach(p -> {
                    try { Files.deleteIfExists(p); } catch (IOException ignored) {}
                });
            }
        }
    }

    @Benchmark
    public void getHit(Blackhole bh) throws IOException {
        bh.consume(reader.get(hitKeys[opIndex++ & keyMask]));
    }

    @Benchmark
    public void getMiss(Blackhole bh) throws IOException {
        bh.consume(reader.get(missKeys[opIndex++ & keyMask]));
    }

    @Benchmark
    public void fullScan(Blackhole bh) throws IOException {
        Iterator<Entry> it = reader.scan();
        while (it.hasNext()) {
            bh.consume(it.next());
        }
    }
}
