use v5.40;
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use blib;
use Test2::V0;
use MockDriver;
use Uji;
use Uji::Layout;

my $layout = Uji::Layout->new( driver => MockDriver->new );

#  1. align_policy resolution and validation
subtest 'align_policy resolves per axis and validates' => sub {
    is Uji::button( label => 'x' )->align_policy('w'),                     undef,    'unset => undef';
    is Uji::button( label => 'x', align_w => 'center' )->align_policy('w'), 'center', 'align_w center';
    is Uji::button( label => 'x', align_w => 'center' )->align_policy('h'), undef,    'the other axis is independent';
    is Uji::button( label => 'x', align_h => 'end' )->align_policy('h'),    'end',    'align_h end';
    is Uji::button( label => 'x', align_w => 'stretch' )->align_policy('w'), 'stretch', 'stretch accepted';
    is Uji::button( label => 'x', align_h => 'start' )->align_policy('h'),   'start',   'start accepted';

    ok dies { Uji::text( 'x', align_w => 'middle' )->align_policy('w') }, 'an unknown policy dies';
};

#  2. Horizontal alignment inside a column
subtest 'align_w places a shrunk leaf across a column' => sub {
    my $col = Uji::column(
        padding  => 0,
        spacing  => 0,
        children => [
            Uji::button( label => 'OK', fit => 'content' ),                            # default start
            Uji::button( label => 'OK', fit => 'content', align_w => 'center' ),
            Uji::button( label => 'OK', fit => 'content', align_w => 'end' ),
            Uji::button( label => 'OK', w => 300,         align_w => 'end' ),          # explicit width
        ],
    );
    $layout->compute( $col, 0, 0, 400, 300 );

    my @b = @{ $col->children };
    is $b[0]->bx, 0,   'default alignment is start';
    is $b[1]->bx, 180, 'center: (400 - 40) / 2';
    is $b[2]->bx, 360, 'end: 400 - 40';
    is $b[3]->bx, 100, 'explicit 300-wide button ends at 400';
    is $b[1]->bw, 40,  'alignment does not change the computed size';
};

#  3. Vertical alignment inside a row
subtest 'align_h places a leaf down a row' => sub {
    my $row = Uji::row(
        padding  => 0,
        spacing  => 0,
        children => [
            Uji::button( label => 'OK' ),                                   # start
            Uji::button( label => 'OK', align_h => 'center' ),
            Uji::button( label => 'OK', align_h => 'end' ),
            Uji::button( label => 'OK', h => 40, align_h => 'center' ),
        ],
    );
    $layout->compute( $row, 0, 0, 400, 200 );

    my @b = @{ $row->children };
    is $b[0]->by, 0,   'default alignment is start';
    is $b[1]->by, 87,  'center: (200 - 26) / 2';
    is $b[2]->by, 174, 'end: 200 - 26';
    is $b[3]->by, 80,  'explicit 40-tall button centers at (200 - 40) / 2';
};

#  4. A floor-constrained content width aligns from the clamped size
subtest 'alignment uses the clamped cross size' => sub {
    my $col = Uji::column(
        padding  => 0,
        spacing  => 0,
        children => [ Uji::button( label => 'OK', fit_w => 'content', min_w => 120, align_w => 'center' ) ],
    );
    $layout->compute( $col, 0, 0, 400, 300 );

    my ($b) = @{ $col->children };
    is $b->bw, 120, 'min_w raises the content width first';
    is $b->bx, 140, 'center offsets from the clamped 120px width';
};

#  5. Children that already fill the cross axis do not move
subtest 'a filling child keeps a zero offset' => sub {
    my $row = Uji::row(
        padding  => 0,
        spacing  => 0,
        children => [ Uji::column( padding => 0, align_h => 'center', children => [ Uji::text('x') ] ) ],
    );
    $layout->compute( $row, 0, 0, 400, 200 );

    my ($nested) = @{ $row->children };
    is $nested->by, 0,   'a container that fills the row height stays at the top';
    is $nested->bh, 200, 'container fills the cross axis';
};

#  6. GroupBox applies align_w like a column
subtest 'group_box honors align_w' => sub {
    my $gb = Uji::group_box(
        label    => 'G',
        padding  => 0,
        spacing  => 0,
        children => [ Uji::button( label => 'x', fit_w => 'content', align_w => 'end' ) ],
    );
    $layout->compute( $gb, 0, 0, 400, 200 );

    my ($b) = @{ $gb->children };
    is $b->bw, 32,  'content button is 32 wide';
    is $b->bx, 368, 'end offset inside the group body (400 - 32)';
};

#  7. The Text/StatusText `align` text prop is untouched
subtest 'the text align prop coexists with align_w/align_h' => sub {
    my $t = Uji::text( 'x', align => 'center' );
    is $t->align,   'center', 'text align prop still readable';
    is $t->align_w, undef,    'align_w is a separate field';
};

done_testing;
