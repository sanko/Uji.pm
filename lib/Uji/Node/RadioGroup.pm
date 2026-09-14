use v5.40;
use experimental 'class';
use Uji::Node;
use Uji::Node::Radio;
class Uji::Node::RadioGroup v0.0.1 : isa(Uji::Node) {
    field $value     : param : reader = '';
    field $options   : param : reader = [];
    field $on_select : param : reader = undef;
    field $padding   : param : reader = 0;
    field $spacing   : param : reader = 4;
    field $_kids     : reader = undef;    # memoized children (stable IDs across renders)
    sub _type {'radio_group'}

    # Build the radio button children once per instance. The reconciler diffs children by index
    # and transfers IDs (patch -> set_id), so caching here keeps HWNDs stable across re-renders.
    method children () {
        return $_kids if $_kids;
        my $first = 1;
        my @kids;
        for my $opt (@$options) {
            push @kids,
                Uji::Node::Radio->new(
                value     => $opt->{value},
                label     => $opt->{label} // $opt->{value},
                first     => $first,
                selected  => ( $opt->{value} eq $value ? 1 : 0 ),
                on_select => $on_select,
                );
            $first = 0;
        }
        $_kids = \@kids;
        return $_kids;
    }
};
1;
