use v5.40;
use FindBin;
use lib "$FindBin::Bin/lib", "$FindBin::Bin/t/lib", "$FindBin::Bin/t";
use blib;
use Test2::V0;
use MockDriver;
use Uji;
use Uji::Layout;

my $layout = Uji::Layout->new( driver => MockDriver->new );

subtest 'row: spacer bh matches sibling bh (cross-size h seam)' => sub {
    my $row = Uji::row(
        padding  => 0,
        spacing  => 0,
        children => [ Uji::button( label => 'OK' ), Uji::spacer( flex => 1 ), Uji::button( label => 'OK' ) ],
    );
    $layout->compute( $row, 0, 0, 400, 26 );

    my ( $a, $sp, $b ) = @{ $row->children };
    is $sp->bh, $a->bh, 'spacer bh equals button bh in a row (cross fill)';
    is $sp->bw, 400 - $a->bw - $b->bw, 'spacer bw absorbs leftover (main fill)';
    is $b->bx, $sp->bx + $sp->bw, 'button placed after spacer';
};

{   # verbatim dump of the h-branch in _cross_size
    my $f = "$FindBin::Bin/../lib/Uji/Layout.pm";
    open my $fh, "<", $f or die "open $f: $!";
    my @L = <$fh>;
    print "# ---- _cross_size 31-39 ----\n";
    for my $i ( 31 .. 39 ) { printf "# %3d: %s", $i, $L[ $i - 1 ]; }
}

done_testing();
