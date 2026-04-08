# Audit Pipeline Visualization Prototypes

Design document for rich visual components that replace or augment text-only
audit pipeline rendering. Each visualization is a self-contained HTML/CSS/SVG
snippet using the audit dark theme (`--bg: #0d1117`, `--surface: #161b22`).

All prototypes use inline styles and zero JavaScript dependencies. They rely
on native HTML/CSS features: CSS Grid, SVG, `<details>`/`<summary>`, and
CSS custom properties.

---

## A. Spec Analysis Coverage Map

### What it shows

A compact grid where rows are requirements (R1-R90) and columns are the 5
domain lenses. Each cell is colored by coverage status:
- **Filled (lens color)**: requirement has findings in that lens
- **Dot (muted)**: requirement is in scope but no findings generated
- **Empty**: requirement not applicable to that lens

At 90 requirements, the grid uses 8px cells so the full matrix fits in
~720px height. Hovering a row (via CSS `:hover`) highlights it with a
brighter background. Column headers are rotated 45 degrees for compactness.

A summary bar below shows per-lens coverage percentage as filled rectangles.

### Why it beats text

A text table at 90 rows is unreadable without scrolling. The grid is a
single visual -- you see coverage density, lens gaps, and requirement
clustering at a glance. Dense regions reveal where the spec has the most
attack surface. Sparse columns reveal underperforming lenses.

### Implementation

```html
<!-- Spec Analysis Coverage Map -->
<div style="
  background: #0d1117;
  border: 1px solid #30363d;
  border-radius: 8px;
  padding: 1.5rem;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
  color: #e6edf3;
  max-width: 600px;
">
  <h3 style="margin: 0 0 1rem; font-size: 1.1rem; border-bottom: 1px solid #30363d; padding-bottom: 0.5rem;">
    Spec Coverage Map
  </h3>

  <!-- Legend -->
  <div style="display: flex; gap: 1rem; margin-bottom: 0.8rem; font-size: 0.75rem; color: #8b949e;">
    <span><span style="display:inline-block;width:10px;height:10px;background:#3fb950;border-radius:2px;vertical-align:middle;"></span> Finding</span>
    <span><span style="display:inline-block;width:10px;height:10px;background:#30363d;border-radius:50%;vertical-align:middle;"></span> In scope</span>
    <span><span style="display:inline-block;width:10px;height:10px;background:transparent;border:1px solid #30363d;border-radius:2px;vertical-align:middle;"></span> N/A</span>
  </div>

  <svg viewBox="0 0 340 500" style="width: 100%; max-width: 340px;">
    <!-- Column headers (rotated) -->
    <g transform="translate(60, 0)">
      <text x="14" y="45" transform="rotate(-45, 14, 45)" style="font-size:9px;fill:#f85149;">concurrency</text>
      <text x="70" y="45" transform="rotate(-45, 70, 45)" style="font-size:9px;fill:#58a6ff;">contracts</text>
      <text x="126" y="45" transform="rotate(-45, 126, 45)" style="font-size:9px;fill:#3fb950;">data_xform</text>
      <text x="182" y="45" transform="rotate(-45, 182, 45)" style="font-size:9px;fill:#d29922;">resource_lc</text>
      <text x="238" y="45" transform="rotate(-45, 238, 45)" style="font-size:9px;fill:#bc8cff;">shared_state</text>
    </g>

    <!-- Grid area -->
    <g transform="translate(0, 55)">
      <!-- Row labels (every 5th requirement for compactness) -->
      <text x="50" y="8" text-anchor="end" style="font-size:8px;fill:#8b949e;">R1</text>
      <text x="50" y="48" text-anchor="end" style="font-size:8px;fill:#8b949e;">R5</text>
      <text x="50" y="88" text-anchor="end" style="font-size:8px;fill:#8b949e;">R10</text>
      <text x="50" y="128" text-anchor="end" style="font-size:8px;fill:#8b949e;">R15</text>
      <text x="50" y="168" text-anchor="end" style="font-size:8px;fill:#8b949e;">R20</text>
      <text x="50" y="208" text-anchor="end" style="font-size:8px;fill:#8b949e;">R25</text>
      <text x="50" y="248" text-anchor="end" style="font-size:8px;fill:#8b949e;">R30</text>
      <text x="50" y="288" text-anchor="end" style="font-size:8px;fill:#8b949e;">R35</text>
      <text x="50" y="328" text-anchor="end" style="font-size:8px;fill:#8b949e;">R40</text>
      <text x="50" y="368" text-anchor="end" style="font-size:8px;fill:#8b949e;">R45</text>
      <text x="50" y="400" text-anchor="end" style="font-size:8px;fill:#8b949e;">R50</text>

      <!-- Example rows: 50 requirements x 5 lenses, 8px cells, 2px gap -->
      <!-- Row 1: R1 - concurrency finding, contracts finding, data N/A, resource in-scope, shared finding -->
      <rect x="60"  y="0" width="8" height="8" rx="1" fill="#f85149" opacity="0.9"/>
      <rect x="116" y="0" width="8" height="8" rx="1" fill="#58a6ff" opacity="0.9"/>
      <rect x="172" y="0" width="8" height="8" rx="1" fill="none" stroke="#30363d" stroke-width="0.5"/>
      <circle cx="232" cy="4" r="2.5" fill="#30363d"/>
      <rect x="284" y="0" width="8" height="8" rx="1" fill="#bc8cff" opacity="0.9"/>

      <!-- Row 2 -->
      <rect x="60"  y="10" width="8" height="8" rx="1" fill="#f85149" opacity="0.9"/>
      <circle cx="120" cy="14" r="2.5" fill="#30363d"/>
      <rect x="172" y="10" width="8" height="8" rx="1" fill="#3fb950" opacity="0.9"/>
      <rect x="228" y="10" width="8" height="8" rx="1" fill="#d29922" opacity="0.9"/>
      <rect x="284" y="10" width="8" height="8" rx="1" fill="#bc8cff" opacity="0.9"/>

      <!-- Row 3 -->
      <circle cx="64" cy="24" r="2.5" fill="#30363d"/>
      <rect x="116" y="20" width="8" height="8" rx="1" fill="#58a6ff" opacity="0.9"/>
      <rect x="172" y="20" width="8" height="8" rx="1" fill="#3fb950" opacity="0.9"/>
      <circle cx="232" cy="24" r="2.5" fill="#30363d"/>
      <rect x="284" y="20" width="8" height="8" rx="1" fill="none" stroke="#30363d" stroke-width="0.5"/>

      <!-- Row 4 -->
      <rect x="60"  y="30" width="8" height="8" rx="1" fill="#f85149" opacity="0.9"/>
      <rect x="116" y="30" width="8" height="8" rx="1" fill="#58a6ff" opacity="0.9"/>
      <rect x="172" y="30" width="8" height="8" rx="1" fill="#3fb950" opacity="0.9"/>
      <rect x="228" y="30" width="8" height="8" rx="1" fill="#d29922" opacity="0.9"/>
      <circle cx="288" cy="34" r="2.5" fill="#30363d"/>

      <!-- Row 5 -->
      <rect x="60"  y="40" width="8" height="8" rx="1" fill="#f85149" opacity="0.9"/>
      <rect x="116" y="40" width="8" height="8" rx="1" fill="none" stroke="#30363d" stroke-width="0.5"/>
      <rect x="172" y="40" width="8" height="8" rx="1" fill="none" stroke="#30363d" stroke-width="0.5"/>
      <rect x="228" y="40" width="8" height="8" rx="1" fill="#d29922" opacity="0.9"/>
      <rect x="284" y="40" width="8" height="8" rx="1" fill="#bc8cff" opacity="0.9"/>

      <!-- Rows 6-10 (showing density pattern) -->
      <rect x="60"  y="50" width="8" height="8" rx="1" fill="#f85149" opacity="0.9"/>
      <rect x="116" y="50" width="8" height="8" rx="1" fill="#58a6ff" opacity="0.9"/>
      <circle cx="176" cy="54" r="2.5" fill="#30363d"/>
      <circle cx="232" cy="54" r="2.5" fill="#30363d"/>
      <rect x="284" y="50" width="8" height="8" rx="1" fill="#bc8cff" opacity="0.9"/>

      <circle cx="64" cy="64" r="2.5" fill="#30363d"/>
      <rect x="116" y="60" width="8" height="8" rx="1" fill="#58a6ff" opacity="0.9"/>
      <rect x="172" y="60" width="8" height="8" rx="1" fill="#3fb950" opacity="0.9"/>
      <rect x="228" y="60" width="8" height="8" rx="1" fill="#d29922" opacity="0.9"/>
      <rect x="284" y="60" width="8" height="8" rx="1" fill="#bc8cff" opacity="0.9"/>

      <rect x="60"  y="70" width="8" height="8" rx="1" fill="#f85149" opacity="0.9"/>
      <rect x="116" y="70" width="8" height="8" rx="1" fill="#58a6ff" opacity="0.9"/>
      <rect x="172" y="70" width="8" height="8" rx="1" fill="#3fb950" opacity="0.9"/>
      <circle cx="232" cy="74" r="2.5" fill="#30363d"/>
      <circle cx="288" cy="74" r="2.5" fill="#30363d"/>

      <rect x="60"  y="80" width="8" height="8" rx="1" fill="#f85149" opacity="0.9"/>
      <circle cx="120" cy="84" r="2.5" fill="#30363d"/>
      <rect x="172" y="80" width="8" height="8" rx="1" fill="none" stroke="#30363d" stroke-width="0.5"/>
      <rect x="228" y="80" width="8" height="8" rx="1" fill="#d29922" opacity="0.9"/>
      <rect x="284" y="80" width="8" height="8" rx="1" fill="#bc8cff" opacity="0.9"/>

      <circle cx="64" cy="94" r="2.5" fill="#30363d"/>
      <rect x="116" y="90" width="8" height="8" rx="1" fill="#58a6ff" opacity="0.9"/>
      <rect x="172" y="90" width="8" height="8" rx="1" fill="#3fb950" opacity="0.9"/>
      <rect x="228" y="90" width="8" height="8" rx="1" fill="#d29922" opacity="0.9"/>
      <rect x="284" y="90" width="8" height="8" rx="1" fill="none" stroke="#30363d" stroke-width="0.5"/>

      <!-- Sparse middle region (rows 20-25) -->
      <rect x="60"  y="200" width="8" height="8" rx="1" fill="#f85149" opacity="0.9"/>
      <rect x="116" y="200" width="8" height="8" rx="1" fill="none" stroke="#30363d" stroke-width="0.5"/>
      <circle cx="176" cy="204" r="2.5" fill="#30363d"/>
      <rect x="228" y="200" width="8" height="8" rx="1" fill="none" stroke="#30363d" stroke-width="0.5"/>
      <circle cx="288" cy="204" r="2.5" fill="#30363d"/>

      <circle cx="64" cy="214" r="2.5" fill="#30363d"/>
      <circle cx="120" cy="214" r="2.5" fill="#30363d"/>
      <rect x="172" y="210" width="8" height="8" rx="1" fill="#3fb950" opacity="0.9"/>
      <circle cx="232" cy="214" r="2.5" fill="#30363d"/>
      <rect x="284" y="210" width="8" height="8" rx="1" fill="none" stroke="#30363d" stroke-width="0.5"/>

      <!-- Dense cluster (rows 35-37) -->
      <rect x="60"  y="280" width="8" height="8" rx="1" fill="#f85149" opacity="0.9"/>
      <rect x="116" y="280" width="8" height="8" rx="1" fill="#58a6ff" opacity="0.9"/>
      <rect x="172" y="280" width="8" height="8" rx="1" fill="#3fb950" opacity="0.9"/>
      <rect x="228" y="280" width="8" height="8" rx="1" fill="#d29922" opacity="0.9"/>
      <rect x="284" y="280" width="8" height="8" rx="1" fill="#bc8cff" opacity="0.9"/>

      <rect x="60"  y="290" width="8" height="8" rx="1" fill="#f85149" opacity="0.9"/>
      <rect x="116" y="290" width="8" height="8" rx="1" fill="#58a6ff" opacity="0.9"/>
      <rect x="172" y="290" width="8" height="8" rx="1" fill="#3fb950" opacity="0.9"/>
      <rect x="228" y="290" width="8" height="8" rx="1" fill="#d29922" opacity="0.9"/>
      <rect x="284" y="290" width="8" height="8" rx="1" fill="#bc8cff" opacity="0.9"/>
    </g>

    <!-- Summary bars at bottom -->
    <g transform="translate(60, 430)">
      <text x="-10" y="12" text-anchor="end" style="font-size:8px;fill:#8b949e;">Coverage</text>
      <!-- Concurrency: 72% -->
      <rect x="0" y="2" width="56" height="10" rx="2" fill="#161b22" stroke="#30363d" stroke-width="0.5"/>
      <rect x="0" y="2" width="40" height="10" rx="2" fill="#f85149" opacity="0.7"/>
      <text x="28" y="10" text-anchor="middle" style="font-size:7px;fill:#e6edf3;">72%</text>
      <!-- Contracts: 58% -->
      <rect x="56" y="2" width="56" height="10" rx="2" fill="#161b22" stroke="#30363d" stroke-width="0.5"/>
      <rect x="56" y="2" width="32" height="10" rx="2" fill="#58a6ff" opacity="0.7"/>
      <text x="84" y="10" text-anchor="middle" style="font-size:7px;fill:#e6edf3;">58%</text>
      <!-- Data transform: 44% -->
      <rect x="112" y="2" width="56" height="10" rx="2" fill="#161b22" stroke="#30363d" stroke-width="0.5"/>
      <rect x="112" y="2" width="25" height="10" rx="2" fill="#3fb950" opacity="0.7"/>
      <text x="140" y="10" text-anchor="middle" style="font-size:7px;fill:#e6edf3;">44%</text>
      <!-- Resource lifecycle: 52% -->
      <rect x="168" y="2" width="56" height="10" rx="2" fill="#161b22" stroke="#30363d" stroke-width="0.5"/>
      <rect x="168" y="2" width="29" height="10" rx="2" fill="#d29922" opacity="0.7"/>
      <text x="196" y="10" text-anchor="middle" style="font-size:7px;fill:#e6edf3;">52%</text>
      <!-- Shared state: 63% -->
      <rect x="224" y="2" width="56" height="10" rx="2" fill="#161b22" stroke="#30363d" stroke-width="0.5"/>
      <rect x="224" y="2" width="35" height="10" rx="2" fill="#bc8cff" opacity="0.7"/>
      <text x="252" y="10" text-anchor="middle" style="font-size:7px;fill:#e6edf3;">63%</text>
    </g>
  </svg>
</div>
```

