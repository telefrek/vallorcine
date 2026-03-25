package jlsm.cache;

import org.junit.jupiter.api.Test;

import java.lang.foreign.MemorySegment;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicLong;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Adversarial tests for {@link StripedBlockCache} and {@link LruBlockCache} — aTDD Round 2. Targets
 * deeper issues exposed by Round 1 fixes.
 */
class StripedBlockCacheAdversarialRound2Test {

    // --- F5: Capacity exceeding Integer.MAX_VALUE disables LRU eviction ---

    /**
     * Vector F5: LruBlockCache uses LinkedHashMap whose size() returns int. The eviction guard is
     * {@code size() > cap} where cap is long. If capacity exceeds Integer.MAX_VALUE, int size can
     * never exceed long cap — eviction never triggers.
     *
     * <p>
     * We cannot insert 2B entries, so we test the boundary indirectly: build with capacity=3,
     * insert 4 entries, verify eviction fires (baseline). Then build with capacity =
     * Integer.MAX_VALUE + 1L and verify the builder rejects it, OR if it doesn't, verify eviction
     * is broken.
     */
    @Test
    void lruBlockCacheRejectsCapacityExceedingIntMaxValue() {
        // Baseline: small capacity evicts correctly
        try (var baseline = LruBlockCache.builder().capacity(3).build()) {
            for (long i = 0; i < 4; i++) {
                baseline.put(i, 0L, MemorySegment.ofArray(new byte[]{ (byte) i }));
            }
            assertEquals(3, baseline.size(), "Baseline eviction should work at capacity=3");
        }

        // The builder should reject capacity values that exceed Integer.MAX_VALUE,
        // since LinkedHashMap.size() returns int and eviction would silently break.
        long overflowCapacity = (long) Integer.MAX_VALUE + 1;
        assertThrows(IllegalArgumentException.class,
                () -> LruBlockCache.builder().capacity(overflowCapacity).build(),
                "LruBlockCache should reject capacity > Integer.MAX_VALUE because "
                        + "LinkedHashMap.size() returns int and eviction guard would never trigger");
    }

    /**
     * Vector F5 (striped): StripedBlockCache should reject configurations where per-stripe capacity
     * would exceed Integer.MAX_VALUE.
     */
    @Test
    void stripedBlockCacheRejectsPerStripeCapacityExceedingIntMaxValue() {
        // capacity = Long.MAX_VALUE, stripeCount = 2 → per-stripe = Long.MAX_VALUE / 2
        // which far exceeds Integer.MAX_VALUE
        long hugeCapacity = Long.MAX_VALUE;
        assertThrows(IllegalArgumentException.class,
                () -> StripedBlockCache.builder().stripeCount(2).capacity(hugeCapacity).build(),
                "Per-stripe capacity exceeds Integer.MAX_VALUE — eviction would be disabled");
    }

    // --- F6: getOrLoad loader that throws exception ---

    /**
     * Vector F6: If the loader throws a RuntimeException during getOrLoad, the cache must remain in
     * a consistent state — the lock is released, no partial entry is cached, and subsequent
     * operations work normally.
     */
    @Test
    void getOrLoadLoaderExceptionLeavesConsistentState() {
        try (var cache = StripedBlockCache.builder().stripeCount(2).capacity(100).build()) {
            // Loader throws on first call
            assertThrows(RuntimeException.class, () -> cache.getOrLoad(1L, 0L, () -> {
                throw new RuntimeException("simulated I/O failure");
            }));

            // Cache should be empty — no partial entry
            assertTrue(cache.get(1L, 0L).isEmpty(),
                    "Failed getOrLoad should not leave a partial entry in the cache");
            assertEquals(0, cache.size(), "Cache size should be 0 after failed load");

            // Subsequent operations should work normally — lock was released
            var block = MemorySegment.ofArray(new byte[]{ 42 });
            cache.put(1L, 0L, block);
            assertEquals(block, cache.get(1L, 0L).orElseThrow(),
                    "Cache should work normally after a failed getOrLoad");
        }
    }

