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

# ── Toolbar constants ──────────────────────────────────────────────────────
my $TB_BUTTONSTRUCTSIZE = 0x041E;                                              # WM_USER + 30
my $TB_ADDBUTTONSW      = 0x0444;                                              # WM_USER + 68
my $TB_ADDSTRINGW       = 0x044D;                                              # WM_USER + 77
my $TB_AUTOSIZE         = 0x0421;                                              # WM_USER + 33
my $TB_BUTTONCOUNT      = 0x0418;                                              # WM_USER + 24
my $TB_DELETEBUTTON     = 0x0416;                                              # WM_USER + 22
my $TB_ISBUTTONENABLED  = 0x0409;                                              # WM_USER + 9
my $TB_ISBUTTONCHECKED  = 0x040A;                                              # WM_USER + 10
my $chan                = Acme::Parataxis::Channel->new( capacity => 1024 );
my $drv                 = Uji::Driver::Win32->new;
$drv->init($chan);
my $clicked_id = undef;
my $toolbar    = Uji::toolbar(
    buttons => [
        { label => 'New',    id => 'new' },
        { label => 'Open',   id => 'open' },
        { label => '',       id => 'sep1', separator => 1 },
        { label => 'Save',   id => 'save', checked   => 1 },
        { label => 'Delete', id => 'del' },
    ],
    on_click => sub ($id) { { type => 'TB_CLICK', id => $id } },
);
my $col   = Uji::column( padding => 8, children => [$toolbar] );
my $vtree = Uji::window( id => 'tb_main', title => 'Toolbar Test', w => 600, h => 400, child => $col );
$drv->mount($vtree);
my $layout = Uji::Layout->new( driver => $drv );
$layout->compute( $vtree, 0, 0, 600, 400 );
$drv->mount_children($vtree);
my $move_all;
$move_all = sub {
    my ($n) = @_;
    $drv->move_widget( $n->id, $n->bx, $n->by, $n->bw, $n->bh ) unless $n->type eq 'window';
    $move_all->($_) for @{ $n->children };
};
$move_all->($vtree);
my $wrb = $drv->_get_registry_record( $vtree->id );
my $tr  = $drv->_get_registry_record( $toolbar->id );
ok $tr && $tr->{hwnd}, 'toolbar has a registry record with a real HWND';

# ── 1. Class name is ToolbarWindow32 ──────────────────────────────────────
my $cls = '';
{
    my $buf = Affix::malloc(128);
    Uji::Driver::Win32::GetClassNameW( $tr->{hwnd}, $buf, 64 );
    $cls = decode( 'UTF-16LE', Affix::raw( $buf, 128 ) );
    $cls =~ s/\x00.*//s;
    Affix::free($buf);
}
is $cls, 'ToolbarWindow32', 'mounts ToolbarWindow32';

# ── 2. Button count: 4 buttons + 1 separator = 5 ─────────────────────────
my $count = Uji::Driver::Win32::SendMessageW( $tr->{hwnd}, $TB_BUTTONCOUNT, 0, 0 );
is $count, 5, 'TB_BUTTONCOUNT returns 5';

# ── 3. Button states: "Save" (id=save) should be checked ─────────────────
# Check buttons by idCommand mapping.  We find the "save" button's command
# via the registry's toolbar->{by_cmd} map.
{
    my $by_cmd = $tr->{toolbar}{by_cmd};
    my $save_cmd;
    for my $cmd ( keys %$by_cmd ) {
        $save_cmd = $cmd if $by_cmd->{$cmd}{id} eq 'save';
    }
    ok defined $save_cmd, 'found cmd id for Save button';

    # TB_ISBUTTONCHECKED / TB_ISBUTTONENABLED take idCommand in wParam (TN_TB)
    my $checked = Uji::Driver::Win32::SendMessageW( $tr->{hwnd}, $TB_ISBUTTONCHECKED, $save_cmd, 0 );
    ok $checked, 'Save button is TBSTATE_CHECKED';
    my $enabled = Uji::Driver::Win32::SendMessageW( $tr->{hwnd}, $TB_ISBUTTONENABLED, $save_cmd, 0 );
    ok $enabled, 'Save button is TBSTATE_ENABLED';
}

# ── 4. WM_COMMAND dispatch: simulate clicking "Open" ──────────────────────
{
    my $by_cmd = $tr->{toolbar}{by_cmd};
    my $open_cmd;
    for my $cmd ( keys %$by_cmd ) {
        $open_cmd = $cmd if $by_cmd->{$cmd}{id} eq 'open';
    }
    ok defined $open_cmd, 'found cmd id for Open button';
    $chan->get() while $chan->size;

    # WM_COMMAND: LOWORD(wParam) = command id, HIWORD = BN_CLICKED (0)
    # Affix trampoline quirk: SendMessageW re-enters the XS wndproc bridge which
    # sometimes invokes an internal Perl sub with an undef; suppress the harmless
    # warning (see poll_events, line ~910 in Win32.pm).
    no warnings 'uninitialized';
    Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x0111, $open_cmd, 0 );
    my $msg = $chan->size ? $chan->get : undef;
    ok $msg, 'Open button click dispatches on_click';
    is $msg->{type}, 'TB_CLICK', 'channel message type is TB_CLICK';
    is $msg->{id},   'open',     'channel message id is open';
}

# ── 5. Reconciler: update buttons (add button, remove separator) ──────────
{
    my $recon  = Uji::Reconciler->new;
    my $old_tb = Uji::toolbar( id => $toolbar->id, buttons => $toolbar->buttons, on_click => $toolbar->on_click, );
    $old_tb->set_id( $toolbar->id );
    $layout->compute( $old_tb, $toolbar->bx, $toolbar->by, $toolbar->bw, $toolbar->bh );
    my $new_tb = Uji::toolbar(
        id       => $toolbar->id,
        buttons  => [ { label => 'New', id => 'new' }, { label => 'Save', id => 'save' }, { label => 'Print', id => 'print' }, ],
        on_click => $toolbar->on_click,
    );
    $layout->compute( $new_tb, $toolbar->bx, $toolbar->by, $toolbar->bw, $toolbar->bh );
    $recon->patch( $old_tb, $new_tb, $drv );
    my $count2 = Uji::Driver::Win32::SendMessageW( $tr->{hwnd}, $TB_BUTTONCOUNT, 0, 0 );
    is $count2, 3, 'reconciled buttons (removed sep + del, added Print) -> count 3';

    # Verify new Print button was added by checking it's in the cmd map
    my $by_cmd2   = $tr->{toolbar}{by_cmd};
    my $has_print = 0;
    for my $cmd ( keys %$by_cmd2 ) {
        $has_print = 1 if $by_cmd2->{$cmd}{id} eq 'print';
    }
    ok $has_print, 'Print button is present after reconciliation';
}

# ─── clean up ───
Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
#
done_testing;
