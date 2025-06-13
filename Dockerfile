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

# Stage pour le build - utiliser une image standard au lieu d'Alpine
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

# Installer pnpm et un serveur HTTP simple
RUN npm install -g pnpm@9.4.0 serve

WORKDIR /app

# Copier les fichiers nécessaires depuis le builder
COPY --from=builder --chown=nextjs:nodejs /app/build ./build
COPY --from=builder --chown=nextjs:nodejs /app/package.json ./package.json
COPY --from=builder --chown=nextjs:nodejs /app/pnpm-lock.yaml ./pnpm-lock.yaml

# Copier le fichier .env s'il existe, sinon créer un fichier vide
COPY --from=builder /app/.env* ./
RUN [ ! -f .env ] && touch .env || true

# Installer seulement les dépendances de production (sans wrangler pour éviter workerd)
RUN pnpm install --prod --frozen-lockfile --ignore-scripts

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

# Commande de démarrage avec serveur simple
CMD ["serve", "-s", "./build/client", "-l", "8787"]