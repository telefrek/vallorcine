package jlsm.sql;

import java.util.List;
import java.util.Objects;

/**
 * Tokenizes a SQL string into a list of {@link Token}s.
 *
 * <p>Contract:
 * <ul>
 *   <li>Receives: a non-null SQL string</li>
 *   <li>Returns: an immutable list of tokens, always ending with {@link TokenType#EOF}</li>
 *   <li>Side effects: none (stateless — new instance per tokenization)</li>
 *   <li>Error conditions: throws {@link SqlParseException} on unrecognised characters
 *       or unterminated string literals, with position information</li>
 * </ul>
 *
 * <p>Handles: SQL keywords (case-insensitive), single-quoted string literals,
 * numeric literals (integers and decimals), identifiers, comparison operators
 * ({@code =}, {@code !=}, {@code <>}, {@code <}, {@code <=}, {@code >}, {@code >=}),
 * punctuation, and positional bind parameters ({@code ?}).
 */
public final class SqlLexer {

    /**
     * Tokenizes the given SQL string.
     *
     * @param sql the SQL string to tokenize, must not be null
     * @return an immutable list of tokens ending with EOF
     * @throws SqlParseException if the input contains unrecognised characters
     *                           or unterminated string literals
     */
    public List<Token> tokenize(String sql) throws SqlParseException {
        Objects.requireNonNull(sql, "sql");
        throw new UnsupportedOperationException("Not implemented");
    }
}
