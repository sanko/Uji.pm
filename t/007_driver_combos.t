use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use blib;
use Test2::V0;
use Uji::Driver::Win32;
use Uji;
use Acme::Parataxis::Channel;
use Affix qw[:memory];
use Encode;
#
skip_all 'Win32 only' unless $^O eq 'MSWin32';

# Real-HWND ComboBox / ListBox: populate items, then drive WM_COMMAND notifications
# (CBN_SELCHANGE=1, CBN_EDITCHANGE=5, LBN_SELCHANGE=1) straight into the parent wndproc.
# wParam layout for WM_COMMAND is (notify_code << 16) | control_id.
my $chan = Acme::Parataxis::Channel->new( capacity => 1024 );
my $drv  = Uji::Driver::Win32->new;
$drv->init($chan);
my $cb = Uji::combo_box(
    value     => 'green',
    options   => [ { value => 'red', label => 'Red' }, { value => 'green', label => 'Green' }, { value => 'blue', label => 'Blue' } ],
    on_select => sub ($v) { { type => 'SET_COLOR', value => $v } },
);
my $lb = Uji::list_box(
    value     => 2,
    options   => [ map { { value => $_, label => $_ } } 1 .. 3 ],
    on_select => sub ($v) { { type => 'SET_COUNT', value => $v } },
);
my $ecb = Uji::combo_box(
    value     => 'X',
    editable  => 1,
    options   => [ { value => 'A', label => 'A' }, { value => 'B', label => 'B' } ],
    on_select => sub ($v) { { type => 'PICK', value => $v } },
    on_input  => sub ($t) { { type => 'CUSTOM', value => $t } },
);
my $ml = Uji::list_box(
    multiple  => 1,
    value     => [ 1, 3 ],
    options   => [ map { { value => $_, label => $_ } } 1 .. 3 ],
    on_select => sub ($v) { { type => 'SET_MULTI', value => $v } },
);
my $col   = Uji::column( spacing => 10, children => [ $cb, $lb, $ecb, $ml ] );
my $vtree = Uji::window( title => 't', w => 360, h => 400, child => $col );
$drv->mount($vtree);
my $layout = Uji::Layout->new( driver => $drv );
$layout->compute( $vtree, 0, 0, 360, 400 );
$drv->mount_children($vtree);
my $cbr  = $drv->_get_registry_record( $cb->id );
my $lbr  = $drv->_get_registry_record( $lb->id );
my $ecbr = $drv->_get_registry_record( $ecb->id );
my $mlr  = $drv->_get_registry_record( $ml->id );
my $wrb  = $drv->_get_registry_record( $vtree->id );
ok $cbr && $cbr->{hwnd}, 'combo box has a real HWND';
ok $lbr && $lbr->{hwnd}, 'list box has a real HWND';
ok $mlr && $mlr->{hwnd}, 'multi-select list box has a real HWND';
my ( $parent, $cid, $lid, $ecid ) = ( $wrb->{hwnd}, $cb->id, $lb->id, $ecb->id );

# Regression: the native controls must be created with "has strings" styles so the items we
# add are copied as text (not owner data), otherwise they render as raw pointer garbage.
{
    my @probe = (
        [ $cbr,  0x0146, 0x0149, 0x0148, 3, "Red"   ],    # CB_GETCOUNT / CB_GETLBTEXTLEN / CB_GETLBTEXT
        [ $lbr,  0x018B, 0x018A, 0x0189, 3, "1"     ],    # LB_GETCOUNT / LB_GETTEXTLEN / LB_GETTEXT
        [ $ecbr, 0x0146, 0x0149, 0x0148, 2, "A"     ],    # editable combo shares the same messages
    );
    for my $pr (@probe) {
        my ( $rec, $count_m, $len_m, $text_m, $expect_count, $expect_first ) = @$pr;
        is Uji::Driver::Win32::SendMessageW( $rec->{hwnd}, $count_m, 0, 0 ), $expect_count,
            'native item count matches options' . ( $rec == $cbr ? ' (combo)' : $rec == $lbr ? ' (list)' : ' (editable combo)' );
        my $l0 = Uji::Driver::Win32::SendMessageW( $rec->{hwnd}, $len_m, 0, 0 );
        is $l0, CORE::length($expect_first), 'item 0 length is stored as text (has-strings style)';
        my $buf = Affix::malloc( 64 );
        Uji::Driver::Win32::SendMessageW( $rec->{hwnd}, $text_m, 0, Affix::address($buf) );
        my $got = Encode::decode( 'UTF-16LE', Affix::raw( $buf, $l0 * 2 ) );
        is $got, $expect_first, 'item 0 reads back as text';
    }
}

