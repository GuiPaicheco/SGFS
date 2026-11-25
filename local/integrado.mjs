import { createHmac } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { createServer, request } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const port = Number(process.env.SGFS_PORT ?? 8089);
const local = new URL('http://127.0.0.1:' + port);
const site = new URL(process.env.SGFS_SITE_URL ?? local.origin + '/SGFS/');
if (!site.pathname.endsWith('/') || site.pathname === '/' || !/^https?:$/.test(site.protocol)
    || site.username || site.password || site.search || site.hash) {
  throw Error('SGFS_SITE_URL deve ser um endereço HTTP(S) com o diretório de publicação e uma barra final.');
}
const base = site.pathname;
const recoveryUrls = (process.env.SGFS_RECOVERY_URLS || '').split(',').map(value => value.trim()).filter(Boolean).map(value => {
  const alias = new URL(value);
  if (alias.protocol !== 'https:' || alias.username || alias.password || alias.search || alias.hash || !alias.pathname.endsWith('/')) {
    throw Error('Cada URL de recuperação adicional deve ser HTTPS, com barra final.');
  }
  return alias.href;
});
const gateway = local.origin + base + 'backend';
const output = resolve(root, 'dist-municipal');
const functions = [
  'access-auth', 'manage-rh', 'manage-cnes', 'manage-access', 'manage-catalogs',
  'manage-operations', 'manage-profiles', 'manage-inclusions', 'submit-request',
  'employee-auth', 'management-auth', 'provisional-login',
];
const authPort = 18991;
const restPort = 18992;
const cnesPort = 18993;
const edgePort = 19000;
const processes = [];
const required = name => {
  const value = process.env[name];
  if (!value) throw Error('Variável de configuração ausente: ' + name);
  return value;
};
const secret = required('SGFS_JWT_SECRET');
if (Buffer.byteLength(secret) < 32) throw Error('SGFS_JWT_SECRET precisa ter no mínimo 32 bytes.');
function jwt(role) {
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const data = encode({ alg: 'HS256', typ: 'JWT' }) + '.' + encode({ role, iss: 'sgfs', exp: Math.floor(Date.now() / 1000) + 31536000 });
  return data + '.' + createHmac('sha256', secret).update(data).digest('base64url');
}
const anonKey = jwt('anon');
const serviceKey = jwt('service_role');
const authDb = required('SGFS_AUTH_DATABASE_URL');
const restDb = required('SGFS_REST_DATABASE_URL');
const captureMail = process.env.SGFS_MAILPIT_EXE;
if (captureMail && site.origin !== local.origin) throw Error('A caixa de teste SMTP exige uma URL local.');
const smtpHost = captureMail ? '127.0.0.1' : process.env.SGFS_SMTP_HOST;
const authExe = required('SGFS_AUTH_EXE');
const restExe = required('SGFS_POSTGREST_EXE');
const pythonExe = required('SGFS_PYTHON_EXE');
const denoExe = required('SGFS_DENO_EXE');

const cleanEnv = Object.fromEntries(Object.entries(process.env).filter(([key]) => !/^(SGFS_|GOTRUE_|PGRST_|SUPABASE_|DATABASE_URL$)/i.test(key)));
const build = spawnSync(process.execPath, ['scripts/build-static.mjs'], {
  cwd: root, stdio: 'inherit', env: { ...cleanEnv, SGFS_MUNICIPAL_PUBLIC_KEY: anonKey, ...(process.env.SGFS_BROWSER_SDK_FILE ? { SGFS_BROWSER_SDK_FILE: process.env.SGFS_BROWSER_SDK_FILE } : {}) },
});
if (build.status !== 0) throw Error('Falha ao compilar a interface municipal.');

function start(name, executable, args, env) {
  const child = spawn(executable, args, {
    cwd: root, env: { ...cleanEnv, ...env }, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true,
  });
  processes.push(child);
  // Os serviços podem registrar URLs ou parâmetros. A saída detalhada é ativada só no ensaio.
  for (const stream of [child.stdout, child.stderr]) {
    if (process.env.SGFS_DEBUG === '1') stream.on('data', data => process.stderr.write('[' + name + '] ' + data));
    else stream.resume();
  }
  child.once('error', () => { console.error(name + ' falhou ao iniciar'); stop(1); });
  child.once('exit', code => { if (!stopping) { console.error(name + ' encerrou (' + code + ')'); stop(1); } });
}

let stopping = false;
function stop(code) {
  if (stopping) return;
  stopping = true;
  for (const child of processes) child.kill();
  server.close(() => process.exit(code));
  setTimeout(() => process.exit(code), 1500).unref();
}

