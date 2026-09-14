# NAME

Uji - Modern, asynchronous GUI toolkit Built with FFI and Elm Architecture

# SYNOPSIS

```perl
use v5.40;
use Uji;

# The MODEL: all of your UI state, in one plain hash
# The only mutable thing in the program. Every widget on screen reads
# from here, and nothing else tells the UI what to show.
my $model = { count => 0 };

# init(): produce the starting model and any initial commands
# Runs exactly once, before the window exists. Returns ($model, $cmd);
# the $cmd half is reserved for background side-effects and stays undef.
sub init () {
    return ( $model, undef );
}

# update(): fold a message into a new model
# Pure: given the same ($msg, $model) it always returns the same model.
# User gestures arrive here as plain hashref messages (see on_click,
# on_input, on_toggle below).
sub update ( $msg, $model ) {
    if ( $msg->{type} eq 'INCREMENT' ) {
        $model->{count} += 1;
    }
    elsif ( $msg->{type} eq 'RESET' ) {
        $model->{count} = 0;
    }
    return ( $model, undef );
}

# view(): turn the model into a declarative widget tree
# Called at startup and after every batch of messages. Uji diffs each new
# tree against the previous one and applies only the native updates that
# actually changed - so this isn't a full rebuild every time.
sub view ($model) {
    # window() is the root of every view; there is exactly one per view.
    Uji::window(
        title    => 'Counter',
        w        => 320,          # outer width/height
        h        => 140,
        centered => 1,
        child    => Uji::column(  # stacks children top-to-bottom
            padding  => 15,       # space from the edge to the children
            spacing  => 12,       # gap between consecutive children
            children => [
                Uji::text( 'Count: ' . $model->{count} ),   # a static label
                Uji::row(         # lays children out left-to-right
                    spacing  => 10,
                    children => [
                        # flex => 2 is twice as wide as flex => 1.
                        # on_click is a static message, sent verbatim;
                        # the toolkit never touches this button again.
                        Uji::button( label => '+1',    flex => 2, on_click => { type => 'INCREMENT' } ),
                        Uji::button( label => 'Reset', flex => 1, on_click => { type => 'RESET' } )
                    ]
                )
            ]
        )
    );
}

# run(): mount the window and start the event loop
# connect the three callbacks; this never returns until the window closes.
Uji::app( init => \&init, update => \&update, view => \&view )->run;

# The whole program is one loop:
#   user clicks +1 -> { type => 'INCREMENT' } -> update() -> count is 1
#   -> view() rebuilds the tree -> reconciler redraws only the label.
#
# State never lives in the widgets; the UI is always a pure function of
# the model, so it can never drift out of sync with that state.
```

# DESCRIPTION

