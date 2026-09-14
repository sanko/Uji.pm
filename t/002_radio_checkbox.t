use v5.40;
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/../lib", "$FindBin::Bin/lib";
use blib;
use Test2::V0;
use Scalar::Util qw[refaddr];
use MockDriver;
use Uji;

# Basic node construction
my $cb = Uji::checkbox( label => 'Dark', checked => 1, on_toggle => sub { } );
is $cb->type,    'checkbox', 'checkbox type';
is $cb->label,   'Dark',     'label round-trips';
is $cb->checked, 1,          'checked round-trips';
ok $cb->can('on_toggle'), 'on_toggle exists';
ok !$cb->can('on_click'), 'checkbox has no on_click';
my $rg = Uji::radio_group(
    value     => 'blue',
    spacing   => 2,
    options   => [ { value => 'red', label => 'Red' }, { value => 'green', label => 'Green' }, { value => 'blue', label => 'Blue' } ],
    on_select => sub { },
);
is $rg->type, 'radio_group', 'radio_group type';
my $kids = $rg->children;
is scalar @$kids,            3,              'three radio children';
is refaddr( $rg->children ), refaddr($kids), 'children() memoized per instance';
is $kids->[0]->type,         'radio',        'child type radio';
is $kids->[0]->value,        'red',          'child 0 value';
is $kids->[0]->first,        1,              'first child carries first flag';
is $kids->[2]->selected,     1,              'current value is selected';
is $kids->[0]->selected,     0,              'other options not selected';
my $rg2 = Uji::radio_group( value => 'red', options => [ { value => 'red', label => 'Red' }, { value => 'blue', label => 'Blue' } ] );
is $rg2->children->[0]->selected, 1,              'second instance selects its own value';
isnt $rg2->children->[0]->id,     $kids->[0]->id, 'independent instances get fresh child ids';

# Helper constructors coexist with the rest of the DSL
is Uji::column()->type,                'column', 'column helper';
is Uji::row()->type,                   'row',    'row helper';
is Uji::text('hi')->label,             'hi',     'text helper';
is Uji::button( label => 'B' )->type,  'button', 'button helper';
is Uji::window( title => 't' )->title, 't',      'window helper';

# Layout treats radio_group like a vertical column
my $col = Uji::column(
    children => [
        Uji::radio_group( value => 'red', options => [ { value => 'red', label => 'Red' }, { value => 'green', label => 'Green' } ] ),
        Uji::text('tail')
    ]
);
my $tree   = Uji::window( title => 't', w => 300, h => 200, child => $col );
my $drv    = MockDriver->new;
my $layout = Uji::Layout->new( driver => $drv );
$layout->compute( $tree, 0, 0, 300, 200 );
my $rg_node = $col->children->[0];
my $radios  = $rg_node->children;
is $rg_node->bh, ( $radios->[0]->bh + $radios->[1]->bh + $rg_node->spacing ), 'radio_group intrinsic height stacks children';
is $radios->[0]->bw, 300 - 20,                                                'radio children span full column width';
is $radios->[0]->by, $radios->[1]->by - $radios->[1]->bh - $rg_node->spacing, 'radios stack vertically';
#
done_testing;
