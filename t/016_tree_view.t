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

#  Tree-view constants
my $TVM_INSERTITEMW   = 0x1132;
my $TVM_DELETEITEM    = 0x1101;
my $TVM_EXPAND        = 0x1102;
my $TVM_GETCOUNT      = 0x1105;
my $TVM_GETNEXTITEM   = 0x110A;
my $TVM_SELECTITEM    = 0x110B;
my $TVM_GETITEMW      = 0x113E;                                              # TV_FIRST + 62 (the W variant of +12)
my $TVM_GETITEMSTATE  = 0x1127;                                              # TV_FIRST + 39
my $TVM_ENSUREVISIBLE = 0x1114;
my $TVE_EXPAND        = 0x0002;
my $TVGN_ROOT         = 0x0;
my $TVGN_NEXT         = 0x1;
my $TVGN_CHILD        = 0x4;
my $TVIS_SELECTED     = 0x2;
my $TVIS_EXPANDED     = 0x20;
my $TVN_SELCHANGEDW   = -451;
my $chan              = Acme::Parataxis::Channel->new( capacity => 1024 );
my $drv               = Uji::Driver::Win32->new;
$drv->init($chan);

#  Set up a window containing a tree_view
#
# Alpha (expanded) ┬ A-one
#                   └ A-two
# Bravo ┬ B-one
#                  ├ B-two
#                  └ B-three
# Charlie
my $tree = Uji::tree_view(
    value => 'b1',
    nodes => [
        { value => 'a', label => 'Alpha', children => [ { value => 'a1', label => 'A-one' }, { value => 'a2', label => 'A-two' }, ] },
        {   value    => 'b',
            label    => 'Bravo',
            children => [ { value => 'b1', label => 'B-one' }, { value => 'b2', label => 'B-two' }, { value => 'b3', label => 'B-three' }, ]
        },
        { value => 'c', label => 'Charlie' },
    ],
    expanded  => ['a'],
    on_select => sub ($v) { { type => 'SELECT', value => $v } },
);
my $col   = Uji::column( padding => 8, children => [$tree] );
my $vtree = Uji::window( id => 'tv_main', title => 'TreeView Test', w => 320, h => 400, child => $col );
$drv->mount($vtree);
my $layout = Uji::Layout->new( driver => $drv );
$layout->compute( $vtree, 0, 0, 320, 400 );
$drv->mount_children($vtree);

# Position every widget (tree_view + status text inside any container).
my $move_all;
$move_all = sub {
    my ($n) = @_;
    $drv->move_widget( $n->id, $n->bx, $n->by, $n->bw, $n->bh ) unless $n->type eq 'window';
    $move_all->($_) for @{ $n->children };
};
$move_all->($vtree);
my $wrb = $drv->_get_registry_record( $vtree->id );
my $tr  = $drv->_get_registry_record( $tree->id );
ok $tr && $tr->{hwnd}, 'tree_view has a registry record with a real HWND';

#  1. Class name is SysTreeView32
my $cls = '';
{
    my $buf = Affix::malloc(128);
    Uji::Driver::Win32::GetClassNameW( $tr->{hwnd}, $buf, 64 );
    $cls = decode( 'UTF-16LE', Affix::raw( $buf, 128 ) );
    $cls =~ s/\x00.*//s;
    Affix::free($buf);
}
is $cls, 'SysTreeView32', 'mounts SysTreeView32';

#  2. Item count: 3 root + 2 under A + 3 under B = 8
my $count = Uji::Driver::Win32::SendMessageW( $tr->{hwnd}, $TVM_GETCOUNT, 0, 0 );
is $count, 8, 'TVM_GETCOUNT returns 8 items';

#  3. Expanded item has TVIS_EXPANDED
my $root_h  = Uji::Driver::Win32::SendMessageW( $tr->{hwnd}, $TVM_GETNEXTITEM, $TVGN_ROOT, 0 );
my $alpha_h = $root_h;                                                                                   # the first root item IS Alpha
my $bravo_h = Uji::Driver::Win32::SendMessageW( $tr->{hwnd}, $TVM_GETNEXTITEM, $TVGN_NEXT, $alpha_h );
ok $alpha_h, 'first root child (Alpha) handle resolved';
my $exp_st = Uji::Driver::Win32::SendMessageW( $tr->{hwnd}, $TVM_GETITEMSTATE, $alpha_h, $TVIS_EXPANDED );
ok $exp_st & $TVIS_EXPANDED, 'Alpha node is expanded';

#  4. Selection: B-one is selected per model value='b1'
my $bone_h = Uji::Driver::Win32::SendMessageW( $tr->{hwnd}, $TVM_GETNEXTITEM, $TVGN_CHILD, $bravo_h );
ok $bone_h, 'Bravo first child (B-one) handle resolved';
my $sel_st = Uji::Driver::Win32::SendMessageW( $tr->{hwnd}, $TVM_GETITEMSTATE, $bone_h, $TVIS_SELECTED );
ok $sel_st & $TVIS_SELECTED, 'B-one is selected as per model value';

