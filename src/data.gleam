//// The library of saved drawings. A drawing is a name and the source of its draw
//// function. The whole library is one localStorage string, and each drawing's
//// source is stored unchanged so a search can find text the user typed.

import examples
import gleam/int
import gleam/list
import gleam/result
import gleam/string

// ── localStorage (data_ffi.mjs) ───────────────────────────────────────────────

/// The string stored in localStorage under key, or an Error if there isn't one.
@external(javascript, "./data_ffi.mjs", "storageGet")
pub fn storage_get(key: String) -> Result(String, Nil)

/// Store value in localStorage under key, replacing anything already there. If that
/// isn't possible, this logs the reason to the browser console.
@external(javascript, "./data_ffi.mjs", "storageSet")
pub fn storage_set(key: String, value: String) -> Nil

// ── The new-drawing prompt (data_ffi.mjs) ─────────────────────────────────────

/// Prompt the user to name a new drawing; "" (empty string) means they
/// cancelled or left it blank.
@external(javascript, "./data_ffi.mjs", "promptDrawingName")
pub fn prompt_drawing_name() -> String

// ── The library ───────────────────────────────────────────────────────────────

const storage_key = "drawings"

pub type Drawing {
  Drawing(name: String, source: String)
}

pub type Library {
  Library(selected: String, drawings: List(Drawing))
}

/// The saved library, or the built-in examples when nothing usable is stored.
pub fn load() -> Library {
  case storage_get(storage_key) {
    Error(_) -> from_examples()
    Ok(raw) ->
      case decode(raw) {
        Ok(library) -> library
        Error(_) -> from_examples()
      }
  }
}

/// Replace the saved library. Each drawing's source is copied in unchanged.
pub fn save(library: Library) -> Nil {
  storage_set(storage_key, encode(library))
}

/// The drawings a browser with no saved library starts with. The first example
/// is the one that opens.
pub fn from_examples() -> Library {
  let drawings =
    list.map(examples.all, fn(pair) {
      let #(name, source) = pair
      Drawing(name:, source:)
    })
  case drawings {
    [first, ..] -> Library(selected: first.name, drawings:)
    [] -> Library(selected: "", drawings: [])
  }
}

/// The source of the drawing with this name.
pub fn source(drawings: List(Drawing), name: String) -> Result(String, Nil) {
  case list.find(drawings, fn(drawing) { drawing.name == name }) {
    Ok(drawing) -> Ok(drawing.source)
    Error(_) -> Error(Nil)
  }
}

/// Replace the source of the named drawing, leaving the others as they are.
pub fn update_source(
  drawings: List(Drawing),
  name: String,
  source: String,
) -> List(Drawing) {
  list.map(drawings, fn(drawing) {
    case drawing.name == name {
      True -> Drawing(..drawing, source:)
      False -> drawing
    }
  })
}

/// A name that is not already in the library. A free name is kept. A taken name
/// gets " 2", then " 3", and so on: "fan" becomes "fan 2".
pub fn fresh_name(drawings: List(Drawing), desired: String) -> String {
  let desired =
    desired
    |> string.replace("\n", "")
    |> string.replace("\r", "")
    |> string.trim
  case desired == "" {
    True -> ""
    False ->
      case taken(drawings, desired) {
        False -> desired
        True -> numbered(drawings, desired, 2)
      }
  }
}

fn numbered(drawings: List(Drawing), stem: String, n: Int) -> String {
  let candidate = stem <> " " <> int.to_string(n)
  case taken(drawings, candidate) {
    False -> candidate
    True -> numbered(drawings, stem, n + 1)
  }
}

fn taken(drawings: List(Drawing), name: String) -> Bool {
  list.any(drawings, fn(drawing) { drawing.name == name })
}

// The stored text is a version line, the open drawing's name, how many drawings
// follow, then each name, the grapheme length of its source, and that source.
// Lengths keep the source exact, including newlines and any text the user typed.
fn encode(library: Library) -> String {
  let head =
    "1\n"
    <> library.selected
    <> "\n"
    <> int.to_string(list.length(library.drawings))
    <> "\n"
  list.fold(library.drawings, head, fn(acc, drawing) {
    acc
    <> drawing.name
    <> "\n"
    <> int.to_string(string.length(drawing.source))
    <> "\n"
    <> drawing.source
  })
}

fn decode(raw: String) -> Result(Library, Nil) {
  use #(version, rest) <- result.try(read_line(raw))
  use Nil <- result.try(case version {
    "1" -> Ok(Nil)
    _ -> Error(Nil)
  })
  use #(selected, rest) <- result.try(read_line(rest))
  use #(count, rest) <- result.try(read_line(rest))
  use count <- result.try(int.parse(count))
  use #(drawings, _) <- result.try(read_drawings(rest, count))
  case drawings {
    [] -> Error(Nil)
    [first, ..] ->
      case taken(drawings, selected) {
        True -> Ok(Library(selected:, drawings:))
        False -> Ok(Library(selected: first.name, drawings:))
      }
  }
}

fn read_drawings(
  rest: String,
  n: Int,
) -> Result(#(List(Drawing), String), Nil) {
  case n <= 0 {
    True -> Ok(#([], rest))
    False -> {
      use #(name, rest) <- result.try(read_line(rest))
      use #(len, rest) <- result.try(read_line(rest))
      use len <- result.try(int.parse(len))
      use #(source, rest) <- result.try(take(rest, len))
      use #(more, rest) <- result.try(read_drawings(rest, n - 1))
      Ok(#([Drawing(name:, source:), ..more], rest))
    }
  }
}

fn read_line(text: String) -> Result(#(String, String), Nil) {
  string.split_once(text, "\n")
}

// Split on graphemes only. drop_start measures the cut in UTF-8 bytes and then
// slices the JavaScript string by those bytes, so a non-ASCII character shifts
// every later drawing and the library no longer loads.
fn take(text: String, n: Int) -> Result(#(String, String), Nil) {
  let total = string.length(text)
  case n >= 0 && total >= n {
    True -> Ok(#(string.slice(text, 0, n), string.slice(text, n, total - n)))
    False -> Error(Nil)
  }
}
