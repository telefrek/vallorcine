package jlsm.table;

import java.lang.foreign.MemorySegment;
import java.util.List;
import java.util.Objects;

/**
 * Configuration for a {@link PartitionedTable} specifying the partition layout.
 *
 * <p>
 * Contract: Immutable configuration holding partition descriptors that must form a contiguous,
 * non-overlapping coverage of the keyspace. Validated at construction time.
 *
 * <p>
 * Governed by: .decisions/table-partitioning/adr.md — static partitions, boundaries fixed at
 * creation.
 */
public final class PartitionConfig {

    private PartitionConfig() {
        throw new AssertionError("not implemented");
    }

    /**
     * Creates a partition configuration from a list of descriptors.
     *
     * <p>
     * Contract:
     * <ul>
     * <li>Receives: list of {@link PartitionDescriptor} — must be non-empty, contiguous,
     * non-overlapping, covering the full keyspace</li>
     * <li>Returns: validated {@code PartitionConfig}</li>
     * <li>Side effects: none</li>
     * <li>Error conditions: throws {@link IllegalArgumentException} if descriptors overlap, have
     * gaps, or are empty</li>
     * </ul>
     *
     * @param descriptors the partition descriptors in key order
     * @return a validated partition configuration
     */
    public static PartitionConfig of(List<PartitionDescriptor> descriptors) {
        throw new UnsupportedOperationException("not implemented");
    }

    /**
     * Returns the unmodifiable list of partition descriptors in key order.
     *
     * @return partition descriptors
     */
    public List<PartitionDescriptor> descriptors() {
        throw new UnsupportedOperationException("not implemented");
    }

    /**
     * Returns the number of partitions.
     *
     * @return partition count
     */
    public int partitionCount() {
        throw new UnsupportedOperationException("not implemented");
    }
}