#  5. lParam round-trip: B-one's lParam == 4 (the slot index)
{
    my $bytes = pack( 'L< x4 q< L< L< q< l< l< l< l< q<', 0x4, $bone_h, 0, 0, 0, 0, 0, 0, 0, 0 );    # TVIF_PARAM mask, hItem
    my $buf   = Affix::malloc( length $bytes );
    Affix::memcpy( $buf, $bytes, length $bytes );
    Uji::Driver::Win32::SendMessageW( $tr->{hwnd}, $TVM_GETITEMW, 0, Affix::address($buf) );
    my $raw = Affix::raw( $buf, 56 );
    Affix::free($buf);
    my $lp = unpack( 'q<', substr( $raw, 48, 8 ) );
    is $lp, 4, 'B-one lParam round-trips to slot 4';
}

#  6. TVN_SELCHANGED: simulate a click on slot 7 (value='c', Charlie)
{
    my $nm = "\0" x 152;
    substr( $nm, 0, 8 )   = pack( 'q<', $tr->{hwnd} );                                      # NMHDR.hwndFrom
    substr( $nm, 8, 8 )   = pack( 'q<', 0 );                                                # idFrom
    substr( $nm, 16, 4 )  = pack( 'l<', $TVN_SELCHANGEDW );                                 # code
    substr( $nm, 24, 4 )  = pack( 'L<', 0 );                                                # action (TVC_UNKNOWN)
    substr( $nm, 136, 8 ) = pack( 'q<', 7 );                                                # itemNew.lParam = slot 7 = Charlie
    my $nmbuf = Affix::malloc(160);
    Affix::memcpy( $nmbuf, $nm, 152 );
    $chan->get() while $chan->size;                                                         # clear any stale messages
    Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x004E, 0, Affix::address($nmbuf) );    # WM_NOTIFY
    Affix::free($nmbuf);
    my $msg = $chan->size ? $chan->get : undef;
    ok $msg, 'TVN_SELCHANGED dispatches on_select';
    is $msg->{type},  'SELECT', 'channel message type is SELECT';
    is $msg->{value}, 'c',      'channel message value is Charlie';
}

#  7. set_prop('value'): move selection to 'a1' (A-one)
{
    $drv->set_prop( $tree->id, 'value', 'a1' );
    my $aone_h = Uji::Driver::Win32::SendMessageW( $tr->{hwnd}, $TVM_GETNEXTITEM,  $TVGN_CHILD, $alpha_h );
    my $st     = Uji::Driver::Win32::SendMessageW( $tr->{hwnd}, $TVM_GETITEMSTATE, $aone_h,     $TVIS_SELECTED );
    ok $st & $TVIS_SELECTED, 'set_prop value moves selection to A-one';
}

#  8. Reconciler: change nodes (add a root item 'd') + change value
{
    my $recon    = Uji::Reconciler->new;
    my $old_tree = Uji::tree_view( value => 'a1', nodes => $tree->nodes, expanded => ['a'], );
    $old_tree->set_id( $tree->id );
    $layout->compute( $old_tree, $tree->bx, $tree->by, $tree->bw, $tree->bh );
    my @new_nodes = @{ $tree->nodes };
    push @new_nodes, { value => 'd', label => 'Delta' };
    my $new_tree = Uji::tree_view( value => 'c', nodes => \@new_nodes, expanded => [ 'a', 'b' ], );
    $layout->compute( $new_tree, $tree->bx, $tree->by, $tree->bw, $tree->bh );
    $recon->patch( $old_tree, $new_tree, $drv );
    my $count2 = Uji::Driver::Win32::SendMessageW( $tr->{hwnd}, $TVM_GETCOUNT, 0, 0 );
    is $count2, 9, 'reconciled nodes change (add Delta) -> count 9';

    # Repopulate invalidated every old handle; re-fetch: root -> Alpha -> Bravo -> Charlie.
    my $new_root_h = Uji::Driver::Win32::SendMessageW( $tr->{hwnd}, $TVM_GETNEXTITEM,  $TVGN_ROOT, 0 );
    my $bravo2_h   = Uji::Driver::Win32::SendMessageW( $tr->{hwnd}, $TVM_GETNEXTITEM,  $TVGN_NEXT, $new_root_h );
    my $charlie_h  = Uji::Driver::Win32::SendMessageW( $tr->{hwnd}, $TVM_GETNEXTITEM,  $TVGN_NEXT, $bravo2_h );
    my $cst        = Uji::Driver::Win32::SendMessageW( $tr->{hwnd}, $TVM_GETITEMSTATE, $charlie_h, $TVIS_SELECTED );
    ok $cst & $TVIS_SELECTED, 'reconciled value change moves selection to Charlie';
}

#  clean up
Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
#
done_testing;
