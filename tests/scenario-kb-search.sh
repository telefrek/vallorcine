#!/usr/bin/env bash
# Scenario: kb-search correctly ranks KB entries using BM25
#
# Tests two-phase ranking:
#   Phase 1: coarse ranking over category CLAUDE.md indexes
#   Phase 2: enriched ranking with subject file frontmatter weights
#
# Also verifies: empty KB, missing root, top-N limit, output format,
# and Python/Node parity.
#
# Run from repo root: bash tests/scenario-kb-search.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-kb-search"

# ── Test helpers ─────────────────────────────────────────────────────────────

passed=0
failed=0
skipped=0
total=0

pass() {
    ((passed++)) || true
    ((total++)) || true
    echo "  PASS  $1"
}

fail() {
    ((failed++)) || true
    ((total++)) || true
    echo "  FAIL  $1"
    [[ -n "${2:-}" ]] && echo "        $2"
}

skip() {
    ((skipped++)) || true
    ((total++)) || true
    echo "  SKIP  $1"
}

cleanup() {
    rm -rf "$TEST_BASE" 2>/dev/null || true
}
trap cleanup EXIT

echo ""
echo "scenario: kb-search BM25 ranking"
echo "────────────────────────────────────────────────"

# ── Setup: create a test KB structure ────────────────────────────────────────

cleanup
mkdir -p "$TEST_BASE"

KB="$TEST_BASE/kb"

# Topic: algorithms, categories: vector-indexing, sorting
mkdir -p "$KB/algorithms/vector-indexing"
mkdir -p "$KB/algorithms/sorting"

# Topic: systems, categories: caching, partitioning
mkdir -p "$KB/systems/caching"
mkdir -p "$KB/systems/partitioning"

# Topic: ml, category: embeddings
mkdir -p "$KB/ml/embeddings"

# Root CLAUDE.md
cat > "$KB/CLAUDE.md" << 'EOF'
# Knowledge Base

## Topic Map
| Topic | Categories | Files | Last Updated |
|-------|------------|-------|--------------|
| algorithms | 2 | 4 | 2026-04-01 |
| systems | 2 | 2 | 2026-04-01 |
| ml | 1 | 2 | 2026-04-01 |
EOF

# ── Category: algorithms/vector-indexing ─────────────────────────────────────

cat > "$KB/algorithms/vector-indexing/CLAUDE.md" << 'EOF'
# Vector Indexing — Category Index
*Topic: algorithms*
*Tags: hnsw, ivf, vector, similarity, approximate, nearest-neighbor, indexing*

Algorithms for approximate nearest neighbor search in high-dimensional vector spaces.

## Contents

| File | Subject | Status | Key Metric | Best For |
|------|---------|--------|------------|----------|
| [hnsw.md](hnsw.md) | HNSW Graph | mature | O(log n) query | Low-latency vector search |
| [ivf-flat.md](ivf-flat.md) | IVF Flat | stable | O(sqrt n) query | Memory-constrained environments |

## Comparison Summary
HNSW is faster for queries; IVF-Flat uses less memory.

## Research Gaps
- Product quantization (PQ) not yet documented
EOF

cat > "$KB/algorithms/vector-indexing/hnsw.md" << 'EOF'
---
title: "Hierarchical Navigable Small World"
aliases: ["HNSW", "hnsw-graph"]
tags: ["vector-search", "approximate-nearest-neighbor", "graph-index"]
complexity:
  time_query: "O(log n)"
  space: "O(n * M)"
research_status: "mature"
confidence: "high"
last_researched: "2026-03-15"
applies_to: []
related: []
decision_refs: []
sources:
  - url: "https://arxiv.org/abs/1603.09320"
    title: "Efficient and robust approximate nearest neighbor using HNSW"
    accessed: "2026-03-15"
    type: "paper"
---

# Hierarchical Navigable Small World

## summary
HNSW is a graph-based approximate nearest neighbor algorithm that builds
a multi-layer navigable small world graph for fast similarity search.
It achieves logarithmic query time with high recall.
EOF

cat > "$KB/algorithms/vector-indexing/ivf-flat.md" << 'EOF'
---
title: "Inverted File Index (Flat)"
aliases: ["IVF", "ivf-flat"]
tags: ["vector-search", "clustering", "inverted-index"]
complexity:
  time_query: "O(sqrt n)"
  space: "O(n)"
research_status: "stable"
confidence: "high"
last_researched: "2026-03-10"
applies_to: []
related: []
decision_refs: []
sources:
  - url: "https://github.com/facebookresearch/faiss"
    title: "FAISS library"
    accessed: "2026-03-10"
    type: "repo"
