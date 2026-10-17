# JARVIS HUD — maquette vocale V1

Prototype d’interface voix-first pour valider l’expérience visuelle de JARVIS avant les intégrations.

## Ce que cette maquette permet

- Présenter un noyau central sobre, immobile au repos, avec des états d’écoute.
- Demander l’accès au microphone et afficher le niveau sonore réel.
- Afficher la dictée française locale du navigateur pour vérifier le parcours vocal.
- Ouvrir des panneaux contextuels d’activité, d’historique et de validation.
- Adapter l’interface au plein écran et au mobile.

## Limites assumées

- Aucun cerveau IA n’est connecté dans cette version.
- Aucun son de réponse n’est généré.
- Aucune donnée n’est envoyée à Base44, OpenAI, Gmail, Google Drive, Calendar, Telegram ou n8n.
- Les cartes de tâche et de validation sont des exemples fictifs. Les boutons d’approbation sont volontairement désactivés.
- La dictée vocale dépend de Chrome/Edge et de la permission micro du navigateur.

La maquette ne doit pas être présentée comme un Jarvis connecté. Les connexions et les actions réelles viendront après validation de l’interface et du parcours vocal.

## Décision d’architecture à préparer

- HUD : interface web voix-first, une seule entrée conversationnelle, panneaux contextuels plutôt qu’un tableau de bord permanent.
- Cerveau vocal visé : API OpenAI Realtime, à tester séparément avec une clé conservée côté serveur.
- Automatisations : projet n8n Cloud JARVIS Personnel.
- Télégramme et HUD devront partager une même mémoire conversationnelle lors de leur raccordement.
- Codex sert à construire et maintenir le logiciel ; il n’est pas le cerveau d’exécution de JARVIS.
- Aucun VPS, publication publique ni nouvelle connexion n’est effectué par cette maquette.
