#!/usr/bin/env perl
# =====================================================================
# KelolaKerja — PSGI Entrypoint (web.pl)
# Compatible with uWSGI (--plugin psgi --psgi web.pl) and Plackup
# =====================================================================
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";

use KelolaKerja::Config qw(validate_config);
use KelolaKerja::Router qw(dispatch);
use KelolaKerja::Response qw(decode_json_body);

# Validate config security on startup
validate_config();

my $app = sub {
    my ($env) = @_;

    my $method = uc($env->{REQUEST_METHOD} // 'GET');
    my $path   = $env->{PATH_INFO} // '/';

    # Extract Query Parameters
    my %params;
    if (defined $env->{QUERY_STRING} && length $env->{QUERY_STRING}) {
        for my $pair (split /[&;]/, $env->{QUERY_STRING}) {
            my ($k, $v) = split /=/, $pair, 2;
            $k //= ''; $v //= '';
            $k =~ s/\+/ /g; $k =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
            $v =~ s/\+/ /g; $v =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
            $params{$k} = $v if length $k;
        }
    }

    # Extract Request Body
    my $body_raw = '';
    if (my $len = int($env->{CONTENT_LENGTH} // 0)) {
        if (my $input = $env->{'psgi.input'}) {
            $input->read($body_raw, $len);
        }
    }

    # Extract Headers
    my %headers;
    for my $key (keys %$env) {
        if ($key =~ /^HTTP_(.+)$/) {
            my $h = lc $1;
            $h =~ tr/_/-/;
            $headers{$h} = $env->{$key};
        } elsif ($key eq 'CONTENT_TYPE') {
            $headers{'content-type'} = $env->{$key};
        } elsif ($key eq 'CONTENT_LENGTH') {
            $headers{'content-length'} = $env->{$key};
        }
    }

    # Decode JSON body
    my $body = decode_json_body($body_raw);

    my %req = (
        method  => $method,
        path    => $path,
        params  => \%params,
        headers => \%headers,
        body    => $body,
        ip      => $env->{HTTP_X_FORWARDED_FOR} // $env->{REMOTE_ADDR} // '127.0.0.1',
    );

    # Dispatch to Router
    my $res = KelolaKerja::Router::dispatch(%req);

    my $status = int($res->{status} || 200);
    my @psgi_headers;
    while (my ($k, $v) = each %{ $res->{headers} || {} }) {
        push @psgi_headers, $k => $v;
    }

    my $res_body = ($status == 204) ? '' : ($res->{body} // '');
    return [ $status, \@psgi_headers, [ $res_body ] ];
};

return $app;

