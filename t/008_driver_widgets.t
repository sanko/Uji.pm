use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use blib;
use Test2::V0;
use Uji::Driver::Win32;
use Uji;
use Affix qw[:memory];
use Acme::Parataxis::Channel;
#
skip_all 'Win32 only' unless $^O eq 'MSWin32';

# Real-HWND spin box (EDIT + up/down buddy), progress bar, toggle switch/button, link button.
# Verifies native state is written at mount, set_prop round-trips, and BN_CLICKED / WM_VSCROLL
# notifications route into on_toggle / on_change / on_click.
my $chan = Acme::Parataxis::Channel->new( capacity => 1024 );
my $drv  = Uji::Driver::Win32->new;
$drv->init($chan);
my $spin  = Uji::spin_box( value => 40, min => 0, max => 100, step => 5, on_change => sub ($v) { { type => 'SET_LEVEL', value => $v } }, );
my $bar   = Uji::progress_bar( value => 40, min => 0, max => 100 );
my $sw    = Uji::toggle_switch( label => 'Enabled', checked => 0, on_toggle => sub ($on) { { type => 'TOGGLE_SW', value => $on } }, );
my $tb    = Uji::toggle_button( label => 'Lock', checked => 1, on_toggle => sub ($on) { { type => 'TOGGLE_LOCK', value => $on } }, );
my $lk    = Uji::link_button( label => 'Visit docs', on_click => { type => 'OPEN_LINK' } );
my $col   = Uji::column( spacing => 10, children => [ $spin, $bar, $sw, $tb, $lk ] );
my $vtree = Uji::window( id => 'main', title => 't', w => 360, h => 400, child => $col );
$drv->mount($vtree);
my $layout = Uji::Layout->new( driver => $drv );
$layout->compute( $vtree, 0, 0, 360, 400 );
$drv->mount_children($vtree);
my $spin_r = $drv->_get_registry_record( $spin->id );
my $bar_r  = $drv->_get_registry_record( $bar->id );
my $sw_r   = $drv->_get_registry_record( $sw->id );
my $tb_r   = $drv->_get_registry_record( $tb->id );
my $lk_r   = $drv->_get_registry_record( $lk->id );
my $wrb    = $drv->_get_registry_record( $vtree->id );
ok $spin_r && $spin_r->{hwnd} && $spin_r->{aux}, 'spin box has an EDIT hwnd and an up/down buddy';
ok $bar_r  && $bar_r->{hwnd}, 'progress bar has a real HWND';
ok $sw_r   && $sw_r->{hwnd} && $tb_r && $tb_r->{hwnd}, 'toggle widgets have real HWNDs';
ok $lk_r   && $lk_r->{hwnd}, 'link button has a real HWND';
my $parent = $wrb->{hwnd};
$chan->get() while $chan->size;    # drop mount noise

# Spin box: buddy holds the range/position and writes it into the edit text
is Uji::Driver::Win32::SendMessageW( $spin_r->{aux}, 0x0472, 0, 0 ), 40,   'up/down buddy starts at value 40';
is $drv->_get_text( $spin_r->{hwnd} ),                               '40', 'edit text mirrors the value';
$drv->set_prop( $spin->id, 'value', 45 );
is Uji::Driver::Win32::SendMessageW( $spin_r->{aux}, 0x0472, 0, 0 ), 45,   'set_prop moves the buddy position';
is $drv->_get_text( $spin_r->{hwnd} ),                               '45', 'set_prop updates the edit text';
{
    my $rng = Affix::malloc(4);
    Uji::Driver::Win32::SendMessageW( $spin_r->{aux}, 0x0470, 0, Affix::address($rng) );    # UDM_GETRANGE32
    my $packed = unpack 'V', Affix::raw( $rng, 4 );
    is( $packed & 0xFFFF,           0,   'buddy range min is 0' );
    is( ( $packed >> 16 ) & 0xFFFF, 100, 'buddy range max is 100' );
    free($rng);
}

