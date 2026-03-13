import { mkdir } from "node:fs/promises";
import { chromium } from "playwright";

const outputDir = "/workspace/docs/screenshots";
const targetSet = new Set(
  (
    process.env.CAPTURE_TARGETS ??
    "frontend,backend,airflow,jupyter,gitlab,control-plane-login,control-plane-nodes,control-plane-pods"
  )
    .split(",")
    .map((value) => value.trim().toLowerCase())
    .filter(Boolean),
);
const controlPlaneUsername = process.env.CONTROL_PLANE_USERNAME ?? "platform-admin";
const controlPlanePassword = process.env.CONTROL_PLANE_PASSWORD ?? "controlplane123!";

async function ensureDir() {
  await mkdir(outputDir, { recursive: true });
}

async function sleep(ms) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForHttp(url, { timeoutMs = 300000, intervalMs = 5000 } = {}) {
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    try {
      const response = await fetch(url, { redirect: "manual" });
      if (response.status >= 200 && response.status < 400) {
        return;
      }
    } catch {
      // Keep polling until the service is reachable.
    }

    await sleep(intervalMs);
  }

  throw new Error(`Timed out waiting for ${url}`);
}

async function captureFrontend(browser) {
  await waitForHttp("http://127.0.0.1:30080", { timeoutMs: 180000 });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1024 } });
  await page.goto("http://127.0.0.1:30080", { waitUntil: "networkidle", timeout: 180000 });
  await page.screenshot({ path: `${outputDir}/frontend-dashboard.png`, fullPage: true });
  await page.close();
}

async function createControlPlanePage(browser) {
  const page = await browser.newPage({
    viewport: { width: 1440, height: 1200 },
  });
  await page.addInitScript(() => {
    window.localStorage.removeItem("controlPlaneToken");
  });
  await page.goto("http://127.0.0.1:30080/#control-plane", {
    waitUntil: "networkidle",
    timeout: 180000,
  });
  return page;
}

async function loginControlPlane(page) {
  await page.getByLabel("Admin Username").fill(controlPlaneUsername);
  await page.getByLabel("Admin Password").fill(controlPlanePassword);
  await page.getByRole("button", { name: "Login Dashboard" }).click();
  await page.getByRole("tab", { name: "Nodes" }).waitFor({ state: "visible", timeout: 180000 });
  await page.waitForLoadState("networkidle", { timeout: 180000 }).catch(() => {});
}

async function captureBackend(browser) {
  await waitForHttp("http://127.0.0.1:30081/docs", { timeoutMs: 180000 });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1024 } });
  await page.goto("http://127.0.0.1:30081/docs", { waitUntil: "networkidle", timeout: 180000 });
  await page.screenshot({ path: `${outputDir}/backend-openapi.png`, fullPage: true });
  await page.close();
}

async function captureAirflow(browser) {
  await waitForHttp("http://127.0.0.1:30090/login/", { timeoutMs: 240000 });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1024 } });
  await page.goto("http://127.0.0.1:30090/login/", { waitUntil: "domcontentloaded", timeout: 240000 });
  await page.getByLabel("Username").fill("admin");
  await page.getByLabel("Password").fill("admin12345!");
  await page.getByRole("button", { name: /sign in/i }).click();
  await page.waitForLoadState("networkidle", { timeout: 240000 });
  await page.screenshot({ path: `${outputDir}/airflow-home.png`, fullPage: true });
  await page.close();
}

async function captureJupyter(browser) {
  await waitForHttp("http://127.0.0.1:30088/login", { timeoutMs: 240000 });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1024 } });
  await page.goto("http://127.0.0.1:30088/login", { waitUntil: "domcontentloaded", timeout: 240000 });
  await page.getByLabel("Password or token").fill("platform123");
  await page.getByRole("button", { name: /log in/i }).click();
  await page.waitForURL(/lab/, { timeout: 240000 });
  await page.waitForLoadState("networkidle", { timeout: 240000 }).catch(() => {});
  await page.screenshot({ path: `${outputDir}/jupyter-lab.png`, fullPage: true });
  await page.close();
}

async function captureGitLab(browser) {
  await waitForHttp("http://127.0.0.1:30089/users/sign_in", { timeoutMs: 600000 });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1024 } });
  await page.goto("http://127.0.0.1:30089/users/sign_in", { waitUntil: "domcontentloaded", timeout: 480000 });
  await page.getByLabel(/username or primary email/i).fill("root");
  await page.getByLabel(/^password$/i).fill("v7Q#2mL!9xC@4pR%8tZ");
  await page.getByRole("button", { name: /sign in/i }).click();
  await page.waitForLoadState("networkidle", { timeout: 480000 });
  await page.screenshot({ path: `${outputDir}/gitlab-dashboard.png`, fullPage: true });
  await page.close();
}

async function captureControlPlaneLogin(browser) {
  await waitForHttp("http://127.0.0.1:30080", { timeoutMs: 180000 });
  const page = await createControlPlanePage(browser);
  await page.screenshot({ path: `${outputDir}/k8s-control-plane-login.png`, fullPage: true });
  await page.close();
}

async function captureControlPlaneNodes(browser) {
  await waitForHttp("http://127.0.0.1:30080", { timeoutMs: 180000 });
  const page = await createControlPlanePage(browser);
  await loginControlPlane(page);
  await page.screenshot({ path: `${outputDir}/k8s-control-plane-nodes.png`, fullPage: true });
  await page.close();
}

async function captureControlPlanePods(browser) {
  await waitForHttp("http://127.0.0.1:30080", { timeoutMs: 180000 });
  const page = await createControlPlanePage(browser);
  await loginControlPlane(page);
  await page.getByRole("tab", { name: "Pods" }).click();
  await page.waitForLoadState("networkidle", { timeout: 180000 }).catch(() => {});
  await page.screenshot({ path: `${outputDir}/k8s-control-plane-pods.png`, fullPage: true });
  await page.close();
}

const captures = [
  ["frontend", captureFrontend],
  ["backend", captureBackend],
  ["airflow", captureAirflow],
  ["jupyter", captureJupyter],
  ["gitlab", captureGitLab],
  ["control-plane-login", captureControlPlaneLogin],
  ["control-plane-nodes", captureControlPlaneNodes],
  ["control-plane-pods", captureControlPlanePods],
];

const browser = await chromium.launch({ headless: true });

try {
  await ensureDir();
  for (const [name, capture] of captures) {
    if (!targetSet.has(name)) {
      continue;
    }
    await capture(browser);
  }
} finally {
  await browser.close();
}
