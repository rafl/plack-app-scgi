use strict;
use warnings;

package Plack::App::SCGI;

use AnyEvent;
use AnyEvent::SCGI::Client;
use HTTP::Response;
use namespace::clean;

use parent 'Plack::Component';
use Plack::Util::Accessor qw(host service);

sub call {
    my ($self, $env) = @_;

    my %scgi_env = map {
        $_ => $env->{$_}
    } grep {
        $_ !~ /^psgi\./ && defined $env->{$_}
    } keys %{ $env };

    return sub {
        my ($respond) = @_;

        my $cv = AnyEvent->condvar;
        my ($buf, $writer);

        my $content_length = $env->{CONTENT_LENGTH} || 0;

        scgi_request(
            $self->host, $self->service, \%scgi_env,
            [$content_length, $content_length ? $env->{'psgi.input'} : undef],
            sub {
                my ($chunk) = @_;

                if (defined $chunk) {
                    $buf .= $chunk;

                    if (!$writer) {
                        my ($start) = $buf =~ m/^(.*?(?:\x0d\x0a){2})/s
                            or return;

                        substr $buf, 0, length($start), '';

                        my ($status, $headers) = do {
                            my $m = HTTP::Response->parse($start);
                            ($m->code, $m->headers);
                        };

                        $writer = $respond->([
                            200,
                            [map {
                                my $k = $_;
                                (map { ($k => $_) } $headers->header($k))
                            } $headers->header_field_names]
                        ]);
                    }

                    if (length $buf) {
                        $writer->write($buf);
                        $buf = '';
                    }
                }
                else {
                    $writer->close;
                    $cv->send;
                }

            },
        );

        $cv->recv unless $env->{'psgi.nonblocking'};
    };
}

1;
