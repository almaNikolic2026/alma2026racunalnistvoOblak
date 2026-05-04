<?php
require_once __DIR__ . '/config.php';

ini_set('display_errors', '1');
error_reporting(E_ALL);

mysqli_report(MYSQLI_REPORT_OFF);

$statusClass = 'badge-error';
$statusText = 'Napaka';
$message = 'Prislo je do nepricakovane napake.';
$details = '';

$element = trim($_POST['element'] ?? '');
$kolicina = (int)($_POST['kolicina'] ?? 0);

if ($element === '' || $kolicina <= 0) {
    $message = 'Element in pozitivna kolicina sta obvezna.';
} else {
    $conn = @new mysqli($host, $username, $password, $dbname, $port ?? 3306);
    if ($conn->connect_error) {
        $message = 'Povezava na bazo ni uspela.';
        $details = $conn->connect_error;
    } else {
        $conn->set_charset('utf8mb4');
        $stmt = $conn->prepare('INSERT INTO nakup (element, kolicina) VALUES (?, ?)');
        if (!$stmt) {
            $message = 'Napaka pri pripravi SQL stavka.';
            $details = $conn->error;
        } else {
            if (!$stmt->bind_param('si', $element, $kolicina)) {
                $message = 'Napaka pri vezavi parametrov.';
                $details = $stmt->error;
            } elseif (!$stmt->execute()) {
                $message = 'Napaka pri vnosu podatka v bazo.';
                $details = $stmt->error;
            } else {
                $statusClass = 'badge-ok';
                $statusText = 'Uspeh';
                $message = 'Podatek je uspesno shranjen v bazo.';
            }
            $stmt->close();
        }
        $conn->close();
    }
}

?>
<!DOCTYPE html>
<html lang="sl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Rezultat vnosa</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <div class="container">
        <div class="card">
            <h1>Rezultat vnosa</h1>
            <p><span class="badge <?php echo $statusClass; ?>"><?php echo htmlspecialchars($statusText); ?></span></p>
            <p><?php echo htmlspecialchars($message); ?></p>

            <?php if ($details !== ''): ?>
                <pre class="code"><?php echo htmlspecialchars($details); ?></pre>
            <?php endif; ?>

            <div class="actions">
                <a class="btn btn-primary" href="index.html">Nazaj na vnos</a>
                <a class="btn btn-secondary" href="izpis.php">Odpri izpis</a>
            </div>
        </div>
    </div>
</body>
</html>
