package scratch;

import jlsm.core.model.Entry;
import jlsm.core.model.SequenceNumber;
import jlsm.memtable.ConcurrentSkipListMemTable;
import org.openjdk.jmh.annotations.*;
import org.openjdk.jmh.infra.Blackhole;

import java.lang.foreign.MemorySegment;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Scratch benchmark: ConcurrentSkipListMemTable put/get/scan cost.
 *
 * Hypothesis: per-operation cost of put and get is dominated by
 * KeyComparator (MemorySegment.mismatch) and skip list traversal,
 * with secondary GC pressure from CompositeKey/Entry record allocation.
 */
@BenchmarkMode(Mode.Throughput)
@OutputTimeUnit(TimeUnit.SECONDS)
@State(Scope.Benchmark)
public class MemTableScratch {

    /** Number of keys pre-loaded into the MemTable before measurement. */
    @Param({"1000", "10000", "100000"})
    int preloadCount;

    private ConcurrentSkipListMemTable memTable;
    private MemorySegment[] keys;
    private MemorySegment value;
    private AtomicLong seqCounter;
    private int keyMask;

    /** Rolling index for cycling through keys without modulo. */
    private int opIndex;

    @Setup(Level.Trial)
    public void setup() {
        memTable = new ConcurrentSkipListMemTable();
        seqCounter = new AtomicLong(1);

        // Power-of-two key pool for mask-based cycling
        int poolSize = Integer.highestOneBit(preloadCount);
        if (poolSize < preloadCount) {
            poolSize <<= 1;
        }
        keyMask = poolSize - 1;
        keys = new MemorySegment[poolSize];

        for (int i = 0; i < poolSize; i++) {
            keys[i] = MemorySegment.ofArray(
                    String.format("key-%08d", i).getBytes(StandardCharsets.UTF_8));
        }

        // Fixed 128-byte value
        byte[] valBytes = new byte[128];
        java.util.Arrays.fill(valBytes, (byte) 0xAB);
        value = MemorySegment.ofArray(valBytes);

        // Preload the MemTable to the target size
        for (int i = 0; i < preloadCount; i++) {
            long seq = seqCounter.getAndIncrement();
            memTable.apply(new Entry.Put(keys[i & keyMask], value, new SequenceNumber(seq)));
        }

        opIndex = 0;
    }

    /**
     * Measure put throughput into an already-populated MemTable.
     * Each iteration inserts with a new sequence number (simulating real writes).
     */
    @Benchmark
    public void put() {
        int idx = opIndex++ & keyMask;
        long seq = seqCounter.getAndIncrement();
        memTable.apply(new Entry.Put(keys[idx], value, new SequenceNumber(seq)));
    }

    /**
     * Measure point-lookup throughput against an already-populated MemTable.
     * Cycles through keys that are known to exist.
     */
    @Benchmark
    public void getHit(Blackhole bh) {
        int idx = opIndex++ & keyMask;
        bh.consume(memTable.get(keys[idx]));
    }

    /**
     * Measure point-lookup throughput for keys that do NOT exist.
     * Tests the ceiling-miss path in ConcurrentSkipListMap.
     */
    @Benchmark
    public void getMiss(Blackhole bh) {
        // Use a key prefix that sorts after all preloaded keys
        bh.consume(memTable.get(MemorySegment.ofArray(
                String.format("zzz-%08d", opIndex++ & keyMask)
                        .getBytes(StandardCharsets.UTF_8))));
    }
}
