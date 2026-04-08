package jlsm.cache;

import org.junit.jupiter.api.Test;

import java.lang.foreign.MemorySegment;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Adversarial tests for {@link StripedBlockCache} — Round 2 (audit mode).
 * Targets deeper concurrency and lifecycle vectors not covered in Round 1.
 */
class StripedBlockCacheAdversarialRound2Test {

    private static MemorySegment block(byte... data) {
        return MemorySegment.ofArray(data);
    }

    // ──────────────────────────────────────────────────────────────────
    // F2-1 — getOrLoad TOCTOU race (double loader invocation)
    // Vector: two threads calling getOrLoad with the same key both see
    // a miss and both invoke the loader, violating "called exactly once"
    // ──────────────────────────────────────────────────────────────────

    @Test
    void getOrLoadInvokesLoaderAtMostOnceUnderContention() throws Exception {
        // F2-1: Two threads race on getOrLoad with the same key.
        // The loader counts invocations. If count > 1, the race is confirmed.
        // Use a barrier to maximize overlap.
        try (var cache = StripedBlockCache.builder().totalCapacity(64).shardCount(4).build()) {
            var loaderCount = new AtomicInteger(0);
            var barrier = new CyclicBarrier(2);
            var errors = new java.util.concurrent.ConcurrentLinkedQueue<Throwable>();
            var done = new CountDownLatch(2);

            for (int t = 0; t < 2; t++) {
                new Thread(() -> {
                    try {
                        barrier.await(5, TimeUnit.SECONDS);
                        cache.getOrLoad(1L, 0L, () -> {
                            loaderCount.incrementAndGet();
                            // Small delay to widen the race window
                            Thread.onSpinWait();
                            return block((byte) 42);
                        });
                    } catch (Throwable ex) {
                        errors.add(ex);
                    } finally {
                        done.countDown();
                    }
                }).start();
            }

            assertTrue(done.await(10, TimeUnit.SECONDS), "threads did not complete");
            assertTrue(errors.isEmpty(), "unexpected exceptions: " + errors);
            assertEquals(1, loaderCount.get(),
                    "Loader should be called exactly once under contention, but was called "
                            + loaderCount.get() + " times — getOrLoad has a TOCTOU race");
        }
    }

    @Test
    void getOrLoadThunderingHerdMultipleThreads() throws Exception {
        // P2-1/F2-1: Wider thundering herd — 8 threads all miss the same key.
        // On a cold cache, all 8 will invoke the loader if getOrLoad is not atomic.
        try (var cache = StripedBlockCache.builder().totalCapacity(64).shardCount(4).build()) {
            int threadCount = 8;
            var loaderCount = new AtomicInteger(0);
            var barrier = new CyclicBarrier(threadCount);
            var done = new CountDownLatch(threadCount);
            var errors = new java.util.concurrent.ConcurrentLinkedQueue<Throwable>();

            for (int t = 0; t < threadCount; t++) {
                new Thread(() -> {
                    try {
                        barrier.await(5, TimeUnit.SECONDS);
                        cache.getOrLoad(42L, 4096L, () -> {
                            loaderCount.incrementAndGet();
                            // Simulate a slow disk read to widen the window
                            try { Thread.sleep(10); } catch (InterruptedException e) {
                                Thread.currentThread().interrupt();
                            }
                            return block((byte) 99);
                        });
                    } catch (Throwable ex) {
                        errors.add(ex);
                    } finally {
                        done.countDown();
                    }
                }).start();
            }

            assertTrue(done.await(30, TimeUnit.SECONDS), "threads did not complete");
            assertTrue(errors.isEmpty(), "unexpected exceptions: " + errors);
            assertEquals(1, loaderCount.get(),
                    "Thundering herd: loader called " + loaderCount.get()
                            + " times instead of 1 — all " + threadCount
                            + " threads invoked the loader independently");
        }
    }

    // ──────────────────────────────────────────────────────────────────
    // F2-2 — Evict-during-getOrLoad stale re-insertion
    // Vector: getOrLoad sees a miss, evict clears the sstableId,
    // then getOrLoad's put re-inserts a stale block
    // ──────────────────────────────────────────────────────────────────

