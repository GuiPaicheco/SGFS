import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,existsSync} from 'node:fs';
const root=new URL('../',import.meta.url);
const readme=readFileSync(new URL('README.md',root),'utf8');
test('README descreve desenvolvimento e implantação atuais, sem formato de apresentação',()=>{
  assert.match(readme,/Sistema de Gestão de Funcionários/);
  for(const section of ['Executar localmente','Configuração','Testes e build','Estrutura','Implantação e manutenção','Licença']) assert.ok(readme.includes(`## ${section}`));
  assert.doesNotMatch(readme,/Para apresentar ao TI|Estado do projeto \(02\/10\/2026\)|Piloto de homologação — 09\/10\/2026/);
  assert.match(readme,/RH\/Diretor/);
  assert.match(readme,/distribuição principal usa PostgreSQL/);
  assert.match(readme,/node local\/integrado\.mjs/);
});
test('links locais do README apontam para arquivos existentes',()=>{
  for(const match of readme.matchAll(/\[[^\]]+\]\(([^)]+)\)/g)){
    if(/^https?:/.test(match[1]))continue;
    assert.ok(existsSync(new URL(match[1],root)),match[1]);
  }
});
test('README distingue configuração publicável de segredos e local de ambiente isolado',()=>{
  assert.match(readme,/não carrega automaticamente arquivos/);
  assert.match(readme,/banco PostgreSQL provisionado/);
  assert.match(readme,/Nunca coloque `SUPABASE_SERVICE_ROLE_KEY`/);
  assert.match(readme,/CI testa a cadeia de migrações/);
});