### Scale handling (125 findings, 90 requirements)

The grid uses 8px cells with 2px gaps = 10px per row. At 90 requirements,
the grid body is 900px tall. This fits on screen with scrolling, or can be
compressed to 6px cells (540px) for overview mode. The generator iterates
`requirements x lenses` and emits one SVG element per cell.

Production generation pseudocode:
```python
y = 0
for req in requirements:
    x = 60
    for lens in LENSES:
        findings = findings_by_req_lens.get((req.id, lens), [])
        if findings:
            color = LENS_COLORS[lens]
            svg += f'<rect x="{x}" y="{y}" width="8" height="8" rx="1" fill="{color}" opacity="0.9"/>'
        elif req.id in scope_by_lens.get(lens, set()):
            svg += f'<circle cx="{x+4}" cy="{y+4}" r="2.5" fill="#30363d"/>'
        # else: empty (no element)
        x += 56  # column spacing
    y += 10
```

---

## B. Construct Clustering Topology

### What it shows

A force-directed-style node-link diagram rendered as static SVG. Each node
is a construct (class/interface/inner type). Edges represent relationships:
- **Solid lines**: shared state (fields referenced by multiple constructs)
- **Dashed lines**: data flow (one construct's output is another's input)
- **Dotted lines**: same cluster membership

Nodes are sized by finding count and colored by the dominant lens that
produced findings. Cluster boundaries are shown as translucent convex hulls
(SVG `<polygon>` with low opacity fill).

Since this is static SVG (no JS physics), positions are pre-computed by the
generator using a simple radial layout: clusters form concentric rings,
constructs within a cluster are spaced evenly on their ring's arc.

### Why it beats text

A text list of "Cluster 1: [A, B, C]" gives no sense of cross-cluster
relationships or node importance. The topology shows dense clusters (high
coupling), bridge constructs (nodes with edges to multiple clusters), and
isolated constructs at a glance. The size encoding immediately highlights
where findings concentrate.

### Implementation

