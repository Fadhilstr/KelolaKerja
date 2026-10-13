package KelolaKerja::Response;
use strict;
use warnings;
use JSON::PP ();
use Exporter 'import';

our @EXPORT_OK = qw(json_response decode_json_body error_response);

sub decode_json_body {
    my ($body_raw) = @_;
    return {} unless defined $body_raw && length($body_raw);
    my $data = eval { JSON::PP::decode_json($body_raw) };
    return $data // {};
}

sub json_response {
    my ($status, $data, $headers) = @_;
    $status //= 200;
    $headers //= {};

    my $body = JSON::PP->new->utf8->allow_nonref->encode($data);

    my %res_headers = (
        'Content-Type'                 => 'application/json; charset=utf-8',
        'Access-Control-Allow-Origin'  => '*',
        'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers' => 'Authorization, Content-Type, Accept, X-Requested-With',
        %$headers,
    );

    return {
        status  => $status,
        headers => \%res_headers,
        body    => $body,
    };
}

sub error_response {
    my ($status, $message, $errors) = @_;
    $status //= 400;
    $message //= 'Terjadi kesalahan pada request';

    return json_response($status, {
        success => 0,
        message => $message,
        errors  => $errors,
    });
}

1;

