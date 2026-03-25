package jlsm.cache;

import org.junit.jupiter.api.Test;

import java.lang.foreign.MemorySegment;
import java.util.ArrayList;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Adversarial tests for {@link StripedBlockCache}. Each test targets a specific attack vector from
 * the Spec Analyst's analysis.
 */
class StripedBlockCacheAdversarialTest {

    // --- Functional vectors ---

    // Vector: [F3] Routing consistency — put and get must route to the same shard
    @Test
    void routingIsConsistentAcrossManyIds() {
        try (var cache = StripedBlockCache.builder().totalCapacity(256).shardCount(4).build()) {
            // Insert entries with a range of sstableIds and verify each can be retrieved
            for (long id = 0; id < 100; id++) {
                var block = MemorySegment.ofArray(new byte[]{ (byte) id });
                cache.put(id, 0L, block);
            }
            for (long id = 0; id < 100; id++) {
                var result = cache.get(id, 0L);
                assertTrue(result.isPresent(), "Entry for sstableId=" + id
                        + " should be retrievable (routing consistency)");
            }
        }
    }

    // Vector: [F4] Evict scope — evict must remove all blocks for the given sstableId
    @Test
    void evictRemovesAllBlocksForSstableViaCorrectRouting() {
        try (var cache = StripedBlockCache.builder().totalCapacity(64).shardCount(4).build()) {
            // Insert multiple blocks for the same sstableId
            for (long offset = 0; offset < 10; offset++) {
                cache.put(7L, offset, MemorySegment.ofArray(new byte[]{ (byte) offset }));
            }
            cache.evict(7L);
            for (long offset = 0; offset < 10; offset++) {
                assertTrue(cache.get(7L, offset).isEmpty(),
                        "Block at offset " + offset + " should be evicted");
            }
        }
    }

    // Vector: [F6] Capacity reports totalCapacity, not sum of shard capacities
    @Test
    void capacityReturnsTotalNotSumOfShards() {
        // totalCapacity=10, shardCount=4 → each shard gets 2 (int div) → sum is 8
        // but capacity() must return 10
        try (var cache = StripedBlockCache.builder().totalCapacity(10).shardCount(4).build()) {
            assertEquals(10, cache.capacity(),
                    "capacity() must return totalCapacity, not sum of shard capacities");
        }
    }

    // Vector: [F10] Per-shard LRU eviction — fill one shard beyond its capacity
    @Test
    void perShardLruEvictionOccurs() {
        int shardCount = 4;
        long totalCapacity = 8; // 2 per shard
        try (var cache = StripedBlockCache.builder().totalCapacity(totalCapacity)
                .shardCount(shardCount).build()) {
            // All these sstableIds route to the same shard: 0, 4, 8, ... (id & 3 == 0)
            // Shard 0 has capacity 2, so inserting a 3rd entry should evict the LRU
            long id0 = 0; // routes to shard 0
            long id4 = 4; // routes to shard 0
            long id8 = 8; // routes to shard 0

            cache.put(id0, 0L, MemorySegment.ofArray(new byte[]{ 1 }));
            cache.put(id4, 0L, MemorySegment.ofArray(new byte[]{ 2 }));
            // Shard 0 is now full (2 entries)
            cache.put(id8, 0L, MemorySegment.ofArray(new byte[]{ 3 }));
            // LRU entry (id0) should be evicted from shard 0
            assertTrue(cache.get(id0, 0L).isEmpty(),
                    "LRU entry in shard should be evicted when shard capacity is exceeded");
            assertTrue(cache.get(id4, 0L).isPresent(), "More recent entry should survive eviction");
            assertTrue(cache.get(id8, 0L).isPresent(), "Newest entry should survive eviction");
        }
    }

    // --- Security / validation vectors ---

    // Vector: [S1] Negative blockOffset in get
    @Test
    void getNegativeBlockOffsetThrows() {
        try (var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build()) {
            assertThrows(IllegalArgumentException.class, () -> cache.get(1L, -1L));
        }
    }

