# Visualization Research: Audit Pipeline Renderer

Research conducted 2026-04-03 for the vallorcine audit narrative HTML renderer.
Goal: identify best patterns for visualizing a multi-stage adversarial code audit
pipeline in standalone HTML (no JS frameworks, dark theme, offline-capable).

---

## 1. Pipeline / Workflow Visualization Patterns

### Best examples

| Tool | What it does well | URL |
|------|------------------|-----|
| **Jenkins Blue Ocean** | Horizontal stage-lane with per-stage status badges; parallel branches shown as forking lanes; real-time status coloring (green/blue/red) | https://www.jenkins.io/doc/book/blueocean/ |
| **Apache Airflow Grid View** | Matrix of runs (columns) x tasks (rows), color-coded by status; collapses TaskGroups to manage 100+ tasks | https://airflow.apache.org/docs/apache-airflow/stable/ui.html |
| **Airflow Graph View** | DAG nodes with directional arrows; zoom + pan; hierarchical grouping via TaskGroups | https://www.astronomer.io/blog/5-ways-to-view-and-manage-dags-in-airflow/ |
| **Azure DevOps Multi-Stage** | Linear stage sequence with gate/approval checkpoints between stages; fan-out for parallel environments | https://learn.microsoft.com/en-us/azure/devops/pipelines/process/stages |
| **dbt Lineage Graph** | Left-to-right DAG with color-coded node types; "lenses" overlay metadata (tags, layers) onto nodes; zoomed-out mode shows only tags + colors | https://docs.getdbt.com/docs/explore/explore-projects |

### Design principles that make these effective

1. **Stage-as-lane**: Each pipeline stage gets a distinct horizontal column or
   vertical band. Status is encoded in color (green=pass, red=fail, blue=running,
   gray=skipped). This lets users scan left-to-right and see where things stalled.

2. **Hierarchical collapse**: At 100+ items, flat lists fail. Airflow's TaskGroups
   and dbt's lenses both solve this by letting users see a 6-stage summary, then
   expand a stage to see its 30 tasks. This is exactly what we need for
   constructs-within-clusters-within-stages.

3. **Gate visualization**: Azure DevOps places explicit checkpoint icons between
   stages. For our pipeline, the transition from "finding generation" to
   "prove-fix" is a natural gate — most findings get filtered here.

4. **Color-coded node types**: dbt uses different colors for models, tests, seeds,
   snapshots. We can use this for construct types (class, interface, inner type,
   enum) or finding severity.

### Application to our pipeline

Our 6-stage pipeline maps naturally to a horizontal stage-lane layout:

```
[Spec Analysis] → [Exploration] → [Clustering] → [Finding Gen] → [Prove-Fix] → [Report]
```

Each stage gets its own accent color (we already have phase colors in the existing
renderer). Within each stage, items should be collapsible — spec requirements,
constructs, clusters, findings.

The key insight from Airflow's Grid View: for the "simulation walkthrough" mode,
a matrix of findings (rows) x prove-fix attempts (columns) would show the
sequential progression with status coloring per cell.

### What's achievable in pure HTML/CSS/SVG

**Fully achievable:**
- Horizontal stage-lane with CSS flexbox/grid
- Status color badges with CSS classes
- Collapsible groups with `<details>`/`<summary>`
- Connecting lines between stages with SVG `<path>` elements
- Animated flow using `stroke-dasharray` + `stroke-dashoffset` CSS animation

**Concrete approach:**
- Use CSS Grid with 6 columns for the pipeline overview
- Each column header shows stage name + aggregate stats (count, duration)
- SVG overlay draws bezier paths between stages with animated dash flow
- Items within each stage use `<details>` for expand/collapse
- Phase accent colors from existing `PHASE_COLORS` in render_html.py

---

## 2. Sankey / Flow Diagrams for Data Pipelines

### Best examples

