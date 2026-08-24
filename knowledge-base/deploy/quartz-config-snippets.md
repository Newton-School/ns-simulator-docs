# Quartz config tuned for this vault

Two files to edit in your Quartz clone. Graph depth and Explorer ordering live in
`quartz.layout.ts` (not `quartz.config.ts`), so both are covered below.

---

## 1) `quartz.config.ts` - title, baseUrl, ignore templates

Edit the `configuration` block:

```ts
const config: QuartzConfig = {
  configuration: {
    pageTitle: "Simulator Knowledge Base",
    pageTitleSuffix: "",
    enableSPA: true,
    enablePopovers: true,          // hover-preview linked notes
    analytics: null,
    locale: "en-US",

    // ── your GitHub Pages URL (no protocol, no trailing slash) ──
    baseUrl: "YOUR-USER.github.io/simulator-kb",

    // don't publish authoring aids / vault chrome
    ignorePatterns: ["private", "meta/templates", "**/.obsidian", "**/.git"],

    defaultDateType: "modified",
    theme: {
      fontOrigin: "googleFonts",
      cdnCaching: true,
      typography: {
        header: "Schibsted Grotesk",
        body: "Source Sans Pro",
        code: "IBM Plex Mono",
      },
      colors: {
        // defaults are fine; tweak accent if you like
        lightMode: { secondary: "#284b63", tertiary: "#84a59d" },
        darkMode:  { secondary: "#7b97aa", tertiary: "#84a59d" },
      },
    },
  },
  plugins: { /* leave the defaults - Wikilinks, Backlinks, CrawlLinks, etc. */ },
}
```

---

## 2) `quartz.layout.ts` - graph depth + push `reference/` & `decisions/` lower

**a) Graph depth.** Find `Component.Graph(...)` and set the local-graph depth so a
node shows two hops of context (default is 1); keep the global graph showing
everything:

```ts
Component.Graph({
  localGraph: {
    depth: 2,            // ← 2 hops from the current note (default 1)
    scale: 1.1,
    repelForce: 0.5,
    linkDistance: 30,
    fontSize: 0.55,
  },
  globalGraph: {
    depth: -1,           // ← whole graph
    repelForce: 0.5,
    linkDistance: 40,
  },
}),
```

**b) Explorer ordering.** Replace the `Component.Explorer(...)` call with a custom
`sortFn` that pins the learning layer on top and drops `reference/` + `decisions/`
(and `meta/`) to the bottom:

```ts
Component.Explorer({
  title: "Explore",
  folderClickBehavior: "collapse",
  folderDefaultState: "collapsed",   // reference/specs has 39 files - keep it folded
  sortFn: (a, b) => {
    // top-level order; anything not listed sorts after (weight = 99)
    const ORDER = ["learn", "problems", "concepts", "maps", "roadmap", "reference", "decisions", "meta"]
    const rank = (n: typeof a) => {
      const i = ORDER.indexOf(n.name)
      return i === -1 ? 99 : i
    }
    // folders before files
    if (!a.file && b.file) return -1
    if (a.file && !b.file) return 1
    const ra = rank(a), rb = rank(b)
    if (ra !== rb) return ra - rb
    // within the same bucket, natural sort so m01 < m02 < m10, p01 < p10
    return a.displayName.localeCompare(b.displayName, undefined, { numeric: true })
  },
  order: ["filter", "map", "sort"],
}),
```

> `n.name` is the folder/file slug segment (e.g. `"reference"`); `n.file` is undefined
> for folders. `numeric: true` gives the natural M01 → M15 / P01 → P13 ordering.

---

### Result
- Site title + Pages URL set; templates excluded from the build.
- Local graph shows 2 hops of context per note; global graph shows the full map.
- Left explorer reads **learn → problems → concepts → maps → reference → decisions →
  meta**, with the 39-file `reference/specs` folder collapsed by default.

---

## 3) `quartz.config.ts` - silence the `$`-as-math warning

The specs use `$` for **dollars** (`$0.021/hr`), not LaTeX math, so the KaTeX
transformer warns (`Unrecognized Unicode character "-"`) and mis-renders those spans.
Since no page uses real `$…$` / `$$…$$` math, **remove the Latex transformer** from
the `transformers` array in `plugins`:

```ts
plugins: {
  transformers: [
    Plugin.FrontMatter(),
    Plugin.CreatedModifiedDate({ priority: ["frontmatter", "git", "filesystem"] }),
    Plugin.SyntaxHighlighting(),
    Plugin.ObsidianFlavoredMarkdown({ enableInHtmlEmbed: false }),
    Plugin.GitHubFlavoredMarkdown(),
    Plugin.TableOfContents(),
    Plugin.CrawlLinks({ markdownLinkResolution: "shortest" }),
    Plugin.Description(),
    // Plugin.Latex({ renderEngine: "katex" }),   // ← removed: specs use $ for dollars
  ],
  filters: [Plugin.RemoveDrafts()],
  emitters: [ /* leave defaults */ ],
}
```

If you *do* want math on some pages later, keep `Plugin.Latex()` and instead escape
currency as `\$` on the few affected spec pages.
