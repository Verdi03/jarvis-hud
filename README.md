# JARVIS HUD — prototype privé

Interface vocale de test pour le Superagent JARVIS de Base44.

## Ce qui fonctionne

- HUD animé avec entrée vocale via Web Speech API du navigateur.
- Synthèse française Kokoro via la voix `ff_siwis`.
- Backend FastAPI lancé avec Docker Compose.
- Accès aux routes API fermé tant que `JARVIS_ACCESS_PASSWORD` n’est pas défini.

## État des connexions

Le Superagent, Gmail et n8n ne sont pas configurés dans cette branche. Le code ne contient aucun jeton ni secret. La route de chat ne doit pas être considérée comme intégrée avant un test réel du contrat de l’API Superagent.

Les routes de création de brouillon Gmail et de déclenchement n8n restent bloquées par défaut. Elles ne devront être activées qu’après ajout d’une validation humaine côté interface et côté serveur.

## Démarrage du prototype

```sh
docker compose -f docker-compose.base44.yml up -d --build
```

Le service Kokoro tourne dans le conteneur de l’environnement qui exécute Compose. Cela ne signifie pas qu’il est installé sur le PC Windows de l’utilisateur.

## Secret d’accès

Dans les secrets de l’application Base44, crée un secret `JARVIS_ACCESS_PASSWORD` avec une valeur longue, unique et aléatoire. Saisis cette même valeur dans le panneau de déverrouillage du HUD. Ne l’ajoute jamais au dépôt Git et ne la partage pas dans le chat.

Sans ce secret, les appels chat, audio, Gmail et n8n renvoient une erreur et restent inaccessibles.

## Règles

- Aucun LLM local et aucun second cerveau.
- Pas d’envoi, suppression ou modification de mail sans validation explicite.
- Pas de déclenchement n8n sans validation explicite.
- Aucune publication de cette version n’est effectuée par ces instructions.
