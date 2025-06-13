# 🐳 Docker Setup pour Bolt.new

Ce guide vous explique comment containeriser et déployer l'application Bolt.new avec Docker.

## 📋 Prérequis

- Docker installé sur votre système
- Docker Compose (inclus avec Docker Desktop)
- Une clé API Anthropic

## 🚀 Démarrage rapide

### 1. Configuration des variables d'environnement

Créez un fichier `.env.local` à la racine du projet :

```bash
# Créez le fichier avec votre clé API
echo "ANTHROPIC_API_KEY=your_anthropic_api_key_here" > .env.local

# Optionnel: ajoutez d'autres variables
echo "VITE_LOG_LEVEL=info" >> .env.local
echo "NODE_ENV=production" >> .env.local
```

### 2. Démarrage avec Docker Compose

```bash
# Production - Construire et démarrer l'application
docker-compose up --build -d

# Développement - Avec hot-reload
docker-compose --profile dev up --build -d

# Voir les logs
docker-compose logs -f bolt-app

# Arrêter l'application
docker-compose down
```

### 3. Accès à l'application

- **Production** : http://localhost:8787
- **Développement** : http://localhost:5173

## 🔧 Commandes Docker utiles

### Construction manuelle

```bash
# Construire l'image de production
docker build -t bolt-app .

# Construire l'image de développement
docker build -f Dockerfile.dev -t bolt-app-dev .

# Démarrer le conteneur de production
docker run -d \
  --name bolt-container \
  -p 8787:8787 \
  --env-file .env.local \
  bolt-app
```

### Gestion des conteneurs

```bash
# Voir les conteneurs en cours d'exécution
docker ps

# Voir les logs d'un conteneur
docker logs -f bolt-container

# Entrer dans le conteneur
docker exec -it bolt-container sh

# Arrêter et supprimer le conteneur
docker stop bolt-container
docker rm bolt-container
```

### Nettoyage

```bash
# Supprimer l'image
docker rmi bolt-app

# Nettoyer les images non utilisées
docker image prune

# Nettoyage complet
docker system prune -a
```

## 🏗️ Architecture Docker

### Dockerfile multi-stage

Le Dockerfile utilise une approche multi-stage pour optimiser la taille et résoudre les problèmes de compatibilité :

1. **Stage `base`** : Configuration de base avec Node.js Alpine et dépendances système
2. **Stage `deps`** : Installation des dépendances
3. **Stage `builder`** : Construction avec Node.js standard (pour éviter les problèmes de binaires natifs)
4. **Stage `runner`** : Image de production Alpine optimisée

### Résolution des problèmes de build

- **Problème workerd** : Utilisation de Node.js standard pour le build au lieu d'Alpine
- **Binaires natifs** : Installation des dépendances système nécessaires
- **Compatibilité** : Ajout de `libc6-compat` pour la compatibilité des binaires

## 🔍 Health Checks

L'application inclut des health checks automatiques :

```bash
# Vérifier le statut de santé
docker inspect --format='{{.State.Health.Status}}' bolt-container

# Logs des health checks
docker inspect --format='{{range .State.Health.Log}}{{.Output}}{{end}}' bolt-container
```

## 🌍 Variables d'environnement

Variables dans `.env.local` :

```env
# Obligatoire
ANTHROPIC_API_KEY=your_key_here

# Optionnelles
NODE_ENV=production
PORT=8787
VITE_LOG_LEVEL=info
```

## 🚀 Déploiement en production

### Avec Docker Compose

```bash
# Production
docker-compose up -d

# Avec rebuild
docker-compose up --build -d

# Scaling (plusieurs instances)
docker-compose up -d --scale bolt-app=3
```

### Avec orchestrateurs

Le conteneur est compatible avec :
- Kubernetes
- Docker Swarm
- AWS ECS
- Google Cloud Run
- Azure Container Instances

