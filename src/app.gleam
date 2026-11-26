//// Animator -- an application for program-generated drawings.

import builtins
import data
import drawing
import editor
import errors
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import lustre
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import parser
import render
import shape.{type Path}

// Set the drawing menu's value once its options are in the document.
@external(javascript, "./data_ffi.mjs", "chooseOption")
fn choose_option(root: a, name: String) -> Nil

// Play mode lives next to the animation clock so a hit uses the same revealed
// stroke the canvas paints. These talk to that loop directly.
@external(javascript, "./canvas.mjs", "armPlayer")
fn arm_player() -> Nil

@external(javascript, "./canvas.mjs", "startRound")
fn start_round(on_hit: fn(Int) -> Nil, on_win: fn() -> Nil) -> Nil

@external(javascript, "./canvas.mjs", "stopGame")
fn stop_game() -> Nil

@external(javascript, "./canvas.mjs", "focusCanvas")
fn focus_canvas() -> Nil

@external(javascript, "./canvas.mjs", "after")
fn after(ms: Int, callback: fn() -> Nil) -> Nil

/// Your app's public address, once you've deployed it in Problem 13, such as
/// "https://your-username.github.io/animator/".
pub const public_url = ""

/// Set to True if you would like your app's URL included in the course gallery.
pub const include_app_in_gallery = False

/// A link to your video from Problem 14, which anyone with the link can watch.
pub const video_url = ""

/// Set to True if you would like your video included in the course gallery.
pub const include_video_in_gallery = False

// The select value for "create a drawing". It is not a drawing name.
const new_option = "__new__"

// Paths carry no colour of their own. This stroke shows on the dark canvas.
const stroke_color = "#e8d8b0"

// shape_slider is the Int passed to draw. The built-in reference documents [0, 100].
const shape_min = 0
const shape_max = 100

// Playback rate for render.set_speed. 1.0 is normal, 0 pauses, and a negative
// rate plays the drawing backward.
const speed_min = -3.0
const speed_max = 3.0
const speed_step = 0.1

// ── Model ──────────────────────────────────────────────────────────────────────

pub type Model {
  Model(
    // The code in the editor.
    source: String,
    // Whether the code editor is shown.
    code_open: Bool,
    output: String,
    // The Int passed to the user's draw function.
    shape_slider: Int,
    // Animation rate. 0 pauses, 1.0 is normal, and negative plays backward.
    speed: Float,
    // Saved drawings, examples first unless the user has added more.
    drawings: List(data.Drawing),
    // The name of the drawing open in the editor.
    selected: String,
    // True while the new-drawing prompt is open, so the menu shows that option.
    pending_new: Bool,
    // 1, 2, or 3. Used by Play, separate from the speed slider.
    play_rate: Int,
    // Draw shows the art. Play counts down, then dodges the lines.
    phase: Phase,
    // Bumped whenever a round is replaced, so a leftover countdown tick is ignored.
    round_id: Int,
  )
}

// Watching is ordinary playback. The other phases are the dodge game.
pub type Phase {
  Watching
  Countdown(Int)
  Playing
  Won
  Lost(Int)
}

pub type Msg {
  SetCode(String)
  SetShape(String)
  SetSpeed(String)
  DrawArt
  PlayLevel
  SetPlayRate(String)
  CountdownTick(Int)
  PlayerHit(Int)
  PlayerWon
  SelectDrawing(String)
  FinishNew(String)

  // Layout controls
  ToggleCode
}

// ── Init ───────────────────────────────────────────────────────────────────────

pub fn init(_flags: Nil) -> #(Model, Effect(Msg)) {
  let library = data.load()
  let source = case data.source(library.drawings, library.selected) {
    Ok(source) -> source
    Error(_) -> ""
  }
  #(
    Model(
      source:,
      code_open: True,
      output: "",
      shape_slider: 0,
      speed: 1.0,
      drawings: library.drawings,
      selected: library.selected,
      pending_new: False,
      play_rate: 1,
      phase: Watching,
      round_id: 0,
    ),
    // Effects that happen automatically at the start go here.
    effect.batch([
      editor.mount(source, SetCode),
      effect.from(fn(dispatch) { dispatch(SetCode(source)) }),
    ]),
  )
}

// Parse and evaluate a draw function at the given shape-slider value, returning
// the rendered paths on success, or a human-readable message on failure.
fn run_source(shape_slider: Int, source: String) -> Result(List(Path), String) {
  case parser.parse_program(source, builtins.global_frame()) {
    Error(msg) -> Error(msg)
    Ok(program) ->
      drawing.try_draw(shape_slider, program)
      // Convert Error(EvalError) to Error(String) with a useful error message.
      |> result.map_error(errors.error_message)
  }
}

