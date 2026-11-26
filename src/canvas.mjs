// The canvas animation loop. The renderer is kept out of Lustre's virtual DOM:
// Gleam computes the full curve of every path once (whenever the code or
// `shape_slider` changes) and pushes it here via `setDrawing`. A single
// requestAnimationFrame loop owns the clock and, each frame, reveals a growing
// prefix of the precomputed points straight to the 2D context. So per frame
// there is no geometry work and no vdom diffing — just canvas strokes — which
// is what lets many paths animate at high frames per second.
//
// Values cross the Gleam/JS boundary directly — no JSON: a Gleam record arrives
// as an object with named fields, and a Gleam list is iterable.


let canvas = null;
let ctx = null;
// { paths: [{ pts: Float64Array [x0,y0,...], thickness, color, start, end }] }
let drawing = null;
let rate = 1; // a multiple of normal speed; negative plays the drawing backward
let clock = 0; // the drawing's time, in tenths of a second, in [0, endClock]
let lastTs = 0;
let running = false;
let framesWithoutCanvas = 0;

// Play mode. The square is drawn in world units on top of the strokes. `live`
// is false during the countdown, and the square cannot move until the round
// starts. Keys count only while the canvas itself is focused.
let player = null;
const held = new Set();
// World units per second at 1x. A 2x level moves the square twice this fast.
const PLAYER_SPEED = 450;

const TENTHS_PER_SECOND = 10;
// How early a line is shown in faint gray, measured in seconds of the drawing.
// During a level the clock already runs at the speed multiplier, so the warning
// gets shorter in real time as the level speeds up and only the next shape
// shows. While the clock is paused the countdown still previews at 1x.
const PREVIEW_SECONDS = 2;
const PREVIEW_COLOR = "rgba(176, 176, 186, 0.4)";
// How many frames (about 10 seconds' worth) to wait for the canvas to appear
// before reporting that it hasn't.
const MAX_FRAMES_WITHOUT_CANVAS = 600;

// Replace the drawing being animated. `pathList` is the List(RenderPath) built
// by render.gleam; each path's points are packed into a flat Float64Array so
// the per-frame draw loop touches only contiguous numbers.
export function setDrawing(pathList) {
  const paths = [];
  for (const p of pathList) {
    const flat = [];
    for (const q of p.points) flat.push(q.x, q.y);
    paths.push({
      pts: new Float64Array(flat),
      thickness: p.thickness,
      color: p.color,
      start: p.start,
      end: p.end,
      vanishes: !!p.vanishes,
    });
  }
  // Keep the current clock across drawing swaps: dragging the shape slider on an
  // already-finished drawing shows the new shape complete, rather than restarting.
  // `endClock` is the moment the last path finishes drawing, past which the frame
  // loop holds time still (see frame).
  drawing = { paths, endClock: drawingEndClock(paths) };
  if (!running) {
    running = true;
    lastTs = performance.now();
    requestAnimationFrame(frame);
  }
}

// The clock at which every path has fully drawn — the largest per-path finish
// time (u = 1). A path finishes at its `end` time, or right at `start` when it
// has no positive duration (end ≤ start, an instant path). An empty drawing
// has nothing to finish, so time runs on unbounded (Infinity).
function drawingEndClock(paths) {
  let end = Infinity;
  for (const p of paths) {
    const finish = Math.max(p.start, p.end);
    end = end === Infinity ? finish : Math.max(end, finish);
  }
  return end;
}

export function setSpeed(r) {
  rate = r;
}

// Jump the animation back to the start (empty canvas).
export function resetClock() {
  clock = 0;
}

// Show the player at the origin and accept WASD. Collision stays off until
// startRound, so the countdown is time to move before any line can hit.
export function armPlayer() {
  player = {
    x: 0,
    y: 0,
    half: 18,
    live: false,
    over: false,
    onHit: null,
    onWin: null,
    t0: 0,
  };
}

// Collision and the survival clock start now. Position is whatever the player
// reached during the countdown.
export function startRound(onHit, onWin) {
  if (!player) armPlayer();
  player.live = true;
  player.over = false;
  player.onHit = onHit;
  player.onWin = onWin;
  player.t0 = performance.now();
}

export function stopGame() {
  player = null;
  held.clear();
}

