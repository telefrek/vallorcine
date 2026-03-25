---
feature: "sql-query-support"
created: "2026-03-16"
language: "Java 25"
---

# Work Plan — sql-query-support

## References
- Brief: [brief.md](brief.md)
- Domains: [domains.md](domains.md)
- KB: [.kb/algorithms/sql-extensions/vector-similarity-sql-syntax.md](../../.kb/algorithms/sql-extensions/vector-similarity-sql-syntax.md)

## Existing Constructs

| Construct | File | Usage |
|-----------|------|-------|
| Predicate | modules/jlsm-table/src/main/java/jlsm/table/Predicate.java | use — SQL WHERE → Predicate tree (Eq, Ne, Gt, Gte, Lt, Lte, Between, And, Or, FullTextMatch, VectorNearest) |
| TableQuery\<K\> | modules/jlsm-table/src/main/java/jlsm/table/TableQuery.java | use — translator builds query components that map to this API |
| JlsmSchema | modules/jlsm-table/src/main/java/jlsm/table/JlsmSchema.java | use — validate column names and types at translation time |
| FieldType | modules/jlsm-table/src/main/java/jlsm/table/FieldType.java | use — type-check literals against field definitions |
| JlsmTable | modules/jlsm-table/src/main/java/jlsm/table/JlsmTable.java | use — execution target for translated queries |

## New Constructs

| Construct | File | Contract summary |
|-----------|------|-----------------|
| TokenType | modules/jlsm-sql/src/main/java/jlsm/sql/TokenType.java | Enum of all token types for lexing |
| Token | modules/jlsm-sql/src/main/java/jlsm/sql/Token.java | Record: (type, text, position) |
| SqlParseException | modules/jlsm-sql/src/main/java/jlsm/sql/SqlParseException.java | Checked exception with position info |
| SqlLexer | modules/jlsm-sql/src/main/java/jlsm/sql/SqlLexer.java | SQL string → List\<Token\> |
| SqlAst | modules/jlsm-sql/src/main/java/jlsm/sql/SqlAst.java | Sealed hierarchy: SelectStatement, Column, Expression, OrderByClause |
| SqlParser | modules/jlsm-sql/src/main/java/jlsm/sql/SqlParser.java | List\<Token\> → SqlAst.SelectStatement |
| SqlQuery | modules/jlsm-sql/src/main/java/jlsm/sql/SqlQuery.java | Record: translated result (predicate, projections, aliases, orderBy, limit, offset, vectorDistance) |
| SqlTranslator | modules/jlsm-sql/src/main/java/jlsm/sql/SqlTranslator.java | SqlAst.SelectStatement + JlsmSchema → SqlQuery |
| JlsmSql | modules/jlsm-sql/src/main/java/jlsm/sql/JlsmSql.java | Public entry point: parse(sql, schema) → SqlQuery |

## Stub Files Written

| File | Status |
|------|--------|
| modules/jlsm-sql/build.gradle | created |
| modules/jlsm-sql/src/main/java/module-info.java | created |
| modules/jlsm-sql/src/main/java/jlsm/sql/TokenType.java | stubbed |
| modules/jlsm-sql/src/main/java/jlsm/sql/Token.java | stubbed |
| modules/jlsm-sql/src/main/java/jlsm/sql/SqlParseException.java | stubbed |
| modules/jlsm-sql/src/main/java/jlsm/sql/SqlLexer.java | stubbed |
| modules/jlsm-sql/src/main/java/jlsm/sql/SqlAst.java | stubbed |
| modules/jlsm-sql/src/main/java/jlsm/sql/SqlParser.java | stubbed |
| modules/jlsm-sql/src/main/java/jlsm/sql/SqlQuery.java | stubbed |
| modules/jlsm-sql/src/main/java/jlsm/sql/SqlTranslator.java | stubbed |
| modules/jlsm-sql/src/main/java/jlsm/sql/JlsmSql.java | stubbed |

## Contract Definitions

### TokenType
**File:** `modules/jlsm-sql/src/main/java/jlsm/sql/TokenType.java`
**Signature:** `public enum TokenType`
**Contract:**
- Enum constants for: SQL keywords (SELECT, FROM, WHERE, AND, OR, NOT, ORDER, BY, ASC, DESC, LIMIT, OFFSET, BETWEEN, IS, NULL, TRUE, FALSE, AS, LIKE, IN), built-in functions (MATCH, VECTOR_DISTANCE), identifier, literals (STRING_LITERAL, NUMBER_LITERAL), PARAMETER, punctuation (COMMA, DOT, STAR, LPAREN, RPAREN), comparison operators (EQ, NE, LT, LTE, GT, GTE), EOF

### Token
**File:** `modules/jlsm-sql/src/main/java/jlsm/sql/Token.java`
**Signature:** `public record Token(TokenType type, String text, int position)`
**Contract:**
- Receives: type (non-null), text (non-null), position (>= 0)
- Returns: immutable record
- Error conditions: NullPointerException on null type/text, IllegalArgumentException on negative position

