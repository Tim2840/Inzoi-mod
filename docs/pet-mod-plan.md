# 寵物模組開發計畫：「毛孩之家 Paw Home」（暫定名稱）

> 2026-10-18 · 語系：繁體中文 + English · 目標平台：Windows（Steam）

## 0. 目前進度（2026-10-18）

照 Sims 4《貓狗成群》的玩法做的 **v0.1 寵物引擎已經完成並通過 67 項自動測試**，在不開遊戲的情況下用模擬環境驗證過。細節見 [`sims4-pet-system.md`](sims4-pet-system.md)。

| 項目 | 狀態 |
|---|---|
| 寵物引擎（需求、個性、心情、成長與老死、親密度、訓練技能、照顧動作、疏於照顧→動保員→收容所→付費贖回、領養） | ✅ 完成，`mod/lua/pawhome/` |
| 與遊戲的連接層（adapter） | ⏳ 只有模擬版（`adapters/mock.lua`）；真實版 `adapters/inzoi.lua` 全是待填空，要等第 0 階段探勘 |
| 介面（寵物卡、領養、設定；繁中／英文；深色／淺色） | ✅ 完成，`mod/ui/`；目前在桌面預覽，遊戲內的傳輸層待第 0 階段 P8 |
| 桌面預覽（不開遊戲就能玩玩看） | ✅ `python3 tools/preview_server.py` |
| 遊戲內實測 | ❌ 還沒有，等你的電腦跑第 0 階段探勘 |

> 和下面原計畫的差異：**資料表改用 Lua table 而不是 JSON**（不需要 JSON 解析器，在遊戲的 Lua 環境裡風險最低，社群一樣能直接改數值）。專案結構以實際目錄為準，見 `README.md`。

## 1. 為什麼值得做

- **inZOI 到現在還沒有可以養的寵物。** 搶先體驗至今十次大更新都沒加，官方 2026 路線圖也沒列，12 月更新是名人系統。2025 年 AMA 時官方說過「高優先」，但沒有時程。
- 寵物是心願單上的常客，而且一直有人拿 The Sims 4 付費的「貓狗成群」資料片來對比。
- **目前沒有競品**：Nexus 上的「Cats and Dogs as Pet」只是把動物雕像換成會走動的貓狗，沒有照顧機制；CurseForge 上也沒有 inZOI 的領養模組。
- 遊戲裡已經有能拿來用的東西：
  - **城市流浪貓**：有完整互動，共存值（Coexistence）≥60 才會出現互動選項，可以餵零食、打招呼，每隻貓有各自的關係值。
  - **「城市外觀」動物**：貓、狗、熊貓、鹿、浣熊、松鼠、狐狸、鱷魚。但除了貓，其他目前都只是背景道具。
  - **貓跳台、飼料碗**：遊戲裡有這些物件，但目前沒有任何功能。
- 真的寵物系統哪天上線時，這個模組可以功成身退，或改成「擴充包」。

## 2. 第一版範圍：**只做貓**

官方明說**動畫不會開放給模組**，而全遊戲只有貓同時具備「實體＋動畫＋互動」。所以第一版只做貓，狗要等探勘確認有可用的動畫和互動之後再說。

### 核心玩法

```
遇見流浪貓 → 建立關係（原版共存值與餵食）→ 【領養】→ 貓在家裡生活
     ↑                                                ↓
  動保員帶走  ← 被忽略太久  ← 需求下降 ← 照顧（餵食、玩耍、撫摸、清潔）
  （收容所可付費贖回，親密度減半）
                                                ↓
                                 Zoi 心情加成、貓的親密度與個性成長
```

