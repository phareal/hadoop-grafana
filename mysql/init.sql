CREATE DATABASE IF NOT EXISTS universite;
USE universite;

-- ─── Étudiants ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS etudiants (
    id        INT AUTO_INCREMENT PRIMARY KEY,
    prenom    VARCHAR(50)  NOT NULL,
    nom       VARCHAR(50)  NOT NULL,
    filiere   VARCHAR(50)  NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ─── Cours ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS cours (
    id        INT AUTO_INCREMENT PRIMARY KEY,
    nom_cours VARCHAR(100) NOT NULL,
    credits   INT DEFAULT 3
);

-- ─── Inscriptions ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS inscriptions (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    etudiant_id     INT,
    cours_id        INT,
    note_finale     FLOAT,
    date_inscription TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (etudiant_id) REFERENCES etudiants(id),
    FOREIGN KEY (cours_id)    REFERENCES cours(id)
);

-- ─── Events Flume (alimenté par le log-generator) ─────────────
CREATE TABLE IF NOT EXISTS events (
    id         BIGINT AUTO_INCREMENT PRIMARY KEY,
    level      VARCHAR(10) NOT NULL,
    message    TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_level   (level),
    INDEX idx_created (created_at)
);

-- ─── Données d'exemple ────────────────────────────────────────
INSERT INTO etudiants (prenom, nom, filiere) VALUES
('Alice',    'Martin',   'Informatique'),
('Bob',      'Dupont',   'Mathématiques'),
('Clara',    'Bernard',  'Informatique'),
('David',    'Petit',    'Physique'),
('Emma',     'Robert',   'Informatique'),
('François', 'Richard',  'Mathématiques'),
('Grace',    'Durand',   'Chimie'),
('Hugo',     'Leblanc',  'Informatique'),
('Iris',     'Moreau',   'Physique'),
('Jacques',  'Simon',    'Informatique'),
('Karim',    'Laurent',  'Mathématiques'),
('Léa',      'Fontaine', 'Chimie'),
('Marc',     'Rousseau', 'Informatique'),
('Nadia',    'Vincent',  'Physique'),
('Oscar',    'Muller',   'Informatique'),
('Pauline',  'Leroy',    'Mathématiques'),
('Quentin',  'Roux',     'Chimie'),
('Rachel',   'David',    'Informatique'),
('Samuel',   'Bertrand', 'Physique'),
('Tina',     'Morel',    'Informatique');

INSERT INTO cours (nom_cours, credits) VALUES
('Big Data & Hadoop',         6),
('Machine Learning',          6),
('Bases de données avancées', 4),
('Architecture distribuée',   5),
('Python pour Data Science',  4),
('Algorithmes & Complexité',  5),
('Sécurité informatique',     3),
('Cloud Computing',           4);

INSERT INTO inscriptions (etudiant_id, cours_id, note_finale, date_inscription) VALUES
(1,  1, 16.5, NOW() - INTERVAL 22 DAY),
(1,  2, 14.0, NOW() - INTERVAL 20 DAY),
(2,  3, 17.5, NOW() - INTERVAL 19 DAY),
(3,  1, 15.0, NOW() - INTERVAL 18 DAY),
(3,  4, 13.5, NOW() - INTERVAL 17 DAY),
(4,  5, 18.0, NOW() - INTERVAL 16 DAY),
(5,  1, 12.0, NOW() - INTERVAL 15 DAY),
(5,  6, 16.0, NOW() - INTERVAL 14 DAY),
(6,  2, 14.5, NOW() - INTERVAL 13 DAY),
(7,  3, 11.0, NOW() - INTERVAL 12 DAY),
(8,  1, 19.0, NOW() - INTERVAL 10 DAY),
(9,  4, 15.5, NOW() - INTERVAL 9  DAY),
(10, 5, 13.0, NOW() - INTERVAL 8  DAY),
(11, 2, 17.0, NOW() - INTERVAL 7  DAY),
(12, 6, 16.5, NOW() - INTERVAL 6  DAY),
(13, 1, 14.0, NOW() - INTERVAL 5  DAY),
(14, 3, 12.5, NOW() - INTERVAL 4  DAY),
(15, 4, 18.5, NOW() - INTERVAL 3  DAY),
(16, 5, 15.0, NOW() - INTERVAL 2  DAY),
(17, 7, 13.5, NOW() - INTERVAL 1  DAY),
(18, 8, 16.0, NOW() - INTERVAL 0  DAY),
(19, 1, 17.5, NOW() - INTERVAL 0  DAY),
(20, 2, 14.0, NOW() - INTERVAL 0  DAY);
