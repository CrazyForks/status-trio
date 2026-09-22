# Version %VERSION% (build %BUILD%)

## Aspect verre natif sous macOS 26
- La fenêtre contextuelle utilise désormais le matériau Liquid Glass de macOS 26 et s’accorde avec les menus du système ; des réglages comme Réduire la transparence s’appliquent toujours.
- macOS 15 à 25 conservent leur apparence actuelle ; la version minimale du système reste inchangée, personne n’a besoin de mettre à jour macOS pour continuer à utiliser Status Trio.

## Le Bluetooth fonctionne mieux
- Le panneau d’état liste désormais vos périphériques jumelés dès l’ouverture : touchez-en un pour le connecter, touchez-le à nouveau pour le déconnecter ; déconnecter un clavier ou une souris demande d’abord confirmation, dans la ligne elle-même.
- Faites glisser les périphériques dans Réglages pour modifier leur ordre ; les périphériques connectés apparaissent toujours en premier.
- Les niveaux de batterie Bluetooth s’affichent désormais par défaut, sans interrupteur à activer.

## Le changement de Wi-Fi reste dans le système
- L’app ne rejoint plus les réseaux à votre place : toucher un réseau ouvre le panneau Wi-Fi des Réglages Système, où vous effectuez le changement.
- Status Trio ne lit ni ne stocke plus les mots de passe Wi-Fi.
- Une entrée de mot de passe enregistrée par une version antérieure peut encore se trouver dans votre trousseau, mais elle n’est plus utilisée.
- Voir vos réseaux, les détails du signal et l’interrupteur Wi-Fi fonctionnent comme avant.

## Utilise moins d’énergie
- Beaucoup moins de travail en arrière-plan : le Bluetooth n’interroge plus les périphériques sur un minuteur, la recherche Wi-Fi s’arrête quand vous quittez la page, et l’actualisation de secours est passée de 5 à 15 secondes.
- Les mises à jour arrivent toujours dès que le système signale un changement, et votre intervalle d’actualisation reste inchangé.

## Correctifs et améliorations
- Cliquer sur l’icône de la barre des menus ouvre désormais le panneau même lorsqu’une autre app est en plein écran.
- Les relevés de puissance des détails de la batterie sont plus précis : « Puissance système (estimée) » sur secteur, « Décharge batterie (estimée) » sur batterie.
- Une autorisation de localisation refusée pour le Wi-Fi peut être redemandée au lieu de rester bloqué sur des noms de réseaux indisponibles.
- Avec Réduire les mouvements activé dans le système, l’interface des réglages ne joue plus d’animations de transition.

## Remerciements
- Merci à @hhh2210 pour ses contributions de code à cette version.
