// Seeded generator for the draw language's random(). Each draw is reseeded
// with the shape slider, so the same slider value repeats the same sequence.
let state = 1;

export function seed(n) {
  state = (Math.imul(Number(n) | 0, 0x6c078965) + 1) >>> 0;
  if (state === 0) state = 1;
}

export function nextUnit() {
  state = (Math.imul(1664525, state) + 1013904223) >>> 0;
  return state / 4294967296;
}
