// Web export smoke test (synthesis D14, R14; docs/QA.md §2.3).
//
//   cd tools/qa/web && npm ci && node web_smoke.mjs [--build ../../../build/web] [--out shot.png]
//       [--wait 20] [--json report.json]
//
// Serves the exported Web build from a local static server, opens it in headless Chromium with
// WebGL2 on SwiftShader (software, like llvmpipe for the desktop captures), waits for the boot ->
// main hand-off, taps the meadow once (touch-down cues and the Web audio path), and fails if the
// page logs any error. Chrome: $CHROME if set (CI uses the runner's google-chrome), otherwise the
// pinned @sparticuz/chromium binary from npm (no browser download host needed).
// Exit 0 = booted cleanly, 1 = errors or a blank canvas, 2 = usage / setup problems.

import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import puppeteer from "puppeteer-core";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DEFAULTS = {
	build: path.resolve(HERE, "../../../build/web"),
	out: path.resolve(HERE, "../../../qa/out/web/web_smoke.png"),
	wait: 20,
	json: "",
};
// Phone-sized CSS viewport (1 dp = 3 px design units at DPR 3 is too slow on SwiftShader; DPR 1
// at 360x640 dp still runs the full layout path).
const VIEWPORT = { width: 360, height: 640, deviceScaleFactor: 1, isMobile: true, hasTouch: true };
const BANNER = /Godot Engine v4\.7\.2\.stable/;
const AFTER_TAP_MS = 3000;
const GOTO_TIMEOUT_MS = 60000;
// A booted frame has a sky gradient: more than this many distinct sampled colours.
const MIN_DISTINCT_COLOURS = 8;
const MIME = {
	".html": "text/html; charset=utf-8",
	".js": "text/javascript",
	".wasm": "application/wasm",
	".pck": "application/octet-stream",
	".png": "image/png",
	".json": "application/json",
};

function parseArgs(argv) {
	const args = { ...DEFAULTS };
	for (let i = 0; i < argv.length; i++) {
		const [key, inline] = argv[i].replace(/^--/, "").split("=", 2);
		if (!(key in args)) {
			throw new Error(`unknown option --${key}`);
		}
		args[key] = inline ?? argv[++i];
	}
	args.wait = Number(args.wait);
	return args;
}

function serve(root) {
	const server = http.createServer((req, res) => {
		const rel = decodeURIComponent(new URL(req.url, "http://localhost").pathname);
		const file = path.join(root, rel === "/" ? "index.html" : rel);
		if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
			res.writeHead(404);
			res.end();
			return;
		}
		res.writeHead(200, { "Content-Type": MIME[path.extname(file)] ?? "application/octet-stream" });
		fs.createReadStream(file).pipe(res);
	});
	return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)));
}

async function launch() {
	const swiftshader = ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
		"--autoplay-policy=no-user-gesture-required", "--no-sandbox"];
	if (process.env.CHROME) {
		return puppeteer.launch({ executablePath: process.env.CHROME, headless: true, args: swiftshader });
	}
	let chromium;
	try {
		chromium = (await import("@sparticuz/chromium")).default;
	} catch {
		throw new Error("no browser: set CHROME=/path/to/chrome or `npm ci` the optional @sparticuz/chromium");
	}
	return puppeteer.launch({
		executablePath: await chromium.executablePath(),
		headless: "shell",
		args: [...chromium.args, ...swiftshader],
	});
}

async function main() {
	let args;
	try {
		args = parseArgs(process.argv.slice(2));
	} catch (e) {
		console.error(`web_smoke: ${e.message}`);
		return 2;
	}
	const root = path.resolve(args.build);
	if (!fs.existsSync(path.join(root, "index.html")) || !fs.existsSync(path.join(root, "index.wasm"))) {
		console.error(`web_smoke: no Web export in ${root} (run tools/ci/run_ci.sh export)`);
		return 2;
	}
	const server = await serve(root);
	const url = `http://127.0.0.1:${server.address().port}/index.html`;
	let browser;
	const logs = [];
	try {
		browser = await launch();
		const page = await browser.newPage();
		await page.setViewport(VIEWPORT);
		page.on("console", (m) => logs.push({ type: m.type(), text: m.text() }));
		page.on("pageerror", (e) => logs.push({ type: "pageerror", text: e.message }));
		page.on("requestfailed", (r) => logs.push({ type: "requestfailed", text: `${r.url()} ${r.failure()?.errorText}` }));
		const t0 = Date.now();
		await page.goto(url, { waitUntil: "load", timeout: GOTO_TIMEOUT_MS });
		await new Promise((r) => setTimeout(r, args.wait * 1000));
		await page.touchscreen.tap(VIEWPORT.width / 2, VIEWPORT.height * 0.7);
		await new Promise((r) => setTimeout(r, AFTER_TAP_MS));
		fs.mkdirSync(path.dirname(path.resolve(args.out)), { recursive: true });
		const png = await page.screenshot({ path: path.resolve(args.out) });
		// Count colours on the screenshot, not on the WebGL canvas (its drawing buffer is not preserved,
		// so reading it back gives a blank image).
		const probe = await page.evaluate(async (b64) => {
			const gl = document.createElement("canvas").getContext("webgl2");
			const canvas = document.querySelector("canvas");
			const img = new Image();
			img.src = `data:image/png;base64,${b64}`;
			await img.decode();
			const shot = document.createElement("canvas");
			shot.width = 32;
			shot.height = 64;
			const ctx = shot.getContext("2d");
			ctx.drawImage(img, 0, 0, shot.width, shot.height);
			const px = ctx.getImageData(0, 0, shot.width, shot.height).data;
			const colours = new Set();
			for (let i = 0; i < px.length; i += 4) {
				colours.add((px[i] << 16) | (px[i + 1] << 8) | px[i + 2]);
			}
			return {
				webgl2: gl ? gl.getParameter(gl.VERSION) : null,
				canvas: canvas ? [canvas.width, canvas.height] : null,
				distinct_colours: colours.size,
			};
		}, Buffer.from(png).toString("base64"));
		const errors = logs.filter((l) => ["error", "pageerror", "requestfailed"].includes(l.type)
			|| /SCRIPT ERROR|^ERROR:/.test(l.text));
		const warnings = logs.filter((l) => l.type === "warn" || l.type === "warning");
		const report = {
			tool: "tools/qa/web/web_smoke.mjs",
			build: root,
			seconds: (Date.now() - t0) / 1000,
			...probe,
			banner: logs.some((l) => BANNER.test(l.text)),
			errors,
			warnings,
			logs,
			screenshot: path.resolve(args.out),
		};
		report.pass = report.banner && errors.length === 0 && probe.distinct_colours >= MIN_DISTINCT_COLOURS;
		const text = JSON.stringify(report, null, 2);
		if (args.json) {
			fs.writeFileSync(path.resolve(args.json), text + "\n");
		}
		console.log(text);
		console.error(`web_smoke: ${report.pass ? "PASS" : "FAIL"} (${errors.length} errors, ${warnings.length} warnings, `
			+ `${probe.distinct_colours} colours, ${report.seconds.toFixed(1)} s)`);
		return report.pass ? 0 : 1;
	} catch (e) {
		console.error(`web_smoke: ${e.message}`);
		return 2;
	} finally {
		if (browser) {
			await browser.close();
		}
		server.close();
	}
}

process.exitCode = await main();