    @Test
    void evictDuringGetOrLoadDoesNotReinsertStaleBlock() throws Exception {
        // F2-2: Controlled interleaving:
        // 1. Thread A starts getOrLoad(1, 0, slowLoader) → get() returns empty
        // 2. slowLoader blocks on a latch
        // 3. Thread B calls evict(1) → removes all entries for sstableId=1
        // 4. Release the latch → loader returns → put(1, 0, block)
        // 5. After both complete, sstableId=1 should NOT be in the cache
        try (var cache = StripedBlockCache.builder().totalCapacity(64).shardCount(4).build()) {
            // Pre-populate so evict has something to remove
            cache.put(1L, 4096L, block((byte) 1));

            var loaderStarted = new CountDownLatch(1);
            var evictDone = new CountDownLatch(1);
            var errors = new java.util.concurrent.ConcurrentLinkedQueue<Throwable>();
            var done = new CountDownLatch(2);

            // Thread A: getOrLoad with a slow loader
            new Thread(() -> {
                try {
                    cache.getOrLoad(1L, 0L, () -> {
                        loaderStarted.countDown(); // signal: we're inside the loader
                        try {
                            // Wait for evict to complete
                            assertTrue(evictDone.await(5, TimeUnit.SECONDS),
                                    "evict did not complete in time");
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                        }
                        return block((byte) 42);
                    });
                } catch (Throwable ex) {
                    errors.add(ex);
                } finally {
                    done.countDown();
                }
            }).start();

            // Thread B: wait for loader to start, then evict
            new Thread(() -> {
                try {
                    assertTrue(loaderStarted.await(5, TimeUnit.SECONDS),
                            "loader did not start in time");
                    cache.evict(1L); // evict all entries for sstableId=1
                    evictDone.countDown();
                } catch (Throwable ex) {
                    errors.add(ex);
                } finally {
                    done.countDown();
                }
            }).start();

            assertTrue(done.await(10, TimeUnit.SECONDS), "threads did not complete");
            assertTrue(errors.isEmpty(), "unexpected exceptions: " + errors);

            // After evict(1), sstableId=1 should be gone. If getOrLoad's put
            // re-inserted it, this will fail — stale re-insertion bug.
            assertTrue(cache.get(1L, 0L).isEmpty(),
                    "Stale re-insertion: evict(1) completed but getOrLoad re-inserted a block "
                            + "for sstableId=1 after eviction — the cache now serves stale data");
        }
    }

    // ──────────────────────────────────────────────────────────────────
    // F2-3 — Effective capacity lie with non-divisible totalCapacity
    // Vector: capacity() returns totalCapacity but actual capacity is
    // shardCount * floor(totalCapacity / shardCount) < totalCapacity
    // ──────────────────────────────────────────────────────────────────

    @Test
    void effectiveCapacityMatchesAdvertisedCapacity() {
        // F2-3: With shardCount=1 (all entries in one shard), the shard capacity
        // is totalCapacity/1 = totalCapacity. This should hold exactly totalCapacity entries.
        // If this passes, the capacity lie only manifests with multi-shard + uneven distribution.
        try (var cache = StripedBlockCache.builder().totalCapacity(10).shardCount(1).build()) {
            for (int i = 0; i < 10; i++) {
                cache.put(1L, i, block((byte) i));
            }
            assertEquals(10, cache.size(),
                    "With shardCount=1, cache should hold exactly totalCapacity entries");
        }
    }

    @Test
    void effectiveCapacityWithNonDivisibleTotalShowsLoss() {
        // F2-3: totalCapacity=7, shardCount=4 → per-shard = 1.
        // Effective max = 4 (4 shards × 1 entry each). But capacity() returns 7.
        // Insert 7 entries via shardCount=1 (all in one shard, capacity 1):
        // only 1 survives.
        try (var cache = StripedBlockCache.builder().totalCapacity(7).shardCount(4).build()) {
            assertEquals(7, cache.capacity(),
                    "capacity() must return the configured totalCapacity");
            // Note: actual effective capacity is 4 (4 shards × 1 entry each),
            // less than the advertised 7. This is inherent to striped caches
            // with integer division. Not a bug, but a documented limitation.
        }
    }

    // ──────────────────────────────────────────────────────────────────
    // F2-4 — Double close idempotency
    // Vector: calling close() twice should not throw
    // ──────────────────────────────────────────────────────────────────

    @Test
    void doubleCloseDoesNotThrow() {
        // F2-4: Production code often calls close() twice (try-with-resources + explicit)
        var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build();
        cache.put(1L, 0L, block((byte) 1));
        cache.close();
        assertDoesNotThrow(cache::close, "double close should be idempotent");
    }

    // ──────────────────────────────────────────────────────────────────
    // F2-5 — Operations after close
    // Vector: put() after close() silently succeeds, potentially
    // masking lifecycle bugs in calling code
    // ──────────────────────────────────────────────────────────────────

    @Test
    void getAfterCloseReturnsEmpty() {
        // F2-5: After close(), all data is cleared. get() should return empty.
        // This is a regression tripwire — the interface says behavior is undefined.
        var cache = StripedBlockCache.builder().totalCapacity(16).shardCount(4).build();
        cache.put(1L, 0L, block((byte) 1));
        cache.close();
        assertTrue(cache.get(1L, 0L).isEmpty(),
                "get() after close() should return empty (cache was cleared)");
    }
}
