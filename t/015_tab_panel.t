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

# Widget-queue batch 2 (part 2): TabPanel. Real-HWND test: verifies the native strip (SysTabControl32
# + TCM_INSERTITEMW population), sibling-mounted panel contents sharing one body rect, active-panel
# visibility toggling, WM_NOTIFY/TCN_SELCHANGE routing to on_select, set_prop index/panels, and the
# reconciler diff.
my $chan = Acme::Parataxis::Channel->new( capacity => 1024 );
my $drv  = Uji::Driver::Win32->new;
$drv->init($chan);

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

sub is_visible {
    my ($hwnd) = @_;
    return ( Uji::Driver::Win32::GetWindowLongW( $hwnd, -16 ) & 0x10000000 ) ? 1 : 0;    # GWL_STYLE & WS_VISIBLE
}
my $pa = Uji::column( padding => 6, children => [ Uji::button( label => 'General' ),  Uji::text('general pane') ] );
my $pb = Uji::column( padding => 6, children => [ Uji::button( label => 'Advanced' ), Uji::text('advanced pane') ] );
my $tp = Uji::tab_panel(
    panels    => [ { title => 'General', child => $pa }, { title => 'Advanced', child => $pb } ],
    index     => 0,
    on_select => sub ($i) { { type => 'TAB', i => $i } },
);
my $col   = Uji::column( padding => 8, children => [$tp] );
my $vtree = Uji::window( id => 'main', title => 't', w => 320, h => 420, child => $col );
$drv->mount($vtree);
my $layout = Uji::Layout->new( driver => $drv );
$layout->compute( $vtree, 0, 0, 320, 420 );
$drv->mount_children($vtree);
my $wrb = $drv->_get_registry_record( $vtree->id );
my $tpr = $drv->_get_registry_record( $tp->id );
ok $tpr && $tpr->{hwnd}, 'tab_panel has a registry record with the native tab HWND';
is class_of( $tpr->{hwnd} ), 'SysTabControl32', 'the strip is a native tab control';
is $tpr->{index},            0,                 'record seeded with the model index';
my $gar = $drv->_get_registry_record( $pa->children->[0]->id );
my $abr = $drv->_get_registry_record( $pb->children->[0]->id );
is $gar->{parent_hwnd}, $wrb->{hwnd}, 'panel A content parented to the app window (sibling mount)';
is $abr->{parent_hwnd}, $wrb->{hwnd}, 'panel B content parented to the app window (sibling mount)';
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

#  the strip row count, and the shared body rect under it
is Uji::Driver::Win32::SendMessageW( $tpr->{hwnd}, 0x1304, 0, 0 ), 2, 'the strip holds one tab per panel';          # TCM_GETITEMCOUNT
is Uji::Driver::Win32::SendMessageW( $tpr->{hwnd}, 0x130B, 0, 0 ), 0, 'strip selection matches the model index';    # TCM_GETCURSEL
is $tp->by + 25, $pa->by, 'panel bodies sit below the native strip';
is( [ $pa->bx, $pa->by, $pa->bw, $pa->bh ], [ $pb->bx, $pb->by, $pb->bw, $pb->bh ], 'all panels share one body rect' );

#  only the active panel's subtree is shown
ok is_visible( $gar->{hwnd} ),  'active panel (A) content is visible';
ok !is_visible( $abr->{hwnd} ), 'inactive panel (B) content is hidden';
my $atr = $drv->_get_registry_record( $pa->children->[1]->id );                                                     # the 'general pane' text
my $btr = $drv->_get_registry_record( $pb->children->[1]->id );                                                     # the 'advanced pane' text
ok is_visible( $gar->{hwnd} )  && is_visible( $atr->{hwnd} ),  'nested content of the active panel stays visible';
ok !is_visible( $abr->{hwnd} ) && !is_visible( $btr->{hwnd} ), 'nested content of the inactive panel is hidden';

