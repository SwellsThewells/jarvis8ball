-- Jarvis 8 Pool: everything the online side keeps.
--
-- Paste the whole file into the Supabase SQL editor and run it once (see
-- ONLINE_SETUP.md). Running it again is safe: it drops and recreates the
-- functions and only creates tables that are missing.
--
-- The game can read what it needs straight from the tables, but it never
-- writes to them directly. Anything that changes coins, trophies, cues,
-- friends, messages or lobbies goes through one of the functions below, which
-- check who is asking and whether they're allowed.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
	id uuid primary key references auth.users (id) on delete cascade,
	username text not null,               -- Discord handle, lower case
	display_name text not null,
	avatar_url text,
	coins int not null default 100 check (coins >= 0),
	trophies int not null default 0,
	mp_wins int not null default 0,
	mp_losses int not null default 0,
	owned_cues text[] not null default array['house'],
	stats jsonb not null default '{}'::jsonb,
	last_bot_reward timestamptz,
	bot_reward_day date,
	bot_rewards_today int not null default 0,
	created_at timestamptz not null default now()
);
create index if not exists profiles_username_idx on public.profiles (lower(username));
create index if not exists profiles_display_idx on public.profiles (lower(display_name));

create table if not exists public.cue_prices (
	id text primary key,
	price int not null check (price >= 0),
	secret boolean not null default false
);

create table if not exists public.codes (
	code text primary key,
	cue_id text not null references public.cue_prices (id)
);

create table if not exists public.friendships (
	requester uuid not null references public.profiles (id) on delete cascade,
	addressee uuid not null references public.profiles (id) on delete cascade,
	status text not null default 'pending' check (status in ('pending', 'accepted')),
	created_at timestamptz not null default now(),
	primary key (requester, addressee),
	check (requester <> addressee)
);
create index if not exists friendships_addressee_idx on public.friendships (addressee);

create table if not exists public.lobbies (
	id uuid primary key default gen_random_uuid(),
	code text not null unique,
	host uuid not null references public.profiles (id) on delete cascade,
	guest uuid references public.profiles (id) on delete set null,
	name text not null check (char_length(name) between 1 and 40),
	is_public boolean not null default true,
	rules jsonb not null default '{}'::jsonb,
	status text not null default 'open' check (status in ('open', 'full', 'playing', 'closed')),
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);
create index if not exists lobbies_browse_idx on public.lobbies (is_public, status, updated_at);

create table if not exists public.messages (
	id bigint generated always as identity primary key,
	sender uuid not null references public.profiles (id) on delete cascade,
	recipient uuid not null references public.profiles (id) on delete cascade,
	body text not null check (char_length(body) between 1 and 500),
	kind text not null default 'text' check (kind in ('text', 'invite')),
	lobby_id uuid references public.lobbies (id) on delete set null,
	created_at timestamptz not null default now(),
	read_at timestamptz
);
create index if not exists messages_pair_idx on public.messages (sender, recipient, created_at desc);
create index if not exists messages_recipient_idx on public.messages (recipient, read_at);

create table if not exists public.matches (
	id uuid primary key default gen_random_uuid(),
	lobby_id uuid references public.lobbies (id) on delete set null,
	host uuid not null references public.profiles (id) on delete cascade,
	guest uuid not null references public.profiles (id) on delete cascade,
	rules jsonb not null default '{}'::jsonb,
	seed int not null,
	host_report uuid,
	guest_report uuid,
	first_report_at timestamptz,
	winner uuid,
	awarded boolean not null default false,
	started_at timestamptz not null default now(),
	finished_at timestamptz
);

-- ---------------------------------------------------------------------------
-- Who can read what. Nobody writes to these tables directly.
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.cue_prices enable row level security;
alter table public.codes enable row level security;
alter table public.friendships enable row level security;
alter table public.lobbies enable row level security;
alter table public.messages enable row level security;
alter table public.matches enable row level security;

revoke insert, update, delete on all tables in schema public from anon, authenticated;
revoke all on public.codes from anon, authenticated;

drop policy if exists "profiles are public" on public.profiles;
create policy "profiles are public" on public.profiles for select to authenticated using (true);

drop policy if exists "prices are public" on public.cue_prices;
create policy "prices are public" on public.cue_prices for select to anon, authenticated using (not secret);

drop policy if exists "your friendships" on public.friendships;
create policy "your friendships" on public.friendships for select to authenticated
	using (auth.uid() in (requester, addressee));

