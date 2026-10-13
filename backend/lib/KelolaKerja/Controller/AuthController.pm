package KelolaKerja::Controller::AuthController;
use strict;
use warnings;
use KelolaKerja::Model::User qw(find_user_by_username_or_email find_user_by_id);
use KelolaKerja::Model::Audit qw(log_audit);
use KelolaKerja::Auth qw(verify_password issue_token);
use KelolaKerja::Response qw(json_response error_response);

sub login {
    my ($class, %req) = @_;
    my $body = $req{body} // {};
    my $username = $body->{username};
    my $password = $body->{password};

    unless ($username && $password) {
        return error_response(400, 'Username dan password wajib diisi');
    }

    my $user = find_user_by_username_or_email($username);
    unless ($user) {
        log_audit(
            action        => 'LOGIN_ATTEMPT',
            resource_type => 'USER',
            status        => 'FAILURE',
            ip_address    => $req{ip},
            user_agent    => $req{headers}{'user-agent'},
            details       => { username => $username, reason => 'User tidak ditemukan' }
        );
        return error_response(401, 'Username atau password tidak sesuai');
    }

    unless ($user->{is_active}) {
        log_audit(
            user_id       => $user->{id},
            username      => $user->{username},
            action        => 'LOGIN_ATTEMPT',
            resource_type => 'USER',
            status        => 'DENIED',
            ip_address    => $req{ip},
            user_agent    => $req{headers}{'user-agent'},
            details       => { reason => 'Akun nonaktif' }
        );
        return error_response(403, 'Akun Anda telah dinonaktifkan. Silakan hubungi Administrator.');
    }

    unless (KelolaKerja::Auth->verify_password($password, $user->{password_hash})) {
        log_audit(
            user_id       => $user->{id},
            username      => $user->{username},
            action        => 'LOGIN_ATTEMPT',
            resource_type => 'USER',
            status        => 'FAILURE',
            ip_address    => $req{ip},
            user_agent    => $req{headers}{'user-agent'},
            details       => { reason => 'Password salah' }
        );
        return error_response(401, 'Username atau password tidak sesuai');
    }

    my $token = KelolaKerja::Auth->issue_token($user);

    log_audit(
        user_id       => $user->{id},
        username      => $user->{username},
        action        => 'LOGIN_SUCCESS',
        resource_type => 'USER',
        status        => 'SUCCESS',
        ip_address    => $req{ip},
        user_agent    => $req{headers}{'user-agent'},
        details       => { role => $user->{role} }
    );

    # Sanitize user object for response
    delete $user->{password_hash};

    return json_response(200, {
        success => 1,
        message => 'Login berhasil',
        data    => {
            token => $token,
            user  => $user,
        }
    });
}

sub me {
    my ($class, %req) = @_;
    my $auth = $req{auth};
    return error_response(401, 'Sesi tidak valid') unless $auth;

    my $user = find_user_by_id($auth->{uid});
    return error_response(404, 'User tidak ditemukan') unless $user;
    return error_response(403, 'Akun nonaktif') unless $user->{is_active};

    return json_response(200, {
        success => 1,
        data    => $user,
    });
}

sub logout {
    my ($class, %req) = @_;
    my $auth = $req{auth};
    if ($auth) {
        log_audit(
            user_id       => $auth->{uid},
            username      => $auth->{username},
            action        => 'LOGOUT',
            resource_type => 'USER',
            status        => 'SUCCESS',
            ip_address    => $req{ip},
            user_agent    => $req{headers}{'user-agent'}
        );
    }
    return json_response(200, {
        success => 1,
        message => 'Logout berhasil'
    });
}

1;