    // Vector: [S1] Negative blockOffset in put
    @Test
    void putNegativeBlockOffsetThrows() {
        try (var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build()) {
            assertThrows(IllegalArgumentException.class,
                    () -> cache.put(1L, -1L, MemorySegment.ofArray(new byte[]{ 1 })));
        }
    }

    // Vector: [S2] Null block in put
    @Test
    void putNullBlockThrows() {
        try (var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build()) {
            assertThrows(NullPointerException.class, () -> cache.put(1L, 0L, null));
        }
    }

    // Vector: [S3] Extreme sstableId: Long.MIN_VALUE
    // The bitmask (sstableId & (shardCount - 1)) must produce a valid non-negative index.
    // Long.MIN_VALUE = 0x8000000000000000L. With shardCount=4, mask=3:
    // Long.MIN_VALUE & 3 = 0 → valid. But if the implementation casts before masking,
    // or uses modulo instead of bitmask, it could produce a negative index.
    @Test
    void routingHandlesLongMinValue() {
        try (var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build()) {
            var block = MemorySegment.ofArray(new byte[]{ 1 });
            assertDoesNotThrow(() -> cache.put(Long.MIN_VALUE, 0L, block));
            assertTrue(cache.get(Long.MIN_VALUE, 0L).isPresent());
        }
    }

    // Vector: [S3] Extreme sstableId: Long.MAX_VALUE
    @Test
    void routingHandlesLongMaxValue() {
        try (var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build()) {
            var block = MemorySegment.ofArray(new byte[]{ 1 });
            assertDoesNotThrow(() -> cache.put(Long.MAX_VALUE, 0L, block));
            assertTrue(cache.get(Long.MAX_VALUE, 0L).isPresent());
        }
    }

    // Vector: [S3] Extreme sstableId: negative (-1)
    @Test
    void routingHandlesNegativeOne() {
        try (var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build()) {
            var block = MemorySegment.ofArray(new byte[]{ 1 });
            assertDoesNotThrow(() -> cache.put(-1L, 0L, block));
            assertTrue(cache.get(-1L, 0L).isPresent());
        }
    }

    // Vector: [S3] Extreme sstableId: zero
    @Test
    void routingHandlesZero() {
        try (var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build()) {
            var block = MemorySegment.ofArray(new byte[]{ 1 });
            cache.put(0L, 0L, block);
            assertTrue(cache.get(0L, 0L).isPresent());
        }
    }

    // --- Memory / resource vectors ---

    // Vector: [M1] Close deferred-exception pattern — all shards must be closed
    @Test
    void closeEmptiesAllShards() {
        var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build();
        // Put entries in multiple shards
        cache.put(0L, 0L, MemorySegment.ofArray(new byte[]{ 1 })); // shard 0
        cache.put(1L, 0L, MemorySegment.ofArray(new byte[]{ 2 })); // shard 1
        cache.put(2L, 0L, MemorySegment.ofArray(new byte[]{ 3 })); // shard 2
        cache.put(3L, 0L, MemorySegment.ofArray(new byte[]{ 4 })); // shard 3
        assertEquals(4, cache.size());
        cache.close();
        // After close, size should be 0 — all shards were closed/cleared
        assertEquals(0, cache.size(),
                "All shards must be closed/cleared — deferred exception pattern must not skip shards");
    }