    /**
     * Vector F6 (NPE variant): If the loader returns null, getOrLoad should throw
     * NullPointerException and leave the cache consistent.
     */
    @Test
    void getOrLoadLoaderReturnsNullThrowsAndLeavesConsistentState() {
        try (var cache = StripedBlockCache.builder().stripeCount(2).capacity(100).build()) {
            assertThrows(NullPointerException.class, () -> cache.getOrLoad(1L, 0L, () -> null));

            assertTrue(cache.get(1L, 0L).isEmpty(),
                    "Null-returning loader should not leave an entry in the cache");

            // Subsequent operations still work
            var block = MemorySegment.ofArray(new byte[]{ 1 });
            cache.put(1L, 0L, block);
            assertEquals(1, cache.size());
        }
    }

    // --- P2: getOrLoad holds stripe lock during slow loader ---

    /**
     * Vector P2: getOrLoad holds the stripe lock during the entire loader execution. A slow loader
     * blocks all other operations on the same stripe. This test establishes the blocking behaviour
     * as a documented trade-off.
     */
    @Test
    void getOrLoadBlocksOtherOperationsOnSameStripe() throws InterruptedException {
        // Use 1 stripe so all operations contend on the same lock
        try (var cache = StripedBlockCache.builder().stripeCount(1).capacity(100).build()) {
            var loaderStarted = new CountDownLatch(1);
            var loaderProceed = new CountDownLatch(1);
            var getCompleted = new AtomicLong(-1);
            var errors = new java.util.concurrent.ConcurrentLinkedQueue<Throwable>();

            // Thread 1: slow getOrLoad
            Thread.ofPlatform().start(() -> {
                try {
                    cache.getOrLoad(1L, 0L, () -> {
                        loaderStarted.countDown();
                        try {
                            loaderProceed.await();
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                        }
                        return MemorySegment.ofArray(new byte[]{ 42 });
                    });
                } catch (Throwable e) {
                    errors.add(e);
                }
            });

            // Wait for loader to be executing (lock is held)
            loaderStarted.await();

            // Thread 2: try a simple get — should block until loader completes
            long getStart = System.nanoTime();
            var getDone = new CountDownLatch(1);
            Thread.ofPlatform().start(() -> {
                try {
                    cache.get(2L, 0L); // different key, same stripe
                    getCompleted.set(System.nanoTime());
                } catch (Throwable e) {
                    errors.add(e);
                } finally {
                    getDone.countDown();
                }
            });

            // Give Thread 2 time to attempt the lock
            Thread.sleep(50);

            // Release the loader
            long releaseTime = System.nanoTime();
            loaderProceed.countDown();

            getDone.await();

            if (!errors.isEmpty()) {
                fail("Thread error: " + errors.peek().getMessage(), errors.peek());
            }

            // The get should have completed AFTER the loader was released,
            // proving it was blocked by the lock. Allow 10ms tolerance.
            long getCompletedTime = getCompleted.get();
            assertTrue(getCompletedTime >= releaseTime - 10_000_000L,
                    "get() should have been blocked by the slow loader — " + "completed "
                            + ((releaseTime - getCompletedTime) / 1_000_000)
                            + "ms before loader released");
        }
    }

    // --- F7: getOrLoad blockOffset validation ---

    /**
     * Vector F7: StripedBlockCache.getOrLoad must validate blockOffset before delegating to stripe.
     */
    @Test
    void getOrLoadRejectsNegativeBlockOffset() {
        try (var cache = StripedBlockCache.builder().stripeCount(2).capacity(100).build()) {
            assertThrows(IllegalArgumentException.class,
                    () -> cache.getOrLoad(1L, -1L, () -> MemorySegment.ofArray(new byte[]{ 1 })));
        }
    }

    /**
     * Vector F7: StripedBlockCache.getOrLoad must validate null loader.
     */
    @Test
    void getOrLoadRejectsNullLoader() {
        try (var cache = StripedBlockCache.builder().stripeCount(2).capacity(100).build()) {
            assertThrows(NullPointerException.class, () -> cache.getOrLoad(1L, 0L, null));
        }
    }

    // --- F8: Builder method ordering ---

    /**
     * Vector F8: Setting capacity before stripeCount should still validate correctly at build time.
     */
    @Test
    void builderCapacityBeforeStripeCountValidatesCorrectly() {
        // capacity=5 then stripeCount=10 → capacity < stripeCount → reject
        assertThrows(IllegalArgumentException.class,
                () -> StripedBlockCache.builder().capacity(5).stripeCount(10).build());

        // capacity=10 then stripeCount=5 → valid
        try (var cache = StripedBlockCache.builder().capacity(10).stripeCount(5).build()) {
            assertEquals(10, cache.capacity());
        }
    }
}
