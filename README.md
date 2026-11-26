# Veoa website

Landing page plus web app: sign in (email or Google), view, download and send photos, reset password.
Plain HTML, CSS and JavaScript. No build step. Hosted for free on GitHub Pages.

Upload everything in this folder to the ROOT of your website repository (including the hidden `.nojekyll` file),
then Settings > Pages > Deploy from a branch > main > / (root).

    index.html  style.css  app.js  evora-crypto.js  jszip.min.js
    robots.txt  sitemap.xml  site.webmanifest  .nojekyll
    favicon.ico  favicon-32.png  icon-192.png  icon-512.png  apple-touch-icon.png  og.png

Address used in the files: https://rajamari2026.github.io/veoa/
If yours is different, change it in index.html (canonical, og:url, og:image, twitter:image, JSON-LD),
sitemap.xml and robots.txt, and in the app's lib/config.dart (webUrl).

Security: a Content-Security-Policy is set in index.html, all scripts are local files (no CDN),
signing out revokes the session on the server, the key in app.js is the public project key.
GitHub Pages cannot send extra security headers; if you later move to a host that can, add
X-Frame-Options DENY and a frame-ancestors rule.
