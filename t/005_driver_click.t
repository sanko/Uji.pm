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

# Build a real window with a checkbox + radios
my $chan = Acme::Parataxis::Channel->new( capacity => 1024 );
my $drv  = Uji::Driver::Win32->new;
$drv->init($chan);
my $rg = Uji::radio_group(
    value     => 'blue',
    options   => [ { value => 'red', label => 'Red' }, { value => 'green', label => 'Green' }, { value => 'blue', label => 'Blue' }, ],
    on_select => sub ($v) { { type => 'SET_COLOR', value => $v } },
);
my $col = Uji::column(
    children => [ Uji::checkbox( label => 'Dark mode', checked => 0, on_toggle => sub ($on) { { type => 'TOGGLE_DARK', value => $on } } ), $rg, ], );
my $vtree = Uji::window( title => 't', w => 360, h => 400, child => $col );
$drv->mount($vtree);
my $layout = Uji::Layout->new( driver => $drv );
$layout->compute( $vtree, 0, 0, 360, 400 );
$drv->mount_children($vtree);
my $cb  = $col->children->[0];
my $wrb = $drv->_get_registry_record( $vtree->id );
my $cbr = $drv->_get_registry_record( $cb->id );
ok $cbr && $cbr->{hwnd}, 'checkbox has a real HWND';

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

# Move window off-screen / close it so the test is unobtrusive
Uji::Driver::Win32::SendMessageW( $wrb->{hwnd}, 0x0010, 0, 0 );     # WM_CLOSE -> WM_DESTROY
#
done_testing;