```html
<!-- Construct Clustering Topology -->
<div style="
  background: #0d1117;
  border: 1px solid #30363d;
  border-radius: 8px;
  padding: 1.5rem;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
  color: #e6edf3;
  max-width: 700px;
">
  <h3 style="margin: 0 0 1rem; font-size: 1.1rem; border-bottom: 1px solid #30363d; padding-bottom: 0.5rem;">
    Construct Topology
  </h3>

  <!-- Legend -->
  <div style="display: flex; gap: 1.2rem; margin-bottom: 0.8rem; font-size: 0.75rem; color: #8b949e;">
    <span><svg width="20" height="10"><line x1="0" y1="5" x2="20" y2="5" stroke="#58a6ff" stroke-width="1.5"/></svg> Shared state</span>
    <span><svg width="20" height="10"><line x1="0" y1="5" x2="20" y2="5" stroke="#3fb950" stroke-width="1.5" stroke-dasharray="4,2"/></svg> Data flow</span>
    <span><svg width="20" height="10"><line x1="0" y1="5" x2="20" y2="5" stroke="#30363d" stroke-width="1" stroke-dasharray="2,2"/></svg> Cluster</span>
  </div>

  <svg viewBox="0 0 600 450" style="width: 100%;">
    <defs>
      <marker id="arrow" viewBox="0 0 10 7" refX="10" refY="3.5"
              markerWidth="6" markerHeight="6" orient="auto-start-reverse">
        <polygon points="0 0, 10 3.5, 0 7" fill="#3fb950" opacity="0.6"/>
      </marker>
    </defs>

    <!-- Cluster 1 hull: EncryptionManager + KeyStore + CipherFactory -->
    <polygon points="80,100 200,60 260,140 220,220 100,200"
             fill="#58a6ff" opacity="0.06" stroke="#58a6ff" stroke-width="0.5" stroke-opacity="0.3"/>
    <text x="160" y="230" text-anchor="middle" style="font-size:9px;fill:#58a6ff;opacity:0.5;">Cluster 1: encryption core</text>

    <!-- Cluster 2 hull: StreamProcessor + BufferPool + MemoryAllocator -->
    <polygon points="320,80 460,60 500,160 450,240 340,220"
             fill="#d29922" opacity="0.06" stroke="#d29922" stroke-width="0.5" stroke-opacity="0.3"/>
    <text x="410" y="250" text-anchor="middle" style="font-size:9px;fill:#d29922;opacity:0.5;">Cluster 2: stream pipeline</text>

    <!-- Cluster 3 hull: ConfigProvider + SessionManager + AuthCache -->
    <polygon points="180,280 320,260 360,340 300,400 200,380"
             fill="#bc8cff" opacity="0.06" stroke="#bc8cff" stroke-width="0.5" stroke-opacity="0.3"/>
    <text x="270" y="410" text-anchor="middle" style="font-size:9px;fill:#bc8cff;opacity:0.5;">Cluster 3: session/config</text>

    <!-- Edges: shared state (solid) -->
    <line x1="140" y1="120" x2="200" y2="130" stroke="#58a6ff" stroke-width="1.5" opacity="0.6"/>
    <line x1="200" y1="130" x2="220" y2="170" stroke="#58a6ff" stroke-width="1.5" opacity="0.6"/>
    <line x1="370" y1="120" x2="420" y2="140" stroke="#58a6ff" stroke-width="1.5" opacity="0.6"/>
    <line x1="420" y1="140" x2="440" y2="180" stroke="#58a6ff" stroke-width="1.5" opacity="0.6"/>
    <line x1="240" y1="310" x2="300" y2="330" stroke="#58a6ff" stroke-width="1.5" opacity="0.6"/>

    <!-- Edges: data flow (dashed, with arrows) -->
    <line x1="220" y1="170" x2="370" y2="120" stroke="#3fb950" stroke-width="1.5" stroke-dasharray="6,3" opacity="0.5" marker-end="url(#arrow)"/>
    <line x1="440" y1="180" x2="300" y2="330" stroke="#3fb950" stroke-width="1.5" stroke-dasharray="6,3" opacity="0.5" marker-end="url(#arrow)"/>

    <!-- Cross-cluster edge (bridge) -->
    <line x1="140" y1="120" x2="240" y2="310" stroke="#f85149" stroke-width="1" stroke-dasharray="3,3" opacity="0.4"/>

    <!-- Nodes -->
    <!-- Cluster 1 nodes -->
    <circle cx="140" cy="120" r="14" fill="#161b22" stroke="#f85149" stroke-width="2"/>
    <text x="140" y="124" text-anchor="middle" style="font-size:7px;fill:#e6edf3;">EncMgr</text>
    <text x="140" y="100" text-anchor="middle" style="font-size:7px;fill:#f85149;">8</text>

    <circle cx="200" cy="130" r="10" fill="#161b22" stroke="#58a6ff" stroke-width="2"/>
    <text x="200" y="134" text-anchor="middle" style="font-size:7px;fill:#e6edf3;">KeyStr</text>
    <text x="200" y="114" text-anchor="middle" style="font-size:7px;fill:#58a6ff;">4</text>

    <circle cx="220" cy="170" r="12" fill="#161b22" stroke="#d29922" stroke-width="2"/>
    <text x="220" y="174" text-anchor="middle" style="font-size:7px;fill:#e6edf3;">CiphF</text>
    <text x="220" y="154" text-anchor="middle" style="font-size:7px;fill:#d29922;">6</text>

    <!-- Cluster 2 nodes -->
    <circle cx="370" cy="120" r="16" fill="#161b22" stroke="#f85149" stroke-width="2"/>
    <text x="370" y="124" text-anchor="middle" style="font-size:7px;fill:#e6edf3;">StrProc</text>
    <text x="370" y="100" text-anchor="middle" style="font-size:7px;fill:#f85149;">10</text>

    <circle cx="420" cy="140" r="11" fill="#161b22" stroke="#3fb950" stroke-width="2"/>
    <text x="420" y="144" text-anchor="middle" style="font-size:7px;fill:#e6edf3;">BufPl</text>
    <text x="420" y="124" text-anchor="middle" style="font-size:7px;fill:#3fb950;">5</text>

    <circle cx="440" cy="180" r="8" fill="#161b22" stroke="#d29922" stroke-width="2"/>
    <text x="440" y="184" text-anchor="middle" style="font-size:7px;fill:#e6edf3;">MemA</text>
    <text x="440" y="168" text-anchor="middle" style="font-size:7px;fill:#d29922;">2</text>

    <!-- Cluster 3 nodes -->
    <circle cx="240" cy="310" r="12" fill="#161b22" stroke="#bc8cff" stroke-width="2"/>
    <text x="240" y="314" text-anchor="middle" style="font-size:7px;fill:#e6edf3;">CfgPr</text>
    <text x="240" y="294" text-anchor="middle" style="font-size:7px;fill:#bc8cff;">6</text>

    <circle cx="300" cy="330" r="13" fill="#161b22" stroke="#f85149" stroke-width="2"/>
    <text x="300" y="334" text-anchor="middle" style="font-size:7px;fill:#e6edf3;">SessMg</text>
    <text x="300" y="312" text-anchor="middle" style="font-size:7px;fill:#f85149;">7</text>

    <circle cx="320" cy="370" r="7" fill="#161b22" stroke="#58a6ff" stroke-width="1.5"/>
    <text x="320" y="374" text-anchor="middle" style="font-size:6px;fill:#e6edf3;">Auth</text>
    <text x="320" y="360" text-anchor="middle" style="font-size:7px;fill:#58a6ff;">1</text>

    <!-- Isolated node (no cluster) -->
    <circle cx="520" cy="320" r="6" fill="#161b22" stroke="#30363d" stroke-width="1"/>
    <text x="520" y="324" text-anchor="middle" style="font-size:6px;fill:#8b949e;">Util</text>
    <text x="520" y="310" text-anchor="middle" style="font-size:7px;fill:#8b949e;">0</text>
  </svg>
</div>
```

### Scale handling (60 constructs)

Radial layout algorithm: assign clusters to angular sectors proportional to
their construct count. Within each sector, place nodes on a ring at radius
proportional to cluster index. Node radius = `max(6, 4 + finding_count)`,
capped at 20. For 60 nodes in ~8 clusters, this produces readable results
without overlap if the viewBox is 800x600 or larger.

