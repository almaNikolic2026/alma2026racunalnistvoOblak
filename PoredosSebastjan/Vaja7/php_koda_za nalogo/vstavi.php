<?php
$host = "192.168.0.157";
$dbname = "AlmaMater";
$username = "sebastjan";
$password = "sebastjan";

$conn = new mysqli($host, $username, $password, $dbname);

if ($conn->connect_error) {
    die("Connection failed: " . $conn->connect_error);
}

$element = $_POST['element'] ?? '';
$kolicina = $_POST['kolicina'] ?? '';

$element = trim($element);
$kolicina = (int)$kolicina;

if ($element === '' || $kolicina <= 0) {
    die("Element in količina sta obvezna.");
}

$stmt = $conn->prepare("INSERT INTO nakup (element, kolicina) VALUES (?, ?)");

if (!$stmt) {
    die("Prepare failed: " . $conn->error);
}

$stmt->bind_param("si", $element, $kolicina);

if ($stmt->execute()) {
    echo "Podatek uspešno shranjen.";
} else {
    echo "Error: " . $stmt->error;
}

$stmt->close();
$conn->close();
?>