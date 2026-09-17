use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use blib;
use Test2::V0;
use Uji::Driver::Win32;
use Uji;
use Affix qw[:memory :core :types];
use Acme::Parataxis::Channel;
use Encode qw[decode];
#
skip_all 'Win32 only' unless $^O eq 'MSWin32';

# Widget-queue batch 1: status_text, status_bar, group_box, scroll_view. Real-HWND test mirroring
# t/008: verifies mounting (class/styles), status-bar panes + parts, group-box sibling mounting
# and title-band layout, and the scroll_view viewport, scroll store, and WM_VSCROLL routing.
my $chan = Acme::Parataxis::Channel->new( capacity => 1024 );
my $drv  = Uji::Driver::Win32->new;
$drv->init($chan);
my $st      = Uji::status_text( 'Ready', align => 'center' );
my $sbar    = Uji::status_bar( label => 'ok', panels => [ 'Ready', '3 items' ] );
my $go      = Uji::button( label => 'Go', on_click => { type => 'GO' } );
my $so      = Uji::button( label => 'Stop' );
my $gb      = Uji::group_box( label => 'Actions', children => [ $go, $so ] );
my $content = Uji::column( spacing => 8, children => [ map { Uji::button( label => 'Row ' . $_ ) } 1 .. 30 ], );
my $sv      = Uji::scroll_view( $content, orientation => 'vertical', on_scroll => sub ( $x, $y ) { { type => 'SCROLLED', x => $x, y => $y } } );
my $col     = Uji::column( padding => 8, spacing => 10, children => [ $st, $sbar, $gb, $sv ] );
my $vtree   = Uji::window( id => 'main', title => 't', w => 360, h => 500, child => $col );
$drv->mount($vtree);
my $layout = Uji::Layout->new( driver => $drv );
$layout->compute( $vtree, 0, 0, 360, 500 );
$drv->mount_children($vtree);
my $wrb = $drv->_get_registry_record( $vtree->id );
my $str = $drv->_get_registry_record( $st->id );
my $sbr = $drv->_get_registry_record( $sbar->id );
my $gbr = $drv->_get_registry_record( $gb->id );
my $gor = $drv->_get_registry_record( $go->id );
my $svr = $drv->_get_registry_record( $sv->id );
my $b0r = $drv->_get_registry_record( $content->children->[0]->id );
ok $wrb && $wrb->{hwnd}, 'app window created';
ok $str && $str->{hwnd}, 'status_text has a HWND';
ok $sbr && $sbr->{hwnd}, 'status_bar has a HWND';
ok $gbr && $gbr->{hwnd}, 'group_box has a HWND';
ok $svr && $svr->{hwnd} && $svr->{hwnd} != $wrb->{hwnd}, 'scroll_view has a viewport HWND';

sub class_of {
    my ($hwnd) = @_;
    my $buf = Affix::malloc(128);
    Affix::memcpy( $buf, "\0" x 128, 128 );
    Uji::Driver::Win32::GetClassNameW( $hwnd, $buf, 64 );
    my $cls = decode( 'UTF-16LE', Affix::raw( $buf, 128 ) );
    free($buf);
    $cls =~ s/\x00.*//s;
    return $cls;
}

# ─── status_text: STATIC with the align style baked in at mount ───
is lc class_of( $str->{hwnd} ), 'static', 'status_text is a STATIC control';
ok Uji::Driver::Win32::GetWindowLongW( $str->{hwnd}, -16 ) & 0x0001, 'status_text has SS_CENTER from align';
$drv->set_prop( $st->id, 'label', 'Busy...' );
my $buf = Affix::malloc(128);
Affix::memcpy( $buf, "\0" x 128, 128 );
my $len = Uji::Driver::Win32::SendMessageW( $str->{hwnd}, 0x000E, 0, 0 );              # WM_GETTEXTLENGTH
Uji::Driver::Win32::SendMessageW( $str->{hwnd}, 0x000D, 64, Affix::address($buf) );    # WM_GETTEXT
my $label = decode( 'UTF-16LE', Affix::raw( $buf, $len * 2 ) );
is $label, 'Busy...', 'set_prop label updates a status_text';
free($buf);