# Mount/centering leaves stray messages in the channel; drop them before asserting.
$chan->get() while $chan->size;

# Select "red" in the combo programmatically, then tap CBN_SELCHANGE into the parent.
Uji::Driver::Win32::SendMessageW( $cbr->{hwnd}, 0x014E, 0, 0 );                       # CB_SETCURSEL index 0
$chan->get() while $chan->size;                                                        # drain any incidental notify
Uji::Driver::Win32::SendMessageW( $parent, 0x0111, ( 0x0001 << 16 ) | $cid, 0 );       # WM_COMMAND: CBN_SELCHANGE
my $msg = $chan->size ? $chan->get : undef;
ok $msg, 'combo selection produced a channel message';
is $msg && $msg->{type},  'SET_COLOR', 'combo selection message type';
is $msg && $msg->{value}, 'red',       'combo selection carries the option value';

# Pick list item index 1 (value 2), then tap LBN_SELCHANGE.
Uji::Driver::Win32::SendMessageW( $lbr->{hwnd}, 0x0186, 1, 0 );                       # LB_SETCURSEL index 1
$chan->get() while $chan->size;
Uji::Driver::Win32::SendMessageW( $parent, 0x0111, ( 0x0001 << 16 ) | $lid, 0 );       # WM_COMMAND: LBN_SELCHANGE
my $msg2 = $chan->size ? $chan->get : undef;
ok $msg2, 'list selection produced a channel message';
is $msg2 && $msg2->{type},  'SET_COUNT', 'list selection message type';
is $msg2 && $msg2->{value}, 2,           'list selection carries the option value';

# Editable combo: selecting "A" fills the edit with its text; typing taps CBN_EDITCHANGE (5).
Uji::Driver::Win32::SendMessageW( $ecbr->{hwnd}, 0x014E, 0, 0 );                       # CB_SETCURSEL index 0 -> edit text "A"
$chan->get() while $chan->size;
Uji::Driver::Win32::SendMessageW( $parent, 0x0111, ( 0x0005 << 16 ) | $ecid, 0 );       # WM_COMMAND: CBN_EDITCHANGE
my $msg3 = $chan->size ? $chan->get : undef;
ok $msg3, 'editable combo edit produced a channel message';
is $msg3 && $msg3->{type},  'CUSTOM', 'editable combo edit message type';
is $msg3 && $msg3->{value}, 'A',      'editable combo edit carries the typed text';

# ...and selecting from the list of the editable combo still routes on_select.
Uji::Driver::Win32::SendMessageW( $ecbr->{hwnd}, 0x014E, 1, 0 );                       # CB_SETCURSEL index 1 -> "B"
$chan->get() while $chan->size;
Uji::Driver::Win32::SendMessageW( $parent, 0x0111, ( 0x0001 << 16 ) | $ecid, 0 );       # WM_COMMAND: CBN_SELCHANGE
my $msg4 = $chan->size ? $chan->get : undef;
ok $msg4, 'editable combo selection produced a channel message';
is $msg4 && $msg4->{type},  'PICK', 'editable combo selection message type';
is $msg4 && $msg4->{value}, 'B',    'editable combo selection carries the option value';

# Multi-select list (LBS_MULTIPLESEL): initial value [1,3] must be applied to the native rows.
my $msel_cnt = Uji::Driver::Win32::SendMessageW( $mlr->{hwnd}, 0x0190, 0, 0 );          # LB_GETSELCOUNT
is $msel_cnt, 2, 'multi-select list applies both initial values (count 2)';
{
    my $cnt = Uji::Driver::Win32::SendMessageW( $mlr->{hwnd}, 0x0190, 0, 0 );          # LB_GETSELCOUNT
    my $mb  = Affix::malloc( ( $cnt || 1 ) * 4 );
    Uji::Driver::Win32::SendMessageW( $mlr->{hwnd}, 0x0191, $cnt, Affix::address($mb) );    # LB_GETSELITEMS
    my @sel = $cnt ? unpack( "V$cnt", Affix::raw( $mb, $cnt * 4 ) ) : ();
    is( \@sel, [ 0, 2 ], 'multi-select list selects rows 0 and 2' );
}

