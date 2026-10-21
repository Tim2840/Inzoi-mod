# 打包與發佈（P1／P2）

## 現況（2026-10-22）

| 項目 | 狀態 |
|---|---|
| `tools/make_release.py` 產生可安裝資料夾與 zip（`lua/`、`ui/`、`l10n/`、`.uplugin`、`mod_manifest.json`） | ✅ 完成，產出 70 個檔案、0.26 MB。**只驗證了檔案結構**，沒有拿這個資料夾裝進乾淨的遊戲測過 |
| 玩家說明（繁中／英文）`docs/player-guide.md` | ✅ 草稿，只寫已驗證的功能 |
| 用 ModKit 正式打包（加上 `mod_assethash.json`、版本字串） | ⏳ 需要 ModKit 編輯器開著（`inzoi-modkit` MCP 目前連不上），由 PO 開啟後我來做 |
| 發佈到 CurseForge | ⏳ **需要 PO 同意**，且要 PO 的 CurseForge 帳號登入（`modkit_cf_*` 工具會寄驗證碼到 PO 的信箱） |

## 已確認的發佈格式

從已安裝的第三方模組（`Documents\inZOI\Mods\88849\<id>\<名稱_代碼>\`）看到的格式：

```
<名稱_8碼>/
  <名稱_8碼>.uplugin     FriendlyName、Description、CreatedBy、ModCode、CfUgcId、MarketplaceURL
  mod_manifest.json      ProjectName、FriendlyName、Description、Author、Version("<遊戲版本>.MODKIT.EGS")、NonAssets
  mod_assethash.json     ModKit 打包時產生
  lua/  ui/  l10n/  non_ufs/  Content/
```

我們的 `tools/make_release.py` 產生同樣的外型，缺 `mod_assethash.json`、`ModCode`、`CfUgcId`、`MarketplaceURL`（這些由 ModKit 和 CurseForge 補上）。

## 正式發佈前要決定／處理的事

1. **模組名稱與代碼**：資料夾名稱就是 `MOD_ID`（B1／B2 用它存取模組設定檔），所以正式版的名稱要在打包**之前**定案，並用同一個名稱執行 `tools/make_release.py --name <名稱_代碼>`。目前開發版是 `PawHomeDev_A5BI7C`。
2. **移除開發版**：`Documents\inZOI\Mods\InGame\PawHomeDev_A5BI7C` 在遊戲的模組管理裡是啟用狀態，會跟著遊戲啟動載入。正式版安裝前要刪除或停用，不然兩個版本會同時存在。
3. **作者名稱**：`--author`。
4. **不放進發佈包的東西**：`tools/walk_probe`、`tools/vat_walk`（含從遊戲匯出的骨架資料）、探勘模組都留在 repo 外／不進包。發佈包只含 `lua/`、`ui/`、`l10n/`。
5. **從乾淨的遊戲測一次**：把 zip 解壓到一個沒有開發版的環境，從遊戲啟動到領養、存檔、讀檔走完一遍（**用專用的新存檔**，見 `docs/roadmap.md` 的存檔規則）。
6. **版本號**：`--version`；之後每次更新都要升版號，存檔格式變動要有 migration（已有 v1→v4）。

## 步驟（PO 開好 ModKit 之後）

1. `py -I tools/make_release.py --name <名稱_代碼> --version 1.0.0 --author <名稱>` → `dist/<名稱_代碼>/` 與 zip。
2. 在 ModKit 建立專案（`modkit_create_project`，名稱要和上一步一致），把 `lua/`、`ui/`、`l10n/` 放進專案資料夾，`modkit_validate_lua_script`、`modkit_validate_uimod` 檢查，`modkit_package` 打包。
3. 第 5 項的乾淨安裝測試。
4. **PO 同意後**才用 `modkit_cf_*` 建立 CurseForge 頁面並上傳（發佈頁文字用 `docs/player-guide.md`）。
