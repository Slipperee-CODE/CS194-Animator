//// The drawings that a browser with no saved library starts with: each one's
//// name and source.

pub const all = [
  #(
    "fan",
    "fn draw(shape_slider: Int) -> List(Path) {
  fan(30, Point(-200, -200))
}

fn fan(n: Int, start: Point) -> List(Path) {
  case n > 0 {
    True -> [Path(Line(start, Point(n * 10, 200)), 0, 30, 3), ..fan(n - 1, start)]
    False -> []
  }
}
",
  ),
  #(
    "square_spiral",
    "fn draw(shape_slider: Int) -> List(Path) {
  let turns = 20 + shape_slider / 4
  spiral(Point(0, 0), Point(1, 0), 0, turns)
}

fn spiral(p: Point, d: Point, i: Int, n: Int) -> List(Path) {
  case i == n {
    True -> []
    False -> {
      let len = { i / 2 + 1 } * 24
      let q = Point(p.x + d.x * len, p.y + d.y * len)
      [
        Path(Line(p, q), i * 3, i * 3 + 3, 3),
        ..spiral(q, Point(0 - d.y, d.x), i + 1, n)
      ]
    }
  }
}
",
  ),
  #(
    "string_art",
    "fn draw(shape_slider: Int) -> List(Path) {
  let n = 8 + shape_slider / 10
  list.flatten([
    quadrant(1, 1, n, 0),
    quadrant(-1, 1, n, n + 1),
    quadrant(-1, -1, n, { n + 1 } * 2),
    quadrant(1, -1, n, { n + 1 } * 3),
  ])
}

fn quadrant(sx: Int, sy: Int, n: Int, base: Int) -> List(Path) {
  strings(0, sx, sy, n, base)
}

fn strings(i: Int, sx: Int, sy: Int, n: Int, base: Int) -> List(Path) {
  case i > n {
    True -> []
    False -> {
      let a = Point(sx * 420 * i / n, 0)
      let b = Point(0, sy * 420 * { n - i } / n)
      let t = { base + i } * 2
      [Path(Line(a, b), t, t + 8, 2), ..strings(i + 1, sx, sy, n, base)]
    }
  }
}
",
  ),
  #(
    "tree",
    "fn draw(shape_slider: Int) -> List(Path) {
  let depth = 4 + shape_slider / 20
  branch(Point(0, 420), Point(0, -220), 0, depth)
}

fn branch(p: Point, d: Point, level: Int, depth: Int) -> List(Path) {
  case level == depth {
    True -> []
    False -> {
      let q = Point(p.x + d.x, p.y + d.y)
      let left = Point({ d.x - d.y } / 2, { d.y + d.x } / 2)
      let right = Point({ d.x + d.y } / 2, { d.y - d.x } / 2)
      [
        Path(Line(p, q), level * 4, level * 4 + 4, depth - level),
        ..list.append(
          branch(q, left, level + 1, depth),
          branch(q, right, level + 1, depth),
        )
      ]
    }
  }
}
",
  ),
  #(
    "circles",
    "fn draw(shape_slider: Int) -> List(Path) {
  let thick = 8 + shape_slider / 50
  list.append(walls(0, thick), list.append(seal(0, thick), march(0, thick)))
}

fn at(i: Int, r: Int) -> Point {
  let u = case i % 16 {
    0 -> Point(100, 0)
    1 -> Point(92, 38)
    2 -> Point(71, 71)
    3 -> Point(38, 92)
    4 -> Point(0, 100)
    5 -> Point(0 - 38, 92)
    6 -> Point(0 - 71, 71)
    7 -> Point(0 - 92, 38)
    8 -> Point(0 - 100, 0)
    9 -> Point(0 - 92, 0 - 38)
    10 -> Point(0 - 71, 0 - 71)
    11 -> Point(0 - 38, 0 - 92)
    12 -> Point(0, 0 - 100)
    13 -> Point(38, 0 - 92)
    14 -> Point(71, 0 - 71)
    15 -> Point(92, 0 - 38)
  }
  Point(u.x * r / 100, u.y * r / 100)
}

fn walls(i: Int, thick: Int) -> List(Path) {
  case i > 15 {
    True -> []
    False -> list.append(edge(i, thick), walls(i + 1, thick))
  }
}

fn edge(i: Int, thick: Int) -> List(Path) {
  list.append(
    ring(i, 450, thick, False),
    ring(i, 340, thick, i == 3 || i == 4),
  )
}

fn ring(i: Int, r: Int, thick: Int, skip: Bool) -> List(Path) {
  case skip {
    True -> []
    False -> [Path(Line(at(i, r), at(i + 1, r)), 0, 12, thick)]
  }
}

