import { cp, mkdir, rm, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const configured = process.env.SGFS_GATEWAY_URL;
const key = process.env.SGFS_MUNICIPAL_PUBLIC_KEY;
if (Boolean(configured) !== Boolean(key)) {
  throw Error('Configure SGFS_GATEWAY_URL e SGFS_MUNICIPAL_PUBLIC_KEY juntos.');
}

let upstream;
if (configured) {
  upstream = new URL(configured);
  const vercelHosts = [process.env.VERCEL_URL, process.env.VERCEL_PROJECT_PRODUCTION_URL].filter(Boolean);
  if (upstream.protocol !== 'https:' || upstream.username || upstream.password || upstream.search
    || upstream.hash || !upstream.pathname.endsWith('/') || vercelHosts.includes(upstream.host)) {
    throw Error('SGFS_GATEWAY_URL deve ser a URL HTTPS do gateway, com barra final, em outro domínio.');
  }
}

execFileSync(process.execPath, ['scripts/build-static.mjs', ...upstream ? [] : ['--without-backend']], {
  cwd: root, stdio: 'inherit',
});

const output = new URL('../.vercel/output/', import.meta.url);
await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });
await cp(new URL('../dist-municipal/', import.meta.url), new URL('static/', output), { recursive: true });

const headers = {
  'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'",
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
};
const routes = [
  { src: '/.*', headers, continue: true },
  { src: '/SGFS/?', status: 308, headers: { Location: '/' } },
  ...upstream ? [
    { src: '/(backend/(?:auth|rest|functions)/v1/.*)', dest: upstream.href + '$1', headers: { 'Cache-Control': 'no-store' } },
    { src: '/(api/cnes)', dest: upstream.href + '$1', headers: { 'Cache-Control': 'no-store' } },
  ] : [],
  { handle: 'filesystem' },
];
await writeFile(new URL('config.json', output), JSON.stringify({ version: 3, routes }, null, 2));
console.log(upstream ? 'Vercel configurada para o gateway HTTPS.' : 'Vercel gerada em modo de manutenção sem conexão ao banco.');