---

# Inverted File Index (Flat)

## summary
IVF-Flat partitions the vector space into clusters using k-means, then
searches only the closest clusters at query time. Lower memory footprint
than graph-based methods, suitable for memory-constrained deployments.
EOF

# ── Category: algorithms/sorting ─────────────────────────────────────────────

cat > "$KB/algorithms/sorting/CLAUDE.md" << 'EOF'
# Sorting — Category Index
*Topic: algorithms*
*Tags: sort, merge, quick, heap, comparison, stable*

Comparison-based and non-comparison sorting algorithms.

## Contents

| File | Subject | Status | Key Metric | Best For |
|------|---------|--------|------------|----------|
| [merge-sort.md](merge-sort.md) | Merge Sort | stable | O(n log n) | Stable sorting of linked lists |
| [radix-sort.md](radix-sort.md) | Radix Sort | mature | O(nk) | Integer key sorting |

## Research Gaps
- TimSort not yet documented
EOF

cat > "$KB/algorithms/sorting/merge-sort.md" << 'EOF'
---
title: "Merge Sort"
aliases: ["mergesort"]
tags: ["sorting", "divide-and-conquer", "stable-sort"]
research_status: "stable"
confidence: "high"
last_researched: "2026-02-20"
applies_to: []
related: []
decision_refs: []
---

# Merge Sort

## summary
A stable comparison-based sorting algorithm using divide-and-conquer.
Guaranteed O(n log n) time complexity for all inputs.
EOF

cat > "$KB/algorithms/sorting/radix-sort.md" << 'EOF'
---
title: "Radix Sort"
aliases: ["radix", "lsd-sort"]
tags: ["sorting", "non-comparison", "integer-sort"]
research_status: "mature"
confidence: "high"
last_researched: "2026-02-20"
applies_to: []
related: []
decision_refs: []
---

# Radix Sort

## summary
A non-comparison integer sorting algorithm that processes digits from
least significant to most significant. Achieves O(nk) where k is the
number of digits.
EOF

# ── Category: systems/caching ────────────────────────────────────────────────

cat > "$KB/systems/caching/CLAUDE.md" << 'EOF'
# Caching — Category Index
*Topic: systems*
*Tags: cache, eviction, lru, lfu, ttl, redis, memcached*

Caching strategies, eviction policies, and distributed cache architectures.

## Contents

| File | Subject | Status | Key Metric | Best For |
|------|---------|--------|------------|----------|
| [lru-eviction.md](lru-eviction.md) | LRU Eviction | mature | O(1) ops | General-purpose caching |

## Research Gaps
- Write-through vs write-back not yet documented
EOF

cat > "$KB/systems/caching/lru-eviction.md" << 'EOF'
---
title: "LRU Eviction Policy"
aliases: ["LRU", "least-recently-used"]
tags: ["caching", "eviction", "data-structures"]
research_status: "mature"
confidence: "high"
last_researched: "2026-03-01"
applies_to: []
related: []
decision_refs: []
---

# LRU Eviction Policy

## summary
Least Recently Used eviction removes the entry that has not been accessed
for the longest time. Implemented with a doubly-linked list and hash map
for O(1) get/put operations.
EOF

# ── Category: systems/partitioning ───────────────────────────────────────────

cat > "$KB/systems/partitioning/CLAUDE.md" << 'EOF'
# Partitioning — Category Index
*Topic: systems*
*Tags: partition, shard, consistent-hashing, range, hash, rebalancing*

Data partitioning strategies for distributed systems.

## Contents

| File | Subject | Status | Key Metric | Best For |
|------|---------|--------|------------|----------|
| [consistent-hashing.md](consistent-hashing.md) | Consistent Hashing | mature | O(log n) lookup | Elastic cluster scaling |

## Research Gaps
- Range partitioning not yet documented
EOF

cat > "$KB/systems/partitioning/consistent-hashing.md" << 'EOF'
---
title: "Consistent Hashing"
aliases: ["hash-ring", "virtual-nodes"]
tags: ["distributed-systems", "partitioning", "load-balancing"]
research_status: "mature"
confidence: "high"
last_researched: "2026-03-05"
applies_to: []
related: []
decision_refs: []
---

# Consistent Hashing

## summary
Consistent hashing maps data to nodes using a hash ring, minimizing
redistribution when nodes are added or removed. Virtual nodes improve
balance across heterogeneous clusters.
EOF

# ── Category: ml/embeddings ──────────────────────────────────────────────────

cat > "$KB/ml/embeddings/CLAUDE.md" << 'EOF'
# Embeddings — Category Index
*Topic: ml*
*Tags: embedding, word2vec, transformer, sentence, vector, representation*

