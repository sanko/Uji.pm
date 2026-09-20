use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use blib;
use Test2::V0;
use Uji::Driver::Win32;
use Uji;
use Uji::Layout;
use Acme::Parataxis::Channel;
use Affix qw[:memory :core :types];
#
skip_all 'Win32 only' unless $^O eq 'MSWin32';

# Owner-drawn dark checkboxes/radios/toggles (this session's dark-mode follow-up): in a dark scheme the
# driver mounts these BUTTON controls with BS_OWNERDRAW so the box/circle, the check mark/dot, and the
# label are painted from the dark palette via WM_DRAWITEM (the classic renderer paints a white box +
# black label and ignores WM_CTLCOLORBTN). This test: (1) the owner-draw style is applied in dark and
# NOT in light, (2) a WM_PAINT-triggered repaint shows dark panel + accent mark + light label pixels,
# (3) the mark follows a click and set_prop('value') live. NOTE: an offline InvalidateRect + UpdateWindow
# chain does NOT drive the button's WM_DRAWITEM (probed: zero messages), so paint must be forced with a
# direct WM_PAINT SendMessageW on the control; the button then re-sends WM_DRAWITEM to its parent, whose
# wndproc is the driver's _ctrl_msg. BM_GETCHECK/SETCHECK are INERT on BS_OWNERDRAW buttons, which is why
# the check state is mirrored in the registry record and asserted there.

my $PANEL  = 0x00302D2D;    # #2D2D30 as COLORREF (0x00BBGGRR)
my $ACCENT = 0x00FFA85C;    # #5CA8FF
my $BS_OWNERDRAW = 0x000B;

sub pixel ($h, $x, $y) {
    my $dc = Uji::Driver::Win32::GetDC($h);
    my $c  = Uji::Driver::Win32::GetPixel( $dc, $x, $y );
    Uji::Driver::Win32::ReleaseDC( $h, $dc );
    return $c;
}

# Count pixels of an exact colour INSIDE the 13px box/circle of a check-type control's own DC. Box
# geometry is control-relative: left = 3, top = (bh-13)/2 (both +1 while pressed, never pressed here).
sub box_count ($hwnd, $by, $color) {
    my $dc = Uji::Driver::Win32::GetDC($hwnd);
    my $n  = 0;
    for my $y ( $by .. $by + 12 ) {
        for my $x ( 3 .. 15 ) {
            $n++ if Uji::Driver::Win32::GetPixel( $dc, $x, $y ) == $color;
        }
    }
    Uji::Driver::Win32::ReleaseDC( $hwnd, $dc );
    return $n;
}

# Bright label pixels: sample the label band right of the box and count pixels whose RGB sum is clearly
# above the dark panel (a light label has many; the old black-on-white text had none).
sub bright_count ($hwnd, $by) {
    my $dc = Uji::Driver::Win32::GetDC($hwnd);
    my $n  = 0;
    for my $x ( 21 .. 80 ) {
        my $c = Uji::Driver::Win32::GetPixel( $dc, $x, $by + 6 );
        next if $c == 0xFFFFFFFF;    # CLR_INVALID (GetPixel failure) - not a real colour
        my ( $b, $g, $r ) = ( ( $c >> 16 ) & 0xFF, ( $c >> 8 ) & 0xFF, $c & 0xFF );
        $n++ if $r + $g + $b > 380;
    }
    Uji::Driver::Win32::ReleaseDC( $hwnd, $dc );
    return $n;
}

