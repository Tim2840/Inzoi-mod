# 研究 W1：會走動的貓（可行性）

> 工作線 W1（`docs/roadmap.md`）。目標：家裡的貓能自己走動，動畫流暢、不滑步、不瞬移、不 T-pose。
> 環境：遊戲 `20261019.16318.W`、ModKit `20261011.16078`。研究日期 2026-10-21。
> 每一條都標 **已驗證**（遊戲版本、日期、依據）或 **未驗證**。依據分兩種：
> **[查詢]**＝在執行中的遊戲用只讀 MCP 查詢（資料表、資產目錄、`lua_api_lookup`）得到的實際回傳；
> **[畫面]**＝在遊戲裡實際操作並截圖。只看 ModKit 文件或 LuaLS 定義檔的一律標「未驗證（文件）」。

## 結論摘要

（遊戲內結果撰寫中）

## 1. `BP_Void_Cat` 是什麼

| # | 結論 | 狀態 | 依據 |
|---|---|---|---|
| 1.1 | `Object` 列 `DEV_Void_Cat` 的資產是 `/Game/Blueprint/GameObject/Animal/BP_Void_Cat`，範本 `DEV_AnimalObjectVoidCatTemplate` 的資產是 `BP_AnimalObjectVoidCatTemplate`，繼承 `BP_AnimalObjectTemplate`；`isCarriable=false` | 已驗證（20261019.16318.W，2026-10-21） | [查詢] `data.table_get Object/DEV_Void_Cat`、`ObjectTemplate/DEV_AnimalObjectVoidCatTemplate`、`ObjectBP/BP_Void_Cat` |
| 1.2 | 貓的所有動作都是 **VAT（頂點動畫貼圖）**：原版每個貓互動的貓端動作都是 `PlayVATAnim`，`BaseObject=Target`，`S1`＝`AnimGameObject` 列（如 `VoidCat_Tickle`、`VoidCat_Eat`）。全 `Action` 表 6588 列裡，動物端只用 `PlayVATAnim`，沒有一列用 `PlayAnim` | 已驗證（同上） | [查詢] `data.table_get_all Action` 篩選 |
| 1.3 | `AnimGameObject` 列記的是 **AnimMontage 路徑**（例：`VoidCat_Tickle` → `/Game/Characters/Void/Void_Cat/Anim/ANIM_Void_Cat_Welcoming_Interaction_Montage`），`FB2Action_PlayVATAnim` 依此解析出「VAT anim sequence 名稱」送給 B1 播放（定義檔註解） | 列內容已驗證；解析方式未驗證（文件） | [查詢] `AnimGameObject`；`luals-defs/actions/FB2Action_PlayVATAnim.lua` |
| 1.4 | 畫面端（B1）播放 VAT 的元件是 `UB1AnimToTexComponent`（UE AnimToTexture），有 `PlayAnimSequence(名稱, 起始秒)`、`StopAnimSquence()`、屬性 `Animation`（目前的 UAnimSequence） | 型別已驗證（[查詢] `lua_api_lookup`）；貓身上是否掛這個元件見第 4 節 | |
| 1.5 | 資產旁證：`/Game/Characters/Void/Void_Cat/Mesh/StaticMesh` 的包圍盒（47.0×101.6×98.8 cm）和 `ObjectBP/BP_Void_Cat` 的 `size` **完全相同**；骨架網格 `SKM_Void_Cat` 另有一份在 `/Game/BG/Working/JM/MakeVAT/` 底下 → 貓是「由骨架動畫烘焙成 VAT 的靜態網格」 | 已驗證（數據一致）；是推論的佐證，不是直接證明 | [查詢] `asset.get`、`ObjectBP` |
| 1.6 | 原版貓的 Montage（`/Game/Characters/Void/Void_Cat/Anim/`）共 13 個，**其中有走路與跑步**：`ANIM_Void_Cat_Walk_F_Montage`（1.63 秒循環，分類 locomotion-walk）、`ANIM_Void_Cat_Run_F_Montage`（0.67 秒），另有 `Sit_Idle_01/02`、`Stand_Idle`、`Stand_Idle_Base`、`Lying_Idle`、`Eat`、`Being_Patted`、`Give_Gift`、`Take_Food`、`Hissing`、`Scared`、`Welcoming`。另一組 `/Game/Characters/Pets/Anims/`（`ANIM_Cat_Meow_03`、`Cat_Slap_01`、`Cat_Lying_Reaction`、`Nyx_Sitting_Idle_00`）配的是別的貓網格（`SKM_CHA_CatB001`、`SKM_Pet_GhostCat` 等） | 資產存在已驗證；**原版資料沒有任何一列用到走路／跑步**；它們有沒有被烘進 VAT 見第 4 節 | [查詢] `asset.search cat`、`AnimGameObject` 全表 |

## 2. 遊戲裡的動物會不會自己動

