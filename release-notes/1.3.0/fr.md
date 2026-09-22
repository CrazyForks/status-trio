# Version %VERSION% (build %BUILD%)

## Liquid Glass natif sous macOS 26 et ultérieur
- La fenêtre contextuelle utilise désormais le matériau Liquid Glass du système au lieu de l’aspect dépoli hérité des versions précédentes de macOS, et s’accorde donc avec les menus et panneaux qui l’entourent.
- Il s’agit de l’apparence du système, et non d’un style propre à l’app : elle suit les réglages de votre système.
- macOS 15 à 25 conservent leur apparence actuelle ; la version minimale du système reste inchangée, personne n’a besoin de mettre à jour macOS pour continuer à utiliser Status Trio.

## Le panneau s’ouvre par-dessus les apps en plein écran
- Cliquer sur l’icône de la barre des menus ouvre désormais le panneau d’état même lorsqu’une autre app est en plein écran. Auparavant, il s’ouvrait derrière cette app, et le clic semblait donc sans effet.

## Actualisation en arrière-plan moins coûteuse
- L’actualisation de secours, c’est-à-dire le minuteur qui rattrape un changement que le système n’a pas poussé vers l’app, s’exécute désormais toutes les 15 secondes par défaut au lieu de toutes les 5 secondes, et macOS peut décaler ce minuteur pour qu’il se déclenche en même temps que d’autres tâches. L’icône se met toujours à jour dès que le système signale un changement.
- La batterie est vérifiée à chaque déclenchement de l’actualisation de secours. Le Wi-Fi et le volume le sont moins souvent tant que le panneau d’état et la fenêtre des Réglages sont tous deux fermés, et reviennent à votre intervalle d’actualisation dès que l’un des deux est à l’écran.
- Le curseur de l’intervalle d’actualisation descend toujours jusqu’à 5 secondes pour ceux qui veulent l’ancien rythme.
- La ligne du volume ne redessine plus le panneau d’état lorsque la valeur du volume n’a pas changé.

## Bluetooth n’interroge plus en arrière-plan
- Le panneau Bluetooth lisait autrefois la liste des périphériques jumelés toutes les 15 secondes tant que l’app était en cours d’exécution, même après la fermeture du panneau. Il s’actualise désormais lorsqu’un périphérique se connecte ou se déconnecte, et ne revient à une vérification lente que pendant qu’une vue Bluetooth est à l’écran.
- Les périphériques jumelés et les niveaux de batterie proviennent désormais d’un seul rapport système au lieu de deux, ce qui divise par deux le travail de chaque actualisation.
- Les noms des appareils proviennent toujours de la même source et le comportement des autorisations est inchangé : l’app ne demande toujours Bluetooth que lorsque vous ouvrez une vue Bluetooth.

## La recherche Wi-Fi s’arrête quand vous ne regardez plus
- La page Wi-Fi balayait autrefois chaque canal environ toutes les cinq secondes tant qu’elle était ouverte, même après votre retour au résumé. Elle scanne désormais lorsque vous ouvrez la page, lorsque vous touchez Actualiser et lorsque vous basculez l’interrupteur Wi-Fi, et conserve le dernier résultat entre-temps.
- Quitter la page Wi-Fi arrête sa boucle de scan au lieu de la laisser tourner en arrière-plan.
- Sur les Mac sans interface Wi-Fi, par exemple un Mac mini ou un Mac Studio connecté en Ethernet, l’app ne reconstruit plus sa surveillance Wi-Fi toutes les 30 secondes ; elle essaie désormais quelques fois, puis attend un réveil ou un changement de réseau.
- Rien ne change dans la liste elle-même : les mêmes réseaux, les mêmes détails et le même bouton d’actualisation manuelle.

## Le changement de Wi-Fi reste dans le système
- La fenêtre contextuelle ne rejoint plus un réseau et ne bascule plus entre eux. Choisir un réseau ouvre le panneau Wi-Fi des Réglages Système, et la page Wi-Fi l’indique au-dessus du bouton qui l’ouvre.
- Status Trio ne lit ni ne stocke plus les mots de passe Wi-Fi. L’ancien comportement ne pouvait pas être rendu fiable : macOS garde pour lui le mot de passe d’un réseau enregistré, et une copie stockée devenue obsolète aboutissait à des échecs de connexion et à des demandes répétées du trousseau, sans aucun moyen de vous signaler que le mot de passe était incorrect.
- Si vous avez coché **Mémoriser le mot de passe dans le trousseau** dans une version antérieure, cet élément du trousseau est toujours présent et n’est plus utilisé. Vous pouvez le supprimer dans Trousseau d’accès en recherchant `com.lingsmbp.StatusTrio.wifi-password`.
- Rien d’autre n’a changé sur cette page : les mêmes réseaux, les mêmes détails de signal et de liaison, le même interrupteur Wi-Fi et le même bouton qui ouvre les Réglages Système.

## Les niveaux de batterie Bluetooth sont activés par défaut
- **Afficher les niveaux de batterie Bluetooth** dans **Réglages › Bluetooth** est désormais activé par défaut : une fois le panneau Bluetooth activé, un appareil connecté indique son niveau sans avoir à activer ce réglage séparément. Le désactiver arrête toujours la lecture.
- La liste des appareils Bluetooth n’affiche plus **Indisponible** sur chaque ligne : un appareil qui n’indique pas de niveau n’affiche aucun texte de batterie, et un rapport illisible est signalé une fois sous la liste.
- Si l’accès Bluetooth a été refusé, la ligne Bluetooth vous amène maintenant directement au panneau où vous pouvez l’autoriser, au lieu de simplement vous le signaler.

## Périphériques jumelés dans le panneau d’état
- **Réglages › Bluetooth** peut désormais lister les périphériques jumelés sous la ligne Bluetooth : les premiers sont toujours visibles, les autres apparaissent derrière un bouton Développer, et le maximum est à votre choix. Les périphériques connectés figurent toujours en premier.
- Faites glisser les périphériques dans Réglages pour définir l’ordre affiché dans le panneau. Les nouveaux périphériques apparaissent à la fin.

## Connecter ou déconnecter un appareil depuis le panneau d’état
- Toucher un périphérique jumelé dans la liste Bluetooth le connecte désormais, et toucher un périphérique connecté le déconnecte. La ligne affiche la demande en cours et signale un échec au lieu de prétendre que cela a fonctionné.
- Déconnecter un clavier, une souris, un trackpad ou une manette demande d’abord confirmation, dans la ligne elle-même — déconnecter celui que vous utilisez vous priverait de toute saisie.
