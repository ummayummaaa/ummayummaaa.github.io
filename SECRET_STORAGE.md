# Secret storage policy

## Public browser configuration

`SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` are shipped to the browser and
must be treated as public configuration. They do not grant administrative
access. Supabase Row Level Security (RLS) remains the security boundary for
browser requests.

Never place the Supabase service-role key, database password, OAuth tokens, or
backup encryption material in browser code.

## Private automation values

The following values belong only in the protected secrets store used by the
backup automation (for example, GitHub Actions repository secrets):

- `SUPABASE_DB_URL`
- `DROPBOX_APP_KEY`
- `DROPBOX_APP_SECRET`
- `DROPBOX_REFRESH_TOKEN`
- `YANDEX_OAUTH_TOKEN`
- `BACKUP_ENCRYPTION_PASSPHRASE`

The repository contains names and empty placeholders only. Real values must
not be committed, written to logs, included in backup manifests, or copied to
Dropbox or Yandex Disk as plaintext.

## Local development

Copy `.env.example` to `.env.local` and fill it locally when a tool needs these
values. Environment files, credential directories, and common private-key
formats are excluded by `.gitignore`.

If a private value is ever committed, removing it in a later commit is not
enough. Revoke or rotate it first, then clean the Git history if necessary.
