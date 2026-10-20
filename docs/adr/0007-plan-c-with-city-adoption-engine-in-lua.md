# 0007 方案 C（虛擬寵物）＋城市認養，引擎留在 Lua

- 日期：2026-10-20　狀態：**採用**　決定者：**PO（使用者）**　依據：第 0 階段遊戲內實測（`docs/phase0-results.md`，遊戲 `20261019.16318.W`）
- **背景**：第 0 階段在真遊戲上確認了哪些事做得到（計時、每存檔一份的資料、UI、辨識與追蹤城市貓、叫 Zoi 和指定的貓互動、B2⇄B1⇄UI 資料通道），
  也確認了做不到的事：把城市貓帶回家（模擬層移動不反映到畫面）、在家放一隻看得見的貓（物件放得進去、互動可用，但畫面上不渲染）。

## 決定

1. **方案 C 為主**：寵物本體是我們引擎裡的資料（需求、個性、成長、親密度、疏於照顧流程照 ADR 0002／0006），
   以 UI 面板呈現；家裡沒有會走動的 3D 寵物。
2. **加上「城市認養」**：玩家可以認養城市裡某一隻真的流浪貓（以實體 ID 識別）。牠留在原地；玩家去探望、餵牠、跟牠玩，
   原版互動（`Object_Void_Cat_Dev`、`Object_Void_Cat_Tickle`）由 B2 的 `interaction.*` 事件偵測並計入引擎。
   領養入口用資料補丁把自訂互動加進城市貓的互動選單（`ObjectSelectionSet_Dev[Id=DEV_Void_Cat]…InteractionBagList`，Witchcraft 模組已證明可行）。
3. **引擎留在 Lua**（現有 `mod/lua/pawhome/` 與測試沿用），跑在 B2：
   - 時鐘：`time.hour_changed`／`time.day_changed`；貓：`ObjectTemplate` 綁定；照顧：`interaction.*` 事件。
   - 與 UI 的同步：B2 `Zoi/ResidenceFamily` 綁定 ⇄ `inzoi.message`（`send_to_client`／`send_to_sim`）⇄ B1 `Zoi/ResidenceFamily` 綁定
     ⇄ `uimod.cfg_save`／`cfg_load` 輪詢 ⇄ UI。
   - 存檔：狀態由 UI 的 `wf.state` 存進遊戲存檔（Lua 的 `on_savegame`／`on_loadgame` 在預覽模式從沒觸發過）。

## 後果

- `adapters/inzoi.lua` 依上面的通道實作；`caps.spawn`、`caps.moveStray` 維持 false。
- 訊息頻道一律加 `pawhome:` 前綴，只處理自己的頻道（同實體上其他模組的訊息也會送進來）。
- 城市貓的外觀可能每次讀檔都不同（同一個實體 ID 先橘貓後三花），UI 不能宣稱固定花色。
- 待確認：正式安裝（非 ModKit 預覽）時 Lua 存檔鉤子是否觸發；`uimod.cfg_save` 寫的是全域檔，B1→UI 中轉檔不可當存檔用。
- **2026-10-21 補充**：用資料腳本 `SpawnGameObjectToFront S1=DEV_Void_Cat` 可以在 Zoi 面前召喚一隻**看得見**、可互動的貓（Age of Magic／Witchcraft 系列的手法）。
  2026-10-21 已確認**跨存檔保留**（同一實體 ID 與座標），但**花色每次載入重新隨機**。家裡的寵物因此可以有實體外觀；
  要不要改方案、`caps.spawn` 何時設為 true，另開 ADR 由 PO 決定。
