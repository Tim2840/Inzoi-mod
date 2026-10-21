# 固定花色（C1 研究）

遊戲 `20261019.16318.W`（Shipping，UE 5.6.1），2026-10-21。「已驗證」= 在執行中的遊戲實際看到（寫明指令或探針與證據）；
「文件」= 只在 ModKit 文件或遊戲附的 `luals-defs` 看到；「未驗證」= 推論，還沒在遊戲裡試過。

## 結論

**可以固定，而且只需要正式（非作弊）的 Lua 綁定。** 花色就是貓材質上的一張貼圖參數 `Color Tex`；
畫面端（B1）的 Lua 綁定在每隻貓的 actor 出現時（讀檔、召喚、走回視野）把它設成指定貼圖，畫面上立刻換色，讀檔後重新套用即可。

- 原版共有 **4 種花色**（已驗證可載入；名稱照貼圖檔名，中文是看截圖取的）：

  | 代號（我們取的） | 貼圖 `/Game/Characters/Void/Void_Cat/Textures/…` | 外觀（截圖） |
  |---|---|---|
  | `orange_tabby` | `Void_Cat_001_D` | 橘色虎斑 |
  | `brown_tabby` | `Void_Cat_001_001_D` | 棕色虎斑 |
  | `calico` | `Void_Cat_001_002_D` | 三花（白底、橘黑斑） |
  | `tuxedo` | `Void_Cat_001_003_D` | 深灰黑、白嘴白腳 |

  以命名規則試載 `Void_Cat_001_004_D`～`_030_D`、`Void_Cat_002_D`、`Void_Cat_002_001_D`～`_005_D` 等都不存在；
  不是窮舉，不能排除別的命名（未驗證）。
- 存檔裡**沒有**花色：每次載入由藍圖重抽，所以我們的花色要記在自己的寵物資料（`pet.coat`），每次 actor 出現就重新套用。
- 不需要自己的物件列、不需要打包資料補丁、不需要作弊指令。

## 1. 問題

- 已驗證（phase0，2026-10-21）：召喚的家貓 `DEV_Void_Cat` 存檔前是橘色虎斑，讀檔後變三花；城市貓實體 89129 跨載入也換過花色。
  實體 ID、座標、互動都保留，只有外觀在每次載入時重新決定。

## 2. 花色不在資料表，也不在存檔

| 查了什麼 | 結果 | 依據 |
|---|---|---|
| `Object` 列 `DEV_Void_Cat`、`Level_Void_Cat`、`DEV_Void_Cat_CahayaTemple` | 都指向同一個藍圖 `/Game/Blueprint/GameObject/Animal/BP_Void_Cat`，`stateVariationId=Normal`；沒有花色欄位 | 已驗證：`data.table_get Object …` |
| `ObjectTemplate` `DEV_AnimalObjectVoidCatTemplate` | 藍圖 `BP_AnimalObjectVoidCatTemplate`、`customizeType=MaterialOnly`、選擇集 `DEV_Void_Cat` | 已驗證：`data.table_get` |
| `StateVariation` 列 `Normal` | 只有狀態 `Normal`，`stateVariations=[]` | 已驗證 |
| 物件自訂表（`ObjectCustomizeMaterialParts` 2670 列、`ObjectChangeMaterialGroup`、`ObjectChangeMeshGroup`、`ObjectCustomizeMaterialGroup`、`ObjectPartsCustomUsage`、`ObjectPartsParamUsage`、`ObjectChangeActorGroup`、`ObjectCustomizeShapeTemplates`） | 沒有貓的列 | 已驗證：`data.list_rows` 比對名稱 |
| `MaterialParamMapping`（225 列）、`Script`（16697 列） | 沒有和貓材質有關的列；唯一用 `ApplyMaterialParameter` 的腳本是作物乾旱 | 已驗證：`data.table_get_all` |
| 家貓 109546：`build.get_customize_info` | `part_count=0`（玩家的物件自訂不涵蓋貓） | 已驗證（Public） |
| 家貓 109546：`entity.get_object_info` | 網格元件 `StaticMesh`、`StaticMeshFur`，網格都是 `/Game/Characters/Void/Void_Cat/Mesh/StaticMesh` | 已驗證（Public） |
| B2 實體 109546：`entity.reflect` | `customizedData=[]`、`appliedMaterialParamContexts=[]`，狀態只有 `Normal/Normal`：**模擬層存檔沒有花色** | 已驗證（UserCheat，唯讀） |

