#!/usr/bin/env python3
"""Bundles one or more `sbsim --record` JSON files into a self-contained HTML 3D viewer.

Usage:
    python3 tools/make_viewer.py --out viewer.html accel_brake.json slalom.json ...
"""

import argparse
import json
from pathlib import Path

TEMPLATE = r"""<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>SoftBodyDriver – 3D-Physik-Replay</title>
<script src="https://www.gstatic.com/antigravity/web/dev/tailwindcss.min.js"></script>
<style>
  html, body { margin: 0; padding: 0; }
  canvas { display: block; touch-action: none; }
</style>
</head>
<body class="bg-[var(--background,#0f172a)] text-[var(--foreground,#f8fafc)] antialiased select-none">
<div class="max-w-6xl mx-auto p-4 flex flex-col gap-3">
  <div class="bg-[var(--card,#1e293b)] border border-[var(--border,#334155)] rounded-xl p-4 shadow-sm flex flex-wrap items-center justify-between gap-3">
    <div>
      <div class="flex items-center gap-2">
        <span class="font-semibold text-base">SoftBodyDriver – C++-Physik-Kern (2000 Hz)</span>
        <span class="text-xs px-2 py-0.5 rounded bg-[var(--secondary,#334155)] text-[var(--secondary-foreground,#e2e8f0)]">Phase 2 · Räder &amp; Antrieb</span>
      </div>
      <p id="sceneDesc" class="text-[var(--muted-foreground,#94a3b8)] text-xs mt-1"></p>
    </div>
    <div id="sceneTabs" class="flex flex-wrap gap-1.5"></div>
  </div>

  <div class="relative bg-[var(--card,#1e293b)] border border-[var(--border,#334155)] rounded-xl overflow-hidden shadow-sm">
    <canvas id="view" class="w-full" style="height: 460px;"></canvas>

    <div class="absolute top-3 left-3 bg-[var(--card,#1e293b)]/90 backdrop-blur border border-[var(--border,#334155)] rounded-lg px-3 py-2 text-xs space-y-1 pointer-events-none min-w-[215px]">
      <div class="font-medium text-sm" id="hudTitle"></div>
      <div class="grid grid-cols-2 gap-x-4 gap-y-0.5 text-[var(--muted-foreground,#94a3b8)]">
        <span>Zeit:</span><span id="hudTime" class="text-[var(--foreground,#f8fafc)] font-mono"></span>
        <span>Geschwindigkeit:</span><span id="hudSpeed" class="text-[var(--foreground,#f8fafc)] font-mono font-semibold"></span>
        <span>Nodes / Beams:</span><span id="hudTopo" class="text-[var(--foreground,#f8fafc)] font-mono"></span>
        <span>Verbeult (&gt;1%):</span><span id="hudDeformed" class="text-amber-400 font-mono"></span>
        <span>Gebrochen:</span><span id="hudBroken" class="text-rose-400 font-mono"></span>
      </div>
      <div id="hudTelemetry" class="pt-1.5 mt-1 border-t border-[var(--border,#334155)] space-y-1 hidden">
        <div class="flex items-center justify-between">
          <span class="text-[var(--muted-foreground,#94a3b8)]">Gang / Drehzahl:</span>
          <span class="font-mono"><span id="hudGear" class="px-1.5 py-0.5 rounded bg-sky-500/20 text-sky-300 font-bold mr-1">1</span><span id="hudRpm">850</span> RPM</span>
        </div>
        <div class="w-full h-1.5 bg-slate-700/60 rounded overflow-hidden">
          <div id="hudRpmBar" class="h-full bg-gradient-to-r from-sky-400 via-amber-400 to-rose-500" style="width:15%"></div>
        </div>
        <div class="grid grid-cols-2 gap-2 pt-0.5">
          <div>
            <div class="flex justify-between text-[var(--muted-foreground,#94a3b8)]"><span>Gas</span><span id="hudThr" class="font-mono">0%</span></div>
            <div class="w-full h-1.5 bg-slate-700/60 rounded overflow-hidden"><div id="hudThrBar" class="h-full bg-emerald-400" style="width:0%"></div></div>
          </div>
          <div>
            <div class="flex justify-between text-[var(--muted-foreground,#94a3b8)]"><span>Bremse</span><span id="hudBrk" class="font-mono">0%</span></div>
            <div class="w-full h-1.5 bg-slate-700/60 rounded overflow-hidden"><div id="hudBrkBar" class="h-full bg-rose-500" style="width:0%"></div></div>
          </div>
        </div>
      </div>
    </div>

    <div class="absolute top-3 right-3 flex flex-wrap gap-1.5">
      <button data-cam="perspective" class="camBtn text-xs px-2.5 py-1 rounded border border-[var(--border,#334155)] bg-[var(--card,#1e293b)]/90">Schräg</button>
      <button data-cam="side" class="camBtn text-xs px-2.5 py-1 rounded border border-[var(--border,#334155)] bg-[var(--card,#1e293b)]/90">Seite</button>
      <button data-cam="front" class="camBtn text-xs px-2.5 py-1 rounded border border-[var(--border,#334155)] bg-[var(--card,#1e293b)]/90">Vorne</button>
      <button data-cam="top" class="camBtn text-xs px-2.5 py-1 rounded border border-[var(--border,#334155)] bg-[var(--card,#1e293b)]/90">Oben</button>
      <label class="text-xs px-2.5 py-1 rounded border border-[var(--border,#334155)] bg-[var(--card,#1e293b)]/90 flex items-center gap-1.5 cursor-pointer">
        <input id="followCam" type="checkbox" checked /> Kamera folgt
      </label>
    </div>

    <div class="absolute bottom-3 left-3 flex items-center gap-3 text-xs bg-[var(--card,#1e293b)]/90 border border-[var(--border,#334155)] rounded-lg px-3 py-1.5 pointer-events-none">
      <span class="flex items-center gap-1"><span class="inline-block w-2.5 h-2.5 rounded-full bg-sky-400"></span> Chassis</span>
      <span class="flex items-center gap-1"><span class="inline-block w-2.5 h-2.5 rounded-full bg-emerald-400"></span> Pressure-Wheels</span>
      <span class="flex items-center gap-1"><span class="inline-block w-2.5 h-2.5 rounded-full bg-amber-400"></span> Last / Dehnung</span>
      <span class="flex items-center gap-1"><span class="inline-block w-2.5 h-2.5 rounded-full bg-rose-500"></span> Verbeult</span>
      <span class="text-[var(--muted-foreground,#94a3b8)] hidden sm:inline">· Ziehen: drehen · Rechts/Shift: schieben · Rad: Zoom</span>
    </div>
  </div>

  <div class="bg-[var(--card,#1e293b)] border border-[var(--border,#334155)] rounded-xl p-3 shadow-sm flex flex-wrap items-center gap-3">
    <button id="playBtn" class="text-xs font-medium px-3 py-1.5 rounded-lg bg-[var(--primary,#38bdf8)] text-[var(--primary-foreground,#0f172a)]">Pause</button>
    <button id="stepBack" class="text-xs px-2.5 py-1.5 rounded-lg border border-[var(--border,#334155)]">-1</button>
    <button id="stepFwd" class="text-xs px-2.5 py-1.5 rounded-lg border border-[var(--border,#334155)]">+1</button>
    <input id="scrub" type="range" min="0" max="100" value="0" class="flex-1 min-w-[160px]" />
    <div class="flex items-center gap-1 text-xs">
      <span class="text-[var(--muted-foreground,#94a3b8)]">Tempo:</span>
      <select id="speedSel" class="bg-[var(--background,#0f172a)] border border-[var(--border,#334155)] rounded px-2 py-1 text-xs">
        <option value="0.2">0.2× (Zeitlupe)</option>
        <option value="0.5">0.5×</option>
        <option value="1" selected>1.0×</option>
        <option value="2">2.0×</option>
      </select>
    </div>
    <label class="text-xs flex items-center gap-1.5 cursor-pointer">
      <input id="showNodes" type="checkbox" checked /> Nodes
    </label>
    <label class="text-xs flex items-center gap-1.5 cursor-pointer">
      <input id="showBroken" type="checkbox" /> gebrochene Beams
    </label>
  </div>
</div>

<script>
const SCENES = __SCENES_JSON__;

const LABELS = {
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
  }

  if (scene.scene === "bridge_overload") {
    camYaw = 0.35; camPitch = 0.25; camDist = 11.5;
    document.getElementById("followCam").checked = false;
    camTarget = [0, 2.5, 0];
  } else if (scene.scene === "cube_drop") {
    camYaw = 0.7; camPitch = 0.35; camDist = 5.5;
    document.getElementById("followCam").checked = false;
    camTarget = [0, 1.0, 0];
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
    btn.className = "text-xs px-3 py-1.5 rounded-lg border transition " + (
      active
        ? "bg-[var(--primary,#38bdf8)] text-[var(--primary-foreground,#0f172a)] border-transparent font-medium"
        : "border-[var(--border,#334155)] text-[var(--foreground,#f8fafc)] hover:bg-[var(--secondary,#334155)]"
    );
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

function strainColor(strain, isWheel, isLight) {
  const s = Math.min(1, strain / 0.12);
  if (s < 0.08) {
    if (isWheel) return isLight ? "#059669" : "#34d399";
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

  const p0 = frame.p[0];
  const n0 = p0.length / 3;
  let cx = 0, cy = 0, cz = 0;
  for (let i = 0; i < p0.length; i += 3) { cx += p0[i]; cy += p0[i+1]; cz += p0[i+2]; }
  cx = (cx / n0) * 0.001; cy = (cy / n0) * 0.001; cz = (cz / n0) * 0.001;
  if (document.getElementById("followCam").checked) {
    camTarget[0] += (cx - camTarget[0]) * 0.25;
    camTarget[1] += (Math.max(0.6, cy) - camTarget[1]) * 0.15;
    camTarget[2] += (cz - camTarget[2]) * 0.25;
  }

  const cam = makeCamera(w, h);

  const gridCol = isLight ? "rgba(100,116,139,0.22)" : "rgba(148,163,184,0.14)";
  const gx0 = Math.floor(camTarget[0] - 18), gx1 = Math.ceil(camTarget[0] + 18);
  for (let x = gx0; x <= gx1; ++x) drawLine3D(cam, [x, 0, -10], [x, 0, 10], gridCol, 1);
  for (let z = -10; z <= 10; ++z) drawLine3D(cam, [gx0, 0, z], [gx1, 0, z], gridCol, 1);

  for (const c of scene.colliders) if (c.kind === "box") drawBoxCollider(cam, c, isLight);

  let totalNodes = 0, totalBeams = 0, deformed = 0, broken = 0;
  const showBroken = document.getElementById("showBroken").checked;
  const showNodes = document.getElementById("showNodes").checked;

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
        color: isBroken ? "rgba(244,63,94,0.28)" : strainColor(strain, wb[i] === 1, isLight),
        w: isBroken ? 1.0 : (strain > 0.03 ? 2.1 : 1.5)
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
        const r = Math.max(1.5, Math.min(3.8, 13 / pr[2]));
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
    const prev = scene.frames[fi - 1].p[0];
    let px = 0, py = 0, pz = 0;
    for (let i = 0; i < prev.length; i += 3) { px += prev[i]; py += prev[i+1]; pz += prev[i+2]; }
    px = (px / n0) * 0.001; py = (py / n0) * 0.001; pz = (cz / n0) * 0.001;
    const dt = (frame.t - scene.frames[fi - 1].t) || (1 / scene.fps);
    speedKmh = Math.hypot(cx - px, cy - py, cz - pz) / dt * 3.6;
  }

  document.getElementById("hudTime").textContent = `${frame.t.toFixed(2)} s`;
  document.getElementById("hudSpeed").textContent = `${speedKmh.toFixed(1)} km/h`;
  document.getElementById("hudTopo").textContent = `${totalNodes} / ${totalBeams}`;
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
  camDist = Math.max(2.0, Math.min(30.0, camDist * (e.deltaY > 0 ? 1.1 : 0.9)));
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
