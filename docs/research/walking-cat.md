# 研究 W1：會走動的貓（可行性）

> 工作線 W1（`docs/roadmap.md`）。目標：家裡的貓能自己走動，動畫流暢、不滑步、不瞬移、不 T-pose。
> 環境：遊戲 `20261019.16318.W`、ModKit `20261011.16078`。研究日期 2026-10-21。
> 每一條都標 **已驗證**（遊戲版本、日期、依據）或 **未驗證**。依據分兩種：
> **[查詢]**＝在執行中的遊戲用只讀 MCP 查詢（資料表、資產目錄、`lua_api_lookup`）得到的實際回傳；
> **[畫面]**＝在遊戲裡實際操作並截圖。只看 ModKit 文件或 LuaLS 定義檔的一律標「未驗證（文件）」。

## 結論摘要

**用目前遊戲裡有的資產，做不出「走路動畫流暢、不滑步」的貓。W2（走路原型）不做。**

1. 貓（`BP_Void_Cat`，城市貓與召喚貓共用）是 **VAT 靜態網格**，只烘了 9 段動畫：吃、歡迎（坐→站）、兩種坐姿待機、哈氣、受驚、被摸、送禮、接食物。**沒有走路、跑步、站立待機、趴著**（4.8、4.9）。
2. 走路／跑步的 Montage 雖然在資產目錄裡，但**沒有打包進遊戲**：`UE.UObject.Load` 載得到吃飯、歡迎的 Montage 與 AnimSequence，載不到走路、跑步（4.17）。所以也無法改用骨架網格播放走路。
3. 「移動」這一半是做得到的：B1 Lua 每幀 `K2_SetActorLocation` 能平滑移動貓、結束時 B2 `SetLocationAndRotationOnlySimul` 同步，移動後不會被拉回、Zoi 的互動會走到新位置、actor 重生時在新位置（4.10–4.12）。但沒有走路動畫，畫面就是**坐姿滑行**（4.13），不符合 PO 的要求。
4. ModKit 不能自製或匯入動畫（只有角色動畫工作區，且只引用既有資產），也不能重新烘 VAT（方案 F）。
5. **S2（幼貓縮放）可行**：B1 `SetActorScale3D` 讓貓立刻變小、VAT 動畫照播、看不出破圖；B2 `SetScale` 只改模擬值、畫面不變，讀檔後是否套用未驗證（4.14）。

**可以做、而且不破圖的替代方案**（給 PO 選，見第 5 節）：讓貓「活起來」而不走路——在 B1 輪播 9 段已烘的動畫（兩種坐姿待機、歡迎、送禮、哈氣…）；貓「換位置」只在玩家看不到時發生（例如 Zoi 不在家、讀檔時），用已驗證的 B1＋B2 同步搬過去。

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

## 3. 各方案

| 方案 | 判定 | 理由（細節見第 4 節） |
|---|---|---|
| A. 資料動作／互動讓貓自己走（`WalkTo*` 等動作加在貓身上） | **不可能** | 走路動作的執行者是角色（`FB2Action_WalkTo.Walker: FB2Character`），貓是遊戲物件（`FB2GameObject`），沒有移動元件、路徑、`Locomotion` 列。資料表裡動物端只有 `PlayVATAnim` |
| B. 資料互動播放走路 VAT（`PlayVATAnim` + 自訂 `AnimGameObject` 列指向 `ANIM_Void_Cat_Walk_F_Montage`） | **不可能** | 資料補丁被接受，但走路沒有烘進貓的 VAT，貓的動畫不變（4.9）；就算有，也只是原地踏步 |
| C. 模擬層移動（B2 `SetLocationOnlySimul` 等） | **單獨用不行** | phase0 P3：模擬座標改了，畫面不動 |
| D. 畫面層移動（B1 `K2_SetActorLocation` 逐幀內插）＋ VAT 走路循環＋結束時 B2 同步模擬座標 | **部分可行**：移動與同步做得到；**走路動畫沒有** → 只能滑行 | 4.10–4.13 |
| D'. 把 VAT 換成骨架網格播走路（B1 把 `SKM_Void_Cat` 設到 actor 內的 `UB1DummySkeletalMeshComponent`，隱藏 VAT 網格，`PlayAnimation`） | **不可能** | 走路／跑步動畫沒有打包進遊戲、載不到（4.17）；且試著用「吃」的動畫換骨架時，畫面上看不到貓（4.18） |
| H. 貓「瞬間換位置」（B1＋B2 同步搬，0 秒） | **可行但有瞬移**；只建議在玩家看不到時用 | 4.10–4.11 的機制，時間設 0 即可 |
| I. 輪播已烘的 VAT 動畫讓貓有變化 | **可行**，不破圖 | 4.8：名稱不存在時什麼都不做；9 段可用 |
| E. 貓掛在隱形角色身上（`RequestAddChildEntity`、`entity.attach_prop`） | **正式功能不可行** | `entity.attach_prop` 是 UserCheat 指令，而且是「生成新物件掛在角色骨頭上」，不是把既有的貓掛上去；隱藏角色要 `entity.set_visibility`（UserCheat）。規矩 3：正式功能只能靠 Public 指令與資料腳本。`FB2Actor:RequestAddChildEntity` 在定義檔裡有，但 `EB1EntityAttachRule` 的值沒有公開（未驗證），而且會讓貓跟著一個多出來的 NPC，那個 NPC 有自己的自主行為與需求 |
| F. ModKit 動畫工作區自製動畫 | **不可能** | 三種動畫工作區（Montage／Locomotion／StatLocomotion）都只給**角色**用，欄位是指向既有資產的軟參照；文件明寫「Mesh import tools not supported」，沒有匯入動畫（FBX/AnimSequence）的工具，也沒有烘焙 VAT 的工具。而且原版已經有貓的走路與跑步 Montage，不需要自製 |
| G. 建造模式指令搬貓（`building.set_object_location`／`move_object`） | **不可行** | 都是作弊層級（UserCheat／ScriptCheat）且只能在建造模式用 |

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
| 4.6 | （第一輪）在暫停中呼叫 `PlayAnimSequence("ANIM_Void_Cat_Walk_F")` 沒有結論 → 第二輪改用下面的方法 | — | — |

