package KelolaKerja::Db;
use strict;
use warnings;
use DBI;
use KelolaKerja::Config qw(config);

our $DBH;

sub connect {
    my ($class) = @_;

    if ($DBH && eval { $DBH->ping }) {
        return $DBH;
    }

    my $cfg = config();
    $DBH = eval {
        DBI->connect(
            $cfg->{db_dsn},
            $cfg->{db_user},
            $cfg->{db_pass},
            {
                RaiseError           => 0,
                PrintError           => 0,
                AutoCommit           => 1,
                mysql_enable_utf8mb4 => 1,
                AutoInactiveDestroy  => 1,
            }
        );
    };

    if (!$DBH) {
        die "Koneksi database KelolaKerja gagal: " . (DBI->errstr // $@);
    }

    $DBH->do("SET time_zone = '+07:00'");
    return $DBH;
}

sub disconnect {
    if ($DBH) {
        $DBH->disconnect;
        undef $DBH;
    }
}

1;