# ─── status_bar: panes + parts ───
is lc class_of( $sbr->{hwnd} ),                                    'msctls_statusbar32', 'status_bar is a native statusbar';
is Uji::Driver::Win32::SendMessageW( $sbr->{hwnd}, 0x0406, 0, 0 ), 2,                    'status_bar has two parts';           # SB_GETPARTS
{
    my $l0 = Uji::Driver::Win32::SendMessageW( $sbr->{hwnd}, 0x040C, 0, 0 );    # SB_GETTEXTLENGTH part 0
    my $b  = Affix::malloc( ( $l0 & 0xFFFF ) * 2 + 2 );
    Uji::Driver::Win32::SendMessageW( $sbr->{hwnd}, 0x040D, 0, Affix::address($b) );    # SB_GETTEXT part 0
    is decode( 'UTF-16LE', Affix::raw( $b, ( $l0 & 0xFFFF ) * 2 ) ), 'Ready', 'status_bar pane 0 text';
    free($b);
    my $l1 = Uji::Driver::Win32::SendMessageW( $sbr->{hwnd}, 0x040C, 1, 0 );
    my $b1 = Affix::malloc( ( $l1 & 0xFFFF ) * 2 + 2 );
    Uji::Driver::Win32::SendMessageW( $sbr->{hwnd}, 0x040D, 1, Affix::address($b1) );
    is decode( 'UTF-16LE', Affix::raw( $b1, ( $l1 & 0xFFFF ) * 2 ) ), '3 items', 'status_bar pane 1 text';
    free($b1);
}
$drv->set_prop( $sbar->id, 'panels', [ 'Left', 'Mid', 'Right' ] );
is Uji::Driver::Win32::SendMessageW( $sbr->{hwnd}, 0x0406, 0, 0 ), 3, 'set_prop panels rebuilt three parts';
{
    my $l2 = Uji::Driver::Win32::SendMessageW( $sbr->{hwnd}, 0x040C, 2, 0 );
    my $b0 = Affix::malloc( ( $l2 & 0xFFFF ) * 2 + 2 );
    Uji::Driver::Win32::SendMessageW( $sbr->{hwnd}, 0x040D, 2, Affix::address($b0) );
    is decode( 'UTF-16LE', Affix::raw( $b0, ( $l2 & 0xFFFF ) * 2 ) ), 'Right', 'status_bar pane 2 text after panels round-trip';
    free($b0);
}

# Panes are proportional to the node width, so a move_widget resize must re-part immediately
# (SB_GETPARTS reads the stored part edges back).
$sbar->set_bounds( $sbar->bx, $sbar->by, 600, $sbar->bh );
$drv->move_widget( $sbar->id, $sbar->bx, $sbar->by, 600, $sbar->bh );
{
    my $p     = Affix::malloc( 3 * 4 );
    my $n     = Uji::Driver::Win32::SendMessageW( $sbr->{hwnd}, 0x0406, 3, Affix::address($p) );
    my @edges = unpack 'l<3', Affix::raw( $p, 12 );
    free($p);
    is $n,        3,               'status_bar reports three parts after resize';
    is $edges[0], int( 600 / 3 ),  'status_bar repart edge 1 tracks the new width';
    is $edges[1], int( 1200 / 3 ), 'status_bar repart edge 2 tracks the new width';
}

# ─── group_box: BUTTON frame + sibling-mounted children in the title band ───
is lc class_of( $gbr->{hwnd} ), 'button', 'group_box is a BUTTON control';
ok Uji::Driver::Win32::GetWindowLongW( $gbr->{hwnd}, -16 ) & 0x0007, 'group_box has BS_GROUPBOX style';
ok $go->by >= $gb->by + 16,                                          'group_box content starts inside the title band';

# If the Go button were parented under the BS_GROUPBOX it would have no functional parent routing
# (the groupbox wndproc swallows grandchildren WM_COMMAND). A BN_CLICKED reaching our channel
# proves the driver mounted it as a SIBLING of the app window.
$chan->get() while $chan->size;

# no warnings guard: SendMessageW re-enters the Affix wndproc bridge (poll_events quirk).
{
    no warnings 'uninitialized';
    Uji::Driver::Win32::SendMessageW( $gor->{hwnd}, 0x00F5, 0, 0 );    # BM_CLICKED -> BN_CLICKED to the parent
}
my $gmsg = $chan->size ? $chan->get : undef;
ok $gmsg, 'group_box button click reached the app wndproc';
is $gmsg && $gmsg->{type}, 'GO', 'group_box child notifications route to the model';

# ─── scroll_view: viewport class, shared store, positioning ───
is class_of( $svr->{hwnd} ) =~ /^UjiViewportClass/, 1, 'scroll_view mounts the dedicated viewport class';
ok $b0r && $b0r->{scroll} && $b0r->{scroll} == $svr->{scroll}, 'content shares the scroll_view scroll store';
my $win_rect = Affix::malloc(16);
Uji::Driver::Win32::GetWindowRect( $svr->{hwnd}, $win_rect );
my ( $sv_left, $sv_top ) = unpack 'l<2', Affix::raw( $win_rect, 8 );

