use v5.40;
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use blib;
use Test2::V0;
use MockDriver;
use Uji;
use Uji::App;

package Canned::Channel {
    use v5.40;
    sub new  { bless { q => [] }, shift }
    sub put  { my ( $s, $m ) = @_; push @{ $s->{q} }, $m; 1 }
    sub get  { my ($s) = @_; shift @{ $s->{q} } }
    sub size { my ($s) = @_; scalar @{ $s->{q} } }
}
my $model0 = { show_dialog => 0 };
my $update = sub ( $msg, $model ) {
    if    ( $msg->{type} eq 'SHOW' ) { $model->{show_dialog} = 1; }
    elsif ( $msg->{type} eq 'HIDE' ) { $model->{show_dialog} = 0; }
    return ( $model, undef );
};
my $view = sub ($model) {
    my @windows = (
        Uji::window(
            id    => 'main',
            title => 'Main Window',
            w     => 400,
            h     => 300,
            child => Uji::button( label => 'Open Dialog', on_click => { type => 'SHOW' } )
        )
    );
    if ( $model->{show_dialog} ) {
        push @windows,
            Uji::window(
            id    => 'dialog',
            title => 'Dialog',
            w     => 200,
            h     => 150,
            child => Uji::button( label => 'Close', on_click => { type => 'HIDE' } )
            );
    }
    return \@windows;
};
my $drv  = MockDriver->new;
my $chan = Canned::Channel->new;
my $app  = Uji::App->new( init => sub { ( $model0, undef ) }, update => $update, view => $view, driver => $drv, channel => $chan );
$app->_boot;

# Initially only 1 window
is scalar( @{ $app->vtrees } ), 1,      'One window returned by view';
is $app->vtrees->[0]->id,       'main', 'Main window is present';
ok exists $drv->mounts->{'main'},        'Main window was mounted in driver';
ok !( exists $drv->mounts->{'dialog'} ), 'Dialog was not mounted';

# Send SHOW message
$chan->put( { type => 'SHOW' } );
$app->_drain_and_render( $chan->get );
is scalar( @{ $app->vtrees } ), 2,        'Two windows returned by view';
is $app->vtrees->[1]->id,       'dialog', 'Dialog window is present';
ok exists $drv->mounts->{'main'},   'Main window is still mounted';
ok exists $drv->mounts->{'dialog'}, 'Dialog was mounted in driver';

# Send HIDE message
$chan->put( { type => 'HIDE' } );
$app->_drain_and_render( $chan->get );
is scalar( @{ $app->vtrees } ), 1, 'One window returned by view again';
ok exists $drv->unmounts->{'dialog'}, 'Dialog was unmounted in driver';

# Regression: a window WITHOUT an explicit id must not be destroyed/recreated on re-render.
# Uji::Node auto-generates a fresh id for every node view() builds, so window identity can only
# be positional. Before the fix, patch_windows saw old-id != new-id, unmounted the live window
# and mounted a brand-new one on every render.
my $auto_model = { bumped => 0 };
my $auto_view  = sub ($model) {
    Uji::window( title => 'Count: ' . $model->{bumped}, child => Uji::text( 'bumped ' . $model->{bumped} ) );
};
my $auto_update = sub ( $msg, $model ) {
    return ( $model, undef );
};
my $auto_drv  = MockDriver->new;
my $auto_chan = Canned::Channel->new;
my $auto_app
    = Uji::App->new( init => sub { ( $auto_model, undef ) }, update => $auto_update, view => $auto_view, driver => $auto_drv, channel => $auto_chan );
$auto_app->_boot;
my $boot_id = $auto_app->vtrees->[0]->id;
ok exists $auto_drv->mounts->{$boot_id}, 'Auto-id window mounted at boot';
is scalar( keys %{ $auto_drv->unmounts } ), 0, 'No window unmounted at boot';

# A no-op render (model unchanged): the window must be patched in place, not recreated.
$auto_chan->put( { type => 'RESIZE' } );
$auto_app->_drain_and_render( $auto_chan->get );
is $auto_app->vtrees->[0]->id, $boot_id, 'Window keeps its id across renders';
ok exists $auto_drv->mounts->{$boot_id},        'Window still mounted (not recreated)';
ok !( exists $auto_drv->unmounts->{$boot_id} ), 'Window was not unmounted/recreated on render';

# A fresh window created after an id-changing render still mounts once.
$auto_model->{bumped} = 1;
$auto_chan->put( { type => 'BUMP' } );
$auto_app->_drain_and_render( $auto_chan->get );
is $auto_app->vtrees->[0]->id, $boot_id, 'Window id still stable after model change';
ok exists $auto_drv->mounts->{$boot_id},        'Window still mounted after model change';
ok !( exists $auto_drv->unmounts->{$boot_id} ), 'Window not recreated after model change';
done_testing;
