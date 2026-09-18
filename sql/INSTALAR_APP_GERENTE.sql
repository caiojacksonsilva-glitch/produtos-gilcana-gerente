-- PRODUTOS GILÇANA GERENTE V1
-- Execute no MESMO projeto do app cliente: kpzcvreqjkgevzmlipjs
-- Antes de executar, troque SOMENTE a senha na linha marcada SENHA_INICIAL.

begin;
create extension if not exists pgcrypto with schema extensions;

do $$ begin
 if to_regclass('public.clientes') is null or to_regclass('public.pedidos') is null or to_regclass('public.produtos') is null then
  raise exception 'BASE_CLIENTE_AUSENTE: execute este SQL no projeto Supabase do Produtos Gilçana Cliente.';
 end if;
end $$;

create table if not exists public.gerente_config(
 id smallint primary key default 1 check(id=1), senha_hash text not null, atualizado_em timestamptz not null default now()
);
-- SENHA_INICIAL: troque 12345 pela senha que você quer usar no painel.
insert into public.gerente_config(id,senha_hash) values(1,extensions.crypt('12345',extensions.gen_salt('bf'))) on conflict(id) do nothing;

create table if not exists public.gerente_sessoes(
 auth_uid uuid primary key references auth.users(id) on delete cascade,
 nome_computador text not null default 'Computador', ativo boolean not null default true,
 criado_em timestamptz not null default now(), ultimo_acesso timestamptz not null default now()
);
alter table public.gerente_config enable row level security;
alter table public.gerente_sessoes enable row level security;

create or replace function public.sou_gerente()
returns boolean language sql security definer set search_path='' stable as $$
 select exists(select 1 from public.gerente_sessoes where auth_uid=auth.uid() and ativo=true);
$$;
revoke all on function public.sou_gerente() from public,anon;
grant execute on function public.sou_gerente() to authenticated;

