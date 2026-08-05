// voxwatch runtime config — Supabase project URL + anon key.
// The anon key is public by design; the RLS policies on the `tracks`
// table are what protect the data, not this key. Fill these in after
// creating the project (docs/supabase-schema.sql).
window.VOXWATCH_SUPABASE = {
  url: '',
  anonKey: ''
};
