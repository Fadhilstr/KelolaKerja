package KelolaKerja::Model::User;
use strict;
use warnings;
use KelolaKerja::Db;
use KelolaKerja::Auth qw(generate_uuid hash_password verify_password);
use Exporter 'import';

our @EXPORT_OK = qw(
    find_user_by_id
    find_user_by_username_or_email
    get_all_users
    create_user
    update_user
    toggle_user_status
    save_face_biometrics
    get_face_biometrics
    get_all_face_biometrics
    delete_face_biometrics
);

sub find_user_by_id {
    my ($id) = @_;
    my $dbh = KelolaKerja::Db->connect();
    my $sth = $dbh->prepare(qq{
        SELECT id, employee_code, name, email, username, role, department, position, is_active, face_registered, created_at, updated_at
        FROM users WHERE id = ? LIMIT 1
    });
    $sth->execute($id);
    return $sth->fetchrow_hashref();
}

sub find_user_by_username_or_email {
    my ($identifier) = @_;
    my $dbh = KelolaKerja::Db->connect();
    my $sth = $dbh->prepare(qq{
        SELECT * FROM users
        WHERE LOWER(username) = LOWER(?) OR LOWER(email) = LOWER(?)
        LIMIT 1
    });
    $sth->execute($identifier, $identifier);
    return $sth->fetchrow_hashref();
}

sub get_all_users {
    my (%filter) = @_;
    my $dbh = KelolaKerja::Db->connect();
    my @where;
    my @params;

    if ($filter{role}) {
        push @where, "role = ?";
        push @params, $filter{role};
    }
    if (defined $filter{is_active}) {
        push @where, "is_active = ?";
        push @params, $filter{is_active};
    }

    my $where_sql = @where ? "WHERE " . join(" AND ", @where) : "";
    my $sql = qq{
        SELECT id, employee_code, name, email, username, role, department, position, is_active, face_registered, created_at, updated_at
        FROM users
        $where_sql
        ORDER BY created_at DESC
    };

    my $sth = $dbh->prepare($sql);
    $sth->execute(@params);
    return $sth->fetchall_arrayref({}) // [];
}

sub create_user {
    my (%data) = @_;
    my $dbh = KelolaKerja::Db->connect();
    my $id = $data{id} // generate_uuid();
    my $hash = KelolaKerja::Auth->hash_password($data{password});

    my $sth = $dbh->prepare(qq{
        INSERT INTO users (id, employee_code, name, email, username, password_hash, role, department, position, is_active, face_registered)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
    });

    my $rv = $sth->execute(
        $id,
        $data{employee_code},
        $data{name},
        $data{email},
        $data{username},
        $hash,
        $data{role} // 'EMPLOYEE',
        $data{department},
        $data{position},
        defined $data{is_active} ? $data{is_active} : 1
    );

    return $rv ? find_user_by_id($id) : undef;
}

sub update_user {
    my ($id, %data) = @_;
    my $dbh = KelolaKerja::Db->connect();
    my @fields;
    my @params;

    for my $col (qw(name email department position role)) {
        if (exists $data{$col}) {
            push @fields, "$col = ?";
            push @params, $data{$col};
        }
    }

    if ($data{password} && length($data{password})) {
        my $hash = KelolaKerja::Auth->hash_password($data{password});
        push @fields, "password_hash = ?";
        push @params, $hash;
    }

    return undef unless @fields;
    push @params, $id;

    my $sql = "UPDATE users SET " . join(", ", @fields) . " WHERE id = ?";
    my $sth = $dbh->prepare($sql);
    my $rv = $sth->execute(@params);
    return $rv ? find_user_by_id($id) : undef;
}

sub toggle_user_status {
    my ($id, $is_active) = @_;
    my $dbh = KelolaKerja::Db->connect();
    my $sth = $dbh->prepare("UPDATE users SET is_active = ? WHERE id = ?");
    my $rv = $sth->execute($is_active ? 1 : 0, $id);
    return $rv ? find_user_by_id($id) : undef;
}

sub save_face_biometrics {
    my ($user_id, $embedding_json, $dimension, $quality_score) = @_;
    my $dbh = KelolaKerja::Db->connect();
    my $id = generate_uuid();
    $dimension //= 128;
    $quality_score //= 1.0;

    my $del_sth = $dbh->prepare("DELETE FROM face_biometrics WHERE user_id = ?");
    $del_sth->execute($user_id);

    my $ins_sth = $dbh->prepare(qq{
        INSERT INTO face_biometrics (id, user_id, embedding_json, vector_dimension, model_version, quality_score, sample_count, registered_at)
        VALUES (?, ?, ?, ?, 'resnet34-128d', ?, 1, NOW())
    });
    my $rv = $ins_sth->execute($id, $user_id, $embedding_json, $dimension, $quality_score);

    if ($rv) {
        my $upd_sth = $dbh->prepare("UPDATE users SET face_registered = 1 WHERE id = ?");
        $upd_sth->execute($user_id);
        return 1;
    }
    return 0;
}

sub get_face_biometrics {
    my ($user_id) = @_;
    my $dbh = KelolaKerja::Db->connect();
    my $sth = $dbh->prepare(qq{
        SELECT id, user_id, embedding_json, vector_dimension, model_version, quality_score, registered_at
        FROM face_biometrics WHERE user_id = ? ORDER BY registered_at DESC LIMIT 1
    });
    $sth->execute($user_id);
    return $sth->fetchrow_hashref();
}

sub get_all_face_biometrics {
    my $dbh = KelolaKerja::Db->connect();
    my $sth = $dbh->prepare(qq{
        SELECT fb.id, fb.user_id, fb.embedding_json, fb.model_version, u.name, u.username, u.employee_code
        FROM face_biometrics fb
        JOIN users u ON fb.user_id = u.id
    });
    $sth->execute();
    return $sth->fetchall_arrayref({}) // [];
}

sub delete_face_biometrics {
    my ($user_id) = @_;
    my $dbh = KelolaKerja::Db->connect();
    $dbh->do("DELETE FROM face_biometrics WHERE user_id = ?", undef, $user_id);
    $dbh->do("UPDATE users SET face_registered = 0 WHERE id = ?", undef, $user_id);
    return 1;
}

1;