// ── Update ─────────────────────────────────────────────────────────────────────

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ToggleCode -> #(Model(..model, code_open: !model.code_open), effect.none())

    // Draw the art from the start, at the speed slider, with no player.
    DrawArt -> #(
      Model(..model, phase: Watching, round_id: model.round_id + 1),
      effect.from(fn(_dispatch) {
        stop_game()
        render.set_speed(model.speed)
        render.reset_clock()
      }),
    )

    // Three seconds to move, then the lines reveal at the play-rate multiplier.
    PlayLevel -> {
      let round_id = model.round_id + 1
      #(
        Model(..model, phase: Countdown(3), round_id:),
        effect.from(fn(dispatch) {
          render.set_speed(0.0)
          render.reset_clock()
          arm_player()
          focus_canvas()
          after(1000, fn() { dispatch(CountdownTick(round_id)) })
        }),
      )
    }

    SetPlayRate(raw) ->
      case int.parse(raw) {
        Error(_) -> #(model, effect.none())
        Ok(n) ->
          case n >= 1 && n <= 5 {
            False -> #(model, effect.none())
            True -> {
              let model = Model(..model, play_rate: n)
              case model.phase {
                Playing -> #(
                  model,
                  effect.from(fn(_dispatch) { render.set_speed(int.to_float(n)) }),
                )
                _ -> #(model, effect.none())
              }
            }
          }
      }

    CountdownTick(id) ->
      case id == model.round_id {
        False -> #(model, effect.none())
        True ->
          case model.phase {
            Countdown(n) if n > 1 -> #(
              Model(..model, phase: Countdown(n - 1)),
              effect.from(fn(dispatch) {
                after(1000, fn() { dispatch(CountdownTick(id)) })
              }),
            )
            Countdown(_) -> #(
              Model(..model, phase: Playing),
              effect.from(fn(dispatch) {
                render.set_speed(int.to_float(model.play_rate))
                start_round(
                  fn(ms) { dispatch(PlayerHit(ms)) },
                  fn() { dispatch(PlayerWon) },
                )
              }),
            )
            _ -> #(model, effect.none())
          }
      }

    PlayerHit(ms) ->
      case model.phase {
        Playing -> #(
          Model(..model, phase: Lost(ms)),
          effect.from(fn(_dispatch) { render.set_speed(0.0) }),
        )
        _ -> #(model, effect.none())
      }

    PlayerWon ->
      case model.phase {
        Playing -> #(
          Model(..model, phase: Won),
          effect.from(fn(_dispatch) { render.set_speed(0.0) }),
        )
        _ -> #(model, effect.none())
      }

    SelectDrawing(name) ->
      case name == new_option {
        // Ask for the name after this event returns. prompt() freezes the page,
        // and a test that selects this option waits for the selection to finish
        // first. Asking inside the change handler makes that wait time out.
        True -> #(
          Model(..model, pending_new: True),
          effect.after_paint(fn(dispatch, _root) {
            dispatch(FinishNew(data.prompt_drawing_name()))
          }),
        )
        // Choosing the drawing that is already open must not rebuild the menu.
        // A test selects an option and waits for that choice to stick; remounting
        // here replaces the <select> and the choice never settles.
        False ->
          case name == model.selected {
            True -> #(model, effect.none())
            False -> open_drawing(model, name)
          }
      }

    // Cancel leaves the open drawing selected. A name copies its source, and a
    // name already in the library gets a numeric suffix. The menu is pointed at
    // that result after the new option has been added.
    FinishNew(raw) ->
      case data.fresh_name(model.drawings, raw) {
        "" -> #(
          Model(..model, pending_new: False),
          effect.after_paint(fn(_dispatch, root) {
            choose_option(root, model.selected)
          }),
        )
        name -> {
          let name = case name == new_option {
            True -> data.fresh_name(model.drawings, name <> " 2")
            False -> name
          }
          let drawings =
            list.append(model.drawings, [
              data.Drawing(name:, source: model.source),
            ])
          let model =
            Model(..model, drawings:, selected: name, pending_new: False)
          data.save(data.Library(selected: name, drawings:))
          #(
            model,
            effect.after_paint(fn(_dispatch, root) { choose_option(root, name) }),
          )
        }
      }

    // After each keystroke in the editor, save that text on the open drawing
    // and evaluate it.
    SetCode(text) -> {
      let drawings = data.update_source(model.drawings, model.selected, text)
      let model = Model(..model, drawings:)
      data.save(data.Library(selected: model.selected, drawings:))
      redraw(model, model.shape_slider, text)
    }

    // A new shape value re-runs draw. The clock stays where it is.
    SetShape(raw) ->
      case int.parse(raw) {
        Error(_) -> #(model, effect.none())
        Ok(n) -> redraw(model, n, model.source)
      }

    // Speed is independent of the drawing. Negative rates play it backward.
    SetSpeed(raw) ->
      case parse_speed(raw) {
        Error(_) -> #(model, effect.none())
        Ok(rate) -> {
          let model = Model(..model, speed: rate)
          // Play uses the 1x–5x menu. The slider must not overwrite that.
          case model.phase {
            Watching -> #(
              model,
              effect.from(fn(_dispatch) { render.set_speed(rate) }),
            )
            _ -> #(model, effect.none())
          }
        }
      }
  }
}

