use strict;
use warnings;
use Test::More;
use Test::TCP;
use Plack::Test;
use HTTP::Headers;
use HTTP::Request::Common;
#use POE;
use AnyEvent::Impl::Perl; # EV is really broken, and it happens to be the
                          # default choice of AnyEvent much too often, so we
                          # just explicitly load something we know actually
                          # works most of the time and doesn't require a huge
                          # test dependency such as POE
use AnyEvent;
use AnyEvent::SCGI;
use Storable 'freeze', 'thaw';

use Plack::App::SCGI;

my $port = empty_port;
my $s = scgi_server '127.0.0.1', $port, sub {
    my ($handle, $env, $content, $fatal, $err) = @_;

    if ($fatal) {
        fail "unexpected $err";
        done_testing;
        exit;
    }

    my $headers = HTTP::Headers->new(
        'Content-Type' => 'text/plain',
        'Connection'   => 'close',
    );

    $handle->push_write(
        join qq{\r\n} => (
            "Status: 200 OK",
            $headers->as_string("\x0d\x0a"),
            freeze {
                env  => $env,
                body => $content,
            }
        )
    );

    my $t;
    $t = AnyEvent->timer(after => 2, cb => sub {
        $handle->push_write(';');
        $t = AnyEvent->timer(after => 2, cb => sub {
            $handle->push_shutdown(1);
            undef $t;
        });
    });
};

my $app = Plack::App::SCGI->new(host => '127.0.0.1', service => $port)->to_app;

test_psgi $app, sub {
    my $cb = shift;

    my $res = $cb->(GET "/");

    is $res->code, 200;
    my $data = thaw $res->content;

    diag explain $data;
};

done_testing;
