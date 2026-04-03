package jlsm.table.internal;

import jlsm.table.JlsmDocument;
import jlsm.table.JlsmTable;
import jlsm.table.PartitionClient;
import jlsm.table.PartitionDescriptor;
import jlsm.table.Predicate;
import jlsm.table.ScoredEntry;
import jlsm.table.TableEntry;
import jlsm.table.UpdateMode;

import java.io.IOException;
import java.util.Iterator;
import java.util.List;
import java.util.Optional;

/**
 * In-process implementation of {@link PartitionClient} that wraps a {@link JlsmTable.StringKeyed}.
 *
 * <p>
 * Contract: Delegates all operations directly to the wrapped table instance. No serialization or
 * network overhead. This is the only implementation for the initial (in-process) deployment.
 *
 * <p>
 * Governed by: .decisions/table-partitioning/adr.md — in-process execution, remote-capable
 * interface.
 */
public final class InProcessPartitionClient implements PartitionClient {

    /**
     * Creates an in-process partition client wrapping the given table.
     *
     * <p>
     * Contract:
     * <ul>
     * <li>Receives: descriptor for this partition, the backing JlsmTable.StringKeyed</li>
     * <li>Returns: partition client ready for operations</li>
     * <li>Side effects: none</li>
     * </ul>
     *
     * @param descriptor the partition descriptor
     * @param table the backing table for this partition
     */
    public InProcessPartitionClient(PartitionDescriptor descriptor, JlsmTable.StringKeyed table) {
        throw new UnsupportedOperationException("not implemented");
    }

    @Override
    public PartitionDescriptor descriptor() {
        throw new UnsupportedOperationException("not implemented");
    }

    @Override
    public void create(String key, JlsmDocument doc) throws IOException {
        throw new UnsupportedOperationException("not implemented");
    }

    @Override
    public Optional<JlsmDocument> get(String key) throws IOException {
        throw new UnsupportedOperationException("not implemented");
    }

    @Override
    public void update(String key, JlsmDocument doc, UpdateMode mode) throws IOException {
        throw new UnsupportedOperationException("not implemented");
    }

    @Override
    public void delete(String key) throws IOException {
        throw new UnsupportedOperationException("not implemented");
    }

    @Override
    public Iterator<TableEntry<String>> getRange(String fromKey, String toKey) throws IOException {
        throw new UnsupportedOperationException("not implemented");
    }

    @Override
    public List<ScoredEntry<String>> query(Predicate predicate, int limit) throws IOException {
        throw new UnsupportedOperationException("not implemented");
    }

    @Override
    public void close() throws IOException {
        throw new UnsupportedOperationException("not implemented");
    }
}
