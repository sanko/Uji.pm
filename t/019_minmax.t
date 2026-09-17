use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use blib;
use Test2::V0;
use Uji::Driver::Win32;
use Uji;
use Uji::Layout;
use Uji::Reconciler;
use Affix qw[:memory :core :types];
use Acme::Parataxis::Channel;
use Encode qw[decode encode];
#
skip_all 'Win32 only' unless $^O eq 'MSWin32';
my $WM_GETMINMAXINFO = 0x0024;
my $WM_CLOSE         = 0x0010;
my $MINMAXINFO_SIZE  = 40;                                                  # 5 POINTs x 8 bytes
my $chan             = Acme::Parataxis::Channel->new( capacity => 1024 );
my $drv              = Uji::Driver::Win32->new;
$drv->init($chan);

sub send_minmax_info ( $hwnd, $min_track = undef, $max_track = undef ) {
    my $ptr = malloc($MINMAXINFO_SIZE);
    my $mmi = cast( $ptr, Uji::Driver::Win32::MINMAXINFO() );
    $mmi->{ptMinTrackSize}{x} = $min_track ? $min_track->[0] : 50;
    $mmi->{ptMinTrackSize}{y} = $min_track ? $min_track->[1] : 50;
    $mmi->{ptMaxTrackSize}{x} = $max_track ? $max_track->[0] : 20000;
    $mmi->{ptMaxTrackSize}{y} = $max_track ? $max_track->[1] : 20000;
    Uji::Driver::Win32::SendMessageW( $hwnd, $WM_GETMINMAXINFO, 0, Affix::address($ptr) );
    my @int = unpack 'l<10', Affix::raw( $ptr, $MINMAXINFO_SIZE );
    free($ptr);
    return ( $int[6], $int[7], $int[8], $int[9] );    # (min_x, min_y, max_x, max_y) in WINDOW coords
}

# ── 1. Constraints applied at mount clamp the drag track ─────────────────
{
    my $col = Uji::column( padding => 8, children => [ Uji::text('hi') ] );
    my $vtree
        = Uji::window( id => 'mm_mount', title => 'MM', w => 600, h => 400, min_w => 300, min_h => 200, max_w => 800, max_h => 600, child => $col );
    $drv->mount($vtree);
    my $rec  = $drv->_get_registry_record( $vtree->id );
    my @vals = send_minmax_info( $rec->{hwnd} );
    ok $vals[0] > 300,   "mount min_w clamps track x (got $vals[0] > 300)";
    ok $vals[1] > 200,   "mount min_h clamps track y (got $vals[1] > 200)";
    ok $vals[2] < 20000, "mount max_w clamps track x (got $vals[2] < 20000)";
    ok $vals[3] < 20000, "mount max_h clamps track y (got $vals[3] < 20000)";

    # The window must NOT maximize when a constraint is defined.
    $drv->set_prop( $vtree->id, 'maximized', 1 );
    ok !Uji::Driver::Win32::IsZoomed( $rec->{hwnd} ), 'maximize refused when constrained';
    Uji::Driver::Win32::SendMessageW( $rec->{hwnd}, $WM_CLOSE, 0, 0 );
}

