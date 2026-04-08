package jlsm.engine.internal;

import jlsm.engine.HandleEvictedException;
import jlsm.engine.Table;
import jlsm.engine.TableMetadata;
import jlsm.table.DuplicateKeyException;
import jlsm.table.JlsmDocument;
import jlsm.table.JlsmTable;
import jlsm.table.KeyNotFoundException;
import jlsm.table.TableEntry;
import jlsm.table.TableQuery;
import jlsm.table.UpdateMode;

import java.io.IOException;
import java.util.Iterator;
import java.util.Objects;
import java.util.Optional;

/**
 * Local implementation of {@link Table} wrapping a {@link JlsmTable.StringKeyed} with
 * handle lifecycle tracking.
 *
 * <p>
 * Every method checks handle validity before delegating to the underlying table.
 * If the handle has been evicted, a {@link HandleEvictedException} is thrown.
 *
 * <p>
 * Governed by: {@code .decisions/engine-api-surface-design/adr.md}
 */
final class LocalTable implements Table {

    private final JlsmTable.StringKeyed delegate;
    private final HandleRegistration registration;
    private final HandleTracker tracker;
    private final TableMetadata metadata;

    LocalTable(JlsmTable.StringKeyed delegate, HandleRegistration registration,
               HandleTracker tracker, TableMetadata metadata) {
        this.delegate = Objects.requireNonNull(delegate, "delegate must not be null");
        this.registration = Objects.requireNonNull(registration, "registration must not be null");
        this.tracker = Objects.requireNonNull(tracker, "tracker must not be null");
        this.metadata = Objects.requireNonNull(metadata, "metadata must not be null");
    }

    @Override
    public void create(String key, JlsmDocument doc) throws IOException {
        Objects.requireNonNull(key, "key must not be null");
        Objects.requireNonNull(doc, "doc must not be null");
        checkValid();
        throw new UnsupportedOperationException("Not implemented");
    }

    @Override
    public Optional<JlsmDocument> get(String key) throws IOException {
        Objects.requireNonNull(key, "key must not be null");
        checkValid();
        throw new UnsupportedOperationException("Not implemented");
    }

    @Override
    public void update(String key, JlsmDocument doc, UpdateMode mode) throws IOException {
        Objects.requireNonNull(key, "key must not be null");
        Objects.requireNonNull(doc, "doc must not be null");
        Objects.requireNonNull(mode, "mode must not be null");
        checkValid();
        throw new UnsupportedOperationException("Not implemented");
    }

    @Override
    public void delete(String key) throws IOException {
        Objects.requireNonNull(key, "key must not be null");
        checkValid();
        throw new UnsupportedOperationException("Not implemented");
    }

    @Override
    public void insert(JlsmDocument doc) throws IOException {
        Objects.requireNonNull(doc, "doc must not be null");
        checkValid();
        throw new UnsupportedOperationException("Not implemented");
    }

    @Override
    public TableQuery<String> query() {
        checkValid();
        throw new UnsupportedOperationException("Not implemented");
    }

    @Override
    public Iterator<TableEntry<String>> scan(String fromKey, String toKey) throws IOException {
        Objects.requireNonNull(fromKey, "fromKey must not be null");
        Objects.requireNonNull(toKey, "toKey must not be null");
        checkValid();
        throw new UnsupportedOperationException("Not implemented");
    }

    @Override
    public TableMetadata metadata() {
        return metadata;
    }

    @Override
    public void close() {
        tracker.release(registration);
    }

    /**
     * Checks that this handle has not been evicted or invalidated.
     *
     * @throws HandleEvictedException if the handle is invalid
     */
    private void checkValid() {
        if (registration.isInvalidated()) {
            throw new HandleEvictedException(
                    registration.tableName(),
                    registration.sourceId(),
                    0,
                    registration.allocationSite(),
                    HandleEvictedException.Reason.EVICTION);
        }
    }
}
