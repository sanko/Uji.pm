use v5.40;
use experimental 'class';
use Uji::Node;
use Uji::Node::Row;
use Uji::Node::Button;
use Uji::Node::Text;
use Uji::Node::Spacer;
class Uji::Node::Calendar v0.0.1 : isa(Uji::Node) {
    field $value     : param : reader = undef;    # ISO 'YYYY-MM-DD'
    field $month     : param : reader = undef;    # displayed month 'YYYY-MM'
    field $min       : param : reader = undef;    # ISO lower bound
    field $max       : param : reader = undef;    # ISO upper bound
    field $on_select : param : reader = undef;    # sub ($iso) -> msg
    field $on_nav    : param : reader = undef;    # sub ($delta) -> msg
    field $children  : param : reader = [];
    field $padding   : param : reader = 8;
    field $spacing   : param : reader = 2;
    sub _type {'calendar'}

    sub _dim ( $y, $m ) {
        my $leap = ( $y % 4 == 0 && $y % 100 != 0 ) || $y % 400 == 0;
        return ( 31, $leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 )[ $m - 1 ];
    }

    sub _first_wday ( $y, $m ) {
        my ( $yy, $mm ) = $m <= 2 ? ( $y - 1, $m + 12 ) : ( $y, $m );
        my $k = $yy % 100;
        my $j = int( $yy / 100 );
        my $h = ( 1 + int( ( 13 * ( $mm + 1 ) ) / 5 ) + $k + int( $k / 4 ) + int( $j / 4 ) - ( 2 * $j ) ) % 7;
        return ( $h + 6 ) % 7;
    }

    method _build () {
        my $ym = $month;
        my $v  = $value;
        my ( $y, $m );
        if ( defined $ym && $ym =~ /^(\d{4})-(\d{2})$/ && $2 >= 1 && $2 <= 12 ) {
            ( $y, $m ) = ( $1 + 0, $2 + 0 );
        }
        elsif ( defined $v && $v =~ /^(\d{4})-(\d{2})-(\d{2})$/ ) {
            ( $y, $m ) = ( $1 + 0, $2 + 0 );
        }
        else {
            ( $y, $m ) = ( ( localtime(time) )[5] + 1900, ( localtime(time) )[4] + 1 );
        }
        my $id       = $self->id;
        my $lo       = ( defined $min && $min =~ /^(\d{4})-(\d{2})-(\d{2})$/ ) ? [ $1 + 0, $2 + 0, $3 + 0 ] : undef;
        my $hi       = ( defined $max && $max =~ /^(\d{4})-(\d{2})-(\d{2})$/ ) ? [ $1 + 0, $2 + 0, $3 + 0 ] : undef;
        my $sel      = ( defined $v   && $v   =~ /^(\d{4})-(\d{2})-(\d{2})$/ ) ? [ $1 + 0, $2 + 0, $3 + 0 ] : undef;
        my $navigate = sub ($d) {
            return sub {
                my $a = $self->on_nav ? $self->on_nav->($d) : undef;
                return $a;
            };
        };
        my @months = qw(January February March April May June July August September October November December);
        my @hdr    = (
            Uji::Node::Button->new( id => "$id-nav-prev", label => '◀', w => 28, h => 24, on_click => $navigate->(-1) ),
            Uji::Node::Text->new( id => "$id-title", label => $months[ $m - 1 ] . ' ' . $y, align => 'center', flex => 1, h => 24 ),
            Uji::Node::Button->new( id => "$id-nav-next", label => '▶', w => 28, h => 24, on_click => $navigate->(1) )
        );
        my @rows  = ( Uji::Node::Row->new( id => "$id-hdr", padding => 0, spacing => 2, children => \@hdr ) );
        my @dow   = qw(S M T W T F S);
        my @wkday = map {
            my $i = $_;
            Uji::Node::Text->new( id => "$id-dow-$i", label => $dow[$i], w => 28, h => 18, align => 'center' )
        } 0 .. 6;
        push @rows, Uji::Node::Row->new( id => "$id-wkday", padding => 0, spacing => 2, children => \@wkday );
        my $dim = _dim( $y, $m );
        my $f   = _first_wday( $y, $m );
        for my $w ( 0 .. 5 ) {
            my @cells;
            my $start = 1 - $f + ( $w * 7 );
            for my $i ( 0 .. 6 ) {
                my $d = $start + $i;
                if ( $d >= 1 && $d <= $dim ) {
                    my $ymd      = sprintf( '%04d-%02d-%02d', $y, $m, $d );
                    my $below_lo = $lo && ( $y * 10000 + $m * 100 + $d ) < ( $lo->[0] * 10000 + $lo->[1] * 100 + $lo->[2] );
                    my $above_hi = $hi && ( $y * 10000 + $m * 100 + $d ) > ( $hi->[0] * 10000 + $hi->[1] * 100 + $hi->[2] );
                    my $pick     = sub () {
                        my $a = $self->on_select ? $self->on_select->($ymd) : undef;
                        return $a;
                    };
                    push @cells,
                        Uji::Node::Button->new(
                        id         => "$id-day-$ymd",
                        label      => "$d",
                        w          => 28,
                        h          => 22,
                        enabled    => $below_lo || $above_hi                                        ? 0         : 1,
                        background => $sel && $sel->[0] == $y && $sel->[1] == $m && $sel->[2] == $d ? '#BBD8F4' : undef,
                        on_click   => $pick
                        );
                }
                else {
                    push @cells, Uji::Node::Spacer->new( id => "$id-blank-$w-$i", w => 28, h => 22 );
                }
            }
            push @rows, Uji::Node::Row->new( id => "$id-week-$w", padding => 0, spacing => 0, children => \@cells );
        }
        $children = \@rows;
    }
};
1;