Vector representations of text, images, and other data types.

## Contents

| File | Subject | Status | Key Metric | Best For |
|------|---------|--------|------------|----------|
| [word2vec.md](word2vec.md) | Word2Vec | mature | 300d default | Word similarity tasks |
| [sentence-transformers.md](sentence-transformers.md) | Sentence Transformers | active | 768d default | Semantic similarity |

## Research Gaps
- Vision transformers for image embeddings not documented
EOF

cat > "$KB/ml/embeddings/word2vec.md" << 'EOF'
---
title: "Word2Vec"
aliases: ["word-vectors", "CBOW", "skip-gram"]
tags: ["nlp", "word-embedding", "neural-network"]
research_status: "mature"
confidence: "high"
last_researched: "2026-01-15"
applies_to: []
related: []
decision_refs: []
---

# Word2Vec

## summary
Word2Vec learns dense vector representations of words from large text
corpora using either CBOW or skip-gram architectures. Word vectors
capture semantic relationships through vector arithmetic.
EOF

cat > "$KB/ml/embeddings/sentence-transformers.md" << 'EOF'
---
title: "Sentence Transformers"
aliases: ["SBERT", "sentence-bert"]
tags: ["nlp", "sentence-embedding", "transformer", "semantic-similarity"]
research_status: "active"
confidence: "high"
last_researched: "2026-03-20"
applies_to: []
related: ["algorithms/vector-indexing/hnsw"]
decision_refs: []
---

# Sentence Transformers

## summary
Sentence Transformers produce fixed-size embeddings for sentences and
paragraphs, enabling efficient semantic similarity search. Built on
BERT-family models fine-tuned with siamese and triplet networks.
EOF

echo ""
echo "── Test KB structure created ──"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Tests
# ══════════════════════════════════════════════════════════════════════════════

# ── Test 1: Tags match ───────────────────────────────────────────────────────

echo "── Test 1: Tags match (vector indexing) ──"
output=$(python3 "$REPO_ROOT/scripts/kb-search.py" "vector indexing HNSW" "$KB" 10 2>/dev/null || true)

if echo "$output" | grep -q "algorithms/vector-indexing/hnsw"; then
    pass "HNSW found in results for 'vector indexing HNSW'"
else
    fail "HNSW not found in results" "$output"
fi

# ── Test 2: Contents table Best For match ────────────────────────────────────

echo "── Test 2: Best For match (memory constrained) ──"
output=$(python3 "$REPO_ROOT/scripts/kb-search.py" "memory constrained environments" "$KB" 10 2>/dev/null || true)

if echo "$output" | grep -q "algorithms/vector-indexing/ivf-flat"; then
    pass "IVF-Flat found for 'memory constrained environments'"
else
    fail "IVF-Flat not found" "$output"
fi

# ── Test 3: Title weight boost ───────────────────────────────────────────────

echo "── Test 3: Title weight boost ──"
# "Consistent Hashing" is the title of one subject — should rank above entries
# that only mention hashing in passing
output=$(python3 "$REPO_ROOT/scripts/kb-search.py" "consistent hashing distributed" "$KB" 10 2>/dev/null || true)

first_result=$(echo "$output" | head -1)
if echo "$first_result" | grep -q "systems/partitioning/consistent-hashing"; then
    pass "Consistent hashing ranked first (title weight)"
else
    fail "Consistent hashing not ranked first" "$first_result"
fi

# ── Test 4: Aliases weight boost ─────────────────────────────────────────────

echo "── Test 4: Aliases weight boost ──"
# "SBERT" is only in aliases of sentence-transformers, not in title or body
output=$(python3 "$REPO_ROOT/scripts/kb-search.py" "SBERT sentence embedding" "$KB" 10 2>/dev/null || true)

if echo "$output" | grep -q "ml/embeddings/sentence-transformers"; then
    pass "Sentence Transformers found via alias 'SBERT'"
else
    fail "Sentence Transformers not found via SBERT alias" "$output"
fi

# ── Test 5: Off-topic excluded ───────────────────────────────────────────────

echo "── Test 5: Off-topic excluded ──"
# Query about vector search should not return caching or sorting results
output=$(python3 "$REPO_ROOT/scripts/kb-search.py" "approximate nearest neighbor vector search" "$KB" 10 2>/dev/null || true)

if echo "$output" | grep -q "systems/caching"; then
    fail "Caching incorrectly appeared in vector search results" "$output"
else
    pass "Caching correctly excluded from vector search results"
fi

if echo "$output" | grep -q "algorithms/sorting"; then
    fail "Sorting incorrectly appeared in vector search results" "$output"