Production generation pseudocode:
```python
sector_size = 2 * math.pi / len(clusters)
for ci, cluster in enumerate(clusters):
    angle_start = ci * sector_size
    for ni, node in enumerate(cluster.constructs):
        angle = angle_start + (ni / len(cluster.constructs)) * sector_size * 0.8
        r = 150 + ci * 30
        x = 300 + r * math.cos(angle)
        y = 225 + r * math.sin(angle)
        node_r = max(6, 4 + node.finding_count)
        svg += f'<circle cx="{x}" cy="{y}" r="{node_r}" .../>'
```

---

## C. Finding Flow Sankey/Funnel

### What it shows

A horizontal flow diagram showing how findings move through the pipeline:

```
Suspected ──> Proved ──┬──> CONFIRMED_AND_FIXED
   (125)       (109)   ├──> IMPOSSIBLE
                       ├──> FIX_IMPOSSIBLE
                       └──> CLEARED (pre-prove)
```

Each stage is a vertical bar whose height is proportional to count. Flow
bands connect stages, splitting by outcome. Bands are colored by lens.
Width of each band encodes the count flowing through that path.

Below the main Sankey, a per-lens mini-funnel shows each lens's
contribution separately (small multiples).

### Why it beats text

A text table "125 findings: 47 fixed, 62 impossible, 16 cleared" hides
the flow. The Sankey shows WHERE findings drop out (cleared before prove-fix
vs impossible during prove-fix), which lenses contribute most to fixes vs
impossible, and the overall conversion rate. The shape of the flow immediately
communicates pipeline effectiveness.

### Implementation

```html
<!-- Finding Flow Sankey -->
<div style="
  background: #0d1117;
  border: 1px solid #30363d;
  border-radius: 8px;
  padding: 1.5rem;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
  color: #e6edf3;
  max-width: 800px;
">
  <h3 style="margin: 0 0 1rem; font-size: 1.1rem; border-bottom: 1px solid #30363d; padding-bottom: 0.5rem;">
    Finding Flow
  </h3>

  <svg viewBox="0 0 750 320" style="width: 100%;">
    <!-- Stage labels -->
    <text x="40" y="20" text-anchor="middle" style="font-size:11px;fill:#8b949e;font-weight:600;">Suspected</text>
    <text x="40" y="35" text-anchor="middle" style="font-size:9px;fill:#58a6ff;">125</text>

    <text x="250" y="20" text-anchor="middle" style="font-size:11px;fill:#8b949e;font-weight:600;">Proved</text>
    <text x="250" y="35" text-anchor="middle" style="font-size:9px;fill:#58a6ff;">109</text>

    <text x="500" y="20" text-anchor="middle" style="font-size:11px;fill:#8b949e;font-weight:600;">Outcome</text>

    <!-- Stage bars -->
    <!-- Suspected: 125 findings, full height = 250px -->
    <rect x="20" y="50" width="40" height="250" rx="3" fill="#161b22" stroke="#30363d" stroke-width="1"/>

    <!-- Proved (after clearing): 109 -->
    <rect x="230" y="66" width="40" height="218" rx="3" fill="#161b22" stroke="#30363d" stroke-width="1"/>

    <!-- Outcome bars stacked -->
    <!-- CONFIRMED_AND_FIXED: 47 -->
    <rect x="480" y="50" width="40" height="94" rx="3" fill="#3fb950" opacity="0.8"/>
    <text x="530" y="100" style="font-size:10px;fill:#3fb950;font-weight:600;">Fixed: 47</text>

    <!-- IMPOSSIBLE: 52 -->
    <rect x="480" y="148" width="40" height="104" rx="3" fill="#30363d" opacity="0.8"/>
    <text x="530" y="205" style="font-size:10px;fill:#8b949e;">Impossible: 52</text>

    <!-- FIX_IMPOSSIBLE: 10 -->
    <rect x="480" y="256" width="40" height="20" rx="3" fill="#f85149" opacity="0.8"/>
    <text x="530" y="270" style="font-size:10px;fill:#f85149;">Fix impossible: 10</text>

    <!-- Cleared branch (exits before prove-fix) -->
    <rect x="480" y="280" width="40" height="20" rx="3" fill="#d29922" opacity="0.5"/>
    <text x="530" y="293" style="font-size:10px;fill:#d29922;">Cleared: 16</text>

    <!-- Flow bands: Suspected -> Cleared (top portion exits) -->
    <path d="M 60,50 C 150,50 150,278 230,280 L 230,300 C 150,300 150,82 60,82 Z"
          fill="#d29922" opacity="0.12"/>

    <!-- Flow bands: Suspected -> Proved (remaining) -->
    <path d="M 60,82 C 150,82 150,66 230,66 L 230,284 C 150,284 150,300 60,300 Z"
          fill="#58a6ff" opacity="0.08"/>

    <!-- Flow bands: Proved -> Fixed -->
    <path d="M 270,66 C 370,66 370,50 480,50 L 480,144 C 370,144 370,156 270,156 Z"
          fill="#3fb950" opacity="0.15"/>

    <!-- Flow bands: Proved -> Impossible -->
    <path d="M 270,156 C 370,156 370,148 480,148 L 480,252 C 370,252 370,260 270,260 Z"
          fill="#8b949e" opacity="0.08"/>

    <!-- Flow bands: Proved -> Fix Impossible -->
    <path d="M 270,260 C 370,260 370,256 480,256 L 480,276 C 370,276 370,284 270,284 Z"
          fill="#f85149" opacity="0.12"/>

    <!-- Conversion rate annotation -->
    <line x1="350" y1="42" x2="350" y2="148" stroke="#3fb950" stroke-width="1" stroke-dasharray="3,3" opacity="0.4"/>
    <text x="350" y="38" text-anchor="middle" style="font-size:9px;fill:#3fb950;">37.6% fix rate</text>
  </svg>

  <!-- Per-lens mini funnels -->
  <div style="display: flex; gap: 0.5rem; margin-top: 1rem; flex-wrap: wrap;">
    <!-- Concurrency lens -->
    <div style="flex: 1; min-width: 120px; background: #161b22; border-radius: 6px; padding: 0.6rem;">
      <div style="font-size: 0.75rem; color: #f85149; font-weight: 600; margin-bottom: 0.4rem;">concurrency</div>
      <svg viewBox="0 0 100 50" style="width: 100%;">
        <rect x="0" y="0" width="100" height="14" rx="2" fill="#f85149" opacity="0.3"/>
        <rect x="0" y="0" width="72" height="14" rx="2" fill="#f85149" opacity="0.6"/>
        <text x="50" y="10" text-anchor="middle" style="font-size:8px;fill:#e6edf3;">36 suspected</text>

        <rect x="0" y="18" width="100" height="14" rx="2" fill="#3fb950" opacity="0.15"/>
        <rect x="0" y="18" width="44" height="14" rx="2" fill="#3fb950" opacity="0.6"/>
        <text x="50" y="28" text-anchor="middle" style="font-size:8px;fill:#e6edf3;">16 fixed</text>

        <rect x="0" y="36" width="100" height="14" rx="2" fill="#30363d" opacity="0.3"/>
        <rect x="0" y="36" width="39" height="14" rx="2" fill="#8b949e" opacity="0.4"/>
        <text x="50" y="46" text-anchor="middle" style="font-size:8px;fill:#8b949e;">14 impossible</text>
      </svg>
    </div>

    <!-- Contracts lens -->
    <div style="flex: 1; min-width: 120px; background: #161b22; border-radius: 6px; padding: 0.6rem;">
      <div style="font-size: 0.75rem; color: #58a6ff; font-weight: 600; margin-bottom: 0.4rem;">contracts</div>
      <svg viewBox="0 0 100 50" style="width: 100%;">
        <rect x="0" y="0" width="100" height="14" rx="2" fill="#58a6ff" opacity="0.3"/>
        <rect x="0" y="0" width="56" height="14" rx="2" fill="#58a6ff" opacity="0.6"/>
        <text x="50" y="10" text-anchor="middle" style="font-size:8px;fill:#e6edf3;">28 suspected</text>

        <rect x="0" y="18" width="100" height="14" rx="2" fill="#3fb950" opacity="0.15"/>
        <rect x="0" y="18" width="75" height="14" rx="2" fill="#3fb950" opacity="0.6"/>
        <text x="50" y="28" text-anchor="middle" style="font-size:8px;fill:#e6edf3;">21 fixed</text>

        <rect x="0" y="36" width="100" height="14" rx="2" fill="#30363d" opacity="0.3"/>
        <rect x="0" y="36" width="18" height="14" rx="2" fill="#8b949e" opacity="0.4"/>
        <text x="50" y="46" text-anchor="middle" style="font-size:8px;fill:#8b949e;">5 impossible</text>
      </svg>
    </div>

    <!-- Data transform lens -->
    <div style="flex: 1; min-width: 120px; background: #161b22; border-radius: 6px; padding: 0.6rem;">
      <div style="font-size: 0.75rem; color: #3fb950; font-weight: 600; margin-bottom: 0.4rem;">data_xform</div>
      <svg viewBox="0 0 100 50" style="width: 100%;">
        <rect x="0" y="0" width="100" height="14" rx="2" fill="#3fb950" opacity="0.3"/>
        <rect x="0" y="0" width="28" height="14" rx="2" fill="#3fb950" opacity="0.6"/>
        <text x="50" y="10" text-anchor="middle" style="font-size:8px;fill:#e6edf3;">14 suspected</text>

        <rect x="0" y="18" width="100" height="14" rx="2" fill="#3fb950" opacity="0.15"/>
        <rect x="0" y="18" width="14" height="14" rx="2" fill="#3fb950" opacity="0.6"/>
        <text x="50" y="28" text-anchor="middle" style="font-size:8px;fill:#e6edf3;">2 fixed</text>

        <rect x="0" y="36" width="100" height="14" rx="2" fill="#30363d" opacity="0.3"/>
        <rect x="0" y="36" width="71" height="14" rx="2" fill="#8b949e" opacity="0.4"/>
        <text x="50" y="46" text-anchor="middle" style="font-size:8px;fill:#8b949e;">10 impossible</text>
      </svg>
    </div>

    <!-- Resource lifecycle lens -->
    <div style="flex: 1; min-width: 120px; background: #161b22; border-radius: 6px; padding: 0.6rem;">
      <div style="font-size: 0.75rem; color: #d29922; font-weight: 600; margin-bottom: 0.4rem;">resource_lc</div>
      <svg viewBox="0 0 100 50" style="width: 100%;">
        <rect x="0" y="0" width="100" height="14" rx="2" fill="#d29922" opacity="0.3"/>
        <rect x="0" y="0" width="40" height="14" rx="2" fill="#d29922" opacity="0.6"/>
        <text x="50" y="10" text-anchor="middle" style="font-size:8px;fill:#e6edf3;">20 suspected</text>

        <rect x="0" y="18" width="100" height="14" rx="2" fill="#3fb950" opacity="0.15"/>
        <rect x="0" y="18" width="20" height="14" rx="2" fill="#3fb950" opacity="0.6"/>
        <text x="50" y="28" text-anchor="middle" style="font-size:8px;fill:#e6edf3;">4 fixed</text>

        <rect x="0" y="36" width="100" height="14" rx="2" fill="#30363d" opacity="0.3"/>
        <rect x="0" y="36" width="60" height="14" rx="2" fill="#8b949e" opacity="0.4"/>
        <text x="50" y="46" text-anchor="middle" style="font-size:8px;fill:#8b949e;">12 impossible</text>
      </svg>
    </div>

    <!-- Shared state lens -->
    <div style="flex: 1; min-width: 120px; background: #161b22; border-radius: 6px; padding: 0.6rem;">
      <div style="font-size: 0.75rem; color: #bc8cff; font-weight: 600; margin-bottom: 0.4rem;">shared_state</div>
      <svg viewBox="0 0 100 50" style="width: 100%;">
        <rect x="0" y="0" width="100" height="14" rx="2" fill="#bc8cff" opacity="0.3"/>
        <rect x="0" y="0" width="54" height="14" rx="2" fill="#bc8cff" opacity="0.6"/>
        <text x="50" y="10" text-anchor="middle" style="font-size:8px;fill:#e6edf3;">27 suspected</text>

        <rect x="0" y="18" width="100" height="14" rx="2" fill="#3fb950" opacity="0.15"/>
        <rect x="0" y="18" width="15" height="14" rx="2" fill="#3fb950" opacity="0.6"/>
        <text x="50" y="28" text-anchor="middle" style="font-size:8px;fill:#e6edf3;">4 fixed</text>

        <rect x="0" y="36" width="100" height="14" rx="2" fill="#30363d" opacity="0.3"/>
        <rect x="0" y="36" width="41" height="14" rx="2" fill="#8b949e" opacity="0.4"/>
        <text x="50" y="46" text-anchor="middle" style="font-size:8px;fill:#8b949e;">11 impossible</text>
      </svg>
    </div>
  </div>
</div>
```

