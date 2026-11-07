use v5.40;
use experimental 'class';
use Uji::Node;
class Uji::Node::DatePicker v0.0.1 : isa(Uji::Node) {
    field $value        : param : reader = undef;            # 'YYYY-MM-DD'
    field $format       : param : reader = 'short';          # 'short' | 'long' | 'time'
    field $min          : param : reader = undef;
    field $max          : param : reader = undef;
    field $show_none    : param : reader = 0;
    field $on_change    : param : reader = undef;
    field $useynavigate : param : reader = builtin::false;
    sub _type {'date_picker'}

    method _iso ($s) {
        return undef unless defined $s;
        $s =~ /^(\d{4})-(\d{2})-(\d{2})$/ or return undef;
        return [ $1 + 0, $2 + 0, $3 + 0 ];
    }
    method year ()      { my $v = $self->_iso($value); return $v ? $v->[0] : undef }
    method month ()     { my $v = $self->_iso($value); return $v ? $v->[1] : undef }
    method day ()       { my $v = $self->_iso($value); return $v ? $v->[2] : undef }
    method max_year ()  { my $v = $self->_iso($max);   return $v ? $v->[0] : undef }
    method max_month () { my $v = $self->_iso($max);   return $v ? $v->[1] : undef }
    method max_day ()   { my $v = $self->_iso($max);   return $v ? $v->[2] : undef }
    method min_year ()  { my $v = $self->_iso($min);   return $v ? $v->[0] : undef }
    method min_month () { my $v = $self->_iso($min);   return $v ? $v->[1] : undef }
    method min_day ()   { my $v = $self->_iso($min);   return $v ? $v->[2] : undef }

    method _mount_only_props () {
        return [ 'format', 'show_none', 'useynavigate' ];
    }
};
1;