### SqlParseException
**File:** `modules/jlsm-sql/src/main/java/jlsm/sql/SqlParseException.java`
**Signature:** `public final class SqlParseException extends Exception`
**Contract:**
- Carries position (zero-based char offset, or -1 if unknown)
- Checked exception — forces callers to handle parse failures

### SqlLexer
**File:** `modules/jlsm-sql/src/main/java/jlsm/sql/SqlLexer.java`
**Signature:** `public List<Token> tokenize(String sql) throws SqlParseException`
**Contract:**
- Receives: non-null SQL string
- Returns: immutable List\<Token\> always ending with EOF
- Side effects: none (stateless)
- Error conditions: SqlParseException on unrecognised characters or unterminated string literals
- Keywords are case-insensitive (matched after uppercasing)
- String literals are single-quoted, with `''` escape for embedded quotes
- Numeric literals: integers and decimals (no scientific notation needed)
- Whitespace is consumed but not emitted

### SqlAst
**File:** `modules/jlsm-sql/src/main/java/jlsm/sql/SqlAst.java`
**Signature:** `public sealed interface SqlAst`
**Contract:**
- SelectStatement: columns, table, where (Optional), orderBy (List), limit (Optional), offset (Optional)
- Column: sealed — Wildcard | Named(name, alias)
- Expression: sealed — Comparison, Logical, Not, Between, IsNull, ColumnRef, StringLiteral, NumberLiteral, BooleanLiteral, Parameter, FunctionCall
- ComparisonOp: EQ, NE, LT, LTE, GT, GTE
- LogicalOp: AND, OR
- OrderByClause: expression + ascending flag
- All records validate non-null in compact constructors
- Immutable — lists are defensively copied

### SqlParser
**File:** `modules/jlsm-sql/src/main/java/jlsm/sql/SqlParser.java`
**Signature:** `public SqlAst.SelectStatement parse(List<Token> tokens) throws SqlParseException`
**Contract:**
- Receives: non-null, non-empty token list from SqlLexer
- Returns: parsed SelectStatement AST
- Side effects: none
- Error conditions: SqlParseException on syntax errors, unexpected tokens, or unsupported constructs (INSERT, UPDATE, DELETE, JOIN, subqueries)
- Grammar: recursive descent with standard precedence (OR < AND < NOT < comparison < primary)
- Rejects non-SELECT statements with clear error messages

### SqlQuery
**File:** `modules/jlsm-sql/src/main/java/jlsm/sql/SqlQuery.java`
**Signature:** `public record SqlQuery(Optional<Predicate> predicate, List<String> projections, List<String> aliases, List<OrderBy> orderBy, OptionalInt limit, OptionalInt offset, Optional<VectorDistanceOrder> vectorDistance)`
**Contract:**
- Immutable record holding the translated query components
- projections: empty list means SELECT * (all columns)
- aliases: parallel to projections, empty string if no alias
- Nested records: OrderBy(field, ascending), VectorDistanceOrder(field, parameterIndex, metric)

### SqlTranslator
**File:** `modules/jlsm-sql/src/main/java/jlsm/sql/SqlTranslator.java`
**Signature:** `public SqlQuery translate(SqlAst.SelectStatement statement, JlsmSchema schema) throws SqlParseException`
**Contract:**
- Receives: parsed AST + target schema
- Returns: SqlQuery with Predicate tree, projections, ordering, limits
- Side effects: none
- Error conditions: SqlParseException if column not in schema, type mismatch, MATCH on non-STRING field, VECTOR_DISTANCE on non-vector field
- Translation: Comparison → leaf Predicate; AND/OR → composite Predicate; BETWEEN → Predicate.Between; MATCH → Predicate.FullTextMatch; VECTOR_DISTANCE in ORDER BY → VectorDistanceOrder
- Governed by: domains.md vector syntax decision (VECTOR_DISTANCE function pattern)

### JlsmSql
**File:** `modules/jlsm-sql/src/main/java/jlsm/sql/JlsmSql.java`
**Signature:** `public static SqlQuery parse(String sql, JlsmSchema schema) throws SqlParseException`
**Contract:**
- Receives: non-null, non-blank SQL string + non-null schema
- Returns: SqlQuery (composes lexer → parser → translator)
- Side effects: none
- Error conditions: SqlParseException on any lexing, parsing, or validation error

---

## Work Units

### WU-1: Lexer + Parser + AST
**Constructs:** TokenType, Token, SqlParseException, SqlLexer, SqlAst, SqlParser
**Depends on:** none (no jlsm-table types needed)
**Est. session load:** ~17K

### WU-2: Translator + Public API
**Constructs:** SqlQuery, SqlTranslator, JlsmSql
**Depends on:** WU-1 public interface (SqlAst records, SqlParseException)
**Est. session load:** ~14K

## Implementation Order
1. WU-1 — Lexer + Parser + AST (no dependencies)
2. WU-2 — Translator + Public API (depends on WU-1)
