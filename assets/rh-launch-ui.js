(function(root){
'use strict';
async function mount({app,esc,request,isCurrent,onBack,viewState={}}){
 let page=viewState.page||0,search=viewState.search||'',data=null,busy=false,error='';
 async function load(fresh=false){if(!isCurrent())return;busy=true;error='';draw();try{
  const result=await request({action:'launch-employees',page,search},{fresh});
  if(isCurrent())data=result;
 }catch(e){error=e.message;data=null;}finally{busy=false;if(isCurrent())draw();}}
 function draw(){if(!isCurrent())return;Object.assign(viewState,{page,search});app.setAttribute?.('aria-busy',String(busy));
 app.innerHTML=`<section class="card rh-launch-card"><h2>Férias e Cadastros</h2><p>Encontre o funcionário e escolha o que deseja registrar.</p>${error?`<p role="alert">${esc(error)}</p>`:''}<form id="rh-launch-search" class="form-grid"><div class="field"><label for="rh-launch-name">Funcionário</label><input id="rh-launch-name" class="control" placeholder="Digite o nome do funcionário" maxlength="120" value="${esc(search)}" ${busy?'disabled':''}></div><div class="actions"><button class="button button-secondary" ${busy?'disabled':''}>Buscar</button></div></form>${busy?'<p role="status">Carregando funcionários…</p>':''}${data?`<div class="table-wrap"><table><caption>Funcionários da unidade · Ordem alfabética</caption><thead><tr><th scope="col">Nome</th><th scope="col">Cargo</th><th scope="col">Opções</th></tr></thead><tbody>${data.employees.map(x=>`<tr><th scope="row">${esc(x.full_name)}</th><td>${esc(x.position||'—')}</td><td>${x.entry_id&&x.binding_confirmed?`<button type="button" class="button button-primary" data-launch-entry="${esc(x.entry_id)}" ${busy?'disabled':''} aria-label="Lançar férias de ${esc(x.full_name)}">Lançar Férias</button> <button type="button" class="button button-secondary" data-occurrence-type="folga" data-occurrence-entry="${esc(x.entry_id)}" ${busy?'disabled':''}>Folga e Afastamento</button> <button type="button" class="button button-secondary" data-occurrence-type="dayoff" data-occurrence-entry="${esc(x.entry_id)}" ${busy?'disabled':''} aria-label="Cadastrar dayoff de ${esc(x.full_name)}">Cadastrar dayoff</button>`:'<span>Cadastro indisponível para lançamento</span>'} ${x.entry_id?`<button type="button" class="button button-secondary" data-record-entry="${esc(x.entry_id)}">Visualizar registros</button>`:''}</td></tr>`).join('')||'<tr><td colspan="3">Nenhum funcionário encontrado.</td></tr>'}</tbody></table></div><div class="actions"><button type="button" id="rh-launch-prev" class="button button-secondary" ${busy||!page?'disabled':''}>Anterior</button><span>${data.total} funcionários · Página ${page+1}</span><button type="button" id="rh-launch-next" class="button button-secondary" ${busy||(page+1)*50>=data.total?'disabled':''}>Próxima</button></div>`:''}</section>`;
 app.querySelector('#rh-launch-search').onsubmit=e=>{e.preventDefault();if(busy)return;search=app.querySelector('#rh-launch-name').value.trim();page=0;load(true);};
 if(data){app.querySelector('#rh-launch-prev').onclick=()=>{if(!busy&&page){page--;load();}};app.querySelector('#rh-launch-next').onclick=()=>{if(!busy&&(page+1)*50<data.total){page++;load();}};
 for(const button of app.querySelectorAll?.('[data-record-entry]')||[])button.onclick=()=>{
  const person=data.employees.find(x=>x.entry_id===button.dataset.recordEntry);
  if(!busy&&person)openHistory({app,esc,request,isCurrent,person,onBack:()=>load(true)});
 };
 for(const button of app.querySelectorAll?.('[data-occurrence-entry]')||[])button.onclick=()=>{if(!busy&&isCurrent())(button.dataset.occurrenceType==='dayoff'?root.SGFRhEmployee:root.SGFRhOccurrence).open({app,esc,request,isCurrent,entryId:button.dataset.occurrenceEntry,type:button.dataset.occurrenceType,onBack:()=>load(true)});};
 for(const button of app.querySelectorAll?.('[data-launch-entry]')||[])button.onclick=()=>{if(busy||!isCurrent())return;const entryId=button.dataset.launchEntry;if(!data.employees.some(x=>x.entry_id===entryId&&x.binding_confirmed))return;root.SGFRhLeave.open({app,esc,request,isCurrent,entryId,cnes:null,onBack});};}
 }
 await load();
}
async function openHistory({app,esc,request,isCurrent,person,onBack}){
 let page=0;
 async function load(){
  app.innerHTML='<section class="card"><h2>Registros do profissional</h2><p role="status">Carregando…</p><button type="button" id="rh-history-back">Voltar</button></section>';
  let active=true;app.querySelector('#rh-history-back').onclick=()=>{active=false;onBack();};
  try{
   const {records,more}=await request({action:'record-history',entryId:person.entry_id,page},{fresh:true});
   if(!active||!isCurrent())return;
   app.innerHTML=`<section class="card"><h2>Registros do profissional</h2><p>${esc(person.full_name)}</p>
   <ul>${records.map((r,i)=>`<li>${esc(r.protocol||r.id)} · ${esc(root.SGFRhLeave.recordType(r.type))} · ${esc(root.SGFRhLeave.recordStatus(r.status))} <button type="button" data-history-record="${i}">Abrir registro</button></li>`).join('')||'<li>Nenhum lançamento encontrado.</li>'}</ul>
   <div class="actions"><button type="button" id="rh-history-prev" ${page?'':'disabled'}>Anterior</button><button type="button" id="rh-history-next" ${more?'':'disabled'}>Próxima</button><button type="button" id="rh-history-back">Voltar</button></div></section>`;
   app.querySelector('#rh-history-back').onclick=onBack;
   app.querySelector('#rh-history-prev').onclick=()=>{page--;load();};
   app.querySelector('#rh-history-next').onclick=()=>{page++;load();};
   for(const button of app.querySelectorAll('[data-history-record]'))button.onclick=()=>{
    const r=records[Number(button.dataset.historyRecord)];
    root.SGFRhLeave.detail({app,esc,request,isCurrent,leaveId:r.id,origin:r.origin,onBack:load});
   };
  }catch(error){
   if(active&&isCurrent()){const message=app.querySelector('[role=status]');message.setAttribute('role','alert');message.textContent=error.message;}
  }
 }
 await load();
}
root.SGFRhLaunch={mount};
})(globalThis);
