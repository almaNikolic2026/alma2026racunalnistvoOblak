const express = require("express");

const app = express();
const PORT = process.env.PORT || 3000;

app.get("/", function(req, res) {
	res.send(`
		<!DOCTYPE html>
		<html lang="en">
		<head>
			<meta charset="UTF-8" />
			<meta name="viewport" content="width=device-width, initial-scale=1.0" />
			<title>AWS Node.js Demo</title>

			<style>
				body {
					margin: 0;
					font-family: Arial, sans-serif;
					background: #f4f7f9;
					color: #222;
					display: flex;
					align-items: center;
					justify-content: center;
					min-height: 100vh;
				}

				.card {
					background: #ffffff;
					padding: 40px;
					border-radius: 18px;
					box-shadow: 0 10px 30px rgba(0, 0, 0, 0.08);
					text-align: center;
					max-width: 520px;
				}

				h1 {
					color: #004b67;
					margin-bottom: 12px;
				}

				p {
					font-size: 16px;
					line-height: 1.5;
				}

				.badge {
					display: inline-block;
					margin-top: 16px;
					padding: 8px 14px;
					background: #e6f4f8;
					color: #004b67;
					border-radius: 999px;
					font-weight: bold;
				}
			</style>
		</head>

		<body>
			<div class="card">
				<h1>AWS Node.js Demo</h1>
				<p>This app is running on an AWS EC2 server.</p>
				<p>It was deployed automatically from GitHub Actions.</p>
				<p>Tim Slana 4.5.2026</p>
				<p>Test CI/CD gitaction</p>
				<div class="badge">
					Server time: ${new Date().toLocaleString()}
				</div>
			</div>
		</body>
		</html>
	`);
});

app.get("/health", function(req, res) {
	res.json({
		status: "ok",
		app: "node-demo-app",
		time: new Date().toISOString()
	});
});

app.listen(PORT, function() {
	console.log("Server running on port " + PORT);
});