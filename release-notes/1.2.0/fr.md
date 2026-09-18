# Version %VERSION% (build %BUILD%)

## Points forts : audio Bluetooth
- La ligne Bluetooth de la fenêtre contextuelle affiche désormais l’état en direct : le nom des appareils connectés et, pour les AirPods, la batterie gauche/droite/boîtier. Les autres appareils n’affichent que leur nom.
- Pendant la lecture audio en Bluetooth, l’icône réseau centrale peut adopter le glyphe de l’appareil correspondant (AirPods, casque, enceinte, etc.) et s’afficher en bleu, les points ou l’arc de volume passant également au bleu, pour identifier la sortie active d’un coup d’œil.
- Nouvelle page « Réglages > Bluetooth » : des interrupteurs pour remplacer l’icône réseau, utiliser le volume Bluetooth en bleu, donner la priorité aux erreurs réseau et afficher le niveau de batterie Bluetooth, ainsi qu’une taille d’icône Bluetooth de 100 % à 180 %.
- Correction : un appareil renommé dans Réglages Système affichait toujours son ancien nom.
- Correction : le niveau de batterie Bluetooth restait sur « Indisponible » après un aller-retour entre le résumé et la page de l’appareil.

## Détails de la batterie
- Un clic sur la ligne de batterie de la fenêtre contextuelle ouvre une page dédiée avec la puissance nominale de l’adaptateur, le temps restant, le mode Économie d’énergie, la tension, le courant, l’heure d’échantillonnage et le nombre de cycles.
- Nouvelle estimation de la puissance nette de la batterie : en charge, elle est indiquée en vert « En charge (estimation) » ; en décharge, « Décharge (estimation) ».
- Ces valeurs sont des estimations au mieux, pas la consommation totale du Mac. Après un changement de source d’alimentation, macOS peut mettre jusqu’à une minute à signaler de nouvelles valeurs ; pendant ce temps, l’affichage indique « Échantillonnage » au lieu de « Indisponible ».

## Résumé Wi-Fi
- Lorsque le Wi-Fi est connecté, la fenêtre contextuelle utilise le nom du réseau (SSID) comme titre et affiche en dessous la bande et la puissance du signal, par exemple 5 GHz / -52 dBm.
- Les mesures manquantes sont omises plutôt qu’affichées à 0 ; Ethernet, hors ligne et les autres chemins non Wi-Fi ne les affichent pas.

## Découvrez votre icône
- Une nouvelle installation ouvre le guide « Découvrez votre icône » au premier lancement. Sélectionnez l’arc de batterie, le glyphe réseau central ou l’indicateur de volume pour découvrir leur signification ; l’explication du volume suit votre réglage actuel en points ou en arc.
- Le guide comprend une galerie de combinaisons d’états courantes : en charge, batterie faible, Ethernet, pas d’Internet et son coupé, partage de connexion avec Économie d’énergie, Wi-Fi faible à 25 % de volume, Wi-Fi désactivé, casque Bluetooth, AirPods et Wi-Fi avec volume bleu.
- La mise à jour vers cette version, un redémarrage et les installations existantes ne l’ouvrent pas automatiquement. Vous pouvez le rouvrir à tout moment depuis « Réglages », « Icône de l’app », « Ouvrir le guide ».

## Volume
- Nouvel interrupteur « Défilement naturel » : activé, le défilement vers le haut à la souris ou au trackpad augmente le volume, indépendamment de la préférence système de défilement naturel ; désactivé, le volume suit le sens de défilement du système.
- Nouveau choix « Zone de réglage » : défiler n’importe où dans le panneau, ou uniquement sur le contrôle du volume.
- Si le défilement vers le haut baisse encore le volume avec cette option, un utilitaire de défilement tel que MOS, Scroll Reverser ou LinearMouse inverse les événements ; ajoutez Status Trio à sa liste d’exceptions ou d’ignorés.

## Réglages et apparence
- Le style de volume (points ou arc), le placement de l’icône et l’épaisseur du trait de l’anneau sont désormais des sélecteurs visuels : la sélection est marquée par un anneau concentrique et l’aperçu s’affiche dans la carte.
- Nouveau réglage « Épaisseur du trait de l’anneau » : fin, standard ou épais, appliqué à l’anneau extérieur de la batterie, à l’arc de volume et aux points de volume pour un rendu plus net sur les écrans Retina.
- Choisir « Barre des menus uniquement » avertit désormais que l’icône du Dock disparaît à la fermeture de la fenêtre des réglages.
- Les commandes audio et le pied de page de la fenêtre contextuelle sont plus compacts : l’interrupteur de sourdine passe dans l’en-tête, les icônes de haut-parleur en double sont supprimées, le nom du périphérique de sortie devient un sous-titre et une entrée « Autres actions » est ajoutée.
- Les lignes de la fenêtre contextuelle partagent désormais une taille d’icône et un espacement uniques ; l’icône par défaut de la barre des menus est de 24 pt et l’échelle du symbole Wi-Fi est de 160 % par défaut.

## Corrections
- Modifier une option d’icône redessine désormais immédiatement les icônes de la barre des menus et du Dock, sans décalage.
- L’aperçu de la barre des menus dans les réglages reste épinglé en haut de la page au lieu de défiler avec les options.
- Cliquer sur un réseau Wi-Fi connu ouvre directement les réglages Wi-Fi du système.
- Le symbole Wi-Fi est centré dans l’icône d’état (issue #30).

## Remerciements
- Merci à @ReffWu et @hhh2210 pour leurs contributions de code à cette version.