# The test mounts via mount_children directly (no App::_move_all), so drive the first placement
# like App would: move the viewport, grow its scrollbars, and offset the content.
$drv->move_widget( $sv->id, $sv->bx, $sv->by, $sv->bw, $sv->bh );
ok $svr->{aux_v},  'vertical scrollbar created when the content overflows';
ok !$svr->{aux_h}, 'no horizontal scrollbar for a vertical scroll_view';
is $svr->{scroll}{oy}, 0, 'the store starts unscrolled';
{
    my $si = Affix::malloc(28);                                                       # SCROLLINFO: cbSize fMask nMin nMax nPage nPos nTrackPos
    memcpy( $si, pack( 'l<7', 28, 0x0001 | 0x0002 | 0x0004, 0, 0, 0, 0, 0 ), 28 );    # SIF_RANGE|SIF_PAGE|SIF_POS
    Uji::Driver::Win32::GetScrollInfo( $svr->{aux_v}, 2, $si );
    my ( undef, undef, undef, undef, $page, undef ) = unpack 'l<7', Affix::raw( $si, 28 );
    free($si);
    is $page, $sv->bh, 'scrollbar SIF_PAGE set to the viewport extent (sized, grabbable thumb)';
}
{
    my $b_rect = Affix::malloc(16);
    Uji::Driver::Win32::GetWindowRect( $b0r->{hwnd}, $b_rect );
    my ( $b_left, $b_top ) = unpack 'l<2', Affix::raw( $b_rect, 8 );
    free($b_rect);
    is $b_top - $sv_top,   $content->children->[0]->by - $sv->by, 'content parked at its layout offset';
    is $b_left - $sv_left, $content->children->[0]->bx - $sv->bx, 'content parked at its layout x-offset';
}

# Thumb drag: WM_VSCROLL wParam = (SB_THUMBTRACK (5) in the low word, thumb position (40) in the high word).
$chan->get() while $chan->size;
Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x0115, ( 40 << 16 ) | 5, $svr->{aux_v} );
my $msg = $chan->size ? $chan->get : undef;
ok $msg, 'scrollbar thumb produced a channel message';
is $msg && $msg->{type}, 'SCROLLED', 'on_scroll message type';
is $msg && $msg->{y},    40,         'on_scroll received the thumb position';
is $svr->{scroll}{oy}, 40, 'the shared store offset moved';
{
    my $b_rect = Affix::malloc(16);
    Uji::Driver::Win32::GetWindowRect( $b0r->{hwnd}, $b_rect );
    my ( $b_left, $b_top ) = unpack 'l<2', Affix::raw( $b_rect, 8 );
    free($b_rect);
    is $b_top - $sv_top, $content->children->[0]->by - $sv->by - 40, 'content shifted up by the scroll offset';
}
is $drv->_scrollbar_read_pos( $svr->{aux_v} ), 40, 'scrollbar thumb tracks the store';

# Offsets survive a re-layout move, and set_prop resets them.
$drv->move_widget( $sv->id, $sv->bx, $sv->by, $sv->bw, $sv->bh );
is $svr->{scroll}{oy}, 40, 'scroll offset survives a re-layout';
$drv->set_prop( $sv->id, 'scroll_x', 10 );
is $svr->{scroll}{ox}, 0,  'set_prop scroll_x clamps to the vertical view range';
is $svr->{scroll}{oy}, 40, 'set_prop scroll_x left the y offset alone';
$drv->set_prop( $sv->id, 'scroll_y', 0 );
is $drv->_scrollbar_read_pos( $svr->{aux_v} ), 0, 'set_prop scroll_y reset the thumb';

# ─── mouse wheel: WM_MOUSEWHEEL must scroll the viewport under the cursor ───
# The wheel arrives at the focused top-level window; the driver routes it to the scroll_view
# whose viewport/scrollbar contains the cursor point (lParam). oy starts at 0.
{
    my $r = Affix::malloc(16);
    Uji::Driver::Win32::GetWindowRect( $svr->{hwnd}, $r );
    my ( $l, $t, $rr, $b ) = unpack 'l<4', Affix::raw( $r, 16 );
    free($r);
    my ( $cx, $cy ) = ( int( ( $l + $rr ) / 2 ), int( ( $t + $b ) / 2 ) );
    my $lparam = ( $cy << 16 ) | $cx & 0xFFFF;    # WM_MOUSEWHEEL cursor screen coords

    # -120 (wheel down) -> SB_LINEDOWN (+16). HIWORD of wParam = delta (signed).
    $chan->get() while $chan->size;
    Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x020A, 0xFF880000, $lparam );
    my $wmsg = $chan->size ? $chan->get : undef;
    ok $wmsg, 'mouse wheel produced a channel message';
    is $wmsg && $wmsg->{type}, 'SCROLLED', 'mouse wheel on_scroll type';
    is $wmsg && $wmsg->{y},    16,         'mouse wheel advanced the offset by one notch';
    is $svr->{scroll}{oy}, 16, 'mouse wheel moved the shared store';

    # +120 (wheel up) -> SB_LINEUP (back to 0).
    $chan->get() while $chan->size;
    Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x020A, 0x00780000, $lparam );
    my $wmsg2 = $chan->size ? $chan->get : undef;
    is $svr->{scroll}{oy},    0, 'mouse wheel up restored the offset';
    is $wmsg2 && $wmsg2->{y}, 0, 'mouse wheel up reported y=0';
}

# Close the test window unobtrusively.
Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE -> WM_DESTROY
free($win_rect);
free($buf);
#
done_testing;
