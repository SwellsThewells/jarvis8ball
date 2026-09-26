# Setting up online play

Discord sign-in, friends, chat, lobbies, online matches and coins all run on
a free [Supabase](https://supabase.com) project. You set it up once; it takes
about 15 minutes. Nothing needs to stay running on your computer.

## 1. Make the Supabase project

1. Sign up at https://supabase.com and click **New project**. Any name and
   region; save the database password somewhere.
2. When it's ready, open **SQL Editor**, click **New query**, paste in all of
   `supabase/schema.sql` from this repo and click **Run**. It should say
   "Success". (Running it again later is safe.)

## 2. Make the Discord app

1. Go to https://discord.com/developers/applications and open the app you
   made for Rich Presence (or click **New Application**, name it `Jarvis 8 Pool`).
2. Open **OAuth2**. Copy the **Client ID**, click **Reset Secret** and copy the
   **Client Secret**.
3. Under **Redirects**, click **Add Redirect** and paste:
   `https://<your-project>.supabase.co/auth/v1/callback`
   (your project URL is in Supabase under **Project Settings > API**). Save.

## 3. Switch on Discord in Supabase

1. In Supabase open **Authentication > Sign In / Providers > Discord**, turn it
   on, paste the Client ID and Client Secret from step 2, and save.
2. Open **Authentication > URL Configuration**. Under **Redirect URLs** click
   **Add URL** and add exactly:
   `http://127.0.0.1:47219/callback`
   (that's the game catching the sign-in on your own computer).

## 4. Point the game at it

Open `online.cfg` in the project folder and fill in, from **Project Settings >
API** in Supabase:

```
[supabase]
url="https://<your-project>.supabase.co"
anon_key="<the anon / publishable key>"
```

Only ever use the **anon** (or **publishable**) key. Never the service_role or
secret key: that one can do anything to your database.

Export the game as usual; `online.cfg` goes into the build. A copy of
`online.cfg` next to the exe overrides it, so you can switch projects without
re-exporting.

## Trying it

Run the game, click **Sign in with Discord** in the top right. Your browser
opens Discord; approve it and the tab says you're signed in. Then **Play >
Multiplayer**. To test a match on your own, run a second copy of the game
signed in with a different Discord account.

## Good to know

- **Coins:** new accounts start with 100. Bot games pay 15 for a win and 5 for
  a loss (at most one payout a minute), online wins pay 50 and a trophy. Cue
  prices live in `scripts/pool_cues.gd`; after changing them, run the schema
  again so the server charges the same.
- **Free plan limits:** Supabase's free plan allows a set number of live
  messages a second across the whole project. The game keeps each match well
  under it, which is enough for a handful of matches at the same time. Free
  projects also pause after a week with nobody using them; one click in the
  dashboard wakes them up.
- **Signed out,** coins and cues are kept on your computer as before. Signed
  in, they're your online account's.
