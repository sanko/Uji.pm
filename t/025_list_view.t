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
use Affix;
Affix::affix 'user32', 'PostMessageW', [ Pointer[Void], UInt, Size_t, SSize_t ] => Int;
#
skip_all 'Win32 only' unless $^O eq 'MSWin32';

#  List-view constants
my $LVM_GETITEMCOUNT     = 0x1004;
my $LVM_GETITEMSTATE     = 0x102C;
my $LVM_GETITEMTEXTW     = 0x1073;
my $LVM_INSERTCOLUMNW    = 0x1061;
my $LVM_SETITEMSTATE     = 0x102B;
my $LVIS_SELECTED        = 0x0002;
my $LVN_ITEMCHANGED      = -101;    # LVN_FIRST-1 (there is no A/W variant)
my $chan                 = Acme::Parataxis::Channel->new( capacity => 1024 );
my $drv                  = Uji::Driver::Win32->new;
$drv->init($chan);

#  Set up a window containing a list_view
my $lv = Uji::list_view(
    value       => 'b',
    columns     => [ { label => 'Fruit', width => 140 }, { label => 'Qty', width => 70 } ],
    rows        => [
        { value => 'a', columns => [ 'Apples', '3' ] },
        { value => 'b', columns => [ 'Bananas', '5' ] },
        { value => 'c', columns => [ 'Cherries', 'café ✓' ] },
    ],
    on_select => sub ($v) { { type => 'SELECT', value => $v } },
);
my $col   = Uji::column( padding => 8, children => [$lv] );
my $vwin  = Uji::window( id => 'lv_main', title => 'ListView Test', w => 320, h => 400, child => $col );
$drv->mount($vwin);
my $layout = Uji::Layout->new( driver => $drv );
$layout->compute( $vwin, 0, 0, 320, 400 );
$drv->mount_children($vwin);

my $move_all;
$move_all = sub {
    my ($n) = @_;
    $drv->move_widget( $n->id, $n->bx, $n->by, $n->bw, $n->bh ) unless $n->type eq 'window';
    $move_all->($_) for @{ $n->children };
};
$move_all->($vwin);
my $wrb = $drv->_get_registry_record( $vwin->id );
my $lr  = $drv->_get_registry_record( $lv->id );
ok $lr && $lr->{hwnd}, 'list_view has a registry record with a real HWND';

#  1. Class name is SysListView32
my $cls = '';
{
    my $buf = Affix::malloc(128);
    Uji::Driver::Win32::GetClassNameW( $lr->{hwnd}, $buf, 64 );
    $cls = decode( 'UTF-16LE', Affix::raw( $buf, 128 ) );
    $cls =~ s/\x00.*//s;
    Affix::free($buf);
}
is $cls, 'SysListView32', 'mounts SysListView32';

#  2. Row count: 3 mounted rows
my $count = Uji::Driver::Win32::SendMessageW( $lr->{hwnd}, $LVM_GETITEMCOUNT, 0, 0 );
is $count, 3, 'LVM_GETITEMCOUNT returns 3 rows';

#  3. Column widths match the model
my $cw0 = Uji::Driver::Win32::SendMessageW( $lr->{hwnd}, 0x101D, 0, 0 );    # LVM_GETCOLUMNWIDTH
my $cw1 = Uji::Driver::Win32::SendMessageW( $lr->{hwnd}, 0x101D, 1, 0 );
is $cw0, 140, 'column 0 width is 140';
is $cw1, 70,  'column 1 width is 70';
is Uji::Driver::Win32::SendMessageW( $lr->{hwnd}, 0x101D, 2, 0 ), 0, 'no third column exists';

#  4. UTF-8 cell round-trips through LVM_GETITEMTEXTW
{
    my $buf = Affix::malloc(256);
    my $lvitem = pack 'L< l< l< L< L< x4 q< l< l< q< l< l< L< x4 q< q< l< x4',
        0x0001, 2, 1, 0, 0, Affix::address($buf), 256, 0, 0, 0, 0, 0, 0, 0, 0;    # LVIF_TEXT, item 2, subitem 1
    my $sb = Affix::malloc( length $lvitem );
    Affix::memcpy( $sb, $lvitem, length $lvitem );
    Uji::Driver::Win32::SendMessageW( $lr->{hwnd}, $LVM_GETITEMTEXTW, 2, Affix::address($sb) );
    Affix::free($sb);
    my $cell = decode( 'UTF-16LE', Affix::raw( $buf, 256 ) );
    $cell =~ s/\x00.*//s;
    Affix::free($buf);
    is $cell, 'café ✓', 'row 2 col 1 text round-trips as UTF-8';
}