#  WM_NOTIFY / TCN_SELCHANGE: a user tab click routes on_select and flips visibility
$chan->get() while $chan->size;
{
    # A real click updates the native selection AND posts TCN_SELCHANGE (code -551) to the host
    # window, preceded by a TCN_SELCHANGING (-552) which the driver must ignore.
    my $nm = Affix::malloc(24);                                                          # NMHDR: hwndFrom(8) idFrom(8) code(4) + pad(4)
    Affix::memcpy( $nm, pack( 'Q<2 l<', $tpr->{hwnd}, 0, -552 ) . "\x00" x 4, 24 );      # TCN_SELCHANGING (ignored)
    Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x004E, 0, Affix::address($nm) );    # WM_NOTIFY to the host
    free($nm);
    is $chan->size, 0, 'TCN_SELCHANGING does not dispatch on_select';
    Uji::Driver::Win32::SendMessageW( $tpr->{hwnd}, 0x130C, 1, 0 );                      # TCM_SETCURSEL (1)
    my $nm2 = Affix::malloc(24);
    Affix::memcpy( $nm2, pack( 'Q<2 l<', $tpr->{hwnd}, 0, -551 ) . "\x00" x 4, 24 );     # TCN_SELCHANGE (real comctl code)
    Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x004E, 0, Affix::address($nm2) );
    free($nm2);
    my $msg = $chan->size ? $chan->get : undef;
    ok $msg && $msg->{type} eq 'TAB' && $msg->{i} == 1, 'TCN_SELCHANGE dispatched on_select with the new index';
    is $tpr->{index}, 1, 'record index follows the user tab click';
    ok !is_visible( $gar->{hwnd} ), 'panel A hidden after switching';
    ok is_visible( $abr->{hwnd} ),  'panel B shown after switching';
}

#  set_prop index: programmatic switch keeps record, strip and visibility in sync
$drv->set_prop( $tp->id, 'index', 0 );
is $tpr->{index},                                                  0, 'set_prop index updates the record';
is Uji::Driver::Win32::SendMessageW( $tpr->{hwnd}, 0x130B, 0, 0 ), 0, 'set_prop index moves the native selection';    # TCM_GETCURSEL
ok is_visible( $gar->{hwnd} ),  'panel A visible again after set_prop';
ok !is_visible( $abr->{hwnd} ), 'panel B hidden again after set_prop';

#  reconciler: index + panels diffs route to set_prop (bounds first, child loop second)
{
    my $recon = Uji::Reconciler->new;
    my $old   = Uji::tab_panel(
        panels => [ { title => 'General', child => Uji::column( children => [] ) }, { title => 'Advanced', child => Uji::column( children => [] ) } ],
        index  => 0
    );
    $old->set_id( $tp->id );
    $layout->compute( $old, $tp->bx, $tp->by, $tp->bw, $tp->bh );    # runtime order: render computes bounds first
    my $new = Uji::tab_panel(
        panels => [
            { title => 'General',  child => Uji::column( children => [] ) },
            { title => 'Network',  child => Uji::column( children => [] ) },
            { title => 'Advanced', child => Uji::column( children => [] ) },
        ],
        index => 2
    );
    $layout->compute( $new, $tp->bx, $tp->by, $tp->bw, $tp->bh );
    $recon->patch( $old, $new, $drv );
    is $tpr->{index}, 2, 'reconciler index diff routes to set_prop';
    is Uji::Driver::Win32::SendMessageW( $tpr->{hwnd}, 0x130B, 0, 0 ), 2, 'reconciled strip selection moved';           # TCM_GETCURSEL
    is Uji::Driver::Win32::SendMessageW( $tpr->{hwnd}, 0x1304, 0, 0 ), 3, 'reconciled panels repopulated the strip';    # TCM_GETITEMCOUNT
}
Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x0010, 0, 0 );                                                         # WM_CLOSE
#
done_testing;
