# 0001 引擎當 core，遊戲介接用 adapter

- 日期：2026-10-18　狀態：**採用中（待本機 session 確認）**　決定者：雲端 session 提案，PO 授權雙 session 決定
- **背景**：使用者有兩個專案——ZoiPets（UE4SS，已在遊戲內驗證注入與讀寫檔）與 Paw Home（官方 ModKit 路線，寵物引擎完整但從未在遊戲內跑過）。兩邊都採「core 與遊戲介接分離、純 Lua 5.4 可離線測試」。
- **決定**：以 Paw Home 的引擎為 core；每條遊戲路線各寫一個 adapter（`adapters/ue4ss.lua`、`adapters/inzoi.lua`）。第一個要做通的是 UE4SS adapter。
- **後果**：引擎規則的單一來源在 `pets/`、`data/`；adapter 只能透過 `core/api.lua` 的契約；契約變更需雙方同意。ZoiPets 專案的工具與設計書之後再逐步搬入。
