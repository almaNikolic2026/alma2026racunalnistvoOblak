<?php
require_once __DIR__ . '/config.php';

$result = null;
$error = '';

try {
    mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
    $conn = new mysqli($host, $username, $password, $dbname, $port ?? 3306);
    $conn->set_charset('utf8mb4');
    $sql = 'SELECT id, element, kolicina FROM nakup ORDER BY id DESC';
    $result = $conn->query($sql);
} catch (Throwable $e) {
    $error = $e->getMessage();
}
?>
<!DOCTYPE html>
<html lang="sl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Izpis nakupov</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <div class="container">
    <div class="card">
      <h1>Izpis nakupnega seznama</h1>
      <p>Pregled vseh vnesenih elementov iz baze.</p>

      <div class="actions">
        <a class="btn btn-primary" href="index.html">Nazaj na vnos</a>
      </div>

      <?php if ($error !== ''): ?>
        <p><span class="badge badge-error">Napaka baze</span></p>
        <pre class="code"><?php echo htmlspecialchars($error); ?></pre>
      <?php elseif ($result && $result->num_rows > 0): ?>
        <table class="table">
          <thead>
            <tr>
              <th>ID</th>
              <th>Element</th>
              <th>Kolicina</th>
            </tr>
          </thead>
          <tbody>
          <?php while ($row = $result->fetch_assoc()): ?>
            <tr>
              <td><?php echo htmlspecialchars($row['id']); ?></td>
              <td><?php echo htmlspecialchars($row['element']); ?></td>
              <td><?php echo htmlspecialchars($row['kolicina']); ?></td>
            </tr>
          <?php endwhile; ?>
          </tbody>
        </table>
      <?php else: ?>
        <p>Tabela je prazna.</p>
      <?php endif; ?>
    </div>
  </div>
</body>
</html>
<?php
if (isset($conn) && $conn instanceof mysqli) {
    $conn->close();
}
