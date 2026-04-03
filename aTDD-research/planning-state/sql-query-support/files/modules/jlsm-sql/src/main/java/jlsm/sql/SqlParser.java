package jlsm.sql;

import java.util.List;
import java.util.Objects;

/**
 * Recursive descent parser for the supported SQL SELECT subset.
 *
 * <p>Contract:
 * <ul>
 *   <li>Receives: a non-null, non-empty list of {@link Token}s (from {@link SqlLexer})</li>
 *   <li>Returns: a {@link SqlAst.SelectStatement} representing the parsed query</li>
 *   <li>Side effects: none</li>
 *   <li>Error conditions: throws {@link SqlParseException} with position info on
 *       syntax errors, unexpected tokens, or unsupported SQL constructs
 *       (INSERT, UPDATE, DELETE, JOIN, subqueries, etc.)</li>
 * </ul>
 *
 * <p>Grammar (simplified):
 * <pre>
 * selectStatement := SELECT columnList FROM tableName
 *                    [WHERE expression]
 *                    [ORDER BY orderByList]
 *                    [LIMIT number]
 *                    [OFFSET number]
 *
 * columnList      := STAR | column (COMMA column)*
 * column          := identifier [AS identifier]
 * expression      := orExpr
 * orExpr          := andExpr (OR andExpr)*
 * andExpr         := notExpr (AND notExpr)*
 * notExpr         := NOT notExpr | comparison
 * comparison      := primary compareOp primary
 *                  | primary BETWEEN primary AND primary
 *                  | primary IS [NOT] NULL
 * primary         := literal | columnRef | parameter | functionCall | LPAREN expression RPAREN
 * functionCall    := MATCH LPAREN args RPAREN | VECTOR_DISTANCE LPAREN args RPAREN
 * </pre>
 *
 * <p>Governed by: brief.md — Architecture section (recursive descent parser).
 */
public final class SqlParser {

    /**
     * Parses a list of tokens into a SQL AST.
     *
     * @param tokens the token list from {@link SqlLexer#tokenize}, must not be null or empty
     * @return the parsed SELECT statement AST
     * @throws SqlParseException on syntax errors or unsupported SQL constructs
     */
    public SqlAst.SelectStatement parse(List<Token> tokens) throws SqlParseException {
        Objects.requireNonNull(tokens, "tokens");
        if (tokens.isEmpty()) {
            throw new SqlParseException("Empty token list", 0);
        }
        throw new UnsupportedOperationException("Not implemented");
    }
}
