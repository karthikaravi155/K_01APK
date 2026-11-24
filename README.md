# K_01 Leads app (PWA -> Android APK)

Same app as EasyShare Leads, now pointed at the **new Supabase project** that the
*WhatsApp AI Sales Agent _2* workflow writes to, and at that workflow's send webhook.

## What changed
- `config.js` (new): Supabase URL, anon key and the n8n send URL. **This is the only file to edit.**
- `index.html`: reads those settings from `config.js` (nothing else changed).
- `service-worker.js`: new cache name, caches `config.js`.
- `supabase_setup.sql` (new): run once in the new Supabase project (tables, round robin, access rules, realtime).

## Setup
1. **Database:** already applied to the new project. Re-running `supabase_setup.sql` is safe.
2. **Logins:** Authentication > Users > Add user (email + password, tick "Auto Confirm"). Also
   Authentication > Sign In / Providers > turn **off** "Allow new users to sign up".
3. **Names and roles:** run the three `update ... set name, role` lines at the bottom of the SQL
   (with the real emails). Admin sees all leads; a team lead ("tl") sees only leads assigned to them.
4. **Anon key:** already filled in `config.js` (and in the "CRM Check Access (RLS)" node of _2).
   Never put the service_role key in the app.
5. **Deploy:** vercel.com > Add New Project > upload this folder (project name e.g. `k-01apk`).
6. **APK:** pwabuilder.com > paste the Vercel URL > Package for Stores > Android > download the `.apk`.
7. **Workflow _2:** publish it, and set Meta's webhook for its number to its production URL.

## Round robin
Every brand-new lead is assigned to the active team lead who was given a lead longest ago.
Set `active = false` on a profile to take someone out of the rotation.
