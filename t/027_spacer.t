use v5.40;
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use blib;
use Test2::V0;
use MockDriver;
use Uji;
use Uji::Layout;

# Spacer is pure layout: an invisible, zero-intrinsic flexible leaf. It never reaches the driver
# (no HWND, no registry record), so this test only ever exercises Uji::Layout against a mock.

my $layout = Uji::Layout->new( driver => MockDriver->new );

#  1. Zero intrinsic box
subtest 'spacer has a zero intrinsic box' => sub {
    my $sp = Uji::spacer( flex => 1 );
    is $sp->type,      'spacer', 'type is spacer';
    my ($nw, $nh) = $layout->_natural($sp);
    is $nw, 0, 'intrinsic width is 0';
    is $nh, 0, 'intrinsic height is 0';
};

#  2. Flex spacer claims leftover main-axis space in a row
subtest 'a flex spacer absorbs leftover width in a row' => sub {
    my $btn = sub { Uji::button( label => 'OK' ) };
    my $row = Uji::row(
        padding  => 0,
        spacing  => 0,
        children => [ $btn->(), Uji::spacer( flex => 1 ), $btn->() ],
    );
    $layout->compute( $row, 0, 0, 400, 200 );

    my ( $a, $sp, $b ) = @{ $row->children };
    my $used = $a->bw + $b->bw;
    is $sp->bx, $a->bw,                                    'spacer starts right after the first button';
    is $sp->bw, 400 - $used,                               'spacer takes the full leftover (400 - used)';
    is $sp->by, 0,                                         'spacer runs the full row height';
    is $sp->bh, $a->bh,                                    'spacer matches the sibling height';
    is $b->bx,  $sp->bx + $sp->bw,                         'second button sits at the right edge';
};

#  3. Flex weight splits leftover proportionally
subtest 'flex weights split the leftover proportionally' => sub {
    my $btn = sub { Uji::button( label => 'X' ) };
    my $row = Uji::row(
        padding  => 0,
        spacing  => 0,
        children => [ $btn->(), Uji::spacer( flex => 1 ), Uji::spacer( flex => 2 ), $btn->() ],
    );
    $layout->compute( $row, 0, 0, 300, 100 );

    my ( $a, $s1, $s2, $b ) = @{ $row->children };
    my $used = $a->bw + $b->bw;
    my $rest = 300 - $used;
    is $s1->bw, int( ( 1 / 3 ) * $rest ), 'weight 1 spacer gets a third of the leftover';
    is $s2->bw, int( ( 2 / 3 ) * $rest ), 'weight 2 spacer gets two thirds';
};

#  4. Explicit w/h works as a fixed-width span
subtest 'spacer can be a fixed size instead of flex' => sub {
    my $row = Uji::row(
        padding  => 0,
        spacing  => 0,
        children => [
            Uji::button( label => 'L' ),
            Uji::spacer( w => 10 ),
            Uji::button( label => 'R' ),
        ],
    );
    $layout->compute( $row, 0, 0, 600, 100 );

    my ( $l, $sp, $r ) = @{ $row->children };
    is $sp->bw, 10, 'explicit w honored';
    is $r->bx,  $l->bw + 10, 'right button offset by exactly the fixed spacer';
};

done_testing;