# ── 2. REGRESSION: constraints added AFTER mount must clamp live drags ───
{
    my $col   = Uji::column( padding => 8, children => [ Uji::text('hi') ] );
    my $vtree = Uji::window( id => 'mm_rerender', title => 'MM2', w => 600, h => 400, child => $col );
    $drv->mount($vtree);
    my $layout = Uji::Layout->new( driver => $drv );
    $layout->compute( $vtree, 0, 0, 600, 400 );
    $drv->mount_children($vtree);
    my $rec = $drv->_get_registry_record( $vtree->id );

    # Before the constraint arrives, the track is unclamped.
    my ( $min_x, $min_y ) = send_minmax_info( $rec->{hwnd}, [ 50, 50 ], [ 20000, 20000 ] );
    ok $min_x == 50, 'no constraint at mount -> track unclamped initially';

    # Re-render adds min/max. The reconciler must push them into surfaces.node too.
    my $new_win = Uji::window( id => 'mm_rerender', title => 'MM2', w => 600, h => 400, min_w => 300, min_h => 200, max_w => 800, max_h => 600,
        child => $col );
    $layout->compute( $new_win, 0, 0, 600, 400 );
    my $recon = Uji::Reconciler->new;
    $recon->patch( $vtree, $new_win, $drv );
    my @vals = send_minmax_info( $rec->{hwnd} );
    ok $vals[0] > 300,                                      "re-rendered min_w clamps track x (got $vals[0] > 300)";
    ok $vals[2] < 20000,                                    "re-rendered max_w clamps track x (got $vals[2] < 20000)";
    ok $drv->surfaces->{'mm_rerender'}{node}->min_w == 300, 'surfaces node refreshed by reconcile (min_w=300)';
    Uji::Driver::Win32::SendMessageW( $rec->{hwnd}, $WM_CLOSE, 0, 0 );
}

# ── 3. Constraint changes live are reflected on the next drag ────────────
{
    my $col = Uji::column( padding => 8, children => [ Uji::text('hi') ] );
    my $vtree
        = Uji::window( id => 'mm_change', title => 'MM3', w => 600, h => 400, min_w => 300, min_h => 200, max_w => 800, max_h => 600, child => $col );
    $drv->mount($vtree);
    my $layout = Uji::Layout->new( driver => $drv );
    $layout->compute( $vtree, 0, 0, 600, 400 );
    $drv->mount_children($vtree);
    my $rec     = $drv->_get_registry_record( $vtree->id );
    my @v0      = send_minmax_info( $rec->{hwnd} );
    my $old_min = $v0[0];
    my $new_win
        = Uji::window( id => 'mm_change', title => 'MM3', w => 600, h => 400, min_w => 500, min_h => 400, max_w => 800, max_h => 600, child => $col );
    $layout->compute( $new_win, 0, 0, 600, 400 );
    my $recon = Uji::Reconciler->new;
    $recon->patch( $vtree, $new_win, $drv );
    my @v1 = send_minmax_info( $rec->{hwnd} );
    ok $v1[0] > $old_min, "raised min_w takes effect live ($v1[0] > $old_min)";
    Uji::Driver::Win32::SendMessageW( $rec->{hwnd}, $WM_CLOSE, 0, 0 );
}

# ── 4. No constraints -> maximize still allowed ──────────────────────────
{
    my $col   = Uji::column( padding => 8, children => [ Uji::text('hi') ] );
    my $vtree = Uji::window( id => 'mm_free', title => 'MM4', w => 600, h => 400, maximized => 1, child => $col );
    $drv->mount($vtree);
    my $rec = $drv->_get_registry_record( $vtree->id );
    ok Uji::Driver::Win32::IsZoomed( $rec->{hwnd} ), 'maximize allowed without constraints';
    Uji::Driver::Win32::SendMessageW( $rec->{hwnd}, $WM_CLOSE, 0, 0 );
}

# ── 5. Regression check: maximized + constraints at mount stays restored ─
{
    my $col   = Uji::column( padding => 8, children => [ Uji::text('hi') ] );
    my $vtree = Uji::window( id => 'mm_z', title => 'MM5', w => 600, h => 400, maximized => 1, min_w => 300, min_h => 200, child => $col );
    $drv->mount($vtree);
    my $rec = $drv->_get_registry_record( $vtree->id );
    ok !Uji::Driver::Win32::IsZoomed( $rec->{hwnd} ), 'mount with maximized+constraint stays unmaximized';
    Uji::Driver::Win32::SendMessageW( $rec->{hwnd}, $WM_CLOSE, 0, 0 );
}
#
done_testing;
