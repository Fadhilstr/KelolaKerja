package KelolaKerja::Controller::BiometricController;
use strict;
use warnings;
use JSON::PP ();
use KelolaKerja::Model::User qw(
    save_face_biometrics
    get_face_biometrics
    get_all_face_biometrics
    delete_face_biometrics
    find_user_by_id
);
use KelolaKerja::Model::Audit qw(log_audit);
use KelolaKerja::Service::FaceMatcher qw(
    verify_embedding
    parse_embedding
    validate_descriptor_integrity
    issue_liveness_challenge
    verify_liveness_challenge
);
use KelolaKerja::Response qw(json_response error_response);

sub get_challenge {
    my ($class, %req) = @_;
    my $auth = $req{auth};
    return error_response(401, 'Autentikasi diperlukan') unless $auth;

    my $challenge_data = issue_liveness_challenge($auth->{uid});
    return json_response(200, {
        success => 1,
        data    => $challenge_data,
    });
}

sub register_face {
    my ($class, %req) = @_;
    my $auth = $req{auth};
    return error_response(401, 'Autentikasi diperlukan') unless $auth;

    my $body = $req{body} // {};
    my $target_user_id = $body->{user_id} // $auth->{uid};

    # RBAC: Only ADMIN or the user themselves can register biometric data
    if ($target_user_id ne $auth->{uid} && $auth->{role} ne 'ADMIN') {
        log_audit(
            user_id       => $auth->{uid},
            username      => $auth->{username},
            action        => 'FACE_REGISTER',
            resource_type => 'BIOMETRIC',
            resource_id   => $target_user_id,
            status        => 'DENIED',
            ip_address    => $req{ip},
            details       => { reason => 'Forbidden cross-user registration' }
        );
        return error_response(403, 'Akses ditolak: Anda tidak memiliki hak akses untuk mendaftarkan wajah pengguna lain');
    }

    my $embedding_raw = $body->{embedding};
    my $embedding = parse_embedding($embedding_raw);

    # Standard face descriptor length: 128 elements (or 512 for larger models)
    if (@$embedding != 128 && @$embedding != 512) {
        return error_response(400, sprintf("Format embedding wajah tidak valid. Membutuhkan 128 atau 512 dimensi vektor numerik (diterima: %d)", scalar(@$embedding)));
    }

    # Validate deep learning descriptor integrity (reject flat/fake luminance arrays)
    my ($valid_vec, $vec_err) = validate_descriptor_integrity($embedding);
    unless ($valid_vec) {
        return error_response(400, $vec_err);
    }

    # Verify liveness challenge if provided
    if ($body->{challenge_token}) {
        my ($live_ok, $live_err) = verify_liveness_challenge(
            $auth->{uid},
            $body->{challenge_token},
            $body->{liveness_proof},
            $embedding
        );
        unless ($live_ok) {
            log_audit(
                user_id       => $auth->{uid},
                username      => $auth->{username},
                action        => 'FACE_REGISTER_SPOOF_BLOCKED',
                resource_type => 'BIOMETRIC',
                status        => 'DENIED',
                ip_address    => $req{ip},
                details       => { reason => $live_err }
            );
            return error_response(400, "Verifikasi Anti-Spoofing Gagal: $live_err");
        }
    }

    my $user = eval { find_user_by_id($target_user_id) };
    if ($@) {
        return error_response(503, 'Layanan database tidak tersedia saat ini');
    }
    return error_response(404, 'Karyawan tidak ditemukan') unless $user;

    # Verify quality metrics
    my $quality_score = defined $body->{quality_score} ? (0.0 + $body->{quality_score}) : 1.0;
    if ($quality_score < 0.6) {
        return error_response(400, 'Kualitas tangkapan wajah tidak memenuhi standar minimal pencahayaan atau fokus (quality < 0.6)');
    }

    # Protection 1: Prevent overwriting an already-registered face with a different person's face!
    my $existing_bio = eval { get_face_biometrics($target_user_id) };
    if ($existing_bio && $auth->{role} ne 'ADMIN') {
        my $self_match = verify_embedding($existing_bio->{embedding_json}, $embedding, 0.42);
        unless ($self_match->{is_match}) {
            log_audit(
                user_id       => $auth->{uid},
                username      => $auth->{username},
                action        => 'FACE_OVERWRITE_BLOCKED',
                resource_type => 'BIOMETRIC',
                resource_id   => $target_user_id,
                status        => 'DENIED',
                ip_address    => $req{ip},
                details       => {
                    distance   => $self_match->{distance},
                    similarity => $self_match->{similarity},
                    reason     => 'Attempted to overwrite registered face with a different person face'
                }
            );
            return error_response(403, sprintf(
                'DITOLAK: Akun ini sudah memiliki wajah terdaftar dan wajah yang baru dipindai TIDAK COCOK dengan pemilik akun (Jarak: %.4f > 0.4200, Kemiripan: %.1f%%). Hanya Administrator yang dapat mereset data biometrik.',
                $self_match->{distance},
                $self_match->{similarity} * 100
            ));
        }
    }

    # Protection 2: 1:N Cross-Account Uniqueness Check (1 face = 1 account)
    my $all_bios = eval { get_all_face_biometrics() } // [];
    for my $other (@$all_bios) {
        next if $other->{user_id} eq $target_user_id;
        my $cross_match = verify_embedding($other->{embedding_json}, $embedding, 0.45);
        if ($cross_match->{is_match}) {
            log_audit(
                user_id       => $auth->{uid},
                username      => $auth->{username},
                action        => 'FACE_DUPLICATE_ACCOUNT_BLOCKED',
                resource_type => 'BIOMETRIC',
                resource_id   => $target_user_id,
                status        => 'DENIED',
                ip_address    => $req{ip},
                details       => {
                    matched_user => $other->{username},
                    distance     => $cross_match->{distance},
                    similarity   => $cross_match->{similarity}
                }
            );
            return error_response(409, sprintf(
                'DITOLAK: Wajah ini sudah terdaftar pada akun karyawan lain (%s - %s, kemiripan %.1f%%). Satu wajah tidak boleh digunakan untuk banyak akun!',
                $other->{name},
                $other->{employee_code},
                $cross_match->{similarity} * 100
            ));
        }
    }

    my $embedding_json = JSON::PP::encode_json($embedding);
    my $saved = save_face_biometrics($target_user_id, $embedding_json, scalar(@$embedding), $quality_score);

    if ($saved) {
        log_audit(
            user_id       => $auth->{uid},
            username      => $auth->{username},
            action        => 'FACE_REGISTER',
            resource_type => 'BIOMETRIC',
            resource_id   => $target_user_id,
            status        => 'SUCCESS',
            ip_address    => $req{ip},
            user_agent    => $req{headers}{'user-agent'},
            details       => { target_user => $user->{username}, dimensions => scalar(@$embedding), quality => $quality_score }
        );

        return json_response(200, {
            success => 1,
            message => 'Biometrik wajah ResNet-34 (128-D) berhasil didaftarkan dan dikunci pada akun Anda.',
            data    => {
                user_id        => $target_user_id,
                dimensions     => scalar(@$embedding),
                registered_at  => scalar(localtime),
            }
        });
    }

    return error_response(500, 'Gagal menyimpan data biometrik wajah ke database');
}

