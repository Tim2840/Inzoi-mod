# inZOI 模組研究報告：製作方式、社群需求與開發規劃

> 調查日期：2026-10-18（遊戲版本 v0.11.0「Mini Update」，2026-10-15 上線）
>
> 資料來源說明：這次的雲端環境網路政策擋掉了 mod-docs.playinzoi.com、官方論壇、CurseForge、SteamDB 的直接連線，所以內容全部來自搜尋引擎的摘要和轉載報導（Sims Community、PCGamesN、mixed-news、巴哈姆特等），沒有逐頁讀過原文。標了「⚠ 待驗證」的項目，開工前要在官方文件確認。

---

## 一、結論摘要

1. **製作門檻剛降了一大截。** 10/15 的 v0.11.0 加入了 **Lua 腳本模組**，加上已有的 **HTML/JS Overlay UI 模組** 和 **MCP 伺服器**，現在可以讓 AI 助手（Claude Code 等）直接連進遊戲和 ModKit 寫模組、測模組。這是 inZOI 第一次有真正的「玩法型」腳本模組。
2. **社群最大的怨言是「漂亮但空洞」**：缺少人生推進、目標感、隨機故事事件，NPC 不會自己過日子。The Sims 4 的 MCCC、Slice of Life、Wonderful Whims 一直被拿來當參考。
3. **市場缺口**：超自然（Age of Magic，約 1.5 萬下載）、犯罪（ZoiWorks Organized Crime）、作弊控制面板（ZOI Command Center）、抱負/特質包（ZoiWorks）都已經有人做。**「城市人生推進＋隨機人生事件」這種 MCCC 類型的模組目前還沒有明確的代表作。**
4. **建議的旗艦專案**：「**活著的城市（Living City）**」，一個模組化的 Lua 腳本模組，核心加上幾個模組：
   - 人生推進（NPC 會自己談戀愛、結婚、分手、換工作、生小孩）
   - 人生事件導演（家庭爭吵、重逢、意外之財等，事件用 JSON 定義，別人也能擴充）
   - 生活帳本（房租、帳單、存款、貸款）
   - 人生年表（家族大事記 UI）

   設定面板用 Overlay UI 做，支援繁中、英文、韓文。

---

## 二、inZOI 模組製作方式（2026 年 10 月最新）

### 2.1 工具鏈總覽

| 工具 | 用途 | 狀態 |
|---|---|---|
| **inZOI ModKit**（Epic Games Store 免費下載） | 以 Unreal Engine 5 為基礎的官方編輯器，所有官方模組都用它製作和打包 | 2025-06 推出，持續更新 |
| **Wizard 精靈工具** | 不用懂 UE 就能做 CAZ（服裝、配件、頭飾）、BUILD（家具）、載具、濾鏡模組 | 頭飾精靈與濾鏡模組 10/15 新增；載具精靈 9/3 新增 |
| **Data 模組（JSON）** | 修改特質、抱負、角色資料等遊戲數值，不需要 3D 建模 | 2026-01 改成 JSON 資產格式，降低版本不一致的問題 |
| **Overlay UI 模組（HTML/JS）** | 在遊戲上疊一層自訂介面，用 `await window.inzoi.cli.execute('<command-id>', {...})` 呼叫遊戲指令 | 已推出；10/15 新增 HUD 上的開關啟動器 |
| **Lua 腳本模組** | 寫遊戲邏輯，用 ModKit 內建的 Lua Script Mod Editor 附加到模組上 | **10/15 推出**（原訂 12 月，提前了） |
| **CLI 指令目錄** | 318 個指令，**只有 115 個是 Public**，正式版只能用這些。UserCheat 和 ScriptCheat 在玩家端不會有作用 | 已推出；Lua 和 JS 共用同一份目錄 |
| **MCP 伺服器** | `inzoi-game`（`localhost:11212/mcp`，遊戲要開著）可以讀取和控制遊戲中的 Zoi、物件、存檔；`inzoi-modkit`（`:11213`，ModKit 要開著）可以建立和編輯模組專案 | 已推出；官方文件有列 Claude、ChatGPT、Gemini、Cursor 的設定方式 |
| **發佈管道** | CurseForge（ModKit 內建上傳，遊戲內可以直接下載）、Nexus Mods | 遊戲內模組管理器支援自訂名稱和載入順序（10/15 改版） |