export function focusCanvas() {
  const el = document.getElementById("animation-canvas");
  if (el) el.focus();
}

export function after(ms, callback) {
  setTimeout(callback, ms);
}

function frame(ts) {
  // Cap dt so a backgrounded/paused tab can't jump the clock far ahead.
  const dt = Math.min((ts - lastTs) / 1000, 0.1);
  lastTs = ts;
  // The clock runs forward, each path drawing in over its window and then
  // staying; there is no loop back to an empty canvas. It is bounded at both
  // ends: reverse rewinds only as far as the start (0), and forward stops the
  // instant the last path has fully drawn (endClock), so time never runs on past
  // a finished drawing.
  clock += dt * rate * TENTHS_PER_SECOND;
  clock = clamp(clock, 0, drawing.endClock);
  // Move and collide against the geometry this frame is about to paint.
  updatePlayer(dt);
  render();
  requestAnimationFrame(frame);
}

// Match the backing store to the element's CSS size (× device pixel ratio) so
// the drawing stays crisp; only touched when the size actually changes.
function ensureSize() {
  const dpr = window.devicePixelRatio || 1;
  const w = Math.round(canvas.clientWidth * dpr);
  const h = Math.round(canvas.clientHeight * dpr);
  if (w > 0 && h > 0 && (canvas.width !== w || canvas.height !== h)) {
    canvas.width = w;
    canvas.height = h;
  }
}

// Find the page's canvas, which Lustre can add to the page after the first drawing
// arrives. Returns whether it is there.
function findCanvas() {
  const el = document.getElementById("animation-canvas");
  if (!el) {
    framesWithoutCanvas += 1;
    if (framesWithoutCanvas === MAX_FRAMES_WITHOUT_CANVAS) {
      console.error('The page has no <canvas id="animation-canvas"> element to draw on.');
    }
    return false;
  }
  if (el !== canvas) {
    canvas = el;
    ctx = canvas.getContext("2d");
  }
  return true;
}

function render() {
  if (!findCanvas()) return;
  ensureSize();
  const w = canvas.width;
  const h = canvas.height;
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.clearRect(0, 0, w, h);
  // Draw functions work in a 0..1000 world centred on the origin: scale it to
  // fill the canvas and translate (0, 0) to the middle, so positive coordinates
  // run toward the bottom-right corner.
  ctx.setTransform(w / 1000, 0, 0, h / 1000, w / 2, h / 2);
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  drawPreviews();
  for (const p of drawing.paths) {
    // Each path is revealed by a parameter u ∈ [0, 1] that advances at a steady
    // rate. A path is complete once u reaches 1.
    const u = penU(p);
    // `u` clamps to 0 both before a path starts and at the very instant it
    // does, so it can't tell "not yet" from "just begun". Gate on the start
    // time instead, so a just-begun path is shown at rest at u = 0
    // rather than staying hidden until the clock advances.
    if (p.vanishes) {
      if (clock >= p.start && clock < p.end) drawFull(p);
    } else if (clock >= p.start) {
      drawUpToU(p, u);
    }
  }
  drawPlayer();
}

// The full path, in translucent gray, from a couple of seconds before it
// starts until the cream stroke finishes. A gate is previewed only before it
// appears. The gray line is not part of the hit test.
function drawPreviews() {
  if (rate < 0) return;
  // A live round looks a fixed distance ahead in the drawing, so 5x does not
  // reveal the safe spot after the next one. Draw mode keeps a real-time lead.
  const playing = player && player.live && rate > 0;
  const speed = playing || rate < 0.05 ? 1 : rate;
  const lead = PREVIEW_SECONDS * speed * TENTHS_PER_SECOND;
  ctx.save();
  ctx.strokeStyle = PREVIEW_COLOR;
  for (const p of drawing.paths) {
    const finish = Math.max(p.start, p.end);
    // A gate is only "about to happen" before it appears. Once it has been
    // erased there is nothing left to preview.
    if (p.vanishes && clock >= p.start) continue;
    if (clock + lead < p.start || clock >= finish) continue;
    const pts = p.pts;
    const count = pts.length / 2;
    if (count < 2) continue;
    ctx.beginPath();
    ctx.moveTo(pts[0], pts[1]);
    for (let i = 1; i < count; i++) ctx.lineTo(pts[2 * i], pts[2 * i + 1]);
    ctx.lineWidth = p.thickness;
    ctx.stroke();
  }
  ctx.restore();
}

