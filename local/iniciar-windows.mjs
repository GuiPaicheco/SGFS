import { spawnSync } from 'node:child_process';
import { join, delimiter } from 'node:path';
import { fileURLToPath } from 'node:url';

const pg = process.env.SGFS_POSTGRES_BIN ?? join(process.env.USERPROFILE, 'Downloads', 'pgsql', 'bin');
const root = process.env.SGFS_POSTGRES_HOME ?? join(process.env.LOCALAPPDATA, 'PostgreSQL', '18');
const runtime = process.env.SGFS_RUNTIME ?? join(process.env.LOCALAPPDATA, 'SGFS-runtime');

const python = join(runtime, 'python', 'Scripts', 'python.exe');
const resultSecrets = spawnSync(python, [fileURLToPath(new URL('./ler-credenciais-windows.py', import.meta.url)), runtime], {
  encoding: 'utf8', windowsHide: true,
});
if (resultSecrets.status !== 0) throw Error('Não foi possível ler as credenciais locais do SGFS.');
const secrets = JSON.parse(resultSecrets.stdout);

const env = {
  ...process.env,
  PATH: pg + delimiter + process.env.PATH,
  SGFS_JWT_SECRET: secrets.jwt,
  SGFS_AUTH_DATABASE_URL: 'postgresql://supabase_auth_admin:' + encodeURIComponent(secrets.auth) + '@127.0.0.1:55432/sgfs_integrado?sslmode=disable',
  SGFS_REST_DATABASE_URL: 'postgresql://sgfs_api_authenticator:' + encodeURIComponent(secrets.rest) + '@127.0.0.1:55432/sgfs_integrado?sslmode=disable',
  SGFS_AUTH_EXE: join(runtime, 'gotrue.exe'),
  SGFS_POSTGREST_EXE: join(runtime, 'postgrest', 'postgrest.exe'),
  SGFS_DENO_EXE: join(runtime, 'deno', 'deno.exe'),
  SGFS_PYTHON_EXE: python,
  SGFS_MAILPIT_EXE: join(runtime, 'mailpit', 'mailpit.exe'),
  SGFS_BROWSER_SDK_FILE: join(runtime, 'package', 'dist', 'umd', 'supabase.js'),
};

const pgctl = join(pg, 'pg_ctl.exe');
const data = join(root, 'migration-data');
const status = spawnSync(pgctl, ['-D', data, 'status'], { windowsHide: true, stdio: 'ignore' });
if (status.status === 3) {
  const boot = spawnSync(pgctl, ['-D', data, '-l', join(root, 'migration.log'), '-o', '-h 127.0.0.1 -p 55432', '-w', 'start'], { stdio: 'inherit' });
  if (boot.status !== 0) throw Error('Não foi possível iniciar o PostgreSQL local.');
}
const result = spawnSync(process.execPath, [fileURLToPath(new URL('./integrado.mjs', import.meta.url))], { env, stdio: 'inherit' });
process.exitCode = result.status ?? 1;
