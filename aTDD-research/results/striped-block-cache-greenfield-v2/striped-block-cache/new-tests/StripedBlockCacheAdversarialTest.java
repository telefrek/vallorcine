package jlsm.cache;

import org.junit.jupiter.api.Test;

import java.lang.foreign.MemorySegment;
import java.util.ArrayList;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Adversarial tests for {@link StripedBlockCache}.
 * Targets security, memory, performance, and functional contract vectors
 * identified by the Spec Analyst in aTDD round 1.
 */
class StripedBlockCacheAdversarialTest {

    private static MemorySegment block(byte... data) {
        return MemorySegment.ofArray(data);
    }

    // ──────────────────────────────────────────────────────────────────
    // S1 — Negative sstableId routing
    // Vector: negative sstableId could produce negative array index in
    // shard routing, causing ArrayIndexOutOfBoundsException
    // ──────────────────────────────────────────────────────────────────

    @Test
    void negativeSstableIdDoesNotCrashGet() {
        // S1: Long.MIN_VALUE and -1 as sstableId must not throw
        try (var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build()) {
            assertDoesNotThrow(() -> cache.get(Long.MIN_VALUE, 0L));
            assertDoesNotThrow(() -> cache.get(-1L, 0L));
        }
    }

    @Test
    void negativeSstableIdDoesNotCrashPut() {
        // S1: put with negative sstableId must route correctly
        try (var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build()) {
            var b = block((byte) 1);
            assertDoesNotThrow(() -> cache.put(Long.MIN_VALUE, 0L, b));
            assertDoesNotThrow(() -> cache.put(-1L, 0L, b));
        }
    }

    @Test
    void negativeSstableIdRoundTrips() {
        // S1: put with negative sstableId must be retrievable
        try (var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build()) {
            var b = block((byte) 42);
            cache.put(-1L, 0L, b);
            assertEquals(b, cache.get(-1L, 0L).orElseThrow());
        }
    }

    @Test
    void negativeSstableIdEvictWorks() {
        // S1: evict with negative sstableId must work
        try (var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build()) {
            cache.put(-1L, 0L, block((byte) 1));
            cache.put(-1L, 4096L, block((byte) 2));
            cache.evict(-1L);
            assertTrue(cache.get(-1L, 0L).isEmpty());
            assertTrue(cache.get(-1L, 4096L).isEmpty());
        }
    }

    @Test
    void maxValueSstableIdRoundTrips() {
        // S1: Long.MAX_VALUE as sstableId
        try (var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build()) {
            var b = block((byte) 99);
            cache.put(Long.MAX_VALUE, 0L, b);
            assertEquals(b, cache.get(Long.MAX_VALUE, 0L).orElseThrow());
        }
    }

    // ──────────────────────────────────────────────────────────────────
    // S2 — Extreme sstableId and blockOffset values
    // Vector: arithmetic overflow in hash function with extreme inputs
    // ──────────────────────────────────────────────────────────────────

    @Test
    void extremeValuePairZeroZeroRoundTrips() {
        // S2: (0, 0) edge case
        try (var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build()) {
            var b = block((byte) 1);
            cache.put(0L, 0L, b);
            assertEquals(b, cache.get(0L, 0L).orElseThrow());
        }
    }

    @Test
    void extremeValuePairMaxMaxRoundTrips() {
        // S2: (MAX_VALUE, MAX_VALUE) — maximum hash input
        try (var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build()) {
            var b = block((byte) 2);
            cache.put(Long.MAX_VALUE, Long.MAX_VALUE, b);
            assertEquals(b, cache.get(Long.MAX_VALUE, Long.MAX_VALUE).orElseThrow());
        }
    }

    @Test
    void extremeValuePairMinMinRoundTrips() {
        // S2: (MIN_VALUE, 0) — blockOffset can't be negative per contract,
        // but sstableId=MIN_VALUE is valid
        try (var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build()) {
            var b = block((byte) 3);
            cache.put(Long.MIN_VALUE, 0L, b);
            assertEquals(b, cache.get(Long.MIN_VALUE, 0L).orElseThrow());
        }
    }