drop policy if exists "public or yours" on public.lobbies;
create policy "public or yours" on public.lobbies for select to authenticated
	using (is_public or auth.uid() in (host, guest));

drop policy if exists "your messages" on public.messages;
create policy "your messages" on public.messages for select to authenticated
	using (auth.uid() in (sender, recipient));

drop policy if exists "your matches" on public.matches;
create policy "your matches" on public.matches for select to authenticated
	using (auth.uid() in (host, guest));

-- live updates for new messages and friend requests
do $$
begin
	if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'messages') then
		alter publication supabase_realtime add table public.messages;
	end if;
	if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'friendships') then
		alter publication supabase_realtime add table public.friendships;
	end if;
end $$;

-- ---------------------------------------------------------------------------
-- A profile for everyone who signs in, kept up to date with Discord
-- ---------------------------------------------------------------------------

create or replace function public._names_from(meta jsonb, email text)
returns text[] language sql immutable as $$
	select array[
		regexp_replace(lower(coalesce(meta->>'full_name', meta->>'user_name', meta->>'name',
			split_part(coalesce(email, 'player'), '@', 1))), '#0$', ''),
		coalesce(meta->'custom_claims'->>'global_name', meta->>'full_name', meta->>'name',
			split_part(coalesce(email, 'player'), '@', 1)),
		coalesce(meta->>'avatar_url', meta->>'picture')
	];
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
	n text[] := public._names_from(coalesce(new.raw_user_meta_data, '{}'::jsonb), new.email);
begin
	insert into public.profiles (id, username, display_name, avatar_url)
	values (new.id, left(n[1], 40), left(n[2], 40), n[3])
	on conflict (id) do nothing;
	return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
	for each row execute function public.handle_new_user();

create or replace function public.handle_user_updated()
returns trigger language plpgsql security definer set search_path = public as $$
declare
	n text[] := public._names_from(coalesce(new.raw_user_meta_data, '{}'::jsonb), new.email);
begin
	update public.profiles set username = left(n[1], 40), display_name = left(n[2], 40), avatar_url = n[3]
	where id = new.id;
	return new;
end $$;

drop trigger if exists on_auth_user_updated on auth.users;
create trigger on_auth_user_updated after update of raw_user_meta_data on auth.users
	for each row execute function public.handle_user_updated();

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function public._me() returns uuid language plpgsql stable as $$
begin
	if auth.uid() is null then
		raise exception 'not signed in';
	end if;
	return auth.uid();
end $$;

create or replace function public._are_friends(a uuid, b uuid) returns boolean language sql stable as $$
	select exists (
		select 1 from public.friendships
		where status = 'accepted' and ((requester = a and addressee = b) or (requester = b and addressee = a))
	);
$$;

create or replace function public._player(p uuid) returns jsonb language sql stable as $$
	select case when p is null then null else (
		select jsonb_build_object('id', id, 'username', username, 'display_name', display_name,
			'avatar_url', avatar_url, 'trophies', trophies)
		from public.profiles where id = p) end;
$$;

-- ---------------------------------------------------------------------------
-- Your profile, stats and coins
-- ---------------------------------------------------------------------------

drop function if exists public.me();
create function public.me() returns public.profiles
language sql security definer set search_path = public stable as $$
	select * from public.profiles where id = public._me();
$$;

