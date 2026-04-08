package jlsm.cache;

import org.junit.jupiter.api.Test;

import java.lang.foreign.MemorySegment;
import java.util.ArrayList;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Adversarial tests for {@link StripedBlockCache} — Round 2. Targets deeper edge cases discovered
 * by analysing the implementation.
 */
class StripedBlockCacheAdversarialRound2Test {

    // --- Functional deeper edge cases ---

    // Vector: [F11] shardCount=1 degenerate case — all entries in one shard
    @Test
    void shardCountOnePutGetEvictWork() {
        try (var cache = StripedBlockCache.builder().totalCapacity(10).shardCount(1).build()) {
            // All sstableIds route to shard 0 (mask = 0, so id & 0 = 0)
            cache.put(1L, 0L, MemorySegment.ofArray(new byte[]{ 1 }));
            cache.put(2L, 0L, MemorySegment.ofArray(new byte[]{ 2 }));
            cache.put(3L, 0L, MemorySegment.ofArray(new byte[]{ 3 }));

            assertEquals(3, cache.size());
            assertTrue(cache.get(1L, 0L).isPresent());
            assertTrue(cache.get(2L, 0L).isPresent());
            assertTrue(cache.get(3L, 0L).isPresent());

            cache.evict(2L);
            assertEquals(2, cache.size());
            assertTrue(cache.get(2L, 0L).isEmpty());
            assertTrue(cache.get(1L, 0L).isPresent());
        }
    }

    // Vector: [F11] shardCount=1 with negative sstableIds
    @Test
    void shardCountOneHandlesNegativeIds() {
        try (var cache = StripedBlockCache.builder().totalCapacity(10).shardCount(1).build()) {
            cache.put(-1L, 0L, MemorySegment.ofArray(new byte[]{ 1 }));
            cache.put(Long.MIN_VALUE, 0L, MemorySegment.ofArray(new byte[]{ 2 }));
            assertTrue(cache.get(-1L, 0L).isPresent());
            assertTrue(cache.get(Long.MIN_VALUE, 0L).isPresent());
        }
    }

    // Vector: [F11] shardCount=1 capacity and LRU eviction
    @Test
    void shardCountOneLruEvictionWorks() {
        try (var cache = StripedBlockCache.builder().totalCapacity(2).shardCount(1).build()) {
            cache.put(1L, 0L, MemorySegment.ofArray(new byte[]{ 1 }));
            cache.put(2L, 0L, MemorySegment.ofArray(new byte[]{ 2 }));
            // Full; insert 3rd → LRU (sstable 1) evicted
            cache.put(3L, 0L, MemorySegment.ofArray(new byte[]{ 3 }));
            assertTrue(cache.get(1L, 0L).isEmpty(), "LRU entry should be evicted");
            assertTrue(cache.get(2L, 0L).isPresent());
            assertTrue(cache.get(3L, 0L).isPresent());
            assertEquals(2, cache.size());
        }
    }

    // Vector: [F12] Builder without totalCapacity must throw
    @Test
    void builderWithoutTotalCapacityThrows() {
        assertThrows(IllegalArgumentException.class,
                () -> StripedBlockCache.builder().shardCount(4).build());
    }

    // Vector: [F12] Builder with only defaults (nothing set) must throw
    @Test
    void builderWithNothingSetThrows() {
        assertThrows(IllegalArgumentException.class, () -> StripedBlockCache.builder().build());
    }

    // Vector: [F13] Concurrent last-write-wins on same key, same shard
    @Test
    void concurrentPutSameKeySameShardLastWriteWins() throws Exception {
        try (var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build()) {
            long sstableId = 0L; // routes to shard 0
            long blockOffset = 0L;
            int threadCount = 4;
            int iterations = 200;
            var barrier = new CyclicBarrier(threadCount);

            ExecutorService exec = Executors.newFixedThreadPool(threadCount);
            var futures = new ArrayList<Future<?>>();

            for (int t = 0; t < threadCount; t++) {
                final byte threadVal = (byte) t;
                futures.add(exec.submit(() -> {
                    try {
                        barrier.await(5, TimeUnit.SECONDS);
                    } catch (Exception e) {
                        throw new RuntimeException(e);
                    }
                    for (int i = 0; i < iterations; i++) {
                        cache.put(sstableId, blockOffset,
                                MemorySegment.ofArray(new byte[]{ threadVal }));
                    }
                }));
            }

            for (var f : futures) {
                f.get(10, TimeUnit.SECONDS);
            }
            exec.shutdown();

            // After all writes complete, exactly one value should be present
            var result = cache.get(sstableId, blockOffset);
            assertTrue(result.isPresent(), "Value must be present after concurrent writes");
            assertEquals(1, cache.size());
        }
    }

