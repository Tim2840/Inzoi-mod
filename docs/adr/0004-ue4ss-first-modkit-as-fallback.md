# 0004 先走 UE4SS，ModKit 當備案，等 M1 結果再決定要不要雙 adapter

- 日期：2026-10-19　狀態：**暫定（待 M1 實測結果）**　決定者：**PO（使用者）採納雲端 session 建議**
- **背景**：官方 ModKit 的 Lua 路線做不到有 AI、會自己走動的動物（製作人 Kjun：個性、自主行為、情緒、動畫不開放給模組）。UE4SS 路線有機會，但生成貓、走動、AI controller 都尚未在遊戲內驗證。UE4SS 不能走官方 CurseForge 發佈，遊戲更新可能弄壞，且需要放入 `dwmapi.dll`（反作弊風險為推論，無證據）。
- **決定**：
  1. 引擎（`pets/`、`data/`）維持當共用 core（見 ADR 0001），**不重寫**。
  2. 主力開發走 UE4SS adapter；`adapters/inzoi.lua`（官方 ModKit）維持空殼，**暫不投入開發**。
  3. 等 M1-3a／3b（進存檔生成貓、看牠會不會自己走動）的結果再決定：
     - 貓會走動 → 主力維持 UE4SS，ModKit 只當備案。
     - 貓只能當擺設 → 重新評估雙 adapter（ModKit 版可走官方發佈）。
- **後果**：不刪除 `adapters/inzoi.lua` 與 `mod/ui/`（HTML 介面）；UE4SS 版的遊戲內介面（UMG）尚未驗證。仍未決定：每戶隻數、老死、需求 3 或 4 個、最終合併到哪個 repo。
- **觸發重審**：M1-3 實測完成、遊戲大版本更新導致 UE4SS 失效，或發現反作弊／停權的實際證據。