sub box_top ($rec) { int( ( ( $rec->{node}->bh // 20 ) - 13 ) / 2 ) }

my $chan = Acme::Parataxis::Channel->new( capacity => 1024 );
my $drv  = Uji::Driver::Win32->new( dark_mode => 1 );
$drv->init($chan);

# Force the owner-draw render of a control: WM_PAINT is sent straight to the button (SendMessageW eases
# WM_DRAWITEM to the app window synchronously), then a poll lets the message pump run to completion.
my $paint;
$paint = sub {
    my ($h) = @_;
    Uji::Driver::Win32::SendMessageW( $h, 0x000F, 0, 0 );    # WM_PAINT
    $drv->poll_events;
};

my $rg = Uji::radio_group(
    id        => 'rgrp',
    value     => 'b',
    on_select => sub { undef },
    options   => [ { value => 'a', label => 'A' }, { value => 'b', label => 'B' } ],
);
my $col   = Uji::column(
    padding => 6, spacing => 4,
    children => [
        Uji::checkbox( id => 'cb1', label => 'Check me', checked => 1, on_toggle => sub { undef } ),
        $rg,
        Uji::toggle_button( id => 'tg1', label => 'Toggle', on_toggle => sub { undef } ),
    ]
);
my $vtree = Uji::window( id => 'main', title => 't', w => 220, h => 170, child => $col );
$drv->mount($vtree);
my $layout = Uji::Layout->new( driver => $drv );
$layout->compute( $vtree, 0, 0, 220, 170 );
$drv->mount_children($vtree);

my $move_all;
$move_all = sub {
    my ($n) = @_;
    $drv->move_widget( $n->id, $n->bx, $n->by, $n->bw, $n->bh ) unless $n->type eq 'window';
    return if $n->type eq 'scroll_view';
    $move_all->($_) for @{ $n->children };
};
$move_all->($vtree);
$layout->compute( $vtree, 0, 0, 220, 170 );
$move_all->($vtree);

my $cb = $drv->_get_registry_record('cb1');
my $tg = $drv->_get_registry_record('tg1');
ok $cb && $cb->{hwnd} && $tg && $tg->{hwnd}, 'dark mount: checkbox + toggle_button have HWNDs';
my $ra = $drv->_get_registry_record( $rg->children->[0]->id );
my $rb = $drv->_get_registry_record( $rg->children->[1]->id );
ok $ra && $ra->{hwnd} && $rb && $rb->{hwnd}, 'radios mount as native BUTTON children';

my $cb_style = Uji::Driver::Win32::GetWindowLongW( $cb->{hwnd}, -16 );
my $ra_style = Uji::Driver::Win32::GetWindowLongW( $ra->{hwnd}, -16 );
is( $cb_style & $BS_OWNERDRAW, $BS_OWNERDRAW, 'dark checkbox mounts BS_OWNERDRAW' );
is( $ra_style & $BS_OWNERDRAW, $BS_OWNERDRAW, 'dark radio mounts BS_OWNERDRAW' );
is( Uji::Driver::Win32::GetWindowLongW( $tg->{hwnd}, -16 ) & $BS_OWNERDRAW, $BS_OWNERDRAW, 'dark toggle_button mounts BS_OWNERDRAW' );

# --- checkbox: dark face + accent check + light label; toggling follows BM_CLICK ---
my $cby = box_top($cb);
$paint->( $cb->{hwnd} );
is pixel( $cb->{hwnd}, 9, $cby + 6 ), $PANEL, 'checked checkbox shows the dark panel in the box';
cmp_ok bright_count( $cb->{hwnd}, $cby ), '>', 5, 'checkbox label is drawn light (not black text on white)';
cmp_ok box_count( $cb->{hwnd}, $cby, $ACCENT ), '>', 0, 'checked checkbox paints the accent check mark';
cmp_ok box_count( $cb->{hwnd}, $cby, $PANEL ),  '>', 25, 'checkbox box keeps its dark face alongside the mark';

# BM_CLICK behaves like a real click: fires BN_CLICKED, which toggles the driver's registry flag for
# owner-drawn dark checks (BM_GETCHECK is inert on BS_OWNERDRAW). The accent mark follows the flag.
Uji::Driver::Win32::SendMessageW( $cb->{hwnd}, 0x00F5, 0, 0 );    # BM_CLICK
is $cb->{check}, 0, "BM_CLICK flips the registry flag to unchecked";
$paint->( $cb->{hwnd} );
is box_count( $cb->{hwnd}, $cby, $ACCENT ), 0, 'accent check mark disappears once unchecked';
Uji::Driver::Win32::SendMessageW( $cb->{hwnd}, 0x00F5, 0, 0 );    # BM_CLICK (back on)
is $cb->{check}, 1, 'BM_CLICK flips the registry flag back to checked';
$paint->( $cb->{hwnd} );
cmp_ok box_count( $cb->{hwnd}, $cby, $ACCENT ), '>', 0, 'check mark returns after re-check';

# --- radios: the dot follows the group value, moved through set_prop ---
my $rby = box_top($rb);
my $ray = box_top($ra);
$paint->( $ra->{hwnd} );
$paint->( $rb->{hwnd} );
cmp_ok box_count( $rb->{hwnd}, $rby, $ACCENT ), '>', 0, 'selected radio paints the accent dot';
is box_count( $ra->{hwnd}, $ray, $ACCENT ), 0, 'unselected radio has no dot';

$drv->set_prop( $rg->id, 'value', 'a' );
$paint->( $ra->{hwnd} );
$paint->( $rb->{hwnd} );
cmp_ok box_count( $ra->{hwnd}, $ray, $ACCENT ), '>', 0, 'set_prop value moves the dot to radio A';
is box_count( $rb->{hwnd}, $rby, $ACCENT ), 0, 'radio B loses its dot';

# --- toggle_button (BS_PUSHLIKE auto-check the classic renderer ignores): same owner-drawn dark treatment ---
my $tgy = box_top($tg);
is $tg->{check}, 0, 'toggle_button starts unchecked';
Uji::Driver::Win32::SendMessageW( $tg->{hwnd}, 0x00F5, 0, 0 );    # BM_CLICK
is $tg->{check}, 1, 'toggle_button checks on click';
$paint->( $tg->{hwnd} );
cmp_ok box_count( $tg->{hwnd}, $tgy, $ACCENT ), '>', 0, 'toggle_button paints the accent mark when checked';

# --- light scheme: native styles are kept (NO BS_OWNERDRAW) ---
my $chan2 = Acme::Parataxis::Channel->new( capacity => 1024 );
my $ldrv  = Uji::Driver::Win32->new( dark_mode => 0 );
$ldrv->init($chan2);
my $lrg   = Uji::radio_group( options => [ { value => 'x', label => 'X' } ] );
my $lvt   = Uji::window(
    id => 'lmain', title => 'l', w => 200, h => 80,
    child => Uji::column(
        padding => 6,
        children => [ Uji::checkbox( id => 'lcb', label => 'L' ), $lrg ],
    )
);
$ldrv->mount($lvt);
my $llayout = Uji::Layout->new( driver => $ldrv );
$llayout->compute( $lvt, 0, 0, 200, 80 );
$ldrv->mount_children($lvt);
my $lmove_all;
$lmove_all = sub {
    my ($n) = @_;
    $ldrv->move_widget( $n->id, $n->bx, $n->by, $n->bw, $n->bh ) unless $n->type eq 'window';
    return if $n->type eq 'scroll_view';
    $lmove_all->($_) for @{ $n->children };
};
$lmove_all->($lvt);
my $lcb = $ldrv->_get_registry_record('lcb');
ok $lcb && $lcb->{hwnd}, 'light mount: checkbox has an HWND';
# Light check/radio keep their native sub-types: BS_AUTOCHECKBOX = 3, BS_AUTORADIOBUTTON = 9 (whose low
# nibble genuinely has the 0x8 bit set), versus the dark BS_OWNERDRAW = 0xB. Compare the low nibble.
is Uji::Driver::Win32::GetWindowLongW( $lcb->{hwnd}, -16 ) & 0xF, 3, 'light checkbox keeps the native auto-checkbox style';
my $lr = $ldrv->_get_registry_record( $lrg->children->[0]->id );
ok $lr && $lr->{hwnd}, 'light mount: radio has an HWND';
is Uji::Driver::Win32::GetWindowLongW( $lr->{hwnd}, -16 ) & 0xF, 9, 'light radio keeps the native auto-radio style';

done_testing;