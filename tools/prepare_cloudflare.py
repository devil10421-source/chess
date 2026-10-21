"""把 Godot Web 匯出（build/web）整理成可部署到 Cloudflare Pages 的資料夾。

Cloudflare Pages 單一檔案上限 25 MiB，但 Godot 4.7 的 index.wasm 約 39 MB，
所以把 index.wasm 切成數個小於上限的分段，並在 index.html 載入 index.js 之前
插入一小段腳本：Godot 讀取 index.wasm 時，改為依序下載各分段並串成一個
Content-Type 為 application/wasm 的串流回應（載入進度照常顯示）。
遊戲本身（index.js、index.pck、存檔、渲染）完全不變；GitHub Pages 仍使用原本未切割的輸出。

用法：python3 tools/prepare_cloudflare.py build/web build/cloudflare
"""
import json
import pathlib
import shutil
import sys

PART_LIMIT = 20 * 1024 * 1024        # 每段 20 MiB（Cloudflare 上限 25 MiB，留餘裕）
CF_FILE_LIMIT = 25 * 1024 * 1024


def main(src: str, dst: str) -> None:
    src_p = pathlib.Path(src)
    dst_p = pathlib.Path(dst)
    if dst_p.exists():
        shutil.rmtree(dst_p)
    shutil.copytree(src_p, dst_p)

    wasm = dst_p / "index.wasm"
    data = wasm.read_bytes()
    parts = []
    for i in range(0, len(data), PART_LIMIT):
        name = f"index.part{len(parts)}.wasm"
        (dst_p / name).write_bytes(data[i:i + PART_LIMIT])
        parts.append(name)
    wasm.unlink()

    # 1) index.html：在 index.js 之前攔截 index.wasm 的下載
    loader = """<script>
// Cloudflare Pages 單檔上限 25 MiB：index.wasm 已切成分段，這裡把分段依序串回同一個串流。
(function () {
	var PARTS = %s;
	var origFetch = window.fetch.bind(window);
	window.fetch = function (input, init) {
		var url = (typeof input === 'string') ? input : ((input && input.url) || '');
		if (!/(^|\\/)index\\.wasm(\\?|$)/.test(url)) {
			return origFetch(input, init);
		}
		var i = 0;
		var reader = null;
		var stream = new ReadableStream({
			pull: function (controller) {
				function next() {
					if (reader === null) {
						if (i >= PARTS.length) {
							controller.close();
							return Promise.resolve();
						}
						return origFetch(PARTS[i++], init).then(function (r) {
							if (!r.ok) {
								throw new Error('Failed loading ' + PARTS[i - 1] + ' (' + r.status + ')');
							}
							reader = r.body.getReader();
							return next();
						});
					}
					return reader.read().then(function (res) {
						if (res.done) {
							reader = null;
							return next();
						}
						controller.enqueue(res.value);
					});
				}
				return next();
			}
		});
		return Promise.resolve(new Response(stream, { status: 200, headers: { 'Content-Type': 'application/wasm' } }));
	};
})();
</script>
""" % json.dumps(parts)
    html_p = dst_p / "index.html"
    html = html_p.read_text(encoding="utf-8")
    marker = '<script src="index.js"></script>'
    if marker not in html:
        sys.exit("index.html 找不到 index.js 的 <script>，無法插入分段載入器")
    html = html.replace(marker, loader + "\t\t" + marker, 1)
    html_p.write_text(html, encoding="utf-8")

    # 2) PWA service worker：快取清單改成分段檔名
    sw_p = dst_p / "index.service.worker.js"
    if sw_p.exists():
        sw = sw_p.read_text(encoding="utf-8")
        if '"index.wasm"' in sw:
            sw = sw.replace('"index.wasm"', ",".join(json.dumps(p) for p in parts))
            sw_p.write_text(sw, encoding="utf-8")

    # 3) Cloudflare Pages 回應標頭：單執行緒匯出不需要 COOP／COEP；只確保 MIME 與入口頁不被長期快取
    (dst_p / "_headers").write_text(
        "/*.wasm\n  Content-Type: application/wasm\n"
        "/*.pck\n  Content-Type: application/octet-stream\n"
        "/\n  Cache-Control: no-cache\n"
        "/index.html\n  Cache-Control: no-cache\n"
        "/index.service.worker.js\n  Cache-Control: no-cache\n",
        encoding="utf-8")

    too_big = [f.name for f in dst_p.iterdir() if f.is_file() and f.stat().st_size > CF_FILE_LIMIT]
    if too_big:
        sys.exit("仍有超過 25 MiB 的檔案：" + ", ".join(too_big))
    print(f"Cloudflare 輸出：{dst_p}（index.wasm {len(data)} bytes → {len(parts)} 段：{', '.join(parts)}）")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "build/web", sys.argv[2] if len(sys.argv) > 2 else "build/cloudflare")