#  5. Mount selection: value='b' selects row 1
my $st0 = Uji::Driver::Win32::SendMessageW( $lr->{hwnd}, $LVM_GETITEMSTATE, 0, $LVIS_SELECTED );
my $st1 = Uji::Driver::Win32::SendMessageW( $lr->{hwnd}, $LVM_GETITEMSTATE, 1, $LVIS_SELECTED );
ok !( $st0 & $LVIS_SELECTED ), 'row 0 is not selected';
ok $st1 & $LVIS_SELECTED,      'row 1 (value b) is selected at mount';

#  6. LVN_ITEMCHANGED: simulate a click on row 2 (value='c')
{
    my $nm = "\0" x 64;
    substr( $nm, 0, 8 )  = pack( 'q<', $lr->{hwnd} );      # NMHDR.hwndFrom
    substr( $nm, 8, 8 )  = pack( 'q<', 0 );                # idFrom
    substr( $nm, 16, 4 ) = pack( 'l<', $LVN_ITEMCHANGED );    # code
    substr( $nm, 24, 4 ) = pack( 'l<', 2 );                # iItem = row 2
    substr( $nm, 28, 4 ) = pack( 'l<', 0 );                # iSubItem
    substr( $nm, 32, 4 ) = pack( 'L<', $LVIS_SELECTED );   # uNewState
    substr( $nm, 36, 4 ) = pack( 'L<', 0 );                # uOldState
    my $nmbuf = Affix::malloc(64);
    Affix::memcpy( $nmbuf, $nm, 64 );
    $chan->get() while $chan->size;                        # clear any stale messages
    Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x004E, 0, Affix::address($nmbuf) );    # WM_NOTIFY
    Affix::free($nmbuf);
    my $msg = $chan->size ? $chan->get : undef;
    ok $msg, 'LVN_ITEMCHANGED dispatches on_select';
    is $msg->{type},  'SELECT', 'channel message type is SELECT';
    is $msg->{value}, 'c',      'channel message value is Cherries row';
}

#  7. Focus-only notification (no LVIS_SELECTED) is ignored
{
    my $nm = "\0" x 64;
    substr( $nm, 0, 8 )  = pack( 'q<', $lr->{hwnd} );
    substr( $nm, 16, 4 ) = pack( 'l<', $LVN_ITEMCHANGED );
    substr( $nm, 24, 4 ) = pack( 'l<', 1 );
    substr( $nm, 32, 4 ) = pack( 'L<', 0x0001 );    # LVIS_FOCUSED only
    my $nmbuf = Affix::malloc(64);
    Affix::memcpy( $nmbuf, $nm, 64 );
    $chan->get() while $chan->size;
    Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x004E, 0, Affix::address($nmbuf) );
    Affix::free($nmbuf);
    ok !$chan->size, 'focus-only LVN_ITEMCHANGED is ignored';
}

#  8. set_prop('value'): move selection to 'a' (row 0)
{
    $drv->set_prop( $lv->id, 'value', 'a' );
    my $s0 = Uji::Driver::Win32::SendMessageW( $lr->{hwnd}, $LVM_GETITEMSTATE, 0, $LVIS_SELECTED );
    my $s1 = Uji::Driver::Win32::SendMessageW( $lr->{hwnd}, $LVM_GETITEMSTATE, 1, $LVIS_SELECTED );
    ok $s0 & $LVIS_SELECTED, 'set_prop value selects row 0';
    ok !( $s1 & $LVIS_SELECTED ), 'set_prop value clears row 1';
    $chan->get() while $chan->size;    # and no echo on_select from the programmatic select
    ok !$chan->size, 'programmatic selection produces no on_select echo';
}

#  9. Reconciler: change rows (add a row 'd') + change value ('d')
{
    my $recon    = Uji::Reconciler->new;
    my $old_lv   = Uji::list_view( value => 'a', columns => $lv->columns, rows => $lv->rows, );
    $old_lv->set_id( $lv->id );
    $layout->compute( $old_lv, $lv->bx, $lv->by, $lv->bw, $lv->bh );
    my @new_rows = @{ $lv->rows };
    push @new_rows, { value => 'd', columns => [ 'Damsons', '8' ] };
    my $new_lv = Uji::list_view( value => 'd', columns => $lv->columns, rows => \@new_rows, );
    $layout->compute( $new_lv, $lv->bx, $lv->by, $lv->bw, $lv->bh );
    $recon->patch( $old_lv, $new_lv, $drv );
    my $count2 = Uji::Driver::Win32::SendMessageW( $lr->{hwnd}, $LVM_GETITEMCOUNT, 0, 0 );
    is $count2, 4, 'reconciled rows change (add Damsons) -> count 4';
    my $s3 = Uji::Driver::Win32::SendMessageW( $lr->{hwnd}, $LVM_GETITEMSTATE, 3, $LVIS_SELECTED );
    ok $s3 & $LVIS_SELECTED, 'reconciled value change selects the new row 3';
}

