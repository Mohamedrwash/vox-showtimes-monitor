# Notifications - all 6 channels

Every channel is **optional**. Enable any combination in `monitor.conf` (PC mode) by
setting the matching `USE_*` to `true` and filling in the credentials.

> **Cloud mode** (GitHub Actions watcher) uses **ntfy only** - it powers the public
> per-film topics that site visitors subscribe to. The other five channels are
> available in PC mode.

## ntfy.sh - zero signup, zero cost (the visitor channel)

**Public per-film topics (this is what website visitors use).** Every film gets topic
`voxwatch-<slug>` - e.g. `voxwatch-the-odyssey`. In cloud mode the topic comes from the
track's `topic` column (empty = `voxwatch-<slug>`); in PC mode it's derived from
`movies.conf`. The site's "notify me" buttons point there; anyone can subscribe in the
app or browser with no account. No setup needed.

**Visitor picks no longer use ntfy.** The site's *track* buttons write straight to the
Supabase `tracks` table (public anon key + RLS by design) - no control topic to set up
or poll.

**Your private mirror.** Everything gets mirrored to one extra topic just for you:

Cloud mode - add a repo secret so the workflow knows it:

| Secret | Value |
|--------|-------|
| `NTFY_MIRROR` | e.g. `vox-odyssey-monitor-abc123` |

PC mode - in `monitor.conf`:

```bash
USE_NTFY=true
NTFY_TOPIC="pick-a-secret-unique-name"     # e.g. vox-odyssey-alerts-abc123
NTFY_SERVER="https://ntfy.sh"
NTFY_PRIORITY="high"
```

Subscribe in the ntfy app: `https://ntfy.sh/<your-topic>`. Topic names are
unguessable-by-accident; treat the private one as secret.

## Gotify - free, self-hosted (PC mode)

1. Deploy the server:
   ```bash
   docker run -p 8080:8080 gotify/server
   ```
2. Open `http://localhost:8080`, create an account and an **application** to
   get an app token.
3. Install the Gotify Android app, point it at your server.
4. In `monitor.conf`:
   ```bash
   USE_GOTIFY=true
   GOTIFY_SERVER="http://localhost:8080"
   GOTIFY_TOKEN="your-app-token"
   GOTIFY_PRIORITY=5
   ```

## Telegram - free, no limits (PC mode)

1. Message [@BotFather](https://t.me/BotFather) - `/newbot` - get the bot token.
2. Start a chat with your bot, then find your chat ID (e.g. via
   `https://api.telegram.org/bot<TOKEN>/getUpdates`).
3. In `monitor.conf`:
   ```bash
   USE_TELEGRAM=true
   TELEGRAM_BOT_TOKEN="123456:ABC-DEF..."
   TELEGRAM_CHAT_ID="123456789"
   ```

## Discord - free (PC mode)

1. Server - Settings - Integrations - Webhooks - New Webhook.
2. Copy the webhook URL.
3. In `monitor.conf`:
   ```bash
   USE_DISCORD=true
   DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/ID/TOKEN"
   ```

## Pushover - free tier (7,500 messages/month) (PC mode)

1. Install the Pushover app (Android is free; iOS is a one-time $5 purchase).
2. Create an account - your **User Key** is on the dashboard.
3. Create an **Application** - gives you an **API Token**.
4. In `monitor.conf`:
   ```bash
   USE_PUSHOVER=true
   PUSHOVER_USER_KEY="your-user-key"
   PUSHOVER_API_TOKEN="your-app-token"
   ```

## Email / SMS gateway - free (PC mode)

1. Install `mail`:
   ```bash
   # Debian/Ubuntu
   sudo apt install mailutils
   # Alpine
   apk add mailx
   ```
2. Configure a relay if needed (the local `mail` uses your system MTA).
3. In `monitor.conf`:
   ```bash
   USE_EMAIL=true
   EMAIL_ADDRESS="you@example.com"
   ```
   For SMS, use your carrier's gateway, e.g. `+2012xxxxxxx@sms.example.net`
   (check your provider's gateway address).

---

## Testing

**Cloud mode:** Actions - **voxwatch watcher** - Run workflow, and watch the log for
`ntfy sent (topic=...)` lines. To re-test a film, delete its key from
`site/data/notified.json` (the bot will re-notify next run) or change the track's `day`.

**PC mode:**

```bash
bash src/vox-monitor.sh digest
```

or trigger a real alert by editing `.known_showtimes_<slug>` to a wrong value,
then:

```bash
bash src/vox-monitor.sh
```

Every enabled channel should fire. Check `vox_showtimes.log` for per-channel
"sent" lines.
