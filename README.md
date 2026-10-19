# JARVIS HUD — voix Realtime locale

Cette branche remplace la démo à réponses simulées par une première connexion vocale Realtime depuis Windows.

## Lancer sur Windows, sans Node.js

1. Copier .env.example vers .env.
2. Ajouter sa clé OpenAI API à OPENAI_API_KEY dans .env. Ne jamais committer ce fichier ni partager la clé.
3. Ouvrir PowerShell dans ce dossier et lancer :
   powershell -ExecutionPolicy Bypass -File .\serveur-jarvis.ps1
4. Ouvrir http://127.0.0.1:4173 dans Chrome ou Edge, puis cliquer DÉMARRER et autoriser le microphone.

La passerelle n'écoute que sur 127.0.0.1 et ne sert que index.html. La clé permanente reste dans le processus PowerShell ; le navigateur reçoit uniquement un secret Realtime temporaire.

## Ce qui est dans cette branche

- HUD sombre/cyan avec une seule interaction vocale.
- Audio bidirectionnel WebRTC, détection de parole, interruption, transcription et contrôle du micro.
- Animation pilotée par le son réel du micro ou de la réponse, arrêt au silence.
- Petit serveur Windows PowerShell, sans Node.js ni paquet externe.
- Aucune réponse de démonstration, aucun appel au Superagent Base44.

## Test MCP fictif

Le HUD ne propose actuellement qu'un outil de test fictif. Il envoie une requête Gmail fixe (sujet impossible à confondre avec une demande réelle) au workflow MCP JARVIS. Le serveur local renvoie au modèle Realtime uniquement un reçu succès/échec ; aucun contenu Gmail n'est transmis à OpenAI.

Pour activer ce test sur ton PC, complète dans `.env` :
- `N8N_MCP_URL` : l'URL MCP affichée par le trigger du workflow publié.
- `N8N_MCP_AUTH_HEADER` : le nom du header configuré dans le credential n8n.
- `N8N_MCP_AUTH_VALUE` : la valeur exacte de ce header. Elle reste dans le fichier local ignoré par Git ; ne la colle jamais dans le chat ni dans GitHub. Si la valeur du credential n'a pas été conservée, crée un credential Header Auth de remplacement dans n8n et remplace le credential du trigger avant le test.

Une fois les trois champs renseignés, relance `lancer-jarvis.cmd`, démarre la voix et demande à Jarvis : « Lance le test fictif du connecteur MCP et dis-moi seulement s'il a réussi. » Le test ne doit lire aucun résultat personnel ni effectuer de modification.

## Ce qui n'est pas encore intégré

Cette première étape est la conversation vocale uniquement. Elle ne lit pas encore Gmail, Drive ou Calendar, ne crée pas de tâche, n'appelle pas n8n, ne déclenche pas d'agent Meta et ne se connecte pas à Telegram. Les outils, le brief, la mémoire partagée et les validations sont décrits dans le plan privé fourni séparément ; ils devront être ajoutés avant de présenter Jarvis comme entièrement opérationnel.

L'API OpenAI est facturée à l'usage séparément de ChatGPT/Codex. Utilise un budget et des alertes sur OpenAI Platform. Ce code n'a pas été testé physiquement sur Windows avec une clé API réelle.
