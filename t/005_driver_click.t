use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use blib;
use Test2::V0;
use Uji::Driver::Win32;
use Uji;
use Acme::Parataxis::Channel;
#
skip_all 'Win32 only' unless $^O eq 'MSWin32';

# Build a real window with a checkbox + radios + buttons
my $chan = Acme::Parataxis::Channel->new( capacity => 1024 );
my $drv  = Uji::Driver::Win32->new;
$drv->init($chan);
my $rg = Uji::radio_group(
    value     => 'blue',
    options   => [ { value => 'red', label => 'Red' }, { value => 'green', label => 'Green' }, { value => 'blue', label => 'Blue' }, ],
    on_select => sub ($v) { { type => 'SET_COLOR', value => $v } },
);
my $btn_static  = Uji::button( label => '+1', on_click => { type => 'INCREMENT' } );
my $btn_cb      = Uji::button( label => 'Reset', on_click => sub { { type => 'RESET', value => 0 } } );
my $btn_nothing = Uji::button( label => 'Noop', on_click => sub { undef } );
my $col = Uji::column(
    children => [
        Uji::checkbox( label => 'Dark mode', checked => 0, on_toggle => sub ($on) { { type => 'TOGGLE_DARK', value => $on } } ),
        $rg, $btn_static, $btn_cb, $btn_nothing,
    ],
);
my $vtree = Uji::window( title => 't', w => 360, h => 400, child => $col );
$drv->mount($vtree);
my $layout = Uji::Layout->new( driver => $drv );
$layout->compute( $vtree, 0, 0, 360, 400 );
$drv->mount_children($vtree);
my $cb  = $col->children->[0];
my $wrb = $drv->_get_registry_record( $vtree->id );
my $cbr = $drv->_get_registry_record( $cb->id );
ok $cbr && $cbr->{hwnd}, 'checkbox has a real HWND';
my $bsr = $drv->_get_registry_record( $btn_static->id );
my $bcr = $drv->_get_registry_record( $btn_cb->id );
my $bnr = $drv->_get_registry_record( $btn_nothing->id );
ok $bsr && $bsr->{hwnd}, 'static-message button has a real HWND';
ok $bcr && $bcr->{hwnd}, 'callback button has a real HWND';
ok $bnr && $bnr->{hwnd}, 'noop-callback button has a real HWND';

# Mount/centering leaves a stray RESIZE in the channel; drop it before clicking.
$chan->get() while $chan->size;

# Simulate a user click on the checkbox via BM_CLICK
# BN_CLICKED toggles BS_AUTOCHECKBOX natively and posts WM_COMMAND to the
# parent synchronously through SendMessage, so no message pump is needed.
Uji::Driver::Win32::SendMessageW( $cbr->{hwnd}, 0x00F5, 0, 0 );    # BM_CLICK
my $msg = $chan->size ? $chan->get : undef;
ok $msg, 'BN_CLICKED produced a channel message';
is $msg && $msg->{type},  'TOGGLE_DARK', 'message type is TOGGLE_DARK';
is $msg && $msg->{value}, 1,             'TOGGLE_DARK carries checked=1';

# Clicking again should report checked=0
Uji::Driver::Win32::SendMessageW( $cbr->{hwnd}, 0x00F5, 0, 0 );    # BM_CLICK
my $msg2 = $chan->size ? $chan->get : undef;
is $msg2 && $msg2->{type},  'TOGGLE_DARK', 'second click still TOGGLE_DARK';
is $msg2 && $msg2->{value}, 0,             'second click carries checked=0';

# Radio click via BM_CLICK
my $red  = $rg->children->[0];
my $redr = $drv->_get_registry_record( $red->id );
Uji::Driver::Win32::SendMessageW( $redr->{hwnd}, 0x00F5, 0, 0 );    # BM_CLICK on Red radio
my $msg3 = $chan->size ? $chan->get : undef;
is $msg3 && $msg3->{type},  'SET_COLOR', 'radio click produced SET_COLOR';
is $msg3 && $msg3->{value}, 'red',       'SET_COLOR carries "red"';

# Static-message button: BN_CLICKED must send the hashref verbatim.
Uji::Driver::Win32::SendMessageW( $bsr->{hwnd}, 0x00F5, 0, 0 );    # BM_CLICK
my $msg4 = $chan->size ? $chan->get : undef;
ok $msg4, 'static-message button produced a channel message';
is ref $msg4, 'HASH', 'static-message button message is a hashref';
is $msg4 && $msg4->{type}, 'INCREMENT', 'static-message button carries its hashref verbatim';

# Callback button: the driver must CALL on_click and send its return value (not the coderef).
Uji::Driver::Win32::SendMessageW( $bcr->{hwnd}, 0x00F5, 0, 0 );    # BM_CLICK
my $msg5 = $chan->size ? $chan->get : undef;
ok $msg5, 'callback button produced a channel message';
is ref $msg5, 'HASH', 'callback button message is a hashref (not a coderef)';
is $msg5 && $msg5->{type},  'RESET', 'callback button message type comes from the return value';
is $msg5 && $msg5->{value}, 0,      'callback button message carries its return value';

# A callback that returns undef produces no message at all.
Uji::Driver::Win32::SendMessageW( $bnr->{hwnd}, 0x00F5, 0, 0 );    # BM_CLICK
is $chan->size, 0, 'noop callback button produces no channel message';

# Move window off-screen / close it so the test is unobtrusive
Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x0010, 0, 0 );     # WM_CLOSE -> WM_DESTROY
#
done_testing;
