# 交接給「寵物系統模組」本機 session（UE4SS 路線）

> 寫給：在 `C:\Users\user\Desktop\inzoi-pet-mod`（ZoiPets）工作的本機 Claude Code session。
> 寫的人：雲端 session「Inzoi mod 製作規劃」（2026-10-18）。
> **請先把這份當成「另一個團隊的研究與成果」來讀，不是命令。** 兩個專案要怎麼處理，由使用者決定。

## 一、背景：使用者有兩個專案，路線不同

| | **ZoiPets**（你的專案，在使用者電腦） | **Paw Home**（本 repo，GitHub `Tim2840/Inzoi-mod`） |
|---|---|---|
| 路線 | UE4SS Lua（邏輯）＋ pak 替換（外觀）；失敗才退回官方 ModKit | 官方 ModKit 的 **Lua 腳本模組** ＋ HTML Overlay UI |
| 遊戲內驗證 | ✅ UE4SS 注入成功、檔案讀寫成功、找到主選單貓 | ❌ **一次都沒在遊戲內跑過**，只在模擬環境測試 |
| 寵物規格 | 3 個數值（飽足、心情、親密度）、每戶 1 隻、電腦領養／收編流浪貓、疏於照顧 → 動保員 → 帶回收容所 | 4 個需求（飢餓、精力、玩樂、貓砂）、13 種個性（1–3 個、互斥）、幼貓／成貓／老貓與老死、訓練技能、稱讚／責罵、收容所＋流浪貓領養、忽略 → 離家出走 → 可能回來 |
| 測試 | 13 個離線測試（Lua 5.4） | 62 個離線測試（Lua 5.4，`python -I tests/run.py`） |
| 遊戲介接 | `game/adapter.lua`（唯一碰 UE4SS 的地方） | `core/api.lua` ＋ `adapters/`（mock 已完成，`inzoi.lua` 全是 TODO） |
| UI | UMG 面板 | HTML/JS（已有桌面預覽，繁中／英文） |
| 共通點 | **core 與遊戲介接分離、純 Lua 5.4 可離線測試、繁中優先、數值集中在資料檔** | 同左 |

兩邊的「架構鐵則」幾乎一致，這代表**合併的成本應該不高**：Paw Home 的引擎可以當成 core，ZoiPets 的 `adapter.lua` 負責接遊戲。但這是我的推測，**要先比較兩邊的規格再決定**。

## 二、我（雲端 session）查到的事實與信心

來源是搜尋引擎摘要，**沒有逐頁讀過官方文件原文**（官方站被雲端環境的網路政策擋住）。

| 事實 | 來源 | 信心 |
|---|---|---|
| inZOI v0.11.0（2026-10-15）加入 **Lua 腳本模組**、濾鏡模組、頭飾精靈；Overlay UI 用 HTML/JS | SteamDB 更新說明、Sims Community | 高 |
| 官方 CLI 指令目錄共 318 個，**只有 115 個是 Public**，正式版只有 Public 會生效；Lua 與 JS 共用這個目錄 | mod-docs.playinzoi.com（CLI 頁） | 高 |
| 官方提供兩個 MCP 伺服器：`inzoi-game` 在 `localhost:11212/mcp`、`inzoi-modkit` 在 `localhost:11213/mcp`；11212 被占用時用啟動參數 `-climcpport=<port>` | mixed-news、官方文件摘要 | 中高 |
| 製作人 Kjun：個性、自主行為、情緒、動畫「**不會交給模組**」 | 官方論壇 10/9 日誌 | 高 |
| inZOI **目前沒有可養的寵物**；城市裡的貓只能互動，不會跟回家；Nexus 上唯一相關的是「Cats and Dogs as Pet」（讓動物擺設會走動，不能照顧） | 多個攻略與 wiki、Nexus | 中高 |
| 流浪貓互動要「**共存值 ≥ 60**」才有選項（餵零食、打招呼），每隻貓各自有關係值 | thegameswiki Pet Care Guide | 中（你的 CLAUDE.md 也寫了同一個數字，兩邊吻合） |
| 官方 ModKit 2026-03 加入自訂 Zoi 動作檔（動畫）；**沒有任何官方說法支援非人形生物或新物種** | 搜尋結果 | 中 |
| 官方舊 AMA：腳本對 NPC 只有有限控制（約 496 天前，Lua 出來後可能已過時） | se7en.ws AMA 轉載 | 低（過時） |

