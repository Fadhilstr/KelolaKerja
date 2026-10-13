package KelolaKerja::Service::FaceMatcher;
use strict;
use warnings;
use JSON::PP ();
use Digest::SHA qw(hmac_sha256_hex);
use MIME::Base64 qw(encode_base64url decode_base64url);
use Exporter 'import';
use KelolaKerja::Config qw(config);

our @EXPORT_OK = qw(
    calculate_euclidean_distance
    calculate_cosine_similarity
    validate_descriptor_integrity
    verify_embedding
    parse_embedding
    issue_liveness_challenge
    verify_liveness_challenge
);

sub parse_embedding {
    my ($input) = @_;
    return [] unless defined $input;

    if (ref($input) eq 'ARRAY') {
        return [ map { 0.0 + $_ } @$input ];
    } elsif (!ref($input) && length($input)) {
        my $decoded = eval { JSON::PP::decode_json($input) };
        if ($decoded && ref($decoded) eq 'ARRAY') {
            return [ map { 0.0 + $_ } @$decoded ];
        }
    }
    return [];
}

# Validate that a 128-D vector is a genuine neural network face descriptor
# and not a flat/synthetic luminance array
sub validate_descriptor_integrity {
    my ($vec) = @_;
    my $parsed = parse_embedding($vec);
    my $n = scalar(@$parsed);

    if ($n != 128 && $n != 512) {
        return (0, sprintf("Dimensi vektor biometrik tidak valid (%d, harus 128)", $n));
    }

    my $sum = 0.0;
    my $norm_sq = 0.0;
    my $neg_count = 0;
    my $pos_count = 0;

    for my $v (@$parsed) {
        $sum += $v;
        $norm_sq += $v * $v;
        $neg_count++ if $v < 0;
        $pos_count++ if $v > 0;
    }

    my $mean = $sum / $n;
    my $var_sum = 0.0;
    for my $v (@$parsed) {
        my $d = $v - $mean;
        $var_sum += $d * $d;
    }
    my $std_dev = sqrt($var_sum / $n);
    my $norm = sqrt($norm_sq);

    if ($norm < 0.3 || $norm > 2.5) {
        return (0, "Magnitudo vektor biometrik tidak valid (norma L2 di luar batas wajar)");
    }

    if ($std_dev < 0.025) {
        return (0, "Vektor biometrik ditolak: Variansi fitur terlalu rendah (indikasi gambar statis/tidak valid)");
    }

    if ($neg_count == 0 || $pos_count == 0) {
        return (0, "Vektor biometrik ditolak: Bukan representasi neural network ResNet-34 yang sah");
    }

    return (1, "OK");
}

# Euclidean distance between two n-dimensional vectors: sqrt( sum( (a_i - b_i)^2 ) )
sub calculate_euclidean_distance {
    my ($vec_a, $vec_b) = @_;
    return 999.0 unless ref($vec_a) eq 'ARRAY' && ref($vec_b) eq 'ARRAY';
    return 999.0 if @$vec_a != @$vec_b || @$vec_a == 0;

    my $sum_sq = 0.0;
    for (my $i = 0; $i < @$vec_a; $i++) {
        my $diff = $vec_a->[$i] - $vec_b->[$i];
        $sum_sq += $diff * $diff;
    }
    return sqrt($sum_sq);
}

# Cosine similarity between two vectors: (A . B) / (||A|| * ||B||)
sub calculate_cosine_similarity {
    my ($vec_a, $vec_b) = @_;
    return 0.0 unless ref($vec_a) eq 'ARRAY' && ref($vec_b) eq 'ARRAY';
    return 0.0 if @$vec_a != @$vec_b || @$vec_a == 0;

    my $dot_product = 0.0;
    my $norm_a = 0.0;
    my $norm_b = 0.0;

    for (my $i = 0; $i < @$vec_a; $i++) {
        $dot_product += $vec_a->[$i] * $vec_b->[$i];
        $norm_a += $vec_a->[$i] * $vec_a->[$i];
        $norm_b += $vec_b->[$i] * $vec_b->[$i];
    }

    my $magnitude = sqrt($norm_a) * sqrt($norm_b);
    return 0.0 if $magnitude == 0;
    return $dot_product / $magnitude;
}

# Verify candidate embedding against registered embedding
# Enforces BOTH Euclidean distance <= threshold (0.42) AND Cosine similarity >= min_similarity (0.89)
sub verify_embedding {
    my ($registered_vec, $candidate_vec, $custom_threshold) = @_;
    my $cfg = config();
    my $threshold = $custom_threshold // $cfg->{face_threshold} // 0.42;

    my $vec1 = parse_embedding($registered_vec);
    my $vec2 = parse_embedding($candidate_vec);

    if (@$vec1 == 0 || @$vec2 == 0) {
        return {
            is_match   => 0,
            distance   => 999.0,
            similarity => 0.0,
            threshold  => $threshold,
            error      => 'Dimensi vektor tidak valid atau kosong',
        };
    }

    if (@$vec1 != @$vec2) {
        return {
            is_match   => 0,
            distance   => 999.0,
            similarity => 0.0,
            threshold  => $threshold,
            error      => sprintf("Dimensi vektor tidak cocok (terdaftar: %d, kandidat: %d)", scalar(@$vec1), scalar(@$vec2)),
        };
    }

    my $distance = calculate_euclidean_distance($vec1, $vec2);
    my $similarity = calculate_cosine_similarity($vec1, $vec2);

    # Minimum cosine similarity corresponding to strict face match
    my $min_similarity = 0.89;
    my $is_match = ($distance <= $threshold && $similarity >= $min_similarity) ? 1 : 0;

    return {
        is_match   => $is_match,
        distance   => sprintf('%.4f', $distance) + 0,
        similarity => sprintf('%.4f', $similarity) + 0,
        threshold  => sprintf('%.4f', $threshold) + 0,
    };
}

