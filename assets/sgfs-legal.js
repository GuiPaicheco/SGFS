(function(root){
'use strict';
const version='2026-11-24';
const section={
 terms:[
  'O SGFS organiza escalas, férias, folgas e afastamentos das unidades de saúde. Use o acesso atribuído à sua unidade ou função apenas para atividades autorizadas.',
  'Mantenha a senha protegida e encerre a sessão ao deixar o computador. Ao atuar como RH, identifique o operador que realizou a ação.',
  'Registre apenas o necessário. Evite diagnósticos e detalhes clínicos em observações. Confira os destinatários antes de exportar ou compartilhar arquivos e informe incidentes pelos canais institucionais.',
 ],
 privacy:[
  'O SGFS usa dados de identificação e vínculo profissional, lotação, calendários e registros de Férias e Afastamentos para apoiar as rotinas de gestão de pessoal. O CNES fornece parte dos dados cadastrais.',
  'O acesso depende da função e da unidade. A Administração autorizada gerencia o cadastro e os acessos. O RH consulta a equipe que lhe foi atribuída. Operações podem gerar registros de auditoria com conta, operador, data e ação.',
  'A Prefeitura de Betim é responsável pelo tratamento institucional. Solicitações de acesso, correção ou informação sobre o tratamento podem ser encaminhadas à Prefeitura pelos canais institucionais de atendimento ao titular. A Prefeitura define a base legal, os prazos de retenção e o canal específico antes da publicação oficial.',
  'Ao continuar, você registra que tomou ciência destes documentos.',
 ],
};
const publicKey='sgfs-public-terms';
let publicAccepted=false;
let pendingDialog;
let releaseShown=false;

function element(tag,text){
 const item=document.createElement(tag);
 if(text)item.textContent=text;
 return item;
}
function dialog(title){
 const modal=element('dialog');
 modal.className='sgfs-info-dialog';
 const heading=element('h2',title);
 heading.id='sgfs-dialog-heading';
 modal.setAttribute('aria-labelledby',heading.id);
 modal.append(heading);
 document.body.append(modal);
 modal.addEventListener('close',()=>modal.remove(),{once:true});
 return modal;
}
function documents(modal){
 for(const [title,items] of [['Termos de Uso',section.terms],['Aviso de Privacidade',section.privacy]]){
  const disclosure=element('details');
  disclosure.append(element('summary',title),...items.map(text=>element('p',text)));
  modal.append(disclosure);
 }
 const label=element('small','Versão dos documentos · '+version);
 modal.append(label);
}
function button(text,primary=true){
 const action=element('button',text);
 action.type='button';
 action.className='button '+(primary?'button-primary':'button-secondary');
 return action;
}
async function decision(save){
 if(pendingDialog)return pendingDialog;
 pendingDialog=new Promise(resolve=>{
  const modal=dialog('Termos de uso e privacidade');
  modal.append(element('p','Leia os documentos e confirme sua ciência para continuar.'));
  documents(modal);
  const message=element('p');
  message.setAttribute('role','alert');
  const actions=element('div');actions.className='actions';
  const agree=button('Aceitar e continuar'),decline=button('Recusar',false);
  actions.append(agree,decline);modal.append(message,actions);
  let saving=false;
  const finish=accepted=>{modal.close();resolve(accepted);};
  modal.addEventListener('cancel',e=>{e.preventDefault();if(!saving)finish(false);});
  decline.onclick=()=>finish(false);
  agree.onclick=async()=>{
   saving=true;agree.disabled=decline.disabled=true;message.textContent='';
   try{finish(await save()!==false);}
   catch(error){message.textContent=error.message;agree.disabled=decline.disabled=false;saving=false;}
  };
  modal.showModal();
 });
 try{return await pendingDialog;}finally{pendingDialog=null;}
}
async function ensurePublic(){
 if(publicAccepted)return true;
 try{if(sessionStorage.getItem(publicKey)===version){publicAccepted=true;return true;}}catch{}
 return decision(()=>{publicAccepted=true;try{sessionStorage.setItem(publicKey,version);}catch{}});
}
async function requireSession(url,key,session){
 const endpoint=url+'/rest/v1/rpc/sgfs_session_requirements';
 async function submit(body){
  const res=await fetch(endpoint,{method:'POST',headers:{'Content-Type':'application/json',apikey:key,Authorization:'Bearer '+session.access_token},body:JSON.stringify(body)});
  if(!res.ok){
   const error=await res.json().catch(()=>null);
   if(res.status===401||(res.status===403&&error?.code==='28000'&&error.message==='SGFS_SESSION_INVALID'))return null;
   throw Error('Não foi possível validar o aceite desta sessão. Entre novamente ou atualize a página.');
  }
  return res.json();
 }
 const status=await submit({});
 if(!status)return false;
 if(status.version!==version)throw Error('Os documentos foram atualizados. Atualize a página antes de continuar.');
 if(status.accepted)return true;
 return decision(async()=>{
  const result=await submit({accept_version:version});
  if(!result)return false;
  if(!result.accepted)throw Error('Não foi possível registrar o aceite.');
 });
}
function showDocuments(){
 if(document.querySelector('dialog[open]'))return;
 const modal=dialog('Termos de uso e privacidade');
 documents(modal);
 const close=button('Fechar');close.onclick=()=>modal.close();modal.append(close);modal.showModal();
}
function showVersions(onlyCurrent=false){
 if(document.querySelector('dialog[open]'))return false;
 const releases=root.SGFSReleases;
 if(!releases?.length)return false;
 const modal=dialog(onlyCurrent?'Novidades da versão':'Histórico de versões');
 for(const entry of onlyCurrent?releases.slice(0,1):releases){
  modal.append(element('h3','Versão '+entry.version),element('p',entry.date));
  const changes=element('ul');for(const change of entry.changes)changes.append(element('li',change));modal.append(changes);
 }
 const close=button('Fechar');close.onclick=()=>modal.close();modal.append(close);modal.showModal();
 return true;
}
function announceRelease(authenticated=false){
 if(releaseShown||(!authenticated&&!publicAccepted)||pendingDialog||!root.SGFSReleases?.length)return;
 const current=root.SGFSReleases[0].version;
 try{if(localStorage.getItem('sgfs-seen-release')===current)return;}catch{}
 if(showVersions(true)){releaseShown=true;try{localStorage.setItem('sgfs-seen-release',current);}catch{}}
}
const termsButton=document.querySelector('#sgfs-documents');
const versionsButton=document.querySelector('#sgfs-versions');
if(termsButton)termsButton.onclick=showDocuments;
if(versionsButton){
 versionsButton.textContent='Histórico de versões · '+root.SGFSReleases[0].version;
 versionsButton.onclick=()=>showVersions();
}
root.SGFSLegal={ensurePublic,requireSession,announceRelease,resetPublic(){publicAccepted=false;try{sessionStorage.removeItem(publicKey);}catch{}}};
})(globalThis);