| 功能 | 說明 | 預計做法 |
|---|---|---|
| 領養 | 關係值夠高的流浪貓可以領養並取名 | Lua 記錄「這隻貓 ID 屬於這個家庭」；入口用 Overlay UI 按鈕（如果能加到原版互動選單更好） |
| 住在家裡 | 貓待在家裡的地塊，Zoi 回家時貓在家 | Lua 定時把貓移回或生成在家裡的地塊（看探勘結果） |
| 寵物需求 | 飢餓、玩樂、親密、清潔，會隨時間下降 | 模組自己用 Lua 計算數值 |
| 照顧動作 | 餵食、玩逗貓棒、撫摸、梳毛 | 能呼叫原版貓互動就用原版的，不行就在 UI 按鈕＋播放現有的貓動畫 |
| 讓物件有用 | 飼料碗可以裝飼料、貓跳台可以讓貓玩 | Data 模組，或用 Lua 偵測 Zoi 使用物件 |
| 寵物卡 UI | 頭像、名字、個性、需求條、親密度 | Overlay UI（HTML/JS） |
| 個性 | 活潑、慵懶、黏人、高冷，影響需求下降速度和事件 | Lua＋JSON 資料表 |
| 後果 | 照顧得好，Zoi 有心情加成；被忽略太久，動保員先警告、再把貓帶回收容所，之後可付費贖回 | Lua |
| 設定 | 需求下降速度、要不要讓動保員帶走被忽略的寵物、最多養幾隻 | Overlay UI 設定頁 |
| 雙語 | 繁中、英文 | 所有字串放在 `localization/zh-TW.json` 和 `en.json` |

### 第一版刻意不做

狗和其他動物、寵物懷孕和繁殖、獸醫職業、寵物用品店、新的 3D 模型和動畫。這些放到後續版本，而且要先看技術可不可行。

## 3. 最大風險：遊戲到底讓不讓我們操作貓

Lua 腳本模組 10/15 才剛推出，正式版只能用 115 個 Public 指令，而且**不知道有沒有能操作動物的指令**。所以**第 0 階段一定要先探勘**，結果決定走哪一套方案：

| 方案 | 前提（探勘要確認） | 玩家體驗 |
|---|---|---|
| **A. 真領養** | 可以取得流浪貓的實體 ID，而且能移動它或讓它跟著 Zoi；存檔讀檔後還在 | 最好：真的是那隻你餵過的貓搬進家裡 |
| **B. 在家生成** | 不能移動流浪貓，但可以在家裡的地塊生成一隻貓 | 好：領養之後，家裡出現一隻外觀相同的貓 |
| **C. 虛擬寵物** | 完全不能操作動物，只有 UI 和 Zoi 相關指令可以用 | 普通：寵物主要活在 UI 裡（像電子雞），照顧動作影響 Zoi 的心情 |

## 4. 開發進程（假設一人兼職，每週約 10–15 小時）

| 週 | 階段 | 主要工作 | 交付物 / 完成標準 |
|---|---|---|---|
| **1** | **0. 環境＋可行性探勘** | 跑安裝腳本、裝好遊戲和 ModKit、連上 MCP；照 `phase0-probe.md` 逐項測試 | `docs/phase0-results.md` 填完，**決定走 A、B 或 C**（決定點 ①） |
| 2 | 1a. 專案骨架 | 建 ModKit 專案；`core/api.lua` 封裝層、排程器、存檔讀寫、日誌；雙語字串檔 | 「Hello Kitty」模組：遊戲裡出現一個 UI 按鈕，按下去會在日誌印出附近貓的資訊 |
| 3–4 | 1b. 領養 MVP | 領養流程、取名、寵物資料存檔、讓貓待在家（照方案 A/B/C） | 領養一隻貓 → 存檔 → 讀檔 → 貓還在家，名字還在 |
| 5 | 2a. 照顧循環 | 四種需求下降、四種照顧動作、寵物卡 UI | 放置 3 個遊戲日，需求會掉；照顧後會回升，UI 同步更新 |
| 6 | 2b. 個性與後果 | 四種個性、Zoi 心情加成、動保員與收容所贖回、飼料碗和貓跳台有功能 | 刻意不照顧 → 貓在設定的天數後離家出走 |
| 7 | 3. 打磨 | 設定頁、繁中和英文校對、效能檢查、錯誤處理；寫測試清單 | 照測試清單全部跑過；朋友試玩 1–2 人（決定點 ②：要不要公開） |
| 8 | **4. 公開 Beta** | 上傳 CurseForge（ModKit 內建上傳）和 Nexus；在官方論壇、巴哈姆特、Reddit 發佈；中英文模組頁面和截圖 | v0.1.0 上架 |
| 9–12 | 5. 擴充（依回饋排序） | 可以養多隻、寵物相簿、獸醫看診（離開地塊型的事件）、寵物用品 BUILD 包（Blender）、**狗**（如果探勘確認可行） | 每兩週出一版小更新 |
| 持續 | 維護 | 每次 inZOI 更新後：重新啟用模組 → 跑測試清單 → 修 `core/api.lua` → 改版本號 → 重新上傳 | 遊戲更新後 48 小時內出相容版 |