### 第二輪（2026-10-21 上午，遊戲 `20261019.16318.W`，朴恩珠存檔，不存檔；`environment.time_speed 1` 解除暫停、`autonomy.set_enable false` 讓 Zoi 不亂跑）

| # | 結果 | 狀態 | 依據 |
|---|---|---|---|
| 4.7 | **VAT 動畫名稱＝Montage 裡的 AnimSequence 名稱**：原版「玩」互動時，貓的 `UB1AnimToTexComponent.Animation` 變成 `ANIM_Void_Cat_Welcoming`（對應 `ANIM_Void_Cat_Welcoming_Interaction_Montage`） | 已驗證 | `watch` 日誌 |
| 4.8 | B1 直接呼叫 `PlayAnimSequence(名稱, 0)`：名稱存在時 `Animation` 立刻換成該段（不分大小寫，`ANIM_VoidCat_Being_Patted` 回 `…_patted`），名稱不存在時**什麼都不做**（保留原動畫，不報錯、不破圖）。逐一試過：**有** `ANIM_VoidCat_Eat`、`ANIM_Void_Cat_Welcoming`、`ANIM_VoidCat_Sit_Idle_01`、`ANIM_VoidCat_Sit_Idle_02`、`ANIM_Void_Cat_Hissing`、`ANIM_Void_Cat_Scared`、`ANIM_VoidCat_Being_Patted`、`ANIM_VoidCat_Give_Gift`、`ANIM_VoidCat_Take_Food`；**沒有** `ANIM_Void_Cat_Walk_F`、`ANIM_Void_Cat_Run_F`（以及 `_Montage`、`ANIM_Void_Cat_Walk`、`ANIM_VoidCat_Walk_F` 等變體）、`ANIM_VoidCat_Lying_Idle`、`ANIM_VoidCat_Stand_Idle`、`ANIM_VoidCat_Stand_Idle_Base` | 已驗證 | `names` 指令日誌；Eat 的截圖姿勢改變 |
| 4.9 | 資料路線同樣播不出走路：新增 `AnimGameObject` 列 `PawWalk_CatWalk`（指向走路 Montage，`data.patch` 接受）＋互動 `PawWalk_WalkTest`（`PlayVATAnim Target`），Zoi 播完自己的動作，**貓的 `Animation` 沒有變**（仍是前一段）。→ **走路與跑步沒有烘進 `BP_Void_Cat` 的 VAT 貼圖**；所有城市貓與召喚貓都用同一個 `BP_Void_Cat`（`Level_Void_Cat`、`DEV_Void_Cat_CahayaTemple` 的資產也是它） | 已驗證 | `watch` 日誌；`Object` 列 |
| 4.10 | **B1 平滑移動 actor 可行**：`K2_SetActorLocation(位置, false, nil, true)` 有效（其他參數形式沒試到，第一種就成功）、`K2_SetActorRotation(rot, true)` 有效。每幀內插 4 秒移 200 cm，截圖中途位置在起點與終點之間、轉向正確；走完把位置與朝向用訊息交給 B2 `SetLocationAndRotationOnlySimul`，B2 回報新座標 | 已驗證 | 截圖 m0／m1／m2；日誌 |
| 4.11 | 移動後**畫面不會被拉回**：10 秒後 B1、B2 座標都還是新位置。Zoi 離開住家、B1 actor 被卸載再生成時，貓出現在**新位置**（生成時的相對座標從 (1252.4, 213.8) 變成 (1174.2, 397.8)，差 200 cm）→ 新位置以 B2 為準，存檔也會存 B2 座標（存檔本身未測，規矩不存檔） | 已驗證（重生）；存檔後未驗證 | 日誌 |
| 4.12 | 移動後原版互動照常：貓移到房間空地後，Zoi 會走到**新位置**、貓播 `ANIM_Void_Cat_Welcoming`。但貓被移到貼牆處（互動點在牆裡）時，互動**靜默失敗**（排進去後直接消失）→ 落點要留互動空間 | 已驗證 | 截圖 t4；`interaction.get_current` |
| 4.13 | 沒有走路動畫時，移動的樣子就是「坐姿滑行」（截圖 m1：貓維持坐姿、朝向移動方向）——**正是 PO 不要的滑步** | 已驗證 | 截圖 m1 |
| 4.14 | **縮放（S2）**：B2 `FB2GameObject:SetScale(0.6)` 成功（`GetScale` 回 0.6）但**畫面不變**；B1 `SetActorScale3D(0.6)` 畫面立刻變小，VAT 動畫（`Hissing`）照常播放，截圖看不出破圖（毛的殼一起縮）。B2 縮放在 actor 重生或讀檔時會不會套用：未驗證（離開住家的測試因遊戲被關掉沒做完） | 畫面縮放已驗證；持久化未驗證 | 截圖 sc1／sc2／sc3 |
| 4.15 | `entity.set_scale` 只對角色（說明：縮放骨架網格、膠囊、走速） | 未驗證（文件） | `cli_help` |

