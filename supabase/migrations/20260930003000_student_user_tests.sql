create table if not exists public.medquiz_user_tests (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  test_id text not null,
  name text not null,
  original_filename text not null,
  file_type text not null check (file_type in ('pdf','docx')),
  source_path text not null unique,
  data_path text not null unique,
  question_count integer not null check (question_count > 0),
  parse_status text not null default 'ready' check (parse_status in ('ready','error')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_user_id,test_id)
);

create index if not exists medquiz_user_tests_owner_created_idx
  on public.medquiz_user_tests (owner_user_id,created_at desc);

alter table public.medquiz_user_tests enable row level security;

create policy medquiz_user_tests_own_select
  on public.medquiz_user_tests
  for select
  using (owner_user_id = (select auth.uid()));

create policy medquiz_user_tests_own_insert
  on public.medquiz_user_tests
  for insert
  with check (
    owner_user_id = (select auth.uid())
    and (select public.medquiz_account_is_active())
  );

create policy medquiz_user_tests_own_update
  on public.medquiz_user_tests
  for update
  using (owner_user_id = (select auth.uid()))
  with check (
    owner_user_id = (select auth.uid())
    and (select public.medquiz_account_is_active())
  );

create policy medquiz_user_tests_own_delete
  on public.medquiz_user_tests
  for delete
  using (owner_user_id = (select auth.uid()));

grant select,insert,update,delete on table public.medquiz_user_tests to authenticated;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'medquiz-user-tests',
  'medquiz-user-tests',
  false,
  20971520,
  array[
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/zip',
    'application/octet-stream',
    'application/json'
  ]::text[]
)
on conflict (id) do nothing;

create policy medquiz_user_test_files_own_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'medquiz-user-tests'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy medquiz_user_test_files_own_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'medquiz-user-tests'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select public.medquiz_account_is_active())
  );

create policy medquiz_user_test_files_own_update
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'medquiz-user-tests'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'medquiz-user-tests'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select public.medquiz_account_is_active())
  );

create policy medquiz_user_test_files_own_delete
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'medquiz-user-tests'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
