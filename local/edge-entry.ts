// Register the original handlers before opening the loopback listener.
const handlers = new Map<string, (request: Request) => Response | Promise<Response>>();
const serve = Deno.serve.bind(Deno);
const names = (Deno.env.get('SGFS_FUNCTIONS') ?? '').split(',');
for (const name of names) {
  if (!/^[a-z-]+$/.test(name)) throw Error('Invalid edge function name');
  Deno.serve = ((handler: (request: Request) => Response | Promise<Response>) => {
    if (handlers.has(name)) throw Error('Edge function registered twice: ' + name);
    handlers.set(name, handler);
  }) as typeof Deno.serve;
  await import('../supabase/functions/' + name + '/index.ts');
  if (!handlers.has(name)) throw Error('Edge function did not register: ' + name);
}
Deno.serve = serve;
serve({ hostname: '127.0.0.1', port: Number(Deno.env.get('SGFS_FUNCTION_PORT')) }, request => {
  const name = new URL(request.url).pathname.slice(1);
  const handler = handlers.get(name);
  return handler ? handler(request) : new Response(null, { status: 404 });
});
