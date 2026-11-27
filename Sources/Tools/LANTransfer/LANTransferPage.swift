enum LANTransferPage {
    static var html: String {
        let title = L10n.html(L10n.text("lanTransfer.web.title", "上传到 MakeTools"))
        return """
        <!doctype html>
        <html lang="\(L10n.html(L10n.locale.identifier.replacingOccurrences(of: "_", with: "-")))">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(title)</title>
          <style>
            :root { color-scheme: light dark; font-family: -apple-system, system-ui, sans-serif;
                    --canvas: #f0f3f9; --surface: #fff; --ink: #182440; --line: #d9e2f1; --accent: #2653c7; }
            @media (prefers-color-scheme: dark) {
              :root { --canvas: #141b2a; --surface: #1b263b; --ink: #eef2ff; --line: #354768; --accent: #5076e2; }
            }
            body { margin: 0; background: var(--canvas); color: var(--ink); }
            main { max-width: 38rem; margin: clamp(1rem, 9vh, 5rem) auto; padding: clamp(1.15rem, 5vw, 2.4rem);
                   width: calc(100% - 2rem); box-sizing: border-box; background: var(--surface);
                   border: 1px solid var(--line); border-radius: 1.25rem; border-top: 4px solid var(--accent); }
            h1 { font-size: clamp(1.8rem, 7vw, 2.8rem); margin: 0 0 .6rem; letter-spacing: -.035em; }
            p { opacity: .72; line-height: 1.6; }
            button { border: 0; border-radius: .8rem; padding: .85rem 1.3rem; background: var(--accent);
                     color: white; font: inherit; font-weight: 650; min-height: 44px; }
            button:disabled { opacity: .5; }
            ul { padding: 0; margin: 1.7rem 0; list-style: none; }
            li { border-top: 1px solid var(--line); padding: .85rem 0; }
            strong, output { display: block; overflow-wrap: anywhere; }
            output { font-size: .9rem; margin: .35rem 0; }
            progress { width: 100%; accent-color: var(--accent); }
          </style>
        </head>
        <body>
          <main>
            <h1>\(title)</h1>
            <p>\(L10n.html(L10n.text("lanTransfer.web.description", "文件将保存到 Mac 上选定的文件夹。单个文件最大 5 GiB。")))</p>
            <input id="files" type="file" multiple hidden>
            <button id="choose" type="button">\(L10n.html(L10n.text("lanTransfer.web.choose", "选择文件并上传")))</button>
            <ul id="results" aria-label="\(L10n.html(L10n.text("lanTransfer.web.results", "上传结果")))"></ul>
          </main>
          <script>
            const picker = document.querySelector('#files');
            const choose = document.querySelector('#choose');
            const results = document.querySelector('#results');
            choose.addEventListener('click', () => picker.click());

            function upload(file) {
              const row = results.appendChild(document.createElement('li'));
              row.appendChild(document.createElement('strong')).textContent = file.name;
              const status = row.appendChild(document.createElement('output'));
              status.textContent = \(L10n.scriptString(L10n.text("lanTransfer.web.uploading", "正在上传…")));
              return new Promise(resolve => {
                if (file.size > 5 * 1024 ** 3) {
                  status.textContent = \(L10n.scriptString(L10n.text("lanTransfer.web.tooLarge", "文件超过 5 GiB")));
                  resolve();
                  return;
                }
                const progress = row.appendChild(document.createElement('progress'));
                progress.max = 100;
                progress.value = 0;
                progress.setAttribute('aria-label', \(L10n.scriptString(L10n.text("lanTransfer.web.progress", "上传进度"))));
                const request = new XMLHttpRequest();
                request.open('PUT', location.pathname + encodeURIComponent(file.name));
                request.upload.onprogress = event => {
                  if (event.lengthComputable && event.total > 0) {
                    progress.value = Math.floor(event.loaded * 100 / event.total);
                  }
                };
                function finish(message) {
                  progress.remove();
                  status.textContent = message;
                  resolve();
                }
                request.onload = () => finish(request.status === 201
                  ? \(L10n.scriptString(L10n.text("lanTransfer.web.saved", "已保存为 {filename}"))).split('{filename}').join(request.responseText)
                  : (request.responseText || \(L10n.scriptString(L10n.text("lanTransfer.web.failed", "上传失败")))));
                request.onerror = () => finish(\(L10n.scriptString(L10n.text("lanTransfer.web.disconnected", "连接已中断，请确认 Mac 仍在接收。"))));
                request.onabort = () => finish(\(L10n.scriptString(L10n.text("lanTransfer.web.cancelled", "上传已取消。"))));
                request.send(file);
              });
            }

            picker.addEventListener('change', async () => {
              const files = Array.from(picker.files);
              choose.disabled = true;
              try {
                for (const file of files) await upload(file);
              } finally {
                picker.value = '';
                choose.disabled = false;
              }
            });
          </script>
        </body>
        </html>
        """
    }
}
