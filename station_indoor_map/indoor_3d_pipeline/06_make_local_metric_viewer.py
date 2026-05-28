#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Create a standalone HTML viewer for a local metric indoor graph."""

from __future__ import annotations

import argparse
import html
import json
from pathlib import Path


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


HTML_TEMPLATE = """<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{title}</title>
  <style>
    :root {{
      color-scheme: light;
      --bg: #f6f7f9;
      --panel: #ffffff;
      --ink: #1f2933;
      --muted: #64748b;
      --line: #d8dee8;
      --walk: #2563eb;
      --vertical: #d44b2f;
      --platform: #a43fb6;
      --node: #111827;
      --entrance: #1f9d55;
      --hall: #0f70b7;
      --warn: #b45309;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: Arial, "Malgun Gothic", sans-serif;
      background: var(--bg);
      color: var(--ink);
    }}
    header {{
      padding: 18px 22px 12px;
      border-bottom: 1px solid var(--line);
      background: var(--panel);
    }}
    h1 {{
      margin: 0 0 10px;
      font-size: 21px;
      letter-spacing: 0;
    }}
    .meta {{
      display: flex;
      flex-wrap: wrap;
      gap: 8px 16px;
      color: var(--muted);
      font-size: 13px;
    }}
    main {{
      display: grid;
      grid-template-columns: minmax(0, 1fr);
      gap: 14px;
      padding: 14px;
    }}
    section {{
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      overflow: hidden;
    }}
    section h2 {{
      margin: 0;
      padding: 11px 13px;
      font-size: 15px;
      border-bottom: 1px solid var(--line);
    }}
    svg {{
      display: block;
      width: 100%;
      height: 560px;
      background: white;
    }}
    .profile svg {{ height: 320px; }}
    .warnings {{
      max-height: 260px;
      overflow: auto;
      padding: 10px 13px 13px;
      font-size: 12px;
      color: var(--ink);
    }}
    .warning {{
      padding: 7px 0;
      border-bottom: 1px solid #edf0f4;
    }}
    .warning strong {{ color: var(--warn); }}
    .legend {{
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      padding: 10px 13px 13px;
      color: var(--muted);
      font-size: 13px;
    }}
    .key {{
      display: inline-flex;
      align-items: center;
      gap: 6px;
    }}
    .swatch {{
      width: 10px;
      height: 10px;
      border-radius: 999px;
      background: var(--node);
      display: inline-block;
    }}
    .swatch.entrance {{ background: var(--entrance); }}
    .swatch.hall {{ background: var(--hall); }}
    .swatch.platform {{ background: var(--platform); }}
    .swatch.edge {{
      width: 18px;
      height: 3px;
      border-radius: 0;
      background: var(--walk);
    }}
    .swatch.vertical {{
      width: 18px;
      height: 3px;
      border-radius: 0;
      background: var(--vertical);
    }}
    .node-label {{
      font-size: 10.5px;
      paint-order: stroke;
      stroke: white;
      stroke-width: 4px;
      stroke-linejoin: round;
      fill: #111827;
    }}
    .axis-label {{
      font-size: 11px;
      fill: #64748b;
    }}
    .tooltip {{
      position: fixed;
      pointer-events: none;
      display: none;
      max-width: 380px;
      padding: 8px 10px;
      border: 1px solid var(--line);
      background: white;
      border-radius: 6px;
      box-shadow: 0 8px 24px rgba(31, 41, 51, 0.16);
      font-size: 12px;
      white-space: pre-line;
      z-index: 5;
    }}
  </style>
</head>
<body>
  <header>
    <h1>{title}</h1>
    <div class="meta">
      <span>nodes: <strong id="node-count"></strong></span>
      <span>edges: <strong id="edge-count"></strong></span>
      <span>scale: <strong id="scale"></strong></span>
      <span>projection y: <strong id="projection"></strong></span>
      <span>warnings: <strong id="warning-count"></strong></span>
    </div>
  </header>
  <main>
    <section>
      <h2>Local XY Metric Graph</h2>
      <svg id="xy"></svg>
      <div class="legend">
        <span class="key"><span class="swatch entrance"></span>entrance</span>
        <span class="key"><span class="swatch hall"></span>hall/turn</span>
        <span class="key"><span class="swatch platform"></span>platform</span>
        <span class="key"><span class="swatch edge"></span>walk</span>
        <span class="key"><span class="swatch vertical"></span>vertical</span>
      </div>
    </section>
    <section class="profile">
      <h2>Local XZ Profile</h2>
      <svg id="xz"></svg>
    </section>
    <section>
      <h2>Validation Warnings</h2>
      <div id="warnings" class="warnings"></div>
    </section>
  </main>
  <div id="tooltip" class="tooltip"></div>
  <script id="graph-data" type="application/json">{graph_json}</script>
  <script>
    const graph = JSON.parse(document.getElementById("graph-data").textContent);
    const nodes = graph.nodes || [];
    const edges = graph.edges || [];
    const byId = new Map(nodes.map(n => [n.id, n]));
    const warnings = graph.validation?.warnings || [];

    document.getElementById("node-count").textContent = nodes.length;
    document.getElementById("edge-count").textContent = edges.length;
    document.getElementById("scale").textContent = `${{(graph.scale?.meters_per_pixel || 0).toFixed(6)}} m/px`;
    document.getElementById("projection").textContent = graph.coordinate_policy?.projection_y_scale ?? 1;
    document.getElementById("warning-count").textContent = warnings.length;

    const warningBox = document.getElementById("warnings");
    warningBox.innerHTML = warnings.length
      ? warnings.map(w => `<div class="warning"><strong>${{w.type}}</strong><br>${{w.from || ""}} -> ${{w.to || ""}} ${{w.kind ? "(" + w.kind + ")" : ""}}<br>${{w.message || ""}}</div>`).join("")
      : `<div class="warning">No validation warnings.</div>`;

    const tooltip = document.getElementById("tooltip");

    function nodeColor(n) {{
      const k = (n.kind || "").toLowerCase();
      if (k.includes("entrance") || k === "exit") return "var(--entrance)";
      if (k.includes("platform")) return "var(--platform)";
      if (k.includes("hall") || k.includes("turn")) return "var(--hall)";
      return "var(--node)";
    }}

    function edgeColor(e) {{
      const k = (e.kind || "").toLowerCase();
      if (k.includes("stairs") || k.includes("elevator") || k.includes("escalator")) return "var(--vertical)";
      if (k.includes("platform")) return "var(--platform)";
      return "var(--walk)";
    }}

    function extent(values) {{
      return [Math.min(...values), Math.max(...values)];
    }}

    function scale(v, d0, d1, r0, r1) {{
      if (Math.abs(d1 - d0) < 1e-9) return (r0 + r1) / 2;
      return r0 + (v - d0) * (r1 - r0) / (d1 - d0);
    }}

    function showTip(evt, text) {{
      tooltip.textContent = text;
      tooltip.style.display = "block";
      tooltip.style.left = `${{evt.clientX + 12}}px`;
      tooltip.style.top = `${{evt.clientY + 12}}px`;
    }}

    function hideTip() {{
      tooltip.style.display = "none";
    }}

    function draw(svgId, mode) {{
      const svg = document.getElementById(svgId);
      const rect = svg.getBoundingClientRect();
      const width = rect.width || 1000;
      const height = rect.height || 500;
      const pad = 48;
      svg.setAttribute("viewBox", `0 0 ${{width}} ${{height}}`);
      svg.innerHTML = "";

      const xs = nodes.map(n => n.local_xyz_m[0]);
      const ys = mode === "xy" ? nodes.map(n => n.local_xyz_m[1]) : nodes.map(n => n.z_m ?? n.local_xyz_m[2] ?? 0);
      const [minX, maxX] = extent(xs);
      const [minY, maxY] = extent(ys);

      function px(n) {{ return scale(n.local_xyz_m[0], minX, maxX, pad, width - pad); }}
      function py(n) {{
        const y = mode === "xy" ? n.local_xyz_m[1] : (n.z_m ?? n.local_xyz_m[2] ?? 0);
        return scale(y, minY, maxY, height - pad, pad);
      }}

      for (const e of edges) {{
        const a = byId.get(e.from);
        const b = byId.get(e.to);
        if (!a || !b) continue;
        const line = document.createElementNS("http://www.w3.org/2000/svg", "line");
        line.setAttribute("x1", px(a));
        line.setAttribute("y1", py(a));
        line.setAttribute("x2", px(b));
        line.setAttribute("y2", py(b));
        line.setAttribute("stroke", edgeColor(e));
        line.setAttribute("stroke-width", mode === "xy" ? 2.4 : 2);
        line.setAttribute("stroke-linecap", "round");
        line.setAttribute("opacity", "0.76");
        line.addEventListener("mousemove", evt => showTip(evt,
          `${{e.from}} -> ${{e.to}}\\nkind: ${{e.kind || ""}}\\npx: ${{(e.distance_px || 0).toFixed(1)}}\\n2D: ${{(e.distance_2d_m || 0).toFixed(2)}}m\\n3D/cost: ${{(e.cost_m || e.distance_3d_m || 0).toFixed(2)}}m`));
        line.addEventListener("mouseleave", hideTip);
        svg.appendChild(line);
      }}

      for (const n of nodes) {{
        const circle = document.createElementNS("http://www.w3.org/2000/svg", "circle");
        circle.setAttribute("cx", px(n));
        circle.setAttribute("cy", py(n));
        circle.setAttribute("r", 5.5);
        circle.setAttribute("fill", nodeColor(n));
        circle.setAttribute("stroke", "white");
        circle.setAttribute("stroke-width", 1.5);
        circle.addEventListener("mousemove", evt => showTip(evt,
          `${{n.id}}\\nkind: ${{n.kind || ""}}\\nfloor: ${{n.floor || ""}}\\nz: ${{(n.z_m || 0).toFixed(2)}}m\\nimage: ${{n.image_xy.join(", ")}}\\nlocal: ${{n.local_xy_m.map(v => v.toFixed(2)).join(", ")}}`));
        circle.addEventListener("mouseleave", hideTip);
        svg.appendChild(circle);

        const label = document.createElementNS("http://www.w3.org/2000/svg", "text");
        label.setAttribute("x", px(n) + 7);
        label.setAttribute("y", py(n) - 7);
        label.setAttribute("class", "node-label");
        label.textContent = n.click_index ?? n.id;
        svg.appendChild(label);
      }}

      const axis = document.createElementNS("http://www.w3.org/2000/svg", "text");
      axis.setAttribute("x", pad);
      axis.setAttribute("y", height - 16);
      axis.setAttribute("class", "axis-label");
      axis.textContent = mode === "xy" ? "Local metric coordinates, not EPSG" : "Local X axis vs z_m";
      svg.appendChild(axis);
    }}

    draw("xy", "xy");
    draw("xz", "xz");
    window.addEventListener("resize", () => {{
      draw("xy", "xy");
      draw("xz", "xz");
    }});
  </script>
</body>
</html>
"""


def main() -> None:
    parser = argparse.ArgumentParser(description="Create standalone local metric graph viewer.")
    parser.add_argument("--graph", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    graph = load_json(Path(args.graph))
    title = f"{graph.get('station_name', 'Indoor')} Local Metric Viewer"
    graph_json = html.escape(json.dumps(graph, ensure_ascii=False), quote=False)
    page = HTML_TEMPLATE.format(title=html.escape(title), graph_json=graph_json)

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(page, encoding="utf-8")
    print(f"[OK] viewer saved: {out_path}")


if __name__ == "__main__":
    main()
