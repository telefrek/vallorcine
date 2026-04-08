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
 * Adversarial tests for {@link StripedBlockCache} — Round 3 (final). Targets the deepest remaining
 * vectors including a confirmed capacity overflow bug.
 */
class StripedBlockCacheAdversarialRound3Test {

    // --- HIGH PRIORITY ---

    // Vector: [S7] LruBlockCache capacity overflow — eviction broken for capacity >
    // Integer.MAX_VALUE
    //
    // LruBlockCache accepts long capacity, but LinkedHashMap.size() returns int.
    // The removeEldestEntry callback checks `size() > cap`. When cap > Integer.MAX_VALUE,
    // the int size() (widened to long) can NEVER exceed cap, so eviction never triggers.
    //
    // This is reachable via StripedBlockCache: totalCapacity = Integer.MAX_VALUE + 2,
    // shardCount = 1 → perShard = Integer.MAX_VALUE + 2 → eviction broken.
    //
    // The fix should reject capacity > Integer.MAX_VALUE at validation time,
    // either in LruBlockCache.Builder or in StripedBlockCache.Builder (for perShard).
    @Test
    void capacityExceedingIntMaxBreaksEviction() {
        // This test demonstrates the bug: LruBlockCache with capacity > Integer.MAX_VALUE
        // silently fails to evict. The builder should reject this.
        //
        // We expect IllegalArgumentException from the builder for capacity > Integer.MAX_VALUE
        // (or from StripedBlockCache when perShard would exceed Integer.MAX_VALUE).
        // If the builder does NOT reject it, the cache is silently broken.

        long overflowCapacity = (long) Integer.MAX_VALUE + 1;

        // Direct LruBlockCache: capacity > Integer.MAX_VALUE should be rejected
        assertThrows(IllegalArgumentException.class,
                () -> LruBlockCache.builder().capacity(overflowCapacity).build(),
                "LruBlockCache must reject capacity > Integer.MAX_VALUE "
                        + "because LinkedHashMap.size() returns int");
    }

    // Vector: [S7] Same bug via StripedBlockCache — perShard exceeds int range
    @Test
    void stripedCacheRejectsPerShardCapacityExceedingIntMax() {
        // totalCapacity = Integer.MAX_VALUE + 2, shardCount = 1
        // → perShard = Integer.MAX_VALUE + 2 → must be rejected
        long overflowCapacity = (long) Integer.MAX_VALUE + 2;

        assertThrows(IllegalArgumentException.class,
                () -> StripedBlockCache.builder().totalCapacity(overflowCapacity).shardCount(1)
                        .build(),
                "StripedBlockCache must reject configurations where perShard > Integer.MAX_VALUE");
    }

    // Vector: [S7] Boundary case — capacity exactly Integer.MAX_VALUE should be accepted
    @Test
    void capacityAtIntMaxIsAccepted() {
        // This should NOT throw — Integer.MAX_VALUE is the maximum valid capacity
        assertDoesNotThrow(() -> LruBlockCache.builder().capacity(Integer.MAX_VALUE).build(),
                "Capacity of exactly Integer.MAX_VALUE must be accepted");
    }

    // --- LOWER PRIORITY ---

    // Vector: [F15] Builder double-set — last call wins
    @Test
    void builderDoubleSetTotalCapacityLastWins() {
        try (var cache = StripedBlockCache.builder().totalCapacity(10).totalCapacity(20)
                .shardCount(4).build()) {
            assertEquals(20, cache.capacity(), "Last totalCapacity call should win");
        }
    }

    // Vector: [F15] Builder double-set shardCount
    @Test
    void builderDoubleSetShardCountLastWins() {
        try (var cache = StripedBlockCache.builder().totalCapacity(32).shardCount(2).shardCount(4)
                .build()) {
            // With shardCount=4 and totalCapacity=32, 4 shards each with capacity 8
            // Fill shard 0 with 9 entries → LRU eviction should occur at capacity 8
            for (int i = 0; i <= 8; i++) {
                long id = (long) i * 4; // all route to shard 0
                cache.put(id, 0L, MemorySegment.ofArray(new byte[]{ (byte) i }));
            }
            // First entry should be evicted (shard 0 capacity = 8)
            assertTrue(cache.get(0L, 0L).isEmpty(),
                    "shardCount=4 should give shard capacity 8, oldest evicted at 9th insert");
        }
    }

    // Vector: [F16] Large shardCount = totalCapacity — minimum capacity per shard
    @Test
    void largeShardCountWithMinCapacityPerShard() {
        int shardCount = 128;
        try (var cache = StripedBlockCache.builder().totalCapacity(shardCount)
                .shardCount(shardCount).build()) {
            // Each shard has capacity 1
            // Fill all 128 shards
            for (long id = 0; id < shardCount; id++) {
                cache.put(id, 0L, MemorySegment.ofArray(new byte[]{ (byte) id }));
            }
            assertEquals(shardCount, cache.size());

            // Add a second entry to shard 0 → evicts the first
            cache.put(0L, 1L, MemorySegment.ofArray(new byte[]{ 99 }));
            assertTrue(cache.get(0L, 0L).isEmpty(), "First entry in shard 0 should be evicted");
            assertTrue(cache.get(0L, 1L).isPresent(), "New entry should survive");
            assertEquals(shardCount, cache.size(), "Total size should remain at shardCount");
        }
    }

    // Vector: [P6] Evict racing with getOrLoad on same sstableId
    @Test
    void evictRacingWithGetOrLoadProducesConsistentState() throws Exception {
        try (var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build()) {
            long sstableId = 1L;
            long blockOffset = 0L;
            var block = MemorySegment.ofArray(new byte[]{ 42 });
            int iterations = 500;

            ExecutorService exec = Executors.newFixedThreadPool(2);

            for (int i = 0; i < iterations; i++) {
                // Seed the cache
                cache.put(sstableId, blockOffset, block);

                var barrier = new CyclicBarrier(2);
                var futures = new ArrayList<Future<?>>();

                // Thread 1: getOrLoad (will hit, but if evict runs between get and return,
                // the next getOrLoad would miss and reload)
                futures.add(exec.submit(() -> {
                    try {
                        barrier.await(5, TimeUnit.SECONDS);
                    } catch (Exception e) {
                        throw new RuntimeException(e);
                    }
                    var result = cache.getOrLoad(sstableId, blockOffset, () -> block);
                    assertNotNull(result, "getOrLoad must never return null");
                }));

                // Thread 2: evict
                futures.add(exec.submit(() -> {
                    try {
                        barrier.await(5, TimeUnit.SECONDS);
                    } catch (Exception e) {
                        throw new RuntimeException(e);
                    }
                    cache.evict(sstableId);
                }));

                for (var f : futures) {
                    f.get(10, TimeUnit.SECONDS);
                }

                // After both complete, state must be consistent:
                // Either the entry is present (getOrLoad's put ran after evict)
                // or absent (evict ran after getOrLoad's put)
                // size must be 0 or 1
                long size = cache.size();
                assertTrue(size == 0 || size == 1,
                        "Size must be 0 or 1 after racing evict + getOrLoad, got: " + size);

                // Clean up for next iteration
                cache.evict(sstableId);
            }

            exec.shutdown();
            assertTrue(exec.awaitTermination(10, TimeUnit.SECONDS));
        }
    }
}
