use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use blib;
use Test2::V0;
use Uji::Driver::Win32;
use Uji;
use Uji::Layout;
use Acme::Parataxis::Channel;
use Affix qw[:memory :core];
use Affix;
Affix::affix 'user32', 'SendMessageW', [ Pointer[Void], UInt, Size_t, SSize_t ] => Int;

skip_all 'Win32 only' unless $^O eq 'MSWin32';

my $chan = Acme::Parataxis::Channel->new( capacity => 1024 );
my $drv  = Uji::Driver::Win32->new;
$drv->init($chan);

#  Constants
my $DTM_GETSYSTEMTIME      = 0x1001;    # DTM_GETSYSTEMTIME (SYSTEMTIME via lParam, GDT_* in ret)
my $DTM_SETSYSTEMTIME      = 0x1002;    # DTM_SETSYSTEMTIME (wParam = GDT_VALID/GDT_NONE)
my $DTM_SETRANGE           = 0x1004;    # DTM_SETRANGE (wParam = GDTR_MIN|GDTR_MAX)
my $WM_NOTIFY              = 0x004E;
my $GDT_VALID              = 0x0000;
my $GDT_NONE               = 0x0001;
my $DTN_DATETIMECHANGE     = -759;      # DTN_FIRST2-6 (DTN_FIRST2 = -753) -- NOT DTN_FIRST (-760)

#  Live ISO + native round-trip (DTM_GETSYSTEMTIME) after user edit
my @iso_seen;
my $dp = Uji::date_picker(
    value     => '2025-11-02',
    min       => '2020-01-01',
    max       => '2030-12-31',
    show_none => 1,
    on_change => sub ($iso) {
        push @iso_seen, $iso;
        { type => 'DATE', value => $iso };
    },
);
my $dp_id  = $dp->id;
my $chan2  = $chan;
my $dwin   = Uji::window( id => 'date_main', title => 'DatePicker', w => 260, h => 120, child => $dp );
$drv->mount($dwin);
my $layout = Uji::Layout->new( driver => $drv );
$layout->compute( $dwin, 0, 0, 260, 120 );
$drv->mount_children($dwin);

my $move_all;
$move_all = sub ($n) {
    $drv->move_widget( $n->id, $n->bx, $n->by, $n->bw, $n->bh ) unless $n->type eq 'window';
    $move_all->($_) for @{ $n->children };
};
$move_all->($dwin);
my $dwinr  = $drv->_get_registry_record( $dwin->id );
my $dprec  = $drv->_get_registry_record( $dp->id );
ok $dprec && $dprec->{hwnd}, 'date_picker mounts with a real HWND';

#  1. Native init read-back via DTM_GETSYSTEMTIME
{
    my $st = Affix::malloc(16);
    my $gv = Uji::Driver::Win32::SendMessageW( $dprec->{hwnd}, $DTM_GETSYSTEMTIME, 0, Affix::address($st) );
    my $raw = Affix::raw( $st, 16 );
    my ( $y, $m, undef, $d ) = unpack( 'v4', $raw );
    is $gv, $GDT_VALID, 'DTM_GETSYSTEMTIME reports GDT_VALID';
    is sprintf( '%04d-%02d-%02d', $y, $m, $d ), '2025-11-02', 'the ISO-8601 value landed in the control';
    Affix::free($st);
}

#  2. DTN_DATETIMECHANGE (-759): user edit -> on_change + ISO via WM_NOTIFY
{
    my $nm = "\0" x 44;    # NMDATETIMECHANGE = NMHDR(24) + dwFlags(4) + SYSTEMTIME(16)
    substr( $nm, 0, 8 )   = pack( 'q<', $dprec->{hwnd} );    # hwndFrom
    substr( $nm, 8, 8 )   = pack( 'q<', 0 );                 # idFrom
    substr( $nm, 16, 4 )  = pack( 'l<', $DTN_DATETIMECHANGE );    # code
    substr( $nm, 24, 4 )  = pack( 'L<', $GDT_VALID );        # dwFlags
    substr( $nm, 28, 16 ) = pack( 'S8', 2028, 6, 0, 15, 0, 0, 0, 0 );    # SYSTEMTIME
    my $nmbuf = Affix::malloc(44);
    Affix::memcpy( $nmbuf, $nm, 44 );
    $chan->get() while $chan->size;

    # DTN_DATETIMECHANGE is delivered to the picker's PARENT (the window that owns the wndproc
    # where _ctrl_msg dispatches WM_NOTIFY); hwndFrom identifies the picker control itself.
    Uji::Driver::Win32::SendMessageW( $dwinr->{hwnd}, $WM_NOTIFY, 0, Affix::address($nmbuf) );
    Affix::free($nmbuf);
    my $msg = $chan->size ? $chan->get : undef;
    ok $msg, 'DTN_DATETIMECHANGE dispatches on_change';
    is $msg->{type},  'DATE', 'message type is DATE';
    is $msg->{value}, '2028-06-15', 'the edited date is reported as ISO-8601';
    is \@iso_seen, [ '2028-06-15' ], 'on_change receives the ISO date';
}

