# 08 · Access from outside your home (Tailscale)

Tailscale builds a private, encrypted network between your devices. Nothing is exposed to the internet and no router ports are opened. The free plan covers personal use, and Tailscale is preinstalled on Bazzite.

## Set up (5 minutes)

```bash
sudo tailscale up --ssh --hostname=evo-x3
```

- Open the printed URL and log in (Google/GitHub/…). The box is now `evo-x3` in your tailnet.
- Install Tailscale on your phone and laptop and log in with the same account.
- In the [admin console](https://login.tailscale.com/admin/machines), **disable key expiry** for `evo-x3`, so the server never drops off the tailnet.
- `--ssh` enables Tailscale SSH, so you can `ssh you@evo-x3` from any of your devices without managing keys.

Everything now works from anywhere at `http://evo-x3:3000`, `http://evo-x3:8080/v1`, and so on (MagicDNS name).

## Optional: real HTTPS for the chat UI

Browsers only allow microphone access (voice chat) and "install as app" on HTTPS pages. Tailscale can provide a certificate:

```bash
# one-time, in the admin console: enable Serve (the first `tailscale serve`
# prints a login.tailscale.com/f/serve?node=... link) and HTTPS Certificates (DNS page)
# one-time, so serve needs no sudo afterwards:
sudo tailscale set --operator=$USER
tailscale serve --bg --https=443 http://127.0.0.1:3000      # Open WebUI
tailscale serve --bg --https=8443 http://127.0.0.1:8080     # API (optional)
tailscale serve status
```

The chat is then at **`https://evo-x3.<your-tailnet>.ts.net`**, valid only inside your tailnet (verified on this machine: HTTP 200, valid certificate; the first request takes a few seconds while the certificate is issued). The serve config persists across reboots. Add it to the phone's home screen for an app-like experience.

## Giving family and friends access

- **Share the machine:** in the admin console, *Machines → evo-x3 → Share…* sends an invite. They install Tailscale, accept, and can only reach this one machine.
- Restrict what shared users can reach with an ACL (e.g. only port 443/3000):
  ```jsonc
  // Tailscale admin → Access controls (excerpt)
  "grants": [
    { "src": ["autogroup:shared"], "dst": ["tag:evo"], "ip": ["tcp:443", "tcp:3000"] }
  ]
  ```
  Tag the machine with `sudo tailscale up --advertise-tags=tag:evo` after defining the tag in the policy.
- They then create an Open WebUI account, and you approve it in *Admin → Users*.

## Later: a public URL without Tailscale on every device

If someone can't install Tailscale, use **Tailscale Funnel** (`sudo tailscale funnel --bg 3000`). It publishes Open WebUI on the internet at the `ts.net` URL. Only do this with sign-ups set to *pending* (the default here) and strong passwords, and **never** funnel port 8080 (the API key would be the only thing protecting your GPU). Alternatively, use Cloudflare Tunnel + Cloudflare Access (login wall) with your own domain.

## Checklist

- [ ] `tailscale status` shows evo-x3 online
- [ ] key expiry disabled
- [ ] phone can open `http://evo-x3:3000` on mobile data
- [ ] (optional) HTTPS serve configured, voice input works on phone
