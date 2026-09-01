# Release notes

One HTML file per version, named after it — `1.0.0.html`. `Scripts/release.sh`
picks the matching file up as the GitHub release body, and `generate_appcast`
links it from the appcast so Sparkle can show it in the update sheet.

Fragments, not documents: no `<html>`, no `<body>`, no styling. Sparkle renders
them inside its own window.

```html
<h2>What's new</h2>
<ul>
  <li>Something that changed.</li>
</ul>
```

A version with no file here still releases — it simply has no notes.
