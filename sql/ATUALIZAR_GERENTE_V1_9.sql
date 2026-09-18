-- Produtos Gilçana Gerente V1.9 - Backup e restauração
begin;

create or replace function public.gerente_exportar_backup_v19()
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v jsonb;
begin
  if not public.sou_gerente() then raise exception 'Não autorizado.'; end if;
  select jsonb_build_object(
    'formato','produtos-gilcana-backup',
    'versao',1,
    'gerado_em',now(),
    'clientes',(select coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]'::jsonb) from public.clientes t),
    'pessoas_autorizadas',(select coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]'::jsonb) from public.pessoas_autorizadas t),
    'produtos',(select coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]'::jsonb) from public.produtos t),
    'produtos_recomendados',(select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) from public.produtos_recomendados t),
    'configuracoes',(select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) from public.configuracoes t),
    'dias_entrega',(select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) from public.dias_entrega t),
    'excecoes_entrega',(select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) from public.excecoes_entrega t),
    'excecoes_corte',(select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) from public.excecoes_corte t),
    'lotes_entrega',(select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) from public.lotes_entrega t),
    'pedidos',(select coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]'::jsonb) from public.pedidos t),
    'itens_pedido',(select coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]'::jsonb) from public.itens_pedido t),
    'reservas_estoque',(select coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]'::jsonb) from public.reservas_estoque t),
    'mensagens',(select coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]'::jsonb) from public.mensagens t),
    'notificacoes',(select coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]'::jsonb) from public.notificacoes t)
  ) into v;
  return v;
end;$$;
revoke all on function public.gerente_exportar_backup_v19() from public,anon;
grant execute on function public.gerente_exportar_backup_v19() to authenticated;

create or replace function public.gerente_restaurar_backup_v19(p_backup jsonb)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare seq text; tname text; n_clientes int; n_pedidos int; n_produtos int;
begin
  if not public.sou_gerente() then raise exception 'Não autorizado.'; end if;
  if coalesce(p_backup->>'formato','') <> 'produtos-gilcana-backup' then raise exception 'Arquivo de backup inválido.'; end if;
  if coalesce((p_backup->>'versao')::int,0) <> 1 then raise exception 'Versão de backup não suportada.'; end if;

  -- Tudo ocorre na mesma transação: se qualquer etapa falhar, nada é apagado.
  delete from public.notificacoes;
  delete from public.mensagens;
  delete from public.reservas_estoque;
  delete from public.itens_pedido;
  delete from public.pedidos;
  delete from public.lotes_entrega;
  delete from public.excecoes_corte;
  delete from public.excecoes_entrega;
  delete from public.dias_entrega;
  delete from public.produtos_recomendados;
  delete from public.pessoas_autorizadas;
  delete from public.produtos;
  delete from public.clientes;
  delete from public.configuracoes;

  insert into public.clientes select * from jsonb_populate_recordset(null::public.clientes,coalesce(p_backup->'clientes','[]'::jsonb));
  insert into public.pessoas_autorizadas select * from jsonb_populate_recordset(null::public.pessoas_autorizadas,coalesce(p_backup->'pessoas_autorizadas','[]'::jsonb));
  insert into public.produtos select * from jsonb_populate_recordset(null::public.produtos,coalesce(p_backup->'produtos','[]'::jsonb));
  insert into public.produtos_recomendados select * from jsonb_populate_recordset(null::public.produtos_recomendados,coalesce(p_backup->'produtos_recomendados','[]'::jsonb));
  insert into public.configuracoes select * from jsonb_populate_recordset(null::public.configuracoes,coalesce(p_backup->'configuracoes','[]'::jsonb));
  insert into public.dias_entrega select * from jsonb_populate_recordset(null::public.dias_entrega,coalesce(p_backup->'dias_entrega','[]'::jsonb));
  insert into public.excecoes_entrega select * from jsonb_populate_recordset(null::public.excecoes_entrega,coalesce(p_backup->'excecoes_entrega','[]'::jsonb));
  insert into public.excecoes_corte select * from jsonb_populate_recordset(null::public.excecoes_corte,coalesce(p_backup->'excecoes_corte','[]'::jsonb));
  insert into public.lotes_entrega select * from jsonb_populate_recordset(null::public.lotes_entrega,coalesce(p_backup->'lotes_entrega','[]'::jsonb));
  insert into public.pedidos select * from jsonb_populate_recordset(null::public.pedidos,coalesce(p_backup->'pedidos','[]'::jsonb));
  insert into public.itens_pedido select * from jsonb_populate_recordset(null::public.itens_pedido,coalesce(p_backup->'itens_pedido','[]'::jsonb));
  insert into public.reservas_estoque select * from jsonb_populate_recordset(null::public.reservas_estoque,coalesce(p_backup->'reservas_estoque','[]'::jsonb));
  insert into public.mensagens select * from jsonb_populate_recordset(null::public.mensagens,coalesce(p_backup->'mensagens','[]'::jsonb));
  insert into public.notificacoes select * from jsonb_populate_recordset(null::public.notificacoes,coalesce(p_backup->'notificacoes','[]'::jsonb));

  -- Reposiciona sequências de IDs quando existirem.
  foreach tname in array array['clientes','pessoas_autorizadas','produtos','lotes_entrega','pedidos','itens_pedido','reservas_estoque','mensagens','notificacoes'] loop
    select pg_get_serial_sequence('public.'||tname,'id') into seq;
    if seq is not null then
      execute format('select setval(%L, greatest(coalesce((select max(id) from public.%I),0),1), true)',seq,tname);
    end if;
  end loop;

  select count(*) into n_clientes from public.clientes;
  select count(*) into n_produtos from public.produtos;
  select count(*) into n_pedidos from public.pedidos;
  return jsonb_build_object('ok',true,'clientes',n_clientes,'produtos',n_produtos,'pedidos',n_pedidos);
end;$$;
revoke all on function public.gerente_restaurar_backup_v19(jsonb) from public,anon;
grant execute on function public.gerente_restaurar_backup_v19(jsonb) to authenticated;

commit;
