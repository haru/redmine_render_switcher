# Redmine Render Switcher Plugin

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![build](https://github.com/haru/redmine_render_switcher/actions/workflows/build.yml/badge.svg)](https://github.com/haru/redmine_render_switcher/actions/workflows/build.yml)
[![Maintainability](https://qlty.sh/gh/haru/projects/redmine_render_switcher/maintainability.svg)](https://qlty.sh/gh/haru/projects/redmine_render_switcher)
[![codecov](https://codecov.io/gh/haru/redmine_render_switcher/graph/badge.svg?token=Rrwokq9ntL)](https://codecov.io/gh/haru/redmine_render_switcher)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/haru/redmine_render_switcher)
![Redmine](https://img.shields.io/badge/redmine->=6.0-blue?logo=redmine&logoColor=%23B32024&labelColor=f0f0f0&link=https%3A%2F%2Fwww.redmine.org)

The Redmine Render Switcher Plugin detects whether each text is written in **Textile** or **Markdown** and renders it with the matching formatter. A site with years of Textile content can let its users write new content in Markdown, without converting a single existing page.

## 🤔 Why This Plugin?

Redmine has one site-wide text formatting setting. Switch it from Textile to Markdown and every existing issue, wiki page and comment written in Textile is suddenly rendered as Markdown: headings turn into plain text, links break, numbered lists collapse. The usual answer is to bulk-convert the database, which is risky and hard to undo.

This plugin removes the need for that. Existing Textile stays Textile, new Markdown is Markdown, and the two live side by side. You migrate at the pace your users do, and nothing stored in the database is ever rewritten.

## ✨ Features

- **Automatic format detection**: Every text field that Redmine renders as wiki text — issue descriptions, comments, wiki pages, news, forum messages, and so on — is rendered with the formatter that matches how it is actually written.
- **Non-destructive**: Only the rendering changes. Stored text is never modified, and turning the plugin off gives you exactly the behaviour of a Redmine without it.
- **Section editing keeps working**: Editing a single wiki section behaves the same whichever format the page uses.
- **Explicit override**: When the detector gets a page wrong, put one line at the top of the body to decide for that page yourself.
- **Tunable**: Turn detection off site-wide, or adjust how confident the detector must be before it overrides the site setting.
- **Cache-safe**: The detector version and threshold are part of Redmine's formatted-HTML cache key, so a change to either never serves stale output.
- **Small footprint**: The plugin patches the two formatter classes only. It registers no new format and adds no database tables, so there are no migrations to run.

## 🔍 How It Works

The detector scores the notation a text uses. Notation that only Textile understands (`h2.` headings, `"text":url` links, `!image.png!`, `bq.` quotes, `@code@`, `|_.` table headers) counts towards Textile. Notation that only Markdown understands (fenced code blocks, `[text](url)` links, `![alt](url)` images, `**bold**`, `` `code` ``, table separator rows) counts towards Markdown. Text inside code blocks is ignored, and a `#` at the start of a line is resolved from its neighbours: two or more in a row are a Textile numbered list, a lone one is a Markdown heading.

The format with the higher score wins, provided it leads by at least the configured threshold. When the score is inconclusive — a short text, plain prose, or notation both formats share — Redmine's own text formatting setting applies, exactly as it would without the plugin.

Detection takes well under a millisecond per text, a small fraction of the time Redmine spends rendering it.

`Setting.text_formatting` keeps its ordinary value (`textile` or `common_mark`) and is the fallback whenever detection is inconclusive. The reasoning behind this design is recorded in [ADR-0001](docs/adr/0001-patch-formatters-instead-of-registering-a-format.md).

## 📦 Installation

Requires Redmine 6.0 or later.

```bash
cd {REDMINE_ROOT}/plugins/
git clone https://github.com/haru/redmine_render_switcher.git
cd {REDMINE_ROOT}
bundle install
```

The plugin has no database migrations. Restart Redmine after the installation is complete.

To uninstall, remove the `redmine_render_switcher` directory from `plugins/` and restart Redmine. Nothing was written to your data, so there is nothing to clean up.

## ⚙️ Configuration

Open **Administration → Plugins → Redmine Render Switcher plugin → Configure**.

| Setting | Default | Description |
|---|---|---|
| Detect the format of each text | Enabled | When disabled, every text is rendered with the site text formatting, exactly as in a Redmine without this plugin. |
| Detection threshold | `2` | How far the Textile and Markdown scores must differ before the detected format is used. Below this margin the site text formatting is kept. A higher value detects less often and more confidently. |

### Choosing the site text formatting

Under **Administration → Settings → General → Text formatting**, choose the format you want **new** content to be written in. This setting still controls the toolbar, the syntax help and everything else on the writing side, and it is the fallback for texts the detector cannot decide on.

For a Textile site that is moving to Markdown, that means switching the setting to *CommonMark Markdown* once the plugin is installed. Existing Textile pages keep rendering as Textile.

### Forcing the format of one page

If the detector picks the wrong format for a particular page, put one of these on the **very first line** of the body:

```text
<!-- render_switcher: textile -->
<!-- render_switcher: markdown -->
```

Follow it with a blank line. The directive beats every detection rule, it is an HTML comment so it never shows on the page, and it survives editing a single section. See [Forcing a format with a directive](docs/directive-usage.md) for the details, including why the blank line matters.

## ⚠️ Limitations

- **One format per text.** A single body must be written in one format throughout. Mixing Textile and Markdown inside one text is not supported; whichever notation belongs to the other format is shown as plain text.
- **Only the reading side is detected.** The editor toolbar, the syntax help, image paste, list auto-continuation and quoted replies follow the site text formatting. This is deliberate: it keeps the plugin's coupling to Redmine to a single point.
- **Short or ambiguous texts fall back to the site setting.** A one-line comment with no distinctive notation renders with the site text formatting. That is usually the right answer, and the directive is there for the cases where it is not.
- **File-driven rendering is affected too.** Browsing a `.textile` or `.md` file in a repository, and previewing an attachment, go through the same formatters. Only files whose extension contradicts their content are rendered differently.
- **Two formats only.** Textile and CommonMark Markdown are supported. The plugin does not convert stored data and does not offer per-project or per-user settings.

## 🔧 Troubleshooting

To see what the detector decided for each text, run Redmine with debug logging enabled and search the log for `[redmine_render_switcher]`. Each line names the verdict and both scores. The text itself is never logged.

## 🤝 Contributing

Contributions are welcome. This project follows the git-flow model: branch from `develop` and open pull requests against it. Please make sure the tests pass before pushing.

All code, comments, test fixtures and documentation under `docs/` are written in English so that contributors worldwide can maintain them. User-facing strings go through `config/locales/` and are provided in English and Japanese.

### Development setup

The plugin lives inside a Redmine checkout at `{REDMINE_ROOT}/plugins/redmine_render_switcher`. Run rake and rails commands from `{REDMINE_ROOT}`.

```bash
cd {REDMINE_ROOT}
bundle install
bundle exec rake redmine:plugins:migrate RAILS_ENV=test
bundle exec rake redmine:plugins:test NAME=redmine_render_switcher
```

To run a single test file:

```bash
bundle exec ruby -Itest plugins/redmine_render_switcher/test/unit/lib/redmine_render_switcher/detector_test.rb
```

Lint and documentation coverage run from the plugin directory:

```bash
cd {REDMINE_ROOT}/plugins/redmine_render_switcher
rubocop --ignore-parent-exclusion
yard stats --list-undoc
```

### Design documents

- [`docs/adr/`](docs/adr/README.md): Architecture Decision Records, the reasoning behind the design.
- [`docs/directive-usage.md`](docs/directive-usage.md): the explicit format directive.

## 🐞 Support

Please report bugs and feature requests as [GitHub issues](https://github.com/haru/redmine_render_switcher/issues). When a text is rendered with the wrong format, including the text (or a minimal sample of it) makes the report much easier to act on.

## 🌟 Credits

Maintained by [Haruyuki Iida](https://github.com/haru).

## 📄 License

Released under the [MIT License](LICENSE).
