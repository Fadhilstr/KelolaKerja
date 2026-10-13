package KelolaKerja::Controller::AdminController;
use strict;
use warnings;
use KelolaKerja::Model::User qw(
    get_all_users
    update_user
    toggle_user_status
    find_user_by_id
);
use KelolaKerja::Model::Audit qw(get_audit_logs log_audit);
use KelolaKerja::Response qw(json_response error_response);

sub list_users {
    my ($class, %req) = @_;
    my $auth = $req{auth};
    return error_response(401, 'Autentikasi diperlukan') unless $auth;

    if ($auth->{role} ne 'ADMIN' && $auth->{role} ne 'SUPERVISOR') {
        return error_response(403, 'Akses ditolak: Hanya Admin atau Supervisor yang dapat melihat daftar pengguna');
    }

    my $users = get_all_users(
        role      => $req{params}{role},
        is_active => $req{params}{is_active},
    );

    return json_response(200, {
        success => 1,
        data    => $users,
    });
}

sub create_user {
    my ($class, %req) = @_;
    my $auth = $req{auth};
    return error_response(401, 'Autentikasi diperlukan') unless $auth;

    if ($auth->{role} ne 'ADMIN') {
        return error_response(403, 'Akses ditolak: Hanya Admin yang dapat mendaftarkan akun baru');
    }

    my $body = $req{body} // {};
    unless ($body->{employee_code} && $body->{name} && $body->{username} && $body->{password}) {
        return error_response(400, 'Kode Karyawan, Nama, Username, dan Password wajib diisi');
    }

    my $user = eval { KelolaKerja::Model::User::create_user(%$body) };
    if ($@ || !$user) {
        return error_response(400, "Gagal membuat user: " . ($@ || 'Data duplikat'));
    }

    log_audit(
        user_id       => $auth->{uid},
        username      => $auth->{username},
        action        => 'USER_CREATE',
        resource_type => 'USER',
        resource_id   => $user->{id},
        status        => 'SUCCESS',
        ip_address    => $req{ip},
        details       => { created_user => $user->{username}, role => $user->{role} }
    );

    return json_response(201, {
        success => 1,
        message => 'User baru berhasil dibuat',
        data    => $user,
    });
}

sub toggle_status {
    my ($class, %req) = @_;
    my $auth = $req{auth};
    return error_response(401, 'Autentikasi diperlukan') unless $auth;

    if ($auth->{role} ne 'ADMIN') {
        return error_response(403, 'Akses ditolak: Hanya Admin yang dapat mengubah status akun');
    }

    my $id = $req{params}{id};
    my $body = $req{body} // {};
    my $is_active = $body->{is_active} ? 1 : 0;

    my $updated = toggle_user_status($id, $is_active);
    unless ($updated) {
        return error_response(404, 'User tidak ditemukan');
    }

    log_audit(
        user_id       => $auth->{uid},
        username      => $auth->{username},
        action        => 'USER_TOGGLE_STATUS',
        resource_type => 'USER',
        resource_id   => $id,
        status        => 'SUCCESS',
        ip_address    => $req{ip},
        details       => { is_active => $is_active }
    );

    return json_response(200, {
        success => 1,
        message => 'Status pengguna berhasil diperbarui',
        data    => $updated,
    });
}

sub audit_logs {
    my ($class, %req) = @_;
    my $auth = $req{auth};
    return error_response(401, 'Autentikasi diperlukan') unless $auth;

    if ($auth->{role} ne 'ADMIN') {
        return error_response(403, 'Akses ditolak: Hanya Admin yang memiliki akses Audit Log');
    }

    my $logs = get_audit_logs(
        action  => $req{params}{action},
        user_id => $req{params}{user_id},
        status  => $req{params}{status},
        limit   => $req{params}{limit} // 50,
    );

    return json_response(200, {
        success => 1,
        data    => $logs,
    });
}

1;