### Scale handling

The Sankey scales linearly: bar heights are proportional to finding counts.
At 125 findings, a 250px column gives 2px per finding -- readable. The
per-lens mini-funnels use relative widths (percentage of max suspected
across all lenses), so they remain proportional regardless of absolute count.

---

## D. Fix Cascade Visualization

### What it shows

A directed acyclic graph showing Phase 0 short-circuit chains. When
Finding A's fix changes code that Finding B targets, Phase 0 detects B
as already-fixed and marks it IMPOSSIBLE (short-circuited). This creates
a dependency chain: A's fix resolves B, B's fix might resolve C, etc.

The visualization draws:
- **Root fixes** (left column): findings that were CONFIRMED_AND_FIXED
  with original prove-fix work
- **Cascade chains** (right columns): findings resolved by Phase 0,
  connected by arrows to the fix that resolved them
- **Chain length** annotation: how many findings each root fix cascaded to

Nodes are colored by outcome: green for fixed, grey with a lightning bolt
for short-circuited.

### Why it beats text

The Phase 0 cascade is the pipeline's highest-leverage feature -- one fix
resolving multiple findings. Text like "F-R12.conc.1.3 was short-circuited
by F-R12.conc.1.1" buries the chain structure. The DAG immediately shows
which fixes had the largest blast radius, which findings were "free"
(resolved without prove-fix cost), and how deep the cascade chains run.

### Implementation

