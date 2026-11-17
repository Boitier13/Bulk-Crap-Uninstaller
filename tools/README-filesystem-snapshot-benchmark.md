# Benchmark du coût des snapshots FileSystemJunk

Ce benchmark mesure, sous Windows, le coût supplémentaire de la capture superficielle utilisée dans PR #4.

## Ce qui est mesuré

Pour des dossiers contenant 100, 1 000 et 5 000 fichiers immédiats :

- **Énumération simple** : énumération des entrées immédiates, sans collecte de métadonnées ni tri. C'est une référence de coût, pas une reproduction complète de tous les scanners BCU.
- **Snapshot initial** : collecte des métadonnées de chaque entrée (chemin, type, dates UTC, attributs, taille fichier), puis tri, comme dans PR #4.
- **Deux snapshots** : deux captures successives, représentant approximativement la capture à la détection puis la revalidation avant suppression.

Les temps sont des médianes sur cinq répétitions par défaut. La création des fichiers de test est exclue des mesures.

## Exécution

Ouvrir PowerShell dans le dépôt, puis exécuter :

    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\benchmark-filesystem-snapshot.ps1

PowerShell 5.1 (présent sur Windows 10) et PowerShell 7 sont pris en charge. Aucun module externe, .NET SDK, GitHub Codespaces ou accès Internet n'est nécessaire.

Pour modifier les tailles et le nombre de répétitions :

    .\tools\benchmark-filesystem-snapshot.ps1 -FileCounts 100,1000,5000,10000 -Repetitions 7

## Sécurité et limites

- Le script crée ses jeux de test dans un sous-dossier au nom aléatoire de %TEMP%.
- Il ne lit, ne modifie et ne supprime aucun fichier en dehors de ce dossier temporaire qu'il a lui-même créé.
- Il ne lance pas BCU et n'exécute aucune suppression de résidu.
- Le dossier temporaire est supprimé dans le bloc finally, même si une erreur survient.
- Le CSV est écrit sur le Bureau (ou dans le dossier courant si le Bureau n'est pas disponible).
- Fermer les applications lourdes et éviter une activité disque importante pendant le test améliore la comparabilité.
- Un test sur le PC HDD de référence est plus représentatif que les résultats d'une machine GitHub hébergée.
- Ce micro-benchmark mesure le coût de l'algorithme sur des dossiers plats. Il ne mesure pas le parcours récursif complet des scanners, les milliers de candidats, les antivirus, ni les variations de cache disque.

Ne pas utiliser les chiffres seuls pour décider de supprimer ou d'affaiblir la protection : il faut les interpréter avec les tailles réelles des dossiers candidats et les limites de couverture du snapshot.
