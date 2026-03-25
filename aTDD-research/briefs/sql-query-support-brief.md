---
slug: sql-query-support
title: SQL Query Support
created: 2026-03-16
---

# SQL Query Support

## Problem
Users comfortable with SQL should be able to query `JlsmTable` using familiar
SQL SELECT syntax instead of (or in addition to) the fluent `TableQuery` API.
The library does not support the full SQL specification — no CTEs, window
functions, subqueries, joins, or write operations. Vector similarity search
and full-text match require custom syntax extensions.

## Scope
- **Read-only**: SELECT queries only (no INSERT, UPDATE, DELETE)
- **New module**: `jlsm-sql` — optional dependency, keeps `jlsm-table` lean
- **Architecture**: SQL string → SQL AST → translate to fluent API / Predicate tree

## Supported SQL Subset

### SELECT
- `SELECT *` — all fields
- `SELECT field1, field2, ...` — column projection
- `SELECT field AS alias` — column aliasing

### FROM
- `FROM tableName` — single table (no joins, no subqueries)

### WHERE (maps to existing Predicate types)
- `=`, `!=` / `<>` → `Predicate.Eq`, `Predicate.Ne`
- `>`, `>=`, `<`, `<=` → `Predicate.Gt`, `Predicate.Gte`, `Predicate.Lt`, `Predicate.Lte`
- `BETWEEN low AND high` → `Predicate.Between`
- `AND`, `OR` → `Predicate.And`, `Predicate.Or`
- Parenthesized grouping for precedence
- `MATCH(field, 'query text')` → `Predicate.FullTextMatch`
- Vector syntax TBD (research needed — e.g., `NEAREST(field, ?, k)`)

### ORDER BY
- `ORDER BY field [ASC|DESC]` — single or multiple columns

### LIMIT / OFFSET
- `LIMIT n`
- `OFFSET n`

### Literals
- String literals: `'single-quoted'`
- Numeric literals: integers and decimals
- Boolean: `TRUE`, `FALSE`
- NULL: `IS NULL`, `IS NOT NULL`
- Bind parameters: `?` positional placeholders

## Out of Scope
- Joins, subqueries, CTEs, window functions
- Aggregate functions (COUNT, SUM, AVG, etc.)
- GROUP BY / HAVING
- INSERT, UPDATE, DELETE
- UNION / INTERSECT / EXCEPT
- CREATE TABLE / DDL

## Architecture

```
SQL string
    ↓
  Lexer (tokenizer)
    ↓
  Parser (recursive descent)
    ↓
  SQL AST (module-internal representation)
    ↓
  Translator (AST → TableQuery + Predicate tree)
    ↓
  TableQuery<K>.execute()
```

### SQL AST
Intermediate representation covering the full SELECT statement structure:
- SelectStatement: columns, table, where, orderBy, limit, offset
- Column projections (field, alias, wildcard)
- Expression tree for WHERE (maps to Predicate but preserves SQL semantics)
- OrderBy clauses

The AST enables future query validation, optimization, and error reporting
before translation to the fluent API.

### Module Dependencies
- `jlsm-sql` requires `jlsm.table` (for Predicate, TableQuery, JlsmSchema)
- `jlsm-sql` requires `jlsm.core` (transitive via jlsm-table)

## Open Questions
- Vector similarity search syntax — research needed for domain-appropriate
  keyword (NEAREST, SIMILAR_TO, VECTOR_SEARCH, etc.)
- Whether to support nested field access in SQL (e.g., `address.city`)
