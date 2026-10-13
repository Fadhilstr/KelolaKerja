package KelolaKerja::Controller::AttendanceController;
use strict;
use warnings;
use KelolaKerja::Model::Attendance qw(
    record_check_in
    record_check_out
    get_today_attendance
    get_attendance_history
    get_attendance_summary_today
    get_admin_attendance_overview
);
use KelolaKerja::Model::User qw(get_face_biometrics get_all_face_biometrics find_user_by_id);
use KelolaKerja::Model::Audit qw(log_audit);
use KelolaKerja::Service::FaceMatcher qw(
    verify_embedding
    parse_embedding
    validate_descriptor_integrity
    verify_liveness_challenge
);
use KelolaKerja::Response qw(json_response error_response);

sub _verify_attendance_biometrics {
    my ($auth, $body, $ip, $action_prefix) = @_;
    my $user_id = $auth->{uid};

    my $candidate_embedding = $body->{embedding};
    unless ($candidate_embedding) {
        return (0, error_response(400, 'Data vektor embedding wajah tidak ditemukan dalam request.'), undef);
    }

    my $liveness_passed = $body->{liveness_passed};
    unless (defined $liveness_passed && $liveness_passed == 1) {
        return (0, error_response(400, 'Verifikasi liveness gagal. Selesaikan tantangan gerakan 3D di depan kamera terlebih dahulu.'), undef);
    }

    # Validate neural network descriptor integrity
    my ($valid_vec, $vec_err) = validate_descriptor_integrity($candidate_embedding);
    unless ($valid_vec) {
        return (0, error_response(400, $vec_err), undef);
    }

    # Verify active challenge-response liveness token & landmark telemetry
    my ($live_ok, $live_err) = verify_liveness_challenge(
        $user_id,
        $body->{challenge_token},
        $body->{liveness_proof},
        $candidate_embedding
    );
    unless ($live_ok) {
        eval {
            log_audit(
                user_id       => $user_id,
                username      => $auth->{username},
                action        => "${action_prefix}_SPOOF_REJECTED",
                resource_type => 'ATTENDANCE',
                status        => 'DENIED',
                ip_address    => $ip,
                details       => { reason => $live_err }
            );
        };
        return (0, error_response(403, "ANTI-SPOOFING MENOLAK ABSENSI: $live_err"), undef);
    }

    my $biometric = eval { get_face_biometrics($user_id) };
    unless ($biometric) {
        return (0, error_response(400, 'Wajah Anda belum terdaftar di sistem. Silakan lakukan Registrasi Wajah terlebih dahulu.'), undef);
    }

    if (($biometric->{model_version} // '') ne 'resnet34-128d') {
        return (0, error_response(400, 'Data biometrik lama terdeteksi. Silakan daftarkan ulang wajah Anda dengan model Neural Network ResNet-34 di menu Registrasi Wajah.'), undef);
    }

    # Strict 1:1 Verification against account owner's registered face (Threshold: 0.42, Cosine >= 0.89)
    my $match_result = verify_embedding($biometric->{embedding_json}, $candidate_embedding, 0.42);
    unless ($match_result->{is_match}) {
        # Check if the impostor face belongs to another registered employee for audit logging
        my $impostor_info = '';
        my $all_bios = eval { get_all_face_biometrics() } // [];
        for my $other (@$all_bios) {
            next if $other->{user_id} eq $user_id;
            my $cross = verify_embedding($other->{embedding_json}, $candidate_embedding, 0.44);
            if ($cross->{is_match}) {
                $impostor_info = sprintf(" [Terdeteksi mirip akun lain: %s (%s)]", $other->{name}, $other->{employee_code});
                last;
            }
        }

        eval {
            log_audit(
                user_id       => $user_id,
                username      => $auth->{username},
                action        => "${action_prefix}_FACE_MISMATCH",
                resource_type => 'ATTENDANCE',
                status        => 'FAILURE',
                ip_address    => $ip,
                details       => {
                    distance      => $match_result->{distance},
                    threshold     => $match_result->{threshold},
                    similarity    => $match_result->{similarity},
                    impostor_note => $impostor_info
                }
            );
        };

        return (0, error_response(403, sprintf(
            'VERIFIKASI WAJAH DITOLAK: Wajah di depan kamera TIDAK COCOK dengan identitas pemilik akun %s! (Jarak Biometrik: %.4f > Batas Maksimal: %.4f | Kemiripan: %.1f%%).%s Absensi tidak dicatat.',
            $auth->{username},
            $match_result->{distance},
            $match_result->{threshold},
            $match_result->{similarity} * 100,
            $impostor_info
        )), undef);
    }

    return (1, undef, $match_result);
}

sub check_in {
    my ($class, %req) = @_;
    my $auth = $req{auth};
    return error_response(401, 'Autentikasi diperlukan') unless $auth;

    my $body = $req{body} // {};
    my $user_id = $auth->{uid};

    my ($ok, $err_res, $match_result) = _verify_attendance_biometrics($auth, $body, $req{ip}, 'CHECK_IN');
    return $err_res unless $ok;

    my $user = eval { find_user_by_id($user_id) };
    if ($@) {
        return error_response(503, 'Layanan database tidak tersedia saat ini');
    }
    return error_response(403, 'Akun nonaktif') unless $user && $user->{is_active};

    my $today = eval { get_today_attendance($user_id) };
    if ($today && $today->{check_in_time}) {
        return error_response(400, 'Anda sudah melakukan absensi masuk hari ini pada ' . $today->{check_in_time});
    }

    my $attendance = record_check_in(
        user_id     => $user_id,
        match_score => $match_result->{distance},
        photo_path  => $body->{photo_path} // 'audit_captured.jpg',
        notes       => sprintf('Verified ResNet-34 (Dist: %.4f, Sim: %.1f%%)', $match_result->{distance}, $match_result->{similarity} * 100),
        ip_address  => $req{ip},
        user_agent  => $req{headers}{'user-agent'},
    );

    log_audit(
        user_id       => $user_id,
        username      => $auth->{username},
        action        => 'CHECK_IN',
        resource_type => 'ATTENDANCE',
        resource_id   => $attendance->{id},
        status        => 'SUCCESS',
        ip_address    => $req{ip},
        user_agent    => $req{headers}{'user-agent'},
        details       => {
            match_score => $match_result->{distance},
            similarity  => $match_result->{similarity},
            status      => $attendance->{status}
        }
    );

    return json_response(200, {
        success => 1,
        message => sprintf('Absensi masuk berhasil! Wajah terverifikasi cocok (Kemiripan: %.1f%%, Jarak: %.4f).', $match_result->{similarity} * 100, $match_result->{distance}),
        data    => $attendance,
    });
}

sub check_out {
    my ($class, %req) = @_;
    my $auth = $req{auth};
    return error_response(401, 'Autentikasi diperlukan') unless $auth;

    my $body = $req{body} // {};
    my $user_id = $auth->{uid};

    my ($ok, $err_res, $match_result) = _verify_attendance_biometrics($auth, $body, $req{ip}, 'CHECK_OUT');
    return $err_res unless $ok;

    my $user = eval { find_user_by_id($user_id) };
    return error_response(403, 'Akun nonaktif') unless $user && $user->{is_active};

    my $today = get_today_attendance($user_id);
    unless ($today && $today->{check_in_time}) {
        return error_response(400, 'Anda belum melakukan absensi masuk hari ini.');
    }

    if ($today->{check_out_time}) {
        return error_response(400, 'Anda sudah melakukan absensi pulang hari ini pada ' . $today->{check_out_time});
    }

    my $attendance = record_check_out(
        user_id     => $user_id,
        match_score => $match_result->{distance},
        photo_path  => $body->{photo_path} // 'audit_checkout.jpg',
        notes       => sprintf('Checkout ResNet-34 (Dist: %.4f)', $match_result->{distance}),
    );

    log_audit(
        user_id       => $user_id,
        username      => $auth->{username},
        action        => 'CHECK_OUT',
        resource_type => 'ATTENDANCE',
        resource_id   => $attendance->{id},
        status        => 'SUCCESS',
        ip_address    => $req{ip},
        user_agent    => $req{headers}{'user-agent'},
        details       => {
            match_score => $match_result->{distance},
            similarity  => $match_result->{similarity}
        }
    );

    return json_response(200, {
        success => 1,
        message => sprintf('Absensi pulang berhasil! Wajah terverifikasi cocok (Kemiripan: %.1f%%, Jarak: %.4f).', $match_result->{similarity} * 100, $match_result->{distance}),
        data    => $attendance,
    });
}

sub today_status {
    my ($class, %req) = @_;
    my $auth = $req{auth};
    return error_response(401, 'Autentikasi diperlukan') unless $auth;

    my $today = get_today_attendance($auth->{uid});
    return json_response(200, {
        success => 1,
        data    => $today,
    });
}

sub my_history {
    my ($class, %req) = @_;
    my $auth = $req{auth};
    return error_response(401, 'Autentikasi diperlukan') unless $auth;

    my $history = get_attendance_history(
        user_id    => $auth->{uid},
        start_date => $req{params}{start_date},
        end_date   => $req{params}{end_date},
        limit      => $req{params}{limit} // 31,
    );

    return json_response(200, {
        success => 1,
        data    => $history,
    });
}

sub admin_overview {
    my ($class, %req) = @_;
    my $auth = $req{auth};
    return error_response(401, 'Autentikasi diperlukan') unless $auth;

    if ($auth->{role} ne 'ADMIN' && $auth->{role} ne 'SUPERVISOR') {
        return error_response(403, 'Akses ditolak: Hanya untuk Admin atau Supervisor');
    }

    my $summary = get_attendance_summary_today();
    my $list = get_attendance_history(
        start_date => $req{params}{start_date},
        end_date   => $req{params}{end_date},
        status     => $req{params}{status},
        limit      => $req{params}{limit} // 50,
    );

    return json_response(200, {
        success => 1,
        data    => {
            summary => $summary,
            records => $list,
        }
    });
}

1;