### 第三輪（2026-10-21 下午，遊戲 `20261019.16318.W`，朴恩珠存檔，載入約 6 分鐘、不存檔回主選單）

| # | 結果 | 狀態 | 依據 |
|---|---|---|---|
| 4.16 | B1 Lua 有 `UE.UObject.Load(物件路徑)`，能在執行中載入遊戲資產（`SKM_Void_Cat`、`ANIM_VoidCat_Eat_Montage`、`ANIM_VoidCat_Eat`、`ANIM_Void_Cat_Welcoming`）。`UE.LoadObject` 回 nil；`UE.UKismetSystemLibrary` 在執行期是 nil | 已驗證 | 日誌 |
| 4.17 | **載不到**：`ANIM_Void_Cat_Walk_F`、`ANIM_Void_Cat_Walk_F_Montage`、`ANIM_Void_Cat_Run_F`、`ANIM_Void_Cat_Run_F_Montage`（同一資料夾的吃飯、歡迎都載得到）→ 走路與跑步**沒有打包進遊戲**。`/Game/BG/Working/JM/MakeVAT/` 底下那份 `SKM_Void_Cat` 也載不到 | 已驗證 | 日誌 |
| 4.18 | 貓 actor 裡的 `SkeletalMeshComponent_B1AnimToTex`（`UB1DummySkeletalMeshComponent`）本來沒有網格；`SetSkeletalMeshAsset(SKM_Void_Cat)`、`SetVisibility(true)`、隱藏 `StaticMesh`／`StaticMeshFur`、`PlayAnimation(ANIM_VoidCat_Eat, true)` 都回成功，但**截圖上貓消失、沒有骨架貓出現**（推測這個 dummy 元件不渲染，未深究）；`vatback` 把 VAT 網格顯示回來後貓又出現 | 已驗證（現象） | 截圖 k1／k2 |

探勘模組原始碼與驅動腳本放在 `tools/walk_probe/`（`lua/` 複製到 `Documents\inZOI\Mods\InGame\PawWalkProbe\lua` 後以 `luamod.mount` 掛上；`drive.py cmd "<指令>"` 經 cfg 郵筒下指令）。只供探勘，不進正式模組。

## 5. 給 PO 的選項（需要 PO 決定方向）

