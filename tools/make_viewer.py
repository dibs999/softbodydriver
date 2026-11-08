#!/usr/bin/env python3
"""Bundles one or more `sbsim --record` JSON files into a self-contained HTML 3D viewer.

Usage:
    python3 tools/make_viewer.py --out viewer.html head_on_crash.json t_bone_crash.json ...
"""

import argparse
import json
from pathlib import Path

TEMPLATE = r"""<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>SoftBodyDriver – 3D-Physik-Replay (Phase 3)</title>
<script src="https://www.gstatic.com/antigravity/web/dev/tailwindcss.min.js"></script>
<style>
  :root {
    --background: #0f172a;
    --foreground: #f8fafc;
    --card: #1e293b;
    --border: #334155;
    --secondary: #334155;
    --secondary-foreground: #e2e8f0;
    --muted-foreground: #94a3b8;
    --primary: #38bdf8;
    --primary-foreground: #0f172a;
  }
  *, *::before, *::after { box-sizing: border-box; }
  html, body {
    margin: 0; padding: 0;
    background: var(--background);
    color: var(--foreground);
    font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
    font-size: 13px;
    -webkit-font-smoothing: antialiased;
    user-select: none;
  }
  canvas { display: block; width: 100%; touch-action: none; }
  .sbd-container { max-width: 1180px; margin: 0 auto; padding: 14px; display: flex; flex-direction: column; gap: 10px; }
  .sbd-card {
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 12px 16px;
    box-shadow: 0 4px 16px rgba(0,0,0,0.25);
  }
  .sbd-header { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 12px; }
  .sbd-title-row { display: flex; align-items: center; gap: 8px; }
  .sbd-title { font-weight: 600; font-size: 15px; color: var(--foreground); }
  .sbd-badge {
    font-size: 12px; padding: 2px 8px; border-radius: 6px;
    background: var(--secondary); color: var(--secondary-foreground); font-weight: 500;
  }
  .sbd-desc { color: var(--muted-foreground); font-size: 12px; margin: 4px 0 0 0; }
  .sbd-tabs { display: flex; flex-wrap: wrap; gap: 6px; }
  .sbd-tab {
    font-size: 12px; padding: 5px 10px; border-radius: 8px;
    border: 1px solid var(--border); background: transparent; color: var(--foreground);
    cursor: pointer; transition: all 0.15s ease;
  }
  .sbd-tab:hover { background: var(--secondary); }
  .sbd-tab.active {
    background: var(--primary); color: var(--primary-foreground);
    border-color: transparent; font-weight: 600;
  }
  .sbd-viewport {
    position: relative; background: #0b1220;
    border: 1px solid var(--border); border-radius: 12px; overflow: hidden;
    box-shadow: 0 4px 20px rgba(0,0,0,0.35);
  }
  .sbd-hud {
    position: absolute; top: 12px; left: 12px;
    background: rgba(15, 23, 42, 0.88);
    backdrop-filter: blur(8px);
    border: 1px solid var(--border);
    border-radius: 10px; padding: 10px 12px;
    font-size: 12px; min-width: 235px; pointer-events: none;
  }
  .sbd-hud-title { font-weight: 600; font-size: 13px; margin-bottom: 6px; color: #38bdf8; }
  .sbd-hud-grid { display: grid; grid-template-columns: auto auto; gap: 3px 14px; color: var(--muted-foreground); }
  .sbd-mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; color: var(--foreground); text-align: right; }
  .sbd-amber { color: #fbbf24; }
  .sbd-rose { color: #fb7185; }
  .sbd-tel { margin-top: 8px; padding-top: 8px; border-top: 1px solid var(--border); display: flex; flex-direction: column; gap: 6px; }
  .sbd-tel.hidden { display: none !important; }
  .sbd-gear-badge {
    display: inline-block; padding: 1px 6px; border-radius: 4px;
    background: rgba(56, 189, 248, 0.2); color: #7dd3fc; font-weight: 700; margin-right: 6px;
  }
  .sbd-bar-bg { width: 100%; height: 6px; background: rgba(51, 65, 85, 0.7); border-radius: 4px; overflow: hidden; margin-top: 2px; }
  .sbd-bar-rpm { height: 100%; background: linear-gradient(90deg, #38bdf8, #fbbf24, #f43f5e); }
  .sbd-bar-thr { height: 100%; background: #34d399; }
  .sbd-bar-brk { height: 100%; background: #f43f5e; }
  .sbd-cam-bar { position: absolute; top: 12px; right: 12px; display: flex; flex-wrap: wrap; gap: 6px; }
  .sbd-btn {
    font-size: 12px; padding: 5px 10px; border-radius: 8px;
    border: 1px solid var(--border); background: rgba(30, 41, 59, 0.9); color: var(--foreground);
    cursor: pointer; display: inline-flex; align-items: center; gap: 5px;
  }
  .sbd-btn:hover { background: var(--secondary); }
  .sbd-btn-primary { background: var(--primary); color: var(--primary-foreground); border-color: transparent; font-weight: 600; }
  .sbd-legend {
    position: absolute; bottom: 12px; left: 12px;
    display: flex; flex-wrap: wrap; align-items: center; gap: 12px;
    font-size: 12px; background: rgba(15, 23, 42, 0.88);
    border: 1px solid var(--border); border-radius: 8px; padding: 6px 12px; pointer-events: none;
  }
  .sbd-dot { display: inline-block; width: 9px; height: 9px; border-radius: 999px; margin-right: 5px; }
  .sbd-controls { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; }
  .sbd-scrub { flex: 1; min-width: 160px; accent-color: #38bdf8; cursor: pointer; }
  .sbd-select {
    background: var(--background); color: var(--foreground);
    border: 1px solid var(--border); border-radius: 6px; padding: 4px 8px; font-size: 12px;
  }
</style>
</head>
<body class="bg-[var(--background,#0f172a)] text-[var(--foreground,#f8fafc)] antialiased select-none">
<div class="sbd-container max-w-6xl mx-auto p-4 flex flex-col gap-3">
  <div class="sbd-card sbd-header">
    <div>
      <div class="sbd-title-row">
        <span class="sbd-title">SoftBodyDriver – C++-Physik-Kern (2000 Hz)</span>
        <span class="sbd-badge">Phase 3 · ColTris, Fahrzeug-Crashs &amp; Terrain</span>
      </div>
      <p id="sceneDesc" class="sbd-desc"></p>
    </div>
    <div id="sceneTabs" class="sbd-tabs"></div>
  </div>

  <div class="sbd-viewport">
    <canvas id="view" style="height: 430px;"></canvas>

    <div class="sbd-hud">
      <div class="sbd-hud-title" id="hudTitle"></div>
      <div class="sbd-hud-grid">
        <span>Zeit:</span><span id="hudTime" class="sbd-mono"></span>
        <span>Geschwindigkeit:</span><span id="hudSpeed" class="sbd-mono" style="font-weight:600"></span>
        <span>Nodes / Beams:</span><span id="hudTopo" class="sbd-mono"></span>
        <span>ColTri-Flächen:</span><span id="hudTris" class="sbd-mono"></span>
        <span>Verbeult (&gt;1%):</span><span id="hudDeformed" class="sbd-mono sbd-amber"></span>
        <span>Gebrochen:</span><span id="hudBroken" class="sbd-mono sbd-rose"></span>
      </div>
      <div id="hudTelemetry" class="sbd-tel hidden">
        <div style="display:flex;align-items:center;justify-content:space-between;">
          <span style="color:var(--muted-foreground)">Gang / Drehzahl:</span>
          <span class="sbd-mono"><span id="hudGear" class="sbd-gear-badge">1</span><span id="hudRpm">850</span> RPM</span>
        </div>
        <div class="sbd-bar-bg">
          <div id="hudRpmBar" class="sbd-bar-rpm" style="width:15%"></div>
        </div>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;padding-top:2px;">
          <div>
            <div style="display:flex;justify-content:space-between;color:var(--muted-foreground)"><span>Gas</span><span id="hudThr" class="sbd-mono">0%</span></div>
            <div class="sbd-bar-bg"><div id="hudThrBar" class="sbd-bar-thr" style="width:0%"></div></div>
          </div>
          <div>
            <div style="display:flex;justify-content:space-between;color:var(--muted-foreground)"><span>Bremse</span><span id="hudBrk" class="sbd-mono">0%</span></div>
            <div class="sbd-bar-bg"><div id="hudBrkBar" class="sbd-bar-brk" style="width:0%"></div></div>
          </div>
        </div>
      </div>
    </div>

    <div class="sbd-cam-bar">
      <button data-cam="perspective" class="camBtn sbd-btn">Schräg</button>
      <button data-cam="side" class="camBtn sbd-btn">Seite</button>
      <button data-cam="front" class="camBtn sbd-btn">Vorne</button>
      <button data-cam="top" class="camBtn sbd-btn">Oben</button>
      <label class="sbd-btn">
        <input id="followCam" type="checkbox" checked /> Kamera folgt
      </label>
    </div>

    <div class="sbd-legend">
      <span><span class="sbd-dot" style="background:#38bdf8"></span>Fahrzeug 1</span>
      <span><span class="sbd-dot" style="background:#c084fc"></span>Fahrzeug 2</span>
      <span><span class="sbd-dot" style="background:#34d399"></span>Pressure-Wheels</span>
      <span><span class="sbd-dot" style="background:#fbbf24"></span>Last / Dehnung</span>
      <span><span class="sbd-dot" style="background:#f43f5e"></span>Verbeult</span>
    </div>
  </div>

  <div class="sbd-card sbd-controls">
    <button id="playBtn" class="sbd-btn sbd-btn-primary">Pause</button>
    <button id="stepBack" class="sbd-btn">-1</button>
    <button id="stepFwd" class="sbd-btn">+1</button>
    <input id="scrub" type="range" min="0" max="100" value="0" class="sbd-scrub" />
    <div style="display:flex;align-items:center;gap:6px;font-size:12px;">
      <span style="color:var(--muted-foreground)">Tempo:</span>
      <select id="speedSel" class="sbd-select">
        <option value="0.2">0.2× (Zeitlupe)</option>
        <option value="0.5">0.5×</option>
        <option value="1" selected>1.0×</option>
        <option value="2">2.0×</option>
      </select>
    </div>
    <label class="sbd-btn" style="background:transparent">
      <input id="showTris" type="checkbox" checked /> ColTri-Flächen
    </label>
    <label class="sbd-btn" style="background:transparent">
      <input id="showNodes" type="checkbox" checked /> Nodes
    </label>
    <label class="sbd-btn" style="background:transparent">
      <input id="showBroken" type="checkbox" /> gebrochene Beams
    </label>
  </div>
</div>

<script>
const SCENES = __SCENES_JSON__;

const LABELS = {
  head_on_crash: "Frontal-Crash (2 Autos)",
  t_bone_crash: "Kreuzungs-Crash (T-Bone)",
  hill_climb: "Hügel-Terrain (Heightfield)",
  accel_brake: "Sprint & Vollbremsung",
  slalom: "Slalom (Hydro-Lenkung)",
  curb_impact: "Bordstein-Einschlag",
  wall_crash: "50 km/h Wand-Crash",
  ramp_jump: "80 km/h Rampensprung",
  bridge_overload: "Brücken-Überlast",
  cube_drop: "Würfel-Falltest"
};

let sceneIdx = 0;
let scene = null;
let framePos = 0;
let playing = true;
let speed = 1.0;

let camYaw = 0.55, camPitch = 0.32, camDist = 9.0;
let camTarget = [0, 0.8, 0];
let panOffset = [0, 0, 0];

function prepareScene(idx) {
  sceneIdx = idx;
  scene = SCENES[idx];
  framePos = 0;
  panOffset = [0, 0, 0];

  const f0 = scene.frames[0];
  scene._restLen = [];
  scene._brokenAt = [];
  scene._brokenTrisAt = [];
  scene._wheelBeamSet = [];
  for (let bi = 0; bi < scene.bodies.length; ++bi) {
    const b = scene.bodies[bi];
    const p = f0.p[bi];
    const nb = b.beams.length / 2;
    const rl = new Float32Array(nb);
    for (let i = 0; i < nb; ++i) {
      const a = b.beams[2*i]*3, c = b.beams[2*i+1]*3;
      const dx = p[c]-p[a], dy = p[c+1]-p[a+1], dz = p[c+2]-p[a+2];
      rl[i] = Math.hypot(dx, dy, dz) || 1;
    }
    scene._restLen.push(rl);

    const wb = new Uint8Array(nb);
    if (b.wheelBeams) for (const k of b.wheelBeams) if (k < nb) wb[k] = 1;
    scene._wheelBeamSet.push(wb);

    const brokenFrames = [];
    const cur = new Uint8Array(nb);
    let count = 0;
    for (let fi = 0; fi < scene.frames.length; ++fi) {
      const nbList = scene.frames[fi].b && scene.frames[fi].b[bi];
      if (nbList) for (const k of nbList) { if (!cur[k]) { cur[k] = 1; ++count; } }
      brokenFrames.push({flags: new Uint8Array(cur), count});
    }
    scene._brokenAt.push(brokenFrames);

    const nt = b.triangles ? (b.triangles.length / 3) : 0;
    const brokenTriFrames = [];
    const curT = new Uint8Array(nt);
    let countT = 0;
    for (let fi = 0; fi < scene.frames.length; ++fi) {
      const btList = scene.frames[fi].bt && scene.frames[fi].bt[bi];
      if (btList) for (const k of btList) { if (!curT[k]) { curT[k] = 1; ++countT; } }
      brokenTriFrames.push({flags: new Uint8Array(curT), count: countT});
    }
    scene._brokenTrisAt.push(brokenTriFrames);
  }

  if (scene.scene === "bridge_overload") {
    camYaw = 0.35; camPitch = 0.25; camDist = 11.5;
    document.getElementById("followCam").checked = false;
    camTarget = [0, 2.5, 0];
  } else if (scene.scene === "cube_drop") {
    camYaw = 0.7; camPitch = 0.35; camDist = 5.5;
    document.getElementById("followCam").checked = false;
    camTarget = [0, 1.0, 0];
  } else if (scene.scene === "head_on_crash") {
    camYaw = 0.32; camPitch = 0.32; camDist = 11.0;
    document.getElementById("followCam").checked = true;
    camTarget = [0, 0.8, 0];
  } else if (scene.scene === "t_bone_crash") {
    camYaw = 0.68; camPitch = 0.38; camDist = 11.5;
    document.getElementById("followCam").checked = true;
    camTarget = [-1.5, 0.8, -1.5];
  } else if (scene.scene === "hill_climb") {
    camYaw = 0.35; camPitch = 0.26; camDist = 8.8;
    document.getElementById("followCam").checked = true;
  } else if (scene.scene === "slalom") {
    camYaw = -1.15; camPitch = 0.32; camDist = 8.5;
    document.getElementById("followCam").checked = true;
  } else {
    camYaw = 0.48; camPitch = 0.25; camDist = 6.8;
    document.getElementById("followCam").checked = true;
  }

  document.getElementById("sceneDesc").textContent = scene.description || "";
  document.getElementById("hudTitle").textContent = LABELS[scene.scene] || scene.scene;
  const scrub = document.getElementById("scrub");
  scrub.max = Math.max(0, scene.frames.length - 1);
  scrub.value = 0;
  renderTabs();
}

function renderTabs() {
  const host = document.getElementById("sceneTabs");
  host.innerHTML = "";
  SCENES.forEach((s, i) => {
    const btn = document.createElement("button");
    const active = i === sceneIdx;
    btn.className = "sbd-tab " + (active ? "active" : "");
    btn.textContent = LABELS[s.scene] || s.scene;
    btn.onclick = () => prepareScene(i);
    host.appendChild(btn);
  });
}

const canvas = document.getElementById("view");
const ctx = canvas.getContext("2d");

function sub(a,b){return [a[0]-b[0],a[1]-b[1],a[2]-b[2]];}
function add(a,b){return [a[0]+b[0],a[1]+b[1],a[2]+b[2]];}
function dot(a,b){return a[0]*b[0]+a[1]*b[1]+a[2]*b[2];}
function cross(a,b){return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];}
function norm(a){const l=Math.hypot(a[0],a[1],a[2])||1;return [a[0]/l,a[1]/l,a[2]/l];}

function makeCamera(w, h) {
  const cp = Math.cos(camPitch), sp = Math.sin(camPitch);
  const cy = Math.cos(camYaw), sy = Math.sin(camYaw);
  const tgt = add(camTarget, panOffset);
  const eye = [tgt[0] + camDist*cp*sy, tgt[1] + camDist*sp, tgt[2] + camDist*cp*cy];
  const fwd = norm(sub(tgt, eye));
  const right = norm(cross(fwd, [0,1,0]));
  const up = cross(right, fwd);
  const f = h * 0.95;
  return {
    eye, fwd, right, up,
    project(p) {
      const d = sub(p, eye);
      const z = dot(d, fwd);
      if (z <= 0.15) return null;
      const x = dot(d, right), y = dot(d, up);
      return [w*0.5 + (x/z)*f, h*0.5 - (y/z)*f, z];
    }
  };
}

function drawLine3D(cam, a, b, color, width = 1.4) {
  const pa = cam.project(a), pb = cam.project(b);
  if (!pa || !pb) return;
  ctx.strokeStyle = color;
  ctx.lineWidth = width;
  ctx.beginPath();
  ctx.moveTo(pa[0], pa[1]);
  ctx.lineTo(pb[0], pb[1]);
  ctx.stroke();
}

function drawBoxCollider(cam, c, isLight) {
  const [hx, hy, hz] = c.half;
  const r = c.rot;
  const corners = [];
  for (let i = 0; i < 8; ++i) {
    const lx = (i&1)?hx:-hx, ly = (i&2)?hy:-hy, lz = (i&4)?hz:-hz;
    corners.push([
      c.center[0] + r[0]*lx + r[1]*ly + r[2]*lz,
      c.center[1] + r[3]*lx + r[4]*ly + r[5]*lz,
      c.center[2] + r[6]*lx + r[7]*ly + r[8]*lz,
    ]);
  }
  const faces = [[0,1,3,2],[4,6,7,5],[0,4,5,1],[2,3,7,6],[0,2,6,4],[1,5,7,3]];
  ctx.fillStyle = isLight ? "rgba(100,116,139,0.25)" : "rgba(148,163,184,0.18)";
  for (const f of faces) {
    const pts = f.map(k => cam.project(corners[k]));
    if (pts.some(p => !p)) continue;
    ctx.beginPath();
    ctx.moveTo(pts[0][0], pts[0][1]);
    for (let i = 1; i < 4; ++i) ctx.lineTo(pts[i][0], pts[i][1]);
    ctx.closePath();
    ctx.fill();
  }
  const edges = [[0,1],[1,3],[3,2],[2,0],[4,5],[5,7],[7,6],[6,4],[0,4],[1,5],[2,6],[3,7]];
  const edgeCol = isLight ? "rgba(71,85,105,0.7)" : "rgba(148,163,184,0.55)";
  for (const [a,b] of edges) drawLine3D(cam, corners[a], corners[b], edgeCol, 1.2);
}

function drawHeightfield(cam, c, isLight) {
  const ox = c.origin[0], oz = c.origin[2];
  const dx = c.cellSizeX, dz = c.cellSizeZ;
  const nx = c.nx, nz = c.nz;
  const h = c.heights;
  const pt = (ix, iz) => [ox + ix*dx, h[ix*nz + iz], oz + iz*dz];

  // Shaded terrain cells (subsampled by 2 for crisp rendering)
  const step = 2;
  for (let ix = 0; ix + step < nx; ix += step) {
    for (let iz = 0; iz + step < nz; iz += step) {
      const p00 = pt(ix, iz), p10 = pt(ix + step, iz);
      const p11 = pt(ix + step, iz + step), p01 = pt(ix, iz + step);
      const s00 = cam.project(p00), s10 = cam.project(p10);
      const s11 = cam.project(p11), s01 = cam.project(p01);
      if (!s00 || !s10 || !s11 || !s01) continue;
      const avgH = 0.25 * (p00[1] + p10[1] + p11[1] + p01[1]);
      const t = Math.max(0, Math.min(1, (avgH + 0.3) / 1.7));
      const r = Math.round(30 + t * 45);
      const g = Math.round(58 + t * 95);
      const b = Math.round(85 + t * 40);
      ctx.fillStyle = isLight ? `rgba(${r},${g},${b},0.22)` : `rgba(${r},${g},${b},0.28)`;
      ctx.beginPath();
      ctx.moveTo(s00[0], s00[1]);
      ctx.lineTo(s10[0], s10[1]);
      ctx.lineTo(s11[0], s11[1]);
      ctx.lineTo(s01[0], s01[1]);
      ctx.closePath();
      ctx.fill();
    }
  }

  const lineCol = isLight ? "rgba(51,65,85,0.32)" : "rgba(148,163,184,0.24)";
  for (let ix = 0; ix < nx; ix += 2) {
    for (let iz = 0; iz + 1 < nz; ++iz) drawLine3D(cam, pt(ix, iz), pt(ix, iz+1), lineCol, 1.0);
  }
  for (let iz = 0; iz < nz; iz += 2) {
    for (let ix = 0; ix + 1 < nx; ++ix) drawLine3D(cam, pt(ix, iz), pt(ix+1, iz), lineCol, 1.0);
  }
}

function strainColor(strain, isWheel, bodyIdx, isLight) {
  const s = Math.min(1, strain / 0.12);
  if (s < 0.08) {
    if (isWheel) return isLight ? "#059669" : "#34d399";
    if (bodyIdx === 1) return isLight ? "#9333ea" : "#c084fc";
    return isLight ? "#0284c7" : "#38bdf8";
  }
  if (s < 0.45) {
    const t = (s - 0.08) / 0.37;
    const r = Math.round(56 + t*(251-56));
    const g = Math.round(189 + t*(191-189));
    const b = Math.round(248 * (1 - t*0.85));
    return `rgb(${r},${g},${b})`;
  }
  const t = (s - 0.45) / 0.55;
  const r = 244;
  const g = Math.round(180 * (1 - t*0.78));
  const b = Math.round(36 + t*30);
  return `rgb(${r},${g},${b})`;
}

function render() {
  const dpr = window.devicePixelRatio || 1;
  const w = canvas.clientWidth, h = canvas.clientHeight;
  if (canvas.width !== Math.round(w*dpr) || canvas.height !== Math.round(h*dpr)) {
    canvas.width = Math.round(w*dpr);
    canvas.height = Math.round(h*dpr);
  }
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

  const isLight = document.documentElement.classList.contains("light");
  ctx.fillStyle = isLight ? "#f1f5f9" : "#0b1220";
  ctx.fillRect(0, 0, w, h);

  const fi = Math.min(scene.frames.length - 1, Math.floor(framePos));
  const frame = scene.frames[fi];

  let cx = 0, cy = 0, cz = 0, totalN = 0;
  for (let bi = 0; bi < frame.p.length; ++bi) {
    const pb = frame.p[bi];
    for (let i = 0; i < pb.length; i += 3) { cx += pb[i]; cy += pb[i+1]; cz += pb[i+2]; }
    totalN += pb.length / 3;
  }
  cx = (cx / totalN) * 0.001; cy = (cy / totalN) * 0.001; cz = (cz / totalN) * 0.001;
  if (document.getElementById("followCam").checked) {
    camTarget[0] += (cx - camTarget[0]) * 0.25;
    camTarget[1] += (Math.max(0.6, cy) - camTarget[1]) * 0.15;
    camTarget[2] += (cz - camTarget[2]) * 0.25;
  }

  const cam = makeCamera(w, h);

  const hasHeightfield = scene.colliders.some(c => c.kind === "heightfield");
  if (!hasHeightfield) {
    const gridCol = isLight ? "rgba(100,116,139,0.22)" : "rgba(148,163,184,0.14)";
    const gx0 = Math.floor(camTarget[0] - 18), gx1 = Math.ceil(camTarget[0] + 18);
    for (let x = gx0; x <= gx1; ++x) drawLine3D(cam, [x, 0, -10], [x, 0, 10], gridCol, 1);
    for (let z = -10; z <= 10; ++z) drawLine3D(cam, [gx0, 0, z], [gx1, 0, z], gridCol, 1);
  }

  for (const c of scene.colliders) {
    if (c.kind === "box") drawBoxCollider(cam, c, isLight);
    else if (c.kind === "heightfield") drawHeightfield(cam, c, isLight);
  }

  let totalNodes = 0, totalBeams = 0, totalTris = 0, activeTris = 0, deformed = 0, broken = 0;
  const showBroken = document.getElementById("showBroken").checked;
  const showNodes = document.getElementById("showNodes").checked;
  const showTris = document.getElementById("showTris").checked;

  // Draw ColTri surface triangles first (sorted back-to-front)
  const triDrawList = [];
  const lightDir = norm([0.45, 0.82, 0.35]);
  for (let bi = 0; bi < scene.bodies.length; ++bi) {
    const b = scene.bodies[bi];
    const p = frame.p[bi];
    const tris = b.triangles || [];
    const nt = tris.length / 3;
    totalTris += nt;
    const brT = scene._brokenTrisAt[bi][fi];
    activeTris += (nt - brT.count);
    if (!showTris) continue;

    for (let ti = 0; ti < nt; ++ti) {
      if (brT.flags[ti]) continue;
      const ia = tris[3*ti]*3, ib = tris[3*ti+1]*3, ic = tris[3*ti+2]*3;
      const pa3 = [p[ia]*0.001, p[ia+1]*0.001, p[ia+2]*0.001];
      const pb3 = [p[ib]*0.001, p[ib+1]*0.001, p[ib+2]*0.001];
      const pc3 = [p[ic]*0.001, p[ic+1]*0.001, p[ic+2]*0.001];
      const sa = cam.project(pa3), sb = cam.project(pb3), sc = cam.project(pc3);
      if (!sa || !sb || !sc) continue;
      const n = norm(cross(sub(pb3, pa3), sub(pc3, pa3)));
      const shade = 0.45 + 0.55 * Math.abs(dot(n, lightDir));
      const base = bi === 1 ? [192, 132, 252] : [56, 189, 248];
      const r = Math.round(base[0] * shade);
      const g = Math.round(base[1] * shade);
      const bl = Math.round(base[2] * shade);
      triDrawList.push({
        sa, sb, sc,
        z: (sa[2] + sb[2] + sc[2]) / 3,
        fill: `rgba(${r},${g},${bl},0.22)`
      });
    }
  }
  triDrawList.sort((a, b) => b.z - a.z);
  for (const t of triDrawList) {
    ctx.fillStyle = t.fill;
    ctx.beginPath();
    ctx.moveTo(t.sa[0], t.sa[1]);
    ctx.lineTo(t.sb[0], t.sb[1]);
    ctx.lineTo(t.sc[0], t.sc[1]);
    ctx.closePath();
    ctx.fill();
  }

  const segments = [];
  for (let bi = 0; bi < scene.bodies.length; ++bi) {
    const b = scene.bodies[bi];
    const p = frame.p[bi];
    const rl = scene._restLen[bi];
    const br = scene._brokenAt[bi][fi];
    const wb = scene._wheelBeamSet[bi];
    broken += br.count;
    totalNodes += b.nodes;
    const nb = b.beams.length / 2;
    totalBeams += nb;

    for (let i = 0; i < nb; ++i) {
      const isBroken = br.flags[i];
      if (isBroken && !showBroken) continue;
      const ia = b.beams[2*i]*3, ib = b.beams[2*i+1]*3;
      const ax = p[ia]*0.001, ay = p[ia+1]*0.001, az = p[ia+2]*0.001;
      const bx = p[ib]*0.001, by = p[ib+1]*0.001, bz = p[ib+2]*0.001;
      const pa = cam.project([ax, ay, az]), pb = cam.project([bx, by, bz]);
      if (!pa || !pb) continue;
      const len = Math.hypot(p[ib]-p[ia], p[ib+1]-p[ia+1], p[ib+2]-p[ia+2]);
      const strain = Math.abs(len - rl[i]) / rl[i];
      if (!isBroken && strain > 0.01) ++deformed;
      segments.push({
        x0: pa[0], y0: pa[1], x1: pb[0], y1: pb[1],
        z: 0.5*(pa[2] + pb[2]),
        color: isBroken ? "rgba(244,63,94,0.28)" : strainColor(strain, wb[i] === 1, bi, isLight),
        w: isBroken ? 1.0 : (strain > 0.03 ? 2.1 : 1.45)
      });
    }
  }
  segments.sort((a, b) => b.z - a.z);
  for (const s of segments) {
    ctx.strokeStyle = s.color;
    ctx.lineWidth = s.w;
    ctx.beginPath();
    ctx.moveTo(s.x0, s.y0);
    ctx.lineTo(s.x1, s.y1);
    ctx.stroke();
  }

  if (showNodes) {
    for (let bi = 0; bi < scene.bodies.length; ++bi) {
      const b = scene.bodies[bi];
      const p = frame.p[bi];
      const fixedSet = new Set(b.fixed || []);
      for (let i = 0; i < b.nodes; ++i) {
        const pr = cam.project([p[3*i]*0.001, p[3*i+1]*0.001, p[3*i+2]*0.001]);
        if (!pr) continue;
        const r = Math.max(1.4, Math.min(3.6, 12 / pr[2]));
        ctx.fillStyle = fixedSet.has(i) ? "#f43f5e" : (isLight ? "#0f172a" : "#e2e8f0");
        ctx.beginPath();
        ctx.arc(pr[0], pr[1], r, 0, Math.PI*2);
        ctx.fill();
      }
    }
  }

  let speedKmh = 0;
  if (frame.tel) {
    speedKmh = frame.tel[0];
  } else if (fi > 0) {
    const p0 = frame.p[0];
    const n0 = p0.length / 3;
    const prev = scene.frames[fi - 1].p[0];
    let c0x = 0, c0y = 0, c0z = 0, px = 0, py = 0, pz = 0;
    for (let i = 0; i < p0.length; i += 3) {
      c0x += p0[i]; c0y += p0[i+1]; c0z += p0[i+2];
      px += prev[i]; py += prev[i+1]; pz += prev[i+2];
    }
    const dt = (frame.t - scene.frames[fi - 1].t) || (1 / scene.fps);
    speedKmh = (Math.hypot(c0x - px, c0y - py, c0z - pz) / n0 * 0.001) / dt * 3.6;
  }

  document.getElementById("hudTime").textContent = `${frame.t.toFixed(2)} s`;
  document.getElementById("hudSpeed").textContent = `${speedKmh.toFixed(1)} km/h`;
  document.getElementById("hudTopo").textContent = `${totalNodes} / ${totalBeams}`;
  document.getElementById("hudTris").textContent = `${activeTris} / ${totalTris}`;
  document.getElementById("hudDeformed").textContent = `${deformed}`;
  document.getElementById("hudBroken").textContent = `${broken}`;

  const telBox = document.getElementById("hudTelemetry");
  if (frame.tel) {
    telBox.classList.remove("hidden");
    const [, rpm, gear, thr, brk] = frame.tel;
    document.getElementById("hudGear").textContent = gear < 0 ? "R" : (gear === 0 ? "N" : String(gear));
    document.getElementById("hudRpm").textContent = String(rpm);
    document.getElementById("hudRpmBar").style.width = `${Math.min(100, Math.round((rpm / 6500) * 100))}%`;
    document.getElementById("hudThr").textContent = `${Math.round(thr * 100)}%`;
    document.getElementById("hudThrBar").style.width = `${Math.round(thr * 100)}%`;
    document.getElementById("hudBrk").textContent = `${Math.round(brk * 100)}%`;
    document.getElementById("hudBrkBar").style.width = `${Math.round(brk * 100)}%`;
  } else {
    telBox.classList.add("hidden");
  }
}

let dragging = false, dragPan = false, lastX = 0, lastY = 0;
canvas.addEventListener("pointerdown", e => {
  dragging = true;
  dragPan = e.button === 2 || e.shiftKey;
  lastX = e.clientX; lastY = e.clientY;
  canvas.setPointerCapture(e.pointerId);
});
canvas.addEventListener("pointermove", e => {
  if (!dragging) return;
  const dx = e.clientX - lastX, dy = e.clientY - lastY;
  lastX = e.clientX; lastY = e.clientY;
  if (dragPan) {
    const s = camDist * 0.0018;
    panOffset[0] -= Math.cos(camYaw) * dx * s;
    panOffset[2] += Math.sin(camYaw) * dx * s;
    panOffset[1] += dy * s;
  } else {
    camYaw -= dx * 0.007;
    camPitch = Math.max(-0.2, Math.min(1.45, camPitch + dy * 0.007));
  }
});
canvas.addEventListener("pointerup", () => dragging = false);
canvas.addEventListener("contextmenu", e => e.preventDefault());
canvas.addEventListener("wheel", e => {
  e.preventDefault();
  camDist = Math.max(2.0, Math.min(35.0, camDist * (e.deltaY > 0 ? 1.1 : 0.9)));
}, {passive: false});

document.querySelectorAll(".camBtn").forEach(btn => {
  btn.onclick = () => {
    const k = btn.dataset.cam;
    panOffset = [0, 0, 0];
    if (k === "side") { camYaw = 0; camPitch = 0.12; }
    else if (k === "front") { camYaw = Math.PI * 0.5; camPitch = 0.15; }
    else if (k === "top") { camYaw = 0; camPitch = 1.42; }
    else { camYaw = 0.5; camPitch = 0.3; }
  };
});

const playBtn = document.getElementById("playBtn");
const scrub = document.getElementById("scrub");
function setPlaying(p) {
  playing = p;
  playBtn.textContent = playing ? "Pause" : "Abspielen";
}
playBtn.onclick = () => setPlaying(!playing);
scrub.oninput = () => { setPlaying(false); framePos = Number(scrub.value); };
document.getElementById("stepBack").onclick = () => { setPlaying(false); framePos = Math.max(0, Math.floor(framePos) - 1); scrub.value = framePos; };
document.getElementById("stepFwd").onclick = () => { setPlaying(false); framePos = Math.min(scene.frames.length - 1, Math.floor(framePos) + 1); scrub.value = framePos; };
document.getElementById("speedSel").onchange = e => speed = Number(e.target.value);

let lastTs = performance.now();
function tick(ts) {
  const dt = Math.min(0.1, (ts - lastTs) * 0.001);
  lastTs = ts;
  if (playing && scene.frames.length > 1) {
    framePos += dt * scene.fps * speed;
    if (framePos >= scene.frames.length - 1) framePos = 0;
    scrub.value = Math.floor(framePos);
  }
  render();
  requestAnimationFrame(tick);
}

prepareScene(0);
const params = new URLSearchParams(window.location.search);
if (params.has("scene")) {
  const sName = params.get("scene");
  const idx = SCENES.findIndex(s => s.scene === sName);
  if (idx >= 0) prepareScene(idx);
}
if (params.has("frame")) {
  setPlaying(false);
  framePos = Math.max(0, Math.min(scene.frames.length - 1, Number(params.get("frame"))));
  scrub.value = Math.floor(framePos);
  for (let k = 0; k < 15; ++k) render();
}
requestAnimationFrame(tick);
</script>
</body>
</html>
"""


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("recordings", nargs="+", help="JSON files produced by sbsim --record")
    ap.add_argument("-o", "--out", required=True, help="Output HTML file")
    args = ap.parse_args()

    scenes = [json.loads(Path(p).read_text(encoding="utf-8")) for p in args.recordings]
    html = TEMPLATE.replace("__SCENES_JSON__", json.dumps(scenes, separators=(",", ":")))
    Path(args.out).write_text(html, encoding="utf-8")
    print(f"wrote {args.out} ({len(html) // 1024} KiB, {len(scenes)} scene(s))")


if __name__ == "__main__":
    main()
