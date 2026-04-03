# Pass 1 — Construct Inventory with Relationships

You are building an inventory of every construct in the audit scope AND the
relationships between them. This is a mechanical task — read the code and list
what exists and what connects to what. Do not analyze for bugs, do not reason
about correctness, do not skip anything.

## Input

Read the audit scope file for the list of implementation files.

## Task

### Part A: Construct Inventory

For each implementation file in scope, read it and list every construct:

- **Classes** (public, package-private, inner)
- **Records/structs/dataclasses** (including compact constructors)
- **Interfaces/traits/protocols**
- **Methods/functions** (public and package-private — skip private unless they
  do significant work like allocation, I/O, or deserialization)
- **Inner types** (nested classes, anonymous classes, enums, variants)

For each construct, record:
- Name (fully qualified: `ClassName.methodName` or `Outer.Inner`)
- Kind (class, record, interface, method, inner-class, enum, struct, trait, function)
- Line range (start-end)
- One-line summary of what it does (from reading the code, not documentation comments)
- Parameters and return type (for methods/functions)
- Mutability: does it hold mutable state? (for types)
- Visibility: public, package-private/crate, private, or equivalent

### Part B: Relationship Edges

After inventorying each file, list the relationships between constructs you
have inventoried. Only record edges where BOTH endpoints are in the inventory
(i.e., both are in-scope constructs). Ignore references to standard library
types, third-party types, or constructs outside the audit scope.

Edge types to record:

| Edge type | Meaning | Example |
|-----------|---------|---------|
| `uses_type` | A has a parameter, return type, or field of type B | method accepts or returns an in-scope type |
| `calls` | A invokes B | one method calls another |
| `creates` | A instantiates B | factory method creates an in-scope type |
| `inherits` | A extends, implements, or derives from B | subtype implements an in-scope interface or trait |
| `contains` | B is defined inside A | outer type contains a nested type |
| `reads_field` | A reads a field defined in B | method accesses a field on an in-scope record or type |
| `shares_state` | A and B are methods/constructs on the same mutable type that both access the same mutable field or resource (a handle, a flag, a collection). Both endpoints must be in the inventory. | two methods that both read/write a shared connection handle |
| `data_flow` | A produces data that B consumes (not via direct call — includes writing a format that another construct reads, or populating a structure that another construct interprets) | serializer writes a binary format that deserializer parses; encoder produces bytes that decoder consumes |

For `data_flow` edges: note what data flows and whether it crosses a trust
boundary (e.g., data read from disk or network, user-provided input,
deserialized from untrusted bytes).

Record edges as a flat list per file — source construct, edge type, target
construct:

```
SourceConstruct -> TargetConstruct [edge_type]
```

If a construct has no in-scope edges, omit it from the edge list (don't write
"no edges").

## Output

Write the construct inventory file:

```markdown
# Construct Inventory — <feature-name>

## <FileName>

### Constructs

| Construct | Kind | Lines | Summary | Params/Returns | Mutable | Visibility |
|-----------|------|-------|---------|----------------|---------|------------|
| TypeName | class | 1-200 | ... | — | yes/no | public |
| TypeName.methodName | method | 45-80 | ... | (Type, Type) → Type | — | public |

### Edges

- TypeName.methodA -> TypeName.methodB [calls]
- TypeName -> OtherType [inherits]
- TypeName.method -> OtherType [uses_type]
- TypeName.factory -> TypeName [creates]
- TypeName.methodA -> TypeName.methodB [shares_state: fieldName]
- Producer.write -> Consumer.read [data_flow: serialized bytes via disk, untrusted]
```

One section per file. Include EVERY construct — completeness is the only
goal for the inventory. For edges, completeness matters but within-scope
only — do not chase references to types outside the audit scope.

Write the file and return a single summary line:
```
inventory: <n> files, <n> constructs, <n> edges
```
