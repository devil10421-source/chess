# Cloudflare Pages 部署說明

目標網址：`https://sixrealms-game.pages.dev/`（實際以 Cloudflare 核發的為準）。舊的 GitHub Pages 網址 `https://devil10421-source.github.io/chess/` 暫時保留。

## 運作方式（方案 B：沿用 GitHub Actions 匯出，再用 Wrangler 上傳）

`.github/workflows/web.yml` 一次 Godot Web 匯出，產生兩份輸出：

| 輸出 | 用途 | 部署時機 |
|---|---|---|
| `build/web` | 原本的 GitHub Pages 版本（不變） | 只有 `main` |
| `build/cloudflare` | Cloudflare Pages 版本（`tools/prepare_cloudflare.py` 產生） | `main`＝正式網址；`*-development` 分支＝預覽網址 |

不採用「Cloudflare 直接連 GitHub 在 Cloudflare 上建置」（方案 A）：Cloudflare 的建置環境沒有 Godot，每次都要另外下載 Godot 與 1.2 GB 匯出範本，而且會和現有 GitHub Actions 重複建置。

### 為什麼要切割 wasm
Cloudflare Pages 單一檔案上限 25 MiB，Godot 4.7.2 的 `index.wasm` 約 39 MB。`prepare_cloudflare.py` 把它切成 `index.part0.wasm`、`index.part1.wasm`（各 ≤ 20 MiB），並在 `index.html` 載入 `index.js` 之前加一小段腳本：Godot 下載 `index.wasm` 時，改成依序下載分段並串成同一個 `application/wasm` 串流。遊戲本身（`index.js`、`index.pck`、存檔、介面）完全不變。PWA service worker 的快取清單也一併改成分段檔名。

### Web 相容性
- 使用 Godot 4 **單執行緒** Web 匯出（`variant/thread_support=false`），不需要 SharedArrayBuffer，也不需要 COOP／COEP 跨來源隔離標頭。
- `_headers`：`.wasm` 為 `application/wasm`、`.pck` 為 `application/octet-stream`；`index.html` 與 service worker 設為 `no-cache`，更新後玩家重新整理就會拿到新版。

## 你需要做的設定（只需一次）

不要把密碼或 Token 貼到聊天或提交到程式碼；只放在 GitHub 的 Secrets。

1. **取得 Account ID**：登入 <https://dash.cloudflare.com> → 左側「Workers & Pages」→ 右側欄「Account details」裡的 **Account ID** → 複製。
2. **建立 API Token**：右上角頭像 → **My Profile** → **API Tokens** → **Create Token** → 最下面 **Create Custom Token** →
   - Token name：`sixrealms-pages-deploy`
   - Permissions：`Account` ／ `Cloudflare Pages` ／ `Edit`（只需要這一項）
   - Account Resources：`Include` ／ 你的帳號
   - Continue to summary → Create Token → 複製 Token（只會顯示一次）。
3. **放進 GitHub**：<https://github.com/devil10421-source/chess/settings/secrets/actions> → **New repository secret**，建立兩個：
   - `CLOUDFLARE_API_TOKEN` ＝ 步驟 2 的 Token
   - `CLOUDFLARE_ACCOUNT_ID` ＝ 步驟 1 的 Account ID
4. **觸發一次部署**：<https://github.com/devil10421-source/chess/actions/workflows/web.yml> → **Run workflow**（分支選 `main`）。
   - 流程會自動建立 Cloudflare Pages 專案 `sixrealms-game`（正式分支 `main`），不用在 Cloudflare 手動建立。
   - 執行結果頁面的 Summary 會顯示實際網址。

### 如果 `sixrealms-game.pages.dev` 已被別人使用
Cloudflare 會改發像 `sixrealms-game-xxx.pages.dev` 的網址，這時流程會**停止並報錯、不部署**，訊息會寫出 Cloudflare 改發的網址。你可以：
- 換名稱：Settings → Secrets and variables → Actions → **Variables** → 新增 `CF_PAGES_PROJECT`（例如 `sixrealms-play`），再 Run workflow；或
- 接受改發的網址：新增 Variable `CF_PAGES_ACCEPT_SUBDOMAIN` ＝ 報錯訊息中的網址（例如 `sixrealms-game-xxx.pages.dev`）。

（若改名稱，Cloudflare 上已建立的 `sixrealms-game` 專案可在 Workers & Pages 裡刪除。）

## 之後的自動更新
- 推送到 `main`：自動檢查 → 匯出 → 更新 GitHub Pages 與 Cloudflare 正式網址。
- 推送到 `v0.4-development` 等 `*-development` 分支：只更新 Cloudflare **預覽**網址（`https://<分支>.<專案>.pages.dev/`，例如 `v0-4-development.sixrealms-game.pages.dev`），不會覆蓋正式網址，也不會動 GitHub Pages。
- 停用舊的 GitHub Pages：等新網址測試沒問題、你同意後再處理（目前保留）。
