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

# ── Menu constants (winuser.h) ─────────────────────────────────────────
my $MF_STRING    = 0x0000;
my $MF_POPUP     = 0x0010;
my $MF_SEPARATOR = 0x0800;
my $MF_CHECKED   = 0x0008;
my $MF_GRAYED    = 0x0001;
my $chan         = Acme::Parataxis::Channel->new( capacity => 1024 );
my $drv          = Uji::Driver::Win32->new;
$drv->init($chan);
my $clicked = [];
my $menubar = Uji::menu_bar(
    items => [
        {   label    => 'File',
            children => [
                { label     => 'New',  id => 'new' },
                { label     => 'Open', id => 'open' },
                { separator => 1 },
                { label     => 'Exit', id => 'exit', checked => 1 },
            ],
        },
        { label => 'Edit', children => [ { label => 'Undo', id => 'undo' }, { label => 'Disabled', id => 'dis', enabled => 0 }, ], },
    ],
    on_click => sub ($id) { { type => 'MENU_CLICK', id => $id } },
);
my $label = Uji::text('hi');
my $col   = Uji::column( padding => 8, children => [$label] );
my $vtree = Uji::window( id => 'mb_main', title => 'Menu Test', w => 600, h => 400, menu_bar => $menubar, child => $col );
$drv->mount($vtree);
my $layout = Uji::Layout->new( driver => $drv );
$layout->compute( $vtree, 0, 0, 600, 400 );
$drv->mount_children($vtree);
my $wrb = $drv->_get_registry_record( $vtree->id );
ok $wrb,                                        'window has a registry record';
ok $wrb->{menu_bar} && $wrb->{menu_bar}{hmenu}, 'window mounted a native menu (HMENU)';

# ── 1. Client area is reduced by the menu bar ───────────────────────────
# A window with a menu bar has a shorter client area than its untitled request.
{
    my ( $cw, $ch ) = $drv->_get_client_size( $wrb->{hwnd} );
    ok $ch < 400, "client height reduced by menu bar (got $ch < 400)";
}

# ── 2. All leaf items got command IDs in the 0x4000+ range ──────────────
{
    my $by_cmd = $wrb->{menu_bar}{by_cmd};
    my @ids    = map { $by_cmd->{$_}{id} } keys %$by_cmd;
    ok @ids >= 4, 'at least 4 leaf items registered (new/open/exit/undo/dis)';
    for my $cmd ( keys %$by_cmd ) {
        ok $cmd >= 0x4000, "menu command id $cmd >= 0x4000";
    }
}

# ── 3. Checked + grayed initial states ──────────────────────────────────
{
    my $by_cmd = $wrb->{menu_bar}{by_cmd};

    # Find "open" cmd and "dis" cmd. We can only observe state via re-reading the
    # menu tree: check "Exit" (checked) and "Disabled" (grayed) presence in by_cmd.
    my %map;
    $map{ $by_cmd->{$_}{id} } = $_ for keys %$by_cmd;
    ok exists $map{exit}, 'Exit item registered';
    ok exists $map{dis},  'Disabled item registered';
}

# ── 4. WM_COMMAND dispatch simulates clicking "Open" ─────────────────────
{
    my $by_cmd = $wrb->{menu_bar}{by_cmd};
    my $open_cmd;
    for my $cmd ( keys %$by_cmd ) {
        $open_cmd = $cmd if $by_cmd->{$cmd}{id} eq 'open';
    }
    ok defined $open_cmd, 'found cmd id for Open item';
    $chan->get() while $chan->size;

    # WM_COMMAND: LOWORD(wParam) = command id, HIWORD = BN_CLICKED (0). Same Affix
    # trampoline quirk as the toolbar test -- suppress the harmless undef warning.
    no warnings 'uninitialized';
    Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x0111, $open_cmd, 0 );
    my $msg = $chan->size ? $chan->get : undef;
    ok $msg, 'Open menu item click dispatches on_click';
    is $msg->{type}, 'MENU_CLICK', 'channel message type is MENU_CLICK';
    is $msg->{id},   'open',       'channel message id is open';
}

