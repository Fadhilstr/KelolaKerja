package KelolaKerja::Config;
use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(config validate_config);

sub config {
    my $db_host = $ENV{DB_HOST} // '127.0.0.1';
    my $db_port = $ENV{DB_PORT} // 3306;
    my $db_name = $ENV{DB_NAME} // 'kelolakerja_db';
    my $dsn     = $ENV{DB_DSN}  // "DBI:mysql:database=$db_name;host=$db_host;port=$db_port";

    return {
        app_env        => $ENV{APP_ENV}        // 'development',
        api_port       => $ENV{PORT}           // 5000,
        db_dsn         => $dsn,
        db_user        => $ENV{DB_USER}        // 'root',
        db_pass        => $ENV{DB_PASS}        // 'root',
        token_secret   => $ENV{TOKEN_SECRET}   // 'kelolakerja-super-secure-jwt-token-secret-2026',
        token_ttl      => $ENV{TOKEN_TTL}      // 86400, # 24 hours
        redis_host     => $ENV{REDIS_HOST}     // '127.0.0.1',
        redis_port     => $ENV{REDIS_PORT}     // 6379,
        # Biometric Face Recognition settings (ResNet-34 128-D strict threshold)
        # Same person: ~0.15 - 0.38 | Different person: ~0.52 - 0.90
        face_threshold => $ENV{FACE_THRESHOLD} // 0.42,
        cors_origin    => $ENV{CORS_ORIGIN}    // '*',
    };
}

sub validate_config {
    my $cfg = config();
    my $env = lc($cfg->{app_env});
    if ($env eq 'production') {
        if ($cfg->{token_secret} =~ /kelolakerja-super-secure/ || length($cfg->{token_secret}) < 32) {
            die "[SECURITY ERROR] TOKEN_SECRET must be set to a custom strong random key in production mode.\n";
        }
    }
    return 1;
}

1;