    // Vector: [M2] Capacity loss from integer division
    @Test
    void integerDivisionCapacityLoss() {
        // totalCapacity=7, shardCount=4 → each shard gets 1 (7/4=1)
        // Actual usable capacity = 4 (1 per shard * 4 shards)
        int shardCount = 4;
        try (var cache = StripedBlockCache.builder().totalCapacity(7).shardCount(shardCount)
                .build()) {
            // capacity() still reports 7
            assertEquals(7, cache.capacity());

            // Fill each shard with 1 entry each (ids 0,1,2,3 route to different shards)
            for (long id = 0; id < shardCount; id++) {
                cache.put(id, 0L, MemorySegment.ofArray(new byte[]{ (byte) id }));
            }
            assertEquals(4, cache.size());

            // Adding a 2nd entry to any shard should evict the first
            // (each shard capacity is only 1)
            cache.put(0L, 1L, MemorySegment.ofArray(new byte[]{ 99 }));
            // The original entry (0, 0) should be evicted within shard 0
            assertTrue(cache.get(0L, 1L).isPresent());
            // Size should still be 4 (eviction within shard 0)
            assertEquals(4, cache.size(),
                    "Size should reflect shard-level eviction, not exceed sum of shard capacities");
        }
    }

    // --- Performance / concurrency vectors ---

    // Vector: [P1] size() under concurrent modification — must not throw or deadlock
    @Test
    void sizeUnderConcurrentModification() throws Exception {
        try (var cache = StripedBlockCache.builder().totalCapacity(256).shardCount(4).build()) {
            int threadCount = 4;
            int opsPerThread = 500;
            var barrier = new CyclicBarrier(threadCount + 1);

            ExecutorService exec = Executors.newFixedThreadPool(threadCount + 1);
            var futures = new ArrayList<Future<?>>();

            // Writer threads
            for (int t = 0; t < threadCount; t++) {
                final int threadId = t;
                futures.add(exec.submit(() -> {
                    try {
                        barrier.await(5, TimeUnit.SECONDS);
                    } catch (Exception e) {
                        throw new RuntimeException(e);
                    }
                    for (int i = 0; i < opsPerThread; i++) {
                        long id = threadId * 1000L + i;
                        cache.put(id, 0L, MemorySegment.ofArray(new byte[]{ 1 }));
                        if (i % 3 == 0) {
                            cache.evict(id);
                        }
                    }
                }));
            }

            // Reader thread calling size() repeatedly
            futures.add(exec.submit(() -> {
                try {
                    barrier.await(5, TimeUnit.SECONDS);
                } catch (Exception e) {
                    throw new RuntimeException(e);
                }
                for (int i = 0; i < opsPerThread; i++) {
                    long s = cache.size();
                    assertTrue(s >= 0, "size() must be non-negative, got: " + s);
                }
            }));

            for (var f : futures) {
                f.get(10, TimeUnit.SECONDS);
            }
            exec.shutdown();
            assertTrue(exec.awaitTermination(5, TimeUnit.SECONDS));
        }
    }

    // Vector: [P3] Concurrent put/get to different shards — no interference
    @Test
    void concurrentAccessToDifferentShardsDoesNotInterfere() throws Exception {
        try (var cache = StripedBlockCache.builder().totalCapacity(256).shardCount(4).build()) {
            int threadCount = 4;
            int opsPerThread = 200;
            var barrier = new CyclicBarrier(threadCount);

            ExecutorService exec = Executors.newFixedThreadPool(threadCount);
            var futures = new ArrayList<Future<?>>();

            for (int t = 0; t < threadCount; t++) {
                final long baseId = t; // routes to shard t (baseId & 3 == t)
                futures.add(exec.submit(() -> {
                    try {
                        barrier.await(5, TimeUnit.SECONDS);
                    } catch (Exception e) {
                        throw new RuntimeException(e);
                    }
                    for (int i = 0; i < opsPerThread; i++) {
                        // Use sstableIds that all route to the same shard for this thread
                        long id = baseId + (long) i * 4; // e.g., 0,4,8,12,... for shard 0
                        var block = MemorySegment.ofArray(new byte[]{ (byte) i });
                        cache.put(id, 0L, block);
                        var result = cache.get(id, 0L);
                        assertTrue(result.isPresent(),
                                "Thread " + baseId + " should see its own entry for id=" + id);
                    }
                }));
            }

            for (var f : futures) {
                f.get(10, TimeUnit.SECONDS);
            }
            exec.shutdown();
            assertTrue(exec.awaitTermination(5, TimeUnit.SECONDS));
        }
    }
}
