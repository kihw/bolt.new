# Multi-stage build pour optimiser la taille de l'image finale
FROM node:20.15.1-alpine AS base

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
FROM base AS builder
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Build de l'application
RUN pnpm run build

# Stage de production
FROM node:20.15.1-alpine AS runner

# Installer pnpm dans l'image finale
RUN npm install -g pnpm@9.4.0

# Créer un utilisateur non-root pour la sécurité
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

WORKDIR /app

# Copier les fichiers nécessaires depuis le builder
COPY --from=builder --chown=nextjs:nodejs /app/build ./build
COPY --from=builder --chown=nextjs:nodejs /app/package.json ./package.json
COPY --from=builder --chown=nextjs:nodejs /app/pnpm-lock.yaml ./pnpm-lock.yaml
COPY --from=builder --chown=nextjs:nodejs /app/functions ./functions
COPY --from=builder --chown=nextjs:nodejs /app/wrangler.toml ./wrangler.toml
COPY --from=builder --chown=nextjs:nodejs /app/bindings.sh ./bindings.sh

# Installer seulement les dépendances de production
RUN pnpm install --prod --frozen-lockfile

# Installer wrangler globalement
RUN pnpm install -g wrangler

# Rendre le script bindings.sh exécutable
RUN chmod +x ./bindings.sh

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
CMD ["pnpm", "run", "start"]