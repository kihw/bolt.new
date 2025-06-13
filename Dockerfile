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

# Créer un serveur CommonJS simple qui détecte automatiquement la structure
RUN cat > server.cjs << 'EOF'
const http = require("http");
const fs = require("fs");
const path = require("path");
const url = require("url");

const PORT = process.env.PORT || 8787;

// Fonction pour trouver le bon répertoire et fichier index
function findBuildStructure() {
  const possibleDirs = [
    "./build/client",
    "./build",
    "./dist/client", 
    "./dist",
    "./public"
  ];
  
  const possibleIndexFiles = [
    "index.html",
    "index.htm",
    "app.html"
  ];
  
  for (const dir of possibleDirs) {
    if (fs.existsSync(dir)) {
      for (const indexFile of possibleIndexFiles) {
        const fullPath = path.join(dir, indexFile);
        if (fs.existsSync(fullPath)) {
          console.log(`📍 Structure trouvée: ${dir} avec ${indexFile}`);
          return { publicDir: dir, indexFile };
        }
      }
      // Si le dossier existe mais pas de fichier index, lister le contenu
      const files = fs.readdirSync(dir);
      console.log(`📁 Contenu de ${dir}:`, files);
    }
  }
  
  // Fallback par défaut
  console.log(`⚠️  Aucune structure standard trouvée, utilisation de ./build/client`);
  return { publicDir: "./build/client", indexFile: "index.html" };
}

const { publicDir: PUBLIC_DIR, indexFile: INDEX_FILE } = findBuildStructure();

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
  
  // Gestion spéciale pour favicon
  if (pathname === "/favicon.ico") {
    const faviconSvg = path.join(PUBLIC_DIR, "favicon.svg");
    if (fs.existsSync(faviconSvg)) {
      fs.readFile(faviconSvg, (err, data) => {
        if (!err) {
          res.writeHead(200, { "Content-Type": "image/svg+xml" });
          res.end(data);
          return;
        }
      });
    }
    // Favicon vide par défaut
    res.writeHead(200, { "Content-Type": "image/x-icon" });
    res.end();
    return;
  }
  
  // Servir depuis le répertoire public
  if (pathname === "/") {
    pathname = `/${INDEX_FILE}`;
  }
  
  const filePath = path.join(PUBLIC_DIR, pathname);
  const ext = path.parse(filePath).ext;
  const mimeType = mimeTypes[ext] || "application/octet-stream";

  fs.readFile(filePath, (err, data) => {
    if (err) {
      // Fallback vers le fichier index pour les routes SPA
      if (ext === "" || ext === ".html" || !ext) {
        const indexPath = path.join(PUBLIC_DIR, INDEX_FILE);
        fs.readFile(indexPath, (fallbackErr, fallbackData) => {
          if (fallbackErr) {
            console.log(`❌ 404: ${pathname} (et pas de ${INDEX_FILE})`);
            // Créer une page d'index simple si rien n'existe
            const simpleHtml = `<!DOCTYPE html>
<html>
<head>
  <title>Bolt.new</title>
  <meta charset="utf-8">
</head>
<body>
  <h1>Bolt.new Application</h1>
  <p>Serveur démarré avec succès!</p>
  <p>Répertoire: ${PUBLIC_DIR}</p>
  <p>Fichiers disponibles:</p>
  <ul>${fs.readdirSync(PUBLIC_DIR).map(f => `<li><a href="/${f}">${f}</a></li>`).join('')}</ul>
</body>
</html>`;
            res.writeHead(200, { "Content-Type": "text/html" });
            res.end(simpleHtml);
          } else {
            console.log(`✅ 200: ${pathname} → ${INDEX_FILE}`);
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
  console.log(`📄 Fichier index: ${INDEX_FILE}`);
  
  // Exploration complète de la structure
  console.log("🗂️  Structure complète du build:");
  function exploreDir(dir, prefix = "") {
    try {
      const items = fs.readdirSync(dir);
      items.forEach(item => {
        const fullPath = path.join(dir, item);
        const stat = fs.statSync(fullPath);
        if (stat.isDirectory()) {
          console.log(`${prefix}📁 ${item}/`);
          if (prefix.length < 6) { // Limiter la profondeur
            exploreDir(fullPath, prefix + "  ");
          }
        } else {
          console.log(`${prefix}📄 ${item}`);
        }
      });
    } catch (err) {
      console.log(`${prefix}❌ Erreur: ${err.message}`);
    }
  }
  
  exploreDir("./build");
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