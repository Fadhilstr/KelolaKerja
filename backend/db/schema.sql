-- =====================================================================
-- KELOLAKERJA — Employee Attendance & Reporting System with Face Recognition
-- Database Schema (MariaDB / MySQL 10.11+)
-- Charset: utf8mb4 / Collation: utf8mb4_unicode_ci
-- =====================================================================

CREATE DATABASE IF NOT EXISTS kelolakerja_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE kelolakerja_db;

-- ---------------------------------------------------------------------
-- 1. Table: users
-- Core user entity with RBAC role, status, and credentials
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    employee_code VARCHAR(30) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    username VARCHAR(50) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role ENUM('ADMIN', 'SUPERVISOR', 'EMPLOYEE') NOT NULL DEFAULT 'EMPLOYEE',
    department VARCHAR(100) NULL,
    position VARCHAR(100) NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    face_registered TINYINT(1) NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_users_role (role),
    INDEX idx_users_status (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 2. Table: face_biometrics
-- Stores 128-d or 512-d normalized face embedding vectors as JSON
-- Secure biometric isolation table linked to users
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS face_biometrics (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    embedding_json LONGTEXT NOT NULL,
    vector_dimension INT NOT NULL DEFAULT 128,
    model_version VARCHAR(50) NOT NULL DEFAULT 'facenet-v1',
    quality_score DECIMAL(5, 4) NOT NULL DEFAULT 1.0000,
    sample_count INT NOT NULL DEFAULT 1,
    registered_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_face_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 3. Table: attendances
-- Check-in and check-out logs with verification score and server timestamp
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS attendances (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    attendance_date DATE NOT NULL,
    check_in_time DATETIME NULL,
    check_out_time DATETIME NULL,
    check_in_match_score DECIMAL(5, 4) NULL,
    check_out_match_score DECIMAL(5, 4) NULL,
    check_in_photo_path VARCHAR(255) NULL,
    check_out_photo_path VARCHAR(255) NULL,
    status ENUM('PRESENT', 'LATE', 'HALF_DAY', 'EARLY_DEPARTURE', 'FLAGGED') NOT NULL DEFAULT 'PRESENT',
    notes TEXT NULL,
    ip_address VARCHAR(45) NULL,
    user_agent VARCHAR(255) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_user_attendance_date (user_id, attendance_date),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT,
    INDEX idx_attendances_date (attendance_date),
    INDEX idx_attendances_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 4. Table: activity_reports
-- Employee daily activity reporting with approval workflow
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS activity_reports (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    report_date DATE NOT NULL,
    title VARCHAR(150) NOT NULL,
    activity_description TEXT NOT NULL,
    results_achieved TEXT NULL,
    obstacles TEXT NULL,
    status ENUM('SUBMITTED', 'APPROVED', 'REJECTED') NOT NULL DEFAULT 'SUBMITTED',
    verified_by VARCHAR(36) NULL,
    verified_at DATETIME NULL,
    verification_notes TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT,
    FOREIGN KEY (verified_by) REFERENCES users(id) ON DELETE SET NULL,
    INDEX idx_reports_date (report_date),
    INDEX idx_reports_status (status),
    INDEX idx_reports_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 5. Table: audit_logs
-- Immutable security and compliance audit trail
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_logs (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    user_id VARCHAR(36) NULL,
    username VARCHAR(50) NULL,
    action VARCHAR(50) NOT NULL,
    resource_type VARCHAR(50) NOT NULL,
    resource_id VARCHAR(50) NULL,
    status ENUM('SUCCESS', 'FAILURE', 'DENIED') NOT NULL,
    ip_address VARCHAR(45) NULL,
    user_agent VARCHAR(255) NULL,
    details LONGTEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_audit_action (action),
    INDEX idx_audit_time (created_at),
    INDEX idx_audit_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

