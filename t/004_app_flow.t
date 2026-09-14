use v5.40;
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use blib;
use Test2::V0;
use MockDriver;
use Uji;
use Uji::App;

# Minimal channel stand-in so we never spin up Acme::Parataxis in a unit test.
package Canned::Channel {
    use v5.40;
    sub new  { bless { q => [] }, shift }
    sub put  { my ( $s, $m ) = @_; push @{ $s->{q} }, $m; 1 }
    sub get  { my ($s) = @_; shift @{ $s->{q} } }
    sub size { my ($s) = @_; scalar @{ $s->{q} } }
}

# Demo-faithful model / update / view
my $model0 = { title => 't', dark => 0, color => 'blue', count => 0, level => 50, locked => 0 };
my $update = sub ( $msg, $model ) {
    if    ( $msg->{type} eq 'TOGGLE_DARK' ) { $model->{dark} = $msg->{value} }
    elsif ( $msg->{type} eq 'SET_COLOR' )   { $model->{color} = $msg->{value} }
    elsif ( $msg->{type} eq 'INCREMENT' )   { $model->{count} += 1 }
    return ( $model, undef );
};
my $view = sub ($model) {
    Uji::window(
        title    => $model->{title},
        w        => 380,
        h        => 600,
        centered => 1,
        child    => Uji::column(
            padding  => 15,
            spacing  => 12,
            children => [
                Uji::checkbox( label => 'Dark mode', checked => $model->{dark}, on_toggle => sub ($on) { { type => 'TOGGLE_DARK', value => $on } } ),
                Uji::text( 'Dark: ' . ( $model->{dark} ? 'ON' : 'OFF' ) ),
                Uji::text('Highlight color'),
                Uji::radio_group(
                    value     => $model->{color},
                    spacing   => 2,
                    options   => [ { value => 'red', label => 'Red' }, { value => 'green', label => 'Green' }, { value => 'blue', label => 'Blue' } ],
                    on_select => sub ($v) { { type => 'SET_COLOR', value => $v } }
                ),
                Uji::text( 'Color: ' . ( $model->{color} // '(none)' ) ),
                Uji::button( label => '+1', on_click => { type => 'INCREMENT' } )
            ]
        )
    );
};

# Walk helpers
my $all_nodes = sub ($node) {
    my $out = [];
    my $walk;
    $walk = sub ($n) {
        push @$out, $n;
        $walk->($_) for @{ $n->children };
    };
    $walk->($node);
    return $out;
};
my $find = sub ( $root, $type ) {
    my @m = grep { $_->type eq $type } @{ $all_nodes->($root) };
    return wantarray ? @m : $m[0];
};

# Build app
my $drv  = MockDriver->new;
my $chan = Canned::Channel->new;
my $app  = Uji::App->new( init => sub { ( $model0, undef ) }, update => $update, view => $view, driver => $drv, channel => $chan );
$app->_boot;    # init + mount + layout
my $cb = $find->( $app->vtree, 'checkbox' );
ok $cb, 'checkbox present in mounted vtree';
is $app->model->{dark}, 0, 'model starts dark=0';
#
subtest Checkbox => sub {    # click round-trip

    # Emulate the Win32 BN_CLICKED branch: BS_AUTOCHECKBOX has already toggled, so
    # BM_GETCHECK reflects the new state; the handler pushes TOGGLE_DARK; the app
    # drains the channel and re-renders.
    my $checked = $drv->checks->{ $cb->id };    # BM_GETCHECK
    is $checked, 0, 'checkbox natively unchecked';
    $drv->checks->{ $cb->id } = 1;              # native toggle on click
    my $action = $cb->on_toggle->(1);
    $chan->put($action);
    $app->_drain_and_render( $chan->get );
    is $app->model->{dark},       1, 'TOGGLE_DARK reached the model';
    is $drv->checks->{ $cb->id }, 1, 'checkbox stays checked after render';
    like $app->vtree->child->children->[1]->label, qr/Dark: ON/, 'view label reflected dark=ON';
    my $cb2 = $find->( $app->vtree, 'checkbox' );
    is $cb2->id, $cb->id, 'checkbox id stable across renders';
};
subtest radio => sub {    # Radio select round-trip
    my @rg_nodes = $find->( $app->vtree, 'radio' );
    is scalar @rg_nodes, 3, 'three radio buttons in mounted vtree';

    # user clicks "Red": Windows checks it and unchecks its group siblings
    for my $r (@rg_nodes) { $drv->checks->{ $r->id } = ( $r->value eq 'red' ? 1 : 0 ) }
    my $red = ( grep { $_->value eq 'red' } @rg_nodes )[0];
    $chan->put( $red->on_select->('red') );
    $app->_drain_and_render( $chan->get );
    is $app->model->{color}, 'red', 'SET_COLOR reached the model';
    my @radios2 = $find->( $app->vtree, 'radio' );
    my $red2    = ( grep { $_->value eq 'red' } @radios2 )[0];
    my $blue2   = ( grep { $_->value eq 'blue' } @radios2 )[0];
    is $drv->checks->{ $red2->id },  1,        'red radio checked';
    is $drv->checks->{ $blue2->id }, 0,        'blue radio unchecked';
    is $red2->id,                    $red->id, 'red radio id stable across renders';
    my @color_text = grep { $_->type eq 'text' && $_->label =~ /^Color:/ } @{ $all_nodes->( $app->vtree ) };
    like $color_text[0]->label, qr/Color: red/, 'view label reflected color=red';
};
#
done_testing;
