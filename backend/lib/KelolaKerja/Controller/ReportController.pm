package KelolaKerja::Controller::ReportController;
use strict;
use warnings;
use KelolaKerja::Model::Report qw(
    create_report
    update_report
    verify_report
    get_report_by_id
    get_reports
    get_report_summary
);
use KelolaKerja::Model::Audit qw(log_audit);
use KelolaKerja::Response qw(json_response error_response);

sub index {
    my ($class, %req) = @_;
    my $auth = $req{auth};
    return error_response(401, 'Autentikasi diperlukan') unless $auth;

    my %filter = (
        status     => $req{params}{status},
        start_date => $req{params}{start_date},
        end_date   => $req{params}{end_date},
        limit      => $req{params}{limit} // 50,
    );

    # RBAC: EMPLOYEE can only view their own reports
    if ($auth->{role} eq 'EMPLOYEE') {
        $filter{user_id} = $auth->{uid};
    } elsif ($req{params}{user_id}) {
        # ADMIN and SUPERVISOR can filter by specific user
        $filter{user_id} = $req{params}{user_id};
    }

    my $reports = get_reports(%filter);
    my $summary = ($auth->{role} eq 'ADMIN' || $auth->{role} eq 'SUPERVISOR') ? get_report_summary() : undef;

    return json_response(200, {
        success => 1,
        data    => {
            reports => $reports,
            summary => $summary,
        }
    });
}

sub store {
    my ($class, %req) = @_;
    my $auth = $req{auth};
    return error_response(401, 'Autentikasi diperlukan') unless $auth;

    my $body = $req{body} // {};
    unless ($body->{title} && $body->{activity_description}) {
        return error_response(400, 'Judul dan deskripsi aktivitas pekerjaan wajib diisi');
    }

    my $report = create_report(
        user_id              => $auth->{uid},
        report_date          => $body->{report_date},
        title                => $body->{title},
        activity_description => $body->{activity_description},
        results_achieved     => $body->{results_achieved},
        obstacles            => $body->{obstacles},
    );

    log_audit(
        user_id       => $auth->{uid},
        username      => $auth->{username},
        action        => 'REPORT_CREATE',
        resource_type => 'REPORT',
        resource_id   => $report->{id},
        status        => 'SUCCESS',
        ip_address    => $req{ip},
        details       => { title => $body->{title} }
    );

    return json_response(201, {
        success => 1,
        message => 'Laporan aktivitas harian berhasil dikirim',
        data    => $report,
    });
}

sub update {
    my ($class, %req) = @_;
    my $auth = $req{auth};
    return error_response(401, 'Autentikasi diperlukan') unless $auth;

    my $id = $req{params}{id};
    return error_response(400, 'ID laporan wajib disertakan') unless $id;

    my $body = $req{body} // {};
    my $result = update_report($id, $auth->{uid}, %$body);

    if (ref($result) eq 'HASH' && $result->{error}) {
        return error_response(403, $result->{error});
    }

    log_audit(
        user_id       => $auth->{uid},
        username      => $auth->{username},
        action        => 'REPORT_UPDATE',
        resource_type => 'REPORT',
        resource_id   => $id,
        status        => 'SUCCESS',
        ip_address    => $req{ip}
    );

    return json_response(200, {
        success => 1,
        message => 'Laporan berhasil diperbarui',
        data    => $result,
    });
}

sub verify {
    my ($class, %req) = @_;
    my $auth = $req{auth};
    return error_response(401, 'Autentikasi diperlukan') unless $auth;

    # RBAC: Only ADMIN or SUPERVISOR can approve/reject reports
    if ($auth->{role} ne 'ADMIN' && $auth->{role} ne 'SUPERVISOR') {
        return error_response(403, 'Akses ditolak: Hanya Supervisor atau Admin yang dapat memverifikasi laporan');
    }

    my $id = $req{params}{id};
    my $body = $req{body} // {};
    my $status = uc($body->{status} // '');

    unless ($status eq 'APPROVED' || $status eq 'REJECTED') {
        return error_response(400, "Status verifikasi harus bernilai 'APPROVED' atau 'REJECTED'");
    }

    my $notes = $body->{verification_notes} // '';
    my $report = verify_report($id, $auth->{uid}, $status, $notes);

    unless ($report) {
        return error_response(404, 'Laporan tidak ditemukan');
    }

    log_audit(
        user_id       => $auth->{uid},
        username      => $auth->{username},
        action        => "REPORT_VERIFY_$status",
        resource_type => 'REPORT',
        resource_id   => $id,
        status        => 'SUCCESS',
        ip_address    => $req{ip},
        details       => { status => $status, notes => $notes }
    );

    return json_response(200, {
        success => 1,
        message => "Laporan berhasil diverifikasi ($status)",
        data    => $report,
    });
}

1;

