use v5.40;
use Scalar::Util qw[refaddr blessed];

package Uji::Sub v0.0.1 {

    # Subscription descriptors are plain hashrefs produced by the sub_* helpers. Uji::App
    # diffs them by C<key> against the running set each render: a sub whose key disappears is
    # stopped, a brand-new key is started (interval timers get their first due time), and a
    # surviving interval keeps its phase while its message closure is refreshed.
    use Exporter qw[import];
    our @EXPORT_OK = qw[sub_interval sub_on_resize sub_key];

    # sub_interval( $ms, $msg, %opts )
    #   $ms   milliseconds between firings (rounded up to 1)
    #   $msg  a message hashref, or a coderef called as $msg->($now_ms) returning one
    #   %opts id => '...' to disambiguate two structurally identical subs
    sub sub_interval ( $ms, $msg, %opts ) {
        $ms = 1 if !defined $ms || $ms < 1;
        return _normalize( %opts, kind => 'interval', ms => $ms, msg => $msg );
    }

    # sub_on_resize( $msg, %opts )
    #   Fires whenever the platform delivers a RESIZE event; same $msg shapes as above.
    sub sub_on_resize ( $msg, %opts ) {
        return _normalize( %opts, kind => 'resize', msg => $msg );
    }

    sub _normalize ( %spec ) {
        my $msg = $spec{msg};
        $spec{key} = sub_key( $spec{kind}, $spec{id}, $spec{ms}, $msg );
        return \%spec;
    }

    sub sub_key ( $kind, $id, $ms, $msg ) {
        my @parts = ( $kind, defined $id ? $id : () );
        push @parts, $ms if defined $ms;
        my $fp = _fingerprint($msg);
        push @parts, $fp if defined $fp;
        return join ':', @parts;
    }

    # A stable string for a plain-data message so that re-building the same hashref each render
    # yields the same key. Coderefs (and odd blessed refs) have no stable value, so they are
    # deliberately not part of the key -- pass id => '...' to keep two such subs distinct.
    sub _fingerprint ($v) {
        return undef unless defined $v;
        return undef if ref $v eq 'CODE';
        if ( ref $v eq 'HASH' ) {
            return '{' . join( ',', map { $_ . '=' . ( _fingerprint( $v->{$_} ) // '~' ) } sort keys %$v ) . '}';
        }
        if ( ref $v eq 'ARRAY' ) {
            return '[' . join( ',', map { _fingerprint($_) // '~' } @$v ) . ']';
        }
        return $v unless ref $v;
        return blessed($v) ? join( '=', ref $v, refaddr($v) ) : undef;
    }
};
1;
