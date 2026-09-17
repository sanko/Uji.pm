use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::TabPanel v0.0.1 : isa(Uji::Node) {
    field $panels    : param : reader = [];       # list of { title =>, child => } (or [ $title, $child ]) sub-views
    field $index     : param : reader = 0;        # selected panel index
    field $on_select : param : reader = undef;    # sub ($index) -> update (fired when the user switches tabs)
    sub _type {'tab_panel'}

    method children () {
        my @kids;
        for my $p (@$panels) {
            my $child = ref $p eq 'HASH' ? $p->{child} : $p->[1];
            push @kids, $child if defined $child;
        }
        return \@kids;
    }
};
1;