#  3. Cleared checkbox (show_none) -> empty string
{
    my $nm = "\0" x 44;
    substr( $nm, 0, 8 )  = pack( 'q<', $dprec->{hwnd} );
    substr( $nm, 8, 8 )  = pack( 'q<', 0 );
    substr( $nm, 16, 4 ) = pack( 'l<', $DTN_DATETIMECHANGE );
    substr( $nm, 24, 4 ) = pack( 'L<', $GDT_NONE );    # cleared checkbox
    my $nmbuf = Affix::malloc(44);
    Affix::memcpy( $nmbuf, $nm, 44 );
    $chan->get() while $chan->size;
    Uji::Driver::Win32::SendMessageW( $dwinr->{hwnd}, $WM_NOTIFY, 0, Affix::address($nmbuf) );
    Affix::free($nmbuf);
    my $msg = $chan->size ? $chan->get : undef;
    ok $msg, 'cleared checkbox still dispatches on_change';
    is $msg->{value}, '', 'no-date choice is reported as the empty string';
    is \@iso_seen, [ '2028-06-15', '' ], 'on_change sees the empty string';
}

#  4. set_prop value -> DTM_SETSYSTEMTIME round-trip (no echo)
{
    $drv->set_prop( $dp->id, 'value', '2027-01-02' );
    my $st = Affix::malloc(16);
    my $gv = Uji::Driver::Win32::SendMessageW( $dprec->{hwnd}, $DTM_GETSYSTEMTIME, 0, Affix::address($st) );
    my $raw = Affix::raw( $st, 16 );
    my ( $y, $m, undef, $d ) = unpack( 'v4', $raw );
    is $gv, $GDT_VALID, 'valid after set_prop';
    is sprintf( '%04d-%02d-%02d', $y, $m, $d ), '2027-01-02', 'set_prop value lands in the native control';
    Affix::free($st);
    $chan->get() while $chan->size;
    ok !$chan->size, 'programmatic set_prop produces no on_change echo';
}

#  5. Constraint seam: min/max set_prop snaps the WINDOW (own fresh tree)
{
    my $dp2 = Uji::date_picker( value => '2026-09-17', min => '2020-01-01', max => '2030-12-31' );
    my $w2  = Uji::window( id => 'dp_clamp', title => 'Clamp', w => 500, h => 100, child => $dp2 );
    $drv->mount($w2);
    $layout->compute( $w2, 0, 0, 500, 100 );
    $drv->mount_children($w2);
    my $m2;
    $m2 = sub ($n) {
        $drv->move_widget( $n->id, $n->bx, $n->by, $n->bw, $n->bh ) unless $n->type eq 'window';
        $m2->($_) for @{ $n->children };
    };
    $m2->($w2);
    my $w2r = $drv->_get_registry_record( $w2->id );
    my ( $cw ) = $drv->_get_client_size( $w2r->{hwnd} );

    # w => 500 is the OUTER (frame-inclusive) width, so the client is a little narrower but
    # the window must start at the requested size, not jump to a constraint.
    ok $cw <= 500 && $cw >= 400, "window starts at its requested 500 width (client = $cw)";

    # The clamp reads the constraint off the node (reconcile-driven, like t/019), so the snap
    # goes through the same pipeline an app uses: a fresh tree + patch -> update_registry +
    # set_prop('max_w', 300) -> immediate re-clamp.
    my $new_w2 = Uji::window( id => 'dp_clamp', title => 'Clamp', w => 500, h => 100, max_w => 300, child => $dp2 );
    my $recon  = Uji::Reconciler->new;
    $recon->patch( $w2, $new_w2, $drv );
    ( $cw ) = $drv->_get_client_size( $w2r->{hwnd} );
    ok $cw <= 300, "window snaps to the max_w constraint (client = $cw)";
}

#  6. min/max land in the control as a native DTM_SETRANGE (DTM_GETRANGE read-back)
{
    my $buf = Affix::malloc(32);
    my $rng = Uji::Driver::Win32::SendMessageW( $dprec->{hwnd}, 0x1003, 0x3, Affix::address($buf) );    # DTM_GETRANGE
    my $raw = Affix::raw( $buf, 32 );
    my ( $loy, $lom, undef, $lod ) = unpack( 'v4', substr( $raw, 0,  8 ) );
    my ( $hiy, $him, undef, $hid ) = unpack( 'v4', substr( $raw, 16, 8 ) );
    Affix::free($buf);
    is $rng, 0x3, 'DTM_GETRANGE reports GDTR_MIN|GDTR_MAX';
    is sprintf( '%04d-%02d-%02d', $loy, $lom, $lod ), '2020-01-01', 'mount-time min bound landed in the native range';
    is sprintf( '%04d-%02d-%02d', $hiy, $him, $hid ), '2030-12-31', 'mount-time max bound landed in the native range';

    my $buf2 = Affix::malloc(32);
    $drv->set_prop( $dp->id, 'min', '2019-05-06' );    # live re-bind, same seam a reconcile uses
    Uji::Driver::Win32::SendMessageW( $dprec->{hwnd}, 0x1003, 0x3, Affix::address($buf2) );
    my $raw3 = Affix::raw( $buf2, 32 );
    my ( $ly2, $lm2, undef, $ld2 ) = unpack( 'v4', substr( $raw3, 0, 8 ) );
    Affix::free($buf2);
    is sprintf( '%04d-%02d-%02d', $ly2, $lm2, $ld2 ), '2019-05-06', 'live set_prop min re-lands in the native range';
}

Uji::Driver::Win32::SendMessageW( $dwinr->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
done_testing;