#  10. Multi-select: arrayref value + arrayref on_select payload
{
    my ( $mwnd, $mr );
    my $multi = Uji::list_view(
        multiple => 1,
        value    => ['Apples'],
        columns  => [ { label => 'Item', width => 120 } ],
        rows     => [
            [ 'Apples', 'x' ],    # arrayref rows: value defaults to the first cell
            { value => 'b', columns => ['Bananas'] },
            { value => 'c', columns => ['Cherries'] },
        ],
        on_select => sub ($v) { { type => 'PICKS', value => $v } },
    );
    my $mcol  = Uji::column( padding => 8, children => [$multi] );
    my $mwin  = Uji::window( id => 'lv_multi', title => 'ListView Multi Test', w => 300, h => 300, child => $mcol );
    $drv->mount($mwin);
    $layout->compute( $mwin, 0, 0, 300, 300 );
    $drv->mount_children($mwin);
    $move_all->($mwin);
    $mwnd = $drv->_get_registry_record( $mwin->id );
    $mr   = $drv->_get_registry_record( $multi->id );
    ok $mr && $mr->{hwnd}, 'multi list_view mounts';

    my $s0 = Uji::Driver::Win32::SendMessageW( $mr->{hwnd}, $LVM_GETITEMSTATE, 0, $LVIS_SELECTED );
    ok $s0 & $LVIS_SELECTED, 'multi-select rows[0] (value Apples) selected at mount';

    # Simulate the user also clicking row 1 (Bananas): a real click updates the native
    # selection first (the control does this before raising LVN_ITEMCHANGED), so set row 1
    # selected natively before emitting the notification.
    {
        my $sel = pack 'L< l< l< L< L< x4 q< l< l< q< l< l< L< x4 q< q< l< x4',
            0x0008, 1, 0, $LVIS_SELECTED, $LVIS_SELECTED, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0;
        my $sb = Affix::malloc( length $sel );
        Affix::memcpy( $sb, $sel, length $sel );
        Uji::Driver::Win32::SendMessageW( $mr->{hwnd}, $LVM_SETITEMSTATE, 1, Affix::address($sb) );
        Affix::free($sb);
    }
    my $nm = "\0" x 64;
    substr( $nm, 0, 8 )  = pack( 'q<', $mr->{hwnd} );
    substr( $nm, 16, 4 ) = pack( 'l<', $LVN_ITEMCHANGED );
    substr( $nm, 24, 4 ) = pack( 'l<', 1 );
    substr( $nm, 32, 4 ) = pack( 'L<', $LVIS_SELECTED );
    my $nmbuf = Affix::malloc(64);
    Affix::memcpy( $nmbuf, $nm, 64 );
    $chan->get() while $chan->size;
    Uji::Driver::Win32::SendMessageW( $mwnd->{hwnd}, 0x004E, 0, Affix::address($nmbuf) );
    Affix::free($nmbuf);
    my $msg = $chan->size ? $chan->get : undef;
    ok $msg, 'multi LVN_ITEMCHANGED dispatches on_select';
    is $msg->{value}, [ 'Apples', 'b' ], 'multi on_select receives the whole selection';

    # set_prop with an arrayref applies the selection.
    $drv->set_prop( $multi->id, 'value', [ 'Apples', 'c' ] );
    my @sel;
    for my $i ( 0 .. 2 ) {
        my $st = Uji::Driver::Win32::SendMessageW( $mr->{hwnd}, $LVM_GETITEMSTATE, $i, $LVIS_SELECTED );
        push @sel, $i if $st & $LVIS_SELECTED;
    }
    is \@sel, [ 0, 2 ], 'set_prop arrayref selection selects rows 0 and 2';
    $chan->get() while $chan->size;    # programmatic, so no echo
    ok !$chan->size, 'programmatic multi-select produces no on_select echo';
    Uji::Driver::Win32::SendMessageW( $mwnd->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
}

#  11. Column sorting (LVN_COLUMNCLICK) + column reorder sync
{
    my $cell = sub ($hwnd, $row, $col) {
        my $buf = Affix::malloc(256);
        my $lvitem = pack 'L< l< l< L< L< x4 q< l< l< q< l< l< L< x4 q< q< l< x4',
            0x0001, $row, $col, 0, 0, Affix::address($buf), 256, 0, 0, 0, 0, 0, 0, 0, 0;
        my $sb = Affix::malloc( length $lvitem );
        Affix::memcpy( $sb, $lvitem, length $lvitem );
        Uji::Driver::Win32::SendMessageW( $hwnd, $LVM_GETITEMTEXTW, $row, Affix::address($sb) );
        Affix::free($sb);
        my $txt = decode( 'UTF-16LE', Affix::raw( $buf, 256 ) );
        $txt =~ s/\x00.*//s;
        Affix::free($buf);
        return $txt;
    };
    my $notify = sub ($hwnd, $code, $iitem, $isub) {
        my $nm = "\0" x 64;
        substr( $nm, 0, 8 )  = pack( 'q<', $hwnd );    # NMHDR.hwndFrom
        substr( $nm, 16, 4 ) = pack( 'l<', $code );    # code
        substr( $nm, 24, 4 ) = pack( 'l<', $iitem );   # iItem
        substr( $nm, 28, 4 ) = pack( 'l<', $isub );    # iSubItem
        my $nmbuf = Affix::malloc(64);
        Affix::memcpy( $nmbuf, $nm, 64 );
        $chan->get() while $chan->size;
        Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x004E, 0, Affix::address($nmbuf) );
        Affix::free($nmbuf);
    };

    my (@sort_events, @ord_events);
    my $sortlv = Uji::list_view(
        value      => 'b',
        sortable   => 1,
        reorderable => 1,
        columns    => [
            { label => 'Fruit', width => 120 },
            { label => 'Qty',   width => 50, sort => 'numeric' },
        ],
        rows       => [
            { value => 'a', columns => [ 'Apples',   '3' ] },
            { value => 'b', columns => [ 'Bananas',  '5' ] },
            { value => 'c', columns => [ 'Cherries', '1' ] },
        ],
        on_sort    => sub ($c, $d) { push @sort_events, [ $c, $d ]; { type => 'SORT', column => $c, dir => $d } },
        on_reorder => sub ($o)     { push @ord_events, [ @$o ];      { type => 'REORDER', order => [@$o] } },
    );
    my $scol = Uji::column( padding => 8, children => [$sortlv] );
    my $swin = Uji::window( id => 'lv_sort', title => 'ListView Sort Test', w => 320, h => 300, child => $scol );
    $drv->mount($swin);
    $layout->compute( $swin, 0, 0, 320, 300 );
    $drv->mount_children($swin);
    $move_all->($swin);
    my $sr = $drv->_get_registry_record( $sortlv->id );
    ok $sr && $sr->{hwnd}, 'sortable list_view mounts';

    # User clicks the Qty header (LVN_COLUMNCLICK, iSubItem=1) → asc numeric sort.
    $notify->( $sr->{hwnd}, -108, -1, 1 );
    my $msgS = $chan->size ? $chan->get : undef;
    ok $msgS, 'LVN_COLUMNCLICK dispatches on_sort';
    is $msgS->{type},   'SORT', 'sort message type is SORT';
    is $msgS->{column}, 1,      'sort column is the clicked header (Qty)';
    is $msgS->{dir},    'asc',  'first click sorts ascending';
    is \@sort_events, [ [ 1, 'asc' ] ], 'on_sort callback gets (column, dir)';
    is $cell->( $sr->{hwnd}, 0, 0 ), 'Cherries', 'numeric asc: row 0 is Cherries (Qty 1)';
    is $cell->( $sr->{hwnd}, 1, 0 ), 'Apples',   'numeric asc: row 1 is Apples (Qty 3)';
    is $cell->( $sr->{hwnd}, 2, 0 ), 'Bananas',  'numeric asc: row 2 is Bananas (Qty 5)';
    is Uji::Driver::Win32::SendMessageW( $sr->{hwnd}, $LVM_GETITEMSTATE, 2, $LVIS_SELECTED )
        & $LVIS_SELECTED, $LVIS_SELECTED, 'selection (value b = Bananas) survives the sort rebuild';

    # Same header again → desc.
    $notify->( $sr->{hwnd}, -108, -1, 1 );
    my $msgS2 = $chan->size ? $chan->get : undef;
    is $msgS2->{dir}, 'desc', 'second click on the same column sorts descending';
    is $cell->( $sr->{hwnd}, 0, 0 ), 'Bananas',  'numeric desc: row 0 is Bananas (Qty 5)';

    # Click the Fruit header (text sort, iSubItem=0).
    $notify->( $sr->{hwnd}, -108, -1, 0 );
    my $msgS3 = $chan->size ? $chan->get : undef;
    is $msgS3->{column}, 0,   'clicking the Fruit header sorts by column 0';
    is $msgS3->{dir},    'asc', 'new column starts ascending';
    is $cell->( $sr->{hwnd}, 0, 0 ), 'Apples', 'text asc: row 0 is Apples';

    # A list that is not sortable ignores the column click entirely.
    $notify->( $lr->{hwnd}, -108, -1, 0 );
    ok !$chan->size, 'non-sortable list ignores LVN_COLUMNCLICK';

    # Real header drag (posted mouse input) changes the native column order; the driver's
    # poll-time sync learns it and dispatches on_reorder. Programmatic LVM_SETCOLUMNORDERARRAY
    # does not update the order LVM_GETCOLUMNORDERARRAY reports, so the drag is simulated.
    {
        my $hdr  = Uji::Driver::Win32::SendMessageW( $sr->{hwnd}, 0x101F, 0, 0 );    # LVM_GETHEADER
        ok $hdr, 'listview exposes its header control';
        is $drv->lv_column_order( $sr->{hwnd}, 2 ), [ 0, 1 ], 'initial column order is [0,1]';
        $chan->get() while $chan->size;
        # Drag header item 1 (Qty, spans x 120-170) leftwards onto item 0.
        PostMessageW( $hdr, 0x0201, 1, 135 | ( 8 << 16 ) );    # WM_LBUTTONDOWN
        PostMessageW( $hdr, 0x0200, 1, 110 | ( 8 << 16 ) );    # WM_MOUSEMOVE
        PostMessageW( $hdr, 0x0200, 1, 60  | ( 8 << 16 ) );
        PostMessageW( $hdr, 0x0200, 1, 30  | ( 8 << 16 ) );
        PostMessageW( $hdr, 0x0202, 0, 25  | ( 8 << 16 ) );    # WM_LBUTTONUP
        for ( 1 .. 50 ) { $drv->poll_events }
        is $drv->lv_column_order( $sr->{hwnd}, 2 ), [ 1, 0 ], 'header drag reorders columns to [1,0]';
        is \@ord_events, [ [ 1, 0 ] ], 'on_reorder dispatched after the drag';
        my $msgR = $chan->size ? $chan->get : undef;
        is $msgR->{type},  'REORDER', 'reorder channel message type is REORDER';
        is $msgR->{order}, [ 1, 0 ],   'reorder channel message carries the new order';
    }

    my $swr = $drv->_get_registry_record( $swin->id );
    Uji::Driver::Win32::SendMessageW( $swr->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
}

#  12. Per-column display format
{
    my $cell = sub ($hwnd, $row, $col) {
        my $buf = Affix::malloc(256);
        my $lvitem = pack 'L< l< l< L< L< x4 q< l< l< q< l< l< L< x4 q< q< l< x4',
            0x0001, $row, $col, 0, 0, Affix::address($buf), 256, 0, 0, 0, 0, 0, 0, 0, 0;
        my $sb = Affix::malloc( length $lvitem );
        Affix::memcpy( $sb, $lvitem, length $lvitem );
        Uji::Driver::Win32::SendMessageW( $hwnd, $LVM_GETITEMTEXTW, $row, Affix::address($sb) );
        Affix::free($sb);
        my $txt = decode( 'UTF-16LE', Affix::raw( $buf, 256 ) );
        $txt =~ s/\x00.*//s;
        Affix::free($buf);
        return $txt;
    };
    my $fmtlv = Uji::list_view(
        columns => [
            { label => 'Item', width => 80 },
            { label => 'Cost', width => 70, format => '$%0.2f', sort => 'numeric' },
        ],
        rows => [
            [ 'A', '1.5' ],
            [ 'B', '2' ],
            [ 'C', 'tbd' ],    # non-numeric cell passes through unformatted
        ],
    );
    my $fcol = Uji::column( padding => 8, children => [$fmtlv] );
    my $fwin = Uji::window( id => 'lv_fmt', title => 'ListView Format Test', w => 300, h => 240, child => $fcol );
    $drv->mount($fwin);
    $layout->compute( $fwin, 0, 0, 300, 240 );
    $drv->mount_children($fwin);
    $move_all->($fwin);
    my $fr = $drv->_get_registry_record( $fmtlv->id );
    ok $fr && $fr->{hwnd}, 'formatted list_view mounts';
    is $cell->( $fr->{hwnd}, 0, 1 ), '$1.50', 'numeric cell renders with the column format';
    is $cell->( $fr->{hwnd}, 1, 1 ), '$2.00', 'integer cell renders with two decimals';
    is $cell->( $fr->{hwnd}, 2, 1 ), 'tbd',   'non-numeric cell passes through unformatted';
    $chan->get() while $chan->size;    # a click on a non-sortable list is a no-op; nothing to read

    my $fwr = $drv->_get_registry_record( $fwin->id );
    Uji::Driver::Win32::SendMessageW( $fwr->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
}

#  13. Width/order persistence + sort indicator
{
    my $widths = sub ($hwnd) {
        return join( ',', map { Uji::Driver::Win32::SendMessageW( $hwnd, 0x101D, $_, 0 ) } 0 .. 1 );
    };
    my $coltext = sub ($hwnd, $col) {
        my $buf = Affix::malloc(256);
        my $lvcol = pack 'L< l< l< x4 q< l< l< l< l< l< l< l< L< q< l< x4',
            0x0004, 0, 0, Affix::address($buf), 256, 0, 0, 0, 0, 0, 0, 0, 0, 0;    # LVCF_TEXT
        my $sb = Affix::malloc( length $lvcol );
        Affix::memcpy( $sb, $lvcol, length $lvcol );
        Uji::Driver::Win32::SendMessageW( $hwnd, 0x105F, $col, Affix::address($sb) );    # LVM_GETCOLUMNW
        Affix::free($sb);
        my $txt = decode( 'UTF-16LE', Affix::raw( $buf, 256 ) );
        $txt =~ s/\x00.*//s;
        Affix::free($buf);
        return $txt;
    };
    my (@pi_events);
    my $pilv = Uji::list_view(
        value       => 'b',
        sortable    => 1,
        reorderable => 1,
        columns     => [
            { label => 'Fruit', width => 120 },
            { label => 'Qty',   width => 50, sort => 'numeric' },
        ],
        rows        => [
            { value => 'a', columns => [ 'Apples',   '3' ] },
            { value => 'b', columns => [ 'Bananas',  '5' ] },
            { value => 'c', columns => [ 'Cherries', '1' ] },
        ],
        on_sort => sub ($c, $d) { push @pi_events, [ $c, $d ]; { type => 'SORT', column => $c, dir => $d } },
    );
    my $pcol = Uji::column( padding => 8, children => [$pilv] );
    my $pwin = Uji::window( id => 'lv_persist', title => 'ListView Persist Test', w => 320, h => 300, child => $pcol );
    $drv->mount($pwin);
    $layout->compute( $pwin, 0, 0, 320, 300 );
    $drv->mount_children($pwin);
    $move_all->($pwin);
    my $pr   = $drv->_get_registry_record( $pilv->id );
    my $pwr  = $drv->_get_registry_record( $pwin->id );
    ok $pr && $pr->{hwnd}, 'persist list_view mounts';
    is $widths->( $pr->{hwnd} ), '120,50', 'baseline widths are 120,50';
    is $coltext->( $pr->{hwnd}, 0 ), 'Fruit', 'baseline header 0 text is Fruit';
    my $pnotify = sub ($isub) {    # portable header-click seam (Uji::Driver::list_view_click_column); NO WM_NOTIFY packing here
        $chan->get() while $chan->size;
        $drv->list_view_click_column( $pilv, $isub );
    };

    # Plain header click (no drag yet): model == visual index, indicator stamped on.
    $pnotify->(1);    # click Qty (visual 1 = model 1)
    my $m1 = $chan->size ? $chan->get : undef;
    is $m1->{column}, 1,          'Qty click reports model column 1';
    is $coltext->( $pr->{hwnd}, 0 ), 'Fruit', 'unsorted header text is plain';
    is $coltext->( $pr->{hwnd}, 1 ), "Qty ▲", 'sorted header carries the up glyph';
    is $widths->( $pr->{hwnd} ), '120,50', 'widths survive the sort rebuild';
    is $drv->lv_column_order( $pr->{hwnd}, 2 ), [ 0, 1 ], 'column order survives the sort rebuild';

    $pnotify->(1);    # toggle -> desc
    my $m2 = $chan->size ? $chan->get : undef;
    is $m2->{dir}, 'desc', 'second Qty click toggles desc';
    is $coltext->( $pr->{hwnd}, 1 ), "Qty ▼", 'desc sorted header carries the down glyph';

    # rows-only reconcile (a sort the app itself does by setting rows): widths + order + glyph persist.
    # The reconcile replaces the driver's node object, so the rebuilt nodes carry the same callbacks.
    my $on_sort = sub ($c, $d) { push @pi_events, [ $c, $d ]; { type => 'SORT', column => $c, dir => $d } };
    my $recon   = Uji::Reconciler->new;
    my $old_lv  = Uji::list_view( sortable => 1, reorderable => 1, on_sort => $on_sort, columns => $pilv->columns, rows => $pilv->rows );
    $old_lv->set_id( $pilv->id );
    my $new_lv = Uji::list_view( sortable => 1, reorderable => 1, on_sort => $on_sort, columns => $pilv->columns, rows => [
        [ 'Apples', '9' ], [ 'Bananas', '7' ], [ 'Cherries', '8' ], [ 'Damsons', '6' ],
    ] );
    $recon->patch( $old_lv, $new_lv, $drv );
    is Uji::Driver::Win32::SendMessageW( $pr->{hwnd}, $LVM_GETITEMCOUNT, 0, 0 ), 4, 'rows-only reconcile refills rows';
    is $widths->( $pr->{hwnd} ), '120,50', 'widths survive a rows-only reconcile';
    is $drv->lv_column_order( $pr->{hwnd}, 2 ), [ 0, 1 ], 'column order survives a rows-only reconcile';
    is $coltext->( $pr->{hwnd}, 1 ), "Qty ▼", 'sorted glyph survives a rows-only reconcile';

    # columns-only reconcile recreates the header (indicator reapplied from `sort` state).
    my $new_cols = [ { label => 'Fruit', width => 140 }, { label => 'Qty', width => 60, sort => 'numeric' } ];
    my $new_lv2  = Uji::list_view( sortable => 1, reorderable => 1, on_sort => $on_sort, columns => $new_cols, rows => $new_lv->rows );
    $recon->patch( $new_lv, $new_lv2, $drv );
    is $widths->( $pr->{hwnd} ), '140,60', 'column reconcile applies new widths';
    is $coltext->( $pr->{hwnd}, 1 ), "Qty ▼", 'column reconcile re-stamps the sort glyph';

    # Now drag Qty to the front, then click the FIRST VISIBLE header (still Qty, model 1).
    {
        my $hdr = Uji::Driver::Win32::SendMessageW( $pr->{hwnd}, 0x101F, 0, 0 );
        PostMessageW( $hdr, 0x0201, 1, 155 | ( 8 << 16 ) );    # WM_LBUTTONDOWN inside Qty (spans 140-200)
        for my $x ( 110, 60, 30, 25 ) {
            PostMessageW( $hdr, 0x0200, 1, $x | ( 8 << 16 ) );    # WM_MOUSEMOVE leftwards
            for ( 1 .. 4 ) { $drv->poll_events }
        }
        PostMessageW( $hdr, 0x0202, 0, 22 | ( 8 << 16 ) );    # WM_LBUTTONUP
        for ( 1 .. 50 ) { $drv->poll_events }
    }
    is $drv->lv_column_order( $pr->{hwnd}, 2 ), [ 1, 0 ], 'header drag reorders to [1,0]';
    is $widths->( $pr->{hwnd} ), '140,60', 'widths survive the header drag';

    $pnotify->(1);    # native reports the clicked column by its MODEL identity: a real click on
                      # Qty (now displayed at the front) carries iSubItem == MODEL column 1
    my $m3 = $chan->size ? $chan->get : undef;
    is $m3->{column}, 1, 'post-drag LVN_COLUMNCLICK reports the MODEL column (Qty), not the visual slot';
    is $m3->{dir},    'asc', 'dragged Qty click sorts ascending';
    is $coltext->( $pr->{hwnd}, 1 ), "Qty ▲", 'glyph lands on the sorted MODEL column (displays at visual slot 0)';
    is $coltext->( $pr->{hwnd}, 0 ), 'Fruit', 'the other model column header stays plain';
    is $widths->( $pr->{hwnd} ), '140,60', 'widths survive sorting a dragged list';
    is $drv->lv_column_order( $pr->{hwnd}, 2 ), [ 1, 0 ], 'column order survives sorting a dragged list';
    my $internal = $drv->_get_registry_record( $pilv->id )->{listview}{sort};
    is $internal, { col => 1, dir => 'asc' }, 'driver sort state tracks the MODEL column + dir';
    Uji::Driver::Win32::SendMessageW( $pwr->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
}

#  14. Per-column alignment
{
    my $colfmt = sub ($hwnd, $col) {
        my $lvcol = pack 'L< l< l< x4 q< l< l< l< l< l< l< l< L< q< l< x4',
            0x0001, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0;    # LVCF_FMT
        my $sb = Affix::malloc( length $lvcol );
        Affix::memcpy( $sb, $lvcol, length $lvcol );
        Uji::Driver::Win32::SendMessageW( $hwnd, 0x105F, $col, Affix::address($sb) );    # LVM_GETCOLUMNW
        my $raw = Affix::raw( $sb, length $lvcol );
        my $fmt = unpack( 'l<', substr( $raw, 4, 4 ) );    # LVCOLUMN.fmt at offset 4
        Affix::free($sb);
        return $fmt;
    };
    my $alv = Uji::list_view(
        columns => [
            { label => 'L', width => 70, align => 'left' },
            { label => 'C', width => 70, align => 'center' },
            { label => 'R', width => 70, align => 'right' },
        ],
        rows => [ [ '1', '2', '3' ] ],
    );
    my $acol = Uji::column( padding => 8, children => [$alv] );
    my $awin = Uji::window( id => 'lv_align', title => 'ListView Align Test', w => 300, h => 240, child => $acol );
    $drv->mount($awin);
    $layout->compute( $awin, 0, 0, 300, 240 );
    $drv->mount_children($awin);
    $move_all->($awin);
    my $ar = $drv->_get_registry_record( $alv->id );
    ok $ar && $ar->{hwnd}, 'aligned list_view mounts';
    is $colfmt->( $ar->{hwnd}, 0 ) & 0x0003, 0, 'align left maps to LVCFMT_LEFT (0)';
    is $colfmt->( $ar->{hwnd}, 1 ) & 0x0003, 2, 'align center maps to LVCFMT_CENTER (2)';
    is $colfmt->( $ar->{hwnd}, 2 ) & 0x0003, 1, 'align right maps to LVCFMT_RIGHT (1)';
    my $awr = $drv->_get_registry_record( $awin->id );
    Uji::Driver::Win32::SendMessageW( $awr->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
}

#  15. MODEL-convention: sort a reordered 4-col list where the clicked (MODEL) column
#        does NOT display at its model slot. Native LVN_COLUMNCLICK.iSubItem is the MODEL
#        identity; the glyph must follow the sorted MODEL column wherever it displays — never
#        shift a second time onto whatever column now occupies the clicked visual slot.
{
    my $mcoltext = sub ($hwnd, $col) {    # LVM_GETCOLUMNW is MODEL-indexed
        my $buf = Affix::malloc(256);
        my $lvcol = pack 'L< l< l< x4 q< l< l< l< l< l< l< l< L< q< l< x4',
            0x0004, 0, 0, Affix::address($buf), 256, 0, 0, 0, 0, 0, 0, 0, 0, 0;    # LVCF_TEXT
        my $sb = Affix::malloc( length $lvcol );
        Affix::memcpy( $sb, $lvcol, length $lvcol );
        Uji::Driver::Win32::SendMessageW( $hwnd, 0x105F, $col, Affix::address($sb) );    # LVM_GETCOLUMNW
        Affix::free($sb);
        my $txt = decode( 'UTF-16LE', Affix::raw( $buf, 256 ) );
        $txt =~ s/\x00.*//s;
        Affix::free($buf);
        return $txt;
    };
    my ($mcol, $mio) = (undef, undef);    # captured by the construction-time on_sort (there is NO set_on_sort setter)
    my $r4lv = Uji::list_view(
        sortable    => 1,
        reorderable => 1,
        on_sort     => sub ($c, $d) { $mcol = $c; $mio  = $d; { type => 'SORT4', column => $c, dir => $d } },
        columns     => [
            { label => 'Fruit', width => 90 },
            { label => 'Qty',   width => 50, sort => 'numeric' },
            { label => 'Unit',  width => 50 },
            { label => 'Price', width => 60, sort => 'numeric' },
        ],
        rows        => [
            [ 'Apples', '3', 'ea', '1.50' ],
            [ 'Bananas', '5', 'lb', '0.99' ],
            [ 'Cherries', '1', 'oz', '6.00' ],
        ],
    );
    my $r4col = Uji::column( padding => 4, children => [$r4lv] );
    my $r4win = Uji::window( id => 'lv_model4', title => 'ListView MODEL-convention', w => 300, h => 240, child => $r4col );
    $drv->mount($r4win);
    $layout->compute( $r4win, 0, 0, 300, 240 );
    $drv->mount_children($r4win);
    $move_all->($r4win);
    my $r4r = $drv->_get_registry_record( $r4lv->id );
    ok $r4r && $r4r->{hwnd}, 'model-4 list_view mounts';

    # Native reorder [0,1,3,2]: Price (MODEL 3) moves up one — it now displays at visual slot 2,
    # while Unit (MODEL 2) is pushed to visual slot 3. This is the asymmetric 4-col layout from
    # the original report, reproduced via the native LVM_SETCOLUMNORDERARRAY message.
    my $arr = pack 'l<l<l<l<', 0, 1, 3, 2;
    my $ab  = Affix::malloc(16);
    Affix::memcpy( $ab, $arr, 16 );
    Uji::Driver::Win32::SendMessageW( $r4r->{hwnd}, 0x103A, 4, Affix::address($ab) );
    Affix::free($ab);
    is $drv->lv_column_order( $r4r->{hwnd}, 4 ), [ 0, 1, 3, 2 ], 'native column order [0,1,3,2] persists in the driver';

    # The user clicks the Price header where his eyes see it — visual slot 2, which native reports
    # as iSubItem == MODEL 3 (Price). The sort AND the glyph must both follow Price, not Unit.
    $drv->list_view_click_column( $r4lv, 3 );    # click MODEL 3 (Price) wherever the native header reports it

    my $r4winr = $drv->_get_registry_record( $r4win->id );
    Uji::Driver::Win32::SendMessageW( $r4winr->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
}

#  clean up
Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
#
done_testing;