## 3. 花色從哪來（B1 探針）

探針模組 `Documents\inZOI\Mods\InGame\PawHomeCoatProbe`（研究用，不進 repo）：`lua_manifest.json` 只有 B1 的
`ObjectTemplate` 綁定（`DEV_AnimalObjectVoidCatTemplate`、`DEV_E01_AnimalObjectVoidCatTemplate`），在 `on_begin` 用 UnLua 反射讀 actor，
結果用 `uimod.cfg_save` 寫到 `PawHomeCoatProbe/probe/*.cfg`。主選單 `luamod.mount` 後讀朴恩珠（江南）存檔，全程不存檔。

已驗證（2026-10-21）：

1. B1 綁定的 `owner` 是 actor `BP_Void_Cat_C`；`owner:GetEntityId().Value` = B2 的實體 ID（109546、109615）。
2. `owner:K2_GetComponentsByClass(UE.UMeshComponent)` 回 3 個元件：`SkeletalMeshComponent_B1AnimToTex`（`B1DummySkeletalMeshComponent`，0 個材質）、
   `StaticMesh`、`StaticMeshFur`（`StaticMeshComponent`，材質槽 `MI_Void_Cat_001`）。
3. 兩個靜態網格的材質都是**動態材質實例**（`MID_MI_VAT_Cat_*`，父材質 `MI_VAT_Cat`；毛皮 `MID_MI_VAT_CatFur_*`，父 `MI_VAT_CatFur`），
   參數：純量 `StartFrame`、`EndFrame`(451)、`TimeOffset`（每隻不同，錯開動畫）、`Burnt Intensity`、`Dust Intensity`；
   貼圖 **`Color Tex`**——兩隻貓不同（109546 = `Void_Cat_001_001_D`，109615 = `Void_Cat_001_D`），身體與毛皮用同一張。
4. 名稱與路徑：`obj:GetName()` 可用；`UE.UKismetSystemLibrary` 在沙箱裡是 nil，`obj:GetPathName()` 不存在；
   完整路徑可從 `GetOuter()`（套件）的名字得到：`/Game/Characters/Void/Void_Cat/Textures/Void_Cat_001_D`。
5. `UE.UObject.Load("/Game/Characters/Void/Void_Cat/Textures/<名>.<名>")` 載得到貼圖（4 張，見結論表）。

## 4. 換色實驗

已驗證（2026-10-21，同一存檔，不存檔離開）：

| 實驗 | 結果 | 證據 |
|---|---|---|
| 在 B1 對 109615 的兩個 MID 呼叫 `mid:SetTextureParameterValue("Color Tex", 貼圖)` | 兩次都成功；回讀參數已改；畫面上的貓從橘色虎斑變成棕色虎斑 | 前後截圖、`cat_2_after_swap.cfg` |
| 依序套 4 張貼圖並各截一張 | 4 種花色都正常顯示，沒有破圖、閃爍或動畫中斷（VAT 動畫參數沒動） | 截圖（`Filename` 存在暫存目錄，未進 repo） |
| 執行中召喚新貓（`data.patch` 加 `PawHome_SpawnCat`／`PawHome_WelcomeCat`，`interaction.execute`） | **B1 綁定對新召喚的貓也會觸發 `on_begin`**（實體 109934；B2 綁定不會，見 runtime 文件）；藍圖已先抽好（三花），我們在 `on_begin` 改成指定花色，截圖中是深色 | `events.cfg`、截圖 |
| 回主選單（不存檔）→ 重讀同一存檔 | `on_begin` 在讀檔時對每隻已載入的貓觸發，那時藍圖已經抽好花色；我們改掉之後，之後移除探針的套用再回讀，兩隻都還是指定的花色（藍圖之後不會再覆寫） | `events.cfg`、`cat_*_now.cfg` |
| `luamod.remount` | 會對已存在的貓 actor 重新觸發 B1 `on_begin`（開發時方便） | `cat_*_begin.cfg` |
| B1 `ObjectTemplate` 綁定的 `on_tick` | 沒有觸發（探針的計時傾印一次都沒寫出） | 只觀察到一次；未深究 |

