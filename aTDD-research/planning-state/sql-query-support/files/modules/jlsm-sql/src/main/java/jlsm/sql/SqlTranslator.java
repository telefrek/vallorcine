package jlsm.sql;

import java.util.Objects;

import jlsm.table.JlsmSchema;

/**
 * Translates a {@link SqlAst.SelectStatement} into a {@link SqlQuery}.
 *
 * <p>Contract:
 * <ul>
 *   <li>Receives: a parsed AST and the target table's {@link JlsmSchema}</li>
 *   <li>Returns: a {@link SqlQuery} with the predicate tree, projections, ordering, and limits</li>
 *   <li>Side effects: none</li>
 *   <li>Error conditions: throws {@link SqlParseException} if:
 *       <ul>
 *         <li>A column name in SELECT/WHERE/ORDER BY does not exist in the schema</li>
 *         <li>A literal type is incompatible with the field type</li>
 *         <li>MATCH is used on a non-STRING field</li>
 *         <li>VECTOR_DISTANCE is used on a non-vector field</li>
 *         <li>An unsupported expression structure is encountered</li>
 *       </ul>
 *   </li>
 * </ul>
 *
 * <p>Translation rules:
 * <ul>
 *   <li>Comparison expressions → leaf Predicates (Eq, Ne, Gt, Gte, Lt, Lte)</li>
 *   <li>BETWEEN → Predicate.Between</li>
 *   <li>AND/OR → Predicate.And / Predicate.Or</li>
 *   <li>MATCH(field, query) → Predicate.FullTextMatch</li>
 *   <li>VECTOR_DISTANCE(field, vec, metric) in ORDER BY → SqlQuery.VectorDistanceOrder</li>
 *   <li>Column aliases are preserved in SqlQuery for result projection</li>
 * </ul>
 *
 * <p>Governed by: domains.md — Vector Similarity SQL Syntax section,
 * .kb/algorithms/sql-extensions/vector-similarity-sql-syntax.md
 */
public final class SqlTranslator {

    /**
     * Translates a parsed SQL AST into a SqlQuery.
     *
     * @param statement the parsed SELECT statement, must not be null
     * @param schema    the target table schema for validation, must not be null
     * @return the translated query
     * @throws SqlParseException if the AST references invalid fields or has type mismatches
     */
    public SqlQuery translate(SqlAst.SelectStatement statement, JlsmSchema schema)
            throws SqlParseException {
        Objects.requireNonNull(statement, "statement");
        Objects.requireNonNull(schema, "schema");
        throw new UnsupportedOperationException("Not implemented");
    }
}
