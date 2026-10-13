#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 10;
use FindBin;
use lib "$FindBin::Bin/../lib";

use KelolaKerja::Auth;
use KelolaKerja::Router;
use KelolaKerja::Response qw(decode_json_body);

# 1. Health check (Public)
my $res_health = KelolaKerja::Router::dispatch(
    method => 'GET',
    path   => '/api/health'
);
is($res_health->{status}, 200, 'GET /api/health returns 200');

# 2. Public Login Endpoint Validation
my $res_bad_login = KelolaKerja::Router::dispatch(
    method => 'POST',
    path   => '/api/auth/login',
    body   => {}
);
is($res_bad_login->{status}, 400, 'POST /api/auth/login with empty body returns 400');

# 3. Protected Route without token
my $res_unauth = KelolaKerja::Router::dispatch(
    method  => 'GET',
    path    => '/api/auth/me',
    headers => {}
);
is($res_unauth->{status}, 401, 'Protected route without token returns 401 Unauthorized');

# 4. Protected Route with invalid token
my $res_invalid = KelolaKerja::Router::dispatch(
    method  => 'GET',
    path    => '/api/auth/me',
    headers => { authorization => 'Bearer token_palsu_random' }
);
is($res_invalid->{status}, 401, 'Protected route with invalid signature returns 401 Unauthorized');

# 5. Protected Route with valid token but non-admin role requesting Admin Users
my $token_emp = KelolaKerja::Auth->issue_token({ id => 'emp-1', username => 'karyawan', role => 'EMPLOYEE' });
my $res_rbac_denied = KelolaKerja::Router::dispatch(
    method  => 'GET',
    path    => '/api/admin/users',
    headers => { authorization => "Bearer $token_emp" }
);
is($res_rbac_denied->{status}, 403, 'EMPLOYEE role attempting GET /api/admin/users returns 403 Forbidden (RBAC enforced)');

# 6. Biometric challenge issuance
my $res_challenge = KelolaKerja::Router::dispatch(
    method  => 'GET',
    path    => '/api/biometric/challenge',
    headers => { authorization => "Bearer $token_emp" }
);
is($res_challenge->{status}, 200, 'GET /api/biometric/challenge issues signed challenge token');

# 7. Biometric registration validation (dimension check)
my $res_bio_invalid = KelolaKerja::Router::dispatch(
    method  => 'POST',
    path    => '/api/biometric/register',
    headers => { authorization => "Bearer $token_emp" },
    body    => { embedding => [ 0.1, 0.2 ] }
);
is($res_bio_invalid->{status}, 400, 'POST /api/biometric/register with wrong vector size returns 400');

# 8. Biometric registration rejects flat luminance vector (anti-spoof integrity)
my $res_bio_flat = KelolaKerja::Router::dispatch(
    method  => 'POST',
    path    => '/api/biometric/register',
    headers => { authorization => "Bearer $token_emp" },
    body    => { embedding => [ (0.088) x 128 ] }
);
is($res_bio_flat->{status}, 400, 'POST /api/biometric/register rejects non-ResNet flat vector');

# 9. Check-in liveness validation
my $res_checkin_liveness = KelolaKerja::Router::dispatch(
    method  => 'POST',
    path    => '/api/attendance/check-in',
    headers => { authorization => "Bearer $token_emp" },
    body    => { embedding => [ (0.1) x 128 ], liveness_passed => 0 }
);
is($res_checkin_liveness->{status}, 400, 'POST /api/attendance/check-in with failed liveness returns 400');

# 10. Report validation
my $res_rep_invalid = KelolaKerja::Router::dispatch(
    method  => 'POST',
    path    => '/api/reports',
    headers => { authorization => "Bearer $token_emp" },
    body    => {}
);
is($res_rep_invalid->{status}, 400, 'POST /api/reports without title/desc returns 400');