sub reset_biometric {
    my ($class, %req) = @_;
    my $auth = $req{auth};
    return error_response(401, 'Autentikasi diperlukan') unless $auth;
    return error_response(403, 'Hanya Admin yang dapat mereset data biometrik') unless $auth->{role} eq 'ADMIN';

    my $target_user_id = $req{params}{id};
    return error_response(400, 'ID user diperlukan') unless $target_user_id;

    delete_face_biometrics($target_user_id);

    log_audit(
        user_id       => $auth->{uid},
        username      => $auth->{username},
        action        => 'FACE_BIOMETRIC_RESET',
        resource_type => 'BIOMETRIC',
        resource_id   => $target_user_id,
        status        => 'SUCCESS',
        ip_address    => $req{ip}
    );

    return json_response(200, {
        success => 1,
        message => 'Data biometrik wajah pengguna berhasil direset. Pengguna dapat mendaftarkan wajah baru.'
    });
}

sub get_status {
    my ($class, %req) = @_;
    my $auth = $req{auth};
    return error_response(401, 'Autentikasi diperlukan') unless $auth;

    my $target_user_id = $req{params}{user_id} // $auth->{uid};
    if ($target_user_id ne $auth->{uid} && $auth->{role} ne 'ADMIN' && $auth->{role} ne 'SUPERVISOR') {
        return error_response(403, 'Akses ditolak');
    }

    my $biometric = get_face_biometrics($target_user_id);
    return json_response(200, {
        success => 1,
        data    => {
            is_registered   => $biometric ? 1 : 0,
            registered_at   => $biometric ? $biometric->{registered_at} : undef,
            quality_score   => $biometric ? (0.0 + $biometric->{quality_score}) : undef,
            model_version   => $biometric ? $biometric->{model_version} : undef,
        }
    });
}

1;
