// K_01 app settings - the only file you need to edit.
// Supabase project: the same one the WhatsApp AI Sales Agent _2 workflow writes to.
const SUPABASE_URL = 'https://exrwflwdjsfkkfrusjip.supabase.co';
// Supabase dashboard > Project Settings > API > "anon" / "publishable" key (NOT the service_role key).
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV4cndmbHdkanNma2tmcnVzamlwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTU0NTI2NDUsImV4cCI6MjExMTAyODY0NX0.q8SP3OqpxvKoFkE-eYU36cCmqgwTAeA7pkEzhAr485E';
// n8n webhook of the _2 workflow that sends a WhatsApp message from the app's chat box.
const SEND_URL = 'https://gladki.app.n8n.cloud/webhook/crm-send-message-2';
