package KelolaKerja::Auth;
use strict;
use warnings;
use Digest::SHA qw(sha256_hex hmac_sha256_hex);
use MIME::Base64 qw(encode_base64url decode_base64url);
use JSON::PP ();
use Exporter 'import';
use KelolaKerja::Config qw(config);

our @EXPORT_OK = qw(
    verify_password
    hash_password
    issue_token
    verify_token
    authenticate_request
    generate_uuid
);

# Generate unique ID (RFC4122 v4 UUID format)
sub generate_uuid {
    my $bytes = '';
    if (open my $fh, '<:raw', '/dev/urandom') {
        read($fh, $bytes, 16);
        close $fh;
    } else {
        $bytes = pack('N*', int(rand(0xFFFFFFFF)), int(rand(0xFFFFFFFF)), int(rand(0xFFFFFFFF)), int(rand(0xFFFFFFFF)));
    }
    my @b = unpack('C16', $bytes);
    $b[6] = ($b[6] & 0x0f) | 0x40; # Version 4
    $b[8] = ($b[8] & 0x3f) | 0x80; # Variant 1
    return sprintf('%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x', @b);
}

# Generate secure random salt
sub generate_salt {
    my $bytes = '';
    if (open my $fh, '<:raw', '/dev/urandom') {
        read($fh, $bytes, 8);
        close $fh;
    } else {
        $bytes = pack('N*', int(rand(0xFFFFFFFF)), int(rand(0xFFFFFFFF)));
    }
    return unpack('H*', $bytes);
}

# Hash password using sha256 with cryptographically generated salt
sub hash_password {
    my ($class, $password, $salt) = @_;
    $salt //= generate_salt();
    my $hash = sha256_hex($salt . $password);
    return "sha256\$$salt\$$hash";
}

# Constant-time string comparison to prevent timing attacks
sub _constant_time_equals {
    my ($a, $b) = @_;
    return 0 unless defined $a && defined $b;
    return 0 if length($a) != length($b);
    my $result = 0;
    for (my $i = 0; $i < length($a); $i++) {
        $result |= ord(substr($a, $i, 1)) ^ ord(substr($b, $i, 1));
    }
    return $result == 0 ? 1 : 0;
}

# Verify password against stored hash
sub verify_password {
    my ($class, $password, $stored_hash) = @_;
    return 0 unless defined $password && defined $stored_hash;

    my ($scheme, $salt, $hash) = split /\$/, $stored_hash, 3;
    return 0 unless defined $scheme && $scheme eq 'sha256';
    return 0 unless defined $salt && defined $hash;

    my $computed = sha256_hex($salt . $password);
    return _constant_time_equals($computed, lc($hash));
}

# Issue signed HMAC-SHA256 JWT-style token
sub issue_token {
    my ($class, $user_data) = @_;
    my $cfg = config();

    my $payload_data = {
        uid      => $user_data->{id},
        username => $user_data->{username},
        role     => $user_data->{role},
        exp      => time() + $cfg->{token_ttl},
        iat      => time(),
    };

    my $payload = encode_base64url(JSON::PP::encode_json($payload_data));
    my $sig = hmac_sha256_hex($payload, $cfg->{token_secret});

    return "$payload.$sig";
}

# Verify signed token
sub verify_token {
    my ($class, $token) = @_;
    return undef unless defined $token && $token =~ /\./;

    my ($payload, $sig) = split /\./, $token, 2;
    return undef unless defined $payload && defined $sig;

    my $cfg = config();
    my $expected_sig = hmac_sha256_hex($payload, $cfg->{token_secret});
    return undef unless _constant_time_equals($sig, $expected_sig);

    my $data = eval { JSON::PP::decode_json(decode_base64url($payload)) };
    return undef unless $data && $data->{uid} && $data->{role} && $data->{exp};
    return undef unless $data->{exp} > time();

    return $data;
}

# Extract and authenticate Bearer token from HTTP request
sub authenticate_request {
    my ($class, $req) = @_;
    my $auth_header = $req->{headers}{authorization} // '';
    return undef unless $auth_header =~ /^Bearer\s+(\S+)$/i;

    return __PACKAGE__->verify_token($1);
}

1;

