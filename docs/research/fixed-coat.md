# 固定花色（C1 研究）

遊戲 `20261019.16318.W`（Shipping，UE 5.6.1）。「已驗證」= 在執行中的遊戲用遊戲 MCP 實際看到（日期與指令寫在後面）；
「文件」= 只在 ModKit 文件（`datatable_docs/`、`cli_catalog.json`）或遊戲附的 `luals-defs` 看到；「未驗證」= 推論，還沒在遊戲裡試過。

> 狀態：**草稿，遊戲內實驗進行中**。結論一節會在實驗後更新。

## 1. 問題

- 已驗證（phase0，2026-10-21）：召喚的家貓 `DEV_Void_Cat` 存檔前是橘色虎斑，讀檔後變三花；城市貓實體 89129 跨載入也換過花色。
  實體 ID、座標、互動都保留，只有外觀在每次載入時重新決定。

## 2. 花色不是從資料表來的

| 查了什麼 | 結果 | 依據 |
|---|---|---|
| `Object` 列 `DEV_Void_Cat`、`Level_Void_Cat`、`DEV_Void_Cat_CahayaTemple` | 三列都指向同一個藍圖 `/Game/Blueprint/GameObject/Animal/BP_Void_Cat`，`stateVariationId=Normal`；沒有任何花色欄位 | 已驗證：`data.table_get Object …`（2026-10-21） |
| `ObjectTemplate` `DEV_AnimalObjectVoidCatTemplate` | 藍圖 `BP_AnimalObjectVoidCatTemplate`、`customizeType=MaterialOnly`、選擇集 `DEV_Void_Cat`；沒有外觀欄位 | 已驗證：`data.table_get` |
| `StateVariation` 列 `Normal` | 只有一個狀態 `Normal`，`stateVariations=[]`（不改材質、不換網格） | 已驗證：`data.table_get StateVariation Normal` |
| 物件自訂表 `ObjectCustomizeMaterialParts`（2670 列）、`ObjectChangeMaterialGroup`、`ObjectChangeMeshGroup`、`ObjectCustomizeMaterialGroup`、`ObjectPartsCustomUsage`、`ObjectPartsParamUsage`、`ObjectChangeActorGroup`、`ObjectCustomizeShapeTemplates` | 沒有任何貓（Void_Cat）的列 | 已驗證：`data.list_rows` 逐表比對名稱 |
| `MaterialParamMapping`（225 列） | 沒有貓的列（都是燈、螢幕、作物、雪人） | 已驗證：`data.table_get_all` |
| `Script`（16697 列） | 沒有任何腳本在改貓的材質；唯一用 `ApplyMaterialParameter` 的是作物乾旱 `Change_Parameter_CropDry` | 已驗證：`data.table_get_all Script` |
| 家貓 109546 的 `build.get_customize_info` | `part_count=0`：玩家的物件自訂系統不涵蓋這隻貓 | 已驗證（Public，2026-10-21） |
| 家貓 109546 的 `entity.get_object_info` | 兩個網格元件 `StaticMesh`、`StaticMeshFur`，網格都是 `/Game/Characters/Void/Void_Cat/Mesh/StaticMesh`（靜態網格＋毛皮殼） | 已驗證（Public，2026-10-21） |
| B2 實體 109546 的 `entity.reflect` | `customizedData=[]`、`appliedMaterialParamContexts=[]`；狀態元件只有 `Normal/Normal`。**模擬層（B2）存檔裡沒有任何花色資料** | 已驗證（UserCheat 唯讀，2026-10-21） |

走路子代理另外查到（主線轉述，2026-10-21 唯讀查詢）：貓是從 `SKM_Void_Cat` 烘焙的 VAT（頂點動畫貼圖）靜態網格，
畫面端元件 `UB1AnimToTexComponent`；城市動物由 `DA_CityEdit.WorldVATSpawnInfoList` 生成（固定位置，從 `vATAssetList` 挑）。

