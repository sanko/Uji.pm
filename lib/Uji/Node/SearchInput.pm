use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::SearchInput v0.0.1 : isa(Uji::Node) {
    field $value       : param : reader = '';
    field $placeholder : param : reader = '';
    field $icon        : param : reader = '';      # data:image/... URI for the leading magnifier glyph
    field $on_input    : param : reader = undef;   # sub($text) -> msg, fired on every keystroke
    field $on_search   : param : reader = undef;   # sub($text) -> msg, fired when the field is cleared
    sub _type {'search_input'}

    # The glyph and edit margins are baked at creation; changing the icon recreates the control.
    method _mount_only_props () { ['icon'] }
};
1;