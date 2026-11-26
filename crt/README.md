# crt.js

Retro-TV look for any page: soft blur, animated grain, scanlines, vignette, faint flicker, and a "TV turn-on" animation. No dependencies, no assets. Same layering as weather.com/retro, with the grain and texture generated instead of using their videos.

```html
<script src="crt.js"></script>
<script>
  const crt = CRT({ target: 'main', grain: 0.2 });
  // crt.destroy();
</script>
```

Options: `target`, `blur`, `saturate`, `grain`, `grainScale`, `grainFps`, `scanlines`, `scanlineGap`, `vignette`, `glow`, `turnOn`, `turnOnMs`, `zIndex`. Respects `prefers-reduced-motion`.

Open `demo.html` to see it.
