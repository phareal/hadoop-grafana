-- ── Base de données Big Data — Lomé Business School
CREATE DATABASE IF NOT EXISTS lbs_bigdata;
USE lbs_bigdata;

-- ────────────────────────────────────────────
-- TABLE ÉTUDIANTS
-- ────────────────────────────────────────────
CREATE TABLE etudiants (
  id        INT PRIMARY KEY,
  nom       VARCHAR(50),
  prenom    VARCHAR(80),
  login     VARCHAR(30),
  groupe_no INT,
  filiere   VARCHAR(40),
  statut    ENUM('actif','absent','validé')
);

INSERT INTO etudiants VALUES
(1,  'AZIAGBEGNON', 'Koami Jonathan',              'k.aziagbegnon', 1, 'Big Data', 'actif'),
(2,  'BANKATI',      'Mabibè',                      'm.bankati',      1, 'Big Data', 'actif'),
(3,  'KLOUGAN',      'Kossi Samson',                'k.klougan',      2, 'Big Data', 'actif'),
(4,  'de SOUZA',     'Felicia Odette',              'f.desouza',      2, 'Big Data', 'actif'),
(5,  'DOH-BARRY',    'Harmonia',                   'h.dohbarry',     3, 'Big Data', 'actif'),
(6,  'DONOU',        'Séfako Félicité',             's.donou',        3, 'Big Data', 'actif'),
(7,  'EDIM',         'Joseph-Kingsley Chris-Joris', 'j.edim',         4, 'Big Data', 'actif'),
(8,  'FOIYEME',      'Nounifou',                   'n.foiyeme',      4, 'Big Data', 'actif'),
(9,  'FOLLY',        'Kokou Claude',               'k.folly',        5, 'Big Data', 'actif'),
(10, 'KUEVIAKOE',    'Ekue Ormad Trésor',          'e.kueviakoe',    5, 'Big Data', 'actif'),
(11, 'LAWSON-DJITO', 'Latévi Steven Antoine',      'l.lawsondjito',  6, 'Big Data', 'actif'),
(12, 'POTCHONA',     'Essosolam Justin',            'e.potchona',     6, 'Big Data', 'actif'),
(13, 'AMEDON',       'Roland',                     'r.amedon',       6, 'Big Data', 'actif');

-- ────────────────────────────────────────────
-- TABLE COURS (4 matières avec vrais profs)
-- ────────────────────────────────────────────
CREATE TABLE cours (
  id         INT PRIMARY KEY,
  code       VARCHAR(10),
  intitule   VARCHAR(50),
  credits    INT,
  professeur VARCHAR(60)
);

INSERT INTO cours VALUES
(1, 'BD101',  'Big Data',   4, 'AMADJI DOSSOU'),
(2, 'ALG101', 'Algorithme', 3, 'Prof. Kpoti'),
(3, 'MGT101', 'Management', 3, 'Prof. Agbeko'),
(4, 'JAV101', 'Java',       4, 'Prof. Dossou');

-- ────────────────────────────────────────────
-- TABLE NOTES (chaque étudiant × 4 cours)
-- ────────────────────────────────────────────
CREATE TABLE notes (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  etudiant_id INT,
  cours_id    INT,
  note_s1     FLOAT,
  note_s2     FLOAT,
  note_finale FLOAT,
  FOREIGN KEY (etudiant_id) REFERENCES etudiants(id),
  FOREIGN KEY (cours_id)    REFERENCES cours(id)
);

-- Notes Big Data — AMADJI DOSSOU (cours_id=1)
INSERT INTO notes (etudiant_id, cours_id, note_s1, note_s2, note_finale) VALUES
(1,1,14.5,15.0,14.8),(2,1,12.0,13.5,12.8),(3,1,11.5,10.0,10.8),
(4,1,16.0,17.5,16.8),(5,1,13.0,14.0,13.5),(6,1,15.5,14.5,15.0),
(7,1,17.0,16.5,16.8),(8,1,10.5,11.0,10.8),(9,1,13.5,12.5,13.0),
(10,1,14.0,15.5,14.8),(11,1,12.5,13.0,12.8),(12,1,15.0,16.0,15.5),
(13,1,11.0,12.0,11.5);

