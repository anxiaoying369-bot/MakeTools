import Foundation

/// Built-in light and dark stylesheet for the Markdown preview.
public enum ThemeCSS {
    public static let stylesheet: String = """
    :root {
        color-scheme: light dark;
        --bg: #f0f3f9;
        --reader-bg: #fff;
        --fg: #182440;
        --muted: #556177;
        --border: #d5deeb;
        --border-subtle: #e3eaf4;
        --code-bg: #f4f7fb;
        --inline-code-bg: rgba(175, 184, 193, 0.2);
        --link: #2653c7;
        --quote-border: #d0d7de;
        --table-stripe: #f6f8fa;
        --card-bg: #f4f7fb;
        --tok-kw: #cf222e;
        --tok-str: #0a3069;
        --tok-cmt: #6e7781;
        --tok-num: #0550ae;
        --tok-type: #953800;
        --note-accent: #0969da;
        --tip-accent: #1a7f37;
        --important-accent: #8250df;
        --warning-accent: #9a6700;
        --caution-accent: #cf222e;
        --btn-bg: #ffffff;
        --btn-hover-bg: #f3f4f6;
        --btn-copied-fg: #1a7f37;
        --btn-copied-border: #1a7f37;
    }

    @media (prefers-color-scheme: dark) {
        :root {
            --bg: #141b2a;
            --reader-bg: #1b263b;
            --fg: #e7edf8;
            --muted: #a4afc3;
            --border: #344059;
            --border-subtle: #2a3448;
            --code-bg: #171e2b;
            --inline-code-bg: rgba(110, 118, 129, 0.35);
            --link: #4493f8;
            --quote-border: #3d444d;
            --table-stripe: #161b22;
            --card-bg: #1b263b;
            --tok-kw: #ff7b72;
            --tok-str: #a5d6ff;
            --tok-cmt: #8b949e;
            --tok-num: #79c0ff;
            --tok-type: #ffa657;
            --note-accent: #4493f8;
            --tip-accent: #3fb950;
            --important-accent: #ab7df8;
            --warning-accent: #d29922;
            --caution-accent: #f85149;
            --btn-bg: #21262d;
            --btn-hover-bg: #30363d;
            --btn-copied-fg: #3fb950;
            --btn-copied-border: #3fb950;
        }
    }

    * {
        box-sizing: border-box;
    }

    html, body {
        margin: 0;
        padding: 0;
        background-color: var(--bg);
        color: var(--fg);
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Helvetica Neue", sans-serif;
        font-size: 15px;
        line-height: 1.7;
        -webkit-font-smoothing: antialiased;
        word-wrap: break-word;
        user-select: text;
        -webkit-user-select: text;
    }

    .markdown-body {
        max-width: 850px;
        margin: 14px auto 28px;
        width: calc(100% - 32px);
        background: var(--reader-bg);
        border: 1px solid var(--border);
        border-radius: 16px;
        padding: clamp(22px, 5vw, 40px) clamp(18px, 5vw, 46px) 48px;
    }

    @media (prefers-reduced-motion: no-preference) {
        .markdown-body.is-interactive {
            animation: document-reveal 220ms ease-out;
        }

        .copy-code-btn {
            transition: background-color 150ms ease, border-color 150ms ease, color 150ms ease, transform 150ms ease;
        }

        .copy-code-btn:active {
            transform: scale(0.96);
        }
    }

    @keyframes document-reveal {
        from { opacity: 0.55; }
        to { opacity: 1; }
    }

    .markdown-body,
    .markdown-body pre,
    .markdown-body code {
        user-select: text;
        -webkit-user-select: text;
    }

    .markdown-body > *:first-child {
        margin-top: 0 !important;
    }

    .markdown-body > *:last-child {
        margin-bottom: 0 !important;
    }

    h1, h2, h3, h4, h5, h6 {
        margin-top: 24px;
        margin-bottom: 14px;
        font-weight: 600;
        line-height: 1.3;
    }

    h1 {
        font-size: 2.14em;
        font-weight: 700;
        letter-spacing: -0.022em;
        padding-bottom: 0.3em;
        border-bottom: 1px solid var(--border-subtle);
    }

    h2 {
        font-size: 1.55em;
        letter-spacing: -0.014em;
        padding-bottom: 0.25em;
        border-bottom: 1px solid var(--border-subtle);
    }

    h3 { font-size: 1.24em; }
    h4 { font-size: 1.05em; }
    h5 { font-size: 0.92em; }
    h6 { font-size: 0.85em; color: var(--muted); }

    p, blockquote, ul, ol, table, pre, .code-block, .callout, .frontmatter {
        margin-top: 0;
        margin-bottom: 16px;
    }

    a {
        color: var(--link);
        text-decoration: none;
    }

    a:hover {
        text-decoration: underline;
    }

    hr {
        height: 2px;
        padding: 0;
        margin: 24px 0;
        background-color: var(--border-subtle);
        border: 0;
    }

    blockquote {
        padding: 2px 16px;
        color: var(--muted);
        border-left: 4px solid var(--quote-border);
        margin-left: 0;
        margin-right: 0;
    }

    blockquote > :last-child {
        margin-bottom: 0;
    }

    ul, ol {
        padding-left: 2em;
    }

    li + li {
        margin-top: 4px;
    }

    li.task-list-item {
        list-style-type: none;
        margin-left: -1.35em;
    }

    li.task-list-item input[type="checkbox"] {
        margin-right: 0.45em;
        vertical-align: middle;
        accent-color: var(--link);
    }

    code, pre {
        font-family: "SF Mono", Menlo, Monaco, Consolas, "Liberation Mono", monospace;
    }

    code {
        padding: 0.16em 0.4em;
        font-size: 87%;
        background-color: var(--inline-code-bg);
        border-radius: 5px;
    }

    .code-block {
        position: relative;
        background-color: var(--code-bg);
        border: 1px solid var(--border-subtle);
        border-radius: 12px;
        overflow: hidden;
    }

    .code-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 7px 12px 7px 14px;
        background-color: var(--card-bg);
        border-bottom: 1px solid var(--border-subtle);
        user-select: none;
        -webkit-user-select: none;
    }

    .code-lang {
        display: inline-block;
        font-family: "SF Mono", Menlo, Monaco, Consolas, monospace;
        font-size: 11px;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        color: var(--muted);
        user-select: none;
        -webkit-user-select: none;
    }

    .code-block > .code-lang {
        display: block;
        padding: 5px 12px;
        border-bottom: 1px solid var(--border-subtle);
    }

    .copy-code-btn {
        appearance: none;
        -webkit-appearance: none;
        min-width: 68px;
        padding: 3px 9px;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", sans-serif;
        font-size: 11px;
        font-weight: 500;
        line-height: 1.5;
        color: var(--fg);
        background-color: var(--btn-bg);
        border: 1px solid var(--border);
        border-radius: 7px;
        cursor: pointer;
        user-select: none;
        -webkit-user-select: none;

    }

    .copy-code-btn:hover {
        background-color: var(--btn-hover-bg);
    }

    :is(a, .copy-code-btn):focus-visible {
        outline: 2px solid var(--link);
        outline-offset: 2px;
    }

    .copy-code-btn.copied {
        color: var(--btn-copied-fg);
        border-color: var(--btn-copied-border);
    }

    .code-block pre {
        margin: 0;
        padding: 15px 16px;
        overflow-x: auto;
        font-size: 13px;
        line-height: 1.5;
    }

    .code-block pre code {
        padding: 0;
        font-size: inherit;
        background: transparent;
        border-radius: 0;
    }

    .tok-kw { color: var(--tok-kw); font-weight: 500; }
    .tok-str { color: var(--tok-str); }
    .tok-cmt { color: var(--tok-cmt); font-style: italic; }
    .tok-num { color: var(--tok-num); }
    .tok-type { color: var(--tok-type); }

    table {
        border-spacing: 0;
        border-collapse: collapse;
        width: 100%;
        overflow: auto;
        display: block;
    }

    table th, table td {
        padding: 7px 13px;
        border: 1px solid var(--border);
    }

    table th {
        font-weight: 600;
        background-color: var(--card-bg);
    }

    table tr:nth-child(2n) td {
        background-color: var(--table-stripe);
    }

    img {
        max-width: 100%;
        height: auto;
        border-radius: 6px;
    }

    .frontmatter {
        background-color: var(--card-bg);
        border: 1px solid var(--border);
        border-radius: 12px;
        padding: 12px 16px;
        font-size: 13px;
    }

    .frontmatter-title {
        font-size: 11px;
        font-weight: 600;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--muted);
        margin-bottom: 6px;
    }

    .frontmatter-grid {
        display: grid;
        grid-template-columns: fit-content(40%) minmax(0, 1fr);
        column-gap: 14px;
        row-gap: 3px;
    }

    .frontmatter-key {
        font-weight: 600;
        color: var(--muted);
    }

    .callout {
        padding: 12px 16px;
        border-left: 4px solid var(--note-accent);
        background-color: var(--card-bg);
        border-radius: 0 10px 10px 0;
    }

    .callout-title {
        font-weight: 600;
        font-size: 13px;
        letter-spacing: 0.03em;
        margin-bottom: 4px;
        color: var(--note-accent);
    }

    .callout > :last-child {
        margin-bottom: 0;
    }

    .callout-note { border-left-color: var(--note-accent); }
    .callout-note .callout-title { color: var(--note-accent); }
    .callout-tip { border-left-color: var(--tip-accent); }
    .callout-tip .callout-title { color: var(--tip-accent); }
    .callout-important { border-left-color: var(--important-accent); }
    .callout-important .callout-title { color: var(--important-accent); }
    .callout-warning { border-left-color: var(--warning-accent); }
    .callout-warning .callout-title { color: var(--warning-accent); }
    .callout-caution { border-left-color: var(--caution-accent); }
    .callout-caution .callout-title { color: var(--caution-accent); }
    """
}
