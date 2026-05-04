<?php
// VAJA-08 — Skupna konfiguracija povezave do RDS MariaDB baze.
// $host je RDS endpoint (substitucija v deploy skripti z vrednostjo iz vaja08-state.env).

$host = "__DB_HOST__";
$dbname = "AlmaMater";
$username = "urban";
$password = "urban";

$conn = new mysqli($host, $username, $password, $dbname);
if ($conn->connect_error) {
    die("Povezava na bazo ni uspela: " . $conn->connect_error);
}
$conn->set_charset("utf8mb4");
?>