### 2.2 用 Claude Code 連接遊戲（官方文件寫法）

```bash
claude mcp add inzoi-game   --scope user --transport http http://localhost:11212/mcp
claude mcp add inzoi-modkit --scope user --transport http http://localhost:11213/mcp
# 埠號被占用時：從 Steam 啟動參數加上 -climcpport=<port>
```

連上之後可以用自然語言下指令，例如官方範例「把城市裡的 Zoi 上限設成 10」，AI 會自己去呼叫對應的指令。官方 10/9 開發日誌示範過的 AI 生成模組包括：Zoi 自己幫車子烤漆、全自動房間佈置（只用 Lua，沒有 UI）、自動趕走不請自來的訪客、甩尾、飛天車等。

### 2.3 官方劃下的界線（規劃時一定要遵守）

- **Kjun（製作人）明說「個性、自主行為、情緒、動畫」由官方團隊自己做，不會交給模組。** 所以模組不應該去覆寫底層的 AI 自主行為，而是從「宏觀人生事件」層面去推動。
- 新增特質 ID 有技術限制（2025-08 官方改過抽象特質之後就這樣了）。
- 遊戲更新時，**所有模組會自動被停用**，玩家要手動重新啟用。官方也不保證模組相容性。
- PS5 和 Mac 的模組支援還在 R&D 階段，可能受限。
- ⚠ 待驗證：Lua API 有沒有事件或掛鉤（例如「每天開始時」、「Zoi 結婚時」）、計時器、存檔持久化。官方文件有「Lua API」、「Script Execution」、「Script Condition」頁面，但這次沒辦法讀到內容。**這是整個規劃最大的技術不確定性**，所以第 0 階段要先做 API 探勘。

### 2.4 官方接下來的規劃（避免撞車）

| 時間 | 官方內容 | 對我們的影響 |
|---|---|---|
| 2026-12 | 名人／網紅／社群媒體／名氣聲望系統 | **不要做名氣系統**，等它推出後再做擴充 |
| 2026-10（R&D） | 多人連動模組、Data 模組 AI 精靈 | 留意就好 |
| 已推出 | 職涯擴充、高中、監獄、度假、城市旅行、載具互動 | 可以拿來當事件素材，例如入獄、度假被觸發 |
| 未定 | Canvastown 新城市、多人模式 | 設計時讓模組不依賴特定城市 |

---

## 三、社群需求調查

### 3.1 需求排序（依各來源出現的頻率與熱度綜合判斷）

| 排名 | 需求 | 證據 | 現有模組 | 適合用模組做嗎 |
|---|---|---|---|---|
| 1 | **NPC 有自己的人生／城市人生推進**（自動談戀愛、結婚、工作、生子、搬家） | 多篇論壇心願單直接點名 MCCC；「Automatic Rabbit-Hole Careers for NPC Zois」；「Players Want Their Zois to Feel Alive」（2026-09） | 沒有明確的代表作 | ✅ 很適合（宏觀層面） |
| 2 | **目標感與經濟深度**（房租、房貸、存款、帳單；錢很快就沒有意義） | 「progression and objectives are inzoi's #1 problem」是熱門串；PC Gamer 和多篇評測都說遊戲「淺」 | 不明顯 | ✅ 適合 |
| 3 | **隨機故事事件／戲劇性**（家庭爭吵、分手、重逢、自主結婚離婚） | 多篇心願單；評測說「行為很少累積成屬於玩家自己的故事」 | 不明顯 | ✅ 很適合 |
| 4 | **家族史／人生年表**（記錄上學、工作、創業、搬家） | 「Better family story telling」、「Making inZOI a Deeper and More Connected Life Simulation」 | 不明顯 | ✅ 適合（Overlay UI） |
| 5 | 超自然（吸血鬼、狼人、巫術、幽靈） | Steam 熱門建議；Age of Magic 巫術約 1.55 萬下載，是已知最高的腳本模組 | **已有**（Age of Magic 系列） | 已經飽和 |
| 6 | 童年經歷影響成年個性 | 心願單高讚貼文 | 無 | ⚠ 碰到個性系統，官方不會開放 |
| 7 | 寵物深化（獸醫、品種、比賽） | 多篇心願單 | 少 | △ 可行，但需要動畫和資產 |
| 8 | 犯罪與黑幫 | — | **已有**（ZoiWorks Organized Crime） | 已經飽和 |
| 9 | 每個模組有自己的設定頁 | 「Script Mods Options UI tool」心願單（模組作者端的需求） | 無官方方案 | ✅ 可以做成共用框架 |
| 10 | 效能優化、更少的通知和 UI 調整 | Nexus 熱門榜第一是 InZOI Optimizer；「UI improvements + less notifications」 | 已有 | 不是我們的方向 |