create or replace function public.ativar_gerente(p_senha text,p_nome_computador text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare h text; n int;
begin
 if auth.uid() is null then raise exception 'Sessão inexistente.'; end if;
 select senha_hash into h from public.gerente_config where id=1;
 if h is null or extensions.crypt(coalesce(p_senha,''),h)<>h then raise exception 'Senha incorreta.'; end if;
 if exists(select 1 from public.gerente_sessoes where auth_uid=auth.uid()) then
   update public.gerente_sessoes set ativo=true,nome_computador=coalesce(nullif(trim(p_nome_computador),''),nome_computador),ultimo_acesso=now() where auth_uid=auth.uid();
   return jsonb_build_object('ok',true);
 end if;
 select count(*) into n from public.gerente_sessoes where ativo=true;
 if n>=3 then raise exception 'Limite de 3 computadores autorizados atingido.'; end if;
 insert into public.gerente_sessoes(auth_uid,nome_computador) values(auth.uid(),coalesce(nullif(trim(p_nome_computador),''),'Computador'));
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.ativar_gerente(text,text) from public,anon;
grant execute on function public.ativar_gerente(text,text) to authenticated;

create or replace function public.gerente_trocar_senha(p_nova text)
returns void language plpgsql security definer set search_path='' as $$ begin
 if not public.sou_gerente() then raise exception 'Não autorizado.'; end if;
 if length(trim(p_nova))<4 then raise exception 'Use pelo menos 4 caracteres.'; end if;
 update public.gerente_config set senha_hash=extensions.crypt(trim(p_nova),extensions.gen_salt('bf')),atualizado_em=now() where id=1;
end $$;
revoke all on function public.gerente_trocar_senha(text) from public,anon;
grant execute on function public.gerente_trocar_senha(text) to authenticated;

create or replace function public.gerente_listar_computadores()
returns jsonb language sql security definer set search_path='' stable as $$
 select case when public.sou_gerente() then coalesce(jsonb_agg(jsonb_build_object('auth_uid',auth_uid,'nome',nome_computador,'ativo',ativo,'ultimo_acesso',ultimo_acesso) order by ultimo_acesso desc),'[]'::jsonb) else '[]'::jsonb end from public.gerente_sessoes;
$$;
revoke all on function public.gerente_listar_computadores() from public,anon;
grant execute on function public.gerente_listar_computadores() to authenticated;

create or replace function public.gerente_remover_computador(p_uid uuid)
returns void language plpgsql security definer set search_path='' as $$ begin
 if not public.sou_gerente() then raise exception 'Não autorizado.'; end if;
 update public.gerente_sessoes set ativo=false where auth_uid=p_uid;
end $$;
revoke all on function public.gerente_remover_computador(uuid) from public,anon;
grant execute on function public.gerente_remover_computador(uuid) to authenticated;

create or replace function public.gerente_listar_pedidos(p_filtro text default 'pending')
returns jsonb language plpgsql security definer set search_path='' stable as $$
declare outj jsonb;
begin
 if not public.sou_gerente() then raise exception 'Não autorizado.'; end if;
 select coalesce(jsonb_agg(x.obj order by x.criado desc),'[]'::jsonb) into outj from (
  select p.criado_em criado, jsonb_build_object(
   'id',p.id,'numero',p.numero,'data_entrega',p.data_entrega,'status',p.status,'criado_em',p.criado_em,
   'cliente_id',c.id,'cliente',coalesce(c.nome_empresa,c.nome_cliente),'telefone',c.telefone,
   'enviado_por',coalesce(pa.nome,c.nome_cliente,c.nome_empresa),
   'itens',coalesce((select jsonb_agg(jsonb_build_object('nome',pr.nome,'unidade',pr.unidade,'quantidade',i.quantidade)) from public.itens_pedido i join public.produtos pr on pr.id=i.produto_id where i.pedido_id=p.id),'[]'::jsonb)
  ) obj
  from public.pedidos p join public.clientes c on c.id=p.cliente_id left join public.pessoas_autorizadas pa on pa.id=p.pessoa_autorizada_id
  where (p_filtro='all' or (p_filtro='pending' and p.status in ('enviado','recebido')) or p.status=p_filtro)
 ) x;
 return outj;
end $$;
revoke all on function public.gerente_listar_pedidos(text) from public,anon;
grant execute on function public.gerente_listar_pedidos(text) to authenticated;

create or replace function public.gerente_receber_pedido(p_id bigint) returns void language plpgsql security definer set search_path='' as $$ begin if not public.sou_gerente() then raise exception 'Não autorizado.'; end if; perform public.receber_pedido(p_id); end $$;
create or replace function public.gerente_confirmar_pedido(p_id bigint) returns void language plpgsql security definer set search_path='' as $$ begin if not public.sou_gerente() then raise exception 'Não autorizado.'; end if; perform public.confirmar_pedido(p_id); end $$;
create or replace function public.gerente_cancelar_pedido(p_id bigint) returns void language plpgsql security definer set search_path='' as $$ begin if not public.sou_gerente() then raise exception 'Não autorizado.'; end if; perform public.cancelar_pedido(p_id); end $$;
revoke all on function public.gerente_receber_pedido(bigint),public.gerente_confirmar_pedido(bigint),public.gerente_cancelar_pedido(bigint) from public,anon;
grant execute on function public.gerente_receber_pedido(bigint),public.gerente_confirmar_pedido(bigint),public.gerente_cancelar_pedido(bigint) to authenticated;

create or replace function public.gerente_listar_chats()
returns jsonb language plpgsql security definer set search_path='' stable as $$ declare j jsonb; begin
 if not public.sou_gerente() then raise exception 'Não autorizado.'; end if;
 select coalesce(jsonb_agg(o order by o->>'ultima' desc),'[]'::jsonb) into j from (
  select jsonb_build_object('cliente_id',c.id,'cliente',coalesce(c.nome_empresa,c.nome_cliente),'telefone',c.telefone,'ultima',max(m.criado_em),'ultima_mensagem',(array_agg(m.mensagem order by m.criado_em desc))[1]) o
  from public.mensagens m join public.clientes c on c.id=m.cliente_id group by c.id,c.nome_empresa,c.nome_cliente,c.telefone
 )q; return j; end $$;
create or replace function public.gerente_mensagens(p_cliente_id bigint)
returns jsonb language plpgsql security definer set search_path='' stable as $$ declare j jsonb; begin
 if not public.sou_gerente() then raise exception 'Não autorizado.'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'pedido_id',pedido_id,'remetente',remetente,'mensagem',mensagem,'criado_em',criado_em) order by criado_em),'[]'::jsonb) into j from public.mensagens where cliente_id=p_cliente_id; return j; end $$;
create or replace function public.gerente_enviar_mensagem(p_cliente_id bigint,p_mensagem text,p_pedido_id bigint default null)
returns bigint language plpgsql security definer set search_path='' as $$ begin
 if not public.sou_gerente() then raise exception 'Não autorizado.'; end if;
 if nullif(trim(p_mensagem),'') is null then raise exception 'Mensagem vazia.'; end if;
 return public.enviar_mensagem(p_cliente_id,p_pedido_id,'gerente',trim(p_mensagem)); end $$;
revoke all on function public.gerente_listar_chats(),public.gerente_mensagens(bigint),public.gerente_enviar_mensagem(bigint,text,bigint) from public,anon;
grant execute on function public.gerente_listar_chats(),public.gerente_mensagens(bigint),public.gerente_enviar_mensagem(bigint,text,bigint) to authenticated;

create or replace function public.gerente_listar_produtos()
returns jsonb language plpgsql security definer set search_path='' stable as $$ declare j jsonb; begin
 if not public.sou_gerente() then raise exception 'Não autorizado.'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'codigo',codigo,'nome',nome,'descricao',descricao,'unidade',unidade,'quantidade_disponivel',quantidade_disponivel,'imagem_url',imagem_url,'ativo',ativo) order by nome),'[]'::jsonb) into j from public.produtos; return j; end $$;