Uji is a concurrency-friendly GUI toolkit built with concepts from [The Elm
Architecture](https://guide.elm-lang.org/architecture/) (TEA). The declarative API wraps native widgets via FFI. Your UI
is a pure function of your data.

Every Uji program is the same three functions:

```
init()                -- the starting model
view(model)           -- turns the model into a widget tree
update(msg, model)    -- turns a message into a new model
```

The `view` function renders the model as a declarative tree of native widgets; user gestures arrive as messages; and
the pure `update` function folds each message into a new model. Uji owns everything else: windows, layout, event
plumbing, and the diffing that turns each render into minimal native updates. The UI can never drift out of sync with
the state that produced it, and all of it can be exercised headless.

## Design Goals

- **Describe, don't manipulate**

    You build the whole screen with the **view** function; Uji figures out the smallest native update. No raw handles, no
    imperative poking at widgets.

- **The model is the source of truth**

    Every visible property - a checkmark, a slider thumb, an edit box's text - derives from the model in **view** and
    changes only when the model changes.

- **Asynchronous, cooperative**

    Events and rendering run as [Acme::Parataxis](https://metacpan.org/pod/Acme%3A%3AParataxis) fibers over a single message channel: responsive without threads, locks,
    or callbacks.

- **One layout, every platform**

    Widget bounds are computed in pure Perl, so behavior is identical across backends and the layout is testable with no
    window at all.

## An Introduction to The Elm Architecture

To really grasp how Uji works, you should be familiar with the Elm Architecture.

Here's a quick rundown...

### The Trio

An Uji application is three callbacks passed to ["app"](#app):

- `init( )`

    Returns `( $initial_model, $initial_cmd )`. Runs once at startup. The `$cmd` half is reserved for background
    side-effects and is currently unused; return `undef`.

- `update( $msg, $model )`

    Returns `( $new_model, $cmd )`. Pure (ideally): given the same message and model it produces the same model every
    time. Mutating the model in place and returning it is acceptable, but see ["Write Your update() As a Pure Function"](#write-your-update-as-a-pure-function).

- `view( $model )`

    Returns a virtual window (see the helper functions in the next section). This is called once at mount time and again
    after every batch of messages, and its output is diffed against the previous render.

### Messages

A message is a plain hash reference with a `type` key:

```perl
{ type => 'INCREMENT' }
{ type => 'SET_NAME',  value => 'Sanko' }
{ type => 'SET_LEVEL', value => 62 }
```

The **view** function attaches messages to widgets using the `on_*` callback parameters. Two shapes are supported:

- A static message hashref

    ```perl
    Uji::button( label => '+1', on_click => { type => 'INCREMENT' } );
    ```

    Sent verbatim whenever the widget fires. Best for controls whose message carries no state.

- A callback returning a message hashref

    ```perl
    Uji::checkbox(
        label     => 'Dark mode',
        checked   => $model->{dark},
        on_toggle => sub ($on) { { type => 'TOGGLE_DARK', value => $on } }
    );
    ```

    The callback receives the widget's current value as an argument and is expected to return a message (or `undef` to
    ignore the event). The arguments differ per widget:

    ```perl
    text_input  on_input  -> sub ($text)  { ... }   # full text string
    slider      on_change -> sub ($value) { ... }   # numeric position
    checkbox    on_toggle -> sub ($on)    { ... }   # 1 or 0
    radio_group on_select -> sub ($value) { ... }   # selected option's value
    ```

## The Render Pipeline

When the app starts, `Uji::app(...)-`run> does:

- 1. `init` produces the initial model.
- 2. `view` renders it to a virtual tree.
- 3. The driver creates the native window and controls _at their measured, absolute positions_
(mount), and the tooltip infrastructure is wired up.
- 4. An event pump fiber polls the message queue while a render fiber waits on the channel.
- 5. Each user gesture **is** a message. Messages are drained in batches, folded through
`update`, and then `view` is called once, producing a new virtual tree.
- 6. A reconciler diffs the new tree against the old one and issues the smallest set of native
updates (positions, text, check state, ...).

The key property: no matter how many messages arrive in a tick, the view is only re-rendered once per batch.

## Write Your update() As a Pure Function

Elm's single most important convention is that the model is the [source of
truth](https://en.wikipedia.org/wiki/Single_source_of_truth), not the widgets. Advice that keeps things sane:

- Do **not** read widget values inside `update`.

    The message already carries the value it needs (handed to your `on_*` callback by the driver, which reads native state
    at event time).

- Do **not** grab the native handle from the driver and mutate the widget.

    There is a reconciler for that. If a property is missing from the model, add the property via the widget prop system
    (see ["Lifecycle of a Property"](#lifecycle-of-a-property)) which is the only sanctioned mutation path.

# FUNCTIONS

All functions are exported by default. Each is a thin constructor for a [Uji::Node](https://metacpan.org/pod/Uji%3A%3ANode) subclass or the
application object.

## `app ( %args )`

Constructs the application runtime. Returns a [Uji::App](https://metacpan.org/pod/Uji%3A%3AApp) object; call `run` on it.

```perl
Uji::app(
    init   => \&init,      # required
    update => \&update,    # required
    view   => \&view      # required
)->run;
```

Optional parameters (rarely needed):

```
driver      # a Uji::Driver instance (default: Uji::Driver::detect)
channel     # a message channel
reconciler  # a Uji::Reconciler
layout      # a Uji::Layout
```

## `window ( %args )`

The root of every view. There is exactly one per view.

```perl
Uji::window(
    title     => 'My App',
    w         => 380,          # outer size
    h         => 600,
    child     => Uji::column(...),
    centered  => 1,
    resizable => 1             # default
);
```

Common parameters:

- `title`

    The window title. Default `'Uji Application'`. Live-updates to the title bar.

- `w`, `h`

    Requested outer width/height. Default 0 (the platform decides).

- child

    The root layout container. Optional; a window with no child renders an empty content area.

- centered

    `1` to center the window on screen at creation. Default 0.

- `resizable`

    `1` to allow user resizing, `0` to fix the size. Default 1.

- `topmost`

    `1` to keep the window above all others. Default 0.

- `minimized` / `maximized`

    Initial window state flags. Default 0 each.

- `min_w` / `min_h` / `max_w` / `max_h`

    Track-size constraints enforced by the OS. 0 means unconstrained.

## `column ( %args )`, `row ( %args )`

Vertical / horizontal flex containers.

```perl
Uji::column( padding => 15, spacing => 12, children => [ ... ] );
```

- `children`

    An array reference of child nodes. The container lays them out along its main axis, splitting remaining space among
    children with `flex > 0`.

- `padding`

    Space between the container's edge and its children. Column default 10, row default 0.

- `spacing`

    Gap between consecutive children. Column default 10, row default 10.

## `text ( $label, %args )`

A static label. The first argument is positional.

```
Uji::text( 'Hello, ' . $model->{name} );
```

The label is a plain string; the toolkit does no markup interpretation.

## `button ( %args )`

A push button that fires ["on\_click"](#on_click).

```perl
Uji::button( label => '+1', on_click => { type => 'INCREMENT' } );
```

- `label`

    The button text. Default `''`.

- `on_click`

    A static message hashref, sent when the button is clicked. See ["Messages"](#messages).

## `text_input ( %args )`

A single-line text editor.

```perl
Uji::text_input(
    value    => $model->{name},
    readonly => $model->{locked},
    focused  => 1,
    on_input => sub ($text) { { type => 'SET_NAME', value => $text } }
);
```

- `value`

    The editor's text. Default `''`.

- `on_input`

    Callback receiving the full text (`sub ($text) { ... }`) whenever the user edits the control. Returns a message (or
    `undef`).

- `readonly`

    `1` to prevent editing. Default 0.

- `maxlength`

    Maximum number of characters. 0 = unlimited.

- `focused`

    `1` to give the control keyboard focus at mount/on change. Default 0.

## `password ( %args )`

A masked text editor (an edit control with />`ES_PASSWORD`). The native display is hidden; the message
payload is the plain text.

```perl
Uji::password( value => $model->{secret}, on_input => sub ($t) { { type => 'SET_SECRET', value => $t } } );
```

Same parameters as ["text\_input"](#text_input).

## `slider ( %args )`

A horizontal range slider.

```perl
Uji::slider(
    value     => $model->{level},
    min       => 0,
    max       => 100,
    step      => 1,               # or 25 when "locked"
    on_change => sub ($v) { { type => 'SET_LEVEL', value => $v } }
);
```

- `value`

    Current position. Default 0.

- `min` / `max`

    Range endpoints. Defaults 0 / 100.

- `step`

    Increment used by arrow-key / page interaction. Default 1.

- `on_change`

    Callback receiving the numeric position. Returns a message (or `undef`).

## `checkbox ( %args )`

A toggle box. Fires ["on\_toggle"](#on_toggle) on every click with the new state.

```perl
Uji::checkbox(
    label     => 'Dark mode',
    checked   => $model->{dark},
    on_toggle => sub ($on) { { type => 'TOGGLE_DARK', value => $on } }
);
```

- `label`

    Adjacent text. Default `''`.

- `checked`

    `1` for checked, `0` for unchecked. Default 0.

- `on_toggle`

    Callback receiving `1` or `0`. Returns a message (or `undef`).

## `radio_group ( %args )`

An exclusive-choice group; the group is stored as a single scalar in the model.

```perl
Uji::radio_group(
    value   => $model->{color},
    options => [
        { value => 'red',   label => 'Red' },
        { value => 'green', label => 'Green' },
        { value => 'blue',  label => 'Blue' }
    ],
    on_select => sub ($v) { { type => 'SET_COLOR', value => $v } }
);
```

- `value`

    The currently selected option's `value`. Default `''`.

- `options`

    Array reference of `{ value => ..., label => ... }` hashrefs. The `label` defaults to the `value`.

- `spacing`

    Gap between the radio buttons. Default 4.

- `on_select`

    Callback receiving the selected option's `value`. Returns a message (or `undef`).

Radios are created internally as [Uji::Node::Radio](https://metacpan.org/pod/Uji%3A%3ANode%3A%3ARadio) children whose [Uji::Node](https://metacpan.org/pod/Uji%3A%3ANode) ids are memoized per group instance,
so the native checkboxes keep stable handles across re-renders even as the model changes the selection.

# COMMON NODE PARAMETERS

Every widget (and the window) accepts the following parameters, provided by the base class [Uji::Node](https://metacpan.org/pod/Uji%3A%3ANode):

- `id`

    A stable identifier, normally auto-generated (101, 102, ...). Handles are keyed by id for the lifetime of a widget; the
    reconciler preserves ids across renders. Provide your own only when you need a stable external key.

- `x`, `y`, `w`, `h`

    Requested position/size, used by layout. The computed position lives in the `bx`/`by`/`bw`/`bh` readers after a
    layout pass - prefer `flex` over manual sizing in containers.

- `flex`

    A proportionality hint (0 = natural size, 1 = take a share of free space). In a row with two `flex` buttons, `flex
    &#x3d;> 2` is twice as wide as `flex => 1`.

- `enabled`

    `1` to accept input, `0` to grey it out. Default 1.

- `visible`

    `1` to show, `0` to hide and release layout space. Default 1.

- `tooltip`

    A short hover tooltip string. Default `undef` (no tooltip).

# The Message Round-Trip, Annotated

Here is the full journey of a single button click:

- 1. The user presses the native button.
- 2. The OS posts `WM_COMMAND` to the window procedure.
- 3. The driver looks up the control in its registry, reads any state the handler needs (e.g.
[BM\_GETCHECK](https://metacpan.org/pod/BM_GETCHECK)), and calls your `on_click` / `on_toggle` / `on_select` / `on_input` /
`on_change` handler.
- 4. The resulting message hashref is `put` onto the channel.
- 5. The render fiber wakes, drains every pending message, and folds them through `update` in
order.
- 6. `view` rebuilds the entire virtual tree from the new model.
- 7. The reconciler walks the old and new trees side-by-side, transfers ids, and emits native
updates (position moves, text/check/state changes) only where a property actually changed.
- 8. The native controls reflect the new model.

# Lifecycle of a Property

To expose a widget property to the model, all three layers must agree on its name. The pattern for any property (the
toolkit's own widgets are built this way):

- 1. A `field $prop : param : reader` on the node class.
- 2. A `can('prop')` diff in [Uji::Reconciler](https://metacpan.org/pod/Uji%3A%3AReconciler)'s `patch`, so a change
triggers [set\_prop](https://metacpan.org/pod/set_prop).
- 3. A branch in the platform driver's `set_prop` that applies the value to the native
control.

This is why the toolkit can run the entire render cycle headless: point the reconciler at a mock driver and the
"native" side is just a hash of recorded calls (see `t/lib/MockDriver.pm`).

# Event Loop and Sub-processes

`run` never returns while the window is open; the process exits when the window is destroyed. Internally two
[Acme::Parataxis](https://metacpan.org/pod/Acme%3A%3AParataxis) fibers cooperate: one pumps platform events with non-blocking polls, the other blocks on the message
channel. The `RESIZE` and `QUIT` message types are reserved for internal use - do not send or filter them from your
`update` function.

# SEE ALSO

- [Uji::App](https://metacpan.org/pod/Uji%3A%3AApp) - the TEA runtime (fibers, channel, render loop)
- [Uji::Node](https://metacpan.org/pod/Uji%3A%3ANode) - the base virtual-node class and common parameters
- [Uji::Node::Button](https://metacpan.org/pod/Uji%3A%3ANode%3A%3AButton), [Uji::Node::Text](https://metacpan.org/pod/Uji%3A%3ANode%3A%3AText), [Uji::Node::TextInput](https://metacpan.org/pod/Uji%3A%3ANode%3A%3ATextInput), [Uji::Node::Slider](https://metacpan.org/pod/Uji%3A%3ANode%3A%3ASlider),
[Uji::Node::Checkbox](https://metacpan.org/pod/Uji%3A%3ANode%3A%3ACheckbox), [Uji::Node::Radio](https://metacpan.org/pod/Uji%3A%3ANode%3A%3ARadio), [Uji::Node::RadioGroup](https://metacpan.org/pod/Uji%3A%3ANode%3A%3ARadioGroup), [Uji::Node::Column](https://metacpan.org/pod/Uji%3A%3ANode%3A%3AColumn),
[Uji::Node::Row](https://metacpan.org/pod/Uji%3A%3ANode%3A%3ARow), [Uji::Node::Window](https://metacpan.org/pod/Uji%3A%3ANode%3A%3AWindow)
- [Uji::Layout](https://metacpan.org/pod/Uji%3A%3ALayout) - the pure-Perl layout engine
- [Uji::Reconciler](https://metacpan.org/pod/Uji%3A%3AReconciler) - VDOM diffing and patching
- [Uji::Driver](https://metacpan.org/pod/Uji%3A%3ADriver), [Uji::Driver::Win32](https://metacpan.org/pod/Uji%3A%3ADriver%3A%3AWin32) - platform abstraction
- The Elm Architecture - [https://guide.elm-lang.org/architecture/](https://guide.elm-lang.org/architecture/)
- The Win32 SDK (user32.h, gdi32.h)

# LICENSE

This software is Copyright (c) 2026 by Sanko Robinson.

This is free software, licensed under:

```
The Artistic License 2.0 (GPL Compatible)
```

See the `LICENSE` file for full text.

# AUTHOR

Sanko Robinson - [https://github.com/sanko](https://github.com/sanko)
