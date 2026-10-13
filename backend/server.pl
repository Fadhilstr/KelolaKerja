#!/usr/bin/env perl
# =====================================================================
# KelolaKerja — Standalone HTTP Server (Development / Testing)
# Uses HTTP::Server::Simple::PSGI or built-in socket server
# =====================================================================
use strict;
use warnings;
use IO::Socket::INET;
use FindBin;
use lib "$FindBin::Bin/lib";

use KelolaKerja::Config qw(config);
use KelolaKerja::Router qw(dispatch);
use KelolaKerja::Response qw(decode_json_body);

my $cfg = config();
my $port = $ARGV[0] // $cfg->{api_port} // 5000;

my $server = IO::Socket::INET->new(
    LocalHost => '0.0.0.0',
    LocalPort => $port,
    Proto     => 'tcp',
    Listen    => 32,
    Reuse     => 1
) or die "Cannot start standalone HTTP server on port $port: $!\n";

print "[KelolaKerja] Backend running at http://0.0.0.0:$port/api/\n";
print "[KelolaKerja] Press Ctrl+C to terminate.\n";

while (my $client = $server->accept()) {
    $client->autoflush(1);

    my $request_line = <$client>;
    next unless $request_line;

    my ($method, $uri, $proto) = split /\s+/, $request_line;
    my ($path, $query_string) = split /\?/, ($uri // '/'), 2;

    my %headers;
    while (my $header_line = <$client>) {
        $header_line =~ s/\r?\n$//;
        last if length($header_line) == 0;
        if ($header_line =~ /^([^:]+):\s*(.*)$/) {
            $headers{lc $1} = $2;
        }
    }

    my $body_raw = '';
    my $content_length = int($headers{'content-length'} // 0);
    if ($content_length > 0) {
        read($client, $body_raw, $content_length);
    }

    my %params;
    if ($query_string) {
        for my $pair (split /[&;]/, $query_string) {
            my ($k, $v) = split /=/, $pair, 2;
            $k //= ''; $v //= '';
            $k =~ s/\+/ /g; $k =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
            $v =~ s/\+/ /g; $v =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
            $params{$k} = $v if length $k;
        }
    }

    my $body = decode_json_body($body_raw);
    my $peer_ip = $client->peerhost // '127.0.0.1';

    my %req = (
        method  => uc($method // 'GET'),
        path    => $path // '/',
        params  => \%params,
        headers => \%headers,
        body    => $body,
        ip      => $headers{'x-forwarded-for'} // $peer_ip,
    );

    my $res = KelolaKerja::Router::dispatch(%req);
    my $status = $res->{status} // 200;
    my $status_text = $status == 200 ? 'OK' : ($status == 201 ? 'Created' : ($status == 204 ? 'No Content' : ($status == 400 ? 'Bad Request' : ($status == 401 ? 'Unauthorized' : ($status == 403 ? 'Forbidden' : ($status == 404 ? 'Not Found' : 'Internal Server Error'))))));

    print $client "HTTP/1.1 $status $status_text\r\n";
    for my $h (keys %{ $res->{headers} // {} }) {
        print $client "$h: " . $res->{headers}{$h} . "\r\n";
    }
    my $body_out = $res->{body} // '';
    print $client "Content-Length: " . length($body_out) . "\r\n";
    print $client "Connection: close\r\n\r\n";
    print $client $body_out;
    close $client;
}

