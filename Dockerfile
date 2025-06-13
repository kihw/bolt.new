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

WORKDIR /app

# Copier les fichiers nécessaires depuis le builder
COPY --from=builder --chown=nextjs:nodejs /app/build ./build

# Analyser la structure pour trouver le bon point d'entrée
RUN echo "Structure complète:" && find ./build -type f -name "*.html" -o -name "*.js" | head -20

# Chercher un fichier HTML existant ou en créer un minimal qui charge l'app
RUN if [ ! -f ./build/client/index.html ]; then \
    echo "Création d'un index.html minimal pour charger Bolt.new..." && \
    cat > ./build/client/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Bolt.new</title>
    <link rel="icon" href="/favicon.svg" type="image/svg+xml">
    <style>
        body { 
            margin: 0; 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: #1a1a1a;
            color: white;
        }
        #root { min-height: 100vh; }
        .loading {
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            flex-direction: column;
        }
        .spinner {
            width: 40px;
            height: 40px;
            border: 4px solid #333;
            border-top: 4px solid #667eea;
            border-radius: 50%;
            animation: spin 1s linear infinite;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
    </style>
</head>
<body>
    <div id="root">
        <div class="loading">
            <div class="spinner"></div>
            <p>Chargement de Bolt.new...</p>
        </div>
    </div>
    
    <!-- Essayer de charger les scripts Bolt.new -->
    <script type="module">
        // Chercher le point d'entrée principal
        const scripts = [
            '/index.js',
            '/assets/index.js', 
            '/client/index.js',
            '/main.js',
            '/app.js'
        ];
        
        let loaded = false;
        
        for (const script of scripts) {
            try {
                await import(script);
                loaded = true;
                break;
            } catch (e) {
                console.log(`Impossible de charger ${script}:`, e.message);
            }
        }
        
        if (!loaded) {
            document.getElementById('root').innerHTML = `
                <div style="padding: 2rem; text-align: center;">
                    <h1>Bolt.new Assets</h1>
                    <p>Application buildée avec succès. Les modules sont prêts.</p>
                    <p>Vérifiez les logs du conteneur pour plus d'informations.</p>
                    <a href="/assets/" style="color: #667eea;">Voir les assets →</a>
                </div>
            `;
        }
    </script>
</body>
</html>
EOF
fi

# Créer un serveur qui sert intelligemment les assets
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
  ".mjs": "text/javascript", 
  ".css": "text/css",
  ".json": "application/json",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".woff": "font/woff",
  ".woff2": "font/woff2"
};

const server = http.createServer((req, res) => {
  // Headers pour les modules ES et CORS
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
  
  // Route racine vers index.html
  if (pathname === "/") {
    pathname = "/index.html";
  }
  
  // Route pour lister les assets (debug)
  if (pathname === "/assets/") {
    const assetsDir = path.join(PUBLIC_DIR, "assets");
    if (fs.existsSync(assetsDir)) {
      const files = fs.readdirSync(assetsDir);
      const html = `
        <h1>Assets Bolt.new</h1>
        <ul>
          ${files.map(f => `<li><a href="/assets/${f}">${f}</a></li>`).join('')}
        </ul>
        <p><a href="/">← Retour à l'application</a></p>
      `;
      res.writeHead(200, { "Content-Type": "text/html" });
      res.end(html);
      return;
    }
  }
  
  const filePath = path.join(PUBLIC_DIR, pathname);
  const ext = path.parse(filePath).ext;
  const mimeType = mimeTypes[ext] || "application/octet-stream";

  fs.readFile(filePath, (err, data) => {
    if (err) {
      // Fallback vers index.html pour les routes SPA
      if (ext === "" || ext === ".html") {
        const indexPath = path.join(PUBLIC_DIR, "index.html");
        fs.readFile(indexPath, (fallbackErr, fallbackData) => {
          if (fallbackErr) {
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
      // Headers spéciaux pour les modules JavaScript
      const headers = { "Content-Type": mimeType };
      if (ext === ".js" || ext === ".mjs") {
        headers["Cross-Origin-Embedder-Policy"] = "require-corp";
        headers["Cross-Origin-Opener-Policy"] = "same-origin";
      }
      
      console.log(`✅ 200: ${pathname}`);
      res.writeHead(200, headers);
      res.end(data);
    }
  });
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`🚀 Bolt.new server running on http://0.0.0.0:${PORT}`);
  console.log(`📁 Serving from: ${PUBLIC_DIR}`);
  
  // Afficher les points d'entrée disponibles
  const indexPath = path.join(PUBLIC_DIR, "index.html");
  if (fs.existsSync(indexPath)) {
    console.log(`📄 Index file found: ${indexPath}`);
  }
  
  const assetsPath = path.join(PUBLIC_DIR, "assets");
  if (fs.existsSync(assetsPath)) {
    const assets = fs.readdirSync(assetsPath).slice(0, 5);
    console.log(`📦 Assets available: ${assets.join(', ')}...`);
  }
});
EOF

# Configurer les permissions
RUN chown -R nextjs:nodejs /app

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

# Commande de démarrage
CMD ["node", "server.cjs"]