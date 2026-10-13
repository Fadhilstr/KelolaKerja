package KelolaKerja::Model::Attendance;
use strict;
use warnings;
use KelolaKerja::Db;
use KelolaKerja::Auth qw(generate_uuid);
use Exporter 'import';

our @EXPORT_OK = qw(
    record_check_in
    record_check_out
    get_today_attendance
    get_attendance_history
    get_attendance_summary_today
    get_admin_attendance_overview
);

sub get_today_attendance {
    my ($user_id) = @_;
    my $dbh = KelolaKerja::Db->connect();
    my $sth = $dbh->prepare(qq{
        SELECT id, user_id, attendance_date, check_in_time, check_out_time, check_in_match_score, check_out_match_score,
               check_in_photo_path, check_out_photo_path, status, notes, ip_address, created_at, updated_at
        FROM attendances
        WHERE user_id = ? AND attendance_date = CURDATE()
        LIMIT 1
    });
    $sth->execute($user_id);
    return $sth->fetchrow_hashref();
}

sub record_check_in {
    my (%data) = @_;
    my $dbh = KelolaKerja::Db->connect();
    my $id = generate_uuid();

    # Determine status (e.g., LATE if past 09:00:00)
    my $status = 'PRESENT';
    my ($sec,$min,$hour) = localtime();
    if ($hour > 9 || ($hour == 9 && $min > 15)) {
        $status = 'LATE';
    }

    my $sth = $dbh->prepare(qq{
        INSERT INTO attendances (
            id, user_id, attendance_date, check_in_time, check_in_match_score,
            check_in_photo_path, status, notes, ip_address, user_agent, created_at
        )
        VALUES (?, ?, CURDATE(), NOW(), ?, ?, ?, ?, ?, ?, NOW())
    });

    my $rv = $sth->execute(
        $id,
        $data{user_id},
        $data{match_score},
        $data{photo_path},
        $status,
        $data{notes},
        $data{ip_address},
        $data{user_agent}
    );

    return $rv ? get_today_attendance($data{user_id}) : undef;
}

sub record_check_out {
    my (%data) = @_;
    my $dbh = KelolaKerja::Db->connect();

    my $sth = $dbh->prepare(qq{
        UPDATE attendances
        SET check_out_time = NOW(),
            check_out_match_score = ?,
            check_out_photo_path = ?,
            notes = COALESCE(CONCAT(COALESCE(notes, ''), ' | Checkout: ', ?), notes)
        WHERE user_id = ? AND attendance_date = CURDATE()
    });

    my $rv = $sth->execute(
        $data{match_score},
        $data{photo_path},
        $data{notes} // 'Check-out berhasil',
        $data{user_id}
    );

    return $rv ? get_today_attendance($data{user_id}) : undef;
}

sub get_attendance_history {
    my (%filter) = @_;
    my $dbh = KelolaKerja::Db->connect();
    my @where;
    my @params;

    if ($filter{user_id}) {
        push @where, "a.user_id = ?";
        push @params, $filter{user_id};
    }
    if ($filter{start_date}) {
        push @where, "a.attendance_date >= ?";
        push @params, $filter{start_date};
    }
    if ($filter{end_date}) {
        push @where, "a.attendance_date <= ?";
        push @params, $filter{end_date};
    }
    if ($filter{status}) {
        push @where, "a.status = ?";
        push @params, $filter{status};
    }

    my $where_sql = @where ? "WHERE " . join(" AND ", @where) : "";
    my $limit = int($filter{limit} // 31);

    my $sql = qq{
        SELECT a.id, a.user_id, u.name as user_name, u.employee_code, u.department,
               a.attendance_date, a.check_in_time, a.check_out_time,
               a.check_in_match_score, a.check_out_match_score,
               a.status, a.notes, a.created_at
        FROM attendances a
        JOIN users u ON a.user_id = u.id
        $where_sql
        ORDER BY a.attendance_date DESC, a.check_in_time DESC
        LIMIT $limit
    };

    my $sth = $dbh->prepare($sql);
    $sth->execute(@params);
    return $sth->fetchall_arrayref({}) // [];
}

sub get_attendance_summary_today {
    my $dbh = KelolaKerja::Db->connect();
    my $sth = $dbh->prepare(qq{
        SELECT
            COUNT(DISTINCT u.id) as total_employees,
            COUNT(DISTINCT CASE WHEN a.check_in_time IS NOT NULL THEN a.user_id END) as present_count,
            COUNT(DISTINCT CASE WHEN a.status = 'LATE' THEN a.user_id END) as late_count,
            COUNT(DISTINCT CASE WHEN a.check_out_time IS NOT NULL THEN a.user_id END) as checked_out_count
        FROM users u
        LEFT JOIN attendances a ON u.id = a.user_id AND a.attendance_date = CURDATE()
        WHERE u.is_active = 1 AND u.role = 'EMPLOYEE'
    });
    $sth->execute();
    my $res = $sth->fetchrow_hashref();
    $res->{not_present_count} = ($res->{total_employees} || 0) - ($res->{present_count} || 0);
    return $res;
}

sub get_admin_attendance_overview {
    my ($date) = @_;
    my $dbh = KelolaKerja::Db->connect();
    my $sql = qq{
        SELECT u.id as user_id, u.employee_code, u.name, u.department, u.position,
               a.id as attendance_id, a.attendance_date, a.check_in_time, a.check_out_time,
               a.check_in_match_score, a.check_out_match_score, a.status
        FROM users u
        LEFT JOIN attendances a ON u.id = a.user_id AND a.attendance_date = ?
        WHERE u.is_active = 1 AND u.role = 'EMPLOYEE'
        ORDER BY u.name ASC
    };
    my $sth = $dbh->prepare($sql);
    $sth->execute($date // 'CURDATE()');
    return $sth->fetchall_arrayref({}) // [];
}

1;

