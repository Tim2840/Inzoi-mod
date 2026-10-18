# CLAUDE.md — 毛孩之家 Paw Home（inZOI 寵物模組）

給在這個 repo 工作的 Claude Code。先讀這份，再讀 `docs/pet-mod-plan.md` 與 `docs/phase0-probe.md`。使用者說繁體中文，回覆請用繁體中文；程式碼、註解、commit 訊息用英文。

## 專案是什麼

inZOI 目前沒有寵物系統。本模組用官方 ModKit 的 **Lua 腳本模組** 加 **HTML/JS Overlay UI**，照 The Sims 4《貓狗成群》的玩法補上養貓：領養、需求、個性、成長老死、親密度、訓練、疏於照顧被動保員帶走。第一版只做貓。語系：繁體中文、English。

## 現況（務必看清楚哪些做了、哪些沒做）

| 部分 | 狀態 |
|---|---|
| 寵物引擎 `mod/lua/pawhome/`（需求、個性、心情、老化、親密度、訓練、照顧、忽略離家、領養、存檔） | ✅ 完成，67 項測試全過，**只在模擬環境驗證過** |
| 介面 `mod/ui/`（繁中／英文） | ✅ 完成，只在桌面預覽驗證過 |
| `mod/lua/pawhome/adapters/inzoi.lua`（連到真遊戲） | ❌ **全是 `error("TODO(Pn)")` 待填空** |
| UI 在遊戲內與 Lua 溝通的傳輸層 `mod/ui/bridge.js` | ❌ 遊戲內分支還會丟錯（待 P8） |
| 遊戲內實測 | ❌ **一次都沒有做過** |

## 平行專案：ZoiPets（UE4SS 路線）

使用者另有一個本機專案 `C:\Users\user\Desktop\inzoi-pet-mod`（ZoiPets），走 **UE4SS Lua ＋ pak 替換**，已在 inZOI v0.10.0 驗證 UE4SS 可注入、可讀寫檔、找到主選單的貓 actor `BP_Pet_Customize_01_C`。以上是從該 session 的紀錄讀到的，**本 repo 的 session 沒有親自驗證**。兩個專案的關係、差異與建議的處理順序見 [`docs/handoff-ue4ss-session.md`](docs/handoff-ue4ss-session.md)。

- 本 repo 的程式（官方 ModKit 路線）**仍然沒有在遊戲內跑過**。
- 官方 ModKit 路線做不到真正的動物 AI；UE4SS 路線可能做得到，但**尚未驗證**。
- 兩邊如何合併由使用者決定，不要自行刪除或覆寫另一邊。
- **已定案（使用者，2026-10-18）**：疏於照顧**不做離家出走**，改成「軟性懲罰 → 動保員警告 → 帶回收容所 → 可付費贖回（有等待時間、親密度打折）」，與 ZoiPets 一致。其餘規格（老死、每戶隻數、只走 UE4SS 或雙 adapter）**尚未決定**。

## 第一優先：第 0 階段探勘

照 `docs/phase0-probe.md` 在真的遊戲上做，把結果填到 `docs/phase0-results.md`。這份探勘決定走方案 A（真領養）、B（在家生成）、C（虛擬寵物）。

## 規矩

1. **絕對不要捏造探勘結果。** 指令名稱、Lua API、參數、行為，都要是從真的遊戲或 `mod-docs.playinzoi.com` 實際看到的。不確定就寫「未驗證」。
2. **只有 `core/api.lua` 和 `adapters/*` 可以碰遊戲**，其他模組只能呼叫 `Api.*`。遊戲更新時應該只需要改 adapter。
3. **只用 Public 指令**（CLI 目錄 318 個指令只有 115 個是 Public；UserCheat／ScriptCheat 在玩家端是 no-op）。
4. **不要覆寫 Zoi 的個性、自主行為、情緒、動畫**，官方明說不開放給模組。只做宏觀層面（領養、需求、照顧）。
5. `adapters/inzoi.lua` 的 `caps`（`spawn`、`moveStray`、`buffs`、`animate`）**只有在實測過之後才能設為 true**。
6. 新增或修改邏輯時，在 `tests/` 補測試（用 `adapters/mock.lua`），並維持全綠：
   - Windows：`py -I tests\run.py`
   - macOS／Linux：`python3 -I tests/run.py`（需要 `pip install lupa`）
7. 字串一律放 `mod/lua/pawhome/localization/`，**en 與 zh_TW 的鍵與 `{佔位符}` 必須一致**（測試會檢查）。UI 不放任何寫死的文字。
8. 平衡數值放 `mod/lua/pawhome/data/`，不要寫死在程式裡。
9. 存檔格式有版本號：改 `state` 結構要加 `core/storage.lua` 的 migration，不能讓舊存檔壞掉。
10. 資料表用 Lua table，**不用 JSON**（遊戲的 Lua 環境不一定有 JSON 解析器）。
11. 不要把 ModKit 的 Unreal 專案或大型二進位檔直接 commit；先討論要用 `.gitignore` 還是 Git LFS。
12. 桌面預覽：`py tools\preview_server.py` → `http://127.0.0.1:8765/?preview=1`。改 Lua 之後要重啟它。

## 已知未知（探勘要回答）

- Lua 有沒有計時器／遊戲事件？能不能存資料（P7）？
- 能不能找到、移動、生成貓，存檔讀檔後還在嗎（P2–P5）？
- 能不能觸發貓的互動或動畫（P6）？能不能在原版貓互動選單加選項（P9）？
- UI 怎麼呼叫 Lua（P8）？
- 一個遊戲日等於現實多久？（用來重新校準 `neglect.lua` 的「約 2–3 天被動保員帶走」是否太嚴）

## Git

- 開發分支：`ccr-d0885a2d-yzygl2`（也是 repo 預設分支）。若有人同時在雲端 session 改程式，建議本機另開分支再合併，避免衝突。
- commit 訊息用英文、說明為什麼。未經使用者要求不要開 PR。
