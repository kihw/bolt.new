# Base image avec pnpm et dépendances natives
FROM node:20.15.1-alpine AS base

RUN apk add --no-cache \
    libc6-compat \
    python3 \
    make \
    g++ \
    && ln -sf python3 /usr/bin/python

RUN npm install -g pnpm@9.4.0

WORKDIR /app

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

# Copier le reste des fichiers source
COPY . .

# Créer un utilisateur non-root
RUN addgroup -g 1001 -S nodejs && adduser -S nextjs -u 1001 -G nodejs \
    && chown -R nextjs:nodejs /app

USER nextjs

EXPOSE 8787

ENV NODE_ENV=development
ENV PORT=8787

# Healthcheck de base
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:8787/ || exit 1

CMD ["node", "server.cjs"]
