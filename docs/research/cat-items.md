# 原版貓用品（S1 研究）

遊戲 `20261019.16318.W`，2026-10-21，全部是唯讀查詢（`data.table_get`、`data.list_rows`、`l10n.get`）。

## 物件

| 物件列 | 英文名稱 | 範本 | 篩選分類 | 價格 | 互動 |
|---|---|---|---|---|---|
| `CatTower01`（另有 `_v01`） | Cat Tower | `Decoration01_Template` | `Pet` | 115 | 只有裝飾類共用互動（選擇集 `Decoration01`） |
| `CatScratcher01` | Cat Scratcher | `Decoration01_Template` | `Pet` | 39 | 同上 |
| `CatWheel01` | Cat Wheel | `Decoration01_Template` | `Pet` | 169 | 同上 |
| `CatToy01` | Cat Toy | `CatToy01_Template` | `User_DEV` | 15 | 撿起、放下、收進背包（`Common_Carriable_Pickup_AutoClean`） |
| `CatPuree01` | Cat Treat | `CatPuree01_Template` | `Dev` | 10 | 同上 |
| `CatLeaf01` | Catnip Candy | `CatLeaf01_Template` | `User_DEV` | 10 | 同上 |
| `E01_CatSandSpray01` | Special Cat Spray | `CatSandSpray01_Template` | `Pet` | 10 | — |
| `E01_CatShop01` | Cat Goods Stand | `CatShop01_Template` | `Dev` | 250 | 選擇集 `CatShopDesk01`：`Object_CommonMarket_Open`；營業時賣 `Buy_CahayaTemple_CatFood`、`_CatLeaf`、`_CatTalisman`、`_CatToy`、`_CatArtLatte` |

- 「Pet」是建造模式裡的分類，**跳台、抓板、滾輪是玩家可以直接買來擺的**（`devOnly=false`）。
- 它們在原版只有裝飾作用，沒有給貓或 Zoi 的互動。
- 貓零食、貓薄荷、玩具是背包道具，原版在 Cahaya 寺廟的貓用品攤買（Cahaya 在選城畫面標示為 DLC，未驗證是否所有玩家都有）。

## 用法（決定）

1. **貓家具＝環境加成**（不需要新互動，也不用遊戲字串）：家裡每種貓家具讓對應需求下降變慢，並稍微提升心情。
   - 抓板 → 玩樂；跳台 → 玩樂與精力；滾輪 → 玩樂。
   - 偵測方式：B2 以 `GetAllEntities(GameObject)` 找家裡、`GetObjectTableId()` 為上表物件列的物件（和找召喚的貓同一個方法，已驗證）。
   - 數值放 `mod/lua/pawhome/data/enrichment.lua`。
2. 背包道具（零食、玩具）：之後評估「在面板商店買，計入寵物的庫存」，不依賴 DLC 的攤位。

## 未驗證

- 上述物件擺在家裡之後，`GetObjectTableId()` 回傳的是否就是物件列名稱（召喚的貓是 `DEV_Void_Cat`，同一個函式；推測相同）。
- 建造模式「Pet」分類在遊戲 UI 裡的實際顯示名稱。
