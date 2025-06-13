# Multi-stage build pour optimiser la taille de l'image finale
FROM node:20.15.1-alpine AS base

# Installation des dépendances système nécessaires pour les binaires natifs
RUN apk add --no-cache \
    libc6-compat \
    python3 \
    make \
    g++ \
    && ln -sf python3 /usr/bin/python

# Installation de pnpm
RUN npm install -g pnpm@9.4.0

# Définir le répertoire de travail
WORKDIR /app

# Copier les fichiers de configuration des dépendances
COPY package.json pnpm-lock.yaml ./

# Stage pour les dépendances
FROM base AS deps
RUN pnpm install --frozen-lockfile

# Stage pour le build
FROM node:20.15.1 AS builder

# Installer pnpm
RUN npm install -g pnpm@9.4.0

WORKDIR /app

# Copier les dépendances depuis le stage deps
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Build de l'application avec les variables d'environnement nécessaires
ENV NODE_ENV=production
RUN pnpm run build

# Stage de production
FROM node:20.15.1-slim AS runner

# Installation des dépendances système pour l'exécution
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 1001 nodejs \
    && useradd --system --uid 1001 --gid nodejs nextjs

# Installer pnpm
RUN npm install -g pnpm@9.4.0

WORKDIR /app

# Copier les fichiers nécessaires depuis le builder
COPY --from=builder --chown=nextjs:nodejs /app/build ./build
COPY --from=builder --chown=nextjs:nodejs /app/package.json ./package.json
COPY --from=builder --chown=nextjs:nodejs /app/pnpm-lock.yaml ./pnpm-lock.yaml

# Copier le fichier .env s'il existe, sinon créer un fichier vide
COPY --from=builder /app/.env* ./
RUN [ ! -f .env ] && touch .env || true

# Installer seulement les dépendances de production nécessaires pour le runtime
# Exclure wrangler et workerd qui causent des problèmes
RUN pnpm install --prod --frozen-lockfile || \
    (echo "Installation avec pnpm échouée, utilisation de npm..." && \
     npm ci --only=production --ignore-scripts)

# Créer un serveur simple pour l'application
RUN echo '#!/bin/bash\n\
set -e\n\
echo "Démarrage du serveur de production..."\n\
\n\
# Serveur Node.js simple pour servir les fichiers statiques et gérer les fonctions\n\
cat > server.js << '"'"'EOF'"'"'\n\
const http = require("http");\n\
const fs = require("fs");\n\
const path = require("path");\n\
const url = require("url");\n\
\n\
const PORT = process.env.PORT || 8787;\n\
const PUBLIC_DIR = "./build/client";\n\
\n\
const mimeTypes = {\n\
  ".html": "text/html",\n\
  ".js": "text/javascript",\n\
  ".css": "text/css",\n\
  ".json": "application/json",\n\
  ".png": "image/png",\n\
  ".jpg": "image/jpg",\n\
  ".gif": "image/gif",\n\
  ".svg": "image/svg+xml",\n\
  ".wav": "audio/wav",\n\
  ".mp4": "video/mp4",\n\
  ".woff": "application/font-woff",\n\
  ".ttf": "application/font-ttf",\n\
  ".eot": "application/vnd.ms-fontobject",\n\
  ".otf": "application/font-otf",\n\
  ".wasm": "application/wasm"\n\
};\n\
\n\
const server = http.createServer((req, res) => {\n\
  const parsedUrl = url.parse(req.url);\n\
  let pathname = `.${parsedUrl.pathname}`;\n\
  \n\
  // Servir depuis le répertoire public\n\
  if (pathname === "./") {\n\
    pathname = `${PUBLIC_DIR}/index.html`;\n\
  } else {\n\
    pathname = `${PUBLIC_DIR}${parsedUrl.pathname}`;\n\
  }\n\
\n\
  const ext = path.parse(pathname).ext;\n\
  const mimeType = mimeTypes[ext] || "application/octet-stream";\n\
\n\
  fs.readFile(pathname, (err, data) => {\n\
    if (err) {\n\
      // Fallback vers index.html pour les routes SPA\n\
      if (ext === "" || ext === ".html") {\n\
        fs.readFile(`${PUBLIC_DIR}/index.html`, (fallbackErr, fallbackData) => {\n\
          if (fallbackErr) {\n\
            res.writeHead(404);\n\
            res.end("404 Not Found");\n\
          } else {\n\
            res.writeHead(200, { "Content-Type": "text/html" });\n\
            res.end(fallbackData);\n\
          }\n\
        });\n\
      } else {\n\
        res.writeHead(404);\n\
        res.end("404 Not Found");\n\
      }\n\
    } else {\n\
      res.writeHead(200, { "Content-Type": mimeType });\n\
      res.end(data);\n\
    }\n\
  });\n\
});\n\
\n\
server.listen(PORT, "0.0.0.0", () => {\n\
  console.log(`Serveur démarré sur http://0.0.0.0:${PORT}`);\n\
});\n\
EOF\n\
\n\
exec node server.js' > start.sh

# Créer les répertoires nécessaires et configurer les permissions
RUN mkdir -p /home/nextjs/.config && \
    chmod +x ./start.sh && \
    chown -R nextjs:nodejs /app /home/nextjs

# Changer vers l'utilisateur non-root
USER nextjs

# Exposer le port
EXPOSE 8787

# Variables d'environnement par défaut
ENV NODE_ENV=production
ENV PORT=8787

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8787/ || exit 1

# Commande de démarrage avec serveur Node.js simple
CMD ["./start.sh"]