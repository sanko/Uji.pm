use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::DatePicker v0.0.1 : isa(Uji::Node) {
    field $value        : param : reader = undef;            # ISO date 'YYYY-MM-DD' (or undef = no date shown)
    field $format       : param : reader = 'short';          # 'short' | 'long' | 'time'
    field $min          : param : reader = undef;            # ISO date 'YYYY-MM-DD' lower bound (range check)
    field $max          : param : reader = undef;            # ISO date 'YYYY-MM-DD' upper bound (range check)
    field $show_none    : param : reader = 0;                # DTS_SHOWNONE: a checkbox lets the user clear the date
    field $on_change    : param : reader = undef;
    field $useynavigate : param : reader = builtin::false;
    sub _type      {'date_picker'}
    method year()  { }
    method month() { }
    method day()   { }
    #
    method max_year()  { }
    method max_month() { }
    method max_day()   { }
    method min_year()  { }
    method min_month() { }
    method min_day()   { }
};
1;
