# JARVIS HUD local — prototype Realtime

HUD local voix-à-voix : le navigateur capte le micro et joue la réponse directement via WebRTC. Le serveur local crée une clé de session éphémère ; la clé API permanente reste dans `.env` sur le PC.

## Démarrage Windows

1. Installez Node.js LTS si nécessaire.
2. Double-cliquez `lancer-jarvis.cmd`.
3. Au premier lancement, le script crée `.env` et l’ouvre dans le Bloc-notes. Collez-y votre clé API OpenAI Platform après `OPENAI_API_KEY=`. Enregistrez, fermez, puis relancez le script.
4. Cliquez sur le noyau et autorisez le microphone dans Chrome ou Edge. Cliquez sur **Terminer la session** pour couper le micro et la connexion.

Adresse locale : http://127.0.0.1:4175

## Coûts et limites

La Realtime API est facturée séparément de l’abonnement ChatGPT/Codex, selon l’usage audio et le modèle. Aucune session API n’est créée avant le clic sur le noyau. Le prototype ne se connecte pas à Base44, Telegram, Gmail, Drive, Calendar ou n8n ; il ne peut pas encore lancer d’actions. Les demandes sont traitées par la session vocale OpenAI. Le raccord à l’orchestrateur Base44 viendra dans une étape distincte avec validations côté serveur.

Le HUD reste local et s’arrête quand le processus Node est arrêté. Le micro s’arrête à la fermeture de session ou de page. Le navigateur doit rester ouvert pendant la conversation.

## Clé API

Créez une clé sur la plateforme API OpenAI et enregistrez-la uniquement dans le fichier `.env` local. Ne l’envoyez ni dans le chat ni dans GitHub. Le fichier `.env` est ignoré par Git. Si la clé a déjà été collée ailleurs, révoquez-la et créez-en une nouvelle.

## Vérifications

`npm test` exécute les contrôles locaux sans clé API et sans appel payant. Le test de conversation réel est manuel et consomme l’usage API correspondant.

## État du prototype

- HUD SF voix-first, états attente/écoute/réflexion/parole/erreur, plein écran et mobile.
- Conversation Realtime directe en français, VAD et interruption vocale fournies par le flux Realtime.
- Réponse vocale native du modèle, avec transcription affichée.
- Pas de mémoire persistante ni de continuité avec Telegram pour l’instant.
- Pas de fonctions/outils branchés : le modèle ne peut pas lire les comptes ou effectuer des tâches.
- Le serveur écoute uniquement sur `127.0.0.1` et limite les créations de session.
