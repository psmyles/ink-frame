-- The directory (shared/api/directory.yaml): each account's frames, and device tokens.
-- account = SHA-256 (hex) of "<provider>:<sub>"; times are Unix seconds.

create table frames (
  account text not null,
  url text not null,
  key text not null,
  added_at integer not null,
  primary key (account, url)
) without rowid;

-- Only the SHA-256 (hex) of each token is kept.
create table tokens (
  hash text primary key,
  account text not null,
  created_at integer not null,
  used_at integer not null
) without rowid;

create index tokens_account on tokens (account);