-- Stats only ever go up: each number keeps the larger of what's stored and
-- what the game sends. The ones the server keeps itself are left alone.
drop function if exists public.save_stats(jsonb);
create function public.save_stats(p_stats jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
	cur jsonb;
	k text;
	v jsonb;
begin
	select stats into cur from public.profiles where id = public._me() for update;
	for k, v in select * from jsonb_each(coalesce(p_stats, '{}'::jsonb)) loop
		if k in ('trophies', 'mp_wins', 'mp_losses') or jsonb_typeof(v) <> 'number' then
			continue;
		end if;
		if coalesce((cur->>k)::bigint, 0) < (v::text)::bigint then
			cur := jsonb_set(cur, array[k], to_jsonb(least((v::text)::bigint, 2000000000)));
		end if;
	end loop;
	update public.profiles set stats = cur where id = auth.uid();
	return cur;
end $$;

-- Coins for a game against the house player. At most one payout a minute and
-- sixty a day, so it can't be farmed by calling it in a loop.
drop function if exists public.bot_reward(boolean);
create function public.bot_reward(p_won boolean) returns int
language plpgsql security definer set search_path = public as $$
declare
	p public.profiles;
	pay int := case when p_won then 15 else 5 end;
begin
	select * into p from public.profiles where id = public._me() for update;
	if p.bot_reward_day is distinct from current_date then
		p.bot_rewards_today := 0;
	end if;
	if (p.last_bot_reward is not null and p.last_bot_reward > now() - interval '60 seconds')
			or p.bot_rewards_today >= 60 then
		return p.coins;
	end if;
	update public.profiles set coins = coins + pay, last_bot_reward = now(), bot_reward_day = current_date,
		bot_rewards_today = p.bot_rewards_today + 1
	where id = p.id returning coins into p.coins;
	return p.coins;
end $$;

-- Spending at the bar.
drop function if exists public.spend_coins(int);
create function public.spend_coins(p_amount int) returns int
language plpgsql security definer set search_path = public as $$
declare
	left_over int;
begin
	if p_amount < 1 or p_amount > 100 then
		raise exception 'bad amount';
	end if;
	update public.profiles set coins = coins - p_amount
	where id = public._me() and coins >= p_amount returning coins into left_over;
	if left_over is null then
		raise exception 'not enough coins';
	end if;
	return left_over;
end $$;

drop function if exists public.buy_cue(text);
create function public.buy_cue(p_cue text) returns public.profiles
language plpgsql security definer set search_path = public as $$
declare
	c public.cue_prices;
	p public.profiles;
begin
	select * into c from public.cue_prices where id = p_cue;
	if c.id is null or c.secret then
		raise exception 'no such cue';
	end if;
	select * into p from public.profiles where id = public._me() for update;
	if p_cue = any (p.owned_cues) then
		return p;
	end if;
	if p.coins < c.price then
		raise exception 'not enough coins';
	end if;
	update public.profiles set coins = coins - c.price, owned_cues = array_append(owned_cues, p_cue)
	where id = p.id returning * into p;
	return p;
end $$;

drop function if exists public.redeem_code(text);
create function public.redeem_code(p_code text) returns text
language plpgsql security definer set search_path = public as $$
declare
	cue text;
begin
	select cue_id into cue from public.codes where code = upper(trim(p_code));
	if cue is null then
		return '';
	end if;
	update public.profiles set owned_cues = array_append(owned_cues, cue)
	where id = public._me() and not (cue = any (owned_cues));
	return cue;
end $$;

-- ---------------------------------------------------------------------------
-- Friends
-- ---------------------------------------------------------------------------

drop function if exists public.find_players(text);
create function public.find_players(p_query text) returns setof jsonb
language sql security definer set search_path = public stable as $$
	select public._player(id) from public.profiles
	where id <> public._me()
		and char_length(trim(p_query)) >= 2
		and (lower(username) like lower(trim(p_query)) || '%' or lower(display_name) like lower(trim(p_query)) || '%')
	order by (lower(username) = lower(trim(p_query))) desc, trophies desc
	limit 10;
$$;

-- Everyone you know: friends, requests to you, and requests you've sent.
drop function if exists public.friends();
create function public.friends() returns setof jsonb
language sql security definer set search_path = public stable as $$
	select public._player(case when f.requester = public._me() then f.addressee else f.requester end)
		|| jsonb_build_object('status', case
			when f.status = 'accepted' then 'friend'
			when f.addressee = public._me() then 'incoming'
			else 'outgoing' end,
		'unread', (select count(*) from public.messages m
			where m.recipient = public._me() and m.read_at is null
				and m.sender = case when f.requester = public._me() then f.addressee else f.requester end))
	from public.friendships f
	where public._me() in (f.requester, f.addressee);
$$;

drop function if exists public.send_friend_request(uuid);
create function public.send_friend_request(p_user uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
	me uuid := public._me();
	f public.friendships;
begin
	if p_user = me or not exists (select 1 from public.profiles where id = p_user) then
		raise exception 'no such player';
	end if;
	select * into f from public.friendships
	where (requester = me and addressee = p_user) or (requester = p_user and addressee = me);
	if f.requester is null then
		insert into public.friendships (requester, addressee) values (me, p_user);
		return 'sent';
	end if;
	if f.status = 'accepted' then
		return 'friends';
	end if;
	if f.requester = p_user then
		-- they'd already asked you: that's a yes
		update public.friendships set status = 'accepted' where requester = p_user and addressee = me;
		return 'friends';
	end if;
	return 'sent';
end $$;

drop function if exists public.respond_friend_request(uuid, boolean);
create function public.respond_friend_request(p_user uuid, p_accept boolean) returns text
language plpgsql security definer set search_path = public as $$
begin
	if p_accept then
		update public.friendships set status = 'accepted'
		where requester = p_user and addressee = public._me() and status = 'pending';
		return 'friends';
	end if;
	delete from public.friendships where requester = p_user and addressee = public._me() and status = 'pending';
	return 'declined';
end $$;

-- Unfriend, or take back a request you sent.
drop function if exists public.remove_friend(uuid);
create function public.remove_friend(p_user uuid) returns void
language sql security definer set search_path = public as $$
	delete from public.friendships
	where (requester = public._me() and addressee = p_user) or (requester = p_user and addressee = public._me());
$$;

-- ---------------------------------------------------------------------------
-- Messages
-- ---------------------------------------------------------------------------

drop function if exists public.send_message(uuid, text, text, uuid);
create function public.send_message(p_to uuid, p_body text, p_kind text default 'text', p_lobby uuid default null)
returns public.messages
language plpgsql security definer set search_path = public as $$
declare
	me uuid := public._me();
	m public.messages;
begin
	if not public._are_friends(me, p_to) then
		raise exception 'you can only message friends';
	end if;
	if (select count(*) from public.messages where sender = me and created_at > now() - interval '10 seconds') >= 10 then
		raise exception 'slow down';
	end if;
	insert into public.messages (sender, recipient, body, kind, lobby_id)
	values (me, p_to, left(trim(p_body), 500), coalesce(p_kind, 'text'), p_lobby)
	returning * into m;
	return m;
end $$;

drop function if exists public.conversation(uuid, int);
create function public.conversation(p_with uuid, p_limit int default 60) returns setof public.messages
language sql security definer set search_path = public stable as $$
	select * from (
		select * from public.messages
		where (sender = public._me() and recipient = p_with) or (sender = p_with and recipient = public._me())
		order by created_at desc
		limit least(greatest(p_limit, 1), 200)
	) t order by created_at;
$$;

drop function if exists public.mark_read(uuid);
create function public.mark_read(p_from uuid) returns void
language sql security definer set search_path = public as $$
	update public.messages set read_at = now()
	where recipient = public._me() and sender = p_from and read_at is null;
$$;

-- ---------------------------------------------------------------------------
-- Lobbies
-- ---------------------------------------------------------------------------

create or replace function public._lobby_json(l public.lobbies) returns jsonb language sql stable as $$
	select to_jsonb(l) || jsonb_build_object('host_player', public._player(l.host), 'guest_player', public._player(l.guest));
$$;

create or replace function public._new_code() returns text language plpgsql as $$
declare
	chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
	c text;
begin
	loop
		c := '';
		for i in 1..6 loop
			c := c || substr(chars, 1 + floor(random() * length(chars))::int, 1);
		end loop;
		exit when not exists (select 1 from public.lobbies where code = c and status <> 'closed');
	end loop;
	return c;
end $$;

-- You're only ever in one lobby: joining or making one leaves the last.
create or replace function public._leave_all(me uuid) returns void language plpgsql as $$
begin
	update public.lobbies set status = 'closed', updated_at = now() where host = me and status <> 'closed';
	update public.lobbies set guest = null, status = case when status = 'closed' then 'closed' else 'open' end,
		updated_at = now()
	where guest = me;
end $$;

drop function if exists public.create_lobby(text, boolean, jsonb);
create function public.create_lobby(p_name text, p_public boolean, p_rules jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
	me uuid := public._me();
	l public.lobbies;
begin
	perform public._leave_all(me);
	insert into public.lobbies (code, host, name, is_public, rules)
	values (public._new_code(), me, left(coalesce(nullif(trim(p_name), ''), 'Pool table'), 40), p_public,
		coalesce(p_rules, '{}'::jsonb))
	returning * into l;
	return public._lobby_json(l);
end $$;

drop function if exists public.update_lobby(uuid, text, boolean, jsonb);
create function public.update_lobby(p_id uuid, p_name text, p_public boolean, p_rules jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
	l public.lobbies;
begin
	update public.lobbies set name = left(coalesce(nullif(trim(p_name), ''), name), 40), is_public = p_public,
		rules = coalesce(p_rules, rules), updated_at = now()
	where id = p_id and host = public._me() and status in ('open', 'full')
	returning * into l;
	if l.id is null then
		raise exception 'not your lobby';
	end if;
	return public._lobby_json(l);
end $$;

create or replace function public._join(l public.lobbies) returns jsonb language plpgsql as $$
declare
	me uuid := auth.uid();
begin
	if l.id is null or l.status = 'closed' then
		raise exception 'That lobby has closed';
	end if;
	if l.host = me or l.guest = me then
		return public._lobby_json(l);
	end if;
	if l.guest is not null or l.status <> 'open' then
		raise exception 'That lobby is full';
	end if;
	perform public._leave_all(me);
	update public.lobbies set guest = me, status = 'full', updated_at = now()
	where id = l.id and guest is null returning * into l;
	if l.id is null then
		raise exception 'That lobby is full';
	end if;
	return public._lobby_json(l);
end $$;

drop function if exists public.join_lobby(uuid);
create function public.join_lobby(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
	l public.lobbies;
begin
	perform public._me();
	select * into l from public.lobbies where id = p_id for update;
	return public._join(l);
end $$;

drop function if exists public.join_lobby_code(text);
create function public.join_lobby_code(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
	l public.lobbies;
begin
	perform public._me();
	select * into l from public.lobbies where code = upper(trim(p_code)) and status <> 'closed'
	order by created_at desc limit 1 for update;
	if l.id is null then
		raise exception 'No lobby with that code';
	end if;
	return public._join(l);
end $$;

drop function if exists public.leave_lobby(uuid);
create function public.leave_lobby(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
	me uuid := public._me();
begin
	update public.lobbies set status = 'closed', updated_at = now() where id = p_id and host = me;
	update public.lobbies set guest = null, status = case when status = 'closed' then 'closed' else 'open' end,
		updated_at = now()
	where id = p_id and guest = me;
end $$;

-- The lobby, as the players in it see it. Also keeps it on the public list:
-- lobbies nobody has touched for a minute and a half drop off it.
drop function if exists public.lobby(uuid);
create function public.lobby(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
	l public.lobbies;
	me uuid := public._me();
begin
	update public.lobbies set updated_at = now() where id = p_id and me in (host, guest) and status <> 'closed'
	returning * into l;
	if l.id is null then
		select * into l from public.lobbies where id = p_id;
	end if;
	if l.id is null then
		return null;
	end if;
	return public._lobby_json(l);
end $$;

drop function if exists public.set_lobby_status(uuid, text);
create function public.set_lobby_status(p_id uuid, p_status text) returns void
language sql security definer set search_path = public as $$
	update public.lobbies set status = p_status, updated_at = now()
	where id = p_id and public._me() in (host, guest) and status <> 'closed'
		and p_status in ('full', 'playing');
$$;

drop function if exists public.public_lobbies();
create function public.public_lobbies() returns setof jsonb
language sql security definer set search_path = public stable as $$
	select public._lobby_json(l) from public.lobbies l
	where l.is_public and l.status = 'open' and l.updated_at > now() - interval '90 seconds'
		and l.host <> public._me()
	order by l.created_at desc
	limit 50;
$$;

-- ---------------------------------------------------------------------------
-- Matches: started by the host, paid out once both players agree who won
-- ---------------------------------------------------------------------------

drop function if exists public.start_match(uuid);
create function public.start_match(p_lobby uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
	l public.lobbies;
	m public.matches;
begin
	select * into l from public.lobbies where id = p_lobby and host = public._me() for update;
	if l.id is null or l.guest is null or l.status = 'closed' then
		raise exception 'Need two players to start';
	end if;
	insert into public.matches (lobby_id, host, guest, rules, seed)
	values (l.id, l.host, l.guest, l.rules, floor(random() * 2147483000)::int)
	returning * into m;
	update public.lobbies set status = 'playing', updated_at = now() where id = l.id;
	return to_jsonb(m);
end $$;

create or replace function public._award(m public.matches, w uuid) returns jsonb language plpgsql as $$
declare
	loser uuid := case when w = m.host then m.guest else m.host end;
begin
	update public.matches set winner = w, awarded = true, finished_at = now() where id = m.id and not awarded;
	if not found then
		return jsonb_build_object('awarded', false);
	end if;
	update public.profiles set trophies = trophies + 1, coins = coins + 50, mp_wins = mp_wins + 1 where id = w;
	update public.profiles set mp_losses = mp_losses + 1 where id = loser;
	update public.lobbies set status = case when guest is null then 'open' else 'full' end, updated_at = now()
	where id = m.lobby_id and status = 'playing';
	return jsonb_build_object('awarded', true, 'winner', w);
end $$;

-- Each player says who won. Saying the other player won (losing, or leaving
-- mid-game) settles it straight away. Saying you won yourself needs the
-- other player to agree, or, if they've vanished, a minute's wait and asking
-- again.
drop function if exists public.report_result(uuid, uuid);
create function public.report_result(p_match uuid, p_winner uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
	me uuid := public._me();
	m public.matches;
	other_report uuid;
begin
	select * into m from public.matches where id = p_match and me in (host, guest) for update;
	if m.id is null then
		raise exception 'not your match';
	end if;
	if m.awarded or m.finished_at is not null then
		return jsonb_build_object('awarded', m.awarded, 'winner', m.winner, 'done', true);
	end if;
	if p_winner not in (m.host, m.guest) then
		raise exception 'winner must be a player';
	end if;
	if me = m.host then
		update public.matches set host_report = p_winner, first_report_at = coalesce(first_report_at, now())
		where id = m.id returning * into m;
		other_report := m.guest_report;
	else
		update public.matches set guest_report = p_winner, first_report_at = coalesce(first_report_at, now())
		where id = m.id returning * into m;
		other_report := m.host_report;
	end if;
	if p_winner <> me then
		return public._award(m, p_winner);
	end if;
	if other_report is not null then
		if other_report = p_winner then
			return public._award(m, p_winner);
		end if;
		update public.matches set finished_at = now() where id = m.id;
		return jsonb_build_object('awarded', false, 'disputed', true);
	end if;
	if m.first_report_at < now() - interval '60 seconds' then
		return public._award(m, p_winner);
	end if;
	return jsonb_build_object('awarded', false, 'waiting', true);
end $$;

-- ---------------------------------------------------------------------------
-- Who may call what
-- ---------------------------------------------------------------------------

revoke execute on all functions in schema public from public, anon;
grant execute on function
	public.me(), public.save_stats(jsonb), public.bot_reward(boolean), public.spend_coins(int),
	public.buy_cue(text), public.redeem_code(text), public.find_players(text), public.friends(),
	public.send_friend_request(uuid), public.respond_friend_request(uuid, boolean), public.remove_friend(uuid),
	public.send_message(uuid, text, text, uuid), public.conversation(uuid, int), public.mark_read(uuid),
	public.create_lobby(text, boolean, jsonb), public.update_lobby(uuid, text, boolean, jsonb),
	public.join_lobby(uuid), public.join_lobby_code(text), public.leave_lobby(uuid), public.lobby(uuid),
	public.set_lobby_status(uuid, text), public.public_lobbies(), public.start_match(uuid),
	public.report_result(uuid, uuid)
to authenticated;

-- ---------------------------------------------------------------------------
-- Prices and codes (generated from scripts/pool_cues.gd)
-- ---------------------------------------------------------------------------
insert into public.cue_prices (id, price, secret) values
	('house', 0, false),
	('sovereign', 150, false),
	('carbon', 200, false),
	('hellfire', 400, false),
	('neon', 450, false),
	('galaxy', 600, false),
	('marble', 350, false),
	('damascus', 300, false),
	('dragon', 500, false),
	('molten', 550, false),
	('barber', 100, false),
	('viper', 250, false),
	('gilded', 400, false),
	('frost', 450, false),
	('bloodwood', 200, false),
	('tiger', 150, false),
	('serpent', 800, false),
	('clockwork', 700, false),
	('maiden', 650, false),
	('amethyst', 750, false),
	('colonnade', 600, false),
	('twisted', 250, false),
	('hologram', 900, false),
	('mainframe', 850, false),
	('hive', 500, false),
	('camo', 100, false),
	('checkered', 150, false),
	('zebra', 120, false),
	('leopard', 180, false),
	('runestone', 800, false),
	('aurora', 950, false),
	('abalone', 350, false),
	('sunset', 300, false),
	('eightbit', 250, false),
	('thunder', 700, false),
	('greatwave', 400, false),
	('sakura', 450, false),
	('katana', 1000, false),
	('wyvern', 1200, false),
	('plasma', 1100, false),
	('crown', 1500, false),
	('rocknroll', 400, false),
	('scrimshaw', 600, false),
	('dylan', 0, true)
on conflict (id) do update set price = excluded.price, secret = excluded.secret;

insert into public.codes (code, cue_id) values
	('JARVIS123', 'dylan')
on conflict (code) do update set cue_id = excluded.cue_id;
