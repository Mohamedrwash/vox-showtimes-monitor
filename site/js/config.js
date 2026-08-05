// voxwatch runtime config — Supabase project URL + anon key.
// The anon key is public by design; the RLS policies on the `tracks`
// table are what protect the data, not this key. Fill these in after
// creating the project (docs/supabase-schema.sql).
window.VOXWATCH_SUPABASE = {
  url: 'https://plueqjsdnhmjtlqmmwpy.supabase.co',
  anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBsdWVxanNkbmhtanRscW1td3B5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU5MTc2NjAsImV4cCI6MjEwMTQ5MzY2MH0.eccK22ENNeuMa6fLVgYXJmOtpZJH4UHQqpBx3SnTLM8'
};

// Admin page gate (admin.html). Soft gate only: it hides the admin page from
// casual visitors but ships with the site, so treat it as obfuscation, not
// real security. Leave empty to disable the admin page entirely.
window.VOXWATCH_ADMIN = {
  passcode: 'Medo1111'
};
