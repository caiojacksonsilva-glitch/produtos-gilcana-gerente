-- Produtos Gilçana Gerente V1.7
begin;

alter table public.mensagens add column if not exists lida_cliente boolean not null default false;
alter table public.mensagens add column if not exists lida_gerente boolean not null default false;

create or replace function public.gerente_listar_chats_v17()
returns jsonb language plpgsql security definer set search_path='' as $$
declare j jsonb;
begin
 if not public.sou_gerente() then raise exception 'Não autorizado.'; end if;
 select coalesce(jsonb_agg(x.o order by x.ultima desc),'[]'::jsonb) into j
 from (
  select max(m.criado_em) ultima,
   jsonb_build_object(
    'cliente_id',c.id,
    'cliente',coalesce(c.nome_empresa,c.nome_cliente),
    'telefone',c.telefone,
    'ultima',max(m.criado_em),
    'ultima_mensagem',(array_agg(m.mensagem order by m.criado_em desc,m.id desc))[1],
    'nao_lidas',count(*) filter(where m.remetente='cliente' and coalesce(m.lida_gerente,false)=false)
   ) o
  from public.mensagens m
  join public.clientes c on c.id=m.cliente_id
  group by c.id,c.nome_empresa,c.nome_cliente,c.telefone
 ) x;
 return j;
end;$$;
revoke all on function public.gerente_listar_chats_v17() from public,anon;
grant execute on function public.gerente_listar_chats_v17() to authenticated;

create or replace function public.gerente_mensagens(p_cliente_id bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j jsonb;
begin
 if not public.sou_gerente() then raise exception 'Não autorizado.'; end if;
 update public.mensagens set lida_gerente=true
 where cliente_id=p_cliente_id and remetente='cliente' and lida_gerente=false;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',id,'pedido_id',pedido_id,'remetente',remetente,'mensagem',mensagem,
  'criado_em',criado_em,'lida_cliente',lida_cliente,'lida_gerente',lida_gerente
 ) order by criado_em,id),'[]'::jsonb) into j
 from public.mensagens where cliente_id=p_cliente_id;
 return j;
end;$$;
revoke all on function public.gerente_mensagens(bigint) from public,anon;
grant execute on function public.gerente_mensagens(bigint) to authenticated;

create or replace function public.gerente_listar_clientes_v17()
returns jsonb language plpgsql security definer set search_path='' as $$
declare j jsonb;
begin
 if not public.sou_gerente() then raise exception 'Não autorizado.'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',id,'nome',coalesce(nome_empresa,nome_cliente),'telefone',telefone,'ativo',ativo
 ) order by coalesce(nome_empresa,nome_cliente)),'[]'::jsonb) into j
 from public.clientes;
 return j;
end;$$;
revoke all on function public.gerente_listar_clientes_v17() from public,anon;
grant execute on function public.gerente_listar_clientes_v17() to authenticated;

create or replace function public.gerente_cadastrar_cliente_v17(p_nome text,p_telefone text,p_codigo text)
returns bigint language plpgsql security definer set search_path='' as $$
declare v_id bigint; v_tel text;
begin
 if not public.sou_gerente() then raise exception 'Não autorizado.'; end if;
 if nullif(trim(p_nome),'') is null then raise exception 'Informe o nome do cliente.'; end if;
 v_tel:=regexp_replace(coalesce(p_telefone,''),'\\D','','g');
 if length(v_tel)<10 then raise exception 'Informe um WhatsApp válido.'; end if;
 if length(trim(coalesce(p_codigo,'')))<4 then raise exception 'A senha deve ter pelo menos 4 caracteres.'; end if;
 if exists(select 1 from public.clientes where regexp_replace(coalesce(telefone,''),'\\D','','g')=v_tel) then raise exception 'Este WhatsApp já está cadastrado.'; end if;
 if exists(select 1 from public.pessoas_autorizadas where regexp_replace(coalesce(telefone,''),'\\D','','g')=v_tel and ativo=true) then raise exception 'Este WhatsApp já pertence a uma pessoa autorizada.'; end if;
 insert into public.clientes(nome_cliente,telefone,ativo,codigo_acesso_hash)
 values(trim(p_nome),v_tel,true,extensions.crypt(trim(p_codigo),extensions.gen_salt('bf')))
 returning id into v_id;
 return v_id;
end;$$;
revoke all on function public.gerente_cadastrar_cliente_v17(text,text,text) from public,anon;
grant execute on function public.gerente_cadastrar_cliente_v17(text,text,text) to authenticated;

commit;
