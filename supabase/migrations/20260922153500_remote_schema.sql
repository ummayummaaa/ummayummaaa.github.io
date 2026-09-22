--
-- PostgreSQL database dump
--

\restrict IjIuYv04y12Uw7f8NB7Xn7Xdi8djRNiIPHZjqB9uuFGFfp7lKfPTzOR8tZIddeg

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: medquiz_account_is_active(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_account_is_active() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (
    select 1 from public.medquiz_profiles
    where user_id = (select auth.uid()) and account_status = 'active'
  );
$$;


--
-- Name: medquiz_admin_get_attempt_detail(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_admin_get_attempt_detail(target_id uuid, target_attempt_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  payload jsonb;
begin
  perform public.medquiz_admin_require_viewable_user(target_id);

  select jsonb_build_object(
    'attempt', to_jsonb(a),
    'questions', coalesce((
      select jsonb_agg(to_jsonb(q) order by q.position)
      from public.medquiz_attempt_questions q
      where q.attempt_id = a.id and q.user_id = target_id
    ), '[]'::jsonb)
  ) into payload
  from public.medquiz_attempts a
  where a.id = target_attempt_id and a.user_id = target_id;

  if payload is null then
    raise exception 'Попытка не найдена';
  end if;

  return payload;
end;
$$;


--
-- Name: FUNCTION medquiz_admin_get_attempt_detail(target_id uuid, target_attempt_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.medquiz_admin_get_attempt_detail(target_id uuid, target_attempt_id uuid) IS 'Read-only attempt snapshot. It never changes the viewed account or creates a student session.';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: medquiz_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medquiz_attempts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    test_id text NOT NULL,
    test_name text NOT NULL,
    mode text DEFAULT 'instant'::text NOT NULL,
    total_questions integer NOT NULL,
    correct_answers integer DEFAULT 0 NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    space_id text,
    subject_id text,
    attempt_kind text,
    status text,
    range_start integer,
    range_end integer,
    duration_seconds integer,
    finished_early boolean DEFAULT false NOT NULL,
    last_activity_at timestamp with time zone,
    CONSTRAINT medquiz_attempts_correct_answers_check CHECK ((correct_answers >= 0)),
    CONSTRAINT medquiz_attempts_duration_check CHECK (((duration_seconds IS NULL) OR (duration_seconds >= 0))),
    CONSTRAINT medquiz_attempts_kind_check CHECK ((attempt_kind = ANY (ARRAY['training'::text, 'general_exam'::text, 'block_exam'::text, 'legacy_exam'::text]))),
    CONSTRAINT medquiz_attempts_range_check CHECK ((((range_start IS NULL) AND (range_end IS NULL)) OR ((range_start > 0) AND (range_end >= range_start)))),
    CONSTRAINT medquiz_attempts_status_check CHECK ((status = ANY (ARRAY['active'::text, 'completed'::text, 'completed_early'::text]))),
    CONSTRAINT medquiz_attempts_total_questions_check CHECK ((total_questions > 0))
);


--
-- Name: medquiz_admin_get_attempts(uuid, text, text, boolean, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_admin_get_attempts(target_id uuid, target_space_id text DEFAULT NULL::text, target_subject_id text DEFAULT NULL::text, include_active boolean DEFAULT true, result_limit integer DEFAULT 100) RETURNS SETOF public.medquiz_attempts
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform public.medquiz_admin_require_viewable_user(target_id);

  return query
  select a.*
  from public.medquiz_attempts a
  where a.user_id = target_id
    and (target_space_id is null or a.space_id = target_space_id)
    and (target_subject_id is null or a.subject_id = target_subject_id)
    and (include_active or a.status <> 'active')
  order by coalesce(a.completed_at, a.last_activity_at, a.started_at) desc
  limit greatest(1, least(coalesce(result_limit, 100), 200));
end;
$$;


--
-- Name: medquiz_block_states; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medquiz_block_states (
    user_id uuid NOT NULL,
    subject_id text NOT NULL,
    block_start integer NOT NULL,
    block_end integer NOT NULL,
    has_checks boolean DEFAULT false NOT NULL,
    ever_passed boolean DEFAULT false NOT NULL,
    last_check_attempt_id uuid,
    last_percent numeric(5,2),
    best_percent numeric(5,2),
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT medquiz_block_states_best_percent_check CHECK (((best_percent >= (0)::numeric) AND (best_percent <= (100)::numeric))),
    CONSTRAINT medquiz_block_states_block_start_check CHECK ((block_start > 0)),
    CONSTRAINT medquiz_block_states_check CHECK ((block_end >= block_start)),
    CONSTRAINT medquiz_block_states_last_percent_check CHECK (((last_percent >= (0)::numeric) AND (last_percent <= (100)::numeric))),
    CONSTRAINT medquiz_block_states_passed_check CHECK (((NOT ever_passed) OR has_checks)),
    CONSTRAINT medquiz_block_states_range_check CHECK (((((block_end - block_start) + 1) >= 1) AND (((block_end - block_start) + 1) <= 50)))
);


--
-- Name: medquiz_admin_get_block_states(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_admin_get_block_states(target_id uuid, target_subject_id text DEFAULT NULL::text) RETURNS SETOF public.medquiz_block_states
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform public.medquiz_admin_require_viewable_user(target_id);

  return query
  select b.*
  from public.medquiz_block_states b
  where b.user_id = target_id
    and (target_subject_id is null or b.subject_id = target_subject_id)
  order by b.subject_id, b.block_start;
end;
$$;


--
-- Name: medquiz_admin_get_dashboard(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_admin_get_dashboard(target_id uuid, target_space_id text DEFAULT 'dentistry'::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  payload jsonb;
begin
  perform public.medquiz_admin_require_viewable_user(target_id);

  select jsonb_build_object(
    'answered_count', coalesce(sum(a.total_questions) filter (where a.completed_at is not null), 0),
    'correct_count', coalesce(sum(a.correct_answers) filter (where a.completed_at is not null), 0),
    'attempt_count', count(*) filter (where a.completed_at is not null),
    'favorite_count', (select count(*) from public.medquiz_question_stats s where s.user_id = target_id and s.space_id = target_space_id and s.favorite),
    'error_count', (select count(*) from public.medquiz_question_stats s where s.user_id = target_id and s.space_id = target_space_id and s.active_error),
    'last_attempt', (
      select to_jsonb(last_attempt)
      from (
        select id, test_name, subject_id, attempt_kind, status, total_questions,
               correct_answers, range_start, range_end, completed_at, started_at,
               last_activity_at
        from public.medquiz_attempts
        where user_id = target_id and space_id = target_space_id
        order by last_activity_at desc nulls last
        limit 1
      ) last_attempt
    ),
    'subject_progress', (
      select coalesce(jsonb_agg(to_jsonb(progress) order by progress.subject_id), '[]'::jsonb)
      from (
        select subject_id,
          count(*) filter (where source = 'block' and passed)::integer as passed_blocks,
          count(*) filter (where source = 'error')::integer as active_errors
        from (
          select b.subject_id, 'block'::text as source, b.ever_passed as passed
          from public.medquiz_block_states b
          where b.user_id = target_id
          union all
          select s.subject_id, 'error'::text, false
          from public.medquiz_question_stats s
          where s.user_id = target_id and s.space_id = target_space_id and s.active_error
        ) combined_rows
        where subject_id is not null
        group by subject_id
      ) progress
    )
  ) into payload
  from public.medquiz_attempts a
  where a.user_id = target_id and a.space_id = target_space_id;

  return coalesce(payload, jsonb_build_object(
    'answered_count', 0, 'correct_count', 0, 'attempt_count', 0,
    'favorite_count', 0, 'error_count', 0, 'last_attempt', null,
    'subject_progress', '[]'::jsonb
  ));
end;
$$;


--
-- Name: medquiz_question_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medquiz_question_stats (
    user_id uuid NOT NULL,
    test_id text NOT NULL,
    question_key text NOT NULL,
    mistake_count integer DEFAULT 0 NOT NULL,
    correct_streak integer DEFAULT 0 NOT NULL,
    favorite boolean DEFAULT false NOT NULL,
    last_answer_correct boolean,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    space_id text,
    subject_id text,
    active_error boolean DEFAULT false NOT NULL,
    exam_correct_streak smallint DEFAULT 0 NOT NULL,
    last_exam_answer_correct boolean,
    CONSTRAINT medquiz_question_stats_correct_streak_check CHECK ((correct_streak >= 0)),
    CONSTRAINT medquiz_question_stats_exam_streak_check CHECK (((exam_correct_streak >= 0) AND (exam_correct_streak <= 3))),
    CONSTRAINT medquiz_question_stats_mistake_count_check CHECK ((mistake_count >= 0))
);


--
-- Name: COLUMN medquiz_question_stats.correct_streak; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.medquiz_question_stats.correct_streak IS 'Legacy mixed-mode streak. Kept for compatibility; do not use for the new 3/3 rule.';


--
-- Name: COLUMN medquiz_question_stats.exam_correct_streak; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.medquiz_question_stats.exam_correct_streak IS 'Consecutive correct answers from submitted exam attempts only, from 0 to 3.';


--
-- Name: medquiz_admin_get_question_stats(uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_admin_get_question_stats(target_id uuid, target_space_id text DEFAULT NULL::text, target_subject_id text DEFAULT NULL::text, filter_kind text DEFAULT 'all'::text) RETURNS SETOF public.medquiz_question_stats
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform public.medquiz_admin_require_viewable_user(target_id);

  if filter_kind not in ('all', 'errors', 'favorites') then
    raise exception 'Недопустимый фильтр';
  end if;

  return query
  select s.*
  from public.medquiz_question_stats s
  where s.user_id = target_id
    and (target_space_id is null or s.space_id = target_space_id)
    and (target_subject_id is null or s.subject_id = target_subject_id)
    and (filter_kind <> 'errors' or s.active_error)
    and (filter_kind <> 'favorites' or s.favorite)
  order by s.updated_at desc;
end;
$$;


--
-- Name: medquiz_admin_get_user(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_admin_get_user(target_id uuid) RETURNS TABLE(user_id uuid, email text, display_name text, role text, account_status text, access_type text, access_expires_at timestamp with time zone, created_at timestamp with time zone, attempt_count bigint, last_active_at timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform public.medquiz_admin_require_viewable_user(target_id);

  return query
  select
    p.user_id,
    u.email::text,
    p.display_name,
    case when p.is_admin then 'admin' else 'student' end::text,
    p.account_status,
    p.access_type,
    p.access_expires_at,
    p.created_at,
    count(a.id)::bigint,
    max(coalesce(a.last_activity_at, a.completed_at, a.started_at))
  from public.medquiz_profiles p
  join auth.users u on u.id = p.user_id
  left join public.medquiz_attempts a on a.user_id = p.user_id
  where p.user_id = target_id
  group by p.user_id, u.email, p.display_name, p.is_admin, p.account_status,
           p.access_type, p.access_expires_at, p.created_at;
end;
$$;


--
-- Name: FUNCTION medquiz_admin_get_user(target_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.medquiz_admin_get_user(target_id uuid) IS 'Read-only whitelisted account metadata for the administrative account viewer.';


--
-- Name: medquiz_admin_list_users(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_admin_list_users(search_text text DEFAULT NULL::text, result_limit integer DEFAULT 100) RETURNS TABLE(user_id uuid, email text, display_name text, account_status text, access_type text, access_expires_at timestamp with time zone, trial_started_at timestamp with time zone, created_at timestamp with time zone, attempt_count bigint, last_active_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.medquiz_is_admin() then
    raise exception 'Доступ запрещён';
  end if;

  return query
  select
    p.user_id,
    u.email::text,
    p.display_name,
    p.account_status,
    p.access_type,
    p.access_expires_at,
    p.trial_started_at,
    p.created_at,
    count(a.id)::bigint,
    max(coalesce(a.completed_at, a.started_at))
  from public.medquiz_profiles p
  join auth.users u on u.id = p.user_id
  left join public.medquiz_attempts a on a.user_id = p.user_id
  where search_text is null
     or search_text = ''
     or u.email ilike '%' || search_text || '%'
     or coalesce(p.display_name, '') ilike '%' || search_text || '%'
  group by p.user_id, u.email, p.display_name, p.account_status, p.access_type,
           p.access_expires_at, p.trial_started_at, p.created_at
  order by p.created_at desc
  limit greatest(1, least(result_limit, 200));
end;
$$;


--
-- Name: medquiz_admin_list_users_v2(text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_admin_list_users_v2(search_text text DEFAULT NULL::text, page_number integer DEFAULT 1, page_size integer DEFAULT 25) RETURNS TABLE(user_id uuid, email text, display_name text, role text, account_status text, access_type text, access_expires_at timestamp with time zone, created_at timestamp with time zone, attempt_count bigint, last_active_at timestamp with time zone, total_count bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  safe_page integer := greatest(coalesce(page_number, 1), 1);
  safe_size integer := greatest(1, least(coalesce(page_size, 25), 100));
begin
  if not public.medquiz_is_admin() then
    raise exception 'Доступ запрещён';
  end if;

  return query
  with filtered as (
    select
      p.user_id,
      u.email::text as email,
      p.display_name,
      case when p.is_admin then 'admin' else 'student' end::text as role,
      p.account_status,
      p.access_type,
      p.access_expires_at,
      p.created_at,
      count(a.id)::bigint as attempt_count,
      max(coalesce(a.last_activity_at, a.completed_at, a.started_at)) as last_active_at
    from public.medquiz_profiles p
    join auth.users u on u.id = p.user_id
    left join public.medquiz_attempts a on a.user_id = p.user_id
    where coalesce(trim(search_text), '') = ''
       or u.email ilike '%' || trim(search_text) || '%'
       or coalesce(p.display_name, '') ilike '%' || trim(search_text) || '%'
    group by p.user_id, u.email, p.display_name, p.is_admin, p.account_status,
             p.access_type, p.access_expires_at, p.created_at
  )
  select f.*, count(*) over()::bigint
  from filtered f
  order by f.created_at desc
  limit safe_size
  offset (safe_page - 1) * safe_size;
end;
$$;


--
-- Name: medquiz_admin_log_password_reset(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_admin_log_password_reset(target_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.medquiz_is_admin() then
    raise exception 'Доступ запрещён';
  end if;

  if not exists (
    select 1
    from auth.users u
    join public.medquiz_profiles p on p.user_id = u.id
    where u.id = target_id
  ) then
    raise exception 'Пользователь не найден';
  end if;

  insert into public.medquiz_admin_actions (
    admin_id,
    action_type,
    target_user_id,
    details
  ) values (
    (select auth.uid()),
    'password_reset_email_sent',
    target_id,
    jsonb_build_object('delivery', 'email')
  );
end;
$$;


--
-- Name: medquiz_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medquiz_profiles (
    user_id uuid NOT NULL,
    display_name text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_admin boolean DEFAULT false NOT NULL,
    account_status text DEFAULT 'active'::text NOT NULL,
    access_type text DEFAULT 'free'::text NOT NULL,
    access_expires_at timestamp with time zone,
    trial_started_at timestamp with time zone,
    trial_ends_at timestamp with time zone,
    admin_grant_reason text,
    CONSTRAINT medquiz_profiles_access_type_check CHECK ((access_type = ANY (ARRAY['free'::text, 'trial'::text, 'subscription'::text, 'lifetime'::text, 'admin_grant'::text]))),
    CONSTRAINT medquiz_profiles_account_status_check CHECK ((account_status = ANY (ARRAY['active'::text, 'blocked'::text])))
);


--
-- Name: medquiz_admin_require_viewable_user(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_admin_require_viewable_user(target_id uuid) RETURNS public.medquiz_profiles
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  target_profile public.medquiz_profiles;
begin
  if not public.medquiz_is_admin() then
    raise exception 'Доступ запрещён';
  end if;

  select p.*
  into target_profile
  from public.medquiz_profiles p
  where p.user_id = target_id;

  if not found then
    raise exception 'Пользователь не найден';
  end if;

  return target_profile;
end;
$$;


--
-- Name: medquiz_admin_set_access(uuid, text, timestamp with time zone, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_admin_set_access(target_id uuid, new_access_type text, new_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone, grant_reason text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.medquiz_is_admin() then
    raise exception 'Доступ запрещён';
  end if;
  if new_access_type not in ('free', 'admin_grant', 'lifetime') then
    raise exception 'Недопустимый тип доступа';
  end if;

  update public.medquiz_profiles
  set access_type = new_access_type,
      access_expires_at = case when new_access_type = 'admin_grant' then new_expires_at else null end,
      admin_grant_reason = case when new_access_type = 'admin_grant' then nullif(trim(grant_reason), '') else null end,
      updated_at = now()
  where user_id = target_id;

  if not found then
    raise exception 'Пользователь не найден';
  end if;

  insert into public.medquiz_admin_actions (admin_id, action_type, target_user_id, details)
  values (
    (select auth.uid()),
    case when new_access_type = 'free' then 'access_revoked' else 'access_granted' end,
    target_id,
    jsonb_build_object('access_type', new_access_type, 'expires_at', new_expires_at, 'reason', grant_reason)
  );
end;
$$;


--
-- Name: medquiz_admin_set_blocked(uuid, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_admin_set_blocked(target_id uuid, blocked boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not public.medquiz_is_admin() then
    raise exception 'Доступ запрещён';
  end if;
  if target_id = (select auth.uid()) then
    raise exception 'Нельзя заблокировать собственный аккаунт';
  end if;

  update public.medquiz_profiles
  set account_status = case when blocked then 'blocked' else 'active' end,
      updated_at = now()
  where user_id = target_id;

  if not found then
    raise exception 'Пользователь не найден';
  end if;

  insert into public.medquiz_admin_actions (admin_id, action_type, target_user_id, details)
  values ((select auth.uid()), case when blocked then 'user_blocked' else 'user_unblocked' end, target_id, '{}'::jsonb);
end;
$$;


--
-- Name: medquiz_cancel_subscription_renewal(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_cancel_subscription_renewal(target_subscription_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  update public.medquiz_subscriptions
  set auto_renew = false,
      cancel_at_period_end = true,
      updated_at = now()
  where id = target_subscription_id
    and user_id = (select auth.uid())
    and status = 'active';

  if not found then
    raise exception 'Активная подписка не найдена';
  end if;
end;
$$;


--
-- Name: medquiz_configure_single_admin(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_configure_single_admin(admin_email text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  target_id uuid;
begin
  select id into target_id
  from auth.users
  where lower(email) = lower(trim(admin_email))
  limit 1;

  if target_id is null then
    raise exception 'Сначала зарегистрируйте аккаунт с этим email';
  end if;

  update public.medquiz_profiles
  set is_admin = (user_id = target_id),
      account_status = case when user_id = target_id then 'active' else account_status end,
      updated_at = now();

  return target_id;
end;
$$;


--
-- Name: medquiz_create_profile(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_create_profile() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  insert into public.medquiz_profiles (user_id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1)))
  on conflict (user_id) do nothing;
  return new;
end;
$$;


--
-- Name: medquiz_has_full_access(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_has_full_access() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (
    select 1
    from public.medquiz_profiles
    where user_id = (select auth.uid())
      and account_status = 'active'
      and (
        is_admin = true or
        access_type = 'lifetime' or
        (access_type in ('trial', 'subscription', 'admin_grant') and access_expires_at > now()) or
        (access_type = 'admin_grant' and access_expires_at is null)
      )
  );
$$;


--
-- Name: medquiz_is_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_is_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (
    select 1 from public.medquiz_profiles
    where user_id = (select auth.uid()) and is_admin = true
  );
$$;


--
-- Name: medquiz_log_report_resolution(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_log_report_resolution() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if new.status = 'resolved' and old.status is distinct from 'resolved' and new.resolved_by is not null then
    insert into public.medquiz_admin_actions (admin_id, action_type, target_user_id, target_report_id, details)
    values (new.resolved_by, 'report_resolved', new.reported_by, new.id, jsonb_build_object('test_name', new.test_name, 'question_number', new.question_number));
  end if;
  return new;
end;
$$;


--
-- Name: medquiz_log_test_activation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_log_test_activation() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if new.is_active = true and old.is_active is distinct from true then
    insert into public.medquiz_admin_actions (admin_id, action_type, target_test_id, details)
    values (new.uploaded_by, 'test_version_activated', new.test_id, jsonb_build_object('filename', new.original_filename, 'question_count', new.question_count));
  end if;
  return new;
end;
$$;


--
-- Name: medquiz_notify_resolved_report(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_notify_resolved_report() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  reporter_email text;
begin
  if new.status = 'resolved' and old.status is distinct from 'resolved' then
    insert into public.medquiz_notifications (
      user_id,
      kind,
      title,
      body,
      related_report_id
    ) values (
      new.reported_by,
      'report_resolved',
      'Ваш запрос решён',
      'Администратор обработал сообщение по вопросу из теста «' || coalesce(new.test_name, 'Без названия') || '».',
      new.id
    );

    select email into reporter_email
    from auth.users
    where id = new.reported_by;

    if reporter_email is not null then
      insert into public.medquiz_email_outbox (
        user_id,
        recipient_email,
        template,
        payload,
        related_report_id
      ) values (
        new.reported_by,
        reporter_email,
        'report_resolved',
        jsonb_build_object(
          'subject', 'Ваш запрос решён',
          'test_name', new.test_name,
          'question_number', new.question_number
        ),
        new.id
      );
    end if;
  end if;
  return new;
end;
$$;


--
-- Name: medquiz_start_trial(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_start_trial() RETURNS TABLE(access_type text, access_expires_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  caller uuid := (select auth.uid());
begin
  if caller is null then
    raise exception 'Требуется вход в аккаунт';
  end if;

  update public.medquiz_profiles
  set access_type = 'trial',
      trial_started_at = now(),
      trial_ends_at = now() + interval '7 days',
      access_expires_at = now() + interval '7 days',
      updated_at = now()
  where user_id = caller
    and account_status = 'active'
    and trial_started_at is null
    and access_type = 'free';

  if not found then
    raise exception 'Пробный период уже использован или полная версия уже активна';
  end if;

  return query
  select p.access_type, p.access_expires_at
  from public.medquiz_profiles p
  where p.user_id = caller;
end;
$$;


--
-- Name: medquiz_sync_subscription_access(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.medquiz_sync_subscription_access() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if new.status = 'active' then
    update public.medquiz_profiles
    set access_type = case when new.plan_type = 'lifetime' then 'lifetime' else 'subscription' end,
        access_expires_at = case when new.plan_type = 'lifetime' then null else new.ends_at end,
        updated_at = now()
    where user_id = new.user_id;
  elsif new.status in ('expired', 'refunded') then
    update public.medquiz_profiles
    set access_type = 'free',
        access_expires_at = null,
        updated_at = now()
    where user_id = new.user_id
      and access_type in ('subscription', 'lifetime');
  end if;
  return new;
end;
$$;


--
-- Name: medquiz_admin_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medquiz_admin_actions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    admin_id uuid NOT NULL,
    action_type text NOT NULL,
    target_user_id uuid,
    target_report_id uuid,
    target_test_id text,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: medquiz_answer_library; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medquiz_answer_library (
    question_key text NOT NULL,
    question_text text NOT NULL,
    options jsonb NOT NULL,
    correct_index integer NOT NULL,
    confirmed_by uuid,
    confirmed_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT medquiz_answer_library_correct_index_check CHECK ((correct_index >= 0))
);


--
-- Name: medquiz_answers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medquiz_answers (
    id bigint NOT NULL,
    attempt_id uuid NOT NULL,
    user_id uuid NOT NULL,
    test_id text NOT NULL,
    question_key text NOT NULL,
    selected_index integer,
    correct_index integer NOT NULL,
    is_correct boolean NOT NULL,
    answered_at timestamp with time zone DEFAULT now() NOT NULL,
    space_id text,
    subject_id text
);


--
-- Name: medquiz_answers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.medquiz_answers ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.medquiz_answers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: medquiz_attempt_questions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medquiz_attempt_questions (
    attempt_id uuid NOT NULL,
    "position" integer NOT NULL,
    user_id uuid NOT NULL,
    space_id text NOT NULL,
    subject_id text,
    question_key text NOT NULL,
    question_number text,
    question_text text NOT NULL,
    options jsonb NOT NULL,
    selected_index integer,
    correct_index integer NOT NULL,
    is_correct boolean NOT NULL,
    explanation text,
    favorite_at_completion boolean DEFAULT false NOT NULL,
    answered_at timestamp with time zone,
    CONSTRAINT medquiz_attempt_questions_correct_index_check CHECK ((correct_index >= 0)),
    CONSTRAINT medquiz_attempt_questions_options_check CHECK (((jsonb_typeof(options) = 'array'::text) AND (jsonb_array_length(options) >= 2))),
    CONSTRAINT medquiz_attempt_questions_position_check CHECK (("position" > 0))
);


--
-- Name: TABLE medquiz_attempt_questions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.medquiz_attempt_questions IS 'Immutable question-and-answer snapshot used to render historical attempts.';


--
-- Name: medquiz_email_outbox; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medquiz_email_outbox (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    recipient_email text NOT NULL,
    template text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    related_report_id uuid,
    sent_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: medquiz_notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medquiz_notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    kind text DEFAULT 'report_resolved'::text NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    related_report_id uuid,
    read_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: medquiz_payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medquiz_payments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    subscription_id uuid,
    amount_minor integer NOT NULL,
    currency text DEFAULT 'EUR'::text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    provider text,
    provider_payment_id text,
    paid_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT medquiz_payments_amount_minor_check CHECK ((amount_minor >= 0)),
    CONSTRAINT medquiz_payments_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'paid'::text, 'failed'::text, 'refunded'::text])))
);


--
-- Name: medquiz_question_reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medquiz_question_reports (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    question_key text NOT NULL,
    question_text text NOT NULL,
    options jsonb NOT NULL,
    detected_correct_index integer,
    user_selected_index integer,
    test_id text,
    test_name text,
    reported_by uuid NOT NULL,
    comment text,
    status text DEFAULT 'pending'::text NOT NULL,
    resolved_correct_index integer,
    resolved_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    resolved_at timestamp with time zone,
    question_number text,
    reason text,
    attachment_path text,
    attachment_name text,
    attachment_type text,
    CONSTRAINT medquiz_question_reports_reason_check CHECK (((reason IS NULL) OR (reason = ANY (ARRAY['typo'::text, 'options_error'::text, 'outdated'::text, 'exam_answer_changed'::text, 'other'::text])))),
    CONSTRAINT medquiz_question_reports_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'resolved'::text])))
);


--
-- Name: medquiz_spaces; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medquiz_spaces (
    id text NOT NULL,
    name_ru text NOT NULL,
    sort_order integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT medquiz_spaces_id_check CHECK ((id = ANY (ARRAY['dentistry'::text, 'medicine'::text, 'custom'::text])))
);


--
-- Name: medquiz_subjects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medquiz_subjects (
    id text NOT NULL,
    space_id text NOT NULL,
    slug text NOT NULL,
    name text NOT NULL,
    question_count integer DEFAULT 0 NOT NULL,
    owner_user_id uuid,
    legacy_test_id text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT medquiz_subjects_owner_space_check CHECK ((((space_id = 'custom'::text) AND (owner_user_id IS NOT NULL)) OR ((space_id <> 'custom'::text) AND (owner_user_id IS NULL)))),
    CONSTRAINT medquiz_subjects_question_count_check CHECK ((question_count >= 0))
);


--
-- Name: medquiz_subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medquiz_subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    plan_type text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    auto_renew boolean DEFAULT true NOT NULL,
    cancel_at_period_end boolean DEFAULT false NOT NULL,
    provider text,
    provider_subscription_id text,
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT medquiz_subscriptions_plan_type_check CHECK ((plan_type = ANY (ARRAY['monthly'::text, 'yearly'::text, 'lifetime'::text]))),
    CONSTRAINT medquiz_subscriptions_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'active'::text, 'past_due'::text, 'canceled'::text, 'expired'::text, 'refunded'::text])))
);


--
-- Name: medquiz_test_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medquiz_test_versions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    test_id text NOT NULL,
    test_name text NOT NULL,
    original_filename text NOT NULL,
    source_path text NOT NULL,
    data_path text NOT NULL,
    question_count integer NOT NULL,
    uploaded_by uuid NOT NULL,
    is_active boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT medquiz_test_versions_question_count_check CHECK ((question_count > 0))
);


--
-- Name: medquiz_admin_actions medquiz_admin_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_admin_actions
    ADD CONSTRAINT medquiz_admin_actions_pkey PRIMARY KEY (id);


--
-- Name: medquiz_answer_library medquiz_answer_library_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_answer_library
    ADD CONSTRAINT medquiz_answer_library_pkey PRIMARY KEY (question_key);


--
-- Name: medquiz_answers medquiz_answers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_answers
    ADD CONSTRAINT medquiz_answers_pkey PRIMARY KEY (id);


--
-- Name: medquiz_attempt_questions medquiz_attempt_questions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_attempt_questions
    ADD CONSTRAINT medquiz_attempt_questions_pkey PRIMARY KEY (attempt_id, "position");


--
-- Name: medquiz_attempts medquiz_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_attempts
    ADD CONSTRAINT medquiz_attempts_pkey PRIMARY KEY (id);


--
-- Name: medquiz_block_states medquiz_block_states_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_block_states
    ADD CONSTRAINT medquiz_block_states_pkey PRIMARY KEY (user_id, subject_id, block_start);


--
-- Name: medquiz_email_outbox medquiz_email_outbox_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_email_outbox
    ADD CONSTRAINT medquiz_email_outbox_pkey PRIMARY KEY (id);


--
-- Name: medquiz_notifications medquiz_notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_notifications
    ADD CONSTRAINT medquiz_notifications_pkey PRIMARY KEY (id);


--
-- Name: medquiz_payments medquiz_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_payments
    ADD CONSTRAINT medquiz_payments_pkey PRIMARY KEY (id);


--
-- Name: medquiz_payments medquiz_payments_provider_payment_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_payments
    ADD CONSTRAINT medquiz_payments_provider_payment_id_key UNIQUE (provider_payment_id);


--
-- Name: medquiz_profiles medquiz_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_profiles
    ADD CONSTRAINT medquiz_profiles_pkey PRIMARY KEY (user_id);


--
-- Name: medquiz_question_reports medquiz_question_reports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_question_reports
    ADD CONSTRAINT medquiz_question_reports_pkey PRIMARY KEY (id);


--
-- Name: medquiz_question_stats medquiz_question_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_question_stats
    ADD CONSTRAINT medquiz_question_stats_pkey PRIMARY KEY (user_id, test_id, question_key);


--
-- Name: medquiz_spaces medquiz_spaces_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_spaces
    ADD CONSTRAINT medquiz_spaces_pkey PRIMARY KEY (id);


--
-- Name: medquiz_subjects medquiz_subjects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_subjects
    ADD CONSTRAINT medquiz_subjects_pkey PRIMARY KEY (id);


--
-- Name: medquiz_subscriptions medquiz_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_subscriptions
    ADD CONSTRAINT medquiz_subscriptions_pkey PRIMARY KEY (id);


--
-- Name: medquiz_subscriptions medquiz_subscriptions_provider_subscription_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_subscriptions
    ADD CONSTRAINT medquiz_subscriptions_provider_subscription_id_key UNIQUE (provider_subscription_id);


--
-- Name: medquiz_test_versions medquiz_test_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_test_versions
    ADD CONSTRAINT medquiz_test_versions_pkey PRIMARY KEY (id);


--
-- Name: medquiz_admin_actions_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medquiz_admin_actions_created_idx ON public.medquiz_admin_actions USING btree (created_at DESC);


--
-- Name: medquiz_answers_user_space_test_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medquiz_answers_user_space_test_idx ON public.medquiz_answers USING btree (user_id, space_id, test_id);


--
-- Name: medquiz_answers_user_test_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medquiz_answers_user_test_idx ON public.medquiz_answers USING btree (user_id, test_id);


--
-- Name: medquiz_attempt_questions_user_question_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medquiz_attempt_questions_user_question_idx ON public.medquiz_attempt_questions USING btree (user_id, space_id, subject_id, question_key);


--
-- Name: medquiz_attempts_active_subject_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medquiz_attempts_active_subject_idx ON public.medquiz_attempts USING btree (user_id, subject_id, last_activity_at DESC) WHERE ((status = 'active'::text) AND (subject_id IS NOT NULL));


--
-- Name: medquiz_attempts_user_completed_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medquiz_attempts_user_completed_idx ON public.medquiz_attempts USING btree (user_id, completed_at DESC);


--
-- Name: medquiz_attempts_user_space_activity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medquiz_attempts_user_space_activity_idx ON public.medquiz_attempts USING btree (user_id, space_id, last_activity_at DESC);


--
-- Name: medquiz_attempts_user_subject_activity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medquiz_attempts_user_subject_activity_idx ON public.medquiz_attempts USING btree (user_id, subject_id, last_activity_at DESC);


--
-- Name: medquiz_block_states_subject_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medquiz_block_states_subject_idx ON public.medquiz_block_states USING btree (user_id, subject_id, block_start);


--
-- Name: medquiz_notifications_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medquiz_notifications_user_idx ON public.medquiz_notifications USING btree (user_id, created_at DESC);


--
-- Name: medquiz_payments_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medquiz_payments_user_idx ON public.medquiz_payments USING btree (user_id, created_at DESC);


--
-- Name: medquiz_question_reports_reporter_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medquiz_question_reports_reporter_idx ON public.medquiz_question_reports USING btree (reported_by, created_at DESC);


--
-- Name: medquiz_question_reports_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medquiz_question_reports_status_idx ON public.medquiz_question_reports USING btree (status, created_at DESC);


--
-- Name: medquiz_question_stats_active_errors_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medquiz_question_stats_active_errors_idx ON public.medquiz_question_stats USING btree (user_id, space_id, subject_id, updated_at DESC) WHERE (active_error = true);


--
-- Name: medquiz_question_stats_favorites_v2_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medquiz_question_stats_favorites_v2_idx ON public.medquiz_question_stats USING btree (user_id, space_id, subject_id, updated_at DESC) WHERE (favorite = true);


--
-- Name: medquiz_question_stats_user_mistakes_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medquiz_question_stats_user_mistakes_idx ON public.medquiz_question_stats USING btree (user_id, mistake_count DESC);


--
-- Name: medquiz_subjects_builtin_slug_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX medquiz_subjects_builtin_slug_idx ON public.medquiz_subjects USING btree (space_id, slug) WHERE (owner_user_id IS NULL);


--
-- Name: medquiz_subjects_custom_slug_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX medquiz_subjects_custom_slug_idx ON public.medquiz_subjects USING btree (owner_user_id, slug) WHERE (owner_user_id IS NOT NULL);


--
-- Name: medquiz_subjects_space_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medquiz_subjects_space_idx ON public.medquiz_subjects USING btree (space_id, name);


--
-- Name: medquiz_subscriptions_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medquiz_subscriptions_user_idx ON public.medquiz_subscriptions USING btree (user_id, created_at DESC);


--
-- Name: medquiz_test_versions_one_active_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX medquiz_test_versions_one_active_idx ON public.medquiz_test_versions USING btree (test_id) WHERE (is_active = true);


--
-- Name: medquiz_test_versions_test_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medquiz_test_versions_test_idx ON public.medquiz_test_versions USING btree (test_id, created_at DESC);


--
-- Name: medquiz_question_reports medquiz_log_report_resolution_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER medquiz_log_report_resolution_trigger AFTER UPDATE OF status ON public.medquiz_question_reports FOR EACH ROW EXECUTE FUNCTION public.medquiz_log_report_resolution();


--
-- Name: medquiz_test_versions medquiz_log_test_activation_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER medquiz_log_test_activation_trigger AFTER UPDATE OF is_active ON public.medquiz_test_versions FOR EACH ROW EXECUTE FUNCTION public.medquiz_log_test_activation();


--
-- Name: medquiz_question_reports medquiz_on_report_resolved; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER medquiz_on_report_resolved AFTER UPDATE OF status ON public.medquiz_question_reports FOR EACH ROW EXECUTE FUNCTION public.medquiz_notify_resolved_report();


--
-- Name: medquiz_subscriptions medquiz_sync_subscription_access_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER medquiz_sync_subscription_access_trigger AFTER INSERT OR UPDATE ON public.medquiz_subscriptions FOR EACH ROW EXECUTE FUNCTION public.medquiz_sync_subscription_access();


--
-- Name: medquiz_admin_actions medquiz_admin_actions_admin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_admin_actions
    ADD CONSTRAINT medquiz_admin_actions_admin_id_fkey FOREIGN KEY (admin_id) REFERENCES auth.users(id) ON DELETE RESTRICT;


--
-- Name: medquiz_admin_actions medquiz_admin_actions_target_report_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_admin_actions
    ADD CONSTRAINT medquiz_admin_actions_target_report_id_fkey FOREIGN KEY (target_report_id) REFERENCES public.medquiz_question_reports(id) ON DELETE SET NULL;


--
-- Name: medquiz_admin_actions medquiz_admin_actions_target_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_admin_actions
    ADD CONSTRAINT medquiz_admin_actions_target_user_id_fkey FOREIGN KEY (target_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: medquiz_answer_library medquiz_answer_library_confirmed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_answer_library
    ADD CONSTRAINT medquiz_answer_library_confirmed_by_fkey FOREIGN KEY (confirmed_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: medquiz_answers medquiz_answers_attempt_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_answers
    ADD CONSTRAINT medquiz_answers_attempt_id_fkey FOREIGN KEY (attempt_id) REFERENCES public.medquiz_attempts(id) ON DELETE CASCADE;


--
-- Name: medquiz_answers medquiz_answers_space_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_answers
    ADD CONSTRAINT medquiz_answers_space_id_fkey FOREIGN KEY (space_id) REFERENCES public.medquiz_spaces(id) ON UPDATE CASCADE;


--
-- Name: medquiz_answers medquiz_answers_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_answers
    ADD CONSTRAINT medquiz_answers_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.medquiz_subjects(id) ON UPDATE CASCADE;


--
-- Name: medquiz_answers medquiz_answers_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_answers
    ADD CONSTRAINT medquiz_answers_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: medquiz_attempt_questions medquiz_attempt_questions_attempt_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_attempt_questions
    ADD CONSTRAINT medquiz_attempt_questions_attempt_id_fkey FOREIGN KEY (attempt_id) REFERENCES public.medquiz_attempts(id) ON DELETE CASCADE;


--
-- Name: medquiz_attempt_questions medquiz_attempt_questions_space_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_attempt_questions
    ADD CONSTRAINT medquiz_attempt_questions_space_id_fkey FOREIGN KEY (space_id) REFERENCES public.medquiz_spaces(id) ON UPDATE CASCADE;


--
-- Name: medquiz_attempt_questions medquiz_attempt_questions_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_attempt_questions
    ADD CONSTRAINT medquiz_attempt_questions_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.medquiz_subjects(id) ON UPDATE CASCADE;


--
-- Name: medquiz_attempt_questions medquiz_attempt_questions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_attempt_questions
    ADD CONSTRAINT medquiz_attempt_questions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: medquiz_attempts medquiz_attempts_space_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_attempts
    ADD CONSTRAINT medquiz_attempts_space_id_fkey FOREIGN KEY (space_id) REFERENCES public.medquiz_spaces(id) ON UPDATE CASCADE;


--
-- Name: medquiz_attempts medquiz_attempts_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_attempts
    ADD CONSTRAINT medquiz_attempts_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.medquiz_subjects(id) ON UPDATE CASCADE;


--
-- Name: medquiz_attempts medquiz_attempts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_attempts
    ADD CONSTRAINT medquiz_attempts_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: medquiz_block_states medquiz_block_states_last_check_attempt_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_block_states
    ADD CONSTRAINT medquiz_block_states_last_check_attempt_id_fkey FOREIGN KEY (last_check_attempt_id) REFERENCES public.medquiz_attempts(id) ON DELETE SET NULL;


--
-- Name: medquiz_block_states medquiz_block_states_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_block_states
    ADD CONSTRAINT medquiz_block_states_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.medquiz_subjects(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: medquiz_block_states medquiz_block_states_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_block_states
    ADD CONSTRAINT medquiz_block_states_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: medquiz_email_outbox medquiz_email_outbox_related_report_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_email_outbox
    ADD CONSTRAINT medquiz_email_outbox_related_report_id_fkey FOREIGN KEY (related_report_id) REFERENCES public.medquiz_question_reports(id) ON DELETE SET NULL;


--
-- Name: medquiz_email_outbox medquiz_email_outbox_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_email_outbox
    ADD CONSTRAINT medquiz_email_outbox_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: medquiz_notifications medquiz_notifications_related_report_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_notifications
    ADD CONSTRAINT medquiz_notifications_related_report_id_fkey FOREIGN KEY (related_report_id) REFERENCES public.medquiz_question_reports(id) ON DELETE SET NULL;


--
-- Name: medquiz_notifications medquiz_notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_notifications
    ADD CONSTRAINT medquiz_notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: medquiz_payments medquiz_payments_subscription_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_payments
    ADD CONSTRAINT medquiz_payments_subscription_id_fkey FOREIGN KEY (subscription_id) REFERENCES public.medquiz_subscriptions(id) ON DELETE SET NULL;


--
-- Name: medquiz_payments medquiz_payments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_payments
    ADD CONSTRAINT medquiz_payments_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: medquiz_profiles medquiz_profiles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_profiles
    ADD CONSTRAINT medquiz_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: medquiz_question_reports medquiz_question_reports_reported_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_question_reports
    ADD CONSTRAINT medquiz_question_reports_reported_by_fkey FOREIGN KEY (reported_by) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: medquiz_question_reports medquiz_question_reports_resolved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_question_reports
    ADD CONSTRAINT medquiz_question_reports_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: medquiz_question_stats medquiz_question_stats_space_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_question_stats
    ADD CONSTRAINT medquiz_question_stats_space_id_fkey FOREIGN KEY (space_id) REFERENCES public.medquiz_spaces(id) ON UPDATE CASCADE;


--
-- Name: medquiz_question_stats medquiz_question_stats_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_question_stats
    ADD CONSTRAINT medquiz_question_stats_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.medquiz_subjects(id) ON UPDATE CASCADE;


--
-- Name: medquiz_question_stats medquiz_question_stats_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_question_stats
    ADD CONSTRAINT medquiz_question_stats_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: medquiz_subjects medquiz_subjects_owner_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_subjects
    ADD CONSTRAINT medquiz_subjects_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: medquiz_subjects medquiz_subjects_space_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_subjects
    ADD CONSTRAINT medquiz_subjects_space_id_fkey FOREIGN KEY (space_id) REFERENCES public.medquiz_spaces(id) ON UPDATE CASCADE;


--
-- Name: medquiz_subscriptions medquiz_subscriptions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_subscriptions
    ADD CONSTRAINT medquiz_subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: medquiz_test_versions medquiz_test_versions_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medquiz_test_versions
    ADD CONSTRAINT medquiz_test_versions_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES auth.users(id) ON DELETE RESTRICT;


--
-- Name: medquiz_admin_actions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.medquiz_admin_actions ENABLE ROW LEVEL SECURITY;

--
-- Name: medquiz_admin_actions medquiz_admin_actions_admin_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_admin_actions_admin_read ON public.medquiz_admin_actions FOR SELECT USING (( SELECT public.medquiz_is_admin() AS medquiz_is_admin));


--
-- Name: medquiz_answer_library; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.medquiz_answer_library ENABLE ROW LEVEL SECURITY;

--
-- Name: medquiz_answer_library medquiz_answer_library_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_answer_library_admin_write ON public.medquiz_answer_library USING (( SELECT public.medquiz_is_admin() AS medquiz_is_admin)) WITH CHECK (( SELECT public.medquiz_is_admin() AS medquiz_is_admin));


--
-- Name: medquiz_answer_library medquiz_answer_library_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_answer_library_read ON public.medquiz_answer_library FOR SELECT USING (true);


--
-- Name: medquiz_answers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.medquiz_answers ENABLE ROW LEVEL SECURITY;

--
-- Name: medquiz_answers medquiz_answers_own_rows; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_answers_own_rows ON public.medquiz_answers USING (((( SELECT auth.uid() AS uid) = user_id) AND ( SELECT public.medquiz_has_full_access() AS medquiz_has_full_access))) WITH CHECK (((( SELECT auth.uid() AS uid) = user_id) AND ( SELECT public.medquiz_has_full_access() AS medquiz_has_full_access)));


--
-- Name: medquiz_attempt_questions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.medquiz_attempt_questions ENABLE ROW LEVEL SECURITY;

--
-- Name: medquiz_attempt_questions medquiz_attempt_questions_own_rows; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_attempt_questions_own_rows ON public.medquiz_attempt_questions USING ((( SELECT auth.uid() AS uid) = user_id)) WITH CHECK (((( SELECT auth.uid() AS uid) = user_id) AND (EXISTS ( SELECT 1
   FROM public.medquiz_attempts a
  WHERE ((a.id = medquiz_attempt_questions.attempt_id) AND (a.user_id = ( SELECT auth.uid() AS uid)))))));


--
-- Name: medquiz_attempts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.medquiz_attempts ENABLE ROW LEVEL SECURITY;

--
-- Name: medquiz_attempts medquiz_attempts_own_rows; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_attempts_own_rows ON public.medquiz_attempts USING (((( SELECT auth.uid() AS uid) = user_id) AND ( SELECT public.medquiz_has_full_access() AS medquiz_has_full_access))) WITH CHECK (((( SELECT auth.uid() AS uid) = user_id) AND ( SELECT public.medquiz_has_full_access() AS medquiz_has_full_access)));


--
-- Name: medquiz_block_states; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.medquiz_block_states ENABLE ROW LEVEL SECURITY;

--
-- Name: medquiz_block_states medquiz_block_states_own_rows; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_block_states_own_rows ON public.medquiz_block_states USING ((( SELECT auth.uid() AS uid) = user_id)) WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));


--
-- Name: medquiz_email_outbox; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.medquiz_email_outbox ENABLE ROW LEVEL SECURITY;

--
-- Name: medquiz_notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.medquiz_notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: medquiz_notifications medquiz_notifications_own_mark_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_notifications_own_mark_read ON public.medquiz_notifications FOR UPDATE USING ((( SELECT auth.uid() AS uid) = user_id)) WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));


--
-- Name: medquiz_notifications medquiz_notifications_own_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_notifications_own_read ON public.medquiz_notifications FOR SELECT USING ((( SELECT auth.uid() AS uid) = user_id));


--
-- Name: medquiz_payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.medquiz_payments ENABLE ROW LEVEL SECURITY;

--
-- Name: medquiz_payments medquiz_payments_own_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_payments_own_read ON public.medquiz_payments FOR SELECT USING (((( SELECT auth.uid() AS uid) = user_id) OR ( SELECT public.medquiz_is_admin() AS medquiz_is_admin)));


--
-- Name: medquiz_profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.medquiz_profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: medquiz_profiles medquiz_profiles_admin_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_profiles_admin_read ON public.medquiz_profiles FOR SELECT USING (( SELECT public.medquiz_is_admin() AS medquiz_is_admin));


--
-- Name: medquiz_profiles medquiz_profiles_own_rows; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_profiles_own_rows ON public.medquiz_profiles USING ((( SELECT auth.uid() AS uid) = user_id)) WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));


--
-- Name: medquiz_question_reports; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.medquiz_question_reports ENABLE ROW LEVEL SECURITY;

--
-- Name: medquiz_question_reports medquiz_question_reports_admin_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_question_reports_admin_update ON public.medquiz_question_reports FOR UPDATE USING (( SELECT public.medquiz_is_admin() AS medquiz_is_admin)) WITH CHECK (( SELECT public.medquiz_is_admin() AS medquiz_is_admin));


--
-- Name: medquiz_question_reports medquiz_question_reports_own_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_question_reports_own_read ON public.medquiz_question_reports FOR SELECT USING (((( SELECT auth.uid() AS uid) = reported_by) OR ( SELECT public.medquiz_is_admin() AS medquiz_is_admin)));


--
-- Name: medquiz_question_reports medquiz_question_reports_submit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_question_reports_submit ON public.medquiz_question_reports FOR INSERT WITH CHECK (((( SELECT auth.uid() AS uid) = reported_by) AND ( SELECT public.medquiz_account_is_active() AS medquiz_account_is_active)));


--
-- Name: medquiz_question_stats; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.medquiz_question_stats ENABLE ROW LEVEL SECURITY;

--
-- Name: medquiz_question_stats medquiz_question_stats_own_rows; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_question_stats_own_rows ON public.medquiz_question_stats USING (((( SELECT auth.uid() AS uid) = user_id) AND ( SELECT public.medquiz_has_full_access() AS medquiz_has_full_access))) WITH CHECK (((( SELECT auth.uid() AS uid) = user_id) AND ( SELECT public.medquiz_has_full_access() AS medquiz_has_full_access)));


--
-- Name: medquiz_spaces; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.medquiz_spaces ENABLE ROW LEVEL SECURITY;

--
-- Name: medquiz_spaces medquiz_spaces_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_spaces_read ON public.medquiz_spaces FOR SELECT USING (true);


--
-- Name: medquiz_subjects; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.medquiz_subjects ENABLE ROW LEVEL SECURITY;

--
-- Name: medquiz_subjects medquiz_subjects_custom_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_subjects_custom_delete ON public.medquiz_subjects FOR DELETE USING ((owner_user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: medquiz_subjects medquiz_subjects_custom_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_subjects_custom_insert ON public.medquiz_subjects FOR INSERT WITH CHECK (((space_id = 'custom'::text) AND (owner_user_id = ( SELECT auth.uid() AS uid))));


--
-- Name: medquiz_subjects medquiz_subjects_custom_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_subjects_custom_update ON public.medquiz_subjects FOR UPDATE USING ((owner_user_id = ( SELECT auth.uid() AS uid))) WITH CHECK (((space_id = 'custom'::text) AND (owner_user_id = ( SELECT auth.uid() AS uid))));


--
-- Name: medquiz_subjects medquiz_subjects_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_subjects_read ON public.medquiz_subjects FOR SELECT USING (((owner_user_id IS NULL) OR (owner_user_id = ( SELECT auth.uid() AS uid))));


--
-- Name: medquiz_subscriptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.medquiz_subscriptions ENABLE ROW LEVEL SECURITY;

--
-- Name: medquiz_subscriptions medquiz_subscriptions_own_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_subscriptions_own_read ON public.medquiz_subscriptions FOR SELECT USING (((( SELECT auth.uid() AS uid) = user_id) OR ( SELECT public.medquiz_is_admin() AS medquiz_is_admin)));


--
-- Name: medquiz_test_versions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.medquiz_test_versions ENABLE ROW LEVEL SECURITY;

--
-- Name: medquiz_test_versions medquiz_test_versions_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_test_versions_admin_write ON public.medquiz_test_versions USING (( SELECT public.medquiz_is_admin() AS medquiz_is_admin)) WITH CHECK (( SELECT public.medquiz_is_admin() AS medquiz_is_admin));


--
-- Name: medquiz_test_versions medquiz_test_versions_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medquiz_test_versions_read ON public.medquiz_test_versions FOR SELECT USING (true);


--
-- PostgreSQL database dump complete
--

\unrestrict IjIuYv04y12Uw7f8NB7Xn7Xdi8djRNiIPHZjqB9uuFGFfp7lKfPTzOR8tZIddeg
