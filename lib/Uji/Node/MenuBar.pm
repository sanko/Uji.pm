use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::MenuBar v0.0.1 : isa(Uji::Node) {
    field $items    : param : reader = [];
    field $on_click : param : reader = undef;
    ADJUST {
        $items = _clone_items( $items // [] );
    }

    sub _clone_items ($list) {
        return [ map { _clone_item($_) } @$list ];
    }

    sub _clone_item ($it) {
        return { separator => 1 } if $it->{separator};
        my %c = map { $_ => $it->{$_} } grep { ref $it->{$_} eq '' } keys %$it;
        $c{children} = _clone_items( $it->{children} ) if $it->{children};
        return \%c;
    }
    sub _type {'menu_bar'}
};
1;
