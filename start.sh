#!/bin/bash

# Script de démarrage start.sh
set -e

echo "Démarrage de l'application bolt.new..."

# Vérifier si wrangler fonctionne
if wrangler --version > /dev/null 2>&1; then
    echo "Wrangler disponible, démarrage avec wrangler..."
    bindings=$(./bindings.sh)
    exec wrangler pages dev ./build/client $bindings --port 8787 --host 0.0.0.0
else
    echo "Wrangler non disponible, démarrage avec serveur statique..."
    exec serve -s ./build/client -l 8787
fi