-- Notes Algorithme (cours_id=2)
INSERT INTO notes (etudiant_id, cours_id, note_s1, note_s2, note_finale) VALUES
(1,2,13.0,14.5,13.8),(2,2,10.5,11.0,10.8),(3,2,12.0,11.5,11.8),
(4,2,17.0,16.0,16.5),(5,2,14.5,13.0,13.8),(6,2,16.0,15.5,15.8),
(7,2,18.0,17.5,17.8),(8,2,9.5,10.5,10.0),(9,2,12.5,13.5,13.0),
(10,2,15.0,14.5,14.8),(11,2,11.0,12.5,11.8),(12,2,14.0,15.5,14.8),
(13,2,10.0,11.5,10.8);

-- Notes Management (cours_id=3)
INSERT INTO notes (etudiant_id, cours_id, note_s1, note_s2, note_finale) VALUES
(1,3,15.5,16.0,15.8),(2,3,13.0,12.5,12.8),(3,3,10.0,11.0,10.5),
(4,3,15.0,16.5,15.8),(5,3,12.5,14.0,13.3),(6,3,14.5,15.0,14.8),
(7,3,16.0,15.5,15.8),(8,3,11.5,10.0,10.8),(9,3,14.0,13.5,13.8),
(10,3,13.5,14.0,13.8),(11,3,13.0,12.0,12.5),(12,3,16.5,15.0,15.8),
(13,3,12.0,13.0,12.5);

-- Notes Java (cours_id=4)
INSERT INTO notes (etudiant_id, cours_id, note_s1, note_s2, note_finale) VALUES
(1,4,12.0,13.5,12.8),(2,4,11.5,10.0,10.8),(3,4,13.0,12.0,12.5),
(4,4,18.0,17.0,17.5),(5,4,11.5,13.0,12.3),(6,4,15.0,14.5,14.8),
(7,4,19.0,18.5,18.8),(8,4,10.0,11.5,10.8),(9,4,13.5,14.0,13.8),
(10,4,14.5,15.0,14.8),(11,4,12.0,13.5,12.8),(12,4,16.0,17.0,16.5),
(13,4,11.5,12.0,11.8);

-- ────────────────────────────────────────────
-- TABLE LOGS_HDFS (alimentée par Flume)
-- ────────────────────────────────────────────
CREATE TABLE logs_hdfs (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  timestamp  DATETIME,
  level      ENUM('INFO','WARN','ERROR'),
  login      VARCHAR(30),
  cours      VARCHAR(20),
  groupe_no  INT,
  message    TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ────────────────────────────────────────────
-- VUES UTILES
-- ────────────────────────────────────────────

-- Moyenne par groupe et par cours
CREATE VIEW moyenne_groupe_cours AS
SELECT e.groupe_no, c.intitule AS cours, c.professeur,
       COUNT(*) AS nb_etudiants,
       ROUND(AVG(n.note_finale), 2) AS moyenne,
       MAX(n.note_finale) AS max_note,
       MIN(n.note_finale) AS min_note
FROM notes n
JOIN etudiants e ON n.etudiant_id = e.id
JOIN cours     c ON n.cours_id    = c.id
GROUP BY e.groupe_no, c.intitule, c.professeur
ORDER BY e.groupe_no, c.intitule;

-- Classement général (moyenne toutes matières)
CREATE VIEW classement_general AS
SELECT RANK() OVER (ORDER BY AVG(n.note_finale) DESC) AS rang,
       e.nom, e.prenom, e.login, e.groupe_no,
       ROUND(AVG(n.note_finale), 2) AS moyenne_generale,
       CASE WHEN AVG(n.note_finale) >= 16 THEN 'Très Bien'
            WHEN AVG(n.note_finale) >= 14 THEN 'Bien'
            WHEN AVG(n.note_finale) >= 12 THEN 'Assez Bien'
            WHEN AVG(n.note_finale) >= 10 THEN 'Passable'
            ELSE 'Insuffisant' END AS mention
FROM notes n
JOIN etudiants e ON n.etudiant_id = e.id
GROUP BY e.id, e.nom, e.prenom, e.login, e.groupe_no
ORDER BY moyenne_generale DESC;

-- Bulletins individuels complets
CREATE VIEW bulletins AS
SELECT e.nom, e.prenom, e.login, e.groupe_no,
       c.intitule AS cours, c.professeur, c.credits,
       n.note_s1, n.note_s2, n.note_finale,
       CASE WHEN n.note_finale >= 10 THEN 'Validé' ELSE 'Ajourné' END AS resultat
FROM notes n
JOIN etudiants e ON n.etudiant_id = e.id
JOIN cours     c ON n.cours_id    = c.id
ORDER BY e.groupe_no, e.nom, c.intitule;
