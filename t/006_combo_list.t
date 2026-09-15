use v5.40;
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use blib;
use Test2::V0;
use MockDriver;
use Uji;
use Uji::Reconciler;
use Uji::Layout;

# ComboBox / ListBox: node construction, layout sizing, and reconciler diffing (headless).
my $drv    = MockDriver->new;
my $patch  = Uji::Reconciler->new;
my $layout = Uji::Layout->new( driver => $drv );

subtest 'node construction' => sub {
    my $cb = Uji::combo_box(
        value     => 'red',
        options   => [ { value => 'red', label => 'Red' }, { value => 'green', label => 'Green' } ],
        on_select => sub ($v) { { type => 'SET_COLOR', value => $v } },
    );
    my $lb = Uji::list_box( value => 1, options => [ { value => 1, label => 'One' } ] );
    is $cb->type,     'combo_box', 'combo type is combo_box';
    is $lb->type,     'list_box',  'list type is list_box';
    is $cb->value,    'red',       'combo value';
    is $cb->editable, 0,           'combo is not editable by default';
    is $cb->options->[1]{label}, 'Green', 'combo options';
    is $lb->value,    1,   'list value';
    is $lb->on_select, undef, 'list without handler defaults to undef';
};

# Render the first frame and check intrinsic sizing for combo (field + dropped list) vs list (rows).
my $build = sub ( $color, $count, $list_opts ) {
    Uji::window(
        title => 't',
        w     => 360,
        h     => 400,
        child => Uji::column(
            padding  => 15,
            spacing  => 12,
            children => [
                Uji::combo_box(
                    value     => $color,
                    options   => [ map { { value => $_, label => ucfirst $_ } } qw(red green blue) ],
                    on_select => sub ($v) { { type => 'SET_COLOR', value => $v } }
                ),
                Uji::list_box(
                    value     => $count,
                    options   => [ map { { value => $_, label => $_ . ' ' x 10 } } 1 .. $list_opts ],
                    on_select => sub ($v) { { type => 'SET_COUNT', value => $v } }
                ),
                Uji::text( 'Picker' )
            ]
        )
    );
};
my $old = $build->( 'blue', 3, 3 );
$drv->mount($old);
$drv->mount_children($old);
$layout->compute( $old, 0, 0, 360, 400 );
my $old_cb = $old->child->children->[0];
my $old_lb = $old->child->children->[1];
is $old_cb->bh, 74, 'combo intrinsic height = field (20) + 3 rows (54)';
is $old_lb->bh, 58, 'list intrinsic height = 3 rows (54) + border-ish padding (4)';

# 1. Change combo value only -> one set_prop('value') for the combo, none for list options.
my $new = $build->( 'red', 3, 3 );
$layout->compute( $new, 0, 0, 360, 400 );
$patch->patch( $old, $new, $drv );
my $new_cb = $new->child->children->[0];
my $new_lb = $new->child->children->[1];
is $new_cb->id, $old_cb->id, 'combo id preserved across render';
is $new_lb->id, $old_lb->id, 'list id preserved across render';
my @cb_value = grep { $_->[1] eq $new_cb->id && $_->[2] eq 'value' } @{ $drv->calls };
my @cb_opts  = grep { $_->[1] eq $new_cb->id && $_->[2] eq 'options' } @{ $drv->calls };
my @lb_opts  = grep { $_->[1] eq $new_lb->id && $_->[2] eq 'options' } @{ $drv->calls };
is scalar @cb_value, 1,            'combo value pushed exactly once';
is scalar @cb_opts,  0,            'combo options untouched when unchanged';
is scalar @lb_opts,  0,            'list options untouched when unchanged';
is $drv->checks->{ $new_cb->id }, 'red', 'reconciled combo value recorded';

# 2. Change list value + list options (and shrink) -> options rebuilt once, value pushed once.
my $newer = $build->( 'red', 2, 2 );
$layout->compute( $newer, 0, 0, 360, 400 );
$patch->patch( $new, $newer, $drv );
my $newer_cb = $newer->child->children->[0];
my $newer_lb = $newer->child->children->[1];
is $newer_cb->id, $old_cb->id, 'combo id survives second render';
is $newer_lb->id, $old_lb->id, 'list id survives second render';
my @cb_value2 = grep { $_->[1] eq $newer_cb->id && $_->[2] eq 'value' } @{ $drv->calls };
my @lb_value2 = grep { $_->[1] eq $newer_lb->id && $_->[2] eq 'value' } @{ $drv->calls };
my @lb_opts2  = grep { $_->[1] eq $newer_lb->id && $_->[2] eq 'options' } @{ $drv->calls };
is scalar @cb_value2, 1, 'combo value not re-pushed when unchanged';
is scalar @lb_value2, 1, 'list value pushed exactly once';
is scalar @lb_opts2,  1, 'list options rebuilt exactly once when they changed';
is $newer_lb->bh,     40, 'list shrank to 2 rows (36+4)';
is $lb_value2[0][3], 2,   'list value pushed with the new value';
#
done_testing;