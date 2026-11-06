use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::TabPanel v0.0.1 : isa(Uji::Node) {
    field $tabs      : param : reader = [];
    field $selected  : param : reader = 0;       # 0-based index of active tab
    field $on_select : param : reader = undef;
    field $padding   : param : reader = 10;
    sub _type {'tab_panel'}

    method active_tab () {
        return $tabs->[$selected] if $selected >= 0 && $selected < @$tabs;
        return $tabs->[0];
    }

    # In the VDOM, only the active tab's content is rendered in the body area
    method children () {
        my $at = $self->active_tab;
        return ( $at && $at->child ) ? [ $at->child ] : [];
    }
};
1;
