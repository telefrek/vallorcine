package jlsm.engine.internal;

import jlsm.engine.AllocationTracking;
import jlsm.engine.EngineMetrics;
import jlsm.engine.HandleEvictedException;

import java.io.Closeable;
import java.io.IOException;
import java.util.Objects;

/**
 * Tracks open table handles per source, enforces configurable limits, and performs
 * greedy-source-first eviction under pressure.
 *
 * <p>
 * Governed by: {@code .decisions/engine-api-surface-design/adr.md}
 */
final class HandleTracker implements Closeable {

    private final int maxHandlesPerSourcePerTable;
    private final int maxHandlesPerTable;
    private final int maxTotalHandles;
    private final AllocationTracking allocationTracking;

    private HandleTracker(Builder builder) {
        assert builder.maxHandlesPerSourcePerTable > 0 : "maxHandlesPerSourcePerTable must be positive";
        assert builder.maxHandlesPerTable > 0 : "maxHandlesPerTable must be positive";
        assert builder.maxTotalHandles > 0 : "maxTotalHandles must be positive";
        this.maxHandlesPerSourcePerTable = builder.maxHandlesPerSourcePerTable;
        this.maxHandlesPerTable = builder.maxHandlesPerTable;
        this.maxTotalHandles = builder.maxTotalHandles;
        this.allocationTracking = Objects.requireNonNull(builder.allocationTracking,
                "allocationTracking must not be null");
    }

    /**
     * Returns a new builder for constructing a HandleTracker.
     *
     * @return a new builder; never null
     */
    static Builder builder() {
        return new Builder();
    }

    /**
     * Registers a new handle for the given table and source.
     *
     * @param tableName the table name; must not be null
     * @param sourceId  the source identifier; must not be null
     * @return a registration token that must be released when the handle is closed
     */
    HandleRegistration register(String tableName, String sourceId) {
        Objects.requireNonNull(tableName, "tableName must not be null");
        Objects.requireNonNull(sourceId, "sourceId must not be null");
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Releases a previously registered handle.
     *
     * @param registration the registration to release; must not be null
     */
    void release(HandleRegistration registration) {
        Objects.requireNonNull(registration, "registration must not be null");
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Evicts handles if the table exceeds its handle limit, using greedy-source-first strategy.
     *
     * @param tableName the table to check; must not be null
     */
    void evictIfNeeded(String tableName) {
        Objects.requireNonNull(tableName, "tableName must not be null");
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Invalidates all tracked handles with the given reason.
     *
     * @param reason the invalidation reason; must not be null
     */
    void invalidateAll(HandleEvictedException.Reason reason) {
        Objects.requireNonNull(reason, "reason must not be null");
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Invalidates all tracked handles for a specific table.
     *
     * @param tableName the table name; must not be null
     * @param reason    the invalidation reason; must not be null
     */
    void invalidateTable(String tableName, HandleEvictedException.Reason reason) {
        Objects.requireNonNull(tableName, "tableName must not be null");
        Objects.requireNonNull(reason, "reason must not be null");
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Returns a snapshot of current engine metrics.
     *
     * @return the current metrics; never null
     */
    EngineMetrics snapshot() {
        throw new UnsupportedOperationException("Not implemented");
    }

    @Override
    public void close() throws IOException {
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Builder for {@link HandleTracker}.
     */
    static final class Builder {

        private int maxHandlesPerSourcePerTable = 16;
        private int maxHandlesPerTable = 64;
        private int maxTotalHandles = 1024;
        private AllocationTracking allocationTracking = AllocationTracking.OFF;

        private Builder() {
        }

        Builder maxHandlesPerSourcePerTable(int max) {
            assert max > 0 : "max must be positive";
            this.maxHandlesPerSourcePerTable = max;
            return this;
        }

        Builder maxHandlesPerTable(int max) {
            assert max > 0 : "max must be positive";
            this.maxHandlesPerTable = max;
            return this;
        }

        Builder maxTotalHandles(int max) {
            assert max > 0 : "max must be positive";
            this.maxTotalHandles = max;
            return this;
        }

        Builder allocationTracking(AllocationTracking tracking) {
            Objects.requireNonNull(tracking, "tracking must not be null");
            this.allocationTracking = tracking;
            return this;
        }

        HandleTracker build() {
            return new HandleTracker(this);
        }
    }
}
