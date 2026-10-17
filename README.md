# JARVIS HUD — prototype privé

Interface vocale de test pour le Superagent JARVIS de Base44.

## Ce qui fonctionne

- HUD animé avec entrée vocale via Web Speech API du navigateur.
- Synthèse française Kokoro via la voix `ff_siwis`.
- Backend FastAPI lancé avec Docker Compose.
- Accès aux routes API fermé tant que `JARVIS_ACCESS_PASSWORD` n’est pas défini.

## État des connexions

Le HUD utilise maintenant le contrat officiel de l’API Superagents : créer/récupérer la conversation principale, puis envoyer le champ `content`. Le jeton reste côté serveur. La connexion réelle n’a pas encore été testée dans cette branche : ajouter `BASE44_SUPERAGENT_TOKEN` aux secrets Base44, puis faire un unique message fictif après vérification des crédits inclus. L’API Superagents est actuellement en bêta et consomme les crédits de l’espace de travail.

Les routes de création de brouillon Gmail et de déclenchement n8n restent bloquées par défaut. Elles ne devront être activées qu’après ajout d’une validation humaine côté interface et côté serveur.

## Démarrage du prototype

```sh
docker compose -f docker-compose.base44.yml up -d --build
```

Le service Kokoro tourne dans le conteneur de l’environnement qui exécute Compose. Cela ne signifie pas qu’il est installé sur le PC Windows de l’utilisateur.

## Secret d’accès

Dans les secrets de l’application Base44, conserve `JARVIS_ACCESS_PASSWORD` pour l’accès privé et ajoute `BASE44_SUPERAGENT_TOKEN` pour l’API de Jarvis. Saisis le jeton uniquement dans les secrets Base44, jamais dans le HUD, le dépôt Git ou le chat. L’identifiant du Superagent existant est configuré côté serveur.

Sans ce secret, les appels chat, audio, Gmail et n8n renvoient une erreur et restent inaccessibles.

## Règles

- Aucun LLM local et aucun second cerveau.
- Pas d’envoi, suppression ou modification de mail sans validation explicite.
- Pas de déclenchement n8n sans validation explicite.
- Aucune publication de cette version n’est effectuée par ces instructions.
