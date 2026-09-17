use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::MenuBar v0.0.1 : isa(Uji::Node) {
    field $items    : param : reader = [];       # [{ label => 'File', children => [ { label => 'New', id => 'new' }, ... ] }]
    field $on_click : param : reader = undef;    # sub ($id) { ... }

    # The items are SNAPSHOT at construction (deep copy). view() runs on every render and the
    # model may mutate the same items structure in place between renders (e.g. toggling `checked`
    # on a click). Without the copy the previous render's MenuBar node would share the arrayref,
    # so the reconciler's _menu_key(old) == _menu_key(new) and the native menu is never rebuilt.
    # Deep-cloning makes each render's node an immutable snapshot of that moment's model state.
    ADJUST {
        $items = _clone_items($items // []);
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