# Tap LBN_SELCHANGE: the message value must be an arrayref of the selected option values.
$chan->get() while $chan->size;
Uji::Driver::Win32::SendMessageW( $parent, 0x0111, ( 0x0001 << 16 ) | $ml->id, 0 );      # WM_COMMAND: LBN_SELCHANGE
my $msg5 = $chan->size ? $chan->get : undef;
ok $msg5, 'multi-select list produced a channel message';
is $msg5 && $msg5->{type},  'SET_MULTI', 'multi-select list message type';
is( $msg5 && $msg5->{value}, [ 1, 3 ], 'multi-select list carries arrayref of selected values' );

# Toggling a row natively updates what a later LBN_SELCHANGE reports.
Uji::Driver::Win32::SendMessageW( $mlr->{hwnd}, 0x0185, 1, 1 );                          # LB_SETSEL select row 1
$chan->get() while $chan->size;
Uji::Driver::Win32::SendMessageW( $parent, 0x0111, ( 0x0001 << 16 ) | $ml->id, 0 );      # WM_COMMAND: LBN_SELCHANGE
my $msg6 = $chan->size ? $chan->get : undef;
is( $msg6 && $msg6->{value}, [ 1, 2, 3 ], 'multi-select list reports the toggled row' );

# set_prop('value') re-applies a whole selection set.
$drv->set_prop( $ml->id, 'value', [ 2 ] );
my $msel_cnt2 = Uji::Driver::Win32::SendMessageW( $mlr->{hwnd}, 0x0190, 0, 0 );          # LB_GETSELCOUNT
is $msel_cnt2, 1, 'set_prop narrows the selection to one row';
{
    my $cnt = Uji::Driver::Win32::SendMessageW( $mlr->{hwnd}, 0x0190, 0, 0 );          # LB_GETSELCOUNT
    my $mb  = Affix::malloc( ( $cnt || 1 ) * 4 );
    Uji::Driver::Win32::SendMessageW( $mlr->{hwnd}, 0x0191, $cnt, Affix::address($mb) );    # LB_GETSELITEMS
    my @sel = $cnt ? unpack( "V$cnt", Affix::raw( $mb, $cnt * 4 ) ) : ();
    is( \@sel, [ 1 ], 'set_prop keeps only the requested row' );
}

# Editable combo caret: set_prop('value') must not force the cursor to the end of the string.
$drv->set_prop( $ecb->id, 'value', 'HELLO' );                                            # not in options -> edit text
Uji::Driver::Win32::SendMessageW( $ecbr->{hwnd}, 0x0142, 0, ( 2 << 16 ) | 2 );           # CB_SETEDITSEL caret at 2
$drv->set_prop( $ecb->id, 'value', 'HELLO' );                                            # unchanged -> skipped
{
    my $p = Uji::Driver::Win32::SendMessageW( $ecbr->{hwnd}, 0x0140, 0, 0 );            # CB_GETEDITSEL
    is( $p & 0xFFFF, 2, 'unchanged re-render leaves the caret where it was' );
    is( ( $p >> 16 ) & 0xFFFF, 2, 'unchanged re-render leaves the caret end where it was' );
}
$drv->set_prop( $ecb->id, 'value', 'HELLO2' );                                           # changed -> restore, not end
{
    my $p = Uji::Driver::Win32::SendMessageW( $ecbr->{hwnd}, 0x0140, 0, 0 );            # CB_GETEDITSEL
    is( $p & 0xFFFF, 2, 'changed text restores the previous caret (not the end)' );
    is( ( $p >> 16 ) & 0xFFFF, 2, 'changed text restores the previous caret end' );
}

# Close the test window unobtrusively.
Uji::Driver::Win32::SendMessageW( $parent, 0x0010, 0, 0 );    # WM_CLOSE -> WM_DESTROY
#
done_testing;
