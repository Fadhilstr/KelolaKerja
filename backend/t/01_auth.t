#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 9;
use FindBin;
use lib "$FindBin::Bin/../lib";

use_ok('KelolaKerja::Config');
use_ok('KelolaKerja::Auth');
use_ok('KelolaKerja::Service::FaceMatcher');
use_ok('KelolaKerja::Response');

# Test 1: Password Hashing & Verification
my $pass = 'rahasia123';
my $hash = KelolaKerja::Auth->hash_password($pass);
ok(KelolaKerja::Auth->verify_password($pass, $hash), 'Password verification succeeds with correct password');
ok(!KelolaKerja::Auth->verify_password('salah123', $hash), 'Password verification fails with wrong password');

# Test 2: Token Issuance & Verification
my $mock_user = { id => 'usr-test-1', username => 'testuser', role => 'EMPLOYEE' };
my $token = KelolaKerja::Auth->issue_token($mock_user);
ok($token && $token =~ /\./, 'Token issued successfully with payload and signature');

my $payload = KelolaKerja::Auth->verify_token($token);
is($payload->{uid}, 'usr-test-1', 'Token verification extracts correct user ID');
is($payload->{role}, 'EMPLOYEE', 'Token verification extracts correct role');

