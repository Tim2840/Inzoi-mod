# 寵物店介面：手機／電腦入口與視覺設計（U1／U2）

> 工作線 U1、U2（`docs/roadmap.md`），分支 `feat/phone-pc-ui`。
> 每條結論標 **已驗證**（遊戲版本、日期、依據）或 **未驗證**。遊戲版本一律是 `20261019.16318.W`，日期 2026-10-21。

## 0. 結論先講

<!-- ENTRY-SUMMARY -->

## 1. 入口：介面模組怎麼從手機、電腦打開

### 1.1 遊戲提供的掛勾

| 掛勾 | 內容 | 狀態 |
|---|---|---|
| 手機的 App 格（`DA_SmartPhone`） | 資料資產只有寫死的幾個 App 點擊腳本欄位：`InsuranceApp_OnClickedScripts`、`LoanApp_…`、`CityMoveApp_…`、`AdoptionApp_OnClickedScripts`（預設 `Finish_Computer_Use_PhysicalAdoption`）、`AdoptionMedicalApp_…`。**沒有「新增 App」的清單欄位**，App 格本身不能擴充。要改這些欄位得走 DataAsset 工作區（打包），執行中的 `data.patch` 只改資料表。 | 已驗證（文件 `data_asset_schemas/12_mobile.md`；資料表清單 `data.list_tables` 沒有手機 App 表） |
| 輪盤選單 `RadialMenuGroup`／`RadialMenuAction` | `PlayModeRadialGroup.actionSlots` 是固定 8 格（`SmartPhoneRadialAction` 的 `executeHandler=ExecuteSmartPhone` 打開手機）。動作列可以 `bUseInteractionBag=true` 指向一個互動（例：`SmartPhoneCheckRadialAction` → `Self_SmartPhone_Check`）。理論上可加一格，但 8 格是 UI 版面，未測、也不建議動。 | 資料已驗證（`data.table_get`）；改動未驗證 |
| 自己身上的互動選單 `ObjectSelectionSet[Id=SelfCharacter]` | `Normal` 狀態有 564 個互動，其中「使用手機」群組 `Group_Using_SmartPhone` 的就是手機類動作（`Self_SmartPhone_Check`、`Self_SmartPhone_Insurance_CurrentState`…）。把我們的互動 Append 進這個清單、`GroupId` 設 `Group_Using_SmartPhone`，就會出現在點自己 →「手機」子選單裡。 | 資料已驗證；選單顯示見 1.3 |
| 電腦、筆電 `ObjectSelectionSet[Id=Computer01]`、`[Id=Laptop01]` | `Normal`（電腦 316 個、筆電 225 個互動）。原版購物類互動 `Computer_Use_Search_BabyProducts`（「Shop for Baby Care Products」）、查資料 `Computer_Use_Lookup` 可當動作範本。 | 資料已驗證；選單顯示見 1.3 |
| UI 模組的 `interaction_menu` 觸發 | 文件只給一個例子 `{ "type":"interaction_menu", "target":"character", "label_key":"My Action" }`。遊戲執行檔的字串顯示觸發定義還有 `TargetTypes`、`LabelKey`、`icon`、`sub_items`（`B1UIModTriggerSubItem`，含 `FilterJson`）、`context_pass`（`ContextPassFields`），以及 `UB1UIModInteractionInjector`／`B1UIModInteractionItem{TriggerId, SubItemId, ModDisplayName}`——也就是 UI 模組系統自己會往互動選單注入項目。實測見 1.3。 | 欄位名稱已驗證（執行檔字串）；行為見 1.3 |
| `ui_injection` 觸發 | 需要 `target`、`InjectionTarget`／`InjectionPosition`，槽位合約沒有公開。 | 未驗證，不使用 |
| UI 收不到遊戲事件 | manifest 的 `game_event` 觸發不會送進 `inzoi.trigger.onActivated`。 | 已驗證（第 0 階段 P9） |

### 1.2 文字標籤

資料補丁加的互動，選單文字取自 `DisplayInfo.DisplayTextId`（字串表 ID）。已安裝的模組（Baby Crib、PocketMart）用**散檔** `l10n/<文化>_mod/<名稱>.po` 帶自己的字串，`msgctxt` 就是字串 ID（`mod_…`），並列在 `mod_manifest.json` 的 `NonAssets`。
`tools/build_modkit.py` 現在從 `mod/lua/pawhome/localization/*.lua` 的 `game` 區塊產生 `l10n/en_mod/PawHome.po`、`l10n/zh-TW_mod/PawHome.po`（字串 ID `mod_PawHome_<鍵>`），字串仍然只有一個來源。

<!-- ENTRY-RESULTS -->

## 2. 其他 inZOI 介面模組怎麼呈現自己

依據：PO 已安裝的模組（`Documents\inZOI\Mods\88849\…`，只讀 manifest 與明文的資料補丁；HTML／JS 都是加密的 `IZUI` 檔）與 CurseForge 頁面（只看網頁，沒有下載）。