```html
<!-- Fix Cascade Visualization -->
<div style="
  background: #0d1117;
  border: 1px solid #30363d;
  border-radius: 8px;
  padding: 1.5rem;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
  color: #e6edf3;
  max-width: 800px;
">
  <h3 style="margin: 0 0 0.5rem; font-size: 1.1rem; border-bottom: 1px solid #30363d; padding-bottom: 0.5rem;">
    Fix Cascade (Phase 0)
  </h3>
  <p style="font-size: 0.8rem; color: #8b949e; margin: 0 0 1rem;">
    Root fixes on the left cascade to resolve downstream findings automatically.
  </p>

  <!-- Summary stats -->
  <div style="display: flex; gap: 1rem; margin-bottom: 1rem;">
    <div style="background: #161b22; border: 1px solid #30363d; border-radius: 6px; padding: 0.5rem 0.8rem; text-align: center;">
      <div style="font-size: 0.7rem; color: #8b949e; text-transform: uppercase;">Root fixes</div>
      <div style="font-size: 1.2rem; color: #3fb950; font-weight: 700;">12</div>
    </div>
    <div style="background: #161b22; border: 1px solid #30363d; border-radius: 6px; padding: 0.5rem 0.8rem; text-align: center;">
      <div style="font-size: 0.7rem; color: #8b949e; text-transform: uppercase;">Cascaded</div>
      <div style="font-size: 1.2rem; color: #58a6ff; font-weight: 700;">35</div>
    </div>
    <div style="background: #161b22; border: 1px solid #30363d; border-radius: 6px; padding: 0.5rem 0.8rem; text-align: center;">
      <div style="font-size: 0.7rem; color: #8b949e; text-transform: uppercase;">Cascade ratio</div>
      <div style="font-size: 1.2rem; color: #d29922; font-weight: 700;">2.9x</div>
    </div>
    <div style="background: #161b22; border: 1px solid #30363d; border-radius: 6px; padding: 0.5rem 0.8rem; text-align: center;">
      <div style="font-size: 0.7rem; color: #8b949e; text-transform: uppercase;">Cost saved</div>
      <div style="font-size: 1.2rem; color: #3fb950; font-weight: 700;">~$26</div>
    </div>
  </div>

  <svg viewBox="0 0 720 380" style="width: 100%;">
    <defs>
      <marker id="cascade-arrow" viewBox="0 0 8 6" refX="8" refY="3"
              markerWidth="6" markerHeight="5" orient="auto">
        <polygon points="0 0, 8 3, 0 6" fill="#3fb950" opacity="0.7"/>
      </marker>
      <!-- Lightning bolt for short-circuited -->
      <symbol id="bolt" viewBox="0 0 12 16">
        <path d="M7 0 L3 7 L6 7 L5 16 L9 9 L6 9 Z" fill="#d29922"/>
      </symbol>
    </defs>

    <!-- Column headers -->
    <text x="60" y="20" text-anchor="middle" style="font-size:10px;fill:#3fb950;font-weight:600;">Root Fix</text>
    <text x="250" y="20" text-anchor="middle" style="font-size:10px;fill:#58a6ff;font-weight:600;">Cascade Depth 1</text>
    <text x="450" y="20" text-anchor="middle" style="font-size:10px;fill:#bc8cff;font-weight:600;">Cascade Depth 2</text>
    <text x="630" y="20" text-anchor="middle" style="font-size:10px;fill:#d29922;font-weight:600;">Depth 3</text>

    <!-- Chain 1: Large cascade (1 root -> 4 depth-1 -> 2 depth-2) -->
    <!-- Root: F-R5.conc.1.1 -->
    <rect x="10" y="40" width="100" height="28" rx="4" fill="#161b22" stroke="#3fb950" stroke-width="1.5"/>
    <text x="60" y="52" text-anchor="middle" style="font-size:8px;fill:#3fb950;font-weight:600;">F-R5.conc.1.1</text>
    <text x="60" y="63" text-anchor="middle" style="font-size:7px;fill:#8b949e;">EncryptionManager</text>

    <!-- Depth 1 targets -->
    <rect x="200" y="30" width="100" height="24" rx="4" fill="#161b22" stroke="#58a6ff" stroke-width="1"/>
    <use href="#bolt" x="288" y="34" width="8" height="11"/>
    <text x="244" y="46" text-anchor="middle" style="font-size:7px;fill:#58a6ff;">F-R5.conc.1.2</text>

    <rect x="200" y="58" width="100" height="24" rx="4" fill="#161b22" stroke="#58a6ff" stroke-width="1"/>
    <use href="#bolt" x="288" y="62" width="8" height="11"/>
    <text x="244" y="74" text-anchor="middle" style="font-size:7px;fill:#58a6ff;">F-R5.state.1.1</text>

    <rect x="200" y="86" width="100" height="24" rx="4" fill="#161b22" stroke="#58a6ff" stroke-width="1"/>
    <use href="#bolt" x="288" y="90" width="8" height="11"/>
    <text x="244" y="102" text-anchor="middle" style="font-size:7px;fill:#58a6ff;">F-R8.conc.1.1</text>

    <rect x="200" y="114" width="100" height="24" rx="4" fill="#161b22" stroke="#58a6ff" stroke-width="1"/>
    <use href="#bolt" x="288" y="118" width="8" height="11"/>
    <text x="244" y="130" text-anchor="middle" style="font-size:7px;fill:#58a6ff;">F-R12.conc.1.1</text>

    <!-- Depth 2 (cascaded from depth 1 fixes) -->
    <rect x="400" y="58" width="100" height="24" rx="4" fill="#161b22" stroke="#bc8cff" stroke-width="1"/>
    <use href="#bolt" x="488" y="62" width="8" height="11"/>
    <text x="444" y="74" text-anchor="middle" style="font-size:7px;fill:#bc8cff;">F-R8.state.1.1</text>

    <rect x="400" y="86" width="100" height="24" rx="4" fill="#161b22" stroke="#bc8cff" stroke-width="1"/>
    <use href="#bolt" x="488" y="90" width="8" height="11"/>
    <text x="444" y="102" text-anchor="middle" style="font-size:7px;fill:#bc8cff;">F-R12.state.1.2</text>

    <!-- Arrows -->
    <line x1="110" y1="54" x2="200" y2="42" stroke="#3fb950" stroke-width="1" opacity="0.5" marker-end="url(#cascade-arrow)"/>
    <line x1="110" y1="54" x2="200" y2="70" stroke="#3fb950" stroke-width="1" opacity="0.5" marker-end="url(#cascade-arrow)"/>
    <line x1="110" y1="54" x2="200" y2="98" stroke="#3fb950" stroke-width="1" opacity="0.5" marker-end="url(#cascade-arrow)"/>
    <line x1="110" y1="54" x2="200" y2="126" stroke="#3fb950" stroke-width="1" opacity="0.5" marker-end="url(#cascade-arrow)"/>
    <line x1="300" y1="70" x2="400" y2="70" stroke="#58a6ff" stroke-width="1" opacity="0.4" marker-end="url(#cascade-arrow)"/>
    <line x1="300" y1="98" x2="400" y2="98" stroke="#58a6ff" stroke-width="1" opacity="0.4" marker-end="url(#cascade-arrow)"/>

    <!-- Chain 2: Smaller cascade (1 root -> 2 depth-1 -> 1 depth-2 -> 1 depth-3) -->
    <rect x="10" y="170" width="100" height="28" rx="4" fill="#161b22" stroke="#3fb950" stroke-width="1.5"/>
    <text x="60" y="182" text-anchor="middle" style="font-size:8px;fill:#3fb950;font-weight:600;">F-R22.cont.2.1</text>
    <text x="60" y="193" text-anchor="middle" style="font-size:7px;fill:#8b949e;">KeyStore</text>

    <rect x="200" y="165" width="100" height="24" rx="4" fill="#161b22" stroke="#58a6ff" stroke-width="1"/>
    <use href="#bolt" x="288" y="169" width="8" height="11"/>
    <text x="244" y="181" text-anchor="middle" style="font-size:7px;fill:#58a6ff;">F-R22.cont.2.2</text>

    <rect x="200" y="193" width="100" height="24" rx="4" fill="#161b22" stroke="#58a6ff" stroke-width="1"/>
    <use href="#bolt" x="288" y="197" width="8" height="11"/>
    <text x="244" y="209" text-anchor="middle" style="font-size:7px;fill:#58a6ff;">F-R23.cont.2.1</text>

    <rect x="400" y="180" width="100" height="24" rx="4" fill="#161b22" stroke="#bc8cff" stroke-width="1"/>
    <use href="#bolt" x="488" y="184" width="8" height="11"/>
    <text x="444" y="196" text-anchor="middle" style="font-size:7px;fill:#bc8cff;">F-R23.state.2.1</text>

    <rect x="580" y="180" width="100" height="24" rx="4" fill="#161b22" stroke="#d29922" stroke-width="1"/>
    <use href="#bolt" x="668" y="184" width="8" height="11"/>
    <text x="624" y="196" text-anchor="middle" style="font-size:7px;fill:#d29922;">F-R25.cont.2.1</text>

    <line x1="110" y1="184" x2="200" y2="177" stroke="#3fb950" stroke-width="1" opacity="0.5" marker-end="url(#cascade-arrow)"/>
    <line x1="110" y1="184" x2="200" y2="205" stroke="#3fb950" stroke-width="1" opacity="0.5" marker-end="url(#cascade-arrow)"/>
    <line x1="300" y1="205" x2="400" y2="192" stroke="#58a6ff" stroke-width="1" opacity="0.4" marker-end="url(#cascade-arrow)"/>
    <line x1="500" y1="192" x2="580" y2="192" stroke="#bc8cff" stroke-width="1" opacity="0.3" marker-end="url(#cascade-arrow)"/>

    <!-- Chain 3: No cascade (isolated root fix) -->
    <rect x="10" y="250" width="100" height="28" rx="4" fill="#161b22" stroke="#3fb950" stroke-width="1.5"/>
    <text x="60" y="262" text-anchor="middle" style="font-size:8px;fill:#3fb950;font-weight:600;">F-R44.data.3.1</text>
    <text x="60" y="273" text-anchor="middle" style="font-size:7px;fill:#8b949e;">StreamProcessor</text>
    <text x="130" y="267" style="font-size:8px;fill:#8b949e;font-style:italic;">no cascade</text>

    <!-- Chain 4: Medium cascade -->
    <rect x="10" y="300" width="100" height="28" rx="4" fill="#161b22" stroke="#3fb950" stroke-width="1.5"/>
    <text x="60" y="312" text-anchor="middle" style="font-size:8px;fill:#3fb950;font-weight:600;">F-R60.res.4.1</text>
    <text x="60" y="323" text-anchor="middle" style="font-size:7px;fill:#8b949e;">BufferPool</text>

    <rect x="200" y="295" width="100" height="24" rx="4" fill="#161b22" stroke="#58a6ff" stroke-width="1"/>
    <use href="#bolt" x="288" y="299" width="8" height="11"/>
    <text x="244" y="311" text-anchor="middle" style="font-size:7px;fill:#58a6ff;">F-R60.res.4.2</text>

    <rect x="200" y="323" width="100" height="24" rx="4" fill="#161b22" stroke="#58a6ff" stroke-width="1"/>
    <use href="#bolt" x="288" y="327" width="8" height="11"/>
    <text x="244" y="339" text-anchor="middle" style="font-size:7px;fill:#58a6ff;">F-R61.conc.4.1</text>

    <rect x="200" y="351" width="100" height="24" rx="4" fill="#161b22" stroke="#58a6ff" stroke-width="1"/>
    <use href="#bolt" x="288" y="355" width="8" height="11"/>
    <text x="244" y="367" text-anchor="middle" style="font-size:7px;fill:#58a6ff;">F-R62.state.4.1</text>

    <line x1="110" y1="314" x2="200" y2="307" stroke="#3fb950" stroke-width="1" opacity="0.5" marker-end="url(#cascade-arrow)"/>
    <line x1="110" y1="314" x2="200" y2="335" stroke="#3fb950" stroke-width="1" opacity="0.5" marker-end="url(#cascade-arrow)"/>
    <line x1="110" y1="314" x2="200" y2="363" stroke="#3fb950" stroke-width="1" opacity="0.5" marker-end="url(#cascade-arrow)"/>
  </svg>
</div>
```