# Arrow tap: move the position natively, then tap WM_VSCROLL with lParam = buddy HWND.
Uji::Driver::Win32::SendMessageW( $spin_r->{aux}, 0x0471, 0, 50 );         # UDM_SETPOS32
$chan->get() while $chan->size;
Uji::Driver::Win32::SendMessageW( $parent, 0x0115, 1, $spin_r->{aux} );    # WM_VSCROLL: SB_LINEDOWN
my $msg = $chan->size ? $chan->get : undef;
ok $msg, 'spin arrow produced a channel message';
is $msg && $msg->{type},  'SET_LEVEL', 'spin arrow message type';
is $msg && $msg->{value}, 50,          'spin arrow reports the new position';

# Progress bar
is Uji::Driver::Win32::SendMessageW( $bar_r->{hwnd}, 0x0408, 0, 0 ), 40, 'progress bar starts at value 40';
$drv->set_prop( $bar->id, 'value', 75 );
is Uji::Driver::Win32::SendMessageW( $bar_r->{hwnd}, 0x0408, 0, 0 ), 75, 'set_prop moves the progress bar';

# Toggle switch / toggle button (state round-trip through BN_CLICKED). State source depends on the
# scheme: light uses the native check state (BM_GETCHECK); a dark owner-draw toggle has no native state,
# so the driver mirrors it in the registry record.
my $getcheck = sub ($r) {
    $drv->uses_dark_mode ? ( $r->{check} // 0 )
    : Uji::Driver::Win32::SendMessageW( $r->{hwnd}, 0x00F0, 0, 0 );    # BM_GETCHECK
};
is $getcheck->($sw_r), 0, 'toggle switch starts unchecked';
is $getcheck->($tb_r), 1, 'toggle button starts checked';
$chan->get() while $chan->size;

# The native button would have toggled itself in a real click; simulate that then tap BN_CLICKED.
Uji::Driver::Win32::SendMessageW( $sw_r->{hwnd}, 0x00F1, 1, 0 );                  # BM_SETCHECK
Uji::Driver::Win32::SendMessageW( $parent, 0x0111, ( 0 << 16 ) | $sw->id, 0 );    # BN_CLICKED
my $msg2 = $chan->size ? $chan->get : undef;
ok $msg2, 'toggle switch click produced a channel message';
is $msg2 && $msg2->{type},  'TOGGLE_SW', 'toggle switch message type';
is $msg2 && $msg2->{value}, 1,           'toggle switch reports the checked state';
Uji::Driver::Win32::SendMessageW( $tb_r->{hwnd}, 0x00F1, 0, 0 );                  # BM_SETCHECK
$chan->get() while $chan->size;
Uji::Driver::Win32::SendMessageW( $parent, 0x0111, ( 0 << 16 ) | $tb->id, 0 );    # BN_CLICKED
my $msg3 = $chan->size ? $chan->get : undef;
ok $msg3, 'toggle button click produced a channel message';
is $msg3 && $msg3->{type},  'TOGGLE_LOCK', 'toggle button message type';
is $msg3 && $msg3->{value}, 0,             'toggle button reports the checked state';

# set_prop('checked') round-trips for toggle widgets.
$drv->set_prop( $sw->id, 'checked', 0 );
is $getcheck->($sw_r), 0, 'set_prop unchecked the toggle switch';

# Link button: static hashref message on BN_CLICKED
$chan->get() while $chan->size;
Uji::Driver::Win32::SendMessageW( $parent, 0x0111, ( 0 << 16 ) | $lk->id, 0 );    # BN_CLICKED
my $msg4 = $chan->size ? $chan->get : undef;
ok $msg4, 'link button click produced a channel message';
is $msg4 && $msg4->{type}, 'OPEN_LINK', 'link button sends its message verbatim';

# Close the test window unobtrusively.
Uji::Driver::Win32::SendMessageW( $parent, 0x0010, 0, 0 );                        # WM_CLOSE -> WM_DESTROY
#
done_testing;