| Tool | What it does well | URL |
|------|------------------|-----|
| **SankeyMATIC** | Simple node-flow diagrams with proportional link width; exports clean SVG | https://sankeymatic.com/ |
| **data-to-viz Sankey reference** | Explains when Sankey works vs when it creates clutter; design guidelines | https://www.data-to-viz.com/graph/sankey.html |
| **think.design Sankey guide** | Masterclass on flow visualization with node sizing and color semantics | https://think.design/services/data-visualization-data-design/sankey-diagram/ |
| **doubleslash data flow blog** | Enterprise data pipeline Sankey with source-transform-sink stages | https://blog.doubleslash.de/en/data-driven-services/datenvisualisierung/visualization-of-data-flows/ |

### Design principles

1. **Width encodes quantity**: The defining Sankey characteristic — link width is
   proportional to the count flowing through it. For our pipeline:
   constructs→findings→confirmed bugs, the narrowing from left to right tells
   the filtering story visually.

2. **Branching shows classification**: Where a flow splits (e.g., findings split
   into "confirmed", "impossible", "deferred"), the branch widths show the ratio
   without needing numbers.

3. **Clutter threshold**: data-to-viz warns that >15 nodes or too many cross-links
   makes Sankey unreadable. For our pipeline's "how does this work" mode, we have
   ~8-10 node types across 6 stages — within the sweet spot. For simulation mode
   with 50+ findings, we would need to aggregate by category first.

4. **Color semantics on links**: Color the links by outcome (green=confirmed bug,
   gray=impossible, yellow=deferred) rather than by source. This tells the
   story of "what happened to findings" rather than "where findings came from."

### Application to our pipeline

A Sankey from left to right:

```
Requirements(N) → Constructs(M) → Clusters(K) → Findings(F) → Confirmed(C) / Impossible(I) / Deferred(D)
```

This is the single most effective visualization for the "how does this work" mode.
It answers: "I put in N requirements, how many real bugs came out?" at a glance.

For simulation mode, a second Sankey per cluster or per lens would show where
findings concentrate. Domain lenses could be shown as parallel Sankey layers
(one per lens) or as colored links within a single diagram.

### What's achievable in pure HTML/CSS/SVG

**Achievable with inline SVG (no JS):**
- Pre-computed node positions (the Python renderer knows all the counts)
- SVG `<rect>` for nodes, `<path>` with cubic beziers for links
- Link width set via `stroke-width` proportional to count
- Color classes for outcome types
- Hover effects via CSS `:hover` on SVG groups