const types = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.png': 'image/png',
};
const headers = {
  'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'",
  'X-Content-Type-Options': 'nosniff', 'Cache-Control': 'no-store',
};
function proxy(req, res, port, path) {
  const upstream = request({
    hostname: '127.0.0.1', port, path, method: req.method,
    headers: { ...req.headers, host: '127.0.0.1:' + port, 'x-forwarded-host': site.host, 'x-forwarded-proto': site.protocol.slice(0, -1), 'x-forwarded-for': req.socket.remoteAddress },
    timeout: 155000,
  }, response => {
    res.writeHead(response.statusCode, { ...response.headers, 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
    response.pipe(res);
  });
  upstream.on('timeout', () => upstream.destroy());
  upstream.on('error', () => {
    if (!res.headersSent) res.writeHead(502, { 'Content-Type': 'application/json' });
    res.end('{"error":"Serviço local indisponível."}');
  });
  res.on('close', () => upstream.destroy());
  req.pipe(upstream);
}
function deny(res,status,error){
  res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});
  res.end(JSON.stringify({error}));
}
async function authorizeSession(req,res,url,path){
  const match=/^Bearer (.+)$/i.exec(req.headers.authorization??'');
  if(!match||[anonKey,serviceKey].includes(match[1]))return true;
  if(path==='backend/rest/v1/rpc/sgfs_session_requirements')return true;
  if(path.startsWith('backend/auth/v1/'))return true;
  if(!path.startsWith('backend/')&&path!=='api/cnes')return true;
  let state;
  try{
    const response=await fetch('http://127.0.0.1:'+restPort+'/rpc/sgfs_session_requirements',{
      method:'POST',headers:{'Content-Type':'application/json',Authorization:req.headers.authorization},
      body:'{}',signal:AbortSignal.timeout(15000),
    });
    if(!response.ok){deny(res,401,'Sessão inválida ou expirada.');return false;}
    state=await response.json();
  }catch{deny(res,503,'Não foi possível validar a sessão.');return false;}
  if(!state.accepted){deny(res,403,'Aceite os documentos para continuar.');return false;}
  if(!state.passwordPending||path==='backend/functions/v1/access-auth')return true;
  if(path==='backend/rest/v1/profiles'&&req.method==='GET'&&url.searchParams.getAll('id').length===1){
    const subject=JSON.parse(Buffer.from(match[1].split('.')[1],'base64url')).sub;
    if(url.searchParams.get('id')==='eq.'+subject)return true;
  }
  deny(res,403,'Troque a senha provisória para continuar.');
  return false;
}
async function handle(req, res) {
  if (![local.host, site.host].includes(req.headers.host)) { res.writeHead(403).end(); return; }
  const url = new URL(req.url, local);
  if (url.origin !== local.origin) { res.writeHead(400).end(); return; }
  if (url.pathname === base.slice(0, -1)) { res.writeHead(302, { Location: base }).end(); return; }
  if (!url.pathname.startsWith(base)) { res.writeHead(404).end(); return; }
  const path = url.pathname.slice(base.length);
  if(!await authorizeSession(req,res,url,path))return;
  if (path.startsWith('backend/auth/v1/')) {
    const endpoint = path.slice('backend/auth/v1'.length);
    if ((endpoint === '/signup' && req.method === 'POST') || (endpoint === '/user' && req.method === 'PUT')) { res.writeHead(403).end(); return; }
    proxy(req, res, authPort, endpoint + url.search); return;
  }
  if (path.startsWith('backend/rest/v1/')) {
    proxy(req, res, restPort, path.slice('backend/rest/v1'.length) + url.search); return;
  }
  const edge = path.match(/^backend\/functions\/v1\/([a-z-]+)\/?$/);
  if (edge && functions.includes(edge[1])) {
    proxy(req, res, edgePort, '/' + edge[1] + url.search); return;
  }
  if (path === 'api/cnes') { proxy(req, res, cnesPort, '/api/cnes' + url.search); return; }
  if (!['GET', 'HEAD'].includes(req.method)) { res.writeHead(405).end(); return; }
  const file = resolve(output, path || 'index.html');
  const type = types[extname(file)];
  if (!file.startsWith(output + sep) || !type) { res.writeHead(404).end(); return; }
  try {
    const bytes = await readFile(file);
    res.writeHead(200, { ...headers, 'Content-Type': type, 'Content-Length': bytes.length });
    res.end(req.method === 'HEAD' ? undefined : bytes);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
    res.writeHead(404).end();
  }
}
const server = createServer((req, res) => {
  handle(req, res).catch(() => { if (!res.headersSent) res.writeHead(500); res.end(); });
});
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => stop(0));
server.on('error', () => stop(1));

