use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::TabPanel v0.0.1 : isa(Uji::Node) {
    field $panels    : param : reader = [];
    field $index     : param : reader = 0;
    field $on_select : param : reader = undef;
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
