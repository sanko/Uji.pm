use v5.40;
use experimental 'class';
use Uji::Node;

# An inline colour well: a swatch button that shows the current colour (plus its hex
# when asked) and opens the platform colour chooser when clicked. Distinct from the
# blocking color_picker driver API - the swatch OWNS opening the chooser and reports
# the result through `on_change`, the native color-well contract (GTK GtkColorButton
# opens a chooser on click, Cocoa NSColorWell opens NSColorPanel).
class Uji::Node::ColorButton v0.0.1 : isa(Uji::Node) {
    field $show_hex  : param : reader = 1;            # print the hex next to the swatch
    field $on_change : param : reader = undef;        # coderef: picker chose a colour -> action
    sub _type {'color_button'}
};
1;