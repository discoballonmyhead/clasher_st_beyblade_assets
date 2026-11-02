-- Optional stadium for a tournament (Accessory dataId from the parts catalog,
-- accessoryType = Stadium). Null = not specified, the default, so existing
-- tournaments are unchanged.
--
-- Used by TournamentStadiumRepository (Flutter):
--   tournaments_set_stadium(p_tournament_id, p_stadium_data_id)  -> {status, error}
--   tournaments_get_stadium(p_tournament_id)                     -> {status, stadium_data_id}

alter table public.tournaments
  add column if not exists stadium_data_id text;

create or replace function public.tournaments_set_stadium(
  p_tournament_id uuid,
  p_stadium_data_id text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return jsonb_build_object('status', 401, 'error', 'Sign in first.');
  end if;

  -- ADJUST: use the same "may manage this tournament" check as
  -- tournaments_set_part_rules in 20_part_lists.sql (host user, or staff of
  -- the hosting organization). The line below assumes a created_by column.
  if not exists (
    select 1 from public.tournaments t
    where t.id = p_tournament_id and t.created_by = auth.uid()
  ) then
    return jsonb_build_object('status', 403,
      'error', 'Only the host can change the stadium.');
  end if;

  update public.tournaments
     set stadium_data_id = nullif(trim(p_stadium_data_id), '')
   where id = p_tournament_id;

  return jsonb_build_object('status', 200);
end;
$$;

-- Runs as the caller, so the table's row-level security decides who can see
-- the tournament (private tournaments stay private).
create or replace function public.tournaments_get_stadium(p_tournament_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(
    (select jsonb_build_object('status', 200, 'stadium_data_id', t.stadium_data_id)
       from public.tournaments t where t.id = p_tournament_id),
    jsonb_build_object('status', 404, 'error', 'Tournament not found.')
  );
$$;

grant execute on function public.tournaments_set_stadium(uuid, text) to authenticated;
grant execute on function public.tournaments_get_stadium(uuid) to anon, authenticated;
