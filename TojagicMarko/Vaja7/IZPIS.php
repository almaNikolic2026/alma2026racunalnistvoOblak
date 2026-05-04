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

$sql = "SELECT id, element, kolicina FROM nakup";
$result = $conn->query($sql);
?>

<!DOCTYPE html>
<html lang="sl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Izpis seznama</title>
</head>
<body>
    <h1>Nakupni seznam</h1>

    <?php
    if ($result && $result->num_rows > 0) {
        echo "<table border='1' cellpadding='8' cellspacing='0'>";
        echo "<tr><th>ID</th><th>Element</th><th>Količina</th></tr>";

        while ($row = $result->fetch_assoc()) {
            echo "<tr>";
            echo "<td>" . htmlspecialchars($row["id"]) . "</td>";
            echo "<td>" . htmlspecialchars($row["element"]) . "</td>";
            echo "<td>" . htmlspecialchars($row["kolicina"]) . "</td>";
            echo "</tr>";
        }

        echo "</table>";
    } else {
        echo "Ni vnešenih podatkov.";
    }

    $conn->close();
    ?>

    <br><br>
    <a href="index.html">Nazaj na vnos</a>
</body>
</html>