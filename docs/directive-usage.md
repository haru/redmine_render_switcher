# Forcing a format with a directive

`redmine_render_switcher` normally works out by itself whether a text is written in
Textile or in Markdown. When it gets a page wrong, you can decide for that page
yourself by adding one line at the very top of the body.

## The two directives

```text
<!-- render_switcher: textile -->
```

```text
<!-- render_switcher: markdown -->
```

The directive beats every detection rule, so the page is rendered with the format
you name, whatever its content scores. It is an HTML comment, so it never appears
on the page, and it survives editing a single section.

Nothing else is accepted. `{{render_switcher_textile}}`, other spellings and other
format names are ignored; whitespace inside the comment and the case of the format
name are the only variations allowed.

## Put a blank line after it

```text
<!-- render_switcher: textile -->

h2. First heading

...
```

The blank line matters. Redmine's Textile formatter only recognises a heading that
follows a blank line, so without one the first heading is not counted and the
section-edit links point one section off. This is Redmine's own behaviour for
anything placed on the first line — the plugin does not correct it, because
rewriting stored text is exactly what this plugin promises never to do.

Markdown is unaffected either way, but write the blank line in both formats so the
same page keeps working if you later switch the directive.

## Only the first line counts

The directive is read from the first line of the body and nowhere else. The same
string quoted in the middle of a page is just text, so quoting an example of this
syntax inside a page cannot change how that page renders.

## One format per text

A single body must be written in one format throughout. Mixing Textile and
Markdown in one text is out of scope: the directive chooses one of the two
formatters for the whole body, and whichever notation belongs to the other format
is rendered as plain text. Split the content into separate pages if you need both.