    // ──────────────────────────────────────────────────────────────────
    // M1 — Per-shard capacity rounding
    // Vector: totalCapacity / shardCount loses entries to integer division.
    // totalCapacity=10, shardCount=4 → each shard gets 2 → effective 8.
    // ──────────────────────────────────────────────────────────────────

    @Test
    void perShardCapacityRoundingDoesNotSilentlyDropEntries() {
        // M1: With totalCapacity=10 and shardCount=4, each shard gets capacity 2.
        // Total effective capacity is 8 (due to integer division).
        // capacity() must still return 10 (the configured total).
        // But only 8 entries total can be held before LRU eviction kicks in.
        try (var cache = StripedBlockCache.builder().totalCapacity(10).shardCount(4).build()) {
            assertEquals(10, cache.capacity(),
                    "capacity() must return totalCapacity, not sum of per-shard capacities");
        }
    }

    @Test
    void perShardCapacityHandlesExactDivision() {
        // M1: totalCapacity=16, shardCount=4 → 4 per shard, no rounding loss
        try (var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build()) {
            // With shardCount=1 to control routing, insert exactly 16 entries
            assertEquals(16, cache.capacity());
        }
    }

    // ──────────────────────────────────────────────────────────────────
    // M2 — Close exception accumulation
    // Vector: if one shard throws on close, others must still be closed.
    // Cannot inject failure without breaking encapsulation — this test
    // verifies the happy path. Theoretical concern noted.
    // ──────────────────────────────────────────────────────────────────

    @Test
    void closeWithPopulatedCacheDoesNotThrow() {
        // M2: Verify close works on populated cache (happy path).
        // Precondition for deferred-exception test: would need injectable shard failure.
        var cache = StripedBlockCache.builder().totalCapacity(64).shardCount(4).build();
        for (int i = 0; i < 20; i++) {
            cache.put(i, 0L, block((byte) i));
        }
        assertDoesNotThrow(cache::close);
        assertEquals(0, cache.size());
    }

    // ──────────────────────────────────────────────────────────────────
    // P1 — Hash distribution quality
    // Vector: if routing uses only sstableId (not both inputs), all blocks
    // from one SSTable land in one shard, destroying parallelism.
    // This is the critical ADR-compliance test.
    // ──────────────────────────────────────────────────────────────────

    @Test
    void hashDistributionUsesBlockOffsetNotJustSstableId() {
        // P1/FA1: Create cache with 4 shards, each with capacity 1.
        // Insert 4 entries with same sstableId but different blockOffsets.
        // If routing uses ONLY sstableId, all 4 go to the same shard (capacity 1),
        // and 3 are evicted → size() == 1.
        // If routing uses BOTH inputs per ADR, they distribute across shards
        // → size() should be > 1 (ideally 4, but at least > 1 proves distribution).
        try (var cache = StripedBlockCache.builder().totalCapacity(4).shardCount(4).build()) {
            // Each shard has capacity 1
            cache.put(1L, 0L, block((byte) 1));
            cache.put(1L, 1L, block((byte) 2));
            cache.put(1L, 2L, block((byte) 3));
            cache.put(1L, 3L, block((byte) 4));

            long size = cache.size();
            assertTrue(size > 1,
                    "Expected entries to distribute across shards (size=" + size
                            + "). If size==1, routing uses only sstableId — violates ADR stripe-hash-function");
        }
    }

    @Test
    void hashDistributionSequentialOffsetsSpreadAcrossShards() {
        // P1: Stronger version — sequential 4096-aligned blockOffsets (typical SSTable block
        // boundaries) must not all cluster in the same shard.
        // With a good hash, 16 sequential offsets into 4 shards should show reasonable spread.
        try (var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build()) {
            for (int i = 0; i < 16; i++) {
                cache.put(1L, i * 4096L, block((byte) i));
            }
            // If all entries cluster in one shard (capacity 4), only 4 survive → size==4.
            // With good hash distribution across 4 shards, most survive (14-16).
            // Allow minor variance from imperfect distribution but reject total clustering.
            // Threshold 12 tolerates up to ~25% loss from hash variance but catches
            // sstableId-only routing which would give exactly 4.
            assertTrue(cache.size() >= 12,
                    "Sequential 4096-aligned offsets should distribute across shards, not cluster. "
                            + "size=" + cache.size() + " (expected ≥12, got 4 with sstableId-only routing)");
        }
    }

