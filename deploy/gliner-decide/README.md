# GLiNER2.5-Decide API (self-hosted)

A private HTTPS API for [fastino/GLiNER2.5-Decide](https://huggingface.co/fastino/GLiNER2.5-Decide), a 340M zero-shot
text classifier: pass any label set at call time (intent, routing, sentiment, priority, multi-label tags).

It runs on any Ubuntu/Debian VPS with 4 GB+ RAM. The server downloads the model itself, so the machine you call it
from never needs to reach Hugging Face.

```
your laptop / app ──HTTPS + API key──▶ VPS: Caddy (auto TLS) ──▶ FastAPI + GLiNER2.5-Decide (CPU)
```

## Deploy on Hostinger (about 15 minutes)

1. **Buy a VPS.** KVM 2 (2 vCPU, 8 GB) is recommended (~0.5 s per request). KVM 1 (1 vCPU, 4 GB) also works, at roughly
   half the speed. Choose **Ubuntu 24.04** as the OS; the plain or the "with Docker" template both work.
2. **Open a terminal on it.** In hPanel: **VPS → Manage → Browser terminal** (or `ssh root@<your-vps-ip>`).
3. **Paste this and press Enter:**

   ```bash
   curl -fsSL https://raw.githubusercontent.com/pirazor/ML-agents/refs/heads/claude/peaceful-gauss-cexx9v/deploy/gliner-decide/install.sh | bash
   ```

   It installs Docker if needed, builds the image (5–10 minutes the first time), starts the API behind HTTPS, and prints
   your **URL** and **API key**. With no domain set, the URL is `https://<ip-with-dashes>.sslip.io`, which works out of
   the box with a real certificate.

If the script reports the API is unreachable, check **hPanel → VPS → Security → Firewall**: ports 80 and 443 must be
allowed (or no firewall rules applied).

### VPS that already runs Traefik (Hostinger "Ubuntu with n8n" template)

That template's Traefik already holds ports 80/443, so `install.sh` (which starts Caddy) would clash with it. Use
`docker-compose.traefik.yml` instead: it joins Traefik's `n8n_default` network and gets its certificate from Traefik's
`mytlschallenge` resolver, leaving the n8n project untouched. It needs no image build, so you can paste it as-is into
**hPanel → VPS → Docker Manager → Compose** (or deploy it through the Hostinger API) with these environment variables:

```
API_KEY=<long random string>
API_HOST=gliner.<your-vps-hostname>      # e.g. gliner.srv123456.hstgr.cloud; *.hstgr.cloud subdomains already resolve
```

The first start installs dependencies and downloads the model into Docker volumes (about 5–10 minutes); after that a
restart takes under a minute. The container is capped at 4 GB RAM and 1.5 CPUs so it can't starve n8n.

### Use your own domain (optional)

Add a DNS **A record** (e.g. `api.yourdomain.com`) pointing at the VPS IP. On Hostinger: **hPanel → Domains → DNS / Nameservers**.
Once it resolves, re-run the installer with the domain; your API key is kept:

```bash
curl -fsSL https://raw.githubusercontent.com/pirazor/ML-agents/refs/heads/claude/peaceful-gauss-cexx9v/deploy/gliner-decide/install.sh | DOMAIN=api.yourdomain.com bash
```

## Calling the API

Send the key as `x-api-key: <key>` or `Authorization: Bearer <key>`.

| Method | Path | Body |
|---|---|---|
| GET | `/` | Health check |
| POST | `/classify` | `{"text": str, "tasks": {...}, "threshold": 0.5, "include_confidence": false}` |
| POST | `/classify/batch` | `{"texts": [str, ...]` (max 32)`, "tasks": {...}, ...}` |

Interactive docs: `https://<your-url>/docs`.

A task is a label list, or an object for multi-label:

```json
{
  "intent": ["refund_request", "cancel_subscription", "other"],
  "topics": {"labels": ["billing", "shipping", "quality"], "multi_label": true, "cls_threshold": 0.4}
}
```

```bash
curl -X POST https://<your-url>/classify \
  -H "x-api-key: $API_KEY" -H "content-type: application/json" \
  -d '{"text": "Can I get a refund for last month?", "tasks": {"intent": ["refund_request", "cancel_subscription", "other"]}}'
# {"intent":"refund_request"}
```

```python
import requests

r = requests.post(
    "https://<your-url>/classify",
    headers={"x-api-key": API_KEY},
    json={"text": "Can I get a refund?", "tasks": {"intent": ["refund_request", "other"]}},
    timeout=30,
)
print(r.json())
```

## Managing it

Everything lives in `/opt/gliner-decide` on the VPS.

| Task | Command |
|---|---|
| Show the API key | `cat /opt/gliner-decide/.env` |
| Logs | `cd /opt/gliner-decide && docker compose logs -f --tail 50` |
| Restart | `cd /opt/gliner-decide && docker compose restart` |
| Change the key | re-run the installer with `API_KEY=<new>` before `bash` |
| Update code | re-run the installer |
| Uninstall | `cd /opt/gliner-decide && docker compose down -v --rmi all && rm -rf /opt/gliner-decide` |

The containers restart automatically after a reboot or crash.

## Files

| File | Purpose |
|---|---|
| `install.sh` | One-shot installer / updater |
| `app.py` | FastAPI service (auth, validation, `/classify`, `/classify/batch`) |
| `Dockerfile` | CPU-only image with the model weights baked in |
| `docker-compose.yml` | API + Caddy reverse proxy |
| `Caddyfile` | HTTPS termination with automatic Let's Encrypt certificates |
| `docker-compose.traefik.yml` | Alternative for servers that already run Traefik (no build, no Caddy) |
| `requirements.txt` | Pinned Python dependencies |