else
    pass "Sorting correctly excluded from vector search results"
fi

# ── Test 6: Empty KB ─────────────────────────────────────────────────────────

echo "── Test 6: Empty KB ──"
empty_kb="$TEST_BASE/empty-kb"
mkdir -p "$empty_kb"

output=$(python3 "$REPO_ROOT/scripts/kb-search.py" "anything" "$empty_kb" 10 2>/dev/null || true)

if [[ -z "$output" ]]; then
    pass "Empty KB produces empty output"
else
    fail "Empty KB produced unexpected output" "$output"
fi

# ── Test 7: Missing KB root ─────────────────────────────────────────────────

echo "── Test 7: Missing KB root ──"
output=$(python3 "$REPO_ROOT/scripts/kb-search.py" "anything" "/tmp/vallorcine/nonexistent-kb-root" 10 2>/dev/null || true)
exit_code=$?

if [[ -z "$output" ]] && [[ $exit_code -eq 0 ]]; then
    pass "Missing KB root: empty output, exit 0"
else
    fail "Missing KB root: unexpected output or exit code" "output='$output' exit=$exit_code"
fi

# ── Test 8: Top-N limit ─────────────────────────────────────────────────────

echo "── Test 8: Top-N limit ──"
# Use a broad query that should match many subjects
output=$(python3 "$REPO_ROOT/scripts/kb-search.py" "algorithm data structure search sort" "$KB" 3 2>/dev/null || true)
line_count=$(echo "$output" | grep -c '.' || true)

if [[ $line_count -le 3 ]]; then
    pass "Top-3 limit respected (got $line_count results)"
else
    fail "Top-3 limit exceeded: got $line_count results" "$output"
fi

# ── Test 9: Output format ───────────────────────────────────────────────────

echo "── Test 9: Output format ──"
output=$(python3 "$REPO_ROOT/scripts/kb-search.py" "vector indexing HNSW" "$KB" 5 2>/dev/null || true)

format_ok=true
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Expected: <float>  <topic>/<category>/<subject>
    if ! echo "$line" | grep -qE '^[0-9]+\.[0-9]+  [a-z]'; then
        format_ok=false
        fail "Output line has wrong format" "$line"
        break
    fi
done <<< "$output"

if $format_ok && [[ -n "$output" ]]; then
    pass "All output lines match expected format"
fi

# ── Test 10: Python/Node parity ──────────────────────────────────────────────

echo "── Test 10: Python/Node parity ──"

if command -v node &>/dev/null; then
    py_output=$(python3 "$REPO_ROOT/scripts/kb-search.py" "vector indexing approximate nearest neighbor" "$KB" 5 2>/dev/null || true)
    js_output=$(node "$REPO_ROOT/scripts/kb-search.js" "vector indexing approximate nearest neighbor" "$KB" 5 2>/dev/null || true)

    # Extract just the doc IDs (second field) for ordering comparison
    py_order=$(echo "$py_output" | awk '{print $2}' | head -3)
    js_order=$(echo "$js_output" | awk '{print $2}' | head -3)

    if [[ "$py_order" == "$js_order" ]]; then
        pass "Python and Node top-3 ordering matches"
    else
        fail "Python/Node ordering mismatch" "Python: $py_order | Node: $js_order"
    fi
else
    skip "Node.js not available for parity test"
fi

# ── Test 11: Bash wrapper delegates correctly ────────────────────────────────

echo "── Test 11: Bash wrapper ──"
output=$(bash "$REPO_ROOT/scripts/kb-search.sh" "vector indexing HNSW" --kb-root "$KB" --top 5 2>/dev/null || true)

if echo "$output" | grep -q "algorithms/vector-indexing/hnsw"; then
    pass "Wrapper found HNSW via delegation"
else
    fail "Wrapper did not find HNSW" "$output"
fi

# ── Test 12: Node.js direct ─────────────────────────────────────────────────

echo "── Test 12: Node.js direct ──"
if command -v node &>/dev/null; then
    output=$(node "$REPO_ROOT/scripts/kb-search.js" "consistent hashing distributed" "$KB" 5 2>/dev/null || true)

    if echo "$output" | grep -q "systems/partitioning/consistent-hashing"; then
        pass "Node.js finds consistent hashing directly"
    else
        fail "Node.js did not find consistent hashing" "$output"
    fi
else
    skip "Node.js not available"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "────────────────────────────────────────────────"
echo "Results: $passed passed, $failed failed, $skipped skipped (of $total)"
echo "────────────────────────────────────────────────"

if [[ $failed -gt 0 ]]; then
    exit 1
fi
exit 0