// Switch the editor and the canvas to a saved drawing. A drawing that does not
// parse or evaluate shows its code and error, and the canvas is cleared.
fn open_drawing(model: Model, name: String) -> #(Model, Effect(Msg)) {
  case data.source(model.drawings, name) {
    Error(_) -> #(model, effect.none())
    Ok(source) -> {
      let model =
        Model(
          ..model,
          selected: name,
          pending_new: False,
          phase: Watching,
          round_id: model.round_id + 1,
        )
      data.save(data.Library(selected: name, drawings: model.drawings))
      let #(model, draw) = case run_source(model.shape_slider, source) {
        Ok(paths) -> #(Model(..model, output: "", source:), show_drawing(paths))
        Error(msg) -> #(
          Model(..model, output: msg, source:),
          effect.from(fn(_dispatch) { render.set_drawing([]) }),
        )
      }
      #(
        model,
        effect.batch([
          editor.mount(source, SetCode),
          draw,
          effect.from(fn(_dispatch) {
            stop_game()
            render.set_speed(model.speed)
          }),
        ]),
      )
    }
  }
}

// Evaluate source at shape_slider. On success, replace the canvas paths without
// restarting the clock. On failure, show the error and clear the canvas so the
// previous drawing is not left on screen.
fn redraw(
  model: Model,
  shape_slider: Int,
  source: String,
) -> #(Model, Effect(Msg)) {
  let model =
    Model(..model, phase: Watching, round_id: model.round_id + 1)
  let halt =
    effect.from(fn(_dispatch) {
      stop_game()
      render.set_speed(model.speed)
    })
  case run_source(shape_slider, source) {
    Ok(paths) -> #(
      Model(..model, output: "", source: source, shape_slider: shape_slider),
      effect.batch([show_drawing(paths), halt]),
    )
    Error(msg) -> #(
      Model(..model, output: msg, source: source, shape_slider: shape_slider),
      effect.batch([
        effect.from(fn(_dispatch) { render.set_drawing([]) }),
        halt,
      ]),
    )
  }
}

// ── View ──────────────────────────────────────────────────────────────────
//
// Two side-by-side panes: the code editor on the left and its rendered output on
// the right. The code column can be hidden to expand the right pane.

pub fn view(model: Model) -> Element(Msg) {
  let app_class = case model.code_open {
    True -> "app"
    False -> "app code-hidden"
  }
  // The code column still exists even when hidden (CSS collapses it) so the
  // mounted CodeMirror editor keeps its state across show/hide.
  html.div([attr.class(app_class)], [
    html.div([attr.class("code-col")], [
      editor.view_panel(ToggleCode, view_menu(model)),
    ]),
    view_anim(model),
  ])
}

fn view_menu(model: Model) -> Element(Msg) {
  let value = case model.pending_new {
    True -> new_option
    False -> model.selected
  }
  html.select(
    [
      attr.class("drawing-select"),
      attr.attribute("data-test-id", "drawing-select"),
      attr.property("value", json.string(value)),
      event.on_change(SelectDrawing),
    ],
    list.append(
      list.map(model.drawings, fn(drawing) {
        html.option(
          [
            attr.value(drawing.name),
            attr.selected(drawing.name == value),
          ],
          drawing.name,
        )
      }),
      [
        html.option(
          [attr.value(new_option), attr.selected(value == new_option)],
          "New drawing...",
        ),
      ],
    ),
  )
}

fn view_anim(model: Model) -> Element(Msg) {
  html.div([attr.class("canvas-area")], [
    view_reveal_code(model),
    html.div([attr.class("canvas-stage")], [
      html.canvas([
        attr.id("animation-canvas"),
        attr.class("canvas"),
        attr.attribute("tabindex", "0"),
      ]),
      view_output(model),
      view_banner(model),
    ]),
    view_controls(model),
  ])
}