| 模組 | 觸發 | 呈現方式 |
|---|---|---|
| Zoi Command Center | `keybind F8`＋`command zcc.toggle` | 可拖曳的大面板、分頁；頁面說明「按 F8 打開」 |
| Age of Magic Interface | `always_on`（3 個 App）＋`keybind Ctrl+F8`＋`command` | 常駐小元件＋面板 |
| ZoiWorks Love Stories | `always_on`（`love`、`zwhud`） | 頁面寫「打開手機、點 ZoiMatch」；它的資料補丁新增自己的互動群組 `ModLove_Group`（字串 `mod_InteractionBagGroup_ModLove_Group_…`），互動的文字也是 `mod_…` 字串 → 走的是「自己身上的互動選單」＋常駐 UI，不是真的手機 App 格 |
| PL Luxe Baby Crib | `always_on`（`crib_chooser`） | 物件互動後由 Lua 打開選擇器 |
| ZoiRadio、High School Life | `game_mode gameplay` | 遊戲中常駐 |
| Alimony | `always_on` passthrough | 只當資料橋 |

**沒有任何已安裝模組用 `interaction_menu` 或 `ui_injection`。** 共同模式：一個常駐（`always_on`／`game_mode`）的 UI 頁面，由按鍵、聊天指令或遊戲互動（資料補丁＋Lua）叫出面板。
遊戲本身另有「隱藏到啟動器」機制（執行檔字串 `window.__uimod_hideToLauncher`、`userHide`／`userShow`、`BW_Button_Gallery`），未研究。

## 3. 視覺設計

（見 4 之後的截圖；設計原則）

- **身分**：「毛孩之家 線上寵物店」。暖奶油色紙張底（`#fff6ec`）、深咖啡墨線（`#4a2f23`）、粉彩色塊（蜜桃 `#ff9e7a`、玫瑰 `#ff7a93`、蜂蜜 `#ffc857`、薄荷 `#7dcfb6`、天空 `#8ec5ff`、薰衣草 `#c6b3f0`），每個元件是「貼紙」：2–3 px 墨線、大圓角（16–22 px）、往下 3–5 px 的平面陰影。
- **吉祥物 Mochi（麻糬）**：奶油色、額頭三條橘色虎斑、腮紅的貓臉，表情隨寵物心情變（開心、平常、睡覺、難過、生氣、生病）；出現在標題、寵物頭像、空狀態、啟動器、通知。
- **三種外殼、同一份內容**（`mod/ui/app.js` 的 `setShell`）：
  - **手機**（380×760）：粉紅色手機殼，上緣有一對貓耳、瀏海、時鐘；底部分頁列（寵物／領養／設定）用圖示＋文字。
  - **電腦**（960×620）：瀏覽器視窗——紅黃綠三個圓點、分頁標籤、網址列 `pawhome.zoi/shop`、左側導覽列與資金卡；寵物頁分兩欄（左：寵物卡與需求，右：照顧、個性、家具）。
  - **啟動器**（88×88）：圓形蜜桃色貼紙，Mochi 顯示目前寵物心情；有寵物生病、被收容或需求危急時右上角的徽章變紅。關閉手機／電腦時縮回啟動器。
- **遊戲瀏覽器限制**（Coherent Gameface）：不吃 CSS 變數（建置時代換）、沒有 emoji 字形、少數新 DOM 方法不存在；版面只用 flexbox 與 margin（不用 grid／gap），文字全部來自 Lua 在地化檔。

## 4. 自製圖示組

`mod/ui/icons.js`：全部原創繪製的 SVG（48×48 格線，墨線＋平塗），以 `data:image/svg+xml` 的 `<img>` 顯示。開發用總覽頁 `mod/ui/icons.html`（不進遊戲）。

| 名稱 | 畫的是什麼 |
|---|---|
| `cat`（6 種表情） | Mochi 貓臉 |
| `paw` | 肉球 |
| `adopt` | 有貓耳屋頂的房子＋愛心 |
| `food` | 飼料碗（小魚圖案） |
| `play` | 毛線球 |
| `litter` | 貓砂盆＋鏟子（盆上肉球印） |
| `energy` | 月亮＋zz |
| `heart` | 愛心（親密度） |
| `coin` | 印著肉球的金幣 |
| `settings` | 中間是貓臉的齒輪 |
| `shelter` | 收容所（門＋十字招牌） |
| `close` | 圓形 × |
| `vet` | 獸醫提袋 |
| `cuddle`、`groom`、`praise`、`scold`、`get_to_know` | 抱抱、梳子、笑臉星星、驚嘆號對話框、問號對話框 |
| `CatScratcher01`、`CatTower01`、`CatWheel01` | 貓抓柱、貓跳台、貓滾輪（家具卡） |
| `phone`、`computer`、`ear` | 手機、電腦、手機殼貓耳 |

<!-- SVG-RESULTS -->
