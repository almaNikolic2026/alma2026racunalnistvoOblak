<?php
$host = "192.168.0.157";
$dbname = "AlmaMater";
$username = "sebastjan";
$password = "sebastjan";

$conn = new mysqli($host, $username, $password, $dbname);

if ($conn->connect_error) {
    die("Connection failed: " . $conn->connect_error);
}

$sql = "SELECT id, element, kolicina FROM nakup";
$result = $conn->query($sql);

if ($result->num_rows > 0) {
    while($row = $result->fetch_assoc()) {
        echo "ID: " . $row["id"] . " - Element: " . $row["element"] . " - Količina: " . $row["kolicina"] . "<br>";
    }
} else {
    echo "Ni podatkov.";
}

$conn->close();
?>