fn seal(i: Int, thick: Int) -> List(Path) {
  case i > 14 {
    True -> []
    False -> case i == 4 {
      True -> seal(i + 2, thick)
      False -> [
        Path(Line(Point(0, 0), at(i, 340)), 28, 42, thick),
        ..seal(i + 2, thick)
      ]
    }
  }
}

fn march(step: Int, thick: Int) -> List(Path) {
  case step > 14 {
    True -> []
    False -> list.append(beat(step, thick), march(step + 1, thick))
  }
}

fn beat(step: Int, thick: Int) -> List(Path) {
  let sector = { 4 + step } % 16
  let open = 50 + step * 18
  let front = sector + 1
  [
    Path(Gate(at(front, 340), at(front, 450)), open - 18, open, thick),
    Path(Line(at(sector, 340), at(front, 450)), open, open + 8, thick),
    Path(Line(at(sector, 450), at(front, 340)), open, open + 8, thick),
  ]
}
",
  ),
  #(
    "reaction",
    "fn draw(shape_slider: Int) -> List(Path) {
  play(0, 8 + shape_slider / 34)
}

fn play(n: Int, total: Int) -> List(Path) {
  case n >= total {
    True -> []
    False -> list.append(round(n, random(0, 8)), play(n + 1, total))
  }
}

fn at(i: Int, r: Int) -> Point {
  let u = case i % 16 {
    0 -> Point(100, 0)
    1 -> Point(92, 38)
    2 -> Point(71, 71)
    3 -> Point(38, 92)
    4 -> Point(0, 100)
    5 -> Point(0 - 38, 92)
    6 -> Point(0 - 71, 71)
    7 -> Point(0 - 92, 38)
    8 -> Point(0 - 100, 0)
    9 -> Point(0 - 92, 0 - 38)
    10 -> Point(0 - 71, 0 - 71)
    11 -> Point(0 - 38, 0 - 92)
    12 -> Point(0, 0 - 100)
    13 -> Point(38, 0 - 92)
    14 -> Point(71, 0 - 71)
    15 -> Point(92, 0 - 38)
  }
  Point(u.x * r / 100, u.y * r / 100)
}

fn round(n: Int, safe: Int) -> List(Path) {
  let t = n * 62
  list.append(wheel(0, t), cover(0, safe, t))
}

fn wheel(i: Int, t: Int) -> List(Path) {
  case i > 7 {
    True -> []
    False -> [
      Path(Gate(at(i * 2, 500), at(i * 2 + 2, 500)), t, t + 48, 8),
      ..wheel(i + 1, t)
    ]
  }
}

fn cover(i: Int, safe: Int, t: Int) -> List(Path) {
  case i > 45 {
    True -> []
    False -> list.append(row(i * 22 - 495, safe, t), cover(i + 1, safe, t))
  }
}

fn row(y: Int, safe: Int, t: Int) -> List(Path) {
  let gap = case y * y > 250000 {
    True -> Point(0, 0)
    False -> cut(safe, y, isqrt(250000 - y * y))
  }
  case gap.x >= gap.y {
    True -> [bar(-500, 500, y, t)]
    False -> [bar(-500, gap.x, y, t), bar(gap.y, 500, y, t)]
  }
}

fn bar(x0: Int, x1: Int, y: Int, t: Int) -> Path {
  Path(Gate(Point(x0, y), Point(x1, y)), t + 32, t + 48, 28)
}

fn cut(safe: Int, y: Int, h: Int) -> Point {
  case safe {
    0 -> open(y + 48, h - 48, y > 0)
    1 -> open(48, lesser(y, h) - 48, y > 0)
    2 -> open(0 - lesser(y, h) + 48, 0 - 48, y > 0)
    3 -> open(0 - h + 48, 0 - y - 48, y > 0)
    4 -> open(0 - h + 48, y - 48, y < 0)
    5 -> open(0 - lesser(0 - y, h) + 48, 0 - 48, y < 0)
    6 -> open(48, lesser(0 - y, h) - 48, y < 0)
    7 -> open(0 - y + 48, h - 48, y < 0)
  }
}

fn open(left: Int, right: Int, keep: Bool) -> Point {
  case keep && left < right {
    True -> Point(left, right)
    False -> Point(0, 0)
  }
}

fn lesser(a: Int, b: Int) -> Int {
  case a < b {
    True -> a
    False -> b
  }
}

fn isqrt(n: Int) -> Int {
  search(n, 0, 500)
}

fn search(n: Int, lo: Int, hi: Int) -> Int {
  case hi - lo <= 1 {
    True ->
      case hi * hi <= n {
        True -> hi
        False -> lo
      }
    False -> {
      let mid = { lo + hi } / 2
      case mid * mid <= n {
        True -> search(n, mid, hi)
        False -> search(n, lo, mid)
      }
    }
  }
}
",
  ),
]