if (captureMail) {
  start('SMTP local', captureMail, ['--listen', '127.0.0.1:19026', '--smtp', '127.0.0.1:19025'], { MP_DISABLE_VERSION_CHECK: 'true' });
}
start('Auth', authExe, [], {
  GOTRUE_API_HOST: '127.0.0.1', GOTRUE_API_PORT: String(authPort),
  API_EXTERNAL_URL: new URL('backend/auth/v1', site).href,
  GOTRUE_DB_DRIVER: 'postgres', GOTRUE_DB_DATABASE_URL: authDb,
  GOTRUE_SITE_URL: site.href, GOTRUE_URI_ALLOW_LIST: [site.href, ...recoveryUrls].join(','),
  GOTRUE_DISABLE_SIGNUP: 'true', GOTRUE_EXTERNAL_EMAIL_ENABLED: 'true',
  GOTRUE_JWT_SECRET: secret, GOTRUE_JWT_ADMIN_ROLES: 'service_role',
  GOTRUE_JWT_AUD: 'authenticated', GOTRUE_JWT_DEFAULT_GROUP_NAME: 'authenticated',
  GOTRUE_JWT_EXP: '3600', GOTRUE_PASSWORD_MIN_LENGTH: '8',
  GOTRUE_MAILER_AUTOCONFIRM: 'true',
  GOTRUE_MAILER_URLPATHS_INVITE: base + 'backend/auth/v1/verify',
  GOTRUE_MAILER_URLPATHS_RECOVERY: base + 'backend/auth/v1/verify',
  GOTRUE_MAILER_URLPATHS_CONFIRMATION: base + 'backend/auth/v1/verify',
  GOTRUE_MAILER_URLPATHS_EMAIL_CHANGE: base + 'backend/auth/v1/verify',
  ...(smtpHost ? {
    GOTRUE_SMTP_HOST: smtpHost, GOTRUE_SMTP_PORT: captureMail ? '19025' : (process.env.SGFS_SMTP_PORT ?? '587'),
    GOTRUE_SMTP_USER: process.env.SGFS_SMTP_USER ?? '', GOTRUE_SMTP_PASS: process.env.SGFS_SMTP_PASSWORD ?? '',
    GOTRUE_SMTP_ADMIN_EMAIL: captureMail ? 'sgfs-local@invalid.test' : required('SGFS_SMTP_FROM'),
  } : {}),
});
start('PostgREST', restExe, [], {
  PGRST_SERVER_HOST: '127.0.0.1', PGRST_SERVER_PORT: String(restPort),
  PGRST_DB_URI: restDb, PGRST_DB_SCHEMAS: 'public', PGRST_DB_ANON_ROLE: 'anon',
  PGRST_DB_EXTRA_SEARCH_PATH: 'public,extensions', PGRST_DB_MAX_ROWS: '1000',
  PGRST_JWT_SECRET: secret, PGRST_OPENAPI_MODE: 'disabled',
});
start('CNES', pythonExe, ['-m', 'uvicorn', 'api.cnes:app', '--host', '127.0.0.1', '--port', String(cnesPort)], {
  SUPABASE_URL: gateway, PYTHONDONTWRITEBYTECODE: '1',
});

start('Funções', denoExe, ['run', '--no-prompt', '--no-lock', '--cached-only',
    '--allow-env=SGFS_FUNCTIONS,SGFS_FUNCTION_PORT,SUPABASE_URL,SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY,SGF_RECOVERY_URLS,SGF_RECOVERY_CANONICAL',
    '--allow-read=' + join(root, 'supabase', 'functions') + ',' + join(root, 'config'),
    '--allow-net=127.0.0.1:' + port + ',127.0.0.1:' + edgePort,
    join(root, 'local', 'edge-entry.ts')], {
    SGFS_FUNCTIONS: functions.join(','), SGFS_FUNCTION_PORT: String(edgePort),
    SUPABASE_URL: gateway, SUPABASE_ANON_KEY: anonKey, SUPABASE_SERVICE_ROLE_KEY: serviceKey,
    SGF_RECOVERY_CANONICAL: site.href, SGF_RECOVERY_URLS: recoveryUrls.join(','),
  });

async function waitForService(name, port, path, expected) {
  const deadline = Date.now() + 60000;
  while (!stopping && Date.now() < deadline) {
    try {
      const result = await fetch('http://127.0.0.1:' + port + path, { signal: AbortSignal.timeout(3000) });
      await result.body?.cancel();
      if (expected.includes(result.status)) return;
    } catch {
      // O serviço pode estar inicializando.
    }
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  throw Error(name + ' não respondeu à verificação de inicialização.');
}
try {
  await Promise.all([
    waitForService('Auth', authPort, '/health', [200]),
    waitForService('PostgREST', restPort, '/calendar_events?select=id&limit=0', [200]),
    waitForService('CNES', cnesPort, '/api/cnes?cnes=2126486', [401]),
    waitForService('Funções', edgePort, '/access-auth', [405]),
    ...(captureMail ? [waitForService('SMTP local', 19026, '/', [200])] : []),
  ]);
  server.listen(port, '127.0.0.1', () => console.log('SGFS integrado em ' + local.origin + base));
} catch (error) {
  console.error(error.message);
  stop(1);
}
