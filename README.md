# harpy-pack

Source du modpack Harpy Express et versions publiées pour le launcher.

## Organisation

- `pack/mods/` : les jars du pack. Ils ne sont pas dans Git, ils sont envoyés dans les Releases.
- `pack/config/` : les configs imposées à tous les joueurs. Les autres configs restent celles du joueur.
- `channels/dev.json`, `channels/prod.json` : la version servie sur chaque canal.

## Publier une mise à jour

1. Mets à jour `pack/mods/` et `pack/config/`.
2. Lance `publish.cmd` : la version part sur le canal **dev**.
3. Teste-la, puis lance `promote.cmd` : elle passe en **prod** pour tous les joueurs.

`publish.cmd -DryRun` affiche ce qui serait publié, sans rien envoyer.

Seuls les fichiers nouveaux ou modifiés sont envoyés, et les joueurs ne téléchargent que ce qui a changé.
