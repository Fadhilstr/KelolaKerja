package KelolaKerja::Router;
use strict;
use warnings;
use Exporter 'import';

use KelolaKerja::Auth qw(authenticate_request);
use KelolaKerja::Response qw(json_response error_response);

use KelolaKerja::Controller::AuthController;
use KelolaKerja::Controller::BiometricController;
use KelolaKerja::Controller::AttendanceController;
use KelolaKerja::Controller::ReportController;
use KelolaKerja::Controller::AdminController;

our @EXPORT_OK = qw(dispatch);

# Routing table: [ METHOD, PATH_REGEX, CONTROLLER_CLASS, METHOD_NAME, REQUIRE_AUTH ]
my @ROUTES = (
    # Public routes
    [ 'OPTIONS', qr{^/api/.*$},                        \&_handle_cors, 0 ],
    [ 'GET',     qr{^/api/health$},                    \&_handle_health, 0 ],
    [ 'POST',    qr{^/api/auth/login$},                'KelolaKerja::Controller::AuthController', 'login', 0 ],

    # Authenticated Auth routes
    [ 'GET',     qr{^/api/auth/me$},                   'KelolaKerja::Controller::AuthController', 'me', 1 ],
    [ 'POST',    qr{^/api/auth/logout$},               'KelolaKerja::Controller::AuthController', 'logout', 1 ],

    # Biometric / Face Recognition routes
    [ 'GET',     qr{^/api/biometric/challenge$},       'KelolaKerja::Controller::BiometricController', 'get_challenge', 1 ],
    [ 'POST',    qr{^/api/biometric/register$},        'KelolaKerja::Controller::BiometricController', 'register_face', 1 ],
    [ 'GET',     qr{^/api/biometric/status$},          'KelolaKerja::Controller::BiometricController', 'get_status', 1 ],

    # Attendance routes
    [ 'POST',    qr{^/api/attendance/check-in$},       'KelolaKerja::Controller::AttendanceController', 'check_in', 1 ],
    [ 'POST',    qr{^/api/attendance/check-out$},      'KelolaKerja::Controller::AttendanceController', 'check_out', 1 ],
    [ 'GET',     qr{^/api/attendance/today$},          'KelolaKerja::Controller::AttendanceController', 'today_status', 1 ],
    [ 'GET',     qr{^/api/attendance/history$},        'KelolaKerja::Controller::AttendanceController', 'my_history', 1 ],
    [ 'GET',     qr{^/api/attendance/admin-overview$}, 'KelolaKerja::Controller::AttendanceController', 'admin_overview', 1 ],

    # Report routes
    [ 'GET',     qr{^/api/reports$},                   'KelolaKerja::Controller::ReportController', 'index', 1 ],
    [ 'POST',    qr{^/api/reports$},                   'KelolaKerja::Controller::ReportController', 'store', 1 ],
    [ 'PUT',     qr{^/api/reports/(?<id>[^/]+)$},      'KelolaKerja::Controller::ReportController', 'update', 1 ],
    [ 'POST',    qr{^/api/reports/(?<id>[^/]+)/verify$}, 'KelolaKerja::Controller::ReportController', 'verify', 1 ],

    # Admin routes
    [ 'GET',     qr{^/api/admin/users$},               'KelolaKerja::Controller::AdminController', 'list_users', 1 ],
    [ 'POST',    qr{^/api/admin/users$},               'KelolaKerja::Controller::AdminController', 'create_user', 1 ],
    [ 'PUT',     qr{^/api/admin/users/(?<id>[^/]+)/status$}, 'KelolaKerja::Controller::AdminController', 'toggle_status', 1 ],
    [ 'DELETE',  qr{^/api/admin/users/(?<id>[^/]+)/biometric$}, 'KelolaKerja::Controller::BiometricController', 'reset_biometric', 1 ],
    [ 'GET',     qr{^/api/admin/audit-logs$},          'KelolaKerja::Controller::AdminController', 'audit_logs', 1 ],
);

sub _handle_cors {
    my (%req) = @_;
    return json_response(204, '');
}

sub _handle_health {
    my (%req) = @_;
    return json_response(200, {
        status    => 'OK',
        app       => 'KelolaKerja Backend API',
        version   => '1.0.0',
        timestamp => scalar(localtime),
    });
}

sub dispatch {
    my (%req) = @_;
    my $method = $req{method};
    my $path   = $req{path};

    for my $r (@ROUTES) {
        my ($r_method, $r_regex, $r_target, $r_action, $require_auth) = @$r;
        next unless $r_method eq $method;

        if ($path =~ $r_regex) {
            my %path_params = %+;
            $req{params} = { %{ $req{params} // {} }, %path_params };

            if ($require_auth) {
                my $auth = KelolaKerja::Auth->authenticate_request(\%req);
                unless ($auth) {
                    return error_response(401, 'Autentikasi gagal: Token tidak valid atau telah kedaluwarsa');
                }
                $req{auth} = $auth;
            }

            if (ref($r_target) eq 'CODE') {
                return $r_target->(%req);
            } else {
                return $r_target->$r_action(%req);
            }
        }
    }

    return error_response(404, "Endpoint tidak ditemukan: $method $path");
}

1;
