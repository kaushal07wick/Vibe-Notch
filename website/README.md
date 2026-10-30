# Vibe Notch website

A single static page (`index.html` + `assets/`). No build step.

- Preview: `python3 -m http.server 8080` here, then open http://localhost:8080
- GitHub Pages: Settings → Pages → deploy from branch `master`, folder `/website` (or copy the folder into a `gh-pages` branch)
- Vercel / Netlify / Cloudflare Pages: set the project root to `website/`, no build command, output directory `.`
- Download buttons point at the repo's latest GitHub Release — publish one (a zipped `VibeNotch.app`) for them to work.
