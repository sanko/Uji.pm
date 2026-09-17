use v5.40;
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use blib;
use Test2::V0;
use MockDriver;
use Uji;
use Uji::Layout;

# The fit policy is pure layout logic, so this test never touches a native driver.
my $layout = Uji::Layout->new( driver => MockDriver->new );

# Walk to the first child of a type under a subtree.
sub find_node ( $node, $type ) {
    return $node if $node->type eq $type;
    for my $child ( @{ $node->children } ) {
        my $hit = find_node( $child, $type );
        return $hit if $hit;
    }
    return undef;
}

# ── 1. Policy aliases, per-axis override, and validation ─────────────────
subtest 'fit_policy resolves aliases and per-axis overrides' => sub {
    is Uji::button( label => 'x', fit => 'stretch' )->fit_policy('w'), 'fill',    'stretch => fill (both axes)';
    is Uji::button( label => 'x', fit => 'fill' )->fit_policy('h'),    'fill',    'fill => fill';
    is Uji::button( label => 'x', fit => 'shrink' )->fit_policy('w'),  'content', 'shrink => content';
    is Uji::button( label => 'x', fit => 'fit' )->fit_policy('h'),     'content', 'fit => content';
    is Uji::button( label => 'x', fit => 'fixed' )->fit_policy('w'),   'fixed',   'fixed => fixed';
    is Uji::button( label => 'x' )->fit_policy('w'),                   undef,     'unset => undef';

    my $both = Uji::button( label => 'x', fit => 'content', fit_w => 'fill' );
    is $both->fit_policy('w'), 'fill',    'fit_w overrides fit on the width axis';
    is $both->fit_policy('h'), 'content', 'fit still applies to the height axis';
    is $both->fit_h,           undef,     'fit_h defaults to undef';

    ok dies { Uji::text( 'x', fit => 'bogus' )->fit_policy('w') }, 'an unknown policy dies';
};

# ── 2. Content fit shrinks a leaf to its natural size ────────────────────
subtest 'fit => content hugs content inside a column' => sub {
    my $col = Uji::column(
        padding  => 0,
        spacing  => 0,
        children => [
            Uji::button( label => 'OK' ),                        # default: fills the column
            Uji::button( label => 'OK', fit => 'content' ),      # shrink-to-content
        ],
    );
    $layout->compute( $col, 0, 0, 400, 300 );

    my @btns = grep { $_->type eq 'button' } @{ $col->children };
    is $btns[0]->bw, 400, 'default button fills the column width';
    is $btns[1]->bw, 40,  'content button hugs its label (16 text + 24 pad)';
    is $btns[1]->bh, 26,  'content button keeps its intrinsic height (16 + 10)';
    is $btns[1]->bx, 0,   'shrunk button stays at the cell origin';
};

# ── 3. flex now grows a leaf along the main (vertical) axis ──────────────
subtest 'flex grows a leaf along the container main axis' => sub {
    my $col = Uji::column(
        padding  => 0,
        spacing  => 0,
        children => [
            Uji::text('head'),
            Uji::button( label => 'grow', flex => 1 ),
        ],
    );
    $layout->compute( $col, 0, 0, 400, 200 );

    my ( $head, $grow ) = @{ $col->children };
    is $head->bh, 16,  'non-flex text keeps its intrinsic height';
    is $grow->bh, 184, 'flex button fills the leftover height (200 - 16)';
    is $grow->by, 16,  'flex button sits below the text';
};

# ── 4. fit_h => fill fills the cross axis (here, a row's height) ─────────
subtest 'fit_h fill stretches across a row' => sub {
    my $row = Uji::row(
        padding  => 0,
        spacing  => 0,
        children => [
            Uji::button( label => 'tall', fit_h => 'fill' ),
            Uji::button( label => 'normal' ),
        ],
    );
    $layout->compute( $row, 0, 0, 400, 200 );

    my ( $tall, $normal ) = @{ $row->children };
    is $tall->bh,   200, 'fit_h fill spans the row height';
    is $normal->bh, 26,  'a default leaf still hugs its intrinsic height in a row';
};

# ── 5. min / max clamps on the computed box ──────────────────────────────
subtest 'min/max clamp computed extents' => sub {
    my $col = Uji::column(
        padding  => 0,
        spacing  => 0,
        children => [
            Uji::text( 'wide', fit_w => 'content', min_w => 120 ),    # intrinsic 32 -> clamped up
            Uji::text( 'wide', fit_w => 'content', max_w => 10 ),     # intrinsic 32 -> clamped down
            Uji::button( label => 'grow', flex => 1, max_h => 50 ),   # flex 250 -> capped
        ],
    );
    $layout->compute( $col, 0, 0, 400, 300 );

    my ( $minw, $maxw, $flex ) = @{ $col->children };
    is $minw->bw, 120, 'min_w raises a content-fit width';
    is $maxw->bw, 10,  'max_w caps a content-fit width';
    is $flex->bh, 50,  'max_h caps a flex child';
};

# ── 6. Explicit w/h still means fixed ────────────────────────────────────
subtest 'explicit sizes stay fixed' => sub {
    my $col = Uji::column(
        padding  => 0,
        spacing  => 0,
        children => [ Uji::button( label => 'box', w => 150, h => 40 ) ],
    );
    $layout->compute( $col, 0, 0, 400, 300 );

    my ($btn) = @{ $col->children };
    is $btn->bw, 150, 'explicit w wins';
    is $btn->bh, 40,  'explicit h wins';
};

# ── 7. Constraints propagate up through a container's natural size ───────
subtest 'min_w propagates into the parent natural width' => sub {
    my $col = Uji::column(
        padding  => 0,
        spacing  => 0,
        children => [ Uji::button( label => 'x', min_w => 300 ) ],
    );
    my ( $w, $h ) = $layout->_natural($col);
    cmp_ok $w, '>=', 300, "a child min_w widens the column's natural size (got $w)";
};

# ── 8. min/max now live on every node (Window inherits the same fields) ──
subtest 'constraints are available on all nodes' => sub {
    is Uji::window( min_w => 300, max_w => 800 )->min_w, 300, 'Window min_w (inherited)';
    is Uji::window( max_h => 600 )->max_h,               600, 'Window max_h (inherited)';
    is Uji::text('x')->min_w,                            0,   'leaf defaults to unconstrained';
    is Uji::text('x')->max_w,                            0,   'leaf max defaults to unconstrained';
};

done_testing;
