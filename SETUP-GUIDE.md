# Setup guide — database and sign-in

This turns the dashboard from a private, per-browser checklist into a shared board
where approved people sign in with Google and everyone sees the same live state.

**Time needed:** about 20 minutes, most of it waiting on Google's console.

You need to do steps 1–4 yourself — they require signing in and accepting terms.
Step 5 is the only one where you send me something.

---

## What you're building

| Layer | What it does |
|---|---|
| **Supabase** | Postgres database that stores every checkbox, note and metric |
| **Google sign-in** | How approved people prove who they are |
| **Allowlist** | Only `lyaraheducation@gmail.com` and `seekhome.thailand@gmail.com` can edit |
| **Public read** | Anyone with the link sees the board — they just can't change it |

---

## Step 1 — Create the Supabase project

1. Go to **https://supabase.com** and sign in with GitHub or Google.
2. Click **New project**.
3. Fill in:
   - **Name:** `fm-launch-dashboard`
   - **Database password:** click Generate, then **save it in your password manager**. You won't need it for this dashboard, but you'll want it if you ever connect directly.
   - **Region:** pick the one closest to you — Singapore if you're in Thailand.
4. Click **Create new project** and wait ~2 minutes while it provisions.

---

## Step 2 — Create the database tables

1. In your new project, open **SQL Editor** in the left sidebar.
2. Click **New query**.
3. Open `supabase-setup.sql` (in this same folder), copy **all** of it, paste it in.
4. Click **Run**.

You should see `Success. No rows returned`. That's correct — it creates tables rather than returning data.

**To verify it worked**, run this in a new query:

```sql
select email from public.allowlist;
```

You should get back the two approved emails.

---

## Step 3 — Set up Google sign-in

This is the fiddly part. Google and Supabase each need to know about the other.

### 3a. Get your Supabase callback URL first

In Supabase, go to **Authentication → Sign In / Providers → Google**.
Near the bottom you'll see a **Callback URL (for OAuth)** that looks like:

```
https://YOURPROJECT.supabase.co/auth/v1/callback
```

Copy it. You'll paste it into Google in a moment. Leave this tab open.

### 3b. Create Google credentials

1. Go to **https://console.cloud.google.com**
2. Create a new project (top-left project dropdown → New project). Name it `FM Launch Dashboard`.
3. In the search bar, go to **APIs & Services → OAuth consent screen**:
   - **User type:** External → Create
   - **App name:** `Full Marks Launch Dashboard`
   - **User support email:** your email
   - **Developer contact:** your email
   - Save and continue through the remaining screens. You don't need to add scopes or test users.
   - On the summary page, click **Publish app** (otherwise only test users can sign in).
4. Go to **APIs & Services → Credentials → Create credentials → OAuth client ID**:
   - **Application type:** Web application
   - **Name:** `FM Dashboard Web`
   - Under **Authorised JavaScript origins**, add:
     ```
     https://c-seeker.github.io
     ```
   - Under **Authorised redirect URIs**, paste the Supabase callback URL from step 3a.
   - Click **Create**.
5. A dialog shows your **Client ID** and **Client secret**. Keep it open.

### 3c. Connect them in Supabase

1. Back in Supabase → **Authentication → Sign In / Providers → Google**
2. Toggle **Enable Sign in with Google** on.
3. Paste the **Client ID** and **Client secret** from Google.
4. Click **Save**.

### 3d. Tell Supabase where your site lives

Go to **Authentication → URL Configuration** and set:

- **Site URL:** `https://c-seeker.github.io/fm-mkt-plan/`
- **Redirect URLs:** add both of these on separate lines:
  ```
  https://c-seeker.github.io/fm-mkt-plan/
  https://c-seeker.github.io/fm-mkt-plan/**
  ```

If you skip this, sign-in will appear to work but bounce you to a blank page.

---

## Step 4 — Copy your two public keys

In Supabase, go to **Project Settings → API** (or **Data API**) and copy:

1. **Project URL** — looks like `https://abcdefghijk.supabase.co`
2. **anon / public key** — a long string starting with `eyJ...`

### Is it safe to put these in a public repo?

**Yes.** The anon key is designed to be public — it's in the browser of every visitor
either way, so hiding it is impossible and pointless. Your data is protected by the
Row Level Security policies in `supabase-setup.sql`, not by keeping the key secret.
Those policies mean an anon key can read the board and nothing else.

**What is NOT safe to share:** the `service_role` key, also on that page. It bypasses
all security policies. Never put it in the HTML, the repo, or a message to anyone.
If you ever paste it somewhere public, rotate it immediately.

---

## Step 5 — Send me the two values

Paste the **Project URL** and the **anon key** into our chat and I'll wire them into
the dashboard and push the update.

Or, if you'd rather do it yourself: open `index.html`, find this block near the top
of the `<script>` section, and fill it in:

```js
const SUPABASE_URL = 'https://YOURPROJECT.supabase.co';
const SUPABASE_ANON_KEY = 'eyJ...';
```

Then commit the file to GitHub.

---

## How it behaves once it's live

| Who | What they see |
|---|---|
| **Not signed in** | Full board, read-only. A "Sign in with Google" button in the header. |
| **Signed in, approved** | Everything editable. Their name is recorded on every change. |
| **Signed in, not approved** | Read-only, with a message saying their account isn't approved. |

Changes appear on everyone else's screen within a second — no refresh needed.
Each completed task shows who ticked it and when, and the Dashboard tab has an
activity feed of recent changes.

---

## Adding or removing editors later

Supabase → **SQL Editor** → New query:

```sql
-- add someone
insert into public.allowlist (email, note)
values ('newperson@example.com', 'Their role')
on conflict (email) do nothing;

-- remove someone
delete from public.allowlist where email = 'oldperson@example.com';
```

Removal takes effect on their next action — no need to redeploy anything.

---

## Troubleshooting

**"redirect_uri_mismatch" from Google**
The callback URL in Google Credentials doesn't exactly match Supabase's. Re-copy it
from Supabase — it must match character for character, including `https://`.

**Sign-in works but lands on a blank page**
Step 3d wasn't done, or the Redirect URLs don't include your Pages URL.

**Signed in but can't edit, and you should be able to**
The email Google returned isn't in the allowlist. Check the exact address:
```sql
select email from public.allowlist;
```
Gmail addresses are case-insensitive, and the policy lowercases before comparing,
so capitalisation isn't the issue — but a different Google account might be.

**Changes don't appear for other people**
Realtime may not be enabled. Re-run the last section of `supabase-setup.sql`, or in
Supabase go to **Database → Replication** and confirm `board_state` is published.

**Everything broke and you want the old behaviour back**
If `SUPABASE_URL` is left empty, the dashboard falls back to browser-only storage
exactly as it worked before. Nothing is lost.
