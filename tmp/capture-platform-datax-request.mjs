import { chromium } from 'playwright';
import fs from 'node:fs/promises';

const outDir = '/home/Kubernetes-Jupyter-Sandbox/tmp/screenshots';
await fs.mkdir(outDir, { recursive: true });

const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'] });
const context = await browser.newContext({ viewport: { width: 1440, height: 1200 } });
const page = await context.newPage();

async function clickIfVisible(locator) {
  try {
    if (await locator.first().isVisible({ timeout: 2000 })) {
      await locator.first().click();
      return true;
    }
  } catch {}
  return false;
}

async function loginPlatformAsTest1() {
  await page.goto('http://platform.local/', { waitUntil: 'domcontentloaded', timeout: 120000 });
  await page.waitForTimeout(1500);

  const alreadyLoggedIn = await page.getByRole('button', { name: /logout/i }).first().isVisible().catch(() => false);
  if (!alreadyLoggedIn) {
    await clickIfVisible(page.getByRole('button', { name: /test user 1/i }));
    await clickIfVisible(page.getByRole('button', { name: /jwt login/i }));
    await page.getByRole('button', { name: /logout/i }).first().waitFor({ state: 'visible', timeout: 120000 });
  }

  await page.getByText('Personal JupyterLab').first().waitFor({ state: 'visible', timeout: 120000 });
  await page.waitForTimeout(1000);

  const jupyterCard = page.locator('text=Personal JupyterLab').first().locator('xpath=ancestor::*[self::div or self::section][1]');
  await jupyterCard.screenshot({ path: `${outDir}/platform-jupyter-execution-20260409.png` });
  await page.screenshot({ path: `${outDir}/platform-login-jupyter-full-20260409.png`, fullPage: true });
}

async function loginDataxAsTest1AndCapture() {
  await page.goto('http://dataxflow.local/', { waitUntil: 'domcontentloaded', timeout: 120000 });
  await page.waitForTimeout(1500);

  const isLoginPage = await page.getByRole('button', { name: '로그인' }).first().isVisible().catch(() => false);
  if (isLoginPage) {
    await clickIfVisible(page.getByRole('button', { name: /적재 개발자 1/i }));
    await page.getByRole('button', { name: '로그인' }).first().click();
  }

  await page.getByRole('button', { name: '로그아웃' }).first().waitFor({ state: 'visible', timeout: 120000 });
  await page.waitForTimeout(1200);

  const queryVisible = await page.getByText(/query result|sample ansi sql/i).first().isVisible().catch(() => false);
  if (queryVisible) {
    const queryPanel = page.getByText(/query result/i).first().locator('xpath=ancestor::*[self::div or self::section][1]');
    await queryPanel.screenshot({ path: `${outDir}/datax-query-screen-20260409.png` });
  } else {
    await page.screenshot({ path: `${outDir}/datax-login-elt-screen-20260409.png`, fullPage: true });
  }
}

try {
  await loginPlatformAsTest1();
  await loginDataxAsTest1AndCapture();
  console.log('DONE');
  console.log(outDir);
} finally {
  await browser.close();
}