# Issue server-signed liveness challenge token
sub issue_liveness_challenge {
    my ($user_id) = @_;
    my $cfg = config();

    my @challenges = (
        {
            id          => 'TURN_LEFT',
            label       => 'Toleh Kepala ke Kiri',
            instruction => 'Putar wajah Anda perlahan ke arah KIRI hingga indikator hijau penuh, lalu kembali hadap lurus.'
        },
        {
            id          => 'TURN_RIGHT',
            label       => 'Toleh Kepala ke Kanan',
            instruction => 'Putar wajah Anda perlahan ke arah KANAN hingga indikator hijau penuh, lalu kembali hadap lurus.'
        },
        {
            id          => 'SMILE_OPEN',
            label       => 'Tersenyum Lebar / Buka Mulut',
            instruction => 'Tersenyum lebar atau buka mulut sedikit di depan kamera hingga terdeteksi oleh sensor landmark.'
        },
        {
            id          => 'HEAD_NOD',
            label       => 'Anggukkan / Gerakkan Kepala',
            instruction => 'Gerakkan kepala naik-turun secara perlahan di depan kamera untuk verifikasi struktur 3D.'
        }
    );

    my $picked = $challenges[ int(rand(scalar(@challenges))) ];
    my $payload_data = {
        uid          => $user_id,
        challenge_id => $picked->{id},
        iat          => time(),
        exp          => time() + 180, # Valid for 3 minutes
        nonce        => int(rand(99999999)),
    };

    my $payload_b64 = encode_base64url(JSON::PP::encode_json($payload_data));
    my $sig = hmac_sha256_hex($payload_b64, $cfg->{token_secret});

    return {
        challenge_token => "$payload_b64.$sig",
        challenge       => $picked,
        expires_in      => 180,
    };
}

# Verify server-signed liveness challenge token + multi-frame landmark telemetry
sub verify_liveness_challenge {
    my ($user_id, $challenge_token, $proof, $primary_vec) = @_;
    my $cfg = config();

    return (0, 'Token tantangan liveness (challenge_token) wajib disertakan.') unless $challenge_token && $challenge_token =~ /\./;

    my ($payload_b64, $sig) = split /\./, $challenge_token, 2;
    my $expected_sig = hmac_sha256_hex($payload_b64, $cfg->{token_secret});
    return (0, 'Tanda tangan token liveness tidak sah.') unless $sig eq $expected_sig;

    my $data = eval { JSON::PP::decode_json(decode_base64url($payload_b64)) };
    return (0, 'Payload token liveness rusak.') unless $data && $data->{uid};
    return (0, 'Token liveness bukan milik pengguna yang sedang login.') if $data->{uid} ne $user_id;
    return (0, 'Sesi tantangan liveness telah kedaluwarsa. Silakan ulangi pemindaian kamera.') if time() > ($data->{exp} // 0);

    return (0, 'Data bukti telemetri liveness (liveness_proof) tidak ditemukan.') unless ref($proof) eq 'HASH';
    return (0, 'Tantangan gerakan liveness belum diselesaikan.') unless ($proof->{step1_passed} // 0) == 1 && ($proof->{step2_passed} // 0) == 1;

    my $landmark_delta = 0.0 + ($proof->{landmark_delta} // 0);
    if ($landmark_delta < 0.08) {
        return (0, sprintf('Gerakan 3D landmark wajah tidak mencukupi (delta: %.3f < 0.080). Indikasi foto statis/spoofing!', $landmark_delta));
    }

    my $frames = int($proof->{frames_analyzed} // 0);
    if ($frames < 3) {
        return (0, 'Jumlah frame analisis video terlalu sedikit untuk verifikasi anti-spoofing.');
    }

    # Verify motion_embedding vs primary_embedding (must be non-identical across frames and within pose variation bounds)
    if ($proof->{motion_embedding} && $primary_vec) {
        my $vec_main   = parse_embedding($primary_vec);
        my $vec_motion = parse_embedding($proof->{motion_embedding});
        if (@$vec_main == 128 && @$vec_motion == 128) {
            my $inter_dist = calculate_euclidean_distance($vec_main, $vec_motion);
            if ($inter_dist < 0.0001) {
                return (0, 'Deteksi anti-spoofing gagal: Frame video identik/beku (indikasi injeksi gambar statis).');
            }
            if ($inter_dist > 0.75) {
                return (0, sprintf('Deteksi anti-spoofing gagal: Wajah berubah drastis saat tantangan berlangsung (jarak antar-frame: %.4f).', $inter_dist));
            }
        }
    }

    return (1, 'Liveness terverifikasi');
}

1;