**Not achievable without JS:**
- Dynamic layout (but we don't need it — counts are known at render time)
- Drag-to-reorder nodes
- Tooltip popups (can use `<title>` for native browser tooltips instead)

**Concrete approach:**
- Python renderer computes node x/y positions using a simple column-based layout
- Nodes placed at fixed x per stage, y stacked by size within each column
- Links drawn as cubic bezier SVG paths: `M x1,y1 C cx1,cy1 cx2,cy2 x2,y2`
- Link opacity 0.6, stroke-width proportional to count
- CSS `:hover` on link group increases opacity to 1.0 and dims other links
- Color palette: confirmed=#e74c3c (red), impossible=#7f8c8d (gray),
  deferred=#f39c12 (amber), in-progress=#3498db (blue)

---

## 3. Code Analysis Result Visualization

### Best examples

| Tool | What it does well | URL |
|------|------------------|-----|
| **SonarQube Issues View** | Filterable issue list with severity, type, effort estimate; grouping by file/rule/severity; quality gate pass/fail | https://docs.sonarsource.com/sonarqube-server/latest/user-guide/issues/ |
| **Semgrep Findings** | Group-by-rule toggle; triage workflow (ignore with reason); AI-assisted filtering of false positives | https://semgrep.dev/docs/semgrep-code/triage-remediation |
| **CodeClimate** | Letter-grade maintainability score per file; trend lines; PR-integrated findings | https://www.qodo.ai/blog/code-analysis-tools/ |
| **NDepend DSM** | Dependency Structure Matrix with 3-color scheme (blue/green/black) encoding direction of coupling; coupling strength as numbers in cells | https://www.ndepend.com/docs/dependency-structure-matrix-dsm |

### Design principles

1. **Severity as visual weight**: SonarQube uses icon + color per severity level.
   Critical/blocker findings get prominent red/orange badges. This lets eyes
   skip straight to what matters. For our pipeline: proven bugs > suspected >
   deferred > impossible.

2. **Group-then-filter**: Both SonarQube and Semgrep offer multiple grouping axes
   (by file, by rule, by severity, by type). The key insight: the default
   grouping should match the user's mental model. For developers, that's
   "by file." For our audit, it's "by construct" or "by lens."

3. **Triage state as first-class data**: Semgrep shows that findings need explicit
   states (open, confirmed, false-positive, ignored-with-reason). Our pipeline
   already has this: suspected → proven / impossible / deferred. Showing the
   triage progression is as important as showing the finding itself.

4. **Effort estimation**: SonarQube assigns time estimates to fixes. Our pipeline
   has actual fix data (token cost, duration, cascade effects). Showing "this
   finding cost 12K tokens to prove and fix" is powerful for the simulation
   walkthrough.

5. **Coupling strength as cell value**: NDepend's DSM puts a number in each cell
   representing coupling strength (methods, fields, types involved). For our
   construct x lens matrix, the cell value would be finding count, and color
   would encode severity.

### Application to our pipeline

For the **"how does this work" mode**: show a sample finding card with labeled
anatomy — what each field means, how severity is determined, what "proven" means.

For the **simulation walkthrough**: show the actual findings grouped by construct
(primary) with lens as a secondary axis. Each finding card shows:
- Construct name + type
- Lens that found it (contract, transformation, lifecycle, concurrency)
- Severity badge
- Prove-fix outcome (proven/impossible/deferred)
- If proven: the test that proved it, the fix applied, cascade effects
- Token cost of the prove-fix cycle

### What's achievable in pure HTML/CSS/SVG

**Fully achievable:**
- Card-based finding layout with severity badges (CSS classes)
- `<details>` for expanding finding details (test code, fix diff)
- CSS-only filtering via `:target` selector or checkbox hack (limited)
- Grouping via nested `<details>` (construct > lens > finding)
- Status progression indicator (suspected → proven) as a mini stepper

**Limited without JS:**
- Multi-axis re-grouping (would need separate pre-rendered views)
- Search/filter by text
- Sort by different columns

**Concrete approach:**
- Render each finding as a card `<article>` with data attributes
- Cards wrapped in `<details>` grouped by construct
- Severity badge as colored `<span>` with CSS class
- Prove-fix outcome shown as a 3-step mini-stepper (suspect → test → outcome)
- For simulation mode, include expandable code blocks with test + fix

---

## 4. Heatmap / Matrix Visualizations for Coverage

### Best examples

| Tool | What it does well | URL |
|------|------------------|-----|
| **Testomat.io Heatmap** | 2D grid of test results color-coded by pass/fail density; spots patterns in flaky tests | https://testomat.io/blog/heatmap-test-result-visualizing/ |
| **NDepend DSM** | Square matrix with coupling direction + strength; layered code patterns visible at a glance | https://www.ndepend.com/docs/dependency-structure-matrix-dsm |
| **go-cover-treemap** | SVG treemap of Go packages colored by coverage percentage; rectangle size = lines of code | https://github.com/nikolaydubina/go-cover-treemap |
| **IEEE Matrix Visualization** | Research paper on matrix-based test coverage overview at method granularity | https://ieeexplore.ieee.org/document/9604904 |
| **Hexawise Coverage Matrix** | Grid showing all pairs in a test plan with intersection coverage | https://hexawise.com/posts/introducing-the-hexawise-coverage-matrix |

### Design principles

1. **Two axes, one color**: The construct x lens matrix is our core analytical
   view. Rows = constructs, columns = lenses, cell color = finding severity
   (or count). This is exactly what heatmaps excel at — showing patterns in
   two-dimensional categorical data.

2. **Size encodes importance**: In treemap views, rectangle area maps to a
   quantitative measure (lines of code, method count). For our pipeline,
   construct size (method count or complexity) determines how much audit
   attention it gets. A treemap would show this at a glance.

3. **Color gradient for continuous values**: Coverage tools use green→yellow→red
   gradients. For our matrix: no findings (dark/empty) → low severity (yellow)
   → high severity (red) → proven critical bug (bright red). The empty cells
   (no findings for a construct+lens pair) should be visually distinct from
   "analyzed, nothing found" — use dark gray vs black.

4. **Row/column ordering matters**: NDepend's DSM orders rows/columns to make
   layering visible (upper-triangle = clean layering, lower-triangle = cycles).
   For our matrix, order constructs by cluster membership so clustered
   constructs are adjacent, revealing the data-flow groupings visually.

### Application to our pipeline

**Construct x Lens Heatmap** — the signature visualization for both modes:

```
                    | Contract | Transform | Lifecycle | Concurrency |
  MemoryDataStore   |  ██ 3    |  ██ 2     |  █ 1      |  ███ 4      |
  EncryptionEngine  |  █ 1     |           |  ██ 2     |             |
  KeyManager        |  ██ 3    |  █ 1      |           |  █ 1        |
  ...
```

Cell color = max severity of findings in that cell.
Cell intensity = finding count.
Empty cells are dark.
Row ordering follows cluster membership (horizontal separators between clusters).

For the **"how does this work" mode**: show a small example matrix (4x4) with
annotations explaining what each axis represents.

For the **simulation walkthrough**: show the full matrix with actual data,
clickable cells that expand to show the findings in that construct+lens pair.

### What's achievable in pure HTML/CSS/SVG

**Fully achievable:**
- HTML `<table>` with CSS grid styling
- Cell background-color via CSS classes (severity levels)
- Cell opacity or font-weight encoding count
- Row grouping with `<tbody>` per cluster + CSS border separators
- Hover row/column highlight via CSS `:hover` on `<tr>` and `nth-child`

**Partially achievable:**
- Column highlight on hover (requires a CSS trick: overlay elements or
  `<col>` styling — limited but workable)
- Click-to-expand cell detail (use anchor links to `<details>` sections below)

**Concrete approach:**
- Python renderer builds the construct x lens matrix from findings data
- Render as `<table>` with `<th>` headers for lenses
- Each `<td>` gets a CSS class: `severity-none`, `severity-low`, `severity-med`,
  `severity-high`, `severity-critical`
- CSS custom properties for the color scale on dark background:
  - none: `#1a1a2e` (background)
  - low: `#2d4a3e` (dark green)
  - medium: `#4a4a2d` (dark yellow)
  - high: `#4a2d2d` (dark red)
  - critical: `#e74c3c` (bright red)
- Cluster separators as thicker `border-top` on first row of each cluster group
- Cell text shows finding count; empty cells show `·`

---

## 5. Animated / Progressive Disclosure for Walkthroughs

### Best examples

| Tool | What it does well | URL |
|------|------------------|-----|
| **Stripe API Tour** | Step-by-step walkthrough with code highlighting linked to description; hovering description highlights corresponding code | https://docs.stripe.com/payments-api/tour |
| **NN/g Progressive Disclosure** | Canonical UX research on reducing cognitive load by revealing information in layers | https://www.nngroup.com/articles/progressive-disclosure/ |
| **Ahmad Shadeed Stepper Component** | Detailed CSS implementation of horizontal/vertical steppers with state indicators | https://ishadeed.com/article/stepper-component-html-css/ |
| **Observable Notebooks** | Reactive documents where code + prose + visualization interleave; cells reveal as you scroll | https://observablehq.com/documentation/notebooks/ |
| **CSS `<details>` animation** | Modern CSS `::details-content` pseudo-element enables smooth expand/collapse transitions | https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Selectors/::details-content |

### Design principles

1. **Layer information by audience need**: Show the pipeline overview first (6
   stages, aggregate numbers). Let users drill into any stage. Within a stage,
   show construct list. Within a construct, show findings. Within a finding,
   show prove-fix detail. Each layer answers a progressively more specific
   question.

2. **Stepper for sequential processes**: The prove-fix cycle is inherently
   sequential: suspect → write test → run test → confirm/deny → fix → cascade
   check. A stepper component (circles connected by lines, filled/unfilled for
   complete/pending) is the canonical way to show this.

3. **Description-code linking**: Stripe's pattern of highlighting code when
   hovering over description text is powerful. For our findings, hovering over
   "the test that proved this" could highlight the relevant code block.
   Without JS, this can be approximated with CSS `:target` or checkbox hacks,
   but it's limited.

4. **Scroll-driven narrative**: Observable's model of content revealing as you
   scroll works well for the "how does this work" mode. In pure HTML, this
   maps to a long-scroll document with anchor-linked table of contents.

5. **Animated expand with `::details-content`**: Modern browsers (Chromium)
   support smooth height transitions on `<details>` elements via the
   `::details-content` pseudo-element. This is a progressive enhancement —
   non-supporting browsers get instant expand, which is fine.

### Application to our pipeline

**"How does this work" mode:**
- Top: pipeline overview (6-stage horizontal stepper)
- Each stage is a section with a short explanation + a small example
- Progressive disclosure: stage overview visible, click to see details
- Animated stepper showing data flow counts at each transition
- Sankey diagram at the top for the full-pipeline summary

**"Simulation walkthrough" mode:**
- Top: Sankey showing the full run's funnel (inputs → outputs)
- Below: construct x lens heatmap matrix
- Below that: per-cluster sections, each expandable
- Within each cluster: findings as cards, each expandable
- Within each finding: prove-fix stepper showing the sequential progression
- Fix cascades shown as indented sub-findings triggered by the original fix

### What's achievable in pure HTML/CSS/SVG

**Fully achievable:**
- `<details>`/`<summary>` for all drill-down (already used in current renderer)
- `::details-content` animation as progressive enhancement
- CSS stepper component (flexbox + pseudo-elements + border-radius)
- Anchor-linked table of contents for navigation
- Scroll-margin-top for smooth anchor scrolling via `scroll-behavior: smooth`

**Partially achievable:**
- Description-code highlighting (CSS `:target` changes style of one element
  at a time — workable but not as fluid as Stripe's JS-based version)
- Scroll-driven animation (CSS `animation-timeline: scroll()` is emerging but
  browser support is limited)

**Concrete approach:**
- Prove-fix stepper as a horizontal flexbox:
  ```html
  <div class="stepper">
    <div class="step complete">Suspect</div>
    <div class="step complete">Test Written</div>
    <div class="step active">Proven</div>
    <div class="step">Fixed</div>
    <div class="step">Cascade OK</div>
  </div>
  ```
- CSS: circles via `border-radius: 50%`, connecting line via `::before` pseudo-
  element with `border-top`, fill color by state class
- Each finding card wraps its prove-fix detail in `<details>`
- Navigation: sticky sidebar with anchor links to each cluster/construct
- `scroll-behavior: smooth` on `<html>` for smooth anchor transitions

---

## 6. Graph / Network Visualization Without JavaScript

### Best examples

| Tool/Resource | What it does well | URL |
|---------------|------------------|-----|
| **CSS-Tricks SVG line animation** | Definitive guide to `stroke-dasharray`/`stroke-dashoffset` animation for path drawing effects | https://css-tricks.com/svg-line-animation-works/ |
| **Cassie Evans logo animation** | Complex SVG path drawing with pure CSS, including timing and sequencing | https://www.cassie.codes/posts/creating-my-logo-animation/ |
| **freefrontend Pure CSS Flowcharts** | 17 examples of CSS-only flowcharts with connectors, decision diamonds, process boxes | https://freefrontend.com/css-flowcharts/ |
| **freefrontend Pure CSS Charts** | 31 examples of CSS-only bar charts, pie charts, line charts — no JS | https://freefrontend.com/css-charts-and-graphs/ |
| **Markus Oberlehner SVG Circle Chart** | Animated SVG donut/circle charts with pure CSS animation | https://markus.oberlehner.net/blog/pure-css-animated-svg-circle-chart |

### Design principles

1. **Pre-compute layout, animate presentation**: The key constraint of no-JS is
   that you cannot compute node positions at render time. Solution: compute all
   positions in the Python renderer, emit absolute-positioned SVG elements. CSS
   handles only visual effects (color, opacity, animation), not layout.

2. **stroke-dasharray for flow animation**: Setting `stroke-dasharray` to create
   dashed lines and animating `stroke-dashoffset` creates a "flowing particles"
   effect along SVG paths. This is the single most effective technique for
   showing data flow through a pipeline without JavaScript.

3. **CSS `:hover` on SVG groups**: Wrapping related SVG elements in `<g>` with
   a class allows CSS `:hover` to highlight connected paths. Example: hovering
   over a construct node highlights all paths leading to/from it.

4. **CSS `@keyframes` for sequenced reveals**: Multiple elements can appear in
   sequence using `animation-delay`. For the "how does this work" mode, stages
   can animate in left-to-right with staggered delays.

5. **Layered SVG + HTML**: Use SVG for the graph/flow visualization (paths,
   nodes, connectors) and HTML for the text content (cards, details, tables).
   Position them in the same coordinate space using CSS `position: relative`
   on the container and `position: absolute` on the SVG overlay.

### Application to our pipeline

**Pipeline flow diagram** (both modes):
- 6 stage nodes as rounded rectangles in a horizontal line
- Bezier path connectors between stages
- Animated dashes flowing left-to-right along connectors
- Count labels on each connector showing items flowing between stages
- On hover: highlight the stage and its immediate connections

**Cluster graph** (simulation mode):
- Within the clustering stage, show constructs as circles
- Circles positioned by cluster membership (pre-computed by Python)
- Lines connecting constructs that share data flow or state
- Cluster boundaries as rounded rectangles enclosing member constructs
- Color by construct type (class, interface, enum)

**Fix cascade visualization** (simulation mode):
- When a fix triggers additional fixes, show as a tree
- Parent finding → child findings connected by paths
- Animated path drawing to show cascade propagation
- Color transition from red (bug) to green (fixed) with CSS transition

### What's achievable in pure HTML/CSS/SVG

**Fully achievable:**
- All node positioning (pre-computed, absolute SVG coordinates)
- Flow animation via `stroke-dasharray` + `@keyframes`
- Hover highlighting via CSS `:hover` on `<g>` elements
- Sequential reveal via `animation-delay`
- Dark theme via CSS custom properties on SVG `fill`/`stroke`

**Not achievable without JS:**
- Dynamic zoom/pan (but we can offer pre-set zoom levels as separate SVG viewBoxes)
- Drag to reposition nodes
- Dynamic filtering that hides/shows nodes

**Concrete approach for the pipeline flow SVG:**
```svg
<svg viewBox="0 0 1200 200" class="pipeline-flow">
  <!-- Stage nodes -->
  <g class="stage" data-stage="spec">
    <rect x="10" y="60" width="160" height="80" rx="12" />
    <text x="90" y="105">Spec Analysis</text>
    <text x="90" y="125" class="count">24 reqs</text>
  </g>
  <!-- Connector with flow animation -->
  <path class="connector" d="M 170,100 C 200,100 210,100 240,100"
        stroke-dasharray="8 4" />
  <!-- ... more stages ... -->
</svg>
```

CSS for flow animation:
```css
.connector {
  stroke: var(--color-flow);
  stroke-width: 3;
  fill: none;
  animation: flow 1.5s linear infinite;
}
@keyframes flow {
  to { stroke-dashoffset: -24; }
}
```

---

## Implementation Recommendations

### For "How does this work" mode

**Primary visualization**: Sankey diagram showing the full pipeline funnel
(requirements → constructs → clusters → findings → outcomes). This single image
answers "what does this pipeline do?" better than any prose explanation.

**Supporting elements**:
1. Horizontal stepper showing the 6 stages with brief descriptions
2. Example finding card with annotated anatomy
3. Small 4x4 construct x lens heatmap with explanatory labels
4. Animated SVG pipeline flow with dashed-line particle animation

**Layout**: Long-scroll single page with sticky navigation sidebar.
Sections follow the pipeline stages top-to-bottom. Each section has a
30-word summary visible by default with `<details>` for deeper explanation.

### For "Simulation walkthrough" mode

**Primary visualization**: Construct x lens heatmap matrix — this is the
analytical core that shows where bugs concentrate.

**Supporting elements**:
1. Sankey diagram at top showing the run's funnel (counts at each stage)
2. Per-cluster expandable sections below the heatmap
3. Finding cards with prove-fix steppers inside each cluster section
4. Fix cascade trees for findings that triggered additional fixes
5. Summary statistics bar (total findings, confirmed, cost, duration)

**Layout**: Dashboard-style with the heatmap as the hero element.
Below it, cluster sections organized vertically. Sticky top bar with
aggregate stats. Anchor navigation for jumping to specific clusters.

### Shared technical approach

1. **All layout computed in Python** — the renderer knows all counts, positions,
   and relationships. Emit absolute coordinates in SVG, semantic classes in HTML.

2. **CSS custom properties for theming** — all colors defined as `--color-*`
   variables on `:root`. Dark theme is default. Could support light theme toggle
   via a `<details>` checkbox hack that swaps a class on `<body>`.

3. **Progressive enhancement for animations** — `::details-content` transitions,
   `scroll-behavior: smooth`, `stroke-dasharray` animation all degrade gracefully.
   Non-supporting browsers get a fully functional but static document.

4. **No JavaScript, period** — every interaction is CSS-only: `<details>` for
   expand/collapse, `:hover` for highlights, `:target` for navigation state,
   `scroll-behavior` for smooth scrolling. This keeps the document standalone
   and offline-capable.

5. **Inline everything** — all CSS in `<style>`, all SVG inline in the HTML.
   Single file, no external requests. Matches the existing render_html.py design.

### Color palette (dark theme)

| Purpose | Color | Hex |
|---------|-------|-----|
| Background | Near-black blue | `#0d1117` |
| Surface (cards) | Dark slate | `#161b22` |
| Border | Subtle gray | `#30363d` |
| Text primary | Off-white | `#e6edf3` |
| Text secondary | Gray | `#8b949e` |
| Stage: Spec Analysis | Purple | `#a855f7` |
| Stage: Exploration | Blue | `#3b82f6` |
| Stage: Clustering | Cyan | `#06b6d4` |
| Stage: Finding Gen | Amber | `#f59e0b` |
| Stage: Prove-Fix | Red/Orange | `#ef4444` |
| Stage: Report | Green | `#22c55e` |
| Severity: Critical | Bright red | `#e74c3c` |
| Severity: High | Orange | `#e67e22` |
| Severity: Medium | Yellow | `#f1c40f` |
| Severity: Low | Teal | `#1abc9c` |
| Outcome: Proven | Red | `#e74c3c` |
| Outcome: Impossible | Gray | `#7f8c8d` |
| Outcome: Deferred | Amber | `#f39c12` |
| Outcome: Fixed | Green | `#2ecc71` |
| Flow animation | Accent blue | `#58a6ff` |

This palette is GitHub-dark-inspired, which matches terminal aesthetics and
provides sufficient contrast ratios for accessibility on dark backgrounds.

---

## Sources

### Pipeline visualization
- [Jenkins Blue Ocean](https://www.jenkins.io/doc/book/blueocean/)
- [Jenkins Pipeline Graph View Plugin](https://github.com/jenkinsci/pipeline-graph-view-plugin)
- [Apache Airflow UI Overview](https://airflow.apache.org/docs/apache-airflow/stable/ui.html)
- [Astronomer: 5 Ways to View DAGs](https://www.astronomer.io/blog/5-ways-to-view-and-manage-dags-in-airflow/)
- [Azure DevOps Pipeline Stages](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/stages)
- [dbt Lineage Graph](https://docs.getdbt.com/docs/explore/explore-projects)
- [dbt DAG Best Practices](https://www.getdbt.com/blog/dag-use-cases-and-best-practices)
- [Dagster Pipeline Architecture Patterns](https://dagster.io/guides/data-pipeline-architecture-5-design-patterns-with-examples)

### Sankey and flow diagrams
- [SankeyMATIC](https://sankeymatic.com/)
- [data-to-viz: Sankey](https://www.data-to-viz.com/graph/sankey.html)
- [think.design Sankey Masterclass](https://think.design/services/data-visualization-data-design/sankey-diagram/)
- [doubleslash Data Flow Visualization](https://blog.doubleslash.de/en/data-driven-services/datenvisualisierung/visualization-of-data-flows/)
- [D3 Sankey](https://github.com/d3/d3-sankey)

### Code analysis result visualization
- [SonarQube Issues Management](https://docs.sonarsource.com/sonarqube-server/latest/user-guide/issues/)
- [SonarQube Metrics Definition](https://docs.sonarsource.com/sonarqube-server/user-guide/code-metrics/metrics-definition)
- [Semgrep Triage and Remediation](https://semgrep.dev/docs/semgrep-code/triage-remediation)
- [Semgrep AI Noise Filtering](https://semgrep.dev/blog/2025/announcing-ai-noise-filtering-and-triage-memories/)
- [NDepend DSM](https://www.ndepend.com/docs/dependency-structure-matrix-dsm)
- [Code Quality Tools Comparison 2026](https://www.qodo.ai/blog/code-analysis-tools/)

### Heatmap and matrix visualization
- [Testomat.io Heatmap](https://testomat.io/blog/heatmap-test-result-visualizing/)
- [NDepend DSM](https://www.ndepend.com/docs/dependency-structure-matrix-dsm)
- [go-cover-treemap](https://github.com/nikolaydubina/go-cover-treemap)
- [IEEE Matrix Visualization Paper](https://ieeexplore.ieee.org/document/9604904)
- [Hexawise Coverage Matrix](https://hexawise.com/posts/introducing-the-hexawise-coverage-matrix)
- [Dependency Analysis as Heat Map (Springer)](https://link.springer.com/chapter/10.1007/978-3-319-11617-4_2)

### Progressive disclosure and walkthroughs
- [Stripe API Tour](https://docs.stripe.com/payments-api/tour)
- [NN/g Progressive Disclosure](https://www.nngroup.com/articles/progressive-disclosure/)
- [Ahmad Shadeed: Stepper Component](https://ishadeed.com/article/stepper-component-html-css/)
- [Observable Notebooks](https://observablehq.com/documentation/notebooks/)
- [MDN: ::details-content](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Selectors/::details-content)
- [CSS-Tricks: Styling Details Element](https://css-tricks.com/using-styling-the-details-element/)
- [LogRocket: Styling Details/Summary](https://blog.logrocket.com/styling-html-modern-css/)
- [Animate Details Element](https://linkedlist.ch/animate_details_element_60/)

### SVG and CSS animation
- [CSS-Tricks: SVG Line Animation](https://css-tricks.com/svg-line-animation-works/)
- [Cassie Evans: SVG Path Animation](https://www.cassie.codes/posts/creating-my-logo-animation/)
- [freefrontend: Pure CSS Flowcharts](https://freefrontend.com/css-flowcharts/)
- [freefrontend: Pure CSS Charts](https://freefrontend.com/css-charts-and-graphs/)
- [Markus Oberlehner: CSS SVG Circle Chart](https://markus.oberlehner.net/blog/pure-css-animated-svg-circle-chart/)
- [LogRocket: Animate SVG with CSS](https://blog.logrocket.com/how-to-animate-svg-css-tutorial-examples/)
- [CSS3Shapes: Animating SVG Paths](https://css3shapes.com/animating-svg-paths-with-css/)
- [W3Schools: CSS Timeline](https://www.w3schools.com/howto/howto_css_timeline.asp)