## 5. 專案結構（已建立）

```
mod/
├─ lua/pawhome/
│  ├─ core/        util, rng, serialize, log, i18n, api（唯一碰遊戲的地方）, storage（存檔＋版本遷移）
│  ├─ data/        settings, needs, stages, traits, actions, habits, moods, training, names（全是可調的 Lua table）
│  ├─ pets/        registry, needs, traits, moods, aging, bond, training, care, neglect, adoption, engine
│  ├─ localization/ en.lua, zh_TW.lua（測試會檢查兩邊鍵值與佔位符一致）
│  ├─ adapters/    mock.lua（測試與預覽用）、inzoi.lua（待第 0 階段填寫）
│  ├─ app.lua      對 UI 與 adapter 的公開介面＋畫面資料（view model）
│  └─ main.lua     進入點
└─ ui/             index.html, style.css, app.js, bridge.js
tests/             framework.lua, helpers.lua, test_core.lua, test_pets.lua, run.lua, run.py
tools/             preview_server.py, preview_glue.lua
docs/
scripts/
```

原則：

1. 所有遊戲呼叫都集中在 `core/api.lua`，而且每個呼叫都包 `pcall`：遊戲端出錯不會讓寵物邏輯壞掉。
2. 只用 Public 指令，玩家端才保證有效。
3. 寵物資料由模組自己管，不碰原版的個性和自主行為系統（官方的界線）。
4. 所有平衡數值都放在 `data/`，不寫死在程式裡。
5. 模擬用「補算」設計：不管 tick 隔多久（讀檔、快轉），結果都和每小時 tick 一樣，上限 12 小時，避免離開很久回來寵物全死。

## 6. 分工：我們怎麼合作

| 誰 | 做什麼 |
|---|---|
| **你**（Windows 電腦） | 開遊戲和 ModKit、在本機跑 Claude Code、在遊戲裡實測、截圖、在 CurseForge 和 Nexus 上架（需要你的帳號） |
| **本機 Claude Code** | 透過 MCP 直接查遊戲狀態、試指令、把 Lua 寫進 ModKit 專案。**探勘和除錯最有效率的方式** |
| **雲端 Claude（這裡）** | 寫程式架構、UI、資料表、雙語字串、文件、模組頁面文案；透過這個 repo 跟你的電腦同步 |

## 7. 下一步

1. 照 [`setup-windows.md`](setup-windows.md) 裝好環境。
2. 照 [`phase0-probe.md`](phase0-probe.md) 做探勘，把結果填進 `phase0-results.md` 並 push（或直接貼給我）。
3. 我根據結果決定方案，並建立第 1a 階段的專案骨架。

## 參考來源

- [inZOI 還沒有寵物系統（Pet System Wiki）](https://thegameswiki.com/inzoi/wiki/pet-system)、[Pet Care Guide](https://thegameswiki.com/inzoi/wiki/pet-care-guide)、[Animals](https://thegameswiki.com/inzoi/wiki/animals)
- [Digital Trends：How to get pets in inZOI](https://www.digitaltrends.com/gaming/how-to-get-pets-in-inzoi/)、[Game Rant：寵物免費更新傳聞（2025）](https://gamerant.com/inzoi-free-update-pets/)
- [Nexus：Cats and Dogs as Pet (add-on)](https://www.nexusmods.com/inzoi/mods/621)
- [論壇心願單：pets??](https://forum.playinzoi.com/t/topic/12846)、[Pets in inzoi](https://forum.playinzoi.com/t/topic/1348)
- [ModKit 安裝（官方文件）](https://mod-docs.playinzoi.com/docs/modkit-docs/modkit/how-to/getting-started/01install)、[Epic 商店頁面](https://store.epicgames.com/p/inzoi-modkit)
- [Kjun：Getting Ready for inZOI's Modding Update](https://forum.playinzoi.com/t/topic/17524)（動畫和自主行為不開放給模組）
- [CLI Command Finder](https://mod-docs.playinzoi.com/docs/modkit-docs/wiki/cli/commands/)
