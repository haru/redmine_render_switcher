# Redmine Plugin Boilerplate

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.md)

## 概要

redmine_plugin_boilerplate は、Redmine プラグインの作成を簡単に行うためのテンプレートリポジトリです。GitHub でテンプレート形式で提供されており、開発者が Redmine プラグインプロジェクトを簡単に始められるようになっています。

## 機能

- **Codespaces 統合:** Github Codespaces を使用した開発が可能で、Web ブラウザだけでどこからでも開発できます。
- **柔軟な環境:** プロジェクトの要件に応じて、Redmine バージョン、Ruby バージョン、データベースタイプの組み合わせをカスタマイズできます。
- **デバッガーサポート:** デバッガーを活用した効率的なデバッグが可能です。

## 使い方

1. GitHub で redmine_plugin_boilerplate リポジトリを開きます。
2. `Use this template` ボタンをクリックして、プラグイン用の新しいリポジトリを作成します。リポジトリ名は、作成したいプラグイン名にしてください。
3. 新しいリポジトリに対して Github Codespace を作成します。
4. すると、.env ファイルが自動的に生成されます。このファイルをコミットし、Rebuild Container を実行してください。
5. Codespace の準備ができたら、`.devcontainer/redmine.code-workspace` を開いてください。
6. この `Readme.md` ファイルの内容を、プラグイン固有の情報に置き換えてください。

## ライセンス

このプロジェクトは MIT ライセンスの下でライセンスされています。詳細は [LICENSE.md](LICENSE.md) ファイルを参照してください。

Happy coding!