**推論（未驗證）**：花色是畫面端（B1）在貓的 actor 建立時隨機決定的（藍圖或 VAT 元件挑材質／材質參數），
不存進存檔，所以每次載入都重抽。模擬層存檔沒有可以「釘住」的欄位。

## 3. 可能的固定方法

### A. 資料：自己的物件列＋狀態變化（不需要作弊指令）

- 文件＋已驗證的資料：`StateVariation` 的狀態可以帶 `ChangeMaterial`（`AssetPath`=材質實例、`F1`=材質槽）或
  `ChangeMaterialLayerParam`（`S1`=`MaterialParamMapping.Id`）。原版就這樣用：`StoreCounter01` 的 `Normal` 狀態
  `ChangeMaterial /Game/BG/HS/FN/A/StoreCounter01/MI/MI_HS_FN_StoreCounter01`；作物用 `F1=1/2` 換第 1、2 槽。
- `MaterialParamMapping` 欄位：`ParamType`（Scalar／Color／Texture）、`MeshName`（元件名）、`LayerIndex`、`ParamName`、`ValueString`。
- 腳本指令 `ApplyMaterialParameter`（S1=`MaterialParamMapping.Id`）也存在；B2 物件有 `AppliedMaterialParamContexts` 欄位
  （`luals-defs/structs/FB2GameObject.lua`），推測套用過的參數會跟著物件存檔（未驗證）。
- 做法：照 `DEV_Void_Cat` 複製物件列 `PawHome_Cat_<花色>`，只把 `StateVariationId` 換成自己的列，
  `Normal` 狀態裡放該花色的 `ChangeMaterial` 或 `ChangeMaterialLayerParam`；召喚腳本改成生成對應的物件列。
- 前提（都未驗證）：
  1. 要知道每種花色的**材質實例路徑**或**參數名稱與值**——資料表裡沒有，只能從遊戲裡的 actor 讀出來（見 §4 探針）。
  2. 狀態變化要在藍圖隨機挑花色**之後**套用，或藍圖不會再覆寫。
  3. 自己的物件列必須在**讀檔前**就存在：執行中 `data.patch` 的列在讀檔時還沒加上（UI 讀檔後才補），存檔裡的
     `PawHome_Cat_*` 實體可能載不回來。要用打包的 `non_ufs/JsonPatch/Object_patch.json`（建造類模組就是這樣加
     `Object` 列，例如已安裝的 `BUILD_Lighting03_v20` 模組；Witchcraft 用同一機制改 `ObjectSelectionSet_Dev`）。

### B. B1 Lua 每次載入後重新上色

- `luals-defs` 的 `UB1SubMaterialComponent`、`UB1ObjectCustomizeComponent` 只有 Reset 類函式，沒有設定材質的 inZOI API。
- UnLua 反射（`Data/CLI/lua-api-core.txt`：C++ 型別經 UnLua 自動匯出）理論上可以在 B1 的 `ObjectTemplate` 綁定裡拿到貓的
  actor，呼叫引擎的 `K2_GetComponentsByClass`、`GetMaterial`、`SetMaterial`。未驗證：沙箱是否允許、`owner` 是不是 actor。
- 召喚當下的新貓不會觸發綁定（runtime 文件），要等下次載入或另想辦法通知 B1。

### C. 作弊指令（只能用在測試）

- `build.set_material`、`build.set_object_material`、`build.set_color`、`build.reset_material`、`smartbuild.set_object_texture` 都是
  **ScriptCheat**；`UB2CheatManager:B2SetMaterialParam(實體, MaterialParamMapping.Id)` 是作弊管理器。正式功能不能依賴（CLAUDE.md 規矩 3）。
- `build.get_customize_info`、`entity.get_object_info` 是 Public，但只讀。

## 4. 遊戲內實驗（進行中）

探針模組 `Documents\inZOI\Mods\InGame\PawHomeCoatProbe`（不進 repo）：B1 綁 `DEV_AnimalObjectVoidCatTemplate`，
貓出現 3 秒與 25 秒後，把元件、材質路徑與材質參數寫到 `PawHomeCoatProbe/probe/cat_*.cfg`。
