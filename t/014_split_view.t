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
use Encode qw[decode];
#
skip_all 'Win32 only' unless $^O eq 'MSWin32';

# Widget-queue batch 2 (part 1): SplitView. Real-HWND test mirroring t/012: verifies mounting
# (panes as app-window siblings, no own HWND), layout (divider gap on the main axis), the drag
# strip (UjiDividerClass placement + orientation swap), the drag event (clamped on_divider via
# capture/WM_MOUSEMOVE), and set_prop routing through the reconciler.
my $chan = Acme::Parataxis::Channel->new( capacity => 1024 );
my $drv  = Uji::Driver::Win32->new;
$drv->init($chan);
my $pa = Uji::column( padding => 4, spacing => 4, children => [ Uji::button( label => 'A1' ), Uji::button( label => 'A2' ) ] );
my $pb = Uji::column( padding => 4, spacing => 4, children => [ Uji::button( label => 'B1' ), Uji::button( label => 'B2' ) ] );
my $sv = Uji::split_view(
    $pa, $pb,
    orientation => 'vertical',
    divider     => 120,
    divider_w   => 6,
    min_a       => 40,
    min_b       => 40,
    on_divider  => sub ($pos) { { type => 'DIV', pos => $pos } },
);
my $col   = Uji::column( padding => 8, children => [$sv] );
my $vtree = Uji::window( id => 'main', title => 't', w => 320, h => 420, child => $col );
$drv->mount($vtree);
my $layout = Uji::Layout->new( driver => $drv );
$layout->compute( $vtree, 0, 0, 320, 420 );
$drv->mount_children($vtree);
my $wrb = $drv->_get_registry_record( $vtree->id );
my $svr = $drv->_get_registry_record( $sv->id );
ok $svr && !$svr->{hwnd}, 'split_view has a registry record but no own HWND';
my $ar = $drv->_get_registry_record( $pa->children->[0]->id );
my $br = $drv->_get_registry_record( $pb->children->[0]->id );
is $ar->{parent_hwnd}, $wrb->{hwnd}, 'pane A content parented to the app window (sibling mount)';
is $br->{parent_hwnd}, $wrb->{hwnd}, 'pane B content parented to the app window (sibling mount)';

# App-like placement: move_widget on every node, which also creates + places the divider strip.
my $move_all;
$move_all = sub {
    my ($n) = @_;
    $drv->move_widget( $n->id, $n->bx, $n->by, $n->bw, $n->bh ) unless $n->type eq 'window';
    return if $n->type eq 'scroll_view';
    $move_all->($_) for @{ $n->children };
};
$move_all->($vtree);
$layout->compute( $vtree, 0, 0, 320, 420 );
$move_all->($vtree);

#  layout: pane A gets [0..divider], a 6px gap, then pane B
my ( $adiv, $avert, $adw ) = $drv->split_position( $sv, $sv->bw, $sv->bh );
is $adw,    6,                 'split resolves the divider width';
is $avert,  1,                 'vertical split resolved as vertical';
is $adiv,   120,               'split resolves the explicit divider position';
is $pa->by, $sv->by,           'pane A sits at the split top';
is $pa->bh, 120,               'pane A extends to the divider';
is $pb->by, $sv->by + 120 + 6, 'pane B starts after the divider gap';
is $pb->bh, $sv->bh - 120 - 6, 'pane B takes the remainder';
ok $pa->bw == $pb->bw && $pa->bw == $sv->bw, 'panes span the full cross axis';

# The strip is a child window of the app window with the dedicated class name.
my $cls = '';
{
    my $buf = Affix::malloc(128);
    Affix::memcpy( $buf, "\0" x 128, 128 );
    Uji::Driver::Win32::GetClassNameW( $svr->{aux}, $buf, 64 );
    $cls = decode( 'UTF-16LE', Affix::raw( $buf, 128 ) );
    free($buf);
    $cls =~ s/\x00.*//s;
}
is $cls =~ /^UjiDividerClass/, 1, 'the divider mounts the dedicated strip class';
ok $svr->{aux} && $svr->{aux} != $wrb->{hwnd}, 'divider is a real child HWND';
is Uji::Driver::Win32::GetClassLongPtrW( $svr->{aux}, -10 ), 18, 'divider face is a valid visible brush (COLOR_BTNSHADOW + 1)';   # GCLP_HBRBACKGROUND

sub client_origin_y {
    my ($hwnd) = @_;
    my $p = Affix::malloc(8);
    Affix::memcpy( $p, "\0" x 8, 8 );    # POINT { x = 0, y = 0 }
    Uji::Driver::Win32::ClientToScreen( $hwnd, $p );
    my ( undef, $oy ) = unpack 'l<2', Affix::raw( $p, 8 );
    free($p);
    return $oy;
}

sub window_top {
    my ($hwnd) = @_;
    my $r = Affix::malloc(16);
    Uji::Driver::Win32::GetWindowRect( $hwnd, $r );
    my ( undef, $top ) = unpack 'l<2', Affix::raw( $r, 8 );
    free($r);
    return $top;
}
my $oy = client_origin_y( $wrb->{hwnd} );
is window_top( $svr->{aux} ) - $oy, $sv->by + 120, 'divider strip parked on the layout divider line';

