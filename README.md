# QuotaBar

QuotaBar 是一個本機優先的 macOS 選單列 App，用來查看 Codex 與 Claude Code 的訂閱額度。

## 功能

- Codex 與 Claude Code 在同一個小型狀態列項目中並排顯示，點擊後開啟共同面板
- 選單列使用 GPT 與 Claude Code 圖示，不佔空間顯示英文名稱
- 顯示兩者的 5 小時、每週額度與重置時間
- 百分比可切換成「剩餘」或「已使用」
- 可關閉選單列上的百分比，只保留圖示
- 每 30 秒更新，亦可手動重新整理；上一輪尚未完成時不會重複發出請求
- 重新整理會同時查詢 Codex 與 Claude Code；Claude 即時查詢不可用時退回最新 status-line 快照
- Codex 與 Claude Code 的選單列圖示可分別更換並自動保存
- 不收集帳號密碼，不建立雲端後端
- Claude status line 連線可復原；若原本已有 status line，QuotaBar 會保留並轉送輸出

## 系統需求

- macOS 14 或更新版本
- Swift 6 / Xcode 16 或更新版本（從原始碼建置時）
- 已安裝並登入 Codex CLI
- 已安裝並登入 Claude Code（如需 Claude 額度）

## 安裝

```sh
git clone https://github.com/johney4415/QuotaBar.git
cd QuotaBar
./scripts/install.sh
open "$HOME/Applications/QuotaBar.app"
```

開啟 QuotaBar 後，Codex 會直接透過本機 CLI 讀取。Claude Code 請在選單內按「連接 Claude Code」，然後重新啟動或開啟一個 Claude Code 工作階段，讓 status line 送出最新資料。

## 開發

```sh
swift test
swift run quota-bar
swift run quota-bar --check
```

`--check` 只在終端顯示 Codex 額度，可用來確認本機 CLI 連線是否正常。

## 資料來源與隱私

### Codex

QuotaBar 啟動本機 `codex app-server`，呼叫 `account/rateLimits/read`。這使用你已登入的 Codex CLI；QuotaBar 不讀取或保存登入 token。這個 app-server 協定目前仍可能隨 Codex 版本改變。

### Claude Code

Claude Code 會把 `rate_limits.five_hour` 與 `rate_limits.seven_day` 放進 status-line JSON。QuotaBar 的橋接器只把該 JSON 寫到：

```text
~/Library/Application Support/QuotaBar/claude-status.json
```

落盤前會移除工作目錄、transcript path、帳號資料及其他無關欄位，只留下兩個額度窗與模型顯示名稱。QuotaBar 資料夾權限為 `0700`，快照與原始 status-line 設定備份為 `0600`。

如果你原本已有 Claude status line command，QuotaBar 會保存原命令、轉送同一份輸入，並把原本輸出交回 Claude Code。按「中斷 Claude」會還原原命令。

## 安全性

- QuotaBar 不讀取或保存 Codex、Claude 的 OAuth token、API key 或密碼。
- 所有 provider 請求都透過使用者已安裝並登入的官方本機 CLI 執行。
- Claude 即時查詢使用 `--safe-mode`，不載入使用者 hooks、plugins、MCP servers 或專案指令。
- 專案沒有第三方 Swift 套件依賴；CI 的 checkout action 固定到完整 commit SHA，且不保留 GitHub credentials。
- 本機安裝腳本使用 ad-hoc 簽章，並非 Apple notarized 發行版。請只從你信任的 checkout 建置。

弱點回報方式與信任邊界請見 [SECURITY.md](SECURITY.md)。

## 已知限制

- Claude 額度需要至少一個活動中的 Claude Code 工作階段提供 status-line 更新。
- Claude Code 目前主要提供 5 小時與 7 天兩個一般額度窗；特定模型額度不一定會出現在 status-line payload。
- Codex / Claude 的本機協定若改版，可能需要同步更新解析器。
- App 需要讀取本機 CLI 與 `~/.claude/settings.json`，因此目前不使用 App Sandbox。

## License

MIT