### Scale handling

At 47 root fixes with varying cascade depths, the layout uses a vertical
list of root fixes (left column) with horizontal chains extending right.
Chains that share no root can be vertically stacked. For very long cascades
(depth 4+), the visualization wraps the chain to the next line. Compact
mode collapses chains with 0 cascades into a summary row: "8 fixes with
no cascade" instead of showing 8 isolated nodes.

---

## E. Lens Effectiveness Heatmap

### What it shows

A grid where rows are constructs (sorted by total finding count descending)
and columns are lenses. Each cell encodes three things:
1. **Finding count** as a number
2. **Verdict distribution** as the cell's fill color: green for mostly-fixed,
   red/amber for mostly-impossible, grey for cleared
3. **Intensity** via opacity proportional to finding count

Row heights are fixed at 22px. Column widths are equal. The top-left
quadrant (high-finding constructs x effective lenses) visually pops as the
densest, greenest region.

A bottom summary row shows per-lens totals with fix rate percentages.

### Why it beats text

Text tables of 60 constructs x 5 lenses are unreadable. The heatmap
encodes verdict AND count in a single glance. You immediately see: which
constructs had the most bugs (dark rows), which lenses were most effective
(green columns), and which construct-lens pairs are dead zones (empty cells).
The color gradient reveals patterns that numbers alone obscure.

### Implementation

```html
<!-- Lens Effectiveness Heatmap -->
<div style="
  background: #0d1117;
  border: 1px solid #30363d;
  border-radius: 8px;
  padding: 1.5rem;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
  color: #e6edf3;
  max-width: 750px;
  overflow-x: auto;
">
  <h3 style="margin: 0 0 1rem; font-size: 1.1rem; border-bottom: 1px solid #30363d; padding-bottom: 0.5rem;">
    Lens Effectiveness by Construct
  </h3>

  <!-- Color legend -->
  <div style="display: flex; gap: 1rem; margin-bottom: 0.8rem; font-size: 0.75rem; color: #8b949e;">
    <span><span style="display:inline-block;width:14px;height:14px;background:#3fb950;border-radius:2px;vertical-align:middle;opacity:0.8;"></span> Fixed</span>
    <span><span style="display:inline-block;width:14px;height:14px;background:#f85149;border-radius:2px;vertical-align:middle;opacity:0.8;"></span> Fix impossible</span>
    <span><span style="display:inline-block;width:14px;height:14px;background:#30363d;border-radius:2px;vertical-align:middle;opacity:0.8;"></span> Impossible</span>
    <span><span style="display:inline-block;width:14px;height:14px;background:#d29922;border-radius:2px;vertical-align:middle;opacity:0.8;"></span> Cleared</span>
    <span style="margin-left: auto;">Opacity = finding count</span>
  </div>

  <table style="
    width: 100%;
    border-collapse: separate;
    border-spacing: 2px;
    font-size: 0.8rem;
  ">
    <thead>
      <tr>
        <th style="background: transparent; border: none; text-align: left; padding: 0.4rem; color: #8b949e; font-weight: 600; width: 180px;">Construct</th>
        <th style="background: transparent; border: none; text-align: center; padding: 0.4rem; color: #f85149; font-weight: 600; width: 90px;">concurrency</th>
        <th style="background: transparent; border: none; text-align: center; padding: 0.4rem; color: #58a6ff; font-weight: 600; width: 90px;">contracts</th>
        <th style="background: transparent; border: none; text-align: center; padding: 0.4rem; color: #3fb950; font-weight: 600; width: 90px;">data_xform</th>
        <th style="background: transparent; border: none; text-align: center; padding: 0.4rem; color: #d29922; font-weight: 600; width: 90px;">resource_lc</th>
        <th style="background: transparent; border: none; text-align: center; padding: 0.4rem; color: #bc8cff; font-weight: 600; width: 90px;">shared_st</th>
        <th style="background: transparent; border: none; text-align: right; padding: 0.4rem; color: #8b949e; font-weight: 600; width: 50px;">Total</th>
      </tr>
    </thead>
    <tbody>
      <!-- Row 1: StreamProcessor (highest findings) -->
      <tr>
        <td style="padding: 0.3rem 0.5rem; border: none; color: #e6edf3; font-weight: 500;">StreamProcessor</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #3fb950; opacity: 0.9; border-radius: 3px; color: #000; font-weight: 700;">4</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #3fb950; opacity: 0.7; border-radius: 3px; color: #000; font-weight: 700;">3</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #30363d; opacity: 0.5; border-radius: 3px; color: #8b949e;">1</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #3fb950; opacity: 0.5; border-radius: 3px; color: #000; font-weight: 700;">1</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #f85149; opacity: 0.5; border-radius: 3px; color: #fff; font-weight: 700;">1</td>
        <td style="padding: 0.3rem; border: none; text-align: right; color: #e6edf3; font-weight: 700;">10</td>
      </tr>
      <!-- Row 2: EncryptionManager -->
      <tr>
        <td style="padding: 0.3rem 0.5rem; border: none; color: #e6edf3; font-weight: 500;">EncryptionManager</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #3fb950; opacity: 0.8; border-radius: 3px; color: #000; font-weight: 700;">3</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #3fb950; opacity: 0.5; border-radius: 3px; color: #000; font-weight: 700;">2</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: transparent; border-radius: 3px; color: #30363d;">-</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #30363d; opacity: 0.6; border-radius: 3px; color: #8b949e;">2</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #3fb950; opacity: 0.5; border-radius: 3px; color: #000; font-weight: 700;">1</td>
        <td style="padding: 0.3rem; border: none; text-align: right; color: #e6edf3; font-weight: 700;">8</td>
      </tr>
      <!-- Row 3: SessionManager -->
      <tr>
        <td style="padding: 0.3rem 0.5rem; border: none; color: #e6edf3; font-weight: 500;">SessionManager</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #3fb950; opacity: 0.7; border-radius: 3px; color: #000; font-weight: 700;">2</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #30363d; opacity: 0.5; border-radius: 3px; color: #8b949e;">1</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #3fb950; opacity: 0.5; border-radius: 3px; color: #000; font-weight: 700;">1</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: transparent; border-radius: 3px; color: #30363d;">-</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #3fb950; opacity: 0.7; border-radius: 3px; color: #000; font-weight: 700;">3</td>
        <td style="padding: 0.3rem; border: none; text-align: right; color: #e6edf3; font-weight: 700;">7</td>
      </tr>
      <!-- Row 4: KeyStore -->
      <tr>
        <td style="padding: 0.3rem 0.5rem; border: none; color: #e6edf3; font-weight: 500;">KeyStore</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #30363d; opacity: 0.5; border-radius: 3px; color: #8b949e;">1</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #3fb950; opacity: 0.7; border-radius: 3px; color: #000; font-weight: 700;">2</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: transparent; border-radius: 3px; color: #30363d;">-</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #3fb950; opacity: 0.5; border-radius: 3px; color: #000; font-weight: 700;">1</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #d29922; opacity: 0.5; border-radius: 3px; color: #000;">1</td>
        <td style="padding: 0.3rem; border: none; text-align: right; color: #e6edf3; font-weight: 700;">5</td>
      </tr>
      <!-- Row 5: CipherFactory -->
      <tr>
        <td style="padding: 0.3rem 0.5rem; border: none; color: #e6edf3; font-weight: 500;">CipherFactory</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: transparent; border-radius: 3px; color: #30363d;">-</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #3fb950; opacity: 0.6; border-radius: 3px; color: #000; font-weight: 700;">2</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #3fb950; opacity: 0.5; border-radius: 3px; color: #000; font-weight: 700;">1</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: transparent; border-radius: 3px; color: #30363d;">-</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #30363d; opacity: 0.5; border-radius: 3px; color: #8b949e;">1</td>
        <td style="padding: 0.3rem; border: none; text-align: right; color: #e6edf3; font-weight: 700;">4</td>
      </tr>
      <!-- Row 6: BufferPool -->
      <tr>
        <td style="padding: 0.3rem 0.5rem; border: none; color: #e6edf3; font-weight: 500;">BufferPool</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #3fb950; opacity: 0.5; border-radius: 3px; color: #000; font-weight: 700;">1</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: transparent; border-radius: 3px; color: #30363d;">-</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: transparent; border-radius: 3px; color: #30363d;">-</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #3fb950; opacity: 0.6; border-radius: 3px; color: #000; font-weight: 700;">2</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #30363d; opacity: 0.3; border-radius: 3px; color: #8b949e;">1</td>
        <td style="padding: 0.3rem; border: none; text-align: right; color: #e6edf3; font-weight: 700;">4</td>
      </tr>
      <!-- Row 7: ConfigProvider -->
      <tr>
        <td style="padding: 0.3rem 0.5rem; border: none; color: #e6edf3; font-weight: 500;">ConfigProvider</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: transparent; border-radius: 3px; color: #30363d;">-</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #3fb950; opacity: 0.5; border-radius: 3px; color: #000; font-weight: 700;">1</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #30363d; opacity: 0.3; border-radius: 3px; color: #8b949e;">1</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: transparent; border-radius: 3px; color: #30363d;">-</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #3fb950; opacity: 0.5; border-radius: 3px; color: #000; font-weight: 700;">1</td>
        <td style="padding: 0.3rem; border: none; text-align: right; color: #e6edf3; font-weight: 700;">3</td>
      </tr>
      <!-- Row 8: MemoryAllocator -->
      <tr>
        <td style="padding: 0.3rem 0.5rem; border: none; color: #e6edf3; font-weight: 500;">MemoryAllocator</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #30363d; opacity: 0.3; border-radius: 3px; color: #8b949e;">1</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: transparent; border-radius: 3px; color: #30363d;">-</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: transparent; border-radius: 3px; color: #30363d;">-</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: #3fb950; opacity: 0.5; border-radius: 3px; color: #000; font-weight: 700;">1</td>
        <td style="padding: 0.3rem; border: none; text-align: center; background: transparent; border-radius: 3px; color: #30363d;">-</td>
        <td style="padding: 0.3rem; border: none; text-align: right; color: #e6edf3; font-weight: 700;">2</td>
      </tr>
    </tbody>
    <!-- Summary footer -->
    <tfoot>
      <tr style="border-top: 2px solid #30363d;">
        <td style="padding: 0.5rem; border: none; color: #8b949e; font-weight: 700;">Totals</td>
        <td style="padding: 0.5rem; border: none; text-align: center; color: #f85149; font-weight: 700;">
          12<br><span style="font-size:0.7rem;font-weight:400;color:#8b949e;">83% fix</span>
        </td>
        <td style="padding: 0.5rem; border: none; text-align: center; color: #58a6ff; font-weight: 700;">
          11<br><span style="font-size:0.7rem;font-weight:400;color:#8b949e;">91% fix</span>
        </td>
        <td style="padding: 0.5rem; border: none; text-align: center; color: #3fb950; font-weight: 700;">
          4<br><span style="font-size:0.7rem;font-weight:400;color:#8b949e;">50% fix</span>
        </td>
        <td style="padding: 0.5rem; border: none; text-align: center; color: #d29922; font-weight: 700;">
          7<br><span style="font-size:0.7rem;font-weight:400;color:#8b949e;">71% fix</span>
        </td>
        <td style="padding: 0.5rem; border: none; text-align: center; color: #bc8cff; font-weight: 700;">
          8<br><span style="font-size:0.7rem;font-weight:400;color:#8b949e;">50% fix</span>
        </td>
        <td style="padding: 0.5rem; border: none; text-align: right; color: #e6edf3; font-weight: 700;">
          42<br><span style="font-size:0.7rem;font-weight:400;color:#8b949e;">74% fix</span>
        </td>
      </tr>
    </tfoot>
  </table>
</div>
```