    // Vector: [F14] getOrLoad stampede — concurrent miss, loader may run more than once
    @Test
    void getOrLoadStampedeDoesNotCorrupt() throws Exception {
        try (var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build()) {
            long sstableId = 1L;
            long blockOffset = 0L;
            int threadCount = 4;
            var barrier = new CyclicBarrier(threadCount);
            var loadCount = new AtomicInteger(0);
            var block = MemorySegment.ofArray(new byte[]{ 42 });

            ExecutorService exec = Executors.newFixedThreadPool(threadCount);
            var futures = new ArrayList<Future<MemorySegment>>();

            for (int t = 0; t < threadCount; t++) {
                futures.add(exec.submit(() -> {
                    try {
                        barrier.await(5, TimeUnit.SECONDS);
                    } catch (Exception e) {
                        throw new RuntimeException(e);
                    }
                    return cache.getOrLoad(sstableId, blockOffset, () -> {
                        loadCount.incrementAndGet();
                        return block;
                    });
                }));
            }

            for (var f : futures) {
                var result = f.get(10, TimeUnit.SECONDS);
                assertNotNull(result, "getOrLoad must never return null");
                assertEquals(block, result, "All threads must get the same block");
            }
            exec.shutdown();

            // Loader was called at least once (possibly more — not stampede-proof)
            assertTrue(loadCount.get() >= 1, "Loader must be called at least once");
            // Cache must contain exactly one entry
            assertEquals(1, cache.size());
            assertTrue(cache.get(sstableId, blockOffset).isPresent());
        }
    }

    // --- Memory / lifecycle vectors ---

    // Vector: [M3] Sustained eviction pressure on single shard
    @Test
    void sustainedEvictionPressureDoesNotLeak() {
        int shardCount = 4;
        long totalCapacity = 8; // 2 per shard
        try (var cache = StripedBlockCache.builder().totalCapacity(totalCapacity)
                .shardCount(shardCount).build()) {
            // Insert 1000 entries all routing to shard 0 (ids: 0, 4, 8, 12, ...)
            // Shard 0 capacity = 2, so 998 evictions must occur
            for (int i = 0; i < 1000; i++) {
                long id = (long) i * shardCount; // always routes to shard 0
                cache.put(id, 0L, MemorySegment.ofArray(new byte[]{ (byte) i }));
            }

            // Size should reflect bounded cache — shard 0 has at most 2 entries,
            // other shards have 0
            long size = cache.size();
            assertTrue(size <= totalCapacity,
                    "Size must not exceed totalCapacity after sustained eviction, got: " + size);
            assertTrue(size >= 1, "Cache should still hold entries");

            // The last two entries inserted should be present
            long lastId = 999L * shardCount;
            long secondLastId = 998L * shardCount;
            assertTrue(cache.get(lastId, 0L).isPresent(), "Last inserted entry should survive");
            assertTrue(cache.get(secondLastId, 0L).isPresent(),
                    "Second-to-last entry should survive");
        }
    }

    // Vector: [M4] Double close is safe
    @Test
    void doubleCloseDoesNotThrow() {
        var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build();
        cache.put(1L, 0L, MemorySegment.ofArray(new byte[]{ 1 }));
        cache.put(2L, 0L, MemorySegment.ofArray(new byte[]{ 2 }));
        cache.close();
        assertDoesNotThrow(cache::close, "Second close must not throw");
        assertEquals(0, cache.size());
    }

    // --- Performance / concurrency vectors ---

    // Vector: [P4] Mixed operations on same shard under contention
    @Test
    void mixedOpsOnSameShardUnderContention() throws Exception {
        int shardCount = 4;
        long totalCapacity = 16; // 4 per shard
        try (var cache = StripedBlockCache.builder().totalCapacity(totalCapacity)
                .shardCount(shardCount).build()) {
            int threadCount = 4;
            int opsPerThread = 500;
            var barrier = new CyclicBarrier(threadCount);

            ExecutorService exec = Executors.newFixedThreadPool(threadCount);
            var futures = new ArrayList<Future<?>>();

            for (int t = 0; t < threadCount; t++) {
                final int threadId = t;
                futures.add(exec.submit(() -> {
                    try {
                        barrier.await(5, TimeUnit.SECONDS);
                    } catch (Exception e) {
                        throw new RuntimeException(e);
                    }
                    for (int i = 0; i < opsPerThread; i++) {
                        // All ids route to shard 0: id = threadId * 4
                        // (but we vary them to create different keys within shard 0)
                        long id = (long) (threadId * 1000 + i) * shardCount;

                        switch (i % 4) {
                            case 0 ->
                                cache.put(id, 0L, MemorySegment.ofArray(new byte[]{ (byte) i }));
                            case 1 -> cache.get(id, 0L);
                            case 2 -> cache.evict(id);
                            case 3 -> {
                                long s = cache.size();
                                assertTrue(s >= 0, "size() must be non-negative, got: " + s);
                            }
                        }
                    }
                }));
            }

            for (var f : futures) {
                f.get(10, TimeUnit.SECONDS);
            }
            exec.shutdown();
            assertTrue(exec.awaitTermination(5, TimeUnit.SECONDS));

            // After all ops, size must be valid
            long finalSize = cache.size();
            assertTrue(finalSize >= 0 && finalSize <= totalCapacity,
                    "Final size must be in [0, totalCapacity], got: " + finalSize);
        }
    }
}