create or replace function public.gerente_salvar_produto(p_id bigint,p_codigo text,p_nome text,p_descricao text,p_unidade text,p_estoque numeric,p_imagem text,p_ativo boolean)
returns bigint language plpgsql security definer set search_path='' as $$ declare rid bigint; begin
 if not public.sou_gerente() then raise exception 'Não autorizado.'; end if;
 if nullif(trim(p_nome),'') is null then raise exception 'Informe o nome.'; end if;
 if p_id is null then insert into public.produtos(codigo,nome,descricao,unidade,quantidade_disponivel,imagem_url,ativo) values(nullif(trim(p_codigo),''),trim(p_nome),p_descricao,p_unidade,greatest(coalesce(p_estoque,0),0),nullif(p_imagem,''),coalesce(p_ativo,true)) returning id into rid;
 else update public.produtos set codigo=nullif(trim(p_codigo),''),nome=trim(p_nome),descricao=p_descricao,unidade=p_unidade,quantidade_disponivel=greatest(coalesce(p_estoque,0),0),imagem_url=nullif(p_imagem,''),ativo=coalesce(p_ativo,true) where id=p_id returning id into rid; end if;
 return rid; end $$;
revoke all on function public.gerente_listar_produtos(),public.gerente_salvar_produto(bigint,text,text,text,text,numeric,text,boolean) from public,anon;
grant execute on function public.gerente_listar_produtos(),public.gerente_salvar_produto(bigint,text,text,text,text,numeric,text,boolean) to authenticated;

create or replace function public.gerente_dias_entrega()
returns jsonb language plpgsql security definer set search_path='' stable as $$ declare j jsonb; begin if not public.sou_gerente() then raise exception 'Não autorizado.'; end if; select coalesce(jsonb_agg(jsonb_build_object('dia_semana',dia_semana,'ativo',ativo,'horario_corte',horario_corte,'dias_antes_preparacao',dias_antes_preparacao) order by dia_semana),'[]'::jsonb) into j from public.dias_entrega; return j; end $$;
create or replace function public.gerente_salvar_dia(p_dia int,p_ativo boolean,p_corte time,p_antes int)
returns void language plpgsql security definer set search_path='' as $$ begin if not public.sou_gerente() then raise exception 'Não autorizado.'; end if; if p_dia<0 or p_dia>6 then raise exception 'Dia inválido.'; end if; insert into public.dias_entrega(dia_semana,ativo,horario_corte,dias_antes_preparacao) values(p_dia,p_ativo,coalesce(p_corte,'10:00'),greatest(coalesce(p_antes,1),0)) on conflict(dia_semana) do update set ativo=excluded.ativo,horario_corte=excluded.horario_corte,dias_antes_preparacao=excluded.dias_antes_preparacao; end $$;
create or replace function public.gerente_excecoes_entrega()
returns jsonb language plpgsql security definer set search_path='' stable as $$ declare j jsonb; begin if not public.sou_gerente() then raise exception 'Não autorizado.'; end if; select coalesce(jsonb_agg(jsonb_build_object('data_original',data_original,'nova_data',nova_data,'cancelada',cancelada) order by data_original desc),'[]'::jsonb) into j from public.excecoes_entrega; return j; end $$;
create or replace function public.gerente_salvar_excecao(p_original date,p_nova date,p_cancelada boolean)
returns void language plpgsql security definer set search_path='' as $$ begin if not public.sou_gerente() then raise exception 'Não autorizado.'; end if; if p_original is null then raise exception 'Informe a data original.'; end if; insert into public.excecoes_entrega(data_original,nova_data,cancelada) values(p_original,case when p_cancelada then null else p_nova end,coalesce(p_cancelada,false)) on conflict(data_original) do update set nova_data=excluded.nova_data,cancelada=excluded.cancelada; end $$;
revoke all on function public.gerente_dias_entrega(),public.gerente_salvar_dia(int,boolean,time,int),public.gerente_excecoes_entrega(),public.gerente_salvar_excecao(date,date,boolean) from public,anon;
grant execute on function public.gerente_dias_entrega(),public.gerente_salvar_dia(int,boolean,time,int),public.gerente_excecoes_entrega(),public.gerente_salvar_excecao(date,date,boolean) to authenticated;

-- Bucket público para imagens de produtos; somente computadores-gerente podem gravar.
insert into storage.buckets(id,name,public) values('produtos','produtos',true) on conflict(id) do update set public=true;
drop policy if exists gerente_envia_imagem_produto on storage.objects;
create policy gerente_envia_imagem_produto on storage.objects for insert to authenticated with check(bucket_id='produtos' and public.sou_gerente());
drop policy if exists gerente_atualiza_imagem_produto on storage.objects;
create policy gerente_atualiza_imagem_produto on storage.objects for update to authenticated using(bucket_id='produtos' and public.sou_gerente()) with check(bucket_id='produtos' and public.sou_gerente());
drop policy if exists gerente_remove_imagem_produto on storage.objects;
create policy gerente_remove_imagem_produto on storage.objects for delete to authenticated using(bucket_id='produtos' and public.sou_gerente());

commit;
