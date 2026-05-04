-- VAJA-06 — Shema baze AlmaMater in začetni podatki.
--   Uvoz: `mariadb < setup-db.sql` (kot root preko Unix socketa)
-- Avtor: Urban Ambrožič

DROP DATABASE IF EXISTS AlmaMater;
CREATE DATABASE AlmaMater;
USE AlmaMater;

CREATE TABLE student (
    stevilka INT PRIMARY KEY AUTO_INCREMENT,
    ime VARCHAR(30),
    priimek VARCHAR(30)
);

DROP USER IF EXISTS 'urban'@'%';
CREATE USER 'urban'@'%' IDENTIFIED BY 'urban';
GRANT ALL ON *.* TO 'urban'@'%';
FLUSH PRIVILEGES;

INSERT INTO student(ime, priimek) VALUES ('Dejan',  'Prvak');
INSERT INTO student(ime, priimek) VALUES ('Maja',   'Drugonja');
INSERT INTO student(ime, priimek) VALUES ('Petra',  'Terčnik');

SELECT * FROM student;
