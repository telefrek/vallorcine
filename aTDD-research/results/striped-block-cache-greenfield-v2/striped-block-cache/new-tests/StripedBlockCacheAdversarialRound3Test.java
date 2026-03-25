package jlsm.cache;

import org.junit.jupiter.api.Test;

import java.lang.foreign.MemorySegment;
import java.util.concurrent.CompletionException;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Adversarial tests for {@link StripedBlockCache} — Round 3 (audit mode).
 * Targets bugs in the round 2 getOrLoad deduplication and eviction version mechanism.
 */
class StripedBlockCacheAdversarialRound3Test {

    private static MemorySegment block(byte... data) {
        return MemorySegment.ofArray(data);
    }

    // ──────────────────────────────────────────────────────────────────
    // F3-1 — Eviction version false positive skips valid loads
    // Vector: evict(sstableId=2) during getOrLoad(sstableId=1) causes the
    // valid load for sstableId=1 to skip caching because the global
    // eviction version changed
    // ──────────────────────────────────────────────────────────────────

    @Test
    void evictOfDifferentSstableIdDoesNotPreventCachingCurrentLoad() throws Exception {
        // F3-1: getOrLoad(sstableId=1) should cache the result even if
        // evict(sstableId=2) is called during loading. The eviction is
        // for a different sstableId — it should not affect sstableId=1's load.
        try (var cache = StripedBlockCache.builder().totalCapacity(64).shardCount(4).build()) {
            var loaderStarted = new CountDownLatch(1);
            var evictDone = new CountDownLatch(1);
            var errors = new java.util.concurrent.ConcurrentLinkedQueue<Throwable>();
            var done = new CountDownLatch(2);

            // Pre-populate sstableId=2 so evict has something to remove
            cache.put(2L, 0L, block((byte) 99));

            // Thread A: getOrLoad sstableId=1 with a slow loader
            new Thread(() -> {
                try {
                    cache.getOrLoad(1L, 0L, () -> {
                        loaderStarted.countDown();
                        try {
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

            // Thread B: evict a DIFFERENT sstableId while sstableId=1 is loading
            new Thread(() -> {
                try {
                    assertTrue(loaderStarted.await(5, TimeUnit.SECONDS),
                            "loader did not start in time");
                    cache.evict(2L); // evict sstableId=2, NOT sstableId=1
                    evictDone.countDown();
                } catch (Throwable ex) {
                    errors.add(ex);
                } finally {
                    done.countDown();
                }
            }).start();

            assertTrue(done.await(10, TimeUnit.SECONDS), "threads did not complete");
            assertTrue(errors.isEmpty(), "unexpected exceptions: " + errors);

            // sstableId=1 was NOT evicted — its loaded block SHOULD be in the cache
            assertTrue(cache.get(1L, 0L).isPresent(),
                    "Eviction version false positive: evict(sstableId=2) caused "
                            + "getOrLoad(sstableId=1) to skip caching — valid data was discarded");
        }
    }

    // ──────────────────────────────────────────────────────────────────
    // F3-2 — Loader exception changes type for waiting threads
    // Vector: waiting threads get CompletionException instead of the
    // original exception type thrown by the loader
    // ──────────────────────────────────────────────────────────────────

    @Test
    void getOrLoadLoaderExceptionPropagatesOriginalTypeToWaiters() throws Exception {
        // F3-2: Two threads call getOrLoad for the same key. The loader throws
        // an IllegalStateException. Both threads should see IllegalStateException,
        // not CompletionException.
        try (var cache = StripedBlockCache.builder().totalCapacity(64).shardCount(4).build()) {
            var barrier = new CyclicBarrier(2);
            var loaderException = new IllegalStateException("simulated disk failure");
            var threadAException = new AtomicReference<Throwable>();
            var threadBException = new AtomicReference<Throwable>();
            var done = new CountDownLatch(2);

            // Thread A
            new Thread(() -> {
                try {
                    barrier.await(5, TimeUnit.SECONDS);
                    cache.getOrLoad(1L, 0L, () -> {
                        // Small delay to let the other thread arrive at join()
                        try { Thread.sleep(50); } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                        }
                        throw loaderException;
                    });
                } catch (Throwable ex) {
                    threadAException.set(ex);
                } finally {
                    done.countDown();
                }
            }).start();

            // Thread B
            new Thread(() -> {
                try {
                    barrier.await(5, TimeUnit.SECONDS);
                    cache.getOrLoad(1L, 0L, () -> {
                        throw new AssertionError("This loader should not be called — "
                                + "Thread A should be the loader");
                    });
                } catch (Throwable ex) {
                    threadBException.set(ex);
                } finally {
                    done.countDown();
                }
            }).start();

            assertTrue(done.await(10, TimeUnit.SECONDS), "threads did not complete");

            // At least one thread should have caught the exception
            // The loader thread should see IllegalStateException directly
            // The waiting thread should ALSO see IllegalStateException, not CompletionException
            Throwable aEx = threadAException.get();
            Throwable bEx = threadBException.get();

            // One of them was the loader, one was the waiter
            // Both should see the original exception type, not wrapped
            if (aEx != null) {
                assertFalse(aEx instanceof CompletionException,
                        "Thread A got CompletionException instead of original exception type: " + aEx);
            }
            if (bEx != null) {
                assertFalse(bEx instanceof CompletionException,
                        "Thread B got CompletionException instead of original exception type: " + bEx);
            }

            // At least one must have caught the exception
            assertTrue(aEx != null || bEx != null,
                    "At least one thread should have caught the loader exception");
        }
    }

    // ──────────────────────────────────────────────────────────────────
    // P3-1 — inflightLoads join() blocks indefinitely
    // Vector: CompletableFuture.join() has no timeout. If the loader
    // hangs, waiting threads block forever.
    // ──────────────────────────────────────────────────────────────────

    @Test
    void getOrLoadWaiterDoesNotBlockIndefinitelyOnSlowLoader() throws Exception {
        // P3-1: Start getOrLoad with a loader that blocks on a latch (simulating
        // a hung disk read). A second thread calling getOrLoad for the same key
        // should not block indefinitely — it should either timeout or proceed.
        //
        // We detect "indefinite blocking" by checking if the second thread completes
        // within 2 seconds. The loader blocks for much longer (never released).
        try (var cache = StripedBlockCache.builder().totalCapacity(64).shardCount(4).build()) {
            var neverReleasedLatch = new CountDownLatch(1);
            var loaderStarted = new CountDownLatch(1);
            var waiterResult = new AtomicReference<String>("not-started");
            var waiterDone = new CountDownLatch(1);

            // Thread A: loader that hangs
            var loaderThread = new Thread(() -> {
                try {
                    cache.getOrLoad(1L, 0L, () -> {
                        loaderStarted.countDown();
                        try {
                            // Block "forever" (until interrupted)
                            neverReleasedLatch.await(30, TimeUnit.SECONDS);
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                        }
                        return block((byte) 1);
                    });
                } catch (Throwable ignored) {
                    // Expected — we'll interrupt this thread
                }
            });
            loaderThread.start();

            // Wait for loader to start
            assertTrue(loaderStarted.await(5, TimeUnit.SECONDS), "loader did not start");

            // Thread B: waiter that should not block indefinitely
            var waiterThread = new Thread(() -> {
                try {
                    cache.getOrLoad(1L, 0L, () -> block((byte) 2));
                    waiterResult.set("completed");
                } catch (Throwable ex) {
                    waiterResult.set("exception: " + ex.getClass().getSimpleName());
                } finally {
                    waiterDone.countDown();
                }
            });
            waiterThread.start();

            // The waiter should complete within a bounded time (2 seconds).
            // If join() blocks indefinitely, this will timeout.
            boolean waiterFinished = waiterDone.await(2, TimeUnit.SECONDS);

            // Clean up: release the loader and interrupt threads
            neverReleasedLatch.countDown();
            loaderThread.interrupt();
            waiterThread.interrupt();
            loaderThread.join(5000);
            waiterThread.join(5000);

            assertTrue(waiterFinished,
                    "Waiter thread blocked indefinitely on join() — violates bounded blocking "
                            + "requirement. CompletableFuture.join() has no timeout.");
        }
    }
}
