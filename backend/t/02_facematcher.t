#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 12;
use FindBin;
use lib "$FindBin::Bin/../lib";

use KelolaKerja::Service::FaceMatcher qw(
    calculate_euclidean_distance
    calculate_cosine_similarity
    validate_descriptor_integrity
    verify_embedding
    parse_embedding
    issue_liveness_challenge
    verify_liveness_challenge
);

# Construct realistic ResNet-34 128-D normalized vectors (both positive & negative activations)
my @vec_person_a = map { ($_ % 2 == 0 ? 1 : -1) * (0.05 + (($_ % 7) * 0.015)) } (1 .. 128);
my @vec_person_a_live = map { $vec_person_a[$_] + (($_ % 3 == 0 ? 1 : -1) * 0.012) } (0 .. 127);
my @vec_person_b = map { ($_ % 3 == 0 ? 1 : -1) * (0.06 + (($_ % 5) * 0.018)) } (1 .. 128);
my @vec_flat_luminance = map { 0.088388 } (1 .. 128);

# Test 1: Vector parsing
my $parsed = parse_embedding(\@vec_person_a);
is(scalar(@$parsed), 128, 'parse_embedding parses 128 elements correctly');

# Test 2: Descriptor integrity accepts genuine ResNet-34 signed vector
my ($ok_valid, $msg_valid) = validate_descriptor_integrity(\@vec_person_a);
is($ok_valid, 1, 'validate_descriptor_integrity accepts genuine ResNet-34 signed vector');

# Test 3: Descriptor integrity rejects flat positive-only luminance vector
my ($ok_flat, $msg_flat) = validate_descriptor_integrity(\@vec_flat_luminance);
is($ok_flat, 0, 'validate_descriptor_integrity rejects flat luminance vector');

# Test 4: Identical vector distance
my $dist_zero = calculate_euclidean_distance(\@vec_person_a, \@vec_person_a);
is(sprintf('%.4f', $dist_zero), '0.0000', 'Identical vectors have 0.0 distance');

# Test 5: Cosine similarity on identical vector
my $sim_one = calculate_cosine_similarity(\@vec_person_a, \@vec_person_a);
is(sprintf('%.4f', $sim_one), '1.0000', 'Identical vectors have 1.0 cosine similarity');

# Test 6: Same person across frames has small Euclidean distance (< 0.42)
my $dist_same = calculate_euclidean_distance(\@vec_person_a, \@vec_person_a_live);
ok($dist_same > 0.01 && $dist_same < 0.42, "Same person live frame distance ($dist_same) is within strict 0.42 threshold");

# Test 7: Verify embedding match for same person
my $match_pos = verify_embedding(\@vec_person_a, \@vec_person_a_live, 0.42);
ok($match_pos->{is_match} == 1, 'verify_embedding accepts same person within 0.42 Euclidean & >= 0.89 Cosine');

# Test 8: Verify embedding rejects different person (Person B on Person A account)
my $match_neg = verify_embedding(\@vec_person_a, \@vec_person_b, 0.42);
ok($match_neg->{is_match} == 0, "verify_embedding rejects different person (distance: $match_neg->{distance}, similarity: $match_neg->{similarity})");

# Test 9: Mismatch error on invalid dimensions
my $invalid_dim = verify_embedding(\@vec_person_a, [ 0.1, -0.2, 0.3 ]);
ok($invalid_dim->{is_match} == 0 && $invalid_dim->{error}, 'verify_embedding rejects dimension mismatch');

# Test 10: Issue & verify 3D liveness challenge token (Success case)
my $chal = issue_liveness_challenge('user-123');
ok($chal->{challenge_token} && $chal->{challenge}{id}, 'issue_liveness_challenge generates signed token');

my ($live_ok, $live_msg) = verify_liveness_challenge(
    'user-123',
    $chal->{challenge_token},
    {
        step1_passed     => 1,
        step2_passed     => 1,
        landmark_delta   => 0.145,
        frames_analyzed  => 8,
        motion_embedding => \@vec_person_a_live,
    },
    \@vec_person_a
);
is($live_ok, 1, 'verify_liveness_challenge accepts genuine 3D landmark delta and dual-frame consistency');

# Test 11: Verify liveness rejects static photo (low landmark delta < 0.08)
my ($spoof_ok, $spoof_msg) = verify_liveness_challenge(
    'user-123',
    $chal->{challenge_token},
    {
        step1_passed     => 1,
        step2_passed     => 1,
        landmark_delta   => 0.02,
        frames_analyzed  => 8,
        motion_embedding => \@vec_person_a_live,
    },
    \@vec_person_a
);
is($spoof_ok, 0, 'verify_liveness_challenge rejects static photo with low 3D landmark delta');
