<?php
$host = "192.168.0.173";
$dbname = "AlmaMater";
$username = "marko";
$password = "marko";

$conn = new mysqli($host, $username, $password, $dbname);

if ($conn->connect_error) {
    die("Povezava ni uspela: " . $conn->connect_error);
}

$conn->set_charset("utf8mb4");

$element = $_POST['element'] ?? '';
$kolicina = $_POST['kolicina'] ?? '';

$element = trim($element);
$kolicina = (int)$kolicina;

if ($element === '' || $kolicina <= 0) {
    die("Element in veljavna količina sta obvezna.");
}

$stmt = $conn->prepare("INSERT INTO nakup (element, kolicina) VALUES (?, ?)");

if (!$stmt) {
    die("Napaka pri prepare: " . $conn->error);
}

$stmt->bind_param("si", $element, $kolicina);

if ($stmt->execute()) {
    echo "Podatek je bil uspešno shranjen.<br><br>";
    echo '<a href="index.html">Nazaj na vnos</a><br>';
    echo '<a href="izpis.php">Poglej seznam</a>';
} else {
    echo "Napaka: " . $stmt->error;
}

$stmt->close();
$conn->close();
?>