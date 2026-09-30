alter table public.medquiz_attempt_questions
  add column if not exists explanation_source text;

comment on column public.medquiz_attempt_questions.explanation_source is
  'Optional source supplied separately from the explanation in a student DOCX import.';
