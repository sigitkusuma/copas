# Release notes

One HTML file per version, named after it — `1.0.0.html`. `Scripts/release.sh`
uses it as the GitHub release body, and copies it beside the archive as
`Copas-1.0.0.html` so `generate_appcast` embeds it in the feed and Sparkle shows
it in the update sheet.

The copy is renamed because `generate_appcast` matches release notes to an
archive by filename, not by version. Named after the version alone, it is
silently ignored and the update sheet comes up blank.

Fragments, not documents: no `<html>`, no `<body>`, no styling. Sparkle renders
them inside its own window.

```html
<h2>What's new</h2>
<ul>
  <li>Something that changed.</li>
</ul>
```

A version with no file here still releases — it simply has no notes.
