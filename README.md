# JARVIS HUD

Interface vocale de démonstration, prévue pour être intégrée à Base44.

## État de cette version

- Le noyau animé et l'interface sont présents.
- Le navigateur peut demander l'accès au micro et reconnaître une phrase en français.
- La réponse est simulée dans le navigateur et lue avec la synthèse vocale disponible.
- **Aucun échange n'est envoyé au Superagent Base44.**
- Aucun jeton, mot de passe ou secret n'est inclus dans le dépôt.

## Aperçu

Ouvrir `index.html` dans Chrome ou Edge, autoriser le micro, puis cliquer sur le noyau et parler. La synthèse vocale dépend des voix installées dans le navigateur.

## Étape d'intégration à faire dans Base44

Le HUD devra appeler une fonction serveur Base44 qui transmet la demande au Superagent existant. Le jeton du Superagent devra être enregistré uniquement dans les secrets serveur de Base44, jamais dans ce dépôt ni dans le navigateur. Le site ne devra afficher « connecté » qu'après un test réel réussi.

Cette version ne contient pas encore cette fonction serveur. Elle ne doit donc pas être considérée comme un JARVIS opérationnel.