其他觀察：
- B1 的 Lua 模組狀態**跨讀檔保留**（探針的事件清單在回主選單、重讀後繼續累積），模組要自己分辨是哪一次載入。
- 同一個遊戲執行期間，109546 兩次載入都抽到 `Void_Cat_001_001_D`、109615 都是 `Void_Cat_001_003_D`；phase0 跨重開遊戲時看過變色。
  抽法是否與遊戲執行有關：未驗證，不影響做法。
- B1 actor 只存在於畫面附近（江南存檔讀檔時只觸發 4 隻，城市裡有 49 隻 B2 貓）；走遠再回來會重建 actor，`on_begin` 會再觸發（推論，未驗證）。

## 5. 被排除的做法

- **資料（自己的物件列＋`StateVariation` 的 `ChangeMaterial`／`ChangeMaterialLayerParam`）**：文件與原版資料顯示可行
  （例如 `StoreCounter01` 的 `Normal` 狀態 `ChangeMaterial MI_HS_FN_StoreCounter01`、作物用 `F1` 指定材質槽；
  `MaterialParamMapping` 可設 `Texture` 參數）。但需要新的 `Object` 列在**讀檔前**存在（要打包 `non_ufs/JsonPatch/Object_patch.json`，
  執行中 `data.patch` 太晚），而且材質是藍圖執行時建立的 MID，`ChangeMaterial` 會整個換掉它、可能弄壞 VAT 動畫參數。未驗證，B1 做法已足夠，不採用。
- **作弊指令**：`build.set_material`、`build.set_object_material`、`build.set_color`、`smartbuild.set_object_texture` 都是 ScriptCheat；
  `UB2CheatManager:B2SetMaterialParam` 是作弊管理器。正式功能不能用（CLAUDE.md 規矩 3）。

## 6. 做法（C2）

1. 引擎：寵物多一個 `coat` 欄位（花色代號，見 `data/coats.lua`），存檔格式升版＋migration（舊寵物依 id 分配一種）。
   收容所的每個候選都帶一種花色；領養時可以改選（`adopt` 多一個 `coat` 參數）。
2. B2 adapter：記下「寵物參考 → 花色」，參考綁定到實體 ID 後，把 `實體ID=貼圖名` 對照表經既有的 B2→B1 訊息送給 B1（頻道 `pawhome:coats`）。
3. B1：新增綁定 `ObjectTemplate`（兩個貓範本）→ `on_begin` 記下 actor 並套色；收到對照表時套到已知的 actor；
   對照表另存在 B1 的 cfg（`coats` 鍵），讀檔時 B2 還沒握手前先用上次的表，避免貓先以隨機花色出現再跳色。
4. 套色只動 `Color Tex`，不碰其他參數。

風險與限制：
- 讀檔後到 B2 握手完成前（約數秒），如果快取不是這個存檔的表，貓會先顯示隨機花色，握手後跳成正確花色（未驗證實際秒數）。
- 只有 4 種花色；要更多花色得自己做貼圖並打包成資產（未研究、不在 C2 範圍）。
- 城市流浪貓的花色仍然每次隨機（我們只固定自己的寵物）。
