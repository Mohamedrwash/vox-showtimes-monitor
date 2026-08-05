# Notifications — all 6 channels

Every channel is **optional**. Enable any combination in `monitor.conf` by
setting the matching `USE_*` to `true` and filling in the credentials.

## 🆓 ntfy.sh — zero signup, zero cost (the visitor channel)

Two roles:

**Public per-film topics (this is what website visitors use).** Every film in
`movies.conf` automatically gets topic `voxwatch-<slug>` — e.g.
`voxwatch-the-odyssey`. The site's "notify me" buttons point there; anyone can
subscribe in the app or browser with no account. No setup needed.

**Control topic (visitor picks).** The site's *track* buttons publish
`PICK <slug>` / `UNPICK <slug>` to the topic in `CONTROL_TOPIC`; the monitor
consumes it on every run. It's public, so picks are unauthenticated — use a
non-obvious topic name if your site is publicly reachable.

**Your private mirror.** Everything gets mirrored to one extra topic just for you:

```bash
USE_NTFY=true
NTFY_TOPIC="pick-a-secret-unique-name"     # e.g. vox-odyssey-alerts-abc123
NTFY_SERVER="https://ntfy.sh"
NTFY_PRIORITY="high"
```

Subscribe in the ntfy app: `https://ntfy.sh/<your-topic>`. Topic names are
unguessable-by-accident; treat the private one as secret.

## 🆓 Gotify — free, self-hosted

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

## 🆓 Telegram — free, no limits

1. Message [@BotFather](https://t.me/BotFather) → `/newbot` → get the bot token.
2. Start a chat with your bot, then find your chat ID (e.g. via
   `https://api.telegram.org/bot<TOKEN>/getUpdates`).
3. In `monitor.conf`:
   ```bash
   USE_TELEGRAM=true
   TELEGRAM_BOT_TOKEN="123456:ABC-DEF..."
   TELEGRAM_CHAT_ID="123456789"
   ```

## 🆓 Discord — free

1. Server → Settings → Integrations → Webhooks → New Webhook.
2. Copy the webhook URL.
3. In `monitor.conf`:
   ```bash
   USE_DISCORD=true
   DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/ID/TOKEN"
   ```

## Pushover — free tier (7,500 messages/month)

1. Install the Pushover app (Android is free; iOS is a one-time $5 purchase).
2. Create an account → your **User Key** is on the dashboard.
3. Create an **Application** → gives you an **API Token**.
4. In `monitor.conf`:
   ```bash
   USE_PUSHOVER=true
   PUSHOVER_USER_KEY="your-user-key"
   PUSHOVER_API_TOKEN="your-app-token"
   ```

## Email / SMS gateway — free

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