### Scale handling (60 constructs)

At 60 rows x 22px = 1320px table height. Two strategies:
1. **Top-N view**: Show only top 15-20 constructs (those with findings),
   with a collapsed `<details>` section for the remaining constructs that
   had 0-1 findings. Most constructs have few findings, so this reduces
   visible rows dramatically.
2. **Full view**: All 60 rows at 18px height = 1080px. The heatmap pattern
   is still visible since cells use color rather than requiring text reading.

Production generation pseudocode:
```python
for construct in sorted(constructs, key=lambda c: c.total_findings, reverse=True):
    row = '<tr>'
    row += f'<td style="...">{construct.name}</td>'
    for lens in LENSES:
        findings = by_construct_lens.get((construct.name, lens), [])
        if not findings:
            row += '<td style="...;color:#30363d;">-</td>'
            continue
        fixed = sum(1 for f in findings if f.verdict == 'CONFIRMED_AND_FIXED')
        total = len(findings)
        ratio = fixed / total
        if ratio > 0.6:
            bg = '#3fb950'
        elif any(f.verdict == 'FIX_IMPOSSIBLE' for f in findings):
            bg = '#f85149'
        else:
            bg = '#30363d'
        opacity = min(0.9, 0.3 + total * 0.15)
        row += f'<td style="...;background:{bg};opacity:{opacity};">{total}</td>'
    row += f'<td style="...">{construct.total_findings}</td></tr>'
```

---

## Integration Notes

### Theme compatibility

All five visualizations use the audit theme variables:
- Background: `#0d1117` (matches `--bg` in generate_audit.py)
- Surface: `#161b22` (matches `--surface`)
- Border: `#30363d` (matches `--border`)
- Text: `#e6edf3` / `#8b949e` (matches `--text` / `--text-muted`)
- Status colors: `#3fb950` green, `#f85149` red, `#d29922` amber, `#58a6ff` blue

Lens colors follow render_html.py's `LENS_COLORS` dict extended with the
5 audit-specific lenses:
- concurrency: `#f85149`
- contracts/contract_boundaries: `#58a6ff`
- data_transformation: `#3fb950`
- resource_lifecycle: `#d29922`
- shared_state: `#bc8cff`

### Where to add generation code

Each visualization needs a generator function in `generate_audit.py` that:
1. Takes parsed audit data (findings list, construct list, cluster map)
2. Produces an HTML string using the patterns above
3. Is called from the main rendering function and embedded in the output

The generator functions should be named:
- `_render_coverage_map(requirements, findings, lenses) -> str`
- `_render_topology(constructs, clusters, edges) -> str`
- `_render_finding_flow(findings, lenses) -> str`
- `_render_cascade(findings, cascade_chains) -> str`
- `_render_lens_heatmap(constructs, findings, lenses) -> str`

### Data requirements

Each visualization needs data that may not be fully available in the current
audit report format. The following data would need to be extracted or added:

| Visualization | Needs | Currently available? |
|---|---|---|
| Coverage map | requirement-to-lens mapping | Partially (from finding IDs) |
| Topology | cluster membership, edge types | Assembly phase output |
| Finding flow | verdict counts by lens | Yes (audit-report.md) |
| Cascade | Phase 0 short-circuit chains | Prove-fix logs |
| Heatmap | construct x lens x verdict | Yes (from findings) |

The topology and cascade visualizations require data from intermediate
pipeline artifacts (assembly clusters, prove-fix Phase 0 logs) that may
not be preserved in the final audit report. Consider emitting a
`viz-data.json` alongside the audit report that captures these intermediate
structures.
