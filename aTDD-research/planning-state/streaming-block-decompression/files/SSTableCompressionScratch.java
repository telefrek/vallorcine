import jlsm.bloom.blocked.BlockedBloomFilter;
import jlsm.core.compression.CompressionCodec;
import jlsm.core.model.Entry;
import jlsm.core.model.Level;
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
import java.util.Arrays;
import java.util.Iterator;
import java.util.Optional;
import java.util.concurrent.TimeUnit;

/**
 * Scratch benchmark: measure SSTable write/read throughput with and without
 * block-level compression (v1 vs v2+Deflate).
 *
 * <p>Compression modes:
 * <ul>
 *   <li>{@code none} — v1 format, no compression</li>
 *   <li>{@code deflate1} — v2 format, Deflate level 1 (speed-optimised)</li>
 *   <li>{@code deflate6} — v2 format, Deflate level 6 (default balance)</li>
 * </ul>
 */
@BenchmarkMode(Mode.Throughput)
@OutputTimeUnit(TimeUnit.SECONDS)
@State(Scope.Benchmark)
@Warmup(iterations = 3, time = 1)
@Measurement(iterations = 5, time = 2)
@Fork(2)
public class SSTableCompressionScratch {

    @Param({"none", "deflate1", "deflate6"})
    String compression;

    @Param({"1000", "10000"})
    int entryCount;

    // Pre-built entries for writing
    private Entry[] entries;
    private MemorySegment[] keys;
    private Path tempDir;

    // Pre-written SSTable for read benchmarks
    private Path readSstPath;
    private long fileSize;

    @Setup(org.openjdk.jmh.annotations.Level.Trial)
    public void setup() throws IOException {
        tempDir = Files.createTempDirectory("jmh-sstable-compression");

        // Build sorted entries with 16-byte keys and 128-byte values
        entries = new Entry[entryCount];
        keys = new MemorySegment[entryCount];
        byte[] valBytes = new byte[128];
        Arrays.fill(valBytes, (byte) 0xAB);
        MemorySegment value = MemorySegment.ofArray(valBytes);

        for (int i = 0; i < entryCount; i++) {
            byte[] keyBytes = String.format("key-%012d", i).getBytes(StandardCharsets.UTF_8);
            keys[i] = MemorySegment.ofArray(keyBytes);
            entries[i] = new Entry.Put(keys[i], value, new SequenceNumber(i + 1));
        }

        // Write a pre-built SSTable for read benchmarks
        readSstPath = tempDir.resolve("read-bench.sst");
        writeSSTable(readSstPath);
        fileSize = Files.size(readSstPath);
    }

    @TearDown(org.openjdk.jmh.annotations.Level.Trial)
    public void tearDown() throws IOException {
        // Clean up temp files
        try (var walk = Files.walk(tempDir)) {
            walk.sorted(java.util.Comparator.reverseOrder())
                .forEach(p -> {
                    try { Files.deleteIfExists(p); } catch (IOException ignored) {}
                });
        }
    }

    // ── Write benchmark ──────────────────────────────────────────────────────

    /**
     * Measures end-to-end SSTable write throughput: create writer, append all
     * entries, finish, close. One op = one complete SSTable written.
     */
    @Benchmark
    public long writeSSTableBench() throws IOException {
        Path path = tempDir.resolve("write-" + Thread.currentThread().getId() + "-" + System.nanoTime() + ".sst");
        long size = writeSSTable(path);
        Files.delete(path);
        return size;
    }

    // ── Read benchmarks (point get) ──────────────────────────────────────────

    private int getIndex = 0;

    /**
     * Measures point-get throughput on a pre-written SSTable.
     * One op = one key lookup (hit).
     */
    @Benchmark
    public void getHit(Blackhole bh) throws IOException {
        int idx = getIndex++ % entryCount;
        try (TrieSSTableReader reader = openReader()) {
            Optional<Entry> result = reader.get(keys[idx]);
            bh.consume(result);
        }
    }

    // ── Read benchmarks (full scan) ──────────────────────────────────────────

    /**
     * Measures full-scan throughput on a pre-written SSTable.
     * One op = iterate all entries.
     */
    @Benchmark
    public void scanAll(Blackhole bh) throws IOException {
        try (TrieSSTableReader reader = openReader()) {
            Iterator<Entry> it = reader.scan();
            while (it.hasNext()) {
                bh.consume(it.next());
            }
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private long writeSSTable(Path path) throws IOException {
        CompressionCodec codec = resolveCodec();
        try (TrieSSTableWriter writer = new TrieSSTableWriter(
                1L, Level.L0, path,
                n -> new BlockedBloomFilter(n, 0.01),
                codec)) {
            for (Entry entry : entries) {
                writer.append(entry);
            }
            writer.finish();
        }
        return Files.size(path);
    }

    private TrieSSTableReader openReader() throws IOException {
        CompressionCodec codec = resolveCodec();
        if (codec != null) {
            return TrieSSTableReader.open(readSstPath,
                    BlockedBloomFilter.deserializer(), null,
                    CompressionCodec.none(), codec);
        } else {
            return TrieSSTableReader.open(readSstPath,
                    BlockedBloomFilter.deserializer());
        }
    }

    private CompressionCodec resolveCodec() {
        return switch (compression) {
            case "none" -> null;
            case "deflate1" -> CompressionCodec.deflate(1);
            case "deflate6" -> CompressionCodec.deflate(6);
            default -> throw new IllegalArgumentException("unknown compression: " + compression);
        };
    }
}
