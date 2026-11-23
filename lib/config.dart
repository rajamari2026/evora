/// Supabase project settings for Evora sharing.
/// The anon key is designed to be public; data is protected by the
/// database rules (row level security) set up in supabase_setup.sql.
class Config {
  static const String url = 'https://qixnxntmaeeeyetwsgdy.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFpeG54bnRtYWVlZXlldHdzZ2R5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMyNzE0ODEsImV4cCI6MjEwODg0NzQ4MX0.FIAPEiucXRikt9PdNtgUc5wCO1TMaCaUTkUfaKbHCeg';

  static bool get ready =>
      url.startsWith('https://') &&
      !url.contains('YOUR-PROJECT') &&
      !anonKey.contains('YOUR-ANON-KEY') &&
      anonKey.length > 20;
}
