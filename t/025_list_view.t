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

# ── List-view constants ──────────────────────────────────────────────────────
my $LVM_GETITEMCOUNT     = 0x1004;
my $LVM_GETITEMSTATE     = 0x102C;
my $LVM_GETITEMTEXTW     = 0x1073;
my $LVM_INSERTCOLUMNW    = 0x1061;
my $LVM_SETITEMSTATE     = 0x102B;
my $LVIS_SELECTED        = 0x0002;
my $LVN_ITEMCHANGEDW     = -102;
my $chan                 = Acme::Parataxis::Channel->new( capacity => 1024 );
my $drv                  = Uji::Driver::Win32->new;
$drv->init($chan);

# ── Set up a window containing a list_view ───────────────────────────────────
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

# ── 1. Class name is SysListView32 ───────────────────────────────────────────
my $cls = '';
{
    my $buf = Affix::malloc(128);
    Uji::Driver::Win32::GetClassNameW( $lr->{hwnd}, $buf, 64 );
    $cls = decode( 'UTF-16LE', Affix::raw( $buf, 128 ) );
    $cls =~ s/\x00.*//s;
    Affix::free($buf);
}
is $cls, 'SysListView32', 'mounts SysListView32';

# ── 2. Row count: 3 mounted rows ─────────────────────────────────────────────
my $count = Uji::Driver::Win32::SendMessageW( $lr->{hwnd}, $LVM_GETITEMCOUNT, 0, 0 );
is $count, 3, 'LVM_GETITEMCOUNT returns 3 rows';

# ── 3. Column widths match the model ─────────────────────────────────────────
my $cw0 = Uji::Driver::Win32::SendMessageW( $lr->{hwnd}, 0x101D, 0, 0 );    # LVM_GETCOLUMNWIDTH
my $cw1 = Uji::Driver::Win32::SendMessageW( $lr->{hwnd}, 0x101D, 1, 0 );
is $cw0, 140, 'column 0 width is 140';
is $cw1, 70,  'column 1 width is 70';
is Uji::Driver::Win32::SendMessageW( $lr->{hwnd}, 0x101D, 2, 0 ), 0, 'no third column exists';

# ── 4. UTF-8 cell round-trips through LVM_GETITEMTEXTW ───────────────────────
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

# ── 5. Mount selection: value='b' selects row 1 ──────────────────────────────
my $st0 = Uji::Driver::Win32::SendMessageW( $lr->{hwnd}, $LVM_GETITEMSTATE, 0, $LVIS_SELECTED );
my $st1 = Uji::Driver::Win32::SendMessageW( $lr->{hwnd}, $LVM_GETITEMSTATE, 1, $LVIS_SELECTED );
ok !( $st0 & $LVIS_SELECTED ), 'row 0 is not selected';
ok $st1 & $LVIS_SELECTED,      'row 1 (value b) is selected at mount';

# ── 6. LVN_ITEMCHANGED: simulate a click on row 2 (value='c') ────────────────
{
    my $nm = "\0" x 64;
    substr( $nm, 0, 8 )  = pack( 'q<', $lr->{hwnd} );      # NMHDR.hwndFrom
    substr( $nm, 8, 8 )  = pack( 'q<', 0 );                # idFrom
    substr( $nm, 16, 4 ) = pack( 'l<', $LVN_ITEMCHANGEDW );    # code
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

# ── 7. Focus-only notification (no LVIS_SELECTED) is ignored ─────────────────
{
    my $nm = "\0" x 64;
    substr( $nm, 0, 8 )  = pack( 'q<', $lr->{hwnd} );
    substr( $nm, 16, 4 ) = pack( 'l<', $LVN_ITEMCHANGEDW );
    substr( $nm, 24, 4 ) = pack( 'l<', 1 );
    substr( $nm, 32, 4 ) = pack( 'L<', 0x0001 );    # LVIS_FOCUSED only
    my $nmbuf = Affix::malloc(64);
    Affix::memcpy( $nmbuf, $nm, 64 );
    $chan->get() while $chan->size;
    Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x004E, 0, Affix::address($nmbuf) );
    Affix::free($nmbuf);
    ok !$chan->size, 'focus-only LVN_ITEMCHANGED is ignored';
}

# ── 8. set_prop('value'): move selection to 'a' (row 0) ──────────────────────
{
    $drv->set_prop( $lv->id, 'value', 'a' );
    my $s0 = Uji::Driver::Win32::SendMessageW( $lr->{hwnd}, $LVM_GETITEMSTATE, 0, $LVIS_SELECTED );
    my $s1 = Uji::Driver::Win32::SendMessageW( $lr->{hwnd}, $LVM_GETITEMSTATE, 1, $LVIS_SELECTED );
    ok $s0 & $LVIS_SELECTED, 'set_prop value selects row 0';
    ok !( $s1 & $LVIS_SELECTED ), 'set_prop value clears row 1';
    $chan->get() while $chan->size;    # and no echo on_select from the programmatic select
    ok !$chan->size, 'programmatic selection produces no on_select echo';
}

# ── 9. Reconciler: change rows (add a row 'd') + change value ('d') ──────────
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

# ── 10. Multi-select: arrayref value + arrayref on_select payload ────────────
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
    substr( $nm, 16, 4 ) = pack( 'l<', $LVN_ITEMCHANGEDW );
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

# ─── clean up ───
Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
#
done_testing;