### Exemple Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bolt-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: bolt-app
  template:
    metadata:
      labels:
        app: bolt-app
    spec:
      containers:
      - name: bolt-app
        image: bolt-app:latest
        ports:
        - containerPort: 8787
        env:
        - name: ANTHROPIC_API_KEY
          valueFrom:
            secretKeyRef:
              name: bolt-secrets
              key: anthropic-api-key
        - name: NODE_ENV
          value: "production"
        livenessProbe:
          httpGet:
            path: /
            port: 8787
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 8787
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: bolt-service
spec:
  selector:
    app: bolt-app
  ports:
  - port: 80
    targetPort: 8787
  type: LoadBalancer
```

## 🐛 Dépannage

### Problèmes courants

1. **Erreur workerd/binaires natifs**
   ```bash
   # Le nouveau Dockerfile résout ce problème en utilisant Node.js standard pour le build
   docker-compose build --no-cache
   ```

2. **Port déjà utilisé**
   ```bash
   # Changer le port dans docker-compose.yml
   ports:
     - "8788:8787"  # Utiliser 8788 au lieu de 8787
   ```

3. **Problème de permissions**
   ```bash
   # Vérifier les permissions du script
   chmod +x bindings.sh
   ```

4. **Variables d'environnement manquantes**
   ```bash
   # Vérifier que .env.local existe et contient ANTHROPIC_API_KEY
   cat .env.local
   ```

5. **Problèmes de mémoire**
   ```bash
   # Augmenter la mémoire Docker si nécessaire
   docker run --memory=4g bolt-app
   ```

### Logs de débogage

```bash
# Logs détaillés avec timestamps
docker-compose logs -t -f bolt-app

# Logs du build
docker-compose build --progress=plain

# Logs système du conteneur
docker exec bolt-container dmesg
```

### Tests de connectivité

```bash
# Test de l'endpoint
curl -f http://localhost:8787/

# Test avec timeout
timeout 5 curl -f http://localhost:8787/ || echo "Service indisponible"

# Test depuis l'intérieur du conteneur
docker exec bolt-container curl -f http://localhost:8787/
```

## 📊 Monitoring

### Métriques de base

```bash
# Utilisation des ressources
docker stats bolt-container

# Informations détaillées
docker inspect bolt-container

# Logs en temps réel
docker logs -f bolt-container
```

### Monitoring avancé

```bash
# Avec docker-compose
docker-compose top

# Métriques système
docker exec bolt-container top
docker exec bolt-container free -h
docker exec bolt-container df -h
```

## 🔄 Mise à jour

```bash
# Mise à jour complète
docker-compose down
docker-compose pull
docker-compose build --no-cache
docker-compose up -d

# Mise à jour rapide (sans rebuild complet)
docker-compose build
docker-compose up -d
```

## 🎯 Optimisations

### Performance

```bash
# Utiliser BuildKit pour des builds plus rapides
export DOCKER_BUILDKIT=1
docker-compose build

# Cache des layers
docker build --cache-from bolt-app .
```

### Sécurité

```bash
# Scanner l'image pour les vulnérabilités
docker scout cves bolt-app

# Utiliser un utilisateur non-root (déjà configuré)
docker exec bolt-container whoami  # Devrait retourner 'nextjs'
```

---

## 📞 Support

Si vous rencontrez des problèmes :

1. Vérifiez les logs : `docker-compose logs -f`
2. Vérifiez les variables d'environnement : `cat .env.local`
3. Testez la connectivité : `curl http://localhost:8787/`
4. Consultez la documentation principale dans `README.md`
5. Vérifiez les issues GitHub pour des problèmes similaires

### Commandes de diagnostic

```bash
# Diagnostic complet
echo "=== Docker Info ==="
docker info

echo "=== Container Status ==="
docker ps -a

echo "=== Container Logs ==="
docker-compose logs --tail=50 bolt-app

echo "=== Health Check ==="
docker inspect --format='{{.State.Health.Status}}' bolt-container

echo "=== Environment ==="
docker exec bolt-container env | grep -E "(NODE_ENV|PORT|ANTHROPIC)"
```