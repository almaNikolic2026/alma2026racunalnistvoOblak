CREATE DATABASE IF NOT EXISTS nakupni_seznam;
USE nakupni_seznam;

CREATE TABLE IF NOT EXISTS nakup (
  id INT AUTO_INCREMENT PRIMARY KEY,
  element VARCHAR(100) NOT NULL,
  kolicina INT NOT NULL
);

INSERT INTO nakup (element, kolicina) VALUES
('kruh', 1),
('mleko', 2);

CREATE USER IF NOT EXISTS 'nakup_app'@'192.168.%' IDENTIFIED BY 'ChangeThisStrongPass123!';
GRANT ALL PRIVILEGES ON nakupni_seznam.* TO 'nakup_app'@'192.168.%';
FLUSH PRIVILEGES;