### 3.2 解讀

- **玩家抱怨的根本問題是「系統面」不足，不是「內容」不足。** 服裝和家具模組再多，也補不了這個洞。真正有差異化的機會在於玩法腳本。
- Lua 腳本 10/15 才剛推出，CurseForge 的腳本模組只有十幾個，**現在是搶佔「必裝模組」地位的時間點**。Sims 4 的 MCCC 就是靠早期卡位變成標配。
- 亞洲（繁中、韓文）社群的在地化模組比較少。從第一天就支援多語系，是低成本的差異化。

---

## 四、開發規劃：「活著的城市（Living City）」

### 4.1 架構

```
LivingCity/
├─ core/            Lua：排程器（每日或每 N 小時 tick）、設定讀寫、日誌、指令封裝層
├─ modules/
│  ├─ progression/  Lua：NPC 戀愛、婚姻、分手、求職、生育的機率模型
│  ├─ events/       Lua＋JSON：事件引擎；事件定義檔是資料，可以擴充
│  ├─ ledger/       Lua：帳單、房租、存款利息、貸款
│  └─ chronicle/    Lua＋UI：人生大事記
├─ ui/              Overlay UI（HTML/JS）：設定面板、事件選擇彈窗、年表
├─ data/            JSON：事件表、機率表、在地化字串（zh-TW / en / ko）
└─ docs/
```

設計原則：

1. **指令封裝層**：所有遊戲呼叫都集中在 `core/api.lua`。遊戲更新改了指令時，只需要修這一層。
2. **只用 Public 指令**，不依賴作弊指令，玩家端才保證有效。
3. **不覆寫自主行為**：只在宏觀層面觸發結果（例如讓兩個 NPC 交往），不干涉 Zoi 每分鐘在做什麼。這符合官方界線，也比較不會因為官方改自主系統而壞掉。
4. **每個模組都能個別開關，機率都能調整**（學 MCCC），並且有「溫和」、「戲劇化」、「寫實」等預設檔。
5. **事件用資料驅動**：事件寫在 JSON 裡（條件 → 機率 → 效果 → 通知文字），社群可以出事件擴充包，形成生態系。

### 4.2 分階段時程（假設一人兼職開發）

| 階段 | 時間 | 交付內容 | 完成標準 |
|---|---|---|---|
| **0. 環境與 API 探勘** | 第 1 週 | Windows 上裝好 inZOI＋ModKit，Claude Code 透過 MCP 連上兩個伺服器；做一個「Hello Zoi」Lua 模組加一個 UI 開關；整理出 **Public 指令能力矩陣**（關係、婚姻、金錢、職業、家戶、通知各自能做什麼） | 確認 Lua 有沒有計時器或事件、能不能存資料。**如果做不到，就調整範圍**（例如改成玩家手動按「推進一天」） |
| **1. 核心框架＋人生推進 MVP** | 第 2–4 週 | 排程器、設定面板、日誌；NPC 自動交往、結婚、分手、求職 | 開一個新存檔放 7 個遊戲日，城裡至少要出現一對新情侶和一次求職，而且沒有錯誤 |
| **2. 人生事件導演** | 第 5–7 週 | 事件引擎＋20 個起始事件（繁中、英文）；事件彈窗可以讓玩家做選擇 | 事件可以從 JSON 熱新增；玩家能在 UI 裡關掉個別事件 |
| **3. 公開 Beta** | 第 8 週 | 上架 CurseForge（主要管道，遊戲內可直接下載）和 Nexus；在官方論壇、巴哈姆特、Reddit 發文 | 收集回報，每次遊戲更新後 48 小時內出相容版 |
| **4. 生活帳本** | 第 9–11 週 | 房租、帳單、存款、貸款 | — |
| **5. 人生年表** | 第 12–14 週 | 家族大事記 UI，可以匯出成圖片或文字 | — |
| 之後 | 12 月官方名人系統推出後 | 「名氣事件包」擴充 | — |