fn view_controls(model: Model) -> Element(Msg) {
  html.div([attr.class("controls")], [
    html.div([attr.class("control-sliders")], [
      slider(
        label: "shape",
        value: int.to_string(model.shape_slider),
        shown: int.to_string(model.shape_slider),
        min: int.to_string(shape_min),
        max: int.to_string(shape_max),
        step: "1",
        test_id: "shape-slider",
        on_input: SetShape,
      ),
      slider(
        label: "speed",
        value: float.to_string(model.speed),
        shown: float.to_string(model.speed),
        min: float.to_string(speed_min),
        max: float.to_string(speed_max),
        step: float.to_string(speed_step),
        test_id: "speed-slider",
        on_input: SetSpeed,
      ),
    ]),
    html.div([attr.class("mode-controls")], [
      html.button(
        [
          attr.class("draw"),
          attr.attribute("title", "Draw the art"),
          event.on_click(DrawArt),
        ],
        [html.text("Draw")],
      ),
      html.div([attr.class("play-row")], [
        html.button(
          [
            attr.class("play"),
            attr.attribute("title", "Play this drawing"),
            event.on_click(PlayLevel),
          ],
          [html.text("Play")],
        ),
        html.select(
          [
            attr.class("play-rate"),
            attr.attribute("data-test-id", "play-rate"),
            attr.attribute("title", "Play speed"),
            event.on_change(SetPlayRate),
          ],
          [
            play_rate_option(model, 1),
            play_rate_option(model, 2),
            play_rate_option(model, 3),
            play_rate_option(model, 4),
            play_rate_option(model, 5),
          ],
        ),
      ]),
    ]),
  ])
}

fn play_rate_option(model: Model, rate: Int) -> Element(Msg) {
  html.option(
    [attr.value(int.to_string(rate)), attr.selected(model.play_rate == rate)],
    int.to_string(rate) <> "x",
  )
}

fn slider(
  label label: String,
  value value: String,
  shown shown: String,
  min min: String,
  max max: String,
  step step: String,
  test_id test_id: String,
  on_input on_input: fn(String) -> Msg,
) -> Element(Msg) {
  html.label([attr.class("control")], [
    html.span([attr.class("control-label")], [html.text(label)]),
    html.input([
      attr.type_("range"),
      attr.class("control-slider"),
      attr.min(min),
      attr.max(max),
      attr.step(step),
      attr.value(value),
      attr.attribute("data-test-id", test_id),
      event.on_input(on_input),
    ]),
    html.span([attr.class("control-value")], [html.text(shown)]),
  ])
}

// The interpreter error, if the latest edit did not produce a drawing. An empty
// string means the canvas is showing the paths, so there is nothing to print.
fn view_banner(model: Model) -> Element(Msg) {
  case model.phase {
    Countdown(n) ->
      html.div([attr.class("banner")], [
        html.p([attr.class("banner-count")], [html.text(int.to_string(n))]),
        html.p([], [html.text("Click the canvas, then WASD")]),
      ])
    Lost(ms) ->
      html.div([attr.class("banner")], [
        html.p([attr.class("banner-title")], [html.text("Game over")]),
        html.p([], [
          html.text("You survived " <> format_seconds(ms) <> " seconds"),
        ]),
        html.p([], [html.text("Click Play below to play again")]),
      ])
    Won ->
      html.div([attr.class("banner")], [
        html.p([attr.class("banner-title")], [html.text("You win")]),
        html.p([], [
          html.text(
            "Speed multiplier: " <> int.to_string(model.play_rate) <> "x",
          ),
        ]),
      ])
    _ -> element.none()
  }
}

// Whole seconds plus one decimal place, from a millisecond count.
fn format_seconds(ms: Int) -> String {
  let tenths = ms / 100
  int.to_string(tenths / 10) <> "." <> int.to_string(tenths % 10)
}

fn view_output(model: Model) -> Element(Msg) {
  case model.output {
    "" -> element.none()
    text -> html.pre([attr.class("output")], [html.text(text)])
  }
}

// A range input reports "2" or "2.0" depending on the step. float.parse only
// accepts a decimal point, so an integer string is parsed and widened.
fn parse_speed(raw: String) -> Result(Float, Nil) {
  case float.parse(raw) {
    Ok(rate) -> Ok(rate)
    Error(_) -> result.map(int.parse(raw), int.to_float)
  }
}

fn show_drawing(paths: List(Path)) -> Effect(Msg) {
  let rendered = list.map(paths, render.render_path(_, stroke_color))
  effect.from(fn(_dispatch) { render.set_drawing(rendered) })
}

// The button that brings the code column back, overlaid on the top-left of the
// right pane. Nothing is rendered while the column is already showing (its own
// header holds the button that hides it).
fn view_reveal_code(model: Model) -> Element(Msg) {
  case model.code_open {
    True -> element.none()
    False ->
      html.button(
        [
          attr.class("icon-btn reveal-code"),
          attr.attribute("title", "Show code"),
          event.on_click(ToggleCode),
        ],
        [html.text("⟩")],
      )
  }
}

// ── Main ───────────────────────────────────────────────────────────────────────

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}