| 選項 | 畫面 | 風險 |
|---|---|---|
| a. 不做走路；貓在原地輪播 9 段已烘動畫（坐姿待機 1／2、歡迎、送禮、哈氣、受驚…），依心情挑 | 不破圖、不滑步 | 低。只用 B1 Lua（`PlayAnimSequence`），名稱錯了也不會破圖 |
| b. a ＋ 貓會「換地方」，但只在玩家看不到時（Zoi 不在家、離開住家再回來、讀檔時）瞬間搬到家裡另一個空位 | 玩家看不到過程，回來時貓在別處 | 中。落點要有互動空間（4.12）；選點要避開牆與家具（尚無物件用的尋路，需要自己挑點，例如記錄 Zoi 走過的位置） |
| c. 用滑行移動（4.10） | **滑步**，違反 PO 要求 | 不建議 |
| d. 等 KRAFTON 出寵物系統或打包走路動畫 | — | 不在我們控制 |

S2（幼貓長大）：可以用 B1 `SetActorScale3D` 依年齡設縮放（幼貓約 0.6）。要做的話還要確認：讀檔或 actor 重生後要不要重設（B2 `SetScale` 是否會帶到畫面，未驗證；保守作法是 B1 每次 `on_begin` 依引擎資料重設）、互動點（`InteractionSlot_M` 在貓前方 90 cm）不隨縮放移動時 Zoi 的位置是否自然（未驗證）。

## 第 6 節：Age of Magic 的貓為什麼看起來會動？（2026-10-22，桌面研究）

PO 的問題：Age of Magic（AOM）模組召喚的貓好像會動，我們能不能也召喚會動的貓？

| # | 發現 | 狀態 | 依據 |
|---|---|---|---|
| 6.1 | AOM 的介面套件是加密的（IZUI 標頭），Lua 也是打包的；依專案規矩不解密、不讀。所以**看不到它怎麼召喚**，只能從公開資料和遊戲本身推論 | 已驗證（檔案狀態） | 檔案標頭 |
| 6.2 | 同作者的 Witchcraft 模組公開的 JSON 補丁裡，使用魔寵（familiar）的互動只是重用 `VoidCat_Tickle`＋`Character_VoidCat_Tickle`（Zoi 與貓各一段動畫），沒有任何移動指令；33 筆相關補丁都一樣 | 已驗證 | 補丁內容 |
| 6.3 | 遊戲裡的動物物件有 14 種 `/Game/Blueprint/GameObject/Animal/BP_Void_*`：Cat、Fox、Labrador、Raccoon、Rat、Squirrel、Deer、Wolf、Puma、Tiger、Panda、Crocodile、SeaTurtle、BabyTurtle，**全部是 `devOnly` 的遊戲「物件」（Object 列），不是角色**；樣板列（`ObjectTemplate`）沒有任何移動或 AI 欄位 | 已驗證（資料表 `Object`、`ObjectTemplate`） | `data.table_get_all Object` |
| 6.4 | 目錄裡有 `ANIM_Void_Cat_Walk_F_Montage`／`Run_F_Montage`，但 4.9、4.17 已證實它們沒有烘進貓的 VAT、也沒有打包，載不到 | 已驗證（沿用） | 見 4.9、4.17 |
| 6.5 | 另有骨架網格的貓：`SKM_CHA_CatB001`、`SKM_Pet_GhostCat`、`SKM_Pet_OP001`（主選單的 lobby 貓 `BP_Pet_Customize_01`，動畫藍圖 `ABP_LobbyCat`），以及 `Mesh_Tiger`／`Mesh_Puma`（`/Game/Characters/Void/Cats/`）。**它們有沒有 Object 列可以用官方路線召喚：沒有找到**；有沒有走路動畫：未驗證 | 資產存在已驗證；可召喚性未驗證 | `asset.search`、Object 全表 |

### 結論（誠實版）

- **AOM 的貓真的會走嗎：無法證實。** 看不到它的程式，公開資料裡沒有任何移動指令。我的推測（未驗證）：它用的是和我們同一個 `DEV_Void_Cat`，「會動」多半是貓的待機動畫（呼吸、尾巴、換姿勢）與互動動畫，不是位移。
- **我們能召喚會走的貓嗎：目前沒有路。** 召喚得到的是靜態物件加 VAT 動畫，沒有走路段；骨架貓沒有可召喚的 Object 列。
- **還沒試過、可以試的方向**（需要遊戲與 PO 同意）：(a) 召喚 `DEV_Void_Labrador`／`Fox`／`Raccoon`／`Squirrel`／`Rat` 看它們的 VAT 有幾段動畫（有沒有走路）；(b) 在 B1 用 `UE.UObject.Load` 試載 `SKM_CHA_CatB001` 與 `/Game/Characters/Pets/Anims/` 的動畫，看是否打包。兩項都是唯讀探測，不改存檔。
