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

# Stage de production - revenir à Alpine pour une image plus légère
FROM node:20.15.1-alpine AS runner

# Installation des dépendances système pour l'exécution
RUN apk add --no-cache \
    libc6-compat \
    curl \
    && addgroup --system --gid 1001 nodejs \
    && adduser --system --uid 1001 nextjs

# Installer pnpm et configurer le répertoire global
RUN npm install -g pnpm@9.4.0 \
    && mkdir -p /home/nextjs/.local/share/pnpm \
    && chown -R nextjs:nodejs /home/nextjs/.local

# Définir les variables d'environnement pour pnpm
ENV PNPM_HOME="/home/nextjs/.local/share/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

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

# Changer vers l'utilisateur non-root avant d'installer wrangler
USER nextjs

# Configurer pnpm pour l'utilisateur et installer wrangler
RUN pnpm setup \
    && pnpm install -g wrangler

# Rendre le script bindings.sh exécutable
USER root
RUN chmod +x ./bindings.sh
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