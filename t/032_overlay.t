use v5.40;
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use blib;
use Test2::V0;
use MockDriver;
use Uji;
use Uji::Layout;

my $layout = Uji::Layout->new( driver => MockDriver->new );

# Intrinsic box: the largest layer + padding
subtest 'overlay intrinsic is the largest layer box' => sub {
    my $ov = Uji::overlay(
        children => [
            Uji::button( label => 'small', w => 80,  h => 24 ),
            Uji::button( label => 'big',   w => 260, h => 120 ),
        ],
    );
    is [ $layout->_intrinsic($ov) ], [ 260, 120 ], 'intrinsic (260, 120) = max layer';

    my $padded = Uji::overlay( padding => 10, children => [ Uji::button( label => 'x', w => 40, h => 30 ) ] );
    is [ $layout->_intrinsic($padded) ], [ 60, 50 ], 'padding 10 bumps both axes';
};

# Layout: layers all share the same plane
subtest 'layers stack in the same box and align within it' => sub {
    my $ov = Uji::overlay(
        padding  => 8,
        children => [
            Uji::button( label => 'full', fit => 'fill' ),
            Uji::button( label => 'dot',  fit => 'content', align_w => 'end', align_h => 'end' ),
        ],
    );
    $layout->compute( $ov, 10, 20, 400, 300 );

    my @l = @{ $ov->children };
    is $l[0]->bx, 18,  'full-width layer at inner x (10 + 8)';
    is $l[0]->by, 28,  'full-height layer at inner y';
    is $l[0]->bw, 400 - 16, 'full layer spans the inner box width';
    is $l[0]->bh, 300 - 16, 'full layer spans the inner box height';

    ok $l[1]->bw < $l[0]->bw, 'content-fit layer shrinks to its label';
    is $l[1]->bx + $l[1]->bw, 402, "end-aligned layer's right edge meets the inner right (x+w-pad)";
    is $l[1]->by + $l[1]->bh, 312, "end-aligned layer's bottom edge meets the inner bottom";
};

# Container layers fill, leaves keep natural height
subtest 'a column layer fills the overlay box; a leaf keeps its height' => sub {
    my $ov = Uji::overlay(
        children => [
            Uji::column(
                spacing => 6,
                children => [ Uji::button( label => 'a' ), Uji::button( label => 'b' ) ],
            ),
            Uji::button( label => 'badge', fit => 'content', align_w => 'center', align_h => 'center' ),
        ],
    );
    $layout->compute( $ov, 0, 0, 300, 200 );

    my @l = @{ $ov->children };
    is $l[0]->bw, 300, 'column layer fills the width';
    is $l[0]->bh, 200, 'column layer fills the height';
    is $l[1]->bh, $l[1]->h ? $l[1]->h : ( $layout->_intrinsic( $l[1] ) )[1], 'badge layer keeps its natural height';
    is $l[1]->bx + ( $l[1]->bw / 2 ), 150, 'center-aligned badge is horizontally centered';
    is $l[1]->by + ( $l[1]->bh / 2 ), 100, 'center-aligned badge is vertically centered';
};

# Real driver: array order IS stacking (later layers on top)
subtest 'the Win32 driver stacks later layers on top' => sub {
    skip_all 'Win32 only' unless $^O eq 'MSWin32';
    use Uji::Driver::Win32;
    use Acme::Parataxis::Channel;

    my $chan = Acme::Parataxis::Channel->new( capacity => 1024 );
    my $drv  = Uji::Driver::Win32->new;
    $drv->init($chan);
    my $ov = Uji::overlay(
        children => [
            Uji::button( id => 71, label => 'base layer' ),
            Uji::button( id => 72, label => 'badge layer' ),
        ],
    );
    my $win = Uji::window( id => 'o', title => 't', w => 260, h => 180, child => $ov );
    $drv->mount($win);
    my $layout = Uji::Layout->new( driver => $drv );
    $layout->compute( $win, 0, 0, 260, 180 );
    $drv->mount_children($win);
    $chan->get() while $chan->size;

    # Win32 puts the FIRST-created sibling on top; an overlay must raise layers in array order
    # so the LAST one is frontmost. GW_CHILD returns the topmost child.
    my @ids;
    my $hw = Uji::Driver::Win32::GetWindow( $drv->_get_registry_record('o')->{hwnd}, 5 );
    while ( $hw ) {
        push @ids, Uji::Driver::Win32::GetWindowLongW( $hw, -12 );
        $hw = Uji::Driver::Win32::GetWindow( $hw, 2 );
    }
    is \@ids, [ 72, 71 ], 'z-order from the top: badge layer (72) then base layer (71)';

    # Reconcile appends a third layer: the driver must raise it above the existing layers.
    my $recon = Uji::Reconciler->new;
    my $ov2   = Uji::overlay(
        children => [
            Uji::button( id => 71, label => 'base layer' ),
            Uji::button( id => 72, label => 'badge layer' ),
            Uji::button( id => 73, label => 'top layer' ),
        ],
    );
    my $win2 = Uji::window( id => 'o', title => 't', w => 260, h => 180, child => $ov2 );
    $recon->patch_windows( [$win], [$win2], $drv );
    my @ids2;
    my $h2 = Uji::Driver::Win32::GetWindow( $drv->_get_registry_record('o')->{hwnd}, 5 );
    while ( $h2 ) {
        push @ids2, Uji::Driver::Win32::GetWindowLongW( $h2, -12 );
        $h2 = Uji::Driver::Win32::GetWindow( $h2, 2 );
    }
    is \@ids2, [ 73, 72, 71 ], 'after reconcile the appended layer (73) sits on top';

    Uji::Driver::Win32::SendMessageW( $drv->_get_registry_record('o')->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
};

done_testing;
