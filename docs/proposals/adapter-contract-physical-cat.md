# 提案：adapter 契約是否要加入「實體貓」資訊（M1-6 草案）

> 狀態：**草案，等 M1-3b 的實驗結果才能定案**。作者：雲端 session。審查者：本機 session。
> 依據只有 `docs/ue4ss-adapter.md`「What is known about in-game cats」。**其餘一律標「未知」，不得猜。**

## 1. 已知與未知

| 項目 | 狀態 | 來源 |
|---|---|---|
| 主選單的貓類別 `BP_Pet_Customize_01_C`，元件有 SkeletalMesh、Capsule、2×AudioComponent，動畫藍圖 `ABP_LobbyCat_C` | **已觀測**（v0.10.0，主選單） | ZoiPets 探索報告 |
| 城市流浪貓是否同一類別 | **未知** | — |
| 該 actor 的屬性、函式、動畫變數 | **未知**（從未 dump） | — |
| 有沒有 AI controller／行為樹 | **無證據** | 掃描沒有專找 |
| 生成貓後能否自己走動 | **未知** | 待 M1-3b |
| 遊戲時間、存檔 key、金錢 API | **未知** | 待 M1-3a／M1-4 |

## 2. 引擎目前對「實體」的依賴（現況）

引擎只使用：`spawnPet`、`bringStray`、`despawnPet`、`entityExists`、`playAnimation(ref, animId)`。它把實體當成**不透明的參考**，不讀位置也不讀狀態。所以**目前契約不需要改**，M1 可以在現有契約下完成。

## 3. 可能的新增（全是「選用」函式；每項都取決於 M1-3b）

| 候選函式 | 引擎用來做什麼 | 啟用條件（需要的證據） |
|---|---|---|
| `entityState(ref)` → `{ exists, x, y, z? }` | 驗證貓還在家附近；之後可做「貓離家太遠就傳回」 | 能讀位置（M1-3b 證據 3） |
| `setBehaviorHint(ref, hint)`（`"sleep"`、`"eat"`、`"play"`、`"cower"`…） | 讓需求與心情反映在貓的行為（累了去睡、餓了去碗邊） | 找到可驅動動畫或行為的介面；**且不覆寫遊戲的自主行為**（規則 4） |
| `householdIds()`／`currentZoi()` | 取代寫死的 ID | M1-4 找到來源 |

## 4. 結論與下一步
- **現在不改契約。** 等 M1-3b 有結果，再依證據把候選函式升為正式提案（新增選用函式＝本機作者＋通知；改必要函式＝雙方 review）。
- 若 M1-3b 結果是「貓不會自己走動、沒有 AI」，則 `setBehaviorHint` 退化為「播放動畫」（現有的 `playAnimation`），不必新增函式。
