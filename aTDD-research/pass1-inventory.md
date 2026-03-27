# Pass 1 — Construct Inventory

You are building an inventory of every construct in the audit scope. This is
a mechanical task — read the code and list what exists. Do not analyze for
bugs, do not reason about correctness, do not skip anything.

## Input

Read `.feature/block-compression/audit-scope.md` for the list of
implementation files.

## Task

For each implementation file in scope, read it and list every construct:

- **Classes** (public, package-private, inner)
- **Records** (including compact constructors)
- **Interfaces** (including default methods)
- **Methods** (public and package-private — skip private unless they do
  significant work like allocation, I/O, or deserialization)
- **Inner types** (static inner classes, anonymous classes, enums)

For each construct, record:
- Name (fully qualified: `ClassName.methodName` or `Outer.Inner`)
- Kind (class, record, interface, method, inner-class, enum)
- Line range (start-end)
- One-line summary of what it does (from reading the code, not javadoc)
- Parameters and return type (for methods)
- Mutability: does it hold mutable state? (for classes/records)
- Visibility: public, package-private, or private

## Output

Write `.feature/block-compression/construct-inventory.md`:

```markdown
# Construct Inventory — block-compression

## <FileName.java>

| Construct | Kind | Lines | Summary | Params/Returns | Mutable | Visibility |
|-----------|------|-------|---------|----------------|---------|------------|
| ClassName | class | 1-200 | ... | — | yes/no | public |
| ClassName.methodName | method | 45-80 | ... | (Type, Type) → Type | — | public |
| ClassName.InnerType | record | 85-95 | ... | — | no | public |
```

One table per file. Include EVERY construct — completeness is the only
goal. The inventory will be validated against a known ground truth, so
missing constructs will be caught.

Write the file and return a single summary line:
```
inventory: <n> files, <n> constructs
```