### 4.3 開發工作流（建議）

1. **原始碼放在這個 Git repo**（Lua、HTML/JS、JSON 都是純文字，適合版本控制）。ModKit 專案資產另外管理，或用 Git LFS。
2. **用 Claude Code＋MCP 迭代**：在你的 Windows 電腦上開遊戲和 ModKit，Claude Code 連上 `inzoi-game` 直接測試指令，再透過 `inzoi-modkit` 把腳本寫進模組專案。
3. **每次遊戲更新的回歸檢查清單**：重新啟用模組 → 跑一次 API 矩陣測試 → 修 `core/api.lua` → 改版本號 → 重新上傳。

### 4.4 風險與對策

| 風險 | 可能性 | 對策 |
|---|---|---|
| Lua API 沒有事件或計時器，或不能存資料 | 中 | 第 0 階段先驗證；備案是用 UI 端的 JS 計時器，或改成玩家手動觸發 |
| Public 指令不夠（例如沒辦法直接讓兩人結婚） | 中 | 能力矩陣出來後縮小範圍；也可以用「提高好感＋引導互動」間接達成 |
| 官方更新弄壞模組 | 高 | 封裝層＋回歸清單＋快速出相容版 |
| 官方之後自己做出類似功能 | 中 | 定位成「可調參數的進階控制」，官方通常不會提供這種細度 |
| 開發和測試只能在 Windows 本機進行 | 確定 | 雲端環境負責寫碼、文件和打包腳本，遊戲內測試由你在本機跑 |

---

## 五、需要你決定的事

1. **旗艦方向**：照建議做「活著的城市」，還是先做範圍小一點的單一模組（例如只做「人生事件導演」）來練手？
2. **開發環境**：你有沒有 Windows 電腦，裝了 inZOI 和 ModKit？第 0 階段的 API 探勘需要在那台電腦上跑。
3. **語系**：第一版要不要同時出繁中和英文（建議要），韓文是否列入？

決定之後，我可以先在這個 repo 建好專案骨架（`core/api.lua`、事件 JSON schema、設定面板 HTML、能力矩陣測試腳本）。

---

## 參考來源