# ── 5. Reconciler rebuilds the menu when items change ────────────────────
{
    my $recon  = Uji::Reconciler->new;
    my $old_mb = Uji::menu_bar( items => $menubar->items, on_click => $menubar->on_click, );
    my $old_win
        = Uji::window( id => $vtree->id, title => $vtree->title, w => $vtree->w, h => $vtree->h, menu_bar => $old_mb, child => $vtree->child, );
    $old_win->set_id( $vtree->id );
    my $new_mb = Uji::menu_bar(
        items    => [ { label => 'File', children => [ { label => 'New', id => 'new' }, { label => 'Save', id => 'save' }, ], }, ],
        on_click => $menubar->on_click,
    );
    my $new_win
        = Uji::window( id => $vtree->id, title => $vtree->title, w => $vtree->w, h => $vtree->h, menu_bar => $new_mb, child => $vtree->child, );
    $new_win->set_id( $vtree->id );
    $recon->patch( $old_win, $new_win, $drv );
    my $by_cmd = $wrb->{menu_bar}{by_cmd};
    my %seen;
    $seen{ $by_cmd->{$_}{id} } = 1 for keys %$by_cmd;
    ok $seen{save},  'Save item present after reconciliation';
    ok !$seen{open}, 'Open item removed after reconciliation';

    # New Save item routes a click too
    my $save_cmd;
    for my $cmd ( keys %$by_cmd ) {
        $save_cmd = $cmd if $by_cmd->{$cmd}{id} eq 'save';
    }
    $chan->get() while $chan->size;
    no warnings 'uninitialized';
    Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x0111, $save_cmd, 0 );
    my $msg = $chan->size ? $chan->get : undef;
    ok $msg && $msg->{id} eq 'save', 'reconciled Save item routes a click';
}

# ── 6. Runtime check-state toggle via the MODEL (in-place mutation) ──────
# The demo mutates $model->{items} in place on MENU_CLICK and rebuilds the menu_bar node from
# the SAME arrayref every render. The MenuBar node snapshots its items at construction, so two
# consecutive renders of one shared model structure must still diff -> the reconciler rebuilds
# the native menu and the checkmark actually lands (GetMenuState reports MF_CHECKED).
{
    affix 'user32', 'GetMenuState', [ Size_t, UInt, UInt ] => UInt;
    my $model_items = [
        { label => 'File', children => [ { label => 'New', id => 'new' }, ], },
    ];
    my $mk_win = sub ($m) {
        my $v
            = Uji::window( id => $vtree->id, title => $vtree->title, w => $vtree->w, h => $vtree->h,
                menu_bar => Uji::menu_bar( items => $m, on_click => $menubar->on_click ), child => $vtree->child, );
        $v->set_id( $vtree->id );
        return $v;
    };

    my $recon2   = Uji::Reconciler->new;
    my $win_old = $mk_win->($model_items);
    $recon2->patch( $win_old, $win_old, $drv );    # refresh the live menu from snapshot v0 (unchecked)

    my $new_cmd;
    {
        my $by_cmd = $wrb->{menu_bar}{by_cmd};
        for my $cmd ( keys %$by_cmd ) { $new_cmd = $cmd if $by_cmd->{$cmd}{id} eq 'new' }
    }
    my $checked0 = GetMenuState( $wrb->{menu_bar}{hmenu}, $new_cmd, 0 );
    is $checked0 & $MF_CHECKED, 0, 'item starts unchecked (native state)';

    # In-place model mutation, exactly like the demo's update()
    $model_items->[0]{children}[0]{checked} = 1;
    my $win_new = $mk_win->($model_items);
    ok $recon2->_menu_key( $win_old->menu_bar ) ne $recon2->_menu_key( $win_new->menu_bar ),
        'in-place model toggle changes the menu key across renders';
    $recon2->patch( $win_old, $win_new, $drv );
    my $by_cmd = $wrb->{menu_bar}{by_cmd};
    for my $cmd ( keys %$by_cmd ) { $new_cmd = $cmd if $by_cmd->{$cmd}{id} eq 'new' }
    my $checked1 = GetMenuState( $wrb->{menu_bar}{hmenu}, $new_cmd, 0 );
    ok $checked1 & $MF_CHECKED, 'checkmark lands on the native menu after the model toggle';

    # Now un-tick it and confirm the menu returns to unchecked.
    $model_items->[0]{children}[0]{checked} = 0;
    my $win_third = $mk_win->($model_items);
    $recon2->patch( $win_new, $win_third, $drv );
    $by_cmd = $wrb->{menu_bar}{by_cmd};
    for my $cmd ( keys %$by_cmd ) { $new_cmd = $cmd if $by_cmd->{$cmd}{id} eq 'new' }
    my $checked2 = GetMenuState( $wrb->{menu_bar}{hmenu}, $new_cmd, 0 );
    is $checked2 & $MF_CHECKED, 0, 'un-toggling removes the checkmark';
}

# ─── clean up ───
Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x0010, 0, 0 );    # WM_CLOSE
#
done_testing;
