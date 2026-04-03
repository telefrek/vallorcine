package jlsm.engine.internal;

import jlsm.engine.AllocationTracking;
import jlsm.engine.Engine;
import jlsm.engine.EngineMetrics;
import jlsm.engine.Table;
import jlsm.engine.TableMetadata;
import jlsm.table.JlsmSchema;

import java.io.IOException;
import java.nio.file.Path;
import java.util.Collection;
import java.util.Objects;

/**
 * Embedded (local filesystem) implementation of {@link Engine}.
 *
 * <p>
 * Manages a {@link TableCatalog} for metadata persistence and a {@link HandleTracker}
 * for handle lifecycle. Each table is backed by its own subdirectory containing WAL,
 * SSTable, and metadata files.
 *
 * <p>
 * Governed by: {@code .decisions/engine-api-surface-design/adr.md},
 * {@code .decisions/table-catalog-persistence/adr.md}
 */
final class LocalEngine implements Engine {

    private final Path rootDirectory;
    private final TableCatalog catalog;
    private final HandleTracker handleTracker;

    private LocalEngine(Builder builder) {
        this.rootDirectory = Objects.requireNonNull(builder.rootDirectory,
                "rootDirectory must not be null");
        this.catalog = new TableCatalog(rootDirectory);
        this.handleTracker = HandleTracker.builder()
                .maxHandlesPerSourcePerTable(builder.maxHandlesPerSourcePerTable)
                .maxHandlesPerTable(builder.maxHandlesPerTable)
                .maxTotalHandles(builder.maxTotalHandles)
                .allocationTracking(builder.allocationTracking)
                .build();
    }

    /**
     * Returns a new builder for constructing a LocalEngine.
     *
     * @return a new builder; never null
     */
    static Builder builder() {
        return new Builder();
    }

    @Override
    public Table createTable(String name, JlsmSchema schema) throws IOException {
        Objects.requireNonNull(name, "name must not be null");
        Objects.requireNonNull(schema, "schema must not be null");
        if (name.isEmpty()) {
            throw new IllegalArgumentException("name must not be empty");
        }
        throw new UnsupportedOperationException("Not implemented");
    }

    @Override
    public Table getTable(String name) throws IOException {
        Objects.requireNonNull(name, "name must not be null");
        if (name.isEmpty()) {
            throw new IllegalArgumentException("name must not be empty");
        }
        throw new UnsupportedOperationException("Not implemented");
    }

    @Override
    public void dropTable(String name) throws IOException {
        Objects.requireNonNull(name, "name must not be null");
        if (name.isEmpty()) {
            throw new IllegalArgumentException("name must not be empty");
        }
        throw new UnsupportedOperationException("Not implemented");
    }

    @Override
    public Collection<TableMetadata> listTables() {
        throw new UnsupportedOperationException("Not implemented");
    }

    @Override
    public TableMetadata tableMetadata(String name) {
        Objects.requireNonNull(name, "name must not be null");
        throw new UnsupportedOperationException("Not implemented");
    }

    @Override
    public EngineMetrics metrics() {
        throw new UnsupportedOperationException("Not implemented");
    }

    @Override
    public void close() throws IOException {
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Builder for {@link LocalEngine}.
     */
    static final class Builder {

        private Path rootDirectory;
        private int maxHandlesPerSourcePerTable = 16;
        private int maxHandlesPerTable = 64;
        private int maxTotalHandles = 1024;
        private AllocationTracking allocationTracking = AllocationTracking.OFF;
        private long memTableFlushThresholdBytes = 64L * 1024 * 1024;

        private Builder() {
        }

        Builder rootDirectory(Path rootDirectory) {
            this.rootDirectory = Objects.requireNonNull(rootDirectory,
                    "rootDirectory must not be null");
            return this;
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
            this.allocationTracking = Objects.requireNonNull(tracking,
                    "tracking must not be null");
            return this;
        }

        Builder memTableFlushThresholdBytes(long bytes) {
            assert bytes > 0 : "bytes must be positive";
            this.memTableFlushThresholdBytes = bytes;
            return this;
        }

        LocalEngine build() {
            if (rootDirectory == null) {
                throw new IllegalStateException("rootDirectory must be set");
            }
            return new LocalEngine(this);
        }
    }
}
