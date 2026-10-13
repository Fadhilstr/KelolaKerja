package KelolaKerja::Model::Report;
use strict;
use warnings;
use KelolaKerja::Db;
use KelolaKerja::Auth qw(generate_uuid);
use Exporter 'import';

our @EXPORT_OK = qw(
    create_report
    update_report
    verify_report
    get_report_by_id
    get_reports
    get_report_summary
);

sub get_report_by_id {
    my ($id) = @_;
    my $dbh = KelolaKerja::Db->connect();
    my $sth = $dbh->prepare(qq{
        SELECT r.*, u.name as employee_name, u.employee_code, u.department,
               v.name as verifier_name
        FROM activity_reports r
        JOIN users u ON r.user_id = u.id
        LEFT JOIN users v ON r.verified_by = v.id
        WHERE r.id = ?
        LIMIT 1
    });
    $sth->execute($id);
    return $sth->fetchrow_hashref();
}

sub create_report {
    my (%data) = @_;
    my $dbh = KelolaKerja::Db->connect();
    my $id = generate_uuid();

    my $sth = $dbh->prepare(qq{
        INSERT INTO activity_reports (
            id, user_id, report_date, title, activity_description, results_achieved, obstacles, status, created_at
        )
        VALUES (?, ?, COALESCE(?, CURDATE()), ?, ?, ?, ?, 'SUBMITTED', NOW())
    });

    my $rv = $sth->execute(
        $id,
        $data{user_id},
        $data{report_date},
        $data{title},
        $data{activity_description},
        $data{results_achieved},
        $data{obstacles}
    );

    return $rv ? get_report_by_id($id) : undef;
}

sub update_report {
    my ($id, $user_id, %data) = @_;
    my $dbh = KelolaKerja::Db->connect();

    # Check report ownership and status (only SUBMITTED/REJECTED can be edited)
    my $existing = get_report_by_id($id);
    return { error => 'Laporan tidak ditemukan' } unless $existing;
    return { error => 'Akses ditolak: bukan laporan Anda' } if $existing->{user_id} ne $user_id;
    return { error => 'Laporan yang telah disetujui tidak dapat diedit' } if $existing->{status} eq 'APPROVED';

    my @fields;
    my @params;
    for my $col (qw(title activity_description results_achieved obstacles report_date)) {
        if (exists $data{$col}) {
            push @fields, "$col = ?";
            push @params, $data{$col};
        }
    }
    # Reset status back to SUBMITTED if previously REJECTED
    push @fields, "status = 'SUBMITTED'";

    push @params, $id;
    my $sql = "UPDATE activity_reports SET " . join(", ", @fields) . ", updated_at = NOW() WHERE id = ?";
    my $sth = $dbh->prepare($sql);
    my $rv = $sth->execute(@params);

    return $rv ? get_report_by_id($id) : undef;
}

sub verify_report {
    my ($id, $verifier_id, $status, $notes) = @_;
    my $dbh = KelolaKerja::Db->connect();

    my $sth = $dbh->prepare(qq{
        UPDATE activity_reports
        SET status = ?, verified_by = ?, verified_at = NOW(), verification_notes = ?, updated_at = NOW()
        WHERE id = ?
    });
    my $rv = $sth->execute($status, $verifier_id, $notes, $id);
    return $rv ? get_report_by_id($id) : undef;
}

sub get_reports {
    my (%filter) = @_;
    my $dbh = KelolaKerja::Db->connect();
    my @where;
    my @params;

    if ($filter{user_id}) {
        push @where, "r.user_id = ?";
        push @params, $filter{user_id};
    }
    if ($filter{status}) {
        push @where, "r.status = ?";
        push @params, $filter{status};
    }
    if ($filter{start_date}) {
        push @where, "r.report_date >= ?";
        push @params, $filter{start_date};
    }
    if ($filter{end_date}) {
        push @where, "r.report_date <= ?";
        push @params, $filter{end_date};
    }
    if ($filter{department}) {
        push @where, "u.department = ?";
        push @params, $filter{department};
    }

    my $where_sql = @where ? "WHERE " . join(" AND ", @where) : "";
    my $limit = int($filter{limit} // 50);

    my $sql = qq{
        SELECT r.*, u.name as employee_name, u.employee_code, u.department,
               v.name as verifier_name
        FROM activity_reports r
        JOIN users u ON r.user_id = u.id
        LEFT JOIN users v ON r.verified_by = v.id
        $where_sql
        ORDER BY r.report_date DESC, r.created_at DESC
        LIMIT $limit
    };

    my $sth = $dbh->prepare($sql);
    $sth->execute(@params);
    return $sth->fetchall_arrayref({}) // [];
}

sub get_report_summary {
    my $dbh = KelolaKerja::Db->connect();
    my $sth = $dbh->prepare(qq{
        SELECT
            COUNT(*) as total_reports,
            COUNT(CASE WHEN status = 'SUBMITTED' THEN 1 END) as pending_count,
            COUNT(CASE WHEN status = 'APPROVED' THEN 1 END) as approved_count,
            COUNT(CASE WHEN status = 'REJECTED' THEN 1 END) as rejected_count
        FROM activity_reports
    });
    $sth->execute();
    return $sth->fetchrow_hashref();
}

1;