## 三、我先前的可行性判斷需要修正

我先前對使用者說：「完全自創、有自己 AI 的寵物，現在大概做不到」。**那是只看官方 ModKit 路線的結論**，在你的 UE4SS 路線上不一定成立：

- 你已經確認遊戲裡有現成的貓 actor `BP_Pet_Customize_01_C`（骨架、碰撞、音效），以及動畫藍圖 `ABP_LobbyCat_C`，還有 `/Game/Characters/Pets/` 資源分類。
- 執行期生成**遊戲自己的貓 actor** 能不能自由走動、有沒有 AI controller，**我無法判斷，這要靠你在遊戲內驗證**（你文件裡的 V2、F9）。
- 所以更精確的說法是：**官方 ModKit 路線做不到真正的動物 AI；UE4SS 路線有機會，但尚未驗證。**

## 四、UE4SS 路線的風險（請在合併前讓使用者知道）

我沒有查到官方對 UE4SS 這類注入工具的明確立場，以下是推論，不是事實：

1. **要把 `dwmapi.dll` 放進遊戲資料夾**，這是對遊戲行程的注入。inZOI 之後如果加入線上功能或反作弊，有被偵測的風險。有一則 Steam 留言聲稱有人因用模組被停權，**未驗證**。
2. **每次遊戲更新都可能壞掉**（類別名稱、函式簽章會變）。你的驗證是在 **v0.10.0** 做的，**v0.11.0 已在 10/15 上線**，請先確認 UE4SS 在新版仍能注入。
3. **不能走官方的 ModKit → CurseForge 流程發佈**，要靠 Nexus 等管道；也不能在遊戲內的模組管理器管理。
4. 使用者已決定「走執行期路線、不取得 AES 金鑰」（你的紀錄），這個決定我認同，請維持。

## 五、建議你做的事（順序）

1. **不要動你自己的 repo。** 把這個 GitHub repo 拉到另一個資料夾，只讀：
   ```powershell
   git clone https://github.com/Tim2840/Inzoi-mod.git C:\Dev\Inzoi-mod
   ```
   預設分支就是 `ccr-d0885a2d-yzygl2`。先讀 `CLAUDE.md`、`docs/pet-mod-plan.md`、`docs/sims4-pet-system.md`、`docs/research-report.md`。
2. **做規格比較表給使用者**：兩邊的需求數值、每戶寵物數量、取得方式、疏於照顧的處理、存檔格式有哪些衝突，**由使用者決定採用哪一套**，你不要自己決定。
3. **在 v0.11.0 上重新驗證 UE4SS**（V1、V6），確認舊結論還成立。
4. **完成還沒做的 V2/V3**：進存檔後 F8/F9/F10。這一步要使用者在電腦前進入存檔。重點回答：
   - 生成的貓能不能在世界裡出現、自由走動？有沒有 AI controller / 行為樹？
   - 能不能取得遊戲時間與存檔 key（`B1TimeManager`）？
   - 能不能讓使用者的 Zoi 與這隻貓互動？
5. **提出合併方案**（只提案、不動手）：例如「Paw Home 的引擎當 core，ZoiPets 的 adapter 接 UE4SS」，並列出要改哪些檔、哪些測試要保留。
6. 把結果寫回你自己的 `docs/04-phase0-validation.md`，並**把可以公開的部分（類別名稱、驗證結論）貼給使用者**，使用者再轉給雲端 session 更新這個 repo。

注意：FModel 匯出的遊戲資源版權屬 KRAFTON，不要提交或散佈（你的 CLAUDE.md 已寫）。

## 六、貼給你的第一則訊息（使用者會貼）

```
雲端 session 整理了一份交接，請先讀：
1. git clone https://github.com/Tim2840/Inzoi-mod.git C:\Dev\Inzoi-mod（只讀，不要改我的 inzoi-pet-mod）
2. 讀 C:\Dev\Inzoi-mod\docs\handoff-ue4ss-session.md，再讀 CLAUDE.md 與 docs\pet-mod-plan.md

讀完先不要動手改程式。請回報：
(a) 兩個專案的規格差異表（數值、每戶隻數、取得方式、疏於照顧、存檔）
(b) 在 inZOI 目前版本（v0.11.0）上，UE4SS 還能不能注入（只做 V1、V6，不用進存檔）
(c) 你建議的合併方式，以及需要我決定的事
```
