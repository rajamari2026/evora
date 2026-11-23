# Evora website

Landing page + web app (sign in, view, download and send photos). Plain HTML, CSS and JavaScript. No build step.

## Where the files go
Upload everything in this folder to the ROOT of your `evora` GitHub repository (replace the existing files).
Netlify rebuilds automatically after the commit.

    index.html  style.css  app.js  evora-crypto.js  jszip.min.js
    netlify.toml  robots.txt  sitemap.xml  site.webmanifest
    favicon.ico  favicon-32.png  icon-192.png  icon-512.png  apple-touch-icon.png  og.png

Delete from that repo: `.github/workflows/static.yml` (the leftover GitHub Pages workflow) and any old copy of the page.

## Security notes
- `netlify.toml` sets a strict Content-Security-Policy and other headers. All scripts are local files (JSZip is included, not loaded from a CDN).
- Signing out also revokes the session on the server.
- The key inside `app.js` is the public project key. It is meant to be public.

## Getting found on Google
1. Netlify > Project configuration > Access and security: turn OFF site password / visitor access. Google cannot index a password-protected site.
2. If your address is not `https://evora.netlify.app/`, replace it in `index.html` (canonical, og:url, og:image, twitter:image, JSON-LD), `sitemap.xml` and `robots.txt`.
3. Open search.google.com/search-console > Add property > URL prefix > your address. Choose "HTML tag", copy the tag into the commented line in `index.html` (remove the comment marks), commit, then click Verify.
4. In Search Console: Sitemaps > add `sitemap.xml`. Then URL Inspection > paste your address > Request indexing.
5. Wait a few days. "Evora" alone is a very common word (a city in Portugal and many brands), so also test searches like `Evora photo sharing app`.
