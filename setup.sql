-- CREATOR TYCOON ONLINE — configuration Supabase
-- À exécuter une fois dans Supabase > SQL Editor > New query.
-- Ce script expose uniquement les lectures publiques et des RPC qui vérifient auth.uid().
-- Ne collez JAMAIS une clé service_role / secret dans le navigateur.

create table if not exists public.creators (
  user_id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  subscribers bigint not null default 50 check (subscribers >= 0),
  cash bigint not null default 2500 check (cash >= 0),
  total_views bigint not null default 0 check (total_views >= 0),
  videos_count integer not null default 0 check (videos_count >= 0),
  reputation integer not null default 50 check (reputation between 0 and 100),
  last_badbuzz_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists creators_name_lower_uidx on public.creators (lower(name));
create index if not exists creators_subscribers_idx on public.creators (subscribers desc, total_views desc);

create table if not exists public.world_state (
  id integer primary key default 1 check (id = 1),
  week_num integer not null default 1 check (week_num >= 1),
  trend_topic text not null default 'gaming',
  hot_format text not null default 'short',
  market_mood numeric(4,2) not null default 1.00 check (market_mood between 0.60 and 1.60),
  action_count integer not null default 0 check (action_count >= 0),
  updated_at timestamptz not null default now()
);
insert into public.world_state (id, week_num, trend_topic, hot_format, market_mood, action_count)
values (1, 1, 'gaming', 'short', 1.00, 0)
on conflict (id) do nothing;

create table if not exists public.videos (
  id bigint generated always as identity primary key,
  owner_id uuid not null references public.creators(user_id) on delete cascade,
  title text not null check (char_length(title) between 3 and 60),
  topic text not null,
  format text not null,
  quality integer not null check (quality between 1 and 5),
  promo_cost bigint not null default 0 check (promo_cost between 0 and 500),
  production_cost bigint not null default 0 check (production_cost >= 0),
  views bigint not null default 0 check (views >= 0),
  subscribers_gained bigint not null default 0 check (subscribers_gained >= 0),
  revenue bigint not null default 0 check (revenue >= 0),
  created_at timestamptz not null default now()
);
create index if not exists videos_owner_created_idx on public.videos (owner_id, created_at desc);

create table if not exists public.game_events (
  id bigint generated always as identity primary key,
  event_type text not null check (event_type in ('publish', 'badbuzz')),
  actor_id uuid references public.creators(user_id) on delete set null,
  target_id uuid references public.creators(user_id) on delete set null,
  message text not null,
  created_at timestamptz not null default now()
);
create index if not exists game_events_created_idx on public.game_events (created_at desc);

-- Active RLS partout. Les joueurs ne peuvent pas écrire directement leurs abonnés ou leur argent.
alter table public.creators enable row level security;
alter table public.world_state enable row level security;
alter table public.videos enable row level security;
alter table public.game_events enable row level security;

revoke all on table public.creators from anon, authenticated;
revoke all on table public.world_state from anon, authenticated;
revoke all on table public.videos from anon, authenticated;
revoke all on table public.game_events from anon, authenticated;
grant select on table public.creators, public.world_state, public.game_events to authenticated;
grant select on table public.videos to authenticated;

drop policy if exists "authenticated read creators" on public.creators;
create policy "authenticated read creators" on public.creators for select to authenticated using (true);
drop policy if exists "authenticated read world" on public.world_state;
create policy "authenticated read world" on public.world_state for select to authenticated using (true);
drop policy if exists "authenticated read videos" on public.videos;
create policy "authenticated read videos" on public.videos for select to authenticated using (true);
drop policy if exists "authenticated read game events" on public.game_events;
create policy "authenticated read game events" on public.game_events for select to authenticated using (true);

-- Crée la chaîne liée à l'utilisateur authentifié (y compris connexion anonyme Supabase).
create or replace function public.create_creator(p_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_creator public.creators%rowtype;
  v_name text := btrim(p_name);
begin
  if auth.uid() is null then raise exception 'Connecte-toi avant de créer une chaîne.'; end if;
  if v_name is null or char_length(v_name) < 3 or char_length(v_name) > 20 or v_name !~ '^[[:alnum:]À-ÿ _.-]+$' then
    raise exception 'Le pseudo doit contenir 3 à 20 caractères : lettres, chiffres, espaces, tirets, points ou underscore.';
  end if;

  select * into v_creator from public.creators where user_id = auth.uid();
  if found then return to_jsonb(v_creator); end if;

  insert into public.creators (user_id, name, subscribers, cash, total_views, videos_count, reputation)
  values (auth.uid(), v_name, 50, 2500, 0, 0, 50)
  returning * into v_creator;
  return to_jsonb(v_creator);
exception
  when unique_violation then raise exception 'Ce pseudo est déjà utilisé. Choisis-en un autre.';
end;
$$;

-- Publier une vidéo : les vues, abonnés et revenus sont calculés côté base de données.
create or replace function public.publish_video(
  p_title text,
  p_topic text,
  p_format text,
  p_quality integer,
  p_promo integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_creator public.creators%rowtype;
  v_world public.world_state%rowtype;
  v_video public.videos%rowtype;
  v_title text := btrim(p_title);
  v_cost bigint;
  v_views bigint;
  v_gained bigint;
  v_revenue bigint;
  v_topic_mult numeric;
  v_format_mult numeric;
  v_random_mult numeric;
  v_new_week integer;
  v_new_topic text;
  v_new_format text;
  v_new_mood numeric;
begin
  if auth.uid() is null then raise exception 'Connecte-toi avant de publier.'; end if;
  select * into v_creator from public.creators where user_id = auth.uid() for update;
  if not found then raise exception 'Crée d’abord ta chaîne.'; end if;
  if v_title is null or char_length(v_title) < 3 or char_length(v_title) > 60 then raise exception 'Le titre doit faire entre 3 et 60 caractères.'; end if;
  if p_topic not in ('gaming','humour','musique','sport','tech','cuisine','lifestyle') then raise exception 'Thématique invalide.'; end if;
  if p_format not in ('short','long','live') then raise exception 'Format invalide.'; end if;
  if p_quality is null or p_quality < 1 or p_quality > 5 then raise exception 'Qualité invalide.'; end if;
  if p_promo is null or p_promo < 0 or p_promo > 500 or p_promo % 50 <> 0 then raise exception 'Budget promotion invalide.'; end if;

  select * into v_world from public.world_state where id = 1 for update;
  v_cost := (p_quality * 45)::bigint + p_promo;
  if v_creator.cash < v_cost then raise exception 'Pas assez d’argent. Il te faut % € et tu possèdes % €.', v_cost, v_creator.cash; end if;

  v_topic_mult := case when p_topic = v_world.trend_topic then 1.65 else 0.90 end;
  v_format_mult := case when p_format = v_world.hot_format then 1.45 else 1.00 end;
  v_random_mult := 0.70 + random() * 0.80;
  v_views := greatest(50, least(5000000, round((150 + v_creator.subscribers * 1.0 + p_quality * 450 + p_promo * 8)::numeric * v_world.market_mood * v_topic_mult * v_format_mult * v_random_mult)::bigint));
  v_gained := greatest(0, floor(v_views * (0.002 + p_quality * 0.0006) * greatest(0.5, v_creator.reputation / 50.0))::bigint);
  v_revenue := greatest(0, floor(v_views / 1000.0 * (25 + v_world.market_mood * 15))::bigint);

  insert into public.videos (owner_id, title, topic, format, quality, promo_cost, production_cost, views, subscribers_gained, revenue)
  values (auth.uid(), v_title, p_topic, p_format, p_quality, p_promo, v_cost, v_views, v_gained, v_revenue)
  returning * into v_video;

  update public.creators
  set subscribers = subscribers + v_gained,
      cash = cash - v_cost + v_revenue,
      total_views = total_views + v_views,
      videos_count = videos_count + 1,
      updated_at = now()
  where user_id = auth.uid()
  returning * into v_creator;

  insert into public.game_events (event_type, actor_id, message)
  values ('publish', auth.uid(), format('%s publie « %s » : %s vues, +%s abonnés, %s € de revenus.', v_creator.name, v_title, to_char(v_views, 'FM999G999G999'), to_char(v_gained, 'FM999G999G999'), to_char(v_revenue, 'FM999G999G999')));

  update public.world_state set action_count = action_count + 1, updated_at = now() where id = 1 returning * into v_world;
  if v_world.action_count >= 6 then
    v_new_week := v_world.week_num + 1;
    v_new_topic := (array['gaming','humour','musique','sport','tech','cuisine','lifestyle'])[1 + floor(random()*7)::integer];
    v_new_format := (array['short','long','live'])[1 + floor(random()*3)::integer];
    v_new_mood := round((0.70 + random() * 0.80)::numeric, 2);
    update public.world_state set week_num = v_new_week, trend_topic = v_new_topic, hot_format = v_new_format, market_mood = v_new_mood, action_count = 0, updated_at = now() where id = 1 returning * into v_world;
  end if;

  return jsonb_build_object('creator', to_jsonb(v_creator), 'video', to_jsonb(v_video), 'world', to_jsonb(v_world));
end;
$$;

-- Bad buzz ciblé : choix d'accusations prédéfinies, cooldown de 10 minutes et possibilité de retour de flamme.
create or replace function public.launch_badbuzz(p_target_id uuid, p_claim text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor public.creators%rowtype;
  v_target public.creators%rowtype;
  v_world public.world_state%rowtype;
  v_chance numeric;
  v_success boolean;
  v_claim_label text;
  v_message text;
  v_new_topic text;
  v_new_format text;
  v_new_mood numeric;
begin
  if auth.uid() is null then raise exception 'Connecte-toi avant cette action.'; end if;
  if p_target_id is null or p_target_id = auth.uid() then raise exception 'Choisis un autre joueur.'; end if;
  if p_claim not in ('copie','pub','ego') then raise exception 'Type de polémique invalide.'; end if;
  select * into v_actor from public.creators where user_id = auth.uid() for update;
  if not found then raise exception 'Crée d’abord ta chaîne.'; end if;
  if v_actor.last_badbuzz_at is not null and v_actor.last_badbuzz_at > now() - interval '10 minutes' then
    raise exception 'Ton public se remet de la dernière polémique. Réessaie dans quelques minutes.';
  end if;
  select * into v_target from public.creators where user_id = p_target_id for update;
  if not found then raise exception 'Ce joueur n’existe plus dans le classement.'; end if;

  v_claim_label := case p_claim when 'copie' then 'copie de contenu' when 'pub' then 'publicité cachée' else 'drama après une interview' end;
  v_chance := greatest(0.20, least(0.80, 0.50 + (v_actor.reputation - v_target.reputation)::numeric / 200.0));
  v_success := random() < v_chance;

  if v_success then
    update public.creators
    set subscribers = greatest(0, subscribers - greatest(5, floor(subscribers * 0.03)::bigint)),
        reputation = greatest(0, reputation - 12), updated_at = now()
    where user_id = v_target.user_id returning * into v_target;
    update public.creators
    set reputation = least(100, reputation + 2), last_badbuzz_at = now(), updated_at = now()
    where user_id = auth.uid() returning * into v_actor;
    v_message := format('Bad buzz réussi : %s lance une polémique (%s) contre %s. La réputation de la cible chute.', v_actor.name, v_claim_label, v_target.name);
  else
    update public.creators
    set subscribers = greatest(0, subscribers - greatest(1, floor(subscribers * 0.005)::bigint)),
        reputation = greatest(0, reputation - 7), last_badbuzz_at = now(), updated_at = now()
    where user_id = auth.uid() returning * into v_actor;
    v_message := format('Retour de flamme : le bad buzz de %s contre %s (%s) se retourne contre lui.', v_actor.name, v_target.name, v_claim_label);
  end if;

  insert into public.game_events (event_type, actor_id, target_id, message)
  values ('badbuzz', auth.uid(), p_target_id, v_message);

  update public.world_state set action_count = action_count + 1, updated_at = now() where id = 1 returning * into v_world;
  if v_world.action_count >= 6 then
    v_new_topic := (array['gaming','humour','musique','sport','tech','cuisine','lifestyle'])[1 + floor(random()*7)::integer];
    v_new_format := (array['short','long','live'])[1 + floor(random()*3)::integer];
    v_new_mood := round((0.70 + random() * 0.80)::numeric, 2);
    update public.world_state set week_num = week_num + 1, trend_topic = v_new_topic, hot_format = v_new_format, market_mood = v_new_mood, action_count = 0, updated_at = now() where id = 1 returning * into v_world;
  end if;
  return jsonb_build_object('success', v_success, 'message', v_message, 'actor', to_jsonb(v_actor), 'target', to_jsonb(v_target), 'world', to_jsonb(v_world));
end;
$$;

-- Les RPC sont exécutables par des utilisateurs connectés, et les fonctions valident auth.uid().
revoke all on function public.create_creator(text) from public, anon;
revoke all on function public.publish_video(text,text,text,integer,integer) from public, anon;
revoke all on function public.launch_badbuzz(uuid,text) from public, anon;
grant execute on function public.create_creator(text) to authenticated;
grant execute on function public.publish_video(text,text,text,integer,integer) to authenticated;
grant execute on function public.launch_badbuzz(uuid,text) to authenticated;

-- Active les événements Realtime si la publication existe et que les tables n'y sont pas déjà.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='creators') then alter publication supabase_realtime add table public.creators; end if;
    if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='world_state') then alter publication supabase_realtime add table public.world_state; end if;
    if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='game_events') then alter publication supabase_realtime add table public.game_events; end if;
  end if;
end;
$$;
