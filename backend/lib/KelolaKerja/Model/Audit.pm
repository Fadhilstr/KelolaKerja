package KelolaKerja::Model::Audit;
use strict;
use warnings;
use JSON::PP ();
use KelolaKerja::Db;
use KelolaKerja::Auth qw(generate_uuid);
use Exporter 'import';

our @EXPORT_OK = qw(log_audit get_audit_logs);

sub log_audit {
    my (%args) = @_;
    eval {
        my $dbh = KelolaKerja::Db->connect();
        my $id = generate_uuid();
        my $details_json = undef;
        if (defined $args{details}) {
            if (ref($args{details})) {
                $details_json = JSON::PP::encode_json($args{details});
            } else {
                $details_json = $args{details};
            }
        }

        my $sth = $dbh->prepare(qq{
            INSERT INTO audit_logs (id, user_id, username, action, resource_type, resource_id, status, ip_address, user_agent, details, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
        });
        $sth->execute(
            $id,
            $args{user_id},
            $args{username},
            $args{action} // 'UNKNOWN_ACTION',
            $args{resource_type} // 'SYSTEM',
            $args{resource_id},
            $args{status} // 'SUCCESS',
            $args{ip_address} // '127.0.0.1',
            $args{user_agent} // '',
            $details_json
        );
        1;
    } or do {
        warn "[AUDIT LOG ERROR] Gagal mencatat audit log: $@\n";
    };
    return 1;
}

sub get_audit_logs {
    my (%filter) = @_;
    my $dbh = KelolaKerja::Db->connect();
    my $limit = int($filter{limit} // 50);
    $limit = 100 if $limit > 100;

    my @where;
    my @params;

    if ($filter{action}) {
        push @where, "action = ?";
        push @params, $filter{action};
    }
    if ($filter{user_id}) {
        push @where, "user_id = ?";
        push @params, $filter{user_id};
    }
    if ($filter{status}) {
        push @where, "status = ?";
        push @params, $filter{status};
    }

    my $where_sql = @where ? "WHERE " . join(" AND ", @where) : "";
    my $sql = qq{
        SELECT id, user_id, username, action, resource_type, resource_id, status, ip_address, user_agent, details, created_at
        FROM audit_logs
        $where_sql
        ORDER BY created_at DESC
        LIMIT $limit
    };

    my $sth = $dbh->prepare($sql);
    $sth->execute(@params);
    my $rows = $sth->fetchall_arrayref({});
    return $rows // [];
}

1;

