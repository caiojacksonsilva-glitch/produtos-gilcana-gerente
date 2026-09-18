import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors={
 'Access-Control-Allow-Origin':'*',
 'Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type',
 'Content-Type':'application/json'
};
const json=(x:any,s=200)=>new Response(JSON.stringify(x),{status:s,headers:cors});
const digits=(v:any)=>String(v??'').replace(/\D/g,'');
const brPhone=(v:any)=>{let n=digits(v); if(n && !n.startsWith('55')) n='55'+n; return n;};

Deno.serve(async(req)=>{
 if(req.method==='OPTIONS') return new Response('ok',{headers:cors});
 try{
  const SUPABASE_URL=Deno.env.get('SUPABASE_URL')!;
  const ANON=Deno.env.get('SUPABASE_ANON_KEY')!;
  const SERVICE=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const META_TOKEN=Deno.env.get('WHATSAPP_ACCESS_TOKEN');
  const PHONE_ID=Deno.env.get('WHATSAPP_PHONE_NUMBER_ID');
  const GRAPH_VERSION=Deno.env.get('WHATSAPP_GRAPH_VERSION')||'v23.0';
  if(!META_TOKEN||!PHONE_ID) return json({ok:false,configured:false,error:'WhatsApp ainda não possui credenciais da Meta.'},503);

  const auth=req.headers.get('Authorization')||'';
  if(!auth) return json({ok:false,error:'Sessão ausente.'},401);
  const userSb=createClient(SUPABASE_URL,ANON,{global:{headers:{Authorization:auth}}});
  const {data:isManager,error:managerError}=await userSb.rpc('sou_gerente');
  if(managerError||!isManager) return json({ok:false,error:'Não autorizado.'},403);

  const admin=createClient(SUPABASE_URL,SERVICE);
  const body=await req.json();
  const tipo=String(body.tipo||'');
  const pedidoId=body.pedido_id?Number(body.pedido_id):null;
  const clienteId=body.cliente_id?Number(body.cliente_id):null;

  const {data:paramsRow}=await admin.from('gerente_parametros').select('dados').eq('id',1).maybeSingle();
  const cfg=paramsRow?.dados||{};
  const enabled:any={
   pedido_confirmado:cfg.whatsapp_pedido_confirmado!==false,
   pedido_cancelado:cfg.whatsapp_pedido_cancelado!==false,
   pronto_envio:cfg.whatsapp_pronto_envio!==false,
   nova_mensagem:cfg.whatsapp_nova_mensagem!==false,
  };
  if(enabled[tipo]===false) return json({ok:true,skipped:true,reason:'Aviso desativado nas configurações.'});

  let cliente:any=null,pedido:any=null;
  if(pedidoId){
   const {data:p,error}=await admin.from('pedidos').select('id,numero,data_entrega,status,cliente_id').eq('id',pedidoId).single();
   if(error) throw error; pedido=p;
   const {data:c,error:ce}=await admin.from('clientes').select('id,nome_cliente,nome_empresa,telefone').eq('id',p.cliente_id).single();
   if(ce) throw ce; cliente=c;
  }else if(clienteId){
   const {data:c,error}=await admin.from('clientes').select('id,nome_cliente,nome_empresa,telefone').eq('id',clienteId).single();
   if(error) throw error; cliente=c;
  }else return json({ok:false,error:'Informe pedido_id ou cliente_id.'},400);

  const to=brPhone(cliente.telefone);
  if(to.length<12) return json({ok:false,error:'WhatsApp do cliente inválido.'},400);
  const names:any={
   pedido_confirmado:cfg.whatsapp_template_confirmado||'pedido_confirmado',
   pedido_cancelado:cfg.whatsapp_template_cancelado||'pedido_cancelado',
   pronto_envio:cfg.whatsapp_template_pronto||'pedido_pronto_envio',
   nova_mensagem:cfg.whatsapp_template_chat||'nova_mensagem',
  };
  const template=names[tipo];
  if(!template) return json({ok:false,error:'Tipo de aviso inválido.'},400);

  const nome=cliente.nome_empresa||cliente.nome_cliente||'Cliente';
  const vars:any={
   pedido_confirmado:[nome,String(pedido?.numero||''),String(pedido?.data_entrega||'')],
   pedido_cancelado:[nome,String(pedido?.numero||'')],
   pronto_envio:[nome,String(pedido?.numero||''),String(pedido?.data_entrega||'')],
   nova_mensagem:[nome],
  };
  const components=[{type:'body',parameters:(vars[tipo]||[]).map((text:string)=>({type:'text',text}))}];
  const payload={messaging_product:'whatsapp',to,type:'template',template:{name:template,language:{code:cfg.whatsapp_idioma||'pt_BR'},components}};

  const {data:log}=await admin.from('whatsapp_envios').insert({cliente_id:cliente.id,pedido_id:pedido?.id||null,tipo,telefone:to,status:'enviando'}).select('id').single();
  const res=await fetch(`https://graph.facebook.com/${GRAPH_VERSION}/${PHONE_ID}/messages`,{method:'POST',headers:{Authorization:`Bearer ${META_TOKEN}`,'Content-Type':'application/json'},body:JSON.stringify(payload)});
  const out=await res.json();
  if(!res.ok){
   if(log?.id) await admin.from('whatsapp_envios').update({status:'erro',erro:JSON.stringify(out)}).eq('id',log.id);
   return json({ok:false,error:'Meta recusou o envio.',meta:out},res.status);
  }
  const mid=out?.messages?.[0]?.id||null;
  if(log?.id) await admin.from('whatsapp_envios').update({status:'enviado',meta_message_id:mid,enviado_em:new Date().toISOString()}).eq('id',log.id);
  return json({ok:true,message_id:mid});
 }catch(e){return json({ok:false,error:e instanceof Error?e.message:String(e)},500)}
});
