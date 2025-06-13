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
RUN pnpm install --prod --frozen-lockfile || \
    npm ci --only=production --ignore-scripts

# Créer un serveur CommonJS simple
RUN cat > server.cjs << 'EOF'
const http = require("http");
const fs = require("fs");
const path = require("path");
const url = require("url");

const PORT = process.env.PORT || 8787;
const PUBLIC_DIR = "./build/client";

const mimeTypes = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".css": "text/css",
  ".json": "application/json",
  ".png": "image/png",
  ".jpg": "image/jpg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".wav": "audio/wav",
  ".mp4": "video/mp4",
  ".woff": "application/font-woff",
  ".woff2": "font/woff2",
  ".ttf": "application/font-ttf",
  ".eot": "application/vnd.ms-fontobject",
  ".otf": "application/font-otf",
  ".wasm": "application/wasm"
};

const server = http.createServer((req, res) => {
  // Ajouter les headers CORS et de sécurité
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  
  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  const parsedUrl = url.parse(req.url);
  let pathname = parsedUrl.pathname;
  
  // Gestion spéciale pour favicon.ico
  if (pathname === "/favicon.ico") {
    const faviconPath = path.join(PUBLIC_DIR, "favicon.ico");
    fs.readFile(faviconPath, (err, data) => {
      if (err) {
        // Créer un favicon minimal si absent
        res.writeHead(200, { "Content-Type": "image/x-icon" });
        res.end();
      } else {
        res.writeHead(200, { "Content-Type": "image/x-icon" });
        res.end(data);
      }
    });
    return;
  }
  
  // Servir depuis le répertoire public
  if (pathname === "/") {
    pathname = "/index.html";
  }
  
  const filePath = path.join(PUBLIC_DIR, pathname);
  const ext = path.parse(filePath).ext;
  const mimeType = mimeTypes[ext] || "application/octet-stream";

  fs.readFile(filePath, (err, data) => {
    if (err) {
      // Fallback vers index.html pour les routes SPA
      if (ext === "" || ext === ".html" || !ext) {
        fs.readFile(path.join(PUBLIC_DIR, "index.html"), (fallbackErr, fallbackData) => {
          if (fallbackErr) {
            console.log(`❌ 404: ${pathname}`);
            res.writeHead(404);
            res.end("404 Not Found");
          } else {
            res.writeHead(200, { "Content-Type": "text/html" });
            res.end(fallbackData);
          }
        });
      } else {
        console.log(`❌ 404: ${pathname}`);
        res.writeHead(404);
        res.end("404 Not Found");
      }
    } else {
      console.log(`✅ 200: ${pathname}`);
      res.writeHead(200, { "Content-Type": mimeType });
      res.end(data);
    }
  });
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`🚀 Serveur bolt.new démarré sur http://0.0.0.0:${PORT}`);
  console.log(`📁 Servant les fichiers depuis: ${PUBLIC_DIR}`);
  console.log(`🔍 Vérifiez que le dossier contient bien index.html`);
  
  // Lister les fichiers disponibles pour debug
  fs.readdir(PUBLIC_DIR, (err, files) => {
    if (err) {
      console.log(`⚠️  Impossible de lire le dossier ${PUBLIC_DIR}`);
    } else {
      console.log(`📋 Fichiers disponibles: ${files.slice(0, 10).join(', ')}${files.length > 10 ? '...' : ''}`);
    }
  });
});
EOF

# Créer les répertoires nécessaires et configurer les permissions
RUN mkdir -p /home/nextjs/.config && \
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

# Commande de démarrage avec serveur CommonJS
CMD ["node", "server.cjs"]