// How much of a path is revealed now: its parameter u ∈ [0, 1], advancing
// linearly from its start time to its end time — 0 before it starts, 1 once
// done. A path with no positive duration (end ≤ start) appears complete the
// moment it starts.
function penU(p) {
  const duration = p.end - p.start;
  if (duration <= 0) return clock >= p.start ? 1 : 0;
  const u = (clock - p.start) / duration;
  return u < 0 ? 0 : u > 1 ? 1 : u;
}

function clamp(x, lo, hi) {
  return x < lo ? lo : x > hi ? hi : x;
}

function canvasFocused() {
  return document.activeElement && document.activeElement.id === "animation-canvas";
}

if (typeof window !== "undefined") {
  window.addEventListener("keydown", (event) => {
    if (!canvasFocused()) return;
    const key = event.key.toLowerCase();
    if (key === "w" || key === "a" || key === "s" || key === "d") {
      held.add(key);
      event.preventDefault();
    }
  });

  window.addEventListener("keyup", (event) => {
    held.delete(event.key.toLowerCase());
  });
}

function updatePlayer(dt) {
  if (!player || player.over) return;
  // The countdown is for looking, not moving. Keys still register, so a key
  // held as the round starts takes effect on the first live frame.
  if (player.live && canvasFocused()) {
    let dx = 0;
    let dy = 0;
    if (held.has("a")) dx -= 1;
    if (held.has("d")) dx += 1;
    if (held.has("w")) dy -= 1;
    if (held.has("s")) dy += 1;
    if (dx !== 0 || dy !== 0) {
      const len = Math.hypot(dx, dy);
      // The level multiplier is the playback rate while a round is live.
      const move = PLAYER_SPEED * (rate > 0 ? rate : 1);
      player.x = clamp(player.x + (dx / len) * move * dt, -470, 470);
      player.y = clamp(player.y + (dy / len) * move * dt, -470, 470);
    }
  }
  if (!player.live || !drawing) return;
  if (hitsDrawing(player)) {
    player.over = true;
    player.live = false;
    const ms = Math.max(0, Math.round(performance.now() - player.t0));
    if (player.onHit) player.onHit(ms);
    return;
  }
  if (drawing.endClock !== Infinity && clock >= drawing.endClock) {
    player.over = true;
    player.live = false;
    if (player.onWin) player.onWin();
  }
}

// Same reveal rule as drawUpToU: equal parameter per segment, not arc length.
// The tested box is the player square expanded by half the stroke, which is
// the reach of the round line caps.
function hitsDrawing(p) {
  for (const path of drawing.paths) {
    if (path.vanishes) {
      if (clock < path.start || clock >= path.end) continue;
      const pad = Math.max(0, path.thickness) / 2;
      if (
        segmentHitsRect(
          path.pts[0],
          path.pts[1],
          path.pts[2],
          path.pts[3],
          p.x - p.half - pad,
          p.y - p.half - pad,
          p.x + p.half + pad,
          p.y + p.half + pad,
        )
      ) {
        return true;
      }
      continue;
    }
    if (clock < path.start) continue;
    const pad = Math.max(0, path.thickness) / 2;
    const minX = p.x - p.half - pad;
    const maxX = p.x + p.half + pad;
    const minY = p.y - p.half - pad;
    const maxY = p.y + p.half + pad;
    if (revealedHits(path.pts, penU(path), minX, minY, maxX, maxY)) return true;
  }
  return false;
}

function revealedHits(pts, u, minX, minY, maxX, maxY) {
  const count = pts.length / 2;
  if (count < 2) return false;
  const segs = count - 1;
  const f = u * segs;
  const k = Math.min(segs, Math.floor(f));
  for (let i = 0; i < k; i++) {
    if (
      segmentHitsRect(
        pts[2 * i],
        pts[2 * i + 1],
        pts[2 * i + 2],
        pts[2 * i + 3],
        minX,
        minY,
        maxX,
        maxY,
      )
    ) {
      return true;
    }
  }
  const frac = f - Math.floor(f);
  if (k < segs && frac > 0) {
    const ax = pts[2 * k];
    const ay = pts[2 * k + 1];
    const bx = pts[2 * k + 2];
    const by = pts[2 * k + 3];
    if (
      segmentHitsRect(
        ax,
        ay,
        ax + (bx - ax) * frac,
        ay + (by - ay) * frac,
        minX,
        minY,
        maxX,
        maxY,
      )
    ) {
      return true;
    }
  }
  // u = 0 still paints a round cap on the first point.
  if (k === 0 && frac === 0) {
    return pts[0] >= minX && pts[0] <= maxX && pts[1] >= minY && pts[1] <= maxY;
  }
  return false;
}

function segmentHitsRect(x1, y1, x2, y2, minX, minY, maxX, maxY) {
  if (pointInRect(x1, y1, minX, minY, maxX, maxY)) return true;
  if (pointInRect(x2, y2, minX, minY, maxX, maxY)) return true;
  return (
    segmentsCross(x1, y1, x2, y2, minX, minY, maxX, minY) ||
    segmentsCross(x1, y1, x2, y2, maxX, minY, maxX, maxY) ||
    segmentsCross(x1, y1, x2, y2, maxX, maxY, minX, maxY) ||
    segmentsCross(x1, y1, x2, y2, minX, maxY, minX, minY)
  );
}

function pointInRect(x, y, minX, minY, maxX, maxY) {
  return x >= minX && x <= maxX && y >= minY && y <= maxY;
}

function segmentsCross(ax, ay, bx, by, cx, cy, dx, dy) {
  const rx = bx - ax;
  const ry = by - ay;
  const sx = dx - cx;
  const sy = dy - cy;
  const denom = rx * sy - ry * sx;
  if (denom === 0) return false;
  const t = ((cx - ax) * sy - (cy - ay) * sx) / denom;
  const u = ((cx - ax) * ry - (cy - ay) * rx) / denom;
  return t >= 0 && t <= 1 && u >= 0 && u <= 1;
}

function drawPlayer() {
  if (!player) return;
  const { x, y, half } = player;
  ctx.save();
  ctx.strokeStyle = "#ffffff";
  ctx.lineWidth = 2.8;
  ctx.lineJoin = "round";
  ctx.lineCap = "round";
  ctx.strokeRect(x - half, y - half, half * 2, half * 2);
  // λ, the same shape as the letter: long stroke from the lower left up to
  // the top, short stroke branching off it to the upper right.
  ctx.beginPath();
  ctx.moveTo(x - 8, y + 11);
  ctx.lineTo(x - 1, y - 11);
  ctx.moveTo(x - 5.1, y + 2);
  ctx.lineTo(x + 9, y - 10);
  ctx.stroke();
  ctx.restore();
}

// Stroke the first `u` fraction of a path's polyline, interpolating the final
// partial segment so the curve reveals smoothly rather than a vertex at a time.
function drawUpToU(p, u) {
  const pts = p.pts;
  const count = pts.length / 2;
  if (count < 2) return;
  const segs = count - 1;
  const f = u * segs;
  const k = Math.min(segs, Math.floor(f));
  ctx.beginPath();
  ctx.moveTo(pts[0], pts[1]);
  for (let i = 1; i <= k; i++) ctx.lineTo(pts[2 * i], pts[2 * i + 1]);
  const frac = f - k;
  if (k < segs && frac > 0) {
    const ax = pts[2 * k];
    const ay = pts[2 * k + 1];
    const bx = pts[2 * k + 2];
    const by = pts[2 * k + 3];
    ctx.lineTo(ax + (bx - ax) * frac, ay + (by - ay) * frac);
  }
  ctx.lineWidth = p.thickness;
  ctx.strokeStyle = p.color;
  ctx.stroke();
}

function drawFull(p) {
  const pts = p.pts;
  const count = pts.length / 2;
  if (count < 2) return;
  ctx.beginPath();
  ctx.moveTo(pts[0], pts[1]);
  for (let i = 1; i < count; i++) ctx.lineTo(pts[2 * i], pts[2 * i + 1]);
  ctx.lineWidth = p.thickness;
  ctx.strokeStyle = p.color;
  ctx.stroke();
}

