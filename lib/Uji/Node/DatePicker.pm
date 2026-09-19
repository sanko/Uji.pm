use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::DatePicker v0.0.1 : isa(Uji::Node) {
    field $value        : param : reader = undef;             # ISO date 'YYYY-MM-DD' (or undef = no date shown)
    field $format       : param : reader = 'short';           # 'short' | 'long' | 'time'
    field $min          : param : reader = undef;             # ISO date 'YYYY-MM-DD' lower bound (range check)
    field $max          : param : reader = undef;             # ISO date 'YYYY-MM-DD' upper bound (range check)
    field $show_none    : param : reader = 0;                 # DTS_SHOWNONE: a checkbox lets the user clear the date
    field $on_change    : param : reader = undef;
    field $useynavigate : param : reader = builtin::false;    # DTS_UPDOWN: an up/down spinner instead of a dropdown
    sub _type {'date_picker'}

    # ISO 'YYYY-MM-DD' (or undef) -> [y, m, d] (numbers); undef on garbage.
    method _iso ($s) {
        $s =~ /^(\d{4})-(\d{2})-(\d{2})$/ or return;
        return [ $1 + 0, $2 + 0, $3 + 0 ];
    }
    method year()      { my $v = $self->_iso($value); return $v ? $v->[0] : undef; }
    method month()     { my $v = $self->_iso($value); return $v ? $v->[1] : undef; }
    method day()       { my $v = $self->_iso($value); return $v ? $v->[2] : undef; }
    method max_year()  { my $v = $self->_iso($max);   return $v ? $v->[0] : undef; }
    method max_month() { my $v = $self->_iso($max);   return $v ? $v->[1] : undef; }
    method max_day()   { my $v = $self->_iso($max);   return $v ? $v->[2] : undef; }
    method min_year()  { my $v = $self->_iso($min);   return $v ? $v->[0] : undef; }
    method min_month() { my $v = $self->_iso($min);   return $v ? $v->[1] : undef; }
    method min_day()   { my $v = $self->_iso($min);   return $v ? $v->[2] : undef; }

    # The picker's presentation (location/format, checkbox, updown arrows) is baked into the class
    # style at CreateWindowExW time, so changing any of these live requires a native recreate.
    method _mount_only_props () {
        return [ 'format', 'show_none', 'useynavigate' ];
    }
};
1;
