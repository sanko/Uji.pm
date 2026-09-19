use v5.40;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Uji;
use MIME::Base64;

# A 16x16 blue magnifier PNG (search glyph for the field's leading icon).
my $mag = 'data:image/png;base64,' .
    encode_base64(
    decode_base64(
        'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAbklEQVR4nGNgGAWjYBSMglEweAaMDP+zE1Mzpv9FJIWYUmJdyn7/P7dnR08oI9ZcTpZWjtEAlCGmpJ71FBBwcH4OD8C2WSAOKElMTUnPnpcSFWXND3Lo/x9/f/8eZBIzvp2pUVSnpzpLwChgBwAA3jRThF06J10AAAAASUVORK5CYII='
    ),
    ''
    );

package main {

    sub init () {
        return ( { query => '', result => 'Type above, then press Search.' }, undef );
    }

    sub update ( $msg, $model ) {
        if ( $msg->{type} eq 'QUERY' ) {
            $model->{query}  = $msg->{text};
            $model->{result} = 'Query: "' . $msg->{text} . '"';
        }
        elsif ( $msg->{type} eq 'SEARCH' ) {
            $model->{result} = 'Searched for: "' . $msg->{text} . '"';
        }
        elsif ( $msg->{type} eq 'RUN' ) {
            $model->{result} = 'Searched for: "' . $model->{query} . '"';
        }
        return ( $model, undef );
    }

    sub view ($model) {
        Uji::window(
            title    => 'Uji SearchInput Demo',
            w        => 520,
            h        => 180,
            centered => 1,
            child    => Uji::column(
                padding  => 20,
                spacing  => 18,
                children => [

                    # The ✕ appears once the user types; clicking it clears the field,
                    # refocuses it, and fires on_search('') so the model re-runs the query.
                    Uji::row(
                        spacing  => 8,
                        children => [
                            Uji::search_input(
                                placeholder => 'Search…',
                                icon        => $mag,
                                value       => $model->{query},
                                on_input    => sub ($t) { { type => 'QUERY',  text => $t } },
                                on_search   => sub ($t) { { type => 'SEARCH', text => $t } },
                                flex        => 1
                            ),
                            Uji::button( label => 'Search', on_click => { type => 'RUN' } )
                        ]
                    ),
                    Uji::separator(),
                    Uji::status_text( $model->{result} )
                ]
            )
        );
    }
    Uji::app( init => \&init, update => \&update, view => \&view )->run();
}