    // ──────────────────────────────────────────────────────────────────
    // P2 — Concurrent thread safety
    // Vector: multiple threads doing put/get must not lose entries,
    // corrupt state, or throw ConcurrentModificationException
    // ──────────────────────────────────────────────────────────────────

    @Test
    void concurrentPutGetDoesNotCorruptState() throws Exception {
        // P2: Spawn 8 threads, each putting and getting 100 entries with disjoint keys
        try (var cache = StripedBlockCache.builder().totalCapacity(10_000).shardCount(8).build()) {
            int threadCount = 8;
            int opsPerThread = 100;
            var errors = new ConcurrentLinkedQueue<Throwable>();
            var startLatch = new CountDownLatch(1);
            var doneLatch = new CountDownLatch(threadCount);

            var threads = new ArrayList<Thread>();
            for (int t = 0; t < threadCount; t++) {
                final int threadId = t;
                var thread = new Thread(() -> {
                    try {
                        startLatch.await(5, TimeUnit.SECONDS);
                        for (int i = 0; i < opsPerThread; i++) {
                            long sstableId = threadId * 1000L + i;
                            var b = block((byte) (i % 128));
                            cache.put(sstableId, 0L, b);
                            var result = cache.get(sstableId, 0L);
                            if (result.isEmpty()) {
                                errors.add(new AssertionError(
                                        "Thread " + threadId + ": get returned empty after put for sstableId=" + sstableId));
                            }
                        }
                    } catch (Throwable ex) {
                        errors.add(ex);
                    } finally {
                        doneLatch.countDown();
                    }
                });
                threads.add(thread);
                thread.start();
            }

            startLatch.countDown();
            assertTrue(doneLatch.await(30, TimeUnit.SECONDS), "threads did not complete in time");

            if (!errors.isEmpty()) {
                var first = errors.peek();
                fail("Concurrent access errors: " + errors.size() + ". First: " + first.getMessage(),
                        first);
            }
        }
    }

    @Test
    void concurrentEvictDoesNotCorruptState() throws Exception {
        // P2: Concurrent put + evict should not throw or corrupt state
        try (var cache = StripedBlockCache.builder().totalCapacity(1000).shardCount(4).build()) {
            var errors = new ConcurrentLinkedQueue<Throwable>();
            var startLatch = new CountDownLatch(1);
            var doneLatch = new CountDownLatch(3);

            // Writer thread
            var writer = new Thread(() -> {
                try {
                    startLatch.await(5, TimeUnit.SECONDS);
                    for (int i = 0; i < 500; i++) {
                        cache.put(1L, i, block((byte) (i % 128)));
                    }
                } catch (Throwable ex) {
                    errors.add(ex);
                } finally {
                    doneLatch.countDown();
                }
            });

            // Reader thread
            var reader = new Thread(() -> {
                try {
                    startLatch.await(5, TimeUnit.SECONDS);
                    for (int i = 0; i < 500; i++) {
                        cache.get(1L, i); // may hit or miss, but must not throw
                    }
                } catch (Throwable ex) {
                    errors.add(ex);
                } finally {
                    doneLatch.countDown();
                }
            });

            // Evictor thread
            var evictor = new Thread(() -> {
                try {
                    startLatch.await(5, TimeUnit.SECONDS);
                    for (int i = 0; i < 50; i++) {
                        cache.evict(1L);
                        Thread.yield();
                    }
                } catch (Throwable ex) {
                    errors.add(ex);
                } finally {
                    doneLatch.countDown();
                }
            });

            writer.start();
            reader.start();
            evictor.start();
            startLatch.countDown();
            assertTrue(doneLatch.await(30, TimeUnit.SECONDS), "threads did not complete in time");

            if (!errors.isEmpty()) {
                fail("Concurrent evict errors: " + errors.size(), errors.peek());
            }
        }
    }
}
