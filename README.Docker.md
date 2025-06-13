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
# Copiez le fichier d'exemple
cp .env.example .env.local

# Éditez le fichier avec vos valeurs
echo "ANTHROPIC_API_KEY=your_anthropic_api_key_here" > .env.local
```

### 2. Démarrage avec Docker Compose

```bash
# Construire et démarrer l'application
docker-compose up --build -d

# Voir les logs
docker-compose logs -f

# Arrêter l'application
docker-compose down
```

### 3. Accès à l'application

L'application sera disponible sur : **http://localhost:8787**

## 🔧 Commandes Docker utiles

### Construction manuelle

```bash
# Construire l'image
docker build -t bolt-app .

# Démarrer le conteneur
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
docker logs bolt-container

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

Le Dockerfile utilise une approche multi-stage pour optimiser la taille de l'image finale :

1. **Stage `base`** : Configuration de base avec Node.js et pnpm
2. **Stage `deps`** : Installation des dépendances
3. **Stage `builder`** : Construction de l'application
4. **Stage `runner`** : Image de production optimisée

### Sécurité

- Utilisation d'un utilisateur non-root (`nextjs:nodejs`)
- Image Alpine Linux légère
- Exclusion des fichiers sensibles via `.dockerignore`

## 🔍 Health Checks

L'application inclut des health checks automatiques :

```bash
# Vérifier le statut de santé
docker inspect --format='{{.State.Health.Status}}' bolt-container
```

## 🌍 Variables d'environnement

Variables requises dans `.env.local` :

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
# Pour la production
docker-compose -f docker-compose.yml up -d
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
```

## 🐛 Dépannage

### Problèmes courants

1. **Port déjà utilisé**
   ```bash
   # Changer le port dans docker-compose.yml
   ports:
     - "8788:8787"  # Utiliser 8788 au lieu de 8787
   ```

2. **Problème de permissions**
   ```bash
   # Vérifier les permissions du script
   chmod +x bindings.sh
   ```

3. **Variables d'environnement manquantes**
   ```bash
   # Vérifier que .env.local existe et contient ANTHROPIC_API_KEY
   cat .env.local
   ```

### Logs de débogage

```bash
# Logs détaillés
docker-compose logs -f bolt-app

# Logs avec timestamps
docker-compose logs -t bolt-app
```

## 📊 Monitoring

### Métriques de base

```bash
# Utilisation des ressources
docker stats bolt-container

# Informations détaillées
docker inspect bolt-container
```

### Health check manuel

```bash
# Test de l'endpoint
curl -f http://localhost:8787/

# Avec timeout
timeout 5 curl -f http://localhost:8787/ || echo "Service indisponible"
```

## 🔄 Mise à jour

```bash
# Reconstruire avec les dernières modifications
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

---

## 📞 Support

Si vous rencontrez des problèmes :

1. Vérifiez les logs : `docker-compose logs -f`
2. Vérifiez les variables d'environnement
3. Assurez-vous que le port 8787 est libre
4. Consultez la documentation principale dans `README.md`