use v5.40;
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use blib;
use Test2::V0;
use MockDriver;
use Uji;
use Uji::Reconciler;

# Props batch: multiline / MultilineText / placeholder / password_char / color / background /
# font / font_size / text align / slider orientation node fields, mount-only recreation, layout
# intrinsics, and live-prop diffs.
my $drv    = MockDriver->new;
my $patch  = Uji::Reconciler->new;
my $layout = Uji::Layout->new( driver => $drv );

sub prop_calls ( $id, $prop ) { grep { $_->[1] eq $id && $_->[2] eq $prop } @{ $drv->calls } }

# Node fields
my $in  = Uji::text_input( value => 'hi', multiline => 1, placeholder => 'Name' );
is $in->multiline, 1, 'text_input multiline field';
is $in->placeholder, 'Name', 'text_input placeholder field';

my $pw = Uji::password( password_char => '*' );
is $pw->password_char, '*', 'password password_char field';

my $sl = Uji::slider( orientation => 'vertical' );
is $sl->orientation, 'vertical', 'slider orientation field';
is $sl->_mount_only_props->[0], 'orientation', 'slider orientation is mount-only';

my $tx = Uji::text( 'hi', align => 'center' );
is $tx->align, 'center', 'text align field';
is $tx->_mount_only_props->[0], 'align', 'text align is mount-only';

is $in->_mount_only_props, [], 'multiline text_input has no mount-only props';
is Uji::text_input()->_mount_only_props->[0], 'multiline', 'single-line text_input multiline is mount-only';
is $pw->_mount_only_props, [], 'password has no mount-only props';

my $ml = Uji::multiline_text( value => 'line one' );
is $ml->type, 'multiline_text', 'multiline_text node type';
is $ml->multiline, 1, 'multiline_text always multiline';
is $ml->_mount_only_props, [], 'multiline_text cannot change multiline';

my $col = Uji::text_input( color => '#FF0000', background => '#0000FF', font => 'Arial', font_size => 14 );
is $col->color, '#FF0000', 'text_input color field';
is $col->background, '#0000FF', 'text_input background field';
is $col->font, 'Arial', 'text_input font field';
is $col->font_size, 14, 'text_input font_size field';

# Layout intrinsics
my ( $iw, $ih ) = $layout->_intrinsic( Uji::text_input( multiline => 1, value => "a\nb\nc" ) );
is $ih, 60, 'multiline text_input intrinsic height is line-based';

my ( $mw, $mh ) = $layout->_intrinsic( Uji::multiline_text( value => "short" ) );
is $mh, 60, 'multiline_text intrinsic minimum height 3 lines';

my ( $vw, $vh ) = $layout->_intrinsic( Uji::slider( orientation => 'vertical' ) );
is $vw, 26, 'vertical slider intrinsic swaps to narrow width';
is $vh, 120, 'vertical slider intrinsic swaps to tall height';
my ( $hw, $hh ) = $layout->_intrinsic( Uji::slider( orientation => 'horizontal' ) );
is $hw, 120, 'horizontal slider intrinsic keeps wide width';
is $hh, 26, 'horizontal slider intrinsic keeps short height';

# Mount-only recreation
my $build = sub ( $orientation, $align, $placeholder ) {
    Uji::window(
        title => 't',
        w     => 360,
        h     => 400,
        child => Uji::column(
            children => [
                Uji::slider( orientation => $orientation ),
                Uji::text( 'Hi', align => $align ),
                Uji::text_input( placeholder => $placeholder ),
            ]
        )
    );
};
my $old = $build->( 'horizontal', 'left', undef );
$drv->mount($old);
$drv->mount_children($old);
$layout->compute( $old, 0, 0, 360, 400 );
my $old_slider = $old->child->children->[0];
my $old_input  = $old->child->children->[2];
my $slider_id  = $old_slider->id;

# Cycle 1: only the slider orientation changes -> one mount-only recreation for the slider.
my $new = $build->( 'vertical', 'left', undef );
$layout->compute( $new, 0, 0, 360, 400 );
$patch->patch( $old, $new, $drv );
my $new_slider = $new->child->children->[0];
is $new_slider->id, $slider_id, 'recreated slider keeps its id';
my @recreates = grep { $_->[0] eq 'recreate_node' } @{ $drv->calls };
is scalar @recreates, 1, 'one recreate_node call for the orientation change';
is $recreates[-1][2], $new_slider->id, 'recreate targets the new slider node';
ok $new->child->children->[2]->id, 'recreated sibling still has an id';

# Cycle 2: the text align changes (mount-only) + the input placeholder changes (live prop).
my $mid = $new;
my $new2 = $build->( 'vertical', 'right', 'Name' );
$layout->compute( $new2, 0, 0, 360, 400 );
$patch->patch( $mid, $new2, $drv );
my @recreates2 = grep { $_->[0] eq 'recreate_node' } @{ $drv->calls };
is scalar @recreates2, 2, 'second cycle recreates the text node (align)';
my $new_input = $new2->child->children->[2];
is $new_input->id, $old_input->id, 'input node keeps its id across the recreates';

my @ph = prop_calls( $new_input->id, 'placeholder' );
is scalar @ph, 1, 'placeholder diff issues one set_prop';
is $ph[-1][3], 'Name', 'placeholder value is Name';

# Nothing re-renders for unchanged props on the fresh tree.
my $calls_before = scalar @{ $drv->calls };
my $same = $build->( 'vertical', 'right', 'Name' );
$layout->compute( $same, 0, 0, 360, 400 );
$patch->patch( $new2, $same, $drv );
is scalar @{ $drv->calls }, $calls_before, 'unchanged re-render issues no calls';

# Live (non-mount-only) diffs
my $live_old = Uji::window(
    title => 't',
    child => Uji::column(
        children => [
            Uji::password( value => 'x', password_char => '.' ),
            Uji::text_input( value => 'a', placeholder => 'Old' ),
            Uji::text_input( value => 'b', color => '#111111', background => '#222222', font => '', font_size => 9 ),
        ]
    )
);
$drv->mount($live_old);
$drv->mount_children($live_old);
$layout->compute( $live_old, 0, 0, 360, 400 );
$calls_before = scalar @{ $drv->calls };

my $live_new = Uji::window(
    title => 't',
    child => Uji::column(
        children => [
            Uji::password( value => 'x', password_char => '*' ),
            Uji::text_input( value => 'a', placeholder => 'New' ),
            Uji::text_input( value => 'b', color => '#FF0000', background => '#0000FF', font => 'Segoe UI', font_size => 12 ),
        ]
    )
);
$layout->compute( $live_new, 0, 0, 360, 400 );
$patch->patch( $live_old, $live_new, $drv );

my @pwchar = prop_calls( $live_new->child->children->[0]->id, 'password_char' );
is scalar @pwchar, 1, 'password_char diff issues one set_prop';
is $pwchar[-1][3], '*', 'password_char value is *';
my @ph2 = prop_calls( $live_new->child->children->[1]->id, 'placeholder' );
is scalar @ph2, 1, 'live placeholder diff issues one set_prop';
for my $p (qw[ color background font font_size ]) {
    my @c = prop_calls( $live_new->child->children->[2]->id, $p );
    is scalar @c, 1, "live $p diff issues one set_prop";
}

done_testing;