#  set_prop: divider + orientation route through the driver
$drv->set_prop( $sv->id, 'divider', 150 );
is $svr->{divider},                 150,           'set_prop divider updates the record';
is window_top( $svr->{aux} ) - $oy, $sv->by + 150, 'set_prop divider moves the strip';
$drv->set_prop( $sv->id, 'orientation', 'horizontal' );
{
    my $r = Affix::malloc(16);
    Uji::Driver::Win32::GetWindowRect( $svr->{aux}, $r );
    my ( $l, $t, $rr, $b ) = unpack 'l<4', Affix::raw( $r, 16 );
    free($r);
    is $b - $t,  $sv->bh, 'horizontal split re-orients the strip (tall bar)';
    is $rr - $l, 6,       'horizontal split strip keeps the divider width';
}
$drv->set_prop( $sv->id, 'orientation', 'vertical' );
$drv->set_prop( $sv->id, 'divider',     120 );
is window_top( $svr->{aux} ) - $oy, $sv->by + 120, 'orientation swap back re-parks the strip';

#  split_position clamping is deterministic for the range edges
{
    my $tiny = Uji::split_view( Uji::row( children => [] ), Uji::row( children => [] ), orientation => 'vertical', divider => 5, min_a => 40,
        min_b => 40 );
    my ( $d1, undef, undef ) = $drv->split_position( $tiny, 300, 200 );
    is $d1, 40, 'divider below min_a clamps up to min_a';
    my $big = Uji::split_view(
        Uji::row( children => [] ), Uji::row( children => [] ),
        orientation => 'vertical',
        divider     => 500,
        min_a       => 40,
        min_b       => 40
    );
    my ( $d2, undef, undef ) = $drv->split_position( $big, 300, 200 );
    is $d2, 154, 'divider over the track clamps down (200 - 6 - 40)';
}

#  drag: capture + WM_MOUSEMOVE dispatch on_divider inside the clamp range
$chan->get() while $chan->size;
Uji::Driver::Win32::SendMessageW( $svr->{aux}, 0x0201, 0, 0 );    # WM_LBUTTONDOWN
Uji::Driver::Win32::SendMessageW( $svr->{aux}, 0x0200, 0, 0 );    # WM_MOUSEMOVE
Uji::Driver::Win32::SendMessageW( $svr->{aux}, 0x0202, 0, 0 );    # WM_LBUTTONUP
my $dmsg = $chan->size ? $chan->get : undef;
ok $dmsg, 'divider drag produced a channel message';
is $dmsg && $dmsg->{type}, 'DIV', 'on_divider message type';
my $pos = $svr->{divider};
ok defined $pos, 'drag stored a divider position on the record';
my $max_div = $sv->bh - 6 - 40;
ok $pos >= 40 && $pos <= $max_div, 'drag position clamped to the pane min/max';
is $dmsg && $dmsg->{pos}, $pos, 'on_divider received the live clamped position';
is window_top( $svr->{aux} ) - $oy, $sv->by + $pos, 'strip follows the drag with no render';

#  reconciler: a divider prop change routes to set_prop with the new id
{
    my $recon = Uji::Reconciler->new;
    my $old   = Uji::split_view( Uji::column( children => [] ), Uji::column( children => [] ), orientation => 'vertical', divider => 120 );
    $old->set_id( $sv->id );
    $layout->compute( $old, $sv->bx, $sv->by, $sv->bw, $sv->bh );    # runtime order: render computes bounds first
    my $new = Uji::split_view( Uji::column( children => [] ), Uji::column( children => [] ), orientation => 'vertical', divider => 180 );
    $layout->compute( $new, $sv->bx, $sv->by, $sv->bw, $sv->bh );
    $recon->patch( $old, $new, $drv );
    is $svr->{divider},                 180,           'reconciler divider diff routes to set_prop';
    is window_top( $svr->{aux} ) - $oy, $sv->by + 180, 'reconciled divider re-parks the strip';
}

#  window resize rescales the divider so the relative position survives
{
    my $cur    = $svr->{node};                                       # the reconciled, current model split node
    my $ratio0 = $svr->{div_ratio};
    ok defined $ratio0, 'layout records the divider ratio for resize tracking';
    is $cur->divider, 180, 'current model node carries the reconciled divider';

    # WM_SIZE path: the split track grows 404 -> 824 on the SAME node.
    $cur->set_bounds( $cur->bx, $cur->by, $cur->bw, 824 );
    $layout->compute( $cur, $cur->bx, $cur->by, $cur->bw, 824 );
    my $exp = int( $ratio0 * ( 824 - 6 ) + 0.5 );
    is $svr->{divider}, $exp, 'divider scaled proportionally on window resize';
    $move_all->($cur);
    is window_top( $svr->{aux} ) - $oy, $cur->by + $exp, 'strip re-parked at the scaled position';
}
Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
#
done_testing;