**官方與版本資訊**
- [inZOI ModKit Docs 首頁](https://mod-docs.playinzoi.com/)、[CLI 說明](https://mod-docs.playinzoi.com/docs/modkit-docs/wiki/cli/)、[CLI Command Finder](https://mod-docs.playinzoi.com/docs/modkit-docs/wiki/cli/commands/)、[Getting Started](https://mod-docs.playinzoi.com/ModKit/How-to/Getting-Started/02setup.html)
- [v0.11.0 Mini Update Patch Notes（SteamDB）](https://steamdb.info/patchnotes/25922370/)、[v0.10.0 Patch Notes（SteamDB）](https://steamdb.info/patchnotes/25077871/)
- [Sims Community：10/15 更新內容](https://simscommunity.info/2026/10/15/inzoi-update-october-15-2026-notes/)、[9/3 更新內容](https://simscommunity.info/2026/09/03/inzoi-update-september-3-2026-release/)
- [Brainstorm with Kjun：MCP Script Modding（10/9）](https://forum.playinzoi.com/t/topic/17644)、[Getting Ready for inZOI's Modding Update（10/2）](https://forum.playinzoi.com/t/topic/17524)、[2026 Roadmap Part 2](https://forum.playinzoi.com/t/topic/8688)
- [Sims Community：Script Mods GenAI 預覽](https://simscommunity.info/2026/10/09/inzoi-script-mods-update-coming-soon/)、[Script Mods & Mod Kit](https://simscommunity.info/2026/10/02/inzoi-update-script-mods-mod-kit/)
- [mixed-news：inZOI 的兩個 MCP 伺服器](https://mixed-news.com/en/inzoi-mcp-servers-ai-assistant-drive-running-game/)
- [Sims Community：2026 路線圖（模組／多人）](https://simscommunity.info/2026/01/02/inzoi-2026-roadmap-part-2/)、[PCGamesN 路線圖](https://www.pcgamesn.com/inzoi/roadmap-free-dlc)、[名人系統預告](https://simscommunity.info/2026/09/25/inzoi-update-1-year-of-kjun/)
- [巴哈姆特：2026 開發路線圖 Part 2](https://forum.gamer.com.tw/C.php?bsn=79062&snA=218)
- [inZOI ModKit（Epic Games Store）](https://store.epicgames.com/p/inzoi-modkit)、[官方模組指南](https://playinzoi.com/guide/mod)
- [CurseForge：The State of inZOI Modding](https://blog.curseforge.com/the-state-of-inzoi-modding-tools-automation-and-whats-next/)

**社群需求**
- [progression and objectives are inzoi's #1 problem](https://forum.playinzoi.com/t/topic/12970)
- [Inspiration Mods to Make inZOI More Realistic and Dynamic](https://forum.playinzoi.com/t/topic/8529)
- [Automatic Rabbit-Hole Careers for NPC Zois](https://forum.playinzoi.com/t/topic/9292)
- [Making inZOI a Deeper and More Connected Life Simulation](https://forum.playinzoi.com/t/topic/17441)
- [Better family story telling](https://forum.playinzoi.com/t/topic/15899)
- [Feature Suggestions to Enhance the Inzoi Experience](https://forum.playinzoi.com/t/topic/12486)
- [Script Mods Options UI tool](https://forum.playinzoi.com/t/topic/11386)
- [Small Details, Big Immersion](https://forum.playinzoi.com/t/topic/15635)
- [UI improvements + less notifications](https://forum.playinzoi.com/t/topic/15040)
- [Pets in inzoi](https://forum.playinzoi.com/t/topic/1348)
- [inZOI Has a New Problem: Players Want Their Zois to Feel Alive](https://mmvasims4.wordpress.com/2026/09/12/inzoi-has-a-new-problem-players-want-their-zois-to-feel-alive/)
- [PC Gamer 評論](https://www.pcgamer.com/games/life-sim/inzois-attempt-to-do-everything-has-left-it-a-shallow-imitation-of-the-sims-and-im-not-sure-it-understands-what-makes-those-games-so-special-in-the-first-place/)、[Eneba 2026 評測](https://www.eneba.com/hub/games/inzoi-review/)
- [Steam 討論區（自主行為）](https://steamcommunity.com/app/2456740/discussions/0/599650036410746232)

**現有模組（競品）**
- [CurseForge 腳本模組列表](https://www.curseforge.com/inzoi/search?class=script-mod&page=1&pageSize=20&sortBy=relevancy)
- [Age of Magic – Witchcraft](https://www.curseforge.com/inzoi/mods/inzoi-age-of-magic-witchcraft)
- [ZoiWorks – Ambitions Pack](https://www.curseforge.com/inzoi/mods/zoiworks-ambitions-pack)
- [ZOI Command Center](https://www.curseforge.com/inzoi/overlay-ui/zoi-command-center-zcc)
- [ZoiWorks – Organized Crime（Nexus）](https://www.nexusmods.com/inzoi/mods/1506)
- [Nexus 熱門模組](https://www.nexusmods.com/inzoi/mods/top)
- [MCCC 文件（Sims 4 參考）](https://deaderpool-mccc.com/documentation.html)