| # | 結論 | 狀態 | 依據 |
|---|---|---|---|
| 2.1 | 城市動物（貓、拉不拉多、熊貓、鹿、浣熊、松鼠、狐狸、鱷魚）由 `DA_CityEdit.WorldVATSpawnInfoList` 決定：每張地圖一串**固定座標**（`transformList`），每個座標從 `vATAssetList` 抽一種動物生成（`DEV_Void_Cat` 等）。沒有路徑或移動相關欄位 | 已驗證（同上） | [查詢] `data.asset_get CityEdit` |
| 2.2 | 城市貓在模擬層不會走（P3）；B2 `SetLocationOnlySimul` 只改模擬座標、畫面不動 | 已驗證（2026-10-20，phase0 P3，截圖） | `docs/phase0-results.md` |
| 2.3 | `Object` 表沒有鳥類列；鳥、蝴蝶有骨架網格（`SK_Pigeon`、`SK_Sparrow`…）與 `FX_Butterfly_00x` 物件，屬於特效／環境系統，不是可互動物件 | 列表已驗證；鳥如何飛未研究（與本題無關） | [查詢] `data.list_rows Object`、`asset.search` |
| 2.4 | 資料表的所有「走」動作（`WalkTo*`、`WalkAroundSite` 等 `EB1ActionType`）都由角色執行：`FB2Action_WalkTo.Walker` 型別是 `FB2Character`；`Locomotion` 表只有人類體型列（Adult_F/M、Youth…） | 已驗證（型別與列表）；對物件執行的結果未實測 | [查詢] `lua_api_lookup FB2Action_WalkTo`、`data.list_rows Locomotion` |

## 3. 各方案（桌面判斷，遊戲內結果見第 4 節）

（撰寫中）

## 4. 遊戲內實測

探勘模組 `PawWalkProbe`（不進 repo，程式放在 `Documents\inZOI\Mods\InGame\PawWalkProbe\lua`，用 `luamod.mount` 在主選單掛上）：
B1 綁 `ObjectTemplate`（兩個貓範本）、`Component`（`B1AnimToTexComponent`）、`Zoi`（ResidenceFamily）；B2 綁兩個貓範本。
指令經 `uimod.cfg_save` 寫進 `cmd/next.cfg`，B1 `Main.on_tick` 每 0.5 秒讀；結果寫 `log/b1.cfg`。存檔：朴恩珠（江南），**不存檔**。

### 第一輪（2026-10-21 上午，遊戲 `20261019.16318.W`；後來因用量上限中斷，遊戲由主線重開，未存檔）

| # | 結果 | 狀態 | 依據 |
|---|---|---|---|
| 4.1 | **B1 的 `ObjectTemplate` 綁定會對讀檔時已存在的家貓觸發**，`owner` 是 `BP_Void_Cat_C` 的 actor（`AB1GameObject`）。家裡兩隻召喚貓 109546、109615 都收到 | 已驗證 | `log/b1.cfg` |
| 4.2 | B1 Lua 可以呼叫 **AActor 的反射 UFUNCTION**：`K2_GetActorLocation`、`K2_GetActorRotation`、`GetActorScale3D`、`K2_GetComponentsByClass`、`GetComponentByClass`、`GetName`（定義檔沒列，但呼叫成功）；`UE.FVector`、`UE.UActorComponent` 可取用 | 已驗證 | 同上 |
| 4.3 | 讀檔初期拿到的 actor 參考會失效（位置、縮放回傳 0）；重新載入 B1（`luamod.reload b1`）後綁定再觸發，拿到有效 actor。**實作時要在每次使用前檢查、失效就等下一次 on_begin** | 已驗證（現象）；原因未驗證 | 同上 |
| 4.4 | `BP_Void_Cat` 的元件：`DefaultSceneRoot`、`MeshRootComponent`、`B1AnimPlayerComponent`、**`B1AnimToTex`（UB1AnimToTexComponent）＋`SkeletalMeshComponent_B1AnimToTex`（UB1DummySkeletalMeshComponent）**、**`StaticMesh`、`StaticMeshFur`（StaticMeshComponent）**、`B1GameObjectUROComponent` 等 → **貓是 VAT 靜態網格（外加一層毛的殼），不是骨架網格**，確定 | 已驗證 | `comps 109546` |
| 4.5 | B1 綁定 → `inzoi.message.send_to_sim(貓的實體ID, …)` 到得了 **B2 的貓綁定** `on_lua_message`；B2 用 `send_to_client(同一ID, …)` 回到 **B1 的貓綁定**。B2 讀到同一隻貓的模擬座標與 B1 actor 座標一致（155203.7, −90459.8, 375.5）、所在地 `Gangnam_Residence_Free07` | 已驗證 | `b2 109546 info` |
| 4.6 | 在 B1 以 `PlayAnimSequence("ANIM_Void_Cat_Walk_F", 0)` 呼叫不報錯，但 `Animation` 屬性仍是 nil；當時遊戲處於暫停（`time_scale 0`），畫面無變化，**這一條不能下結論** | 未驗證 | — |
