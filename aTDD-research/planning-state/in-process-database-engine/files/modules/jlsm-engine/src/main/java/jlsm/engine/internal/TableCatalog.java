package jlsm.engine.internal;

import jlsm.engine.TableMetadata;
import jlsm.table.JlsmSchema;

import java.io.Closeable;
import java.io.IOException;
import java.nio.file.Path;
import java.util.Collection;
import java.util.Objects;
import java.util.Optional;

/**
 * Manages per-table directory layout, metadata persistence, and lazy table loading.
 *
 * <p>
 * Each table lives in its own subdirectory under the engine root. The catalog scans
 * the root directory on {@link #open()} to discover existing tables and builds lightweight
 * metadata handles. Full table initialization is deferred until first access.
 *
 * <p>
 * Governed by: {@code .decisions/table-catalog-persistence/adr.md}
 */
final class TableCatalog implements Closeable {

    private final Path rootDir;

    /**
     * Constructs a new TableCatalog for the given root directory.
     *
     * @param rootDir the engine root directory; must not be null
     */
    TableCatalog(Path rootDir) {
        this.rootDir = Objects.requireNonNull(rootDir, "rootDir must not be null");
    }

    /**
     * Opens the catalog by scanning the root directory for existing table subdirectories.
     * Builds lightweight metadata handles without fully initializing tables.
     *
     * @throws IOException if the root directory cannot be read or is corrupt
     */
    void open() throws IOException {
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Registers a new table by creating its subdirectory and metadata file.
     *
     * @param name   the table name; must not be null or empty
     * @param schema the table schema; must not be null
     * @return the metadata for the newly registered table
     * @throws IOException if the table already exists or the directory cannot be created
     */
    TableMetadata register(String name, JlsmSchema schema) throws IOException {
        Objects.requireNonNull(name, "name must not be null");
        Objects.requireNonNull(schema, "schema must not be null");
        if (name.isEmpty()) {
            throw new IllegalArgumentException("name must not be empty");
        }
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Unregisters a table by removing its subdirectory and all contained files.
     *
     * @param name the table name; must not be null or empty
     * @throws IOException if the table does not exist or cannot be removed
     */
    void unregister(String name) throws IOException {
        Objects.requireNonNull(name, "name must not be null");
        if (name.isEmpty()) {
            throw new IllegalArgumentException("name must not be empty");
        }
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Returns metadata for a specific table, or empty if not registered.
     *
     * @param name the table name; must not be null
     * @return an Optional containing the metadata, or empty if not found
     */
    Optional<TableMetadata> get(String name) {
        Objects.requireNonNull(name, "name must not be null");
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Returns metadata for all known tables.
     *
     * @return an unmodifiable collection of table metadata; never null
     */
    Collection<TableMetadata> list() {
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Returns the directory path for a given table.
     *
     * @param name the table name; must not be null
     * @return the table's subdirectory path; never null
     */
    Path tableDirectory(String name) {
        Objects.requireNonNull(name, "name must not be null");
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Returns true if the catalog is still loading (scanning the root directory).
     *
     * @return true if loading is in progress
     */
    boolean isLoading() {
        throw new UnsupportedOperationException("Not implemented");
    }

    @Override
    public void close() throws IOException {
        throw new UnsupportedOperationException("Not implemented");
    }
}
