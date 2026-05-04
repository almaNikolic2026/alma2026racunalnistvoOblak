<?php
// VAJA-06 — Obrazec za vnos študenta in prikaz tabele.

require __DIR__ . '/db.php';

$error    = null;
$inserted = null;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $ime     = trim($_POST['ime']     ?? '');
    $priimek = trim($_POST['priimek'] ?? '');

    if ($ime === '' || $priimek === '') {
        $error = 'Ime in priimek sta obvezna.';
    } elseif (mb_strlen($ime) > 30 || mb_strlen($priimek) > 30) {
        $error = 'Ime in priimek smeta biti največ 30 znakov.';
    } else {
        $stmt = $pdo->prepare('INSERT INTO student(ime, priimek) VALUES (?, ?)');
        $stmt->execute([$ime, $priimek]);
        $inserted = $pdo->lastInsertId();
    }
}

$rows = $pdo
    ->query('SELECT stevilka, ime, priimek FROM student ORDER BY stevilka')
    ->fetchAll();
?>
<!doctype html>
<html lang="sl">
<head>
    <meta charset="utf-8">
    <title>AlmaMater — seznam študentov</title>
    <style>
        body  { font-family: system-ui, sans-serif; max-width: 640px; margin: 2em auto; padding: 0 1em; color: #222; }
        h1    { margin-bottom: 0.25em; }
        p.sub { margin-top: 0; color: #666; }
        form  { display: flex; gap: 0.5em; margin: 1em 0; }
        input[type=text] { flex: 1; padding: 0.5em; font-size: 1em; border: 1px solid #bbb; border-radius: 4px; }
        button { padding: 0.5em 1em; background: #005a9c; color: #fff; border: 0; border-radius: 4px; cursor: pointer; }
        button:hover { background: #003f6b; }
        table { border-collapse: collapse; width: 100%; margin-top: 1em; }
        th, td { border: 1px solid #ddd; padding: 0.4em 0.6em; text-align: left; }
        th     { background: #f2f2f2; }
        .notice { padding: 0.5em 0.75em; background: #e8f7e8; border: 1px solid #9dcd9d; border-radius: 4px; margin: 0.75em 0; }
        .error  { padding: 0.5em 0.75em; background: #fbecec; border: 1px solid #cd9d9d; border-radius: 4px; margin: 0.75em 0; }
    </style>
</head>
<body>
    <h1>AlmaMater</h1>
    <p class="sub">Vnos študenta v bazo in prikaz obstoječih zapisov.</p>

    <?php if ($error): ?>
        <div class="error"><?= htmlspecialchars($error) ?></div>
    <?php elseif ($inserted): ?>
        <div class="notice">Študent je bil dodan (št. <?= (int)$inserted ?>).</div>
    <?php endif; ?>

    <form method="post">
        <input type="text" name="ime"     placeholder="Ime"     maxlength="30" required>
        <input type="text" name="priimek" placeholder="Priimek" maxlength="30" required>
        <button type="submit">Dodaj</button>
    </form>

    <table>
        <thead>
            <tr><th>Št.</th><th>Ime</th><th>Priimek</th></tr>
        </thead>
        <tbody>
            <?php foreach ($rows as $r): ?>
            <tr>
                <td><?= (int)$r['stevilka'] ?></td>
                <td><?= htmlspecialchars($r['ime']) ?></td>
                <td><?= htmlspecialchars($r['priimek']) ?></td>
            </tr>
            <?php endforeach; ?>
        </tbody>
    </table>
</body>
</html>
