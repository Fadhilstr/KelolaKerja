-- =====================================================================
-- KELOLAKERJA — Initial Seed Data
-- =====================================================================

USE kelolakerja_db;

-- Initial users
-- Password hash format: sha256$<salt>$<hex(sha256(salt . password))>
-- admin      -> admin123
-- supervisor -> supervisor123
-- karyawan   -> karyawan123

INSERT INTO users (id, employee_code, name, email, username, password_hash, role, department, position, is_active, face_registered)
VALUES
('usr-admin-001', 'EMP-001', 'Administrator Sistem', 'admin@kelolakerja.local', 'admin', 'sha256$kksalt01$c2319177004ab5c1c6bff31c9825fc6469d456b22a213271a7c2166cd4f66ce6', 'ADMIN', 'IT & Operasional', 'Lead Administrator', 1, 0),
('usr-spv-001', 'EMP-002', 'Budi Santoso', 'supervisor@kelolakerja.local', 'supervisor', 'sha256$kksalt02$270ca5a89133e0e6b2941470d069e340262f4c257d51ab1e4f49a21ee4070ac1', 'SUPERVISOR', 'Human Resources', 'HR Supervisor', 1, 0),
('usr-emp-001', 'EMP-003', 'Ahmad Fadillah', 'karyawan@kelolakerja.local', 'karyawan', 'sha256$kksalt03$6d8b238729d526d1399262f70e66d7d6e91433e3fa7d68f789b691a104e4c930', 'EMPLOYEE', 'Engineering', 'Software Engineer', 1, 0)
ON DUPLICATE KEY UPDATE
    password_hash = VALUES(password_hash),
    name = VALUES(name),
    role = VALUES(role),
    is_active = VALUES